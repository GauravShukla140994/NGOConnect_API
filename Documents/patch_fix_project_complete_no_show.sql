-- ============================================================
-- PATCH: Fix Project_Complete SP — auto-NO_SHOW instead of auto-ATTENDED
-- Bug: Marking a project Complete was auto-marking ALL APPROVED volunteers as
--      ATTENDED, even those who never checked in (no QR or self-check-in record).
-- Fix: APPROVED volunteers WITHOUT any ProjectAttendance record → auto-NO_SHOW.
--      Volunteers who DID check in already have an ATTENDED record; step 8
--      (HoursLogged backfill) handles them — unchanged behaviour.
-- Priority: HIGH — this is a data-integrity bug (incorrect attendance records)
-- Run on: Local DB → Railway staging → production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_Complete //
CREATE PROCEDURE Project_Complete(
    IN p_ProjectId        INT UNSIGNED,
    IN p_CompletedBy      INT UNSIGNED,
    IN p_ImpactSummary    TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_CompletedStatusId  INT UNSIGNED;
    DECLARE v_ApprovedLkpId      INT UNSIGNED;
    DECLARE v_AttendedLkpId      INT UNSIGNED;
    DECLARE v_NoShowLkpId        INT UNSIGNED;
    DECLARE v_SessionId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionDate        DATE;
    DECLARE v_StartTime          TIME;
    DECLARE v_EndTime            TIME;
    DECLARE v_MaxVol             INT UNSIGNED DEFAULT 0;
    DECLARE v_SessionHours       DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_HoursLogged        DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_TypeCode           VARCHAR(50)  DEFAULT '';
    DECLARE v_RecurStart         DATE         DEFAULT NULL;
    DECLARE v_RecurEnd           DATE         DEFAULT NULL;
    DECLARE v_RecurDays          VARCHAR(50)  DEFAULT NULL;
    DECLARE v_DaysPerWeek        INT          DEFAULT 1;
    DECLARE v_Weeks              INT          DEFAULT 1;

    -- 1. Get lookup IDs
    SELECT LookupValueId INTO v_CompletedStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    SELECT LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    -- 2. Mark project COMPLETED
    UPDATE Projects
    SET    StatusLkpId    = v_CompletedStatusId,
           CompletedAt    = NOW(),
           CompletedBy    = p_CompletedBy,
           ImpactSummary  = p_ImpactSummary,
           BeneficiaryCount = p_BeneficiaryCount,
           UpdatedAt      = NOW()
    WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

    -- 3. Load project schedule info (type + times + recur details)
    SELECT
        COALESCE(ptv.ValueCode, 'ONE_TIME'),
        COALESCE(p.SessionStartTime, '09:00:00'),
        COALESCE(p.SessionEndTime,   '17:00:00'),
        p.RecurStart, p.RecurEnd, p.RecurDays,
        COALESCE(p.MaxVolunteers, 0)
    INTO v_TypeCode, v_StartTime, v_EndTime, v_RecurStart, v_RecurEnd, v_RecurDays, v_MaxVol
    FROM Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    -- 4. Find an existing past session, or auto-create one
    SELECT ps.SessionId, ps.SessionDate, ps.StartTime, ps.EndTime
    INTO   v_SessionId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions ps
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate DESC LIMIT 1;

    IF v_SessionId IS NULL THEN
        SELECT COALESCE(p.OneTimeDate, p.RecurStart, p.FlexFromDate, CURDATE())
        INTO   v_SessionDate
        FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

        INSERT INTO ProjectSessions
            (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, CreatedBy)
        VALUES
            (p_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, p_CompletedBy);

        SET v_SessionId = LAST_INSERT_ID();
    END IF;

    -- 5. Hours per session (minimum 0.5h)
    SET v_SessionHours = GREATEST(
        ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2),
        0.50
    );

    -- 6. Total hours = session_hours × occurrences (RECURRING: days/week × weeks)
    IF v_TypeCode = 'RECURRING'
       AND v_RecurStart IS NOT NULL AND v_RecurEnd IS NOT NULL
       AND v_RecurDays IS NOT NULL AND v_RecurDays <> ''
    THEN
        SET v_DaysPerWeek = LENGTH(v_RecurDays) - LENGTH(REPLACE(v_RecurDays, ',', '')) + 1;
        SET v_Weeks = GREATEST(CEIL(DATEDIFF(v_RecurEnd, v_RecurStart) / 7.0), 1);
        SET v_HoursLogged = LEAST(v_SessionHours * v_DaysPerWeek * v_Weeks, 9999.99);
    ELSE
        SET v_HoursLogged = v_SessionHours;
    END IF;

    -- 7. Auto-mark NO_SHOW for APPROVED volunteers who never checked in at all.
    --    Volunteers who already have ANY attendance record (ATTENDED via QR/self-check-in,
    --    or NO_SHOW from a prior manual marking) are skipped — do not overwrite their real status.
    --    Volunteers who DID check in (ATTENDED) are handled by step 8 (HoursLogged backfill).
    INSERT INTO ProjectAttendance
        (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, AdminNote, CreatedBy)
    SELECT
        v_SessionId,
        pa.UserId,
        NOW(),
        0.00,
        v_NoShowLkpId,
        'Auto-marked no-show on project completion — volunteer did not check in.',
        p_CompletedBy
    FROM ProjectApplications pa
    WHERE pa.ProjectId   = p_ProjectId
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND pa.IsDeleted   = 0
      AND NOT EXISTS (
          -- Skip if the volunteer has ANY attendance record for this project
          SELECT 1
          FROM   ProjectAttendance att2
          JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
          WHERE  att2.UserId   = pa.UserId
            AND  ps2.ProjectId = p_ProjectId
            AND  ps2.IsDeleted = 0
      )
    ON DUPLICATE KEY UPDATE
        AttendStatusLkpId = v_NoShowLkpId,
        HoursLogged       = 0.00,
        AdminNote         = 'Auto-marked no-show on project completion — volunteer did not check in.',
        UpdatedAt         = NOW(),
        UpdatedBy         = p_CompletedBy;

    -- 8. Backfill HoursLogged for volunteers who checked in via QR or self-check-in
    --    BEFORE project completion. They already had ATTENDED status so step 7 skipped
    --    them, leaving HoursLogged = NULL.
    --    Formula: CheckInTime (UTC stored) → LEAST(completion NOW(), session end IST→UTC).
    --    Minimum 0.50h to avoid zero-duration edge cases.
    UPDATE ProjectAttendance att
    JOIN   ProjectSessions   ps ON att.SessionId = ps.SessionId
    SET    att.HoursLogged = GREATEST(
             ROUND(
               TIMESTAMPDIFF(MINUTE, att.CheckInTime,
                 LEAST(
                   NOW(),
                   CONVERT_TZ(TIMESTAMP(ps.SessionDate, ps.EndTime), '+05:30', '+00:00')
                 )
               ) / 60.0,
             2),
             0.50)
    WHERE  ps.ProjectId          = p_ProjectId
      AND  att.HoursLogged       IS NULL
      AND  att.AttendStatusLkpId = v_AttendedLkpId
      AND  ps.IsDeleted          = 0;

    SELECT 1 AS IsSuccess, 'Project marked as completed.' AS Message;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.1-fix-project-complete-no-show',
        'Fix Project_Complete SP: APPROVED volunteers without any check-in record are now auto-marked NO_SHOW (HoursLogged=0) instead of being wrongly auto-marked ATTENDED. Volunteers who DID check in (QR/self-check-in) already have an ATTENDED record; their HoursLogged is still backfilled by step 8.',
        'System');

-- ============================================================
-- NGO Connect — Patch: HoursLogged backfill for QR / self-check-in attendance
-- Version : v5.0 patch
-- Date    : 2026-08-07
-- Scope   : Railway staging → Railway production
-- ============================================================
--
-- Problem
-- -------
-- Project_CheckIn (QR scan) and Project_SelfCheckIn both INSERT into
-- ProjectAttendance without a HoursLogged value, leaving it NULL.
-- Project_Complete skips already-ATTENDED volunteers (NOT EXISTS guard),
-- so those volunteers never get HoursLogged calculated.
-- Result: Impact screen shows "—" for hours on completed projects.
--
-- Fix (two parts)
-- ---------------
-- Part A – Updated Project_Complete SP:
--   Adds step 8 that backfills HoursLogged for already-ATTENDED rows
--   where HoursLogged IS NULL after the main INSERT in step 7.
--
-- Part B – One-time backfill UPDATE:
--   Fixes existing rows already in the DB (projects already completed
--   before this patch). Run once, idempotent (WHERE HoursLogged IS NULL).
--
-- Formula
-- -------
--   HoursLogged = GREATEST(
--     ROUND(TIMESTAMPDIFF(MINUTE,
--       CheckInTime,          -- UTC (stored as NOW() at check-in)
--       LEAST(
--         p.CompletedAt,      -- UTC (stored as NOW() at completion)
--         CONVERT_TZ(TIMESTAMP(ps.SessionDate, ps.EndTime), '+05:30', '+00:00')
--                             -- session end time IST → UTC
--       )
--     ) / 60.0, 2),
--     0.50                    -- minimum 0.50h
--   )
-- ============================================================

DELIMITER //

-- ── Part A: Updated Project_Complete ────────────────────────────────────────
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

    -- 7. Insert ATTENDED records for APPROVED volunteers not already marked ATTENDED
    INSERT INTO ProjectAttendance
        (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, AdminNote, CreatedBy)
    SELECT
        v_SessionId,
        pa.UserId,
        NOW(),
        v_HoursLogged,
        v_AttendedLkpId,
        'Auto-marked attended on project completion.',
        p_CompletedBy
    FROM ProjectApplications pa
    WHERE pa.ProjectId  = p_ProjectId
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND pa.IsDeleted   = 0
      AND NOT EXISTS (
          SELECT 1
          FROM   ProjectAttendance att2
          JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
          WHERE  att2.UserId    = pa.UserId
            AND  ps2.ProjectId  = p_ProjectId
            AND  att2.AttendStatusLkpId = v_AttendedLkpId
            AND  ps2.IsDeleted  = 0
      )
    ON DUPLICATE KEY UPDATE
        AttendStatusLkpId = v_AttendedLkpId,
        HoursLogged       = v_HoursLogged,
        AdminNote         = 'Auto-marked attended on project completion.',
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

-- ── Part B: One-time backfill for existing records ──────────────────────────
-- Fixes ProjectAttendance rows already in the DB from before this patch.
-- Safe to re-run: WHERE HoursLogged IS NULL means it's idempotent.
-- Only updates ATTENDED rows for COMPLETED projects (CompletedAt IS NOT NULL).
--
-- NOTE: SQL_SAFE_UPDATES is disabled for this statement because the UPDATE
-- uses multi-table JOINs and MySQL Workbench's safe mode requires a KEY column
-- in the WHERE of the target table. Re-enabled immediately after.

SET SQL_SAFE_UPDATES = 0;

UPDATE ProjectAttendance att
JOIN   ProjectSessions ps ON att.SessionId  = ps.SessionId
JOIN   Projects        p  ON ps.ProjectId   = p.ProjectId
JOIN   LookupValues    lv ON att.AttendStatusLkpId = lv.LookupValueId
JOIN   LookupTypes     lt ON lv.LookupTypeId       = lt.LookupTypeId
SET    att.HoursLogged = GREATEST(
         ROUND(
           TIMESTAMPDIFF(MINUTE, att.CheckInTime,
             LEAST(
               p.CompletedAt,
               CONVERT_TZ(TIMESTAMP(ps.SessionDate, ps.EndTime), '+05:30', '+00:00')
             )
           ) / 60.0,
         2),
         0.50)
WHERE  att.HoursLogged  IS NULL
  AND  lt.TypeCode      = 'ATTENDANCE_STATUS'
  AND  lv.ValueCode     = 'ATTENDED'
  AND  p.CompletedAt    IS NOT NULL
  AND  ps.IsDeleted     = 0;

SET SQL_SAFE_UPDATES = 1;

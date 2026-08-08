-- ============================================================
-- PATCH: Project_ManualAttendance — auto-create session if none exists
-- Apply to: Local DB first → Railway Staging → Railway Production
-- Generated: 2026-08-01
--
-- Problem: Project_ManualAttendance failed with "No past session found"
--   for projects where admin never created a QR session. This blocked
--   retroactive attendance marking on completed projects.
--
-- Fix: If no ProjectSession exists, create one from the project's own
--   schedule (OneTimeDate / RecurStart / FlexFromDate, SessionStartTime,
--   SessionEndTime, MaxVolunteers), then proceed with the attendance insert.
--   Admin can then individually mark APPROVED volunteers as ATTENDED
--   or NO_SHOW on the completed project's participants screen.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_ManualAttendance //

CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId        INT UNSIGNED;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_CurrentStatus VARCHAR(50);
    DECLARE v_SessionId     INT UNSIGNED;
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_HoursLogged   DECIMAL(4,2);
    DECLARE v_SessionDate   DATE;
    DECLARE v_StartTime     TIME;
    DECLARE v_EndTime       TIME;
    DECLARE v_MaxVol        INT UNSIGNED;

    SELECT pa.UserId, pa.ProjectId, sv.ValueCode
    INTO   v_UserId, v_ProjectId, v_CurrentStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0 LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;
    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;
    ELSE
        -- Find latest past session; auto-create from project schedule if none exists
        SELECT ps.SessionId,
               ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
        INTO   v_SessionId, v_HoursLogged
        FROM   ProjectSessions ps
        WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
        ORDER BY ps.SessionDate DESC LIMIT 1;

        IF v_SessionId IS NULL THEN
            -- No session exists — create one from project schedule
            SELECT
                COALESCE(p.OneTimeDate, p.RecurStart, p.FlexFromDate, CURDATE()),
                COALESCE(p.SessionStartTime, '09:00:00'),
                COALESCE(p.SessionEndTime,   '17:00:00'),
                COALESCE(p.MaxVolunteers, 0)
            INTO v_SessionDate, v_StartTime, v_EndTime, v_MaxVol
            FROM Projects p WHERE p.ProjectId = v_ProjectId;

            INSERT INTO ProjectSessions
                (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, CreatedBy)
            VALUES
                (v_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, p_MarkedBy);

            SET v_SessionId   = LAST_INSERT_ID();
            SET v_HoursLogged = GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2), 0.5);
        END IF;

        SELECT lv.LookupValueId INTO v_AttendedLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

        INSERT INTO ProjectAttendance
            (SessionId, UserId, CheckInTime, HoursLogged, QrScannedAt,
             AttendStatusLkpId, AdminNote, CreatedBy)
        VALUES
            (v_SessionId, v_UserId, NOW(), v_HoursLogged, NULL,
             v_AttendedLkpId, 'Manually marked as attended by admin.', p_MarkedBy)
        ON DUPLICATE KEY UPDATE
            AttendStatusLkpId = v_AttendedLkpId,
            CheckInTime       = NOW(),
            HoursLogged       = v_HoursLogged,
            QrScannedAt       = NULL,
            AdminNote         = 'Manually marked as attended by admin.',
            UpdatedBy         = p_MarkedBy,
            UpdatedAt         = NOW();

        SELECT 1 AS IsSuccess, 'Volunteer marked as attended.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //

DELIMITER ;

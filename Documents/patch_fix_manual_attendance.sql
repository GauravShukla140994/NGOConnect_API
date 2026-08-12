-- ── patch_fix_manual_attendance.sql ──────────────────────────────────────────
-- Bug  : "Mark Attended" button on ParticipantsScreen silently fails for
--        projects that have never had a QR session created.
--
-- Root cause (original):
--   Project_ManualAttendance auto-creates a ProjectSessions row when none
--   exists, but the INSERT omitted SessionStatusLkpId — a NOT NULL column
--   with no DEFAULT. MySQL rejects the INSERT, the SP exits without marking
--   attendance, and the mobile shows a generic "Could not mark attendance"
--   error (or no feedback at all).
--   The identical bug was fixed for Project_SelfCheckIn in a prior patch;
--   this patch applies the same fix to Project_ManualAttendance.
--
-- Additional validations added (this version):
--   1. Project state — rejects CANCELLED and EXPIRED projects immediately.
--   2. Time window — for ACTIVE/UPCOMING projects, attendance can only be
--      marked from (SessionStartTime − QR_BUFFER_MINUTES) to SessionEndTime,
--      in IST. Same window enforced by QR scan and Project_SelfCheckIn.
--      COMPLETED projects have no time restriction (admin post-session cleanup).
--
-- No table or column changes. Safe to re-run.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Project_ManualAttendance //
CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId             INT UNSIGNED;
    DECLARE v_ProjectId          INT UNSIGNED;
    DECLARE v_CurrentStatus      VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ProjectStatus      VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ScheduleTypeCode   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_SessionId          INT UNSIGNED;
    DECLARE v_AttendedLkpId      INT UNSIGNED;
    DECLARE v_SessionStatusLkpId INT UNSIGNED;
    DECLARE v_HoursLogged        DECIMAL(4,2);
    DECLARE v_SessionDate        DATE         DEFAULT NULL;
    DECLARE v_StartTime          TIME         DEFAULT NULL;
    DECLARE v_EndTime            TIME         DEFAULT NULL;
    DECLARE v_MaxVol             INT UNSIGNED DEFAULT 0;
    DECLARE v_OneTimeDate        DATE         DEFAULT NULL;
    DECLARE v_RecurStart         DATE         DEFAULT NULL;
    DECLARE v_RecurEnd           DATE         DEFAULT NULL;
    DECLARE v_RecurDays          VARCHAR(200) DEFAULT NULL;
    DECLARE v_FlexFromDate       DATE         DEFAULT NULL;
    DECLARE v_FlexToDate         DATE         DEFAULT NULL;
    DECLARE v_Buffer             INT          DEFAULT 15;
    DECLARE v_NowIST             DATETIME;
    DECLARE v_TodayIST           DATE;
    DECLARE v_WindowStart        DATETIME;
    DECLARE v_WindowEnd          DATETIME;
    DECLARE v_ValidationError    VARCHAR(300) DEFAULT NULL;

    -- Single join: application + project status + schedule fields
    SELECT pa.UserId, pa.ProjectId, appSv.ValueCode,
           projSv.ValueCode, ptv.ValueCode,
           p.SessionStartTime, p.SessionEndTime,
           p.OneTimeDate, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate,
           COALESCE(p.MaxVolunteers, 0)
    INTO   v_UserId, v_ProjectId, v_CurrentStatus,
           v_ProjectStatus, v_ScheduleTypeCode,
           v_StartTime, v_EndTime,
           v_OneTimeDate, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFromDate, v_FlexToDate,
           v_MaxVol
    FROM   ProjectApplications pa
    JOIN   Projects p            ON pa.ProjectId       = p.ProjectId
    JOIN   LookupValues appSv    ON pa.StatusLkpId     = appSv.LookupValueId
    JOIN   LookupValues projSv   ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0 LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;
    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;
    ELSE
        -- ── Project-state & time-window validation ───────────────────────────
        IF v_ProjectStatus IN ('CANCELLED', 'EXPIRED') THEN
            SET v_ValidationError = CONCAT('Cannot mark attendance: project is ', v_ProjectStatus, '.');

        ELSEIF v_ProjectStatus IN ('ACTIVE', 'UPCOMING') THEN
            -- Resolve today's session date in IST
            SET v_NowIST   = CONVERT_TZ(NOW(), '+00:00', '+05:30');
            SET v_TodayIST = DATE(v_NowIST);

            IF v_ScheduleTypeCode = 'ONE_TIME' THEN
                IF v_TodayIST = v_OneTimeDate THEN
                    SET v_SessionDate = v_OneTimeDate;
                END IF;
            ELSEIF v_ScheduleTypeCode = 'RECURRING' THEN
                IF v_TodayIST BETWEEN v_RecurStart AND v_RecurEnd
                   AND FIND_IN_SET(DAYNAME(v_TodayIST), v_RecurDays) > 0 THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;
            ELSEIF v_ScheduleTypeCode = 'FLEXIBLE' THEN
                IF v_TodayIST BETWEEN v_FlexFromDate AND v_FlexToDate THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;
            END IF;

            IF v_SessionDate IS NULL THEN
                SET v_ValidationError = 'There is no scheduled session for today.';
            ELSE
                -- Read buffer from Settings (default 15 min, same as QR)
                SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
                FROM   Settings WHERE SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;
                IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

                SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
                SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

                IF v_NowIST < v_WindowStart THEN
                    SET v_ValidationError = CONCAT('Attendance window opens at ',
                        TIME_FORMAT(TIME(v_WindowStart), '%h:%i %p'),
                        '. Please try after the session begins.');
                ELSEIF v_NowIST > v_WindowEnd THEN
                    SET v_ValidationError = CONCAT('Session ended at ',
                        TIME_FORMAT(v_EndTime, '%h:%i %p'),
                        '. The attendance window is now closed.');
                END IF;
            END IF;
        END IF;
        -- COMPLETED projects: no time restriction — v_ValidationError stays NULL

        IF v_ValidationError IS NOT NULL THEN
            SELECT 0 AS IsSuccess, v_ValidationError AS Message;
        ELSE
            -- Find latest past session; auto-create from project schedule if none exists
            SELECT ps.SessionId,
                   ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
            INTO   v_SessionId, v_HoursLogged
            FROM   ProjectSessions ps
            WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
            ORDER BY ps.SessionDate DESC LIMIT 1;

            IF v_SessionId IS NULL THEN
                -- No session exists — create one from project schedule fields already fetched
                SET v_SessionDate = COALESCE(v_OneTimeDate, v_RecurStart, v_FlexFromDate, CURDATE());
                IF v_StartTime IS NULL THEN SET v_StartTime = '09:00:00'; END IF;
                IF v_EndTime   IS NULL THEN SET v_EndTime   = '17:00:00'; END IF;

                SELECT lv.LookupValueId INTO v_SessionStatusLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

                INSERT INTO ProjectSessions
                    (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
                VALUES
                    (v_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, v_SessionStatusLkpId, p_MarkedBy);

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
    END IF;
END //

DELIMITER ;

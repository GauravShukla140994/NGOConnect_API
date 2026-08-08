-- ============================================================
-- NGO Connect — Patch: Project_SelfCheckIn
-- ============================================================
-- Purpose : Allow volunteers on OPEN_SIGNUP (no-approval) projects
--           to mark their own attendance without a QR scan.
--           Enforces the same time window as QR: from QR_BUFFER_MINUTES
--           before session start through session end (all times IST).
--
-- Validations (in order):
--   1. Project exists and is OPEN_SIGNUP
--   2. Volunteer has an APPROVED application for the project
--   3. Today is a valid session day for the schedule type
--   4. Current IST time is within [start - buffer, end]
--   5. Not already checked in for today's session
--
-- Session row: auto-created for today if none exists (same pattern
--              as Project_ManualAttendance).
--
-- Apply: run this block on Railway staging, then production.
-- No table schema changes — SP-only patch.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_SelfCheckIn //
CREATE PROCEDURE Project_SelfCheckIn(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_ScheduleTypeCode VARCHAR(20)  DEFAULT NULL;
    DECLARE v_JoinTypeCode     VARCHAR(20)  DEFAULT NULL;
    DECLARE v_StartTime        TIME         DEFAULT NULL;
    DECLARE v_EndTime          TIME         DEFAULT NULL;
    DECLARE v_OneTimeDate      DATE         DEFAULT NULL;
    DECLARE v_RecurStart       DATE         DEFAULT NULL;
    DECLARE v_RecurEnd         DATE         DEFAULT NULL;
    DECLARE v_RecurDays        VARCHAR(200) DEFAULT NULL;
    DECLARE v_FlexFromDate     DATE         DEFAULT NULL;
    DECLARE v_FlexToDate       DATE         DEFAULT NULL;
    DECLARE v_HasApproval      INT          DEFAULT 0;
    DECLARE v_IsCheckedIn      INT          DEFAULT 0;
    DECLARE v_Buffer           INT          DEFAULT 15;
    DECLARE v_NowIST           DATETIME;
    DECLARE v_TodayIST         DATE;
    DECLARE v_SessionDate      DATE         DEFAULT NULL;
    DECLARE v_WindowStart      DATETIME;
    DECLARE v_WindowEnd        DATETIME;
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_AttendedLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId      INT UNSIGNED DEFAULT NULL;

    -- Fetch project schedule + join type
    SELECT ptv.ValueCode, jtv.ValueCode,
           p.SessionStartTime, p.SessionEndTime,
           p.OneTimeDate, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate
    INTO   v_ScheduleTypeCode, v_JoinTypeCode,
           v_StartTime, v_EndTime,
           v_OneTimeDate, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFromDate, v_FlexToDate
    FROM   Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0
    LIMIT  1;

    IF v_ScheduleTypeCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message, NULL AS SessionId;

    ELSEIF v_JoinTypeCode != 'OPEN_SIGNUP' THEN
        SELECT 0 AS IsSuccess, 'This project requires a QR scan for attendance.' AS Message, NULL AS SessionId;

    ELSE
        -- Verify APPROVED application
        SELECT COUNT(*) INTO v_HasApproval
        FROM   ProjectApplications pa
        JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId
          AND  lv.ValueCode = 'APPROVED' AND pa.IsDeleted = 0;

        IF v_HasApproval = 0 THEN
            SELECT 0 AS IsSuccess, 'You are not registered for this project.' AS Message, NULL AS SessionId;

        ELSE
            SET v_NowIST   = CONVERT_TZ(NOW(), '+00:00', '+05:30');
            SET v_TodayIST = DATE(v_NowIST);

            -- Determine effective session date for today
            IF v_ScheduleTypeCode = 'ONE_TIME' THEN
                SET v_SessionDate = v_OneTimeDate;

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
                SELECT 0 AS IsSuccess,
                       'There is no scheduled session for today.' AS Message,
                       NULL AS SessionId;

            ELSE
                -- Read buffer from Settings (default 15 min, same as QR)
                SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
                FROM   Settings
                WHERE  SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0
                LIMIT  1;
                IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

                -- Time window: [sessionStart - buffer, sessionEnd] in IST
                SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
                SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

                IF v_NowIST < v_WindowStart THEN
                    SELECT 0 AS IsSuccess,
                           CONCAT('Check-in opens at ',
                                  TIME_FORMAT(TIME(v_WindowStart), '%h:%i %p'),
                                  '. Please return when the session is about to start.') AS Message,
                           NULL AS SessionId;

                ELSEIF v_NowIST > v_WindowEnd THEN
                    SELECT 0 AS IsSuccess,
                           CONCAT('Session ended at ',
                                  TIME_FORMAT(v_EndTime, '%h:%i %p'),
                                  '. Check-in is no longer available.') AS Message,
                           NULL AS SessionId;

                ELSE
                    -- Find or create session row for today
                    SELECT SessionId INTO v_SessionId
                    FROM   ProjectSessions
                    WHERE  ProjectId = p_ProjectId AND SessionDate = v_SessionDate AND IsDeleted = 0
                    LIMIT  1;

                    IF v_SessionId IS NULL THEN
                        SELECT LookupValueId INTO v_StatusLkpId
                        FROM   LookupValues lv
                        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                        WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING'
                        LIMIT  1;

                        INSERT INTO ProjectSessions
                               (ProjectId, SessionDate, StartTime, EndTime, SessionStatusLkpId, CreatedBy)
                        VALUES (p_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_StatusLkpId, p_UserId);
                        SET v_SessionId = LAST_INSERT_ID();
                    END IF;

                    -- Already checked in?
                    SELECT COUNT(*) INTO v_IsCheckedIn
                    FROM   ProjectAttendance
                    WHERE  SessionId = v_SessionId AND UserId = p_UserId;

                    IF v_IsCheckedIn > 0 THEN
                        SELECT 0 AS IsSuccess,
                               'You have already marked your attendance for this session.' AS Message,
                               v_SessionId AS SessionId;

                    ELSE
                        SELECT LookupValueId INTO v_AttendedLkpId
                        FROM   LookupValues lv
                        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                        WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                        LIMIT  1;

                        INSERT INTO ProjectAttendance
                               (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
                        VALUES (v_SessionId, p_UserId, NOW(), v_AttendedLkpId, p_UserId);

                        SELECT 1 AS IsSuccess,
                               'Attendance marked successfully! Thank you for being there.' AS Message,
                               v_SessionId AS SessionId;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;
END //

DELIMITER ;

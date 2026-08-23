-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_recurring_days.sql
-- Fixes RECURRING day-of-week matching in Project_SelfCheckIn and
-- Project_ManualAttendance.
--
-- Bug (SP — fixed here):
--   Both SPs used DAYNAME() which returns full names ("Monday", "Tuesday").
--   Stored format is 3-letter abbreviations: "MON,TUE,WED".
--   FIND_IN_SET('Monday', 'MON,TUE,WED') always returns 0 → "no session today".
--   Fix: LEFT(UPPER(DAYNAME(...)), 3) → matches stored "MON","TUE" etc.
--
-- ONE_TIME and FLEXIBLE branches are untouched.
-- Apply to Railway staging and production after local verification.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── Project_SelfCheckIn ──────────────────────────────────────────────────────
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
                -- FIX: use LEFT(UPPER(DAYNAME(...)),3) to match stored "MON","TUE" format
                IF v_TodayIST BETWEEN v_RecurStart AND v_RecurEnd
                   AND FIND_IN_SET(LEFT(UPPER(DAYNAME(v_TodayIST)), 3),
                                   UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
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
                -- Read buffer from Settings (default 15 min)
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

-- ── Project_ManualAttendance — RECURRING day-fix only ─────────────────────────
-- NOTE: Only the RECURRING FIND_IN_SET line changes; all other logic is identical
-- to the version in setup SQL. Run validate_sp_params.py after applying.
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
        IF v_ProjectStatus IN ('CANCELLED', 'EXPIRED') THEN
            SET v_ValidationError = CONCAT('Cannot mark attendance: project is ', v_ProjectStatus, '.');

        ELSEIF v_ProjectStatus IN ('ACTIVE', 'UPCOMING', 'CLOSING') THEN
            SET v_NowIST   = CONVERT_TZ(NOW(), '+00:00', '+05:30');
            SET v_TodayIST = DATE(v_NowIST);

            IF v_ScheduleTypeCode = 'ONE_TIME' THEN
                IF v_TodayIST = v_OneTimeDate THEN
                    SET v_SessionDate = v_OneTimeDate;
                END IF;
            ELSEIF v_ScheduleTypeCode = 'RECURRING' THEN
                -- FIX: use LEFT(UPPER(DAYNAME(...)),3) to match stored "MON","TUE" format
                IF v_TodayIST BETWEEN v_RecurStart AND v_RecurEnd
                   AND FIND_IN_SET(LEFT(UPPER(DAYNAME(v_TodayIST)), 3),
                                   UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
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
        -- COMPLETED projects: no time restriction

        IF v_ValidationError IS NOT NULL THEN
            SELECT 0 AS IsSuccess, v_ValidationError AS Message;
        ELSE
            SELECT ps.SessionId,
                   ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
            INTO   v_SessionId, v_HoursLogged
            FROM   ProjectSessions ps
            WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
            ORDER BY ps.SessionDate DESC LIMIT 1;

            IF v_SessionId IS NULL THEN
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

            UPDATE ProjectApplications
            SET    StatusLkpId = v_AttendedLkpId, UpdatedAt = NOW(), UpdatedBy = p_MarkedBy
            WHERE  ApplicationId = p_ApplicationId;

            INSERT INTO ProjectAttendance
                   (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, CreatedBy)
            VALUES (v_SessionId, v_UserId, NOW(), v_HoursLogged, v_AttendedLkpId, p_MarkedBy)
            ON DUPLICATE KEY UPDATE
                   HoursLogged = v_HoursLogged, AttendStatusLkpId = v_AttendedLkpId,
                   CheckInTime = NOW(), UpdatedAt = NOW();

            SELECT 1 AS IsSuccess, 'Attendance marked successfully.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

-- Verify
SELECT 'patch_fix_recurring_days applied successfully.' AS Status;

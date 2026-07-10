-- ============================================================
-- NGO Connect — Patch: QR Time Window + Manual Attendance
-- Version : v4.3 patch
-- Date    : 2026-07-09
-- Changes :
--   1. Settings seed: QR_EXPIRY_MINUTES (60) + QR_BUFFER_MINUTES (15)
--   2. Project_GetSessionQr: enforce time-window check
--        - QR active from (SessionStartTime - QR_BUFFER_MINUTES)
--        - QR inactive after SessionEndTime
--        - Descriptive error messages returned on both edges
--   3. Application_GetByProject: join ProjectAttendance to return
--        effective attendance status (ATTENDED / NO_SHOW / EXCUSED)
--        when a record exists, otherwise falls back to application status
--   4. Project_ManualAttendance: new SP for admin to manually mark
--        a volunteer as ATTENDED (overrides APPROVED or NO_SHOW)
--   5. Project_AddSession: guard against duplicate sessions for same date
--        (returns IsSuccess=0 if a session already exists for that date)
--   6. Project_GetSessions: return SessionDate as plain 'YYYY-MM-DD' string
--        using DATE_FORMAT to avoid DateTime serialization ambiguity across
--        timezones when Oracle MySql.Data fills a DataSet
-- Apply   : Run against NGOConnect database.
-- ============================================================

USE ngoconnect;

-- ─── 1. Settings ─────────────────────────────────────────────────────────────
-- INSERT IGNORE — safe to run multiple times; won't duplicate if already seeded.

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
('PROJECT', 'QR_EXPIRY_MINUTES',  '60', 'NUMBER',
    'QR code validity window in minutes after generation. Volunteers must scan within this time.', 0),
('PROJECT', 'QR_BUFFER_MINUTES',  '15', 'NUMBER',
    'Minutes BEFORE session start that the admin can generate a QR. Allows early arrivals to scan.', 0);

-- ─── 2. Project_GetSessionQr — time-window enforcement ───────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetSessionQr //
CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_QrCode      VARCHAR(100);
    DECLARE v_ProjectId   INT UNSIGNED;
    DECLARE v_SessionDate DATE;
    DECLARE v_StartTime   TIME;
    DECLARE v_EndTime     TIME;
    DECLARE v_Expiry      INT DEFAULT 60;
    DECLARE v_Buffer      INT DEFAULT 15;
    DECLARE v_WindowStart DATETIME;
    DECLARE v_WindowEnd   DATETIME;
    DECLARE v_RowsHit     INT DEFAULT 0;

    -- Load session details
    SELECT ProjectId, SessionDate, StartTime, EndTime
    INTO   v_ProjectId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions
    WHERE  SessionId = p_SessionId AND IsDeleted = 0
    LIMIT 1;

    -- Session must exist
    IF v_SessionDate IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found or already deleted.' AS Message, NULL AS QrToken;

    ELSE
        -- Load configurable minutes from Settings (safe defaults if not seeded)
        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Expiry
        FROM Settings WHERE SettingKey = 'QR_EXPIRY_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Expiry IS NULL OR v_Expiry = 0 THEN SET v_Expiry = 60; END IF;

        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
        FROM Settings WHERE SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

        -- Compute the valid window
        SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
        SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

        -- Too early
        IF NOW() < v_WindowStart THEN
            SELECT 0 AS IsSuccess,
                   CONCAT(
                       'QR not yet available. Session starts at ',
                       TIME_FORMAT(v_StartTime, '%h:%i %p'),
                       '. QR opens ', v_Buffer, ' min before start.'
                   ) AS Message,
                   NULL AS QrToken;

        -- Session over
        ELSEIF NOW() > v_WindowEnd THEN
            SELECT 0 AS IsSuccess,
                   CONCAT(
                       'Session ended at ',
                       TIME_FORMAT(v_EndTime, '%h:%i %p'),
                       '. QR is no longer active.'
                   ) AS Message,
                   NULL AS QrToken;

        -- In window — generate
        ELSE
            SET v_QrCode = REPLACE(UUID(), '-', '');

            UPDATE ProjectSessions
            SET    QrCode      = v_QrCode,
                   QrExpiresAt = DATE_ADD(NOW(), INTERVAL v_Expiry MINUTE),
                   UpdatedBy   = p_UserId,
                   UpdatedAt   = NOW()
            WHERE  SessionId = p_SessionId AND IsDeleted = 0;

            SET v_RowsHit = ROW_COUNT();

            IF v_RowsHit = 0 THEN
                SELECT 0 AS IsSuccess, 'Failed to stamp QR on session.' AS Message, NULL AS QrToken;
            ELSE
                SELECT 1 AS IsSuccess, 'QR generated.' AS Message, v_QrCode AS QrToken;
            END IF;
        END IF;
    END IF;
END //

-- ─── 3. Application_GetByProject — join attendance status ────────────────────
-- BEFORE: only returned APPLICATION_STATUS values (PENDING, APPROVED, REJECTED, WITHDRAWN)
-- AFTER : also joins ProjectAttendance; returns ATTENDED / NO_SHOW / EXCUSED
--         when an attendance record exists for the user in the latest session.

DROP PROCEDURE IF EXISTS Application_GetByProject //
CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_FilterLkpId INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    -- Resolve filter: check APPLICATION_STATUS first, then ATTENDANCE_STATUS
    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_FilterLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode
        LIMIT 1;

        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode
            LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId,
        pa.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)         AS ApplicantName,
        up.ProfilePhoto,
        up.City,
        up.Occupation                                  AS Profession,
        pa.Motivation,
        pa.RequestedSessions,
        -- Effective status: attendance status takes precedence over application status
        COALESCE(attSv.ValueCode, appSv.ValueCode)     AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName)     AS Status,
        pa.StatusUpdatedAt,
        pa.CreatedAt,
        -- Attendance detail fields (null when no attendance record exists)
        att.CheckInTime                                AS CheckedInAt,
        att.HoursLogged,
        att.IsNoShowExcused                            AS IsExcused,
        att.QrScannedAt,
        att.AdminNote,
        -- Session context (for display in ParticipantsScreen)
        ps.SessionDate,
        ps.StartTime                                   AS SessionStartTime,
        ps.EndTime                                     AS SessionEndTime
    FROM   ProjectApplications pa
    JOIN   UserProfiles up ON pa.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    -- Latest attendance record for this user across all sessions of this project
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT  att2.AttendanceId
        FROM    ProjectAttendance att2
        JOIN    ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE   att2.UserId    = pa.UserId
          AND   ps2.ProjectId  = pa.ProjectId
          AND   ps2.IsDeleted  = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT 1
    )
    LEFT JOIN LookupValues attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps ON ps.SessionId = att.SessionId
    WHERE  pa.ProjectId  = p_ProjectId
      AND  pa.IsDeleted  = 0
      AND  (
           v_FilterLkpId IS NULL
        OR pa.StatusLkpId          = v_FilterLkpId
        OR att.AttendStatusLkpId   = v_FilterLkpId
      )
    ORDER BY pa.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- Total count (same filter logic)
    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications pa
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT  att2.AttendanceId
        FROM    ProjectAttendance att2
        JOIN    ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE   att2.UserId    = pa.UserId
          AND   ps2.ProjectId  = pa.ProjectId
          AND   ps2.IsDeleted  = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT 1
    )
    WHERE  pa.ProjectId  = p_ProjectId
      AND  pa.IsDeleted  = 0
      AND  (
           v_FilterLkpId IS NULL
        OR pa.StatusLkpId          = v_FilterLkpId
        OR att.AttendStatusLkpId   = v_FilterLkpId
      );
END //

-- ─── 4. Project_ManualAttendance — admin marks a volunteer as attended ────────

DROP PROCEDURE IF EXISTS Project_ManualAttendance //
CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId           INT UNSIGNED;
    DECLARE v_ProjectId        INT UNSIGNED;
    DECLARE v_CurrentStatus    VARCHAR(50);
    DECLARE v_SessionId        INT UNSIGNED;
    DECLARE v_AttendedLkpId    INT UNSIGNED;
    DECLARE v_HoursLogged      DECIMAL(4,2);

    -- Get applicant and project
    SELECT pa.UserId, pa.ProjectId, sv.ValueCode
    INTO   v_UserId, v_ProjectId, v_CurrentStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0
    LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;

    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        -- ATTENDED: already done; PENDING/REJECTED: wrong state
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;

    ELSE
        -- Latest session (past or today) for this project
        SELECT  ps.SessionId,
                ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
        INTO    v_SessionId, v_HoursLogged
        FROM    ProjectSessions ps
        WHERE   ps.ProjectId  = v_ProjectId
          AND   ps.SessionDate <= CURDATE()
          AND   ps.IsDeleted   = 0
        ORDER BY ps.SessionDate DESC
        LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No past session found for this project.' AS Message;

        ELSE
            -- Look up ATTENDED status in ATTENDANCE_STATUS
            SELECT lv.LookupValueId INTO v_AttendedLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
            LIMIT 1;

            -- Insert or update attendance record
            -- QrScannedAt = NULL marks this as a manual (non-QR) entry
            INSERT INTO ProjectAttendance
                (SessionId, UserId, CheckInTime, HoursLogged, QrScannedAt,
                 AttendStatusLkpId, AdminNote, CreatedBy)
            VALUES
                (v_SessionId, v_UserId, NOW(), v_HoursLogged, NULL,
                 v_AttendedLkpId,
                 'Manually marked as attended by admin.',
                 p_MarkedBy)
            ON DUPLICATE KEY UPDATE
                AttendStatusLkpId = v_AttendedLkpId,
                CheckInTime       = NOW(),
                HoursLogged       = v_HoursLogged,
                QrScannedAt       = NULL,
                AdminNote         = 'Manually marked as attended by admin.',
                UpdatedBy         = p_MarkedBy,
                UpdatedAt         = NOW();

            SELECT 1 AS IsSuccess,
                   'Volunteer marked as attended.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

-- ─── 5. Project_AddSession — duplicate guard ─────────────────────────────────
-- Prevents an admin from creating two sessions for the same project on the same date.
-- Returns IsSuccess=0 with a descriptive message if a session already exists.

DELIMITER //

DROP PROCEDURE IF EXISTS Project_AddSession //

CREATE PROCEDURE Project_AddSession(
    IN p_ProjectId    INT UNSIGNED,
    IN p_SessionDate  DATE,
    IN p_StartTime    TIME,
    IN p_EndTime      TIME,
    IN p_MaxVolunteers INT UNSIGNED,
    IN p_CreatedBy    INT UNSIGNED
)
BEGIN
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_ExistingId   INT UNSIGNED DEFAULT NULL;

    -- Guard: block duplicate session for same project + date
    SELECT SessionId INTO v_ExistingId
    FROM ProjectSessions
    WHERE ProjectId = p_ProjectId
      AND SessionDate = p_SessionDate
      AND IsDeleted = 0
    LIMIT 1;

    IF v_ExistingId IS NOT NULL THEN
        SELECT 0 AS IsSuccess,
               'A session already exists for this date.' AS Message,
               v_ExistingId AS SessionId;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING'
        LIMIT 1;

        INSERT INTO ProjectSessions
            (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
        VALUES
            (p_ProjectId, p_SessionDate, p_StartTime, p_EndTime, p_MaxVolunteers, v_StatusLkpId, p_CreatedBy);

        SELECT 1 AS IsSuccess, 'Session added.' AS Message, LAST_INSERT_ID() AS SessionId;
    END IF;
END //

DELIMITER ;

-- ─── 6. Project_GetSessions — plain date string ──────────────────────────────
-- DATE_FORMAT forces SessionDate to be returned as 'YYYY-MM-DD' (plain string).
-- This prevents Oracle MySql.Data DateTime serialization ambiguity where
-- the .NET DateTime kind (Local/Unspecified) could shift the date in certain
-- timezones when System.Text.Json serializes it.

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetSessions //

CREATE PROCEDURE Project_GetSessions(
    IN p_ProjectId  INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        ps.SessionId,
        DATE_FORMAT(ps.SessionDate, '%Y-%m-%d') AS SessionDate,
        ps.StartTime,
        ps.EndTime,
        ps.MaxVolunteers,
        sv.ValueCode AS StatusCode,
        sv.ValueName AS Status,
        ps.QrCode,
        ps.QrExpiresAt
    FROM ProjectSessions ps
    LEFT JOIN LookupValues sv ON ps.SessionStatusLkpId = sv.LookupValueId
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER BY ps.SessionDate ASC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM ProjectSessions
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;
END //

DELIMITER ;

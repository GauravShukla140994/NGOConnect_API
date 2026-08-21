-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_excuse_noshow.sql
-- 1. Application_GetByProject — add att.AttendanceId to SELECT
-- 2. Attendance_ExcuseNoShow  — remove p_OrgId param; set IsNoShowExcused = 1
-- Run on: local → Railway staging → Railway production
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── 1. Application_GetByProject ──────────────────────────────────────────────
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

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_FilterLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        -- Also try ATTENDANCE_STATUS (ATTENDED, NO_SHOW)
        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId,
        pa.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)     AS ApplicantName,
        up.ProfilePhoto,
        up.City,
        up.Occupation                               AS Profession,
        pa.Motivation,
        pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode)  AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName)  AS Status,
        pa.StatusUpdatedAt,
        pa.CreatedAt,
        -- Check-in time converted to IST (Railway MySQL server = UTC)
        DATE_FORMAT(CONVERT_TZ(att.CheckInTime, '+00:00', '+05:30'), '%Y-%m-%dT%H:%i:%s') AS CheckedInAt,
        att.AttendanceId,
        att.HoursLogged,
        att.IsNoShowExcused                         AS IsExcused,
        att.QrScannedAt,
        att.AdminNote,
        ps.SessionDate,
        ps.StartTime   AS SessionStartTime,
        ps.EndTime     AS SessionEndTime,
        -- Badges already awarded to this volunteer on this project (comma-separated ValueCodes)
        (SELECT GROUP_CONCAT(lv2.ValueCode ORDER BY ub.CreatedAt SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv2 ON ub.BadgeLkpId = lv2.LookupValueId
         WHERE  ub.UserId     = pa.UserId
           AND  ub.ProjectId  = pa.ProjectId
           AND  ub.IsDeleted  = 0
        )                                           AS AwardedBadgeCodes,
        -- Whether a certificate has already been issued for this volunteer on this project
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc2
                  WHERE vc2.ProjectId = pa.ProjectId
                    AND vc2.UserId    = pa.UserId
                    AND vc2.IsDeleted = 0), 1, 0)   AS HasCertificate
    FROM   ProjectApplications pa
    JOIN   UserProfiles up   ON pa.UserId        = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    -- Most-recent attendance record for this user on this project
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    LEFT JOIN LookupValues   attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps   ON ps.SessionId          = att.SessionId
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           )
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications
    WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;
END //

-- ── 2. Attendance_ExcuseNoShow ────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Attendance_ExcuseNoShow //
CREATE PROCEDURE Attendance_ExcuseNoShow(
    IN p_AttendanceId INT,
    IN p_ExcusedBy    INT
)
BEGIN
    DECLARE v_UserId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectId INT UNSIGNED DEFAULT NULL;

    SELECT pa.UserId, ps.ProjectId
    INTO   v_UserId, v_ProjectId
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.AttendanceId = p_AttendanceId
    LIMIT  1;

    UPDATE ProjectAttendance pa
    SET pa.AttendanceStatus = 'EXCUSED',
        pa.IsNoShowExcused  = 1,
        pa.UpdatedAt        = NOW()
    WHERE pa.AttendanceId      = p_AttendanceId
      AND pa.AttendanceStatus  = 'NO_SHOW';

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or already not a no-show.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show excused. Reliability score will not be affected.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //

DELIMITER ;

-- ── Patch: Badge Award Fixes (2026-08-01) ────────────────────────────────────
--
-- Fix 1 · UserBadge_Award
--   Added:  Duplicate guard — prevents double-awarding same badge on same project
--   Added:  BadgeName in result set — used by OrgDal to send personalised FCM push
--   Added:  UserId in result set — for OrgDal notification helper
--
-- Fix 2 · Application_GetByProject
--   Added:  AwardedBadgeCodes — comma-separated ValueCodes of badges already awarded
--           to each volunteer for this project (so admin screen pre-highlights buttons)
--   Merged: CheckedInAt (IST ISO datetime), Profession, StatusUpdatedAt, HoursLogged,
--           IsExcused, QrScannedAt, SessionDate, SessionStartTime, SessionEndTime
--           (previously in NGOConnect_Patch_QR_Attendance_Fixes.sql)
--
-- Apply to: Railway staging → Railway production
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

-- ── Fix 1: UserBadge_Award ───────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS UserBadge_Award //
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId     INT UNSIGNED,
    IN p_BadgeLkpId INT UNSIGNED,
    IN p_AwardedBy  INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,
    IN p_ProjectId  INT UNSIGNED
)
BEGIN
    DECLARE v_BadgeName VARCHAR(100) DEFAULT 'Badge';
    DECLARE v_Exists    INT DEFAULT 0;

    -- Prevent double-awarding the same badge on the same project
    SELECT COUNT(*) INTO v_Exists
    FROM   UserBadges
    WHERE  UserId      = p_UserId
      AND  BadgeLkpId  = p_BadgeLkpId
      AND  (p_ProjectId IS NULL OR ProjectId = p_ProjectId)
      AND  IsDeleted   = 0;

    IF v_Exists > 0 THEN
        SELECT 0    AS IsSuccess,
               'This badge has already been awarded to this volunteer.' AS Message,
               NULL AS BadgeId,
               NULL AS BadgeName,
               NULL AS UserId;
    ELSE
        SELECT ValueName INTO v_BadgeName
        FROM   LookupValues WHERE LookupValueId = p_BadgeLkpId LIMIT 1;

        INSERT INTO UserBadges
            (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
        VALUES
            (p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());

        SELECT 1                   AS IsSuccess,
               'Badge awarded successfully.' AS Message,
               LAST_INSERT_ID()   AS BadgeId,
               v_BadgeName        AS BadgeName,
               p_UserId           AS UserId;
    END IF;
END //


-- ── Fix 2: Application_GetByProject ─────────────────────────────────────────

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
        )                                           AS AwardedBadgeCodes
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

DELIMITER ;

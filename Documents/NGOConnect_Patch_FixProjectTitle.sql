-- ============================================================
-- NGOConnect — Patch: Fix p.Title → p.ProjectName
-- Affected SPs: Certificate_GetByUser, User_GetBadges,
--               Application_GetByUser, Project_List
-- Root cause: Projects table column is ProjectName, not Title
-- Run this on Railway staging (and any env where v4.4 was applied)
-- ============================================================

USE ngoconnect;
DELIMITER //

-- ── 1. Certificate_GetByUser ─────────────────────────────────
DROP PROCEDURE IF EXISTS Certificate_GetByUser //
CREATE PROCEDURE Certificate_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT vc.CertificateId, vc.ProjectId, p.ProjectName AS ProjectTitle,
           vc.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
           vc.CertificateUrl, vc.IssuedAt, vc.TotalHours
    FROM VolunteerCertificates vc
    JOIN Projects p ON vc.ProjectId = p.ProjectId
    JOIN Organisations o ON vc.OrgId = o.OrgId
    WHERE vc.UserId = p_UserId AND vc.IsDeleted = 0
    ORDER BY vc.IssuedAt DESC;
END //

-- ── 2. User_GetBadges ────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetBadges //
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        ub.BadgeLkpId,
        lv.ValueName AS BadgeName,
        lv.ValueCode AS BadgeCode,
        o.OrgName,
        p.ProjectName,
        ub.AwardedAt
    FROM UserBadges ub
    JOIN LookupValues lv  ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId = p.ProjectId
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;
END //

-- ── 3. Application_GetByUser ─────────────────────────────────
DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        appSv.ValueCode  AS StatusCode,
        appSv.ValueName  AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        p.ScheduleType   AS ScheduleTypeCode,
        p.ScheduleType   AS ScheduleTypeName,
        p.StartDate      AS RecurStart,
        p.EndDate        AS RecurEnd,
        p.RecurrenceDays AS RecurDays,
        p.StartTime      AS SessionStartTime,
        p.EndTime        AS SessionEndTime,
        p.LocationName   AS Landmark,
        p.City,
        projSv.ValueCode AS ProjectStatusCode,
        projSv.ValueName AS ProjectStatus
    FROM   ProjectApplications pa
    JOIN   Projects     p    ON pa.ProjectId  = p.ProjectId
    JOIN   Organisations o   ON p.OrgId       = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId  = projSv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //

-- ── 4. Project_List ──────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7)
)
BEGIN
    DECLARE v_Offset       INT;
    DECLARE v_StatusLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId    INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    END IF;

    IF p_TypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_TypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode LIMIT 1;
    END IF;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl    AS OrgLogoUrl,
        p.ProjectName,
        p.Description,
        ptv.ValueCode AS ScheduleType,
        p.LocationName,
        p.Address,
        p.City,
        p.State,
        p.StartDate,
        p.EndDate,
        p.StartTime,
        p.EndTime,
        p.MaxVolunteers,
        p.CoverImageUrl,
        p.Latitude,
        p.Longitude,
        sv.ValueCode AS StatusCode,
        sv.ValueName AS Status,
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId AND pa2.IsDeleted = 0
           AND lv2.ValueCode = 'APPROVED') AS ApprovedCount,
        p.CreatedAt,
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN ROUND(
                6371 * ACOS(
                    LEAST(1.0, COS(RADIANS(p_UserLat))
                    * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat))
                    * SIN(RADIANS(p.Latitude)))
                ), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o ON p.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues sv  ON p.StatusLkpId      = sv.LookupValueId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.IsDeleted  = 0
      AND  p.IsPublic   = 1
      AND  (p_OrgId     IS NULL OR p.OrgId        = p_OrgId)
      AND  (p_Category  IS NULL OR p.Category     = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City      IS NULL OR p.City         LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY
        CASE WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL THEN
            CASE WHEN p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL THEN
                6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))))
            ELSE 999999 END
        ELSE NULL END ASC,
        p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    LEFT JOIN LookupValues sv  ON p.StatusLkpId      = sv.LookupValueId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.IsDeleted = 0 AND p.IsPublic = 1
      AND  (p_OrgId     IS NULL OR p.OrgId        = p_OrgId)
      AND  (p_Category  IS NULL OR p.Category     = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City      IS NULL OR p.City         LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //

DELIMITER ;

-- Verify
SELECT 'Patch applied: 4 SPs fixed (Certificate_GetByUser, User_GetBadges, Application_GetByUser, Project_List)' AS Result;

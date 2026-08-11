-- ── patch_fix_applied_status.sql ─────────────────────────────────────────────
-- Feature : All Opportunities screen — show "Applied ✓" button for projects
--           the logged-in volunteer has already applied to.
--
-- Root cause: Project_List SP had no p_UserId parameter and returned no
--             ApplicationStatusCode, so the mobile screen could not distinguish
--             already-applied projects from new ones.
--
-- Change (1 SP):
--   Project_List : added IN p_UserId INT UNSIGNED (nullable — pass NULL for
--                  anonymous / unauthenticated requests).
--                  Added ApplicationStatusCode correlated subquery to SELECT
--                  (CASE guards against anonymous: returns NULL when p_UserId
--                  IS NULL or 0, so no extra cost for public browse).
--
-- No table or column changes. Safe to re-run.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Project_List //

CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_Keyword    VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7),
    IN p_UserId     INT UNSIGNED
)
BEGIN
    DECLARE v_Offset             INT;
    DECLARE v_StatusLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_UpcomingLkpId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedOrgLkpId   INT UNSIGNED DEFAULT NULL;

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

    -- Resolve ACTIVE + UPCOMING LkpIds for public volunteer browse whitelist
    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    -- Resolve APPROVED org status — public browse must exclude suspended/inactive orgs
    SELECT lv.LookupValueId INTO v_ApprovedOrgLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl    AS OrgLogoUrl,
        p.ProjectName,
        p.Category,
        ptv.ValueCode    AS ScheduleType,
        ptv.ValueCode    AS ProjectTypeCode,
        ptv.ValueName    AS ProjectType,
        ltv.ValueCode    AS LocationTypeCode,
        ltv.ValueName    AS LocationType,
        p.Landmark       AS LocationName,
        p.AddressLine    AS Address,
        sv.ValueCode     AS StatusCode,
        sv.ValueName     AS Status,
        p.City,
        p.State,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.IsPublic,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.MinHoursRequired,
        p.CancelReason,
        p.CancelledAt,
        p.ImpactSummary,
        p.BeneficiaryCount,
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv ON pa2.StatusLkpId = alv.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv.ValueCode = 'APPROVED'
           AND pa2.IsDeleted = 0) AS ApprovedCount,
        -- ApplicationStatusCode: non-null only when p_UserId provided and user has applied
        CASE WHEN p_UserId IS NOT NULL AND p_UserId > 0 THEN
            (SELECT lv2.ValueCode FROM ProjectApplications pa3
             JOIN LookupValues lv2 ON pa3.StatusLkpId = lv2.LookupValueId
             WHERE pa3.ProjectId = p.ProjectId AND pa3.UserId = p_UserId AND pa3.IsDeleted = 0
             LIMIT 1)
        ELSE NULL END AS ApplicationStatusCode,
        p.CreatedAt,
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
            )), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o       ON p.OrgId             = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv   ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv    ON p.StatusLkpId       = sv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      AND  (p_Keyword     IS NULL
            OR p.ProjectName  LIKE CONCAT('%', p_Keyword, '%')
            OR p.Description  LIKE CONCAT('%', p_Keyword, '%')
            OR o.OrgName      LIKE CONCAT('%', p_Keyword, '%')
            OR p.City         LIKE CONCAT('%', p_Keyword, '%')
            OR p.State        LIKE CONCAT('%', p_Keyword, '%')
            OR p.Landmark     LIKE CONCAT('%', p_Keyword, '%')
            OR p.AddressLine  LIKE CONCAT('%', p_Keyword, '%'))
      -- Public volunteer browse: only ACTIVE + UPCOMING (admin with p_OrgId sees all)
      AND  (p_OrgId IS NOT NULL OR p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId))
      -- Public volunteer browse: only projects from APPROVED organisations
      AND  (p_OrgId IS NOT NULL OR o.StatusLkpId = v_ApprovedOrgLkpId)
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

    -- TotalCount — same JOINs and WHERE as main SELECT
    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    JOIN   Organisations o       ON p.OrgId             = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues sv    ON p.StatusLkpId       = sv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      AND  (p_Keyword     IS NULL
            OR p.ProjectName  LIKE CONCAT('%', p_Keyword, '%')
            OR p.Description  LIKE CONCAT('%', p_Keyword, '%')
            OR o.OrgName      LIKE CONCAT('%', p_Keyword, '%')
            OR p.City         LIKE CONCAT('%', p_Keyword, '%')
            OR p.State        LIKE CONCAT('%', p_Keyword, '%')
            OR p.Landmark     LIKE CONCAT('%', p_Keyword, '%')
            OR p.AddressLine  LIKE CONCAT('%', p_Keyword, '%'))
      AND  (p_OrgId IS NOT NULL OR p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId))
      AND  (p_OrgId IS NOT NULL OR o.StatusLkpId = v_ApprovedOrgLkpId);
END //

DELIMITER ;

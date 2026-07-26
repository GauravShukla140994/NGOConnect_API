-- ============================================================
-- NGO Connect — Patch: Nearby ordering + All Opportunities fixes
-- Date: 2026-07-24
-- Changes:
--   1. Project_List SP
--      - Added p_Keyword (search on ProjectName + Description)
--      - Public volunteer browse now restricted to ACTIVE + UPCOMING only
--        (replaces EXPIRED blacklist — also hides DRAFT/CANCELLED/COMPLETED)
--      - TotalCount query now has same JOINs as main SELECT (was missing org JOIN)
--      - Removed incorrect ptv.ValueCode fallback in p_Category filter
--   2. Project_GetNearbyFeed SP
--      - ORDER BY changed from band+relevance to pure distance (nearest first)
--      - RelevanceScore removed from SELECT (was driving ordering; no longer needed)
-- Apply to: Railway Staging, Railway Production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_StatusLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId   INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode
        LIMIT 1;
    END IF;

    IF p_TypeCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_TypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode
        LIMIT 1;
    END IF;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        p.ProjectName,
        p.Category,
        ptv.ValueCode   AS ScheduleType,         -- ONE_TIME | RECURRING | FLEXIBLE (derived from ProjectTypeLkpId)
        ptv.ValueCode   AS ProjectTypeCode,
        ptv.ValueName   AS ProjectType,
        ltv.ValueCode   AS LocationTypeCode,
        ltv.ValueName   AS LocationType,
        p.Landmark      AS LocationName,          -- actual column is Landmark
        p.AddressLine   AS Address,               -- actual column is AddressLine
        sv.ValueCode    AS StatusCode,
        sv.ValueName    AS Status,
        p.City,
        p.State,
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
        (SELECT COUNT(*) FROM ProjectApplications pa
         JOIN LookupValues alv ON pa.StatusLkpId = alv.LookupValueId
         WHERE pa.ProjectId = p.ProjectId
           AND alv.ValueCode = 'APPROVED'
           AND pa.IsDeleted  = 0
        ) AS ApprovedCount,
        p.CreatedAt
    FROM Projects p
    JOIN Organisations o        ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues ptv  ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv  ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv   ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.IsDeleted = 0
      -- Admin querying their own org sees ALL projects (public + private)
      -- Public browsing (no orgId) sees only IsPublic=1
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId            = p_OrgId)
      AND (p_Category    IS NULL OR p.Category         = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Projects p
    WHERE p.IsDeleted = 0
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId            = p_OrgId)
      AND (p_Category    IS NULL OR p.Category         = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //

DROP PROCEDURE IF EXISTS Project_GetNearbyFeed //
CREATE PROCEDURE Project_GetNearbyFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_UserLat    DECIMAL(10,7),   -- NULL = no GPS (distance skipped)
    IN p_UserLon    DECIMAL(10,7),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset        INT         DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ActiveLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_UpcomingLkpId INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'   LIMIT 1;

    SELECT LookupValueId INTO v_UpcomingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl           AS OrgLogoUrl,
        p.ProjectName,
        p.Description,
        p.Category          AS CategoryName,
        ptv.ValueCode       AS ProjectTypeCode,
        ptv.ValueName       AS ProjectType,
        ltv.ValueCode       AS LocationTypeCode,
        p.Landmark          AS LocationName,
        p.AddressLine       AS Address,
        p.City,
        p.State,
        sv.ValueCode        AS StatusCode,
        sv.ValueName        AS Status,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.CreatedAt,
        -- Approved volunteer count (for "X / Y spots" display)
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv2.ValueCode = 'APPROVED'
           AND pa2.IsDeleted  = 0
        ) AS ApprovedCount,
        -- Haversine distance (km); NULL only when user has no GPS.
        -- Project GPS is guaranteed non-null by WHERE clause below.
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 )), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o       ON o.OrgId               = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv      ON sv.LookupValueId       = p.StatusLkpId
    LEFT JOIN LookupValues ptv   ON ptv.LookupValueId      = p.ProjectTypeLkpId
    LEFT JOIN LookupValues ltv   ON ltv.LookupValueId      = p.LocationTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      -- Only projects with a map pin — no pin = not a nearby opportunity
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      -- Exclude projects the user has ever applied to (any status).
      -- Hidden until the project completes and is re-activated as a new cycle.
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      -- Distance guard: only within 1000 km when user GPS is available
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          )
      -- Exclude capacity-full projects (MaxVolunteers = 0 means unlimited)
      AND (
            p.MaxVolunteers = 0
            OR (SELECT COUNT(*) FROM ProjectApplications pa2
                JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
                WHERE pa2.ProjectId    = p.ProjectId
                  AND alv2.ValueCode   = 'APPROVED'
                  AND pa2.IsDeleted    = 0
               ) < p.MaxVolunteers
          )
    ORDER BY
        -- Nearest first; NULL distance (no GPS) sorts last
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN 6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 ))
            ELSE NULL
        END ASC,
        p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- TotalCount for pagination (same filters, no pagination)
    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    JOIN   Organisations o  ON o.OrgId = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv ON sv.LookupValueId = p.StatusLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          )
      AND (
            p.MaxVolunteers = 0
            OR (SELECT COUNT(*) FROM ProjectApplications pa2
                JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
                WHERE pa2.ProjectId    = p.ProjectId
                  AND alv2.ValueCode   = 'APPROVED'
                  AND pa2.IsDeleted    = 0
               ) < p.MaxVolunteers
          );
END //

DELIMITER ;

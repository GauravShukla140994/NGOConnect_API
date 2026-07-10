-- ============================================================
-- NGO Connect — Patch: Project_List with Distance (Haversine)
-- Version : v4.3 patch
-- Date    : 2026-07-07
-- Purpose : Add optional p_UserLat / p_UserLon params to
--           Project_List SP. When both are supplied the SELECT
--           includes a DistanceKm column (Haversine formula) and
--           results are ordered nearest-first. When NULL the SP
--           behaves exactly as before (CreatedAt DESC, no distance).
-- Apply   : Run against NGOConnect database after v4.3 setup.
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
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),   -- optional: user's current latitude
    IN p_UserLon    DECIMAL(10,7)    -- optional: user's current longitude
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
        ptv.ValueCode   AS ScheduleType,
        ptv.ValueCode   AS ProjectTypeCode,
        ptv.ValueName   AS ProjectType,
        ltv.ValueCode   AS LocationTypeCode,
        ltv.ValueName   AS LocationType,
        p.Landmark      AS LocationName,
        p.AddressLine   AS Address,
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
        p.Latitude,
        p.Longitude,
        -- Haversine distance in km (NULL when user location not provided or project has no coords)
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN ROUND(
                6371 * 2 * ASIN(SQRT(
                    POWER(SIN(RADIANS((p.Latitude  - p_UserLat)  / 2)), 2) +
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude)) *
                    POWER(SIN(RADIANS((p.Longitude - p_UserLon) / 2)), 2)
                )), 2)
            ELSE NULL
        END AS DistanceKm,
        p.CreatedAt
    FROM Projects p
    JOIN Organisations o        ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues ptv  ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv  ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv   ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.IsDeleted = 0
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId            = p_OrgId)
      AND (p_Category    IS NULL OR p.Category         = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN 6371 * 2 * ASIN(SQRT(
                    POWER(SIN(RADIANS((p.Latitude  - p_UserLat)  / 2)), 2) +
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude)) *
                    POWER(SIN(RADIANS((p.Longitude - p_UserLon) / 2)), 2)
                 ))
            ELSE NULL
        END ASC,
        p.CreatedAt DESC
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

DELIMITER ;

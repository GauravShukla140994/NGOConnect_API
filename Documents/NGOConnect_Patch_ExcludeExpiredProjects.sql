-- ============================================================
-- NGO Connect — Patch: Exclude EXPIRED projects from public browse
-- Version : applied to v4.9
-- Date    : 2026-07-25
-- Scope   : Project_List SP
-- Reason  : Expired projects were visible on the All Opportunities
--           screen (volunteer browse) because no status filter was
--           applied when p_StatusCode IS NULL. Volunteers should
--           only see ACTIVE and UPCOMING projects.
-- Safe    : Admin view unaffected — when p_OrgId is provided the
--           exclusion condition is skipped, so admin tabs that
--           pass an explicit statusCode keep working exactly as
--           before.
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
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7)
)
BEGIN
    DECLARE v_Offset        INT;
    DECLARE v_StatusLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExpiredLkpId  INT UNSIGNED DEFAULT NULL;

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

    -- Resolve EXPIRED LkpId once; used to hide expired projects from public volunteer browse
    SELECT lv.LookupValueId INTO v_ExpiredLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'EXPIRED' LIMIT 1;

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
      AND  (p_Category   IS NULL OR p.Category          = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      -- Public browse only: hide EXPIRED projects; admin (p_OrgId set) sees all statuses
      AND  (p_OrgId IS NOT NULL OR v_ExpiredLkpId IS NULL OR p.StatusLkpId != v_ExpiredLkpId)
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
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      AND  (p_OrgId IS NOT NULL OR v_ExpiredLkpId IS NULL OR p.StatusLkpId != v_ExpiredLkpId);
END //

DELIMITER ;

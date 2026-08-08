-- ============================================================
-- Patch: Project_List SP fix for admin view
-- Changes:
--   1. Removes IsPublic=1 filter when OrgId is supplied (admin sees all their projects)
--   2. Adds StatusCode, CancelReason, CancelledAt, ImpactSummary, BeneficiaryCount,
--      RecurDays, SessionStartTime, SessionEndTime, ApprovedCount
-- Run against: ngodb
-- ============================================================

DROP PROCEDURE IF EXISTS Project_List;

DELIMITER //

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
        ptv.ValueCode   AS ProjectTypeCode,
        ptv.ValueName   AS ProjectType,
        ltv.ValueCode   AS LocationTypeCode,
        ltv.ValueName   AS LocationType,
        sv.ValueCode    AS StatusCode,
        sv.ValueName    AS Status,
        p.City,
        p.State,
        p.MaxVolunteers,
        p.IsPublic,
        -- Schedule fields
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.MinHoursRequired,
        -- Cancel info
        p.CancelReason,
        p.CancelledAt,
        -- Completion info
        p.ImpactSummary,
        p.BeneficiaryCount,
        -- Live approved count (for progress bar on ACTIVE cards)
        (SELECT COUNT(*) FROM ProjectApplications pa
         WHERE pa.ProjectId = p.ProjectId
           AND pa.StatusCode = 'APPROVED'
           AND pa.IsDeleted  = 0
        ) AS ApprovedCount,
        p.CreatedAt
    FROM Projects p
    JOIN Organisations o        ON p.OrgId          = o.OrgId
    LEFT JOIN LookupValues ptv  ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv  ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv   ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.IsDeleted = 0
      -- IsPublic filter: only enforce when browsing publicly (no OrgId filter)
      -- Admin querying their own org sees all projects regardless of IsPublic
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId           = p_OrgId)
      AND (p_Category    IS NULL OR p.Category        = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId     = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- TotalCount for pagination
    SELECT COUNT(*) AS TotalCount
    FROM Projects p
    LEFT JOIN LookupValues sv ON p.StatusLkpId = sv.LookupValueId
    WHERE p.IsDeleted = 0
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId           = p_OrgId)
      AND (p_Category    IS NULL OR p.Category        = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId     = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //

DELIMITER ;

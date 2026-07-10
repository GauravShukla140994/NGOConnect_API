-- ============================================================
-- NGOConnect: Project_List SP — v2
-- Adds ScheduleType, LocationName, Address to SELECT so the
-- mobile app can show schedule-type pills and location rows.
--
-- RUN IN MYSQL WORKBENCH:
--   Query → Run SQL Script  (NOT the lightning bolt ⚡)
-- ============================================================

DELIMITER $

DROP PROCEDURE IF EXISTS Project_List$

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
        ptv.ValueCode   AS ScheduleType,        -- ONE_TIME | RECURRING | FLEXIBLE (from ProjectTypeLkpId)
        ptv.ValueCode   AS ProjectTypeCode,
        ptv.ValueName   AS ProjectType,
        ltv.ValueCode   AS LocationTypeCode,
        ltv.ValueName   AS LocationType,
        p.Landmark      AS LocationName,         -- actual column name is Landmark
        p.AddressLine   AS Address,              -- actual column name is AddressLine
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

END$

DELIMITER ;

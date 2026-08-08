-- ============================================================
-- NGO Connect — Patch: Fix Project_Create & Project_Update SPs
-- Bug: Both SPs referenced RequiresApproval, GenderRestriction,
--      CoverImageUrl columns which do NOT exist in Projects table,
--      causing "An error occurred" on every project creation/edit.
-- Apply to: Railway staging + production
-- Date: 2026-07-14
-- ============================================================

DELIMITER //

-- ── Project_Create: remove 3 non-existent column references ──
DROP PROCEDURE IF EXISTS Project_Create //
CREATE PROCEDURE Project_Create(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgId             INT UNSIGNED,
    IN p_Title             VARCHAR(200),
    IN p_Description       TEXT,
    IN p_Category          VARCHAR(100),
    IN p_ProjectTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId     INT UNSIGNED,
    IN p_StatusLkpId       INT UNSIGNED,
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_MinAge            INT UNSIGNED,
    IN p_MaxAge            INT UNSIGNED,
    IN p_IsPublic          TINYINT(1),
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_ScheduleType      VARCHAR(20),
    IN p_RecurrenceDays    VARCHAR(100),
    IN p_StartTime         VARCHAR(10),
    IN p_EndTime           VARCHAR(10),
    IN p_DurationMinutes   INT UNSIGNED,
    IN p_LocationTypeLkpId INT UNSIGNED,
    IN p_LocationTypeCode  VARCHAR(20),
    IN p_LocationName      VARCHAR(200),
    IN p_Address           VARCHAR(500),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_GenderRestriction VARCHAR(20),
    IN p_RequiresApproval  TINYINT(1),
    IN p_CoverImageUrl     VARCHAR(255),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_IsDraft           TINYINT(1)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

    -- Resolve ProjectTypeLkpId from ScheduleType string if not supplied directly
    IF p_ProjectTypeLkpId IS NOT NULL THEN
        SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
    ELSE
        SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = COALESCE(p_ScheduleType, 'ONE_TIME')
        LIMIT 1;
    END IF;

    -- Resolve LocationTypeLkpId
    IF p_LocationTypeLkpId IS NOT NULL THEN
        SET v_LocationTypeLkpId = p_LocationTypeLkpId;
    ELSEIF p_LocationTypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode
        LIMIT 1;
    END IF;
    IF v_LocationTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = 'IN_PERSON'
        LIMIT 1;
    END IF;

    -- Resolve JoinTypeLkpId (p_RequiresApproval still used for logic — column just doesn't exist)
    IF p_JoinTypeLkpId IS NOT NULL THEN
        SET v_JoinTypeLkpId = p_JoinTypeLkpId;
    ELSE
        SELECT lv.LookupValueId INTO v_JoinTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
          AND lv.ValueCode = IF(COALESCE(p_RequiresApproval, 0) = 1, 'APPROVE_REQ', 'OPEN_SIGNUP')
        LIMIT 1;
    END IF;

    -- Resolve StatusLkpId
    IF p_StatusLkpId IS NOT NULL THEN
        SET v_StatusLkpId = p_StatusLkpId;
    ELSEIF COALESCE(p_IsDraft, 0) = 1 THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'DRAFT' LIMIT 1;
    ELSE
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;
    END IF;

    INSERT INTO Projects (
        OrgId, ProjectName, Category, Description,
        ProjectTypeLkpId,
        OneTimeDate, RecurStart, RecurEnd, RecurDays,
        FlexFromDate, FlexToDate,
        MinHoursRequired,
        SessionStartTime, SessionEndTime,
        LocationTypeLkpId, AddressLine, Landmark, City, State,
        Latitude, Longitude, GoogleMapsUrl,
        MaxVolunteers, JoinTypeLkpId, IsPublic,
        AgeRestriction, IdVerRequired, MinReliability,
        StatusLkpId, CreatedBy
    ) VALUES (
        p_OrgId,
        p_Title,
        p_Category,
        p_Description,
        v_ProjectTypeLkpId,
        IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, NULL),
        IF(p_ScheduleType = 'RECURRING', p_StartDate, NULL),
        IF(p_ScheduleType = 'RECURRING', p_EndDate,   NULL),
        IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, NULL),
        IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, NULL),
        IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   NULL),
        IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL),
        p_StartTime, p_EndTime,
        v_LocationTypeLkpId,
        p_Address,
        p_LocationName,
        p_City, p_State,
        p_Latitude, p_Longitude, p_GoogleMapsUrl,
        p_MaxVolunteers,
        v_JoinTypeLkpId,
        COALESCE(p_IsPublic, 1),
        IF(COALESCE(p_MinAge, 0) >= 18, 1, 0),
        0,
        0.00,
        v_StatusLkpId,
        p_UserId
    );

    SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
END //

-- ── Project_Update: remove 3 non-existent column references ──
DROP PROCEDURE IF EXISTS Project_Update //
CREATE PROCEDURE Project_Update(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Title             VARCHAR(200),
    IN p_Description       TEXT,
    IN p_Category          VARCHAR(100),
    IN p_ProjectTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId     INT UNSIGNED,
    IN p_StatusLkpId       INT UNSIGNED,
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_MinAge            INT UNSIGNED,
    IN p_MaxAge            INT UNSIGNED,
    IN p_IsPublic          TINYINT(1),
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_ScheduleType      VARCHAR(20),
    IN p_RecurrenceDays    VARCHAR(100),
    IN p_StartTime         VARCHAR(10),
    IN p_EndTime           VARCHAR(10),
    IN p_DurationMinutes   INT UNSIGNED,
    IN p_LocationTypeLkpId INT UNSIGNED,
    IN p_LocationTypeCode  VARCHAR(20),
    IN p_LocationName      VARCHAR(200),
    IN p_Address           VARCHAR(500),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_GenderRestriction VARCHAR(20),
    IN p_RequiresApproval  TINYINT(1),
    IN p_CoverImageUrl     VARCHAR(255),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_IsDraft           TINYINT(1)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

    IF p_ProjectTypeLkpId IS NOT NULL THEN
        SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
    ELSEIF p_ScheduleType IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_ScheduleType LIMIT 1;
    END IF;

    IF p_LocationTypeLkpId IS NOT NULL THEN
        SET v_LocationTypeLkpId = p_LocationTypeLkpId;
    ELSEIF p_LocationTypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode LIMIT 1;
    END IF;

    IF p_JoinTypeLkpId IS NOT NULL THEN
        SET v_JoinTypeLkpId = p_JoinTypeLkpId;
    ELSEIF p_RequiresApproval IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_JoinTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
          AND lv.ValueCode = IF(p_RequiresApproval = 1, 'APPROVE_REQ', 'OPEN_SIGNUP') LIMIT 1;
    END IF;

    IF p_StatusLkpId IS NOT NULL THEN
        SET v_StatusLkpId = p_StatusLkpId;
    ELSEIF p_IsDraft IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS'
          AND lv.ValueCode = IF(p_IsDraft = 1, 'DRAFT', 'UPCOMING') LIMIT 1;
    END IF;

    UPDATE Projects SET
        ProjectName       = COALESCE(p_Title,             ProjectName),
        Category          = COALESCE(p_Category,          Category),
        Description       = COALESCE(p_Description,       Description),
        ProjectTypeLkpId  = COALESCE(v_ProjectTypeLkpId,  ProjectTypeLkpId),
        OneTimeDate       = IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, OneTimeDate),
        RecurStart        = IF(p_ScheduleType = 'RECURRING', p_StartDate, RecurStart),
        RecurEnd          = IF(p_ScheduleType = 'RECURRING', p_EndDate,   RecurEnd),
        RecurDays         = IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, RecurDays),
        FlexFromDate      = IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, FlexFromDate),
        FlexToDate        = IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   FlexToDate),
        MinHoursRequired  = COALESCE(IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL), MinHoursRequired),
        SessionStartTime  = COALESCE(p_StartTime,         SessionStartTime),
        SessionEndTime    = COALESCE(p_EndTime,           SessionEndTime),
        LocationTypeLkpId = COALESCE(v_LocationTypeLkpId, LocationTypeLkpId),
        AddressLine       = COALESCE(p_Address,           AddressLine),
        Landmark          = COALESCE(p_LocationName,      Landmark),
        City              = COALESCE(p_City,              City),
        State             = COALESCE(p_State,             State),
        Latitude          = COALESCE(p_Latitude,          Latitude),
        Longitude         = COALESCE(p_Longitude,         Longitude),
        GoogleMapsUrl     = COALESCE(p_GoogleMapsUrl,     GoogleMapsUrl),
        MaxVolunteers     = COALESCE(p_MaxVolunteers,     MaxVolunteers),
        JoinTypeLkpId     = COALESCE(v_JoinTypeLkpId,     JoinTypeLkpId),
        IsPublic          = COALESCE(p_IsPublic,          IsPublic),
        AgeRestriction    = IF(p_MinAge IS NOT NULL, IF(p_MinAge >= 18, 1, 0), AgeRestriction),
        StatusLkpId       = COALESCE(v_StatusLkpId,       StatusLkpId),
        UpdatedBy         = p_UserId,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;
END //

DELIMITER ;

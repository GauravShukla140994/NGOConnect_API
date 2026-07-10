-- ============================================================
-- NGOConnect Patch: Project_Create & Project_Update SP Fix
-- Aligns SP parameters with DAL (CreateAsync / UpdateAsync)
-- Run this ONCE against your MySQL 8.0 database.
-- ============================================================

-- 1. Schema changes ─────────────────────────────────────────

-- Make Category nullable (not always known at create time)
ALTER TABLE Projects MODIFY COLUMN Category VARCHAR(100) NULL;

-- Add new columns safely (ADD COLUMN IF NOT EXISTS needs MySQL 8.0.3+;
-- this helper works on all 8.0.x versions)
DROP PROCEDURE IF EXISTS _ngo_add_col;
DELIMITER //
CREATE PROCEDURE _ngo_add_col(IN p_tbl VARCHAR(64), IN p_col VARCHAR(64), IN p_def TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = p_tbl
          AND COLUMN_NAME  = p_col
    ) THEN
        SET @_sql = CONCAT('ALTER TABLE `', p_tbl, '` ADD COLUMN `', p_col, '` ', p_def);
        PREPARE _stmt FROM @_sql;
        EXECUTE _stmt;
        DEALLOCATE PREPARE _stmt;
    END IF;
END //
DELIMITER ;

CALL _ngo_add_col('Projects', 'RequiresApproval',  'TINYINT(1) NOT NULL DEFAULT 0 AFTER IsPublic');
CALL _ngo_add_col('Projects', 'GenderRestriction', 'VARCHAR(20) NULL AFTER RequiresApproval');
CALL _ngo_add_col('Projects', 'CoverImageUrl',     'VARCHAR(255) NULL AFTER GenderRestriction');

DROP PROCEDURE IF EXISTS _ngo_add_col;

-- 2. Drop old SPs ────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Project_Create;
DROP PROCEDURE IF EXISTS Project_Update;

-- 3. Project_Create ──────────────────────────────────────────
-- Accepts the exact params the DAL's CreateAsync sends.
-- Internally resolves:
--   p_ScheduleType   (string) → ProjectTypeLkpId via PROJECT_TYPE
--   p_LocationTypeCode (string) → LocationTypeLkpId via LOCATION_TYPE
--   p_RequiresApproval (bool)  → JoinTypeLkpId via PROJECT_JOIN_TYPE
--   p_IsDraft (bool)           → StatusLkpId DRAFT vs UPCOMING

DELIMITER //
CREATE PROCEDURE Project_Create(
    IN p_UserId            INT UNSIGNED,      -- DAL: userId param
    IN p_OrgId             INT UNSIGNED,
    IN p_Title             VARCHAR(200),       -- → ProjectName column
    IN p_Description       TEXT,
    IN p_Category          VARCHAR(100),
    IN p_ProjectTypeLkpId  INT UNSIGNED,       -- optional override
    IN p_JoinTypeLkpId     INT UNSIGNED,       -- optional override
    IN p_StatusLkpId       INT UNSIGNED,       -- optional override
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_MinAge            INT UNSIGNED,        -- → AgeRestriction = (MinAge >= 18)
    IN p_MaxAge            INT UNSIGNED,        -- stored for future use
    IN p_IsPublic          TINYINT(1),
    IN p_StartDate         DATE,               -- maps to OneTimeDate / RecurStart / FlexFromDate
    IN p_EndDate           DATE,               -- maps to RecurEnd / FlexToDate
    IN p_ScheduleType      VARCHAR(20),        -- ONE_TIME | RECURRING | FLEXIBLE
    IN p_RecurrenceDays    VARCHAR(100),        -- → RecurDays
    IN p_StartTime         VARCHAR(10),         -- → SessionStartTime
    IN p_EndTime           VARCHAR(10),         -- → SessionEndTime
    IN p_DurationMinutes   INT UNSIGNED,        -- → MinHoursRequired = ROUND(val/60)
    IN p_LocationTypeLkpId INT UNSIGNED,        -- optional override
    IN p_LocationTypeCode  VARCHAR(20),         -- IN_PERSON | REMOTE | HYBRID
    IN p_LocationName      VARCHAR(200),        -- → Landmark column
    IN p_Address           VARCHAR(500),        -- → AddressLine column
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_GenderRestriction VARCHAR(20),
    IN p_RequiresApproval  TINYINT(1),
    IN p_CoverImageUrl     VARCHAR(255),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_IsDraft           TINYINT(1)          -- 1 = save as DRAFT, 0/NULL = UPCOMING
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

    -- ── Resolve ProjectTypeLkpId from ScheduleType string ──
    IF p_ProjectTypeLkpId IS NOT NULL THEN
        SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
    ELSE
        SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE'
          AND lv.ValueCode = COALESCE(p_ScheduleType, 'ONE_TIME')
        LIMIT 1;
    END IF;

    -- ── Resolve LocationTypeLkpId ──
    IF p_LocationTypeLkpId IS NOT NULL THEN
        SET v_LocationTypeLkpId = p_LocationTypeLkpId;
    ELSEIF p_LocationTypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE'
          AND lv.ValueCode = p_LocationTypeCode
        LIMIT 1;
    END IF;
    -- If still null, fall back to IN_PERSON
    IF v_LocationTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = 'IN_PERSON'
        LIMIT 1;
    END IF;

    -- ── Resolve JoinTypeLkpId from RequiresApproval flag ──
    IF p_JoinTypeLkpId IS NOT NULL THEN
        SET v_JoinTypeLkpId = p_JoinTypeLkpId;
    ELSE
        SELECT lv.LookupValueId INTO v_JoinTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
          AND lv.ValueCode = IF(COALESCE(p_RequiresApproval, 0) = 1, 'APPROVE_REQ', 'OPEN_SIGNUP')
        LIMIT 1;
    END IF;

    -- ── Resolve StatusLkpId ──
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
        RequiresApproval, GenderRestriction, CoverImageUrl,
        StatusLkpId, CreatedBy
    ) VALUES (
        p_OrgId,
        p_Title,
        p_Category,
        p_Description,
        v_ProjectTypeLkpId,
        -- Date columns mapped by schedule type
        IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, NULL),       -- OneTimeDate
        IF(p_ScheduleType = 'RECURRING', p_StartDate, NULL),       -- RecurStart
        IF(p_ScheduleType = 'RECURRING', p_EndDate,   NULL),       -- RecurEnd
        IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, NULL),  -- RecurDays
        IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, NULL),       -- FlexFromDate
        IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   NULL),       -- FlexToDate
        IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL),
        p_StartTime, p_EndTime,
        v_LocationTypeLkpId,
        p_Address,       -- AddressLine
        p_LocationName,  -- Landmark
        p_City, p_State,
        p_Latitude, p_Longitude, p_GoogleMapsUrl,
        p_MaxVolunteers,
        v_JoinTypeLkpId,
        COALESCE(p_IsPublic, 1),
        IF(COALESCE(p_MinAge, 0) >= 18, 1, 0),  -- AgeRestriction
        0,     -- IdVerRequired (future)
        0.00,  -- MinReliability (future)
        COALESCE(p_RequiresApproval, 0),
        p_GenderRestriction,
        p_CoverImageUrl,
        v_StatusLkpId,
        p_UserId  -- CreatedBy
    );

    SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
END //

-- 4. Project_Update ──────────────────────────────────────────
-- Mirrors UpdateAsync params. Uses COALESCE so partial updates are safe.

CREATE PROCEDURE Project_Update(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,      -- DAL: userId param (was p_UpdatedBy)
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

    -- ── Resolve ProjectTypeLkpId ──
    IF p_ProjectTypeLkpId IS NOT NULL THEN
        SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
    ELSEIF p_ScheduleType IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_ScheduleType LIMIT 1;
    END IF;

    -- ── Resolve LocationTypeLkpId ──
    IF p_LocationTypeLkpId IS NOT NULL THEN
        SET v_LocationTypeLkpId = p_LocationTypeLkpId;
    ELSEIF p_LocationTypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode LIMIT 1;
    END IF;

    -- ── Resolve JoinTypeLkpId ──
    IF p_JoinTypeLkpId IS NOT NULL THEN
        SET v_JoinTypeLkpId = p_JoinTypeLkpId;
    ELSEIF p_RequiresApproval IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_JoinTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
          AND lv.ValueCode = IF(p_RequiresApproval = 1, 'APPROVE_REQ', 'OPEN_SIGNUP') LIMIT 1;
    END IF;

    -- ── Resolve StatusLkpId ──
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
        -- Date fields: only update the relevant ones for the new schedule type
        OneTimeDate       = IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, OneTimeDate),
        RecurStart        = IF(p_ScheduleType = 'RECURRING', p_StartDate, RecurStart),
        RecurEnd          = IF(p_ScheduleType = 'RECURRING', p_EndDate,   RecurEnd),
        RecurDays         = IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, RecurDays),
        FlexFromDate      = IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, FlexFromDate),
        FlexToDate        = IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   FlexToDate),
        MinHoursRequired  = COALESCE(
                                IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL),
                                MinHoursRequired),
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
        RequiresApproval  = COALESCE(p_RequiresApproval,  RequiresApproval),
        GenderRestriction = COALESCE(p_GenderRestriction, GenderRestriction),
        CoverImageUrl     = COALESCE(p_CoverImageUrl,     CoverImageUrl),
        StatusLkpId       = COALESCE(v_StatusLkpId,       StatusLkpId),
        UpdatedBy         = p_UserId,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;
END //

DELIMITER ;

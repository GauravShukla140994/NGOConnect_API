-- ============================================================
-- patch_project_settings_validation.sql
-- Adds settings-based validation to Project_Create and
-- Project_Update SPs. Rules are read from the Settings table
-- at runtime so admin can tune limits without redeployment.
--
-- Validation rules added:
--   ONE_TIME: session duration <= OT_MAX_DURATION_HOURS
--   RECURRING: date span between RECURRING_MIN/MAX_DURATION_DAYS
--   FLEXIBLE: date span between FLEXIBLE_MIN/MAX_DURATION_DAYS
--   FLEXIBLE: MaxDailyHours >= FLEXIBLE_MAX_DAILY_HOURS (floor)
--   FLEXIBLE: MinSessionHours >= FLEXIBLE_MIN_SESSION_HOURS (floor)
--   FLEXIBLE: MinAttendPct >= FLEXIBLE_MIN_ATTEND_PCT (floor)
--   RECURRING: MinAttendPct >= RECURRING_MIN_ATTEND_PCT (floor)
--
-- Run on: local -> Railway staging -> Railway production
-- Safe to re-run: DROP + CREATE is idempotent.
-- ============================================================

DELIMITER //

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
    IN p_IsDraft           TINYINT(1),
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_ProjectTypeLkpId   INT UNSIGNED    DEFAULT NULL;
    DECLARE v_LocationTypeLkpId  INT UNSIGNED    DEFAULT NULL;
    DECLARE v_JoinTypeLkpId      INT UNSIGNED    DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED    DEFAULT NULL;

    -- Settings-based validation variables
    DECLARE v_Error              VARCHAR(500)    DEFAULT NULL;
    DECLARE v_OtMaxHours         INT             DEFAULT 12;
    DECLARE v_RecurMaxDays       INT             DEFAULT 90;
    DECLARE v_RecurMinDays       INT             DEFAULT 7;
    DECLARE v_FlexMaxDays        INT             DEFAULT 60;
    DECLARE v_FlexMinDays        INT             DEFAULT 3;
    DECLARE v_FlexMaxDailyHrs    DECIMAL(4,2)    DEFAULT 8;
    DECLARE v_FlexMinSessHrs     DECIMAL(4,2)    DEFAULT 1;
    DECLARE v_FlexMinAttendPct   DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_RecurMinAttendPct  DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_SessionDurHours    DECIMAL(6,2)    DEFAULT NULL;
    DECLARE v_SpanDays           INT             DEFAULT NULL;

    -- Load settings (fall back to declared defaults if setting row missing)
    SELECT CAST(SettingValue AS SIGNED)          INTO v_OtMaxHours        FROM Settings WHERE SettingKey = 'OT_MAX_DURATION_HOURS'       AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMaxDays       FROM Settings WHERE SettingKey = 'RECURRING_MAX_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMinDays       FROM Settings WHERE SettingKey = 'RECURRING_MIN_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMaxDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMinDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMaxDailyHrs    FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DAILY_HOURS'     AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMinSessHrs     FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_SESSION_HOURS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_FlexMinAttendPct   FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_ATTEND_PCT'      AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_RecurMinAttendPct  FROM Settings WHERE SettingKey = 'RECURRING_MIN_ATTEND_PCT'     AND IsDeleted = 0 LIMIT 1;

    -- ── Validation ────────────────────────────────────────────────────────────
    -- ONE_TIME: session duration must not exceed OT_MAX_DURATION_HOURS
    IF v_Error IS NULL AND p_ScheduleType = 'ONE_TIME'
       AND p_StartTime IS NOT NULL AND p_EndTime IS NOT NULL THEN
        SET v_SessionDurHours = (
            TIME_TO_SEC(CAST(p_EndTime AS TIME)) - TIME_TO_SEC(CAST(p_StartTime AS TIME))
        ) / 3600.0;
        IF v_SessionDurHours <= 0 THEN
            SET v_Error = 'Session end time must be after start time.';
        ELSEIF v_SessionDurHours > v_OtMaxHours THEN
            SET v_Error = CONCAT('Session duration cannot exceed ', v_OtMaxHours,
                                 ' hours for a ONE_TIME project. Please adjust start and end times.');
        END IF;
    END IF;

    -- RECURRING: date span must be within RECURRING_MIN/MAX_DURATION_DAYS
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_RecurMinDays THEN
            SET v_Error = CONCAT('RECURRING projects must span at least ', v_RecurMinDays, ' days.');
        ELSEIF v_SpanDays > v_RecurMaxDays THEN
            SET v_Error = CONCAT('RECURRING projects cannot span more than ', v_RecurMaxDays, ' days.');
        END IF;
    END IF;

    -- FLEXIBLE: date span must be within FLEXIBLE_MIN/MAX_DURATION_DAYS
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_FlexMinDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects must span at least ', v_FlexMinDays, ' days.');
        ELSEIF v_SpanDays > v_FlexMaxDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects cannot span more than ', v_FlexMaxDays, ' days.');
        END IF;
    END IF;

    -- FLEXIBLE: MaxDailyHours must be >= system floor (project can override upward only)
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MaxDailyHours IS NOT NULL THEN
        IF p_MaxDailyHours < v_FlexMaxDailyHrs THEN
            SET v_Error = CONCAT('Max daily hours cannot be less than the platform minimum of ',
                                 v_FlexMaxDailyHrs, ' hours.');
        END IF;
    END IF;

    -- FLEXIBLE: MinSessionHours must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinSessionHours IS NOT NULL THEN
        IF p_MinSessionHours < v_FlexMinSessHrs THEN
            SET v_Error = CONCAT('Minimum session hours cannot be less than the platform minimum of ',
                                 v_FlexMinSessHrs, ' hour(s).');
        END IF;
    END IF;

    -- FLEXIBLE: MinAttendPct must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_FlexMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_FlexMinAttendPct, '% for FLEXIBLE projects.');
        END IF;
    END IF;

    -- RECURRING: MinAttendPct must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_RecurMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_RecurMinAttendPct, '% for RECURRING projects.');
        END IF;
    END IF;

    -- Return validation error if any check failed
    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS ProjectId;

    -- Duplicate check 1: same org + same title (case-insensitive, trimmed)
    ELSEIF EXISTS (
        SELECT 1 FROM Projects
        WHERE OrgId                    = p_OrgId
          AND LOWER(TRIM(ProjectName)) = LOWER(TRIM(p_Title))
          AND IsDeleted                = 0
    ) THEN
        SELECT 0    AS IsSuccess,
               'A project with this title already exists in your organisation. Please use a different name.' AS Message,
               NULL AS ProjectId;

    -- Duplicate check 2: same org + same category + same date range + same session times
    ELSEIF p_Category IS NOT NULL AND p_StartDate IS NOT NULL
        AND p_StartTime IS NOT NULL   AND p_EndTime IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM Projects
            WHERE OrgId                   = p_OrgId
              AND IsDeleted               = 0
              AND LOWER(TRIM(Category))   = LOWER(TRIM(p_Category))
              AND SessionStartTime        = p_StartTime
              AND SessionEndTime          = p_EndTime
              AND (
                  (p_ScheduleType = 'ONE_TIME'
                        AND OneTimeDate  = p_StartDate)
               OR (p_ScheduleType = 'RECURRING'
                        AND RecurStart  = p_StartDate
                        AND RecurEnd    = p_EndDate)
               OR (p_ScheduleType = 'FLEXIBLE'
                        AND FlexFromDate = p_StartDate
                        AND FlexToDate   = p_EndDate)
              )
        )
    THEN
        SELECT 0    AS IsSuccess,
               'A project in this category is already scheduled for the same date and time. Please choose a different schedule.' AS Message,
               NULL AS ProjectId;

    ELSE

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

        -- Resolve JoinTypeLkpId
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
            StatusLkpId, MinAttendPct, MaxDailyHours, MinSessionHours, CreatedBy
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
            p_MinAttendPct, p_MaxDailyHours, p_MinSessionHours,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;

    END IF;
END //

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
    IN p_IsDraft           TINYINT(1),
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId  INT UNSIGNED    DEFAULT NULL;
    DECLARE v_JoinTypeLkpId      INT UNSIGNED    DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED    DEFAULT NULL;

    -- Settings-based validation variables
    DECLARE v_Error              VARCHAR(500)    DEFAULT NULL;
    DECLARE v_OtMaxHours         INT             DEFAULT 12;
    DECLARE v_RecurMaxDays       INT             DEFAULT 90;
    DECLARE v_RecurMinDays       INT             DEFAULT 7;
    DECLARE v_FlexMaxDays        INT             DEFAULT 60;
    DECLARE v_FlexMinDays        INT             DEFAULT 3;
    DECLARE v_FlexMaxDailyHrs    DECIMAL(4,2)    DEFAULT 8;
    DECLARE v_FlexMinSessHrs     DECIMAL(4,2)    DEFAULT 1;
    DECLARE v_FlexMinAttendPct   DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_RecurMinAttendPct  DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_SessionDurHours    DECIMAL(6,2)    DEFAULT NULL;
    DECLARE v_SpanDays           INT             DEFAULT NULL;

    -- Load settings
    SELECT CAST(SettingValue AS SIGNED)          INTO v_OtMaxHours        FROM Settings WHERE SettingKey = 'OT_MAX_DURATION_HOURS'       AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMaxDays       FROM Settings WHERE SettingKey = 'RECURRING_MAX_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMinDays       FROM Settings WHERE SettingKey = 'RECURRING_MIN_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMaxDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMinDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMaxDailyHrs    FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DAILY_HOURS'     AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMinSessHrs     FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_SESSION_HOURS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_FlexMinAttendPct   FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_ATTEND_PCT'      AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_RecurMinAttendPct  FROM Settings WHERE SettingKey = 'RECURRING_MIN_ATTEND_PCT'     AND IsDeleted = 0 LIMIT 1;

    -- ── Validation (only when relevant fields are being changed) ──────────────
    IF v_Error IS NULL AND p_ScheduleType = 'ONE_TIME'
       AND p_StartTime IS NOT NULL AND p_EndTime IS NOT NULL THEN
        SET v_SessionDurHours = (
            TIME_TO_SEC(CAST(p_EndTime AS TIME)) - TIME_TO_SEC(CAST(p_StartTime AS TIME))
        ) / 3600.0;
        IF v_SessionDurHours <= 0 THEN
            SET v_Error = 'Session end time must be after start time.';
        ELSEIF v_SessionDurHours > v_OtMaxHours THEN
            SET v_Error = CONCAT('Session duration cannot exceed ', v_OtMaxHours,
                                 ' hours for a ONE_TIME project. Please adjust start and end times.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_RecurMinDays THEN
            SET v_Error = CONCAT('RECURRING projects must span at least ', v_RecurMinDays, ' days.');
        ELSEIF v_SpanDays > v_RecurMaxDays THEN
            SET v_Error = CONCAT('RECURRING projects cannot span more than ', v_RecurMaxDays, ' days.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_FlexMinDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects must span at least ', v_FlexMinDays, ' days.');
        ELSEIF v_SpanDays > v_FlexMaxDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects cannot span more than ', v_FlexMaxDays, ' days.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MaxDailyHours IS NOT NULL THEN
        IF p_MaxDailyHours < v_FlexMaxDailyHrs THEN
            SET v_Error = CONCAT('Max daily hours cannot be less than the platform minimum of ',
                                 v_FlexMaxDailyHrs, ' hours.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinSessionHours IS NOT NULL THEN
        IF p_MinSessionHours < v_FlexMinSessHrs THEN
            SET v_Error = CONCAT('Minimum session hours cannot be less than the platform minimum of ',
                                 v_FlexMinSessHrs, ' hour(s).');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_FlexMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_FlexMinAttendPct, '% for FLEXIBLE projects.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_RecurMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_RecurMinAttendPct, '% for RECURRING projects.');
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE

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
        MinAttendPct      = COALESCE(p_MinAttendPct,      MinAttendPct),
        MaxDailyHours     = COALESCE(p_MaxDailyHours,     MaxDailyHours),
        MinSessionHours   = COALESCE(p_MinSessionHours,   MinSessionHours),
        UpdatedBy         = p_UserId,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;

    END IF; -- v_Error IS NOT NULL check
END //

DELIMITER ;

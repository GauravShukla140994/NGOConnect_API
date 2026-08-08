-- ============================================================
-- NGO Connect — Patch: Project_Create Duplicate Title Check
-- ============================================================
-- Purpose : Prevent creating two projects with the same title
--           in the same organisation (case-insensitive, trimmed).
--           Returns IsSuccess=0 + descriptive message when a
--           duplicate is detected; the C# DAL surfaces this as
--           an error Alert on the mobile app — no code change needed.
--
-- Duplicate rule : same OrgId + same ProjectName (case-insensitive,
--                  both sides TRIM'd) + IsDeleted = 0
--
-- Apply : run this block against Railway staging, then production.
-- No table schema changes — SP-only patch.
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
    IN p_IsDraft           TINYINT(1)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

    -- Duplicate check 1: same org + same title (case-insensitive, trimmed)
    IF EXISTS (
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

    END IF;
END //

DELIMITER ;

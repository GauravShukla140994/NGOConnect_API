-- ═══════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch v5.1: RECURRING + FLEXIBLE Project Flow
-- Covers: ALTER Tables, New Tables, New Lookup Seeds, New Settings,
--         Updated SPs (Project_Create, Project_Update, Project_GetById,
--                       Certificate_Issue),
--         New SPs (Project_GenerateSessions, Project_FlexCheckIn,
--                  Project_FlexCheckOut, Project_TransitionToClosing,
--                  Project_FinalizeClosing, Project_AutoActivate,
--                  Project_MarkNoShows, Project_AutoCheckoutMissed,
--                  Project_GetVolunteerEligibility, Project_GetMySessionList,
--                  Session_Cancel, Session_OptOut,
--                  Certificate_IssueBulk,
--                  UserSessionSkillRating_AddUpdate,
--                  Project_CheckMilestoneNotification)
-- Apply: local DB first → Railway staging → Railway production
-- ═══════════════════════════════════════════════════════════════════════════

-- =============================================================
-- SECTION 1: ALTER TABLES
-- =============================================================

ALTER TABLE Projects
    ADD COLUMN MinAttendPct    DECIMAL(5,2) NULL COMMENT '% attendance required for certificate eligibility (NULL = no minimum)'  AFTER MinHoursRequired,
    ADD COLUMN MaxDailyHours   DECIMAL(4,2) NULL COMMENT 'Max hours a FLEXIBLE volunteer can log per day'                          AFTER MinAttendPct,
    ADD COLUMN MinSessionHours DECIMAL(4,2) NULL COMMENT 'Min session hours to count as attended (for cert eligibility check)'     AFTER MaxDailyHours;

-- =============================================================
-- SECTION 2: NEW TABLES
-- =============================================================

CREATE TABLE IF NOT EXISTS UserSessionSkillRatings (
    SessionSkillRatingId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SessionId            INT UNSIGNED  NOT NULL,
    UserId               INT UNSIGNED  NOT NULL,
    ProjectId            INT UNSIGNED  NOT NULL,
    SkillId              INT UNSIGNED  NOT NULL,   -- ProjectSkills.ProjectSkillId
    Rating               DECIMAL(3,2) NOT NULL,   -- 1.0–5.0
    RatedBy              INT UNSIGNED  NOT NULL,
    Notes                TEXT          NULL,
    CreatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SessionSkillRatingId),
    UNIQUE KEY uq_ssr (SessionId, UserId, SkillId),
    INDEX idx_ssr_user    (UserId),
    INDEX idx_ssr_session (SessionId),
    INDEX idx_ssr_project (ProjectId),
    CONSTRAINT fk_ssr_session  FOREIGN KEY (SessionId)  REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_ssr_user     FOREIGN KEY (UserId)     REFERENCES Users(UserId),
    CONSTRAINT fk_ssr_ratedby  FOREIGN KEY (RatedBy)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS VolunteerSessionOptOuts (
    OptOutId        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SessionId       INT UNSIGNED  NOT NULL,
    UserId          INT UNSIGNED  NOT NULL,
    ProjectId       INT UNSIGNED  NOT NULL,
    OptOutTypeLkpId INT UNSIGNED  NOT NULL,   -- SESSION_OPT_OUT_TYPE: SELF | ADMIN_EXCUSED | ADMIN_REMOVED
    Reason          TEXT          NULL,
    CreatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED  NOT NULL,
    PRIMARY KEY (OptOutId),
    UNIQUE KEY uq_session_optout (SessionId, UserId),
    INDEX idx_optout_user    (UserId),
    INDEX idx_optout_session (SessionId),
    INDEX idx_optout_project (ProjectId),
    CONSTRAINT fk_optout_session FOREIGN KEY (SessionId) REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_optout_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- SECTION 3: LOOKUP DATA
-- =============================================================

-- New LookupType
INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsActive, IsSystemType)
VALUES ('SESSION_OPT_OUT_TYPE', 'Session Opt-Out Type',
        'Reason a volunteer was removed from a specific session', 1, 1);

-- PROJECT_STATUS: CLOSING (between ACTIVE and COMPLETED)
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'CLOSING', 'Closing', 6, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'PROJECT_STATUS';

-- ATTENDANCE_STATUS: CHECKED_IN (FLEXIBLE volunteer checked in, not yet checked out)
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKED_IN', 'Checked In', 4, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

-- ATTENDANCE_STATUS: CHECKOUT_MISSED (FLEXIBLE, forgot checkout — HoursLogged = 0)
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKOUT_MISSED', 'Checkout Missed', 5, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

-- SESSION_OPT_OUT_TYPE values
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'SELF', 'Self Opt-Out', 1, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'ADMIN_EXCUSED', 'Admin Excused', 2, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'ADMIN_REMOVED', 'Admin Removed', 3, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

-- BADGE_TYPE: PROJECT_COMPLETE
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'PROJECT_COMPLETE', 'Project Completed', 8, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'BADGE_TYPE';

-- =============================================================
-- SECTION 4: SETTINGS
-- =============================================================

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('PROJECT',  'RECURRING_MAX_DURATION_DAYS',  '90',          'NUMBER',  'Maximum calendar days a RECURRING project can span',                           0),
('PROJECT',  'FLEXIBLE_MAX_DURATION_DAYS',   '90',          'NUMBER',  'Maximum calendar days a FLEXIBLE project can span',                            0),
('PROJECT',  'FLEX_CHECKIN_OPEN_MINUTES',    '15',          'NUMBER',  'Minutes before session start that FLEXIBLE check-in opens',                    0),
('PROJECT',  'FLEX_CHECKOUT_BUFFER_MINUTES', '30',          'NUMBER',  'Minutes after session end before auto-CHECKOUT_MISSED kicks in',                0),
('PROJECT',  'RECURRING_NOSHOW_GRACE_MINUTES','30',         'NUMBER',  'Minutes after RECURRING session end before marking absent volunteers NO_SHOW',  0),
('PROJECT',  'AUTO_ACTIVATE_LEAD_DAYS',      '0',           'NUMBER',  'Days before start date to auto-activate project (0 = same day)',               0),
('PROJECT',  'CLOSING_TRIGGER_OFFSET_DAYS',  '0',           'NUMBER',  'Days after project end date to auto-transition to CLOSING',                    0),
('PROJECT',  'SKILL_RATING_WINDOW_DAYS',     '30',          'NUMBER',  'Days after project enters CLOSING that skill ratings can be submitted',        0),
('PROJECT',  'MILESTONE_25_ENABLED',         'true',        'BOOLEAN', 'Send push notification when volunteer reaches 25% attendance milestone',       0),
('PROJECT',  'MILESTONE_50_ENABLED',         'true',        'BOOLEAN', 'Send push notification when volunteer reaches 50% attendance milestone',       0),
('PROJECT',  'MILESTONE_75_ENABLED',         'true',        'BOOLEAN', 'Send push notification when volunteer reaches 75% attendance milestone',       0),
('HANGFIRE', 'AUTO_ACTIVATE_CRON',           '0 1 * * *',   'STRING',  'Cron expression: AutoActivateProjectsJob — daily at 01:00',                   0),
('HANGFIRE', 'MARK_NOSHOW_CRON',             '*/30 * * * *','STRING',  'Cron expression: MarkNoShowJob — every 30 minutes',                           0),
('HANGFIRE', 'AUTO_CHECKOUT_MISSED_CRON',    '*/30 * * * *','STRING',  'Cron expression: AutoCheckoutMissedJob — every 30 minutes',                   0),
('HANGFIRE', 'TRANSITION_CLOSING_CRON',      '0 2 * * *',   'STRING',  'Cron expression: TransitionToClosingJob — daily at 02:00',                    0);

-- =============================================================
-- SECTION 5: STORED PROCEDURES
-- =============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- 5.1  Project_Create (updated: +3 schedule-override params)
-- ─────────────────────────────────────────────────────────────
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
    -- v5.1 NEW: schedule-override fields
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

    IF EXISTS (
        SELECT 1 FROM Projects
        WHERE OrgId = p_OrgId AND LOWER(TRIM(ProjectName)) = LOWER(TRIM(p_Title)) AND IsDeleted = 0
    ) THEN
        SELECT 0 AS IsSuccess, 'A project with this title already exists in your organisation.' AS Message, NULL AS ProjectId;

    ELSEIF p_Category IS NOT NULL AND p_StartDate IS NOT NULL
        AND p_StartTime IS NOT NULL AND p_EndTime IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM Projects
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND LOWER(TRIM(Category)) = LOWER(TRIM(p_Category))
              AND SessionStartTime = p_StartTime AND SessionEndTime = p_EndTime
              AND (
                  (p_ScheduleType = 'ONE_TIME'  AND OneTimeDate   = p_StartDate)
               OR (p_ScheduleType = 'RECURRING' AND RecurStart    = p_StartDate AND RecurEnd    = p_EndDate)
               OR (p_ScheduleType = 'FLEXIBLE'  AND FlexFromDate  = p_StartDate AND FlexToDate  = p_EndDate)
              )
        )
    THEN
        SELECT 0 AS IsSuccess, 'A project in this category is already scheduled for the same date and time.' AS Message, NULL AS ProjectId;

    ELSE
        IF p_ProjectTypeLkpId IS NOT NULL THEN
            SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
        ELSE
            SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = COALESCE(p_ScheduleType, 'ONE_TIME') LIMIT 1;
        END IF;

        IF p_LocationTypeLkpId IS NOT NULL THEN
            SET v_LocationTypeLkpId = p_LocationTypeLkpId;
        ELSEIF p_LocationTypeCode IS NOT NULL THEN
            SELECT lv.LookupValueId INTO v_LocationTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode LIMIT 1;
        END IF;
        IF v_LocationTypeLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_LocationTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = 'IN_PERSON' LIMIT 1;
        END IF;

        IF p_JoinTypeLkpId IS NOT NULL THEN
            SET v_JoinTypeLkpId = p_JoinTypeLkpId;
        ELSE
            SELECT lv.LookupValueId INTO v_JoinTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
              AND lv.ValueCode = IF(COALESCE(p_RequiresApproval, 0) = 1, 'APPROVE_REQ', 'OPEN_SIGNUP') LIMIT 1;
        END IF;

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
            OneTimeDate, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
            FlexFromDate, FlexToDate,
            MinHoursRequired, MinAttendPct, MaxDailyHours, MinSessionHours,
            LocationTypeLkpId, AddressLine, Landmark, City, State,
            Latitude, Longitude, GoogleMapsUrl,
            MaxVolunteers, JoinTypeLkpId, IsPublic,
            AgeRestriction, IdVerRequired, MinReliability,
            StatusLkpId, CreatedBy
        ) VALUES (
            p_OrgId, p_Title, p_Category, p_Description,
            v_ProjectTypeLkpId,
            IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, NULL),
            IF(p_ScheduleType = 'RECURRING', p_StartDate, NULL),
            IF(p_ScheduleType = 'RECURRING', p_EndDate,   NULL),
            IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, NULL),
            p_StartTime, p_EndTime,
            IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, NULL),
            IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   NULL),
            IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL),
            p_MinAttendPct, p_MaxDailyHours, p_MinSessionHours,
            v_LocationTypeLkpId, p_Address, p_LocationName, p_City, p_State,
            p_Latitude, p_Longitude, p_GoogleMapsUrl,
            p_MaxVolunteers, v_JoinTypeLkpId, COALESCE(p_IsPublic, 1),
            IF(COALESCE(p_MinAge, 0) >= 18, 1, 0), 0, 0.00,
            v_StatusLkpId, p_UserId
        );

        SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.2  Project_Update (updated: +3 params, locked if not UPCOMING)
-- ─────────────────────────────────────────────────────────────
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
    -- v5.1 NEW
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_StatusCode       VARCHAR(20);
    DECLARE v_JoinTypeLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectTypeLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.ValueCode INTO v_StatusCode
    FROM Projects p JOIN LookupValues lv ON p.StatusLkpId = lv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    IF v_StatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        -- Resolve JoinType from RequiresApproval if not supplied
        IF p_JoinTypeLkpId IS NULL AND p_RequiresApproval IS NOT NULL THEN
            SELECT lv.LookupValueId INTO v_JoinTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
              AND lv.ValueCode = IF(p_RequiresApproval = 1, 'APPROVE_REQ', 'OPEN_SIGNUP') LIMIT 1;
        ELSE
            SET v_JoinTypeLkpId = p_JoinTypeLkpId;
        END IF;

        -- Resolve ProjectType from ScheduleType if not supplied
        IF p_ProjectTypeLkpId IS NULL AND p_ScheduleType IS NOT NULL THEN
            SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_ScheduleType LIMIT 1;
        ELSE
            SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
        END IF;

        UPDATE Projects SET
            ProjectName       = COALESCE(p_Title,            ProjectName),
            Description       = COALESCE(p_Description,      Description),
            Category          = COALESCE(p_Category,         Category),
            ProjectTypeLkpId  = COALESCE(v_ProjectTypeLkpId, ProjectTypeLkpId),
            JoinTypeLkpId     = COALESCE(v_JoinTypeLkpId,    JoinTypeLkpId),
            MaxVolunteers     = COALESCE(p_MaxVolunteers,     MaxVolunteers),
            IsPublic          = COALESCE(p_IsPublic,          IsPublic),
            OneTimeDate       = IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, OneTimeDate),
            RecurStart        = IF(p_ScheduleType = 'RECURRING', p_StartDate, RecurStart),
            RecurEnd          = IF(p_ScheduleType = 'RECURRING', p_EndDate,   RecurEnd),
            RecurDays         = IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, RecurDays),
            FlexFromDate      = IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, FlexFromDate),
            FlexToDate        = IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   FlexToDate),
            SessionStartTime  = COALESCE(p_StartTime,         SessionStartTime),
            SessionEndTime    = COALESCE(p_EndTime,           SessionEndTime),
            AddressLine       = COALESCE(p_Address,           AddressLine),
            Landmark          = COALESCE(p_LocationName,      Landmark),
            City              = COALESCE(p_City,              City),
            State             = COALESCE(p_State,             State),
            Latitude          = COALESCE(p_Latitude,          Latitude),
            Longitude         = COALESCE(p_Longitude,         Longitude),
            GoogleMapsUrl     = COALESCE(p_GoogleMapsUrl,     GoogleMapsUrl),
            -- Schedule-override fields: only editable in UPCOMING status
            MinAttendPct      = IF(v_StatusCode = 'UPCOMING', COALESCE(p_MinAttendPct,    MinAttendPct),    MinAttendPct),
            MaxDailyHours     = IF(v_StatusCode = 'UPCOMING', COALESCE(p_MaxDailyHours,   MaxDailyHours),   MaxDailyHours),
            MinSessionHours   = IF(v_StatusCode = 'UPCOMING', COALESCE(p_MinSessionHours, MinSessionHours), MinSessionHours),
            UpdatedBy         = p_UserId,
            UpdatedAt         = NOW()
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.3  Project_GetById (updated: +MinAttendPct, MaxDailyHours,
--       MinSessionHours, TotalSessions)
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        DATE_FORMAT(p.RecurStart,   '%Y-%m-%d') AS RecurStart,
        DATE_FORMAT(p.RecurEnd,     '%Y-%m-%d') AS RecurEnd,
        p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        DATE_FORMAT(p.OneTimeDate,  '%Y-%m-%d') AS OneTimeDate,
        DATE_FORMAT(p.FlexFromDate, '%Y-%m-%d') AS FlexFromDate,
        DATE_FORMAT(p.FlexToDate,   '%Y-%m-%d') AS FlexToDate,
        p.MinHoursRequired,
        p.MinAttendPct, p.MaxDailyHours, p.MinSessionHours,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode  AS StatusCode,   sv.ValueName  AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications
         WHERE ProjectId = p.ProjectId AND IsDeleted = 0
           AND StatusLkpId = (SELECT lv2.LookupValueId FROM LookupValues lv2
                              JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                              WHERE lt2.TypeCode = 'APPLICATION_STATUS' AND lv2.ValueCode = 'APPROVED')
        ) AS ApprovedCount,
        (SELECT COUNT(*) FROM ProjectSessions WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS TotalSessions,
        (SELECT lv2.ValueCode FROM ProjectApplications pa2
         JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId AND pa2.UserId = p_UserId AND pa2.IsDeleted = 0
         LIMIT 1) AS ApplicationStatusCode
    FROM Projects p
    JOIN Organisations  o   ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.4  Certificate_Issue (updated: removed p_TotalHours, computed from DB)
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Certificate_Issue //
CREATE PROCEDURE Certificate_Issue(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_IssuedBy  INT UNSIGNED
)
BEGIN
    DECLARE v_CertCode   VARCHAR(20);
    DECLARE v_TotalHours DECIMAL(6,2) DEFAULT 0;

    -- Compute total attended hours for this volunteer in this project
    SELECT COALESCE(SUM(pa.HoursLogged), 0) INTO v_TotalHours
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId     = ps.SessionId
    JOIN   LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
    JOIN   LookupTypes       lt ON lv.LookupTypeId  = lt.LookupTypeId
    WHERE  ps.ProjectId = p_ProjectId
      AND  pa.UserId    = p_UserId
      AND  lt.TypeCode  = 'ATTENDANCE_STATUS'
      AND  lv.ValueCode = 'ATTENDED';

    SELECT CertCode INTO v_CertCode
    FROM   VolunteerCertificates
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_CertCode IS NOT NULL THEN
        SELECT 1 AS IsSuccess, 'Certificate already issued.' AS Message, v_CertCode AS CertCode;
    ELSE
        UPDATE IdSequences SET LastValue = LastValue + 1
        WHERE  SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
        FROM   IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
        VALUES (v_CertCode, p_ProjectId, p_UserId, p_OrgId, v_TotalHours, p_IssuedBy);

        SELECT 1 AS IsSuccess, 'Certificate issued successfully.' AS Message, v_CertCode AS CertCode;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.5  Project_GenerateSessions (NEW)
--      Called inline by Project_AutoActivate Hangfire job.
--      RECURRING: one session per matching weekday in date range.
--      FLEXIBLE:  one session per calendar day in date range.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_GenerateSessions //
CREATE PROCEDURE Project_GenerateSessions(IN p_ProjectId INT UNSIGNED, IN p_CreatedBy INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode     VARCHAR(20);
    DECLARE v_RecurStart   DATE;
    DECLARE v_RecurEnd     DATE;
    DECLARE v_RecurDays    VARCHAR(100);
    DECLARE v_FlexFrom     DATE;
    DECLARE v_FlexTo       DATE;
    DECLARE v_StartTime    TIME;
    DECLARE v_EndTime      TIME;
    DECLARE v_MaxVol       INT UNSIGNED;
    DECLARE v_CurrDate     DATE;
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_Count        INT DEFAULT 0;
    DECLARE v_DayAbbr      VARCHAR(3);

    SELECT ptv.ValueCode, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate, p.SessionStartTime, p.SessionEndTime, p.MaxVolunteers
    INTO   v_TypeCode, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFrom, v_FlexTo, v_StartTime, v_EndTime, v_MaxVol
    FROM   Projects p
    JOIN   LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    -- Idempotent: skip if already generated
    IF EXISTS (SELECT 1 FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0 LIMIT 1) THEN
        SELECT 1 AS IsSuccess, 'Sessions already generated.' AS Message, 0 AS SessionCount;

    ELSEIF v_TypeCode = 'RECURRING' AND v_RecurStart IS NOT NULL AND v_RecurEnd IS NOT NULL THEN
        SET v_CurrDate = v_RecurStart;
        WHILE v_CurrDate <= v_RecurEnd DO
            SET v_DayAbbr = LEFT(UPPER(DAYNAME(v_CurrDate)), 3);
            IF FIND_IN_SET(v_DayAbbr, UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
                INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, QrCode, SessionStatusLkpId, CreatedBy)
                VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, UUID(), v_UpcomingLkpId, p_CreatedBy);
                SET v_Count = v_Count + 1;
            END IF;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' recurring sessions.') AS Message, v_Count AS SessionCount;

    ELSEIF v_TypeCode = 'FLEXIBLE' AND v_FlexFrom IS NOT NULL AND v_FlexTo IS NOT NULL THEN
        SET v_CurrDate = v_FlexFrom;
        WHILE v_CurrDate <= v_FlexTo DO
            INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
            VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, v_UpcomingLkpId, p_CreatedBy);
            SET v_Count = v_Count + 1;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' flexible sessions.') AS Message, v_Count AS SessionCount;

    ELSE
        SELECT 0 AS IsSuccess, 'Project type does not support session generation or missing schedule data.' AS Message, 0 AS SessionCount;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.6  Project_FlexCheckIn (NEW)
--      FLEXIBLE project self check-in within the session window.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_FlexCheckIn //
CREATE PROCEDURE Project_FlexCheckIn(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode         VARCHAR(20);
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionStart     TIME;
    DECLARE v_SessionEnd       TIME;
    DECLARE v_OpenMins         INT DEFAULT 15;
    DECLARE v_CheckedInLkpId   INT UNSIGNED;
    DECLARE v_InProgressLkpId  INT UNSIGNED;
    DECLARE v_IsApproved       INT DEFAULT 0;
    DECLARE v_AlreadyIn        INT DEFAULT 0;
    DECLARE v_StatusCode       VARCHAR(20);

    -- Verify project type and active status
    SELECT ptv.ValueCode, sv.ValueCode
    INTO   v_TypeCode, v_StatusCode
    FROM   Projects p
    JOIN   LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    JOIN   LookupValues sv  ON p.StatusLkpId      = sv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    IF v_TypeCode != 'FLEXIBLE' THEN
        SELECT 0 AS IsSuccess, 'Self check-in is only available for FLEXIBLE projects.' AS Message, NULL AS SessionId;
    ELSEIF v_StatusCode != 'ACTIVE' THEN
        SELECT 0 AS IsSuccess, 'Project is not currently active.' AS Message, NULL AS SessionId;
    ELSE
        -- Check volunteer is APPROVED
        SELECT COUNT(*) INTO v_IsApproved
        FROM ProjectApplications pa
        JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
          AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED';

        IF v_IsApproved = 0 THEN
            SELECT 0 AS IsSuccess, 'You are not an approved volunteer for this project.' AS Message, NULL AS SessionId;
        ELSE
            -- Read check-in buffer
            SELECT COALESCE(CAST(SettingValue AS UNSIGNED), 15) INTO v_OpenMins
            FROM Settings WHERE SettingKey = 'FLEX_CHECKIN_OPEN_MINUTES' AND IsDeleted = 0 LIMIT 1;

            -- Get today's session
            SELECT ps.SessionId, ps.StartTime, ps.EndTime
            INTO   v_SessionId, v_SessionStart, v_SessionEnd
            FROM   ProjectSessions ps
            WHERE  ps.ProjectId = p_ProjectId AND ps.SessionDate = CURDATE() AND ps.IsDeleted = 0
            LIMIT 1;

            IF v_SessionId IS NULL THEN
                SELECT 0 AS IsSuccess, 'No session is scheduled for today.' AS Message, NULL AS SessionId;
            ELSEIF CURTIME() < SUBTIME(v_SessionStart, SEC_TO_TIME(v_OpenMins * 60)) THEN
                SELECT 0 AS IsSuccess,
                       CONCAT('Check-in opens at ', TIME_FORMAT(SUBTIME(v_SessionStart, SEC_TO_TIME(v_OpenMins * 60)), '%h:%i %p'), '.') AS Message,
                       NULL AS SessionId;
            ELSEIF CURTIME() > v_SessionEnd THEN
                SELECT 0 AS IsSuccess, 'Today''s session has ended. Check-in is closed.' AS Message, NULL AS SessionId;
            ELSE
                -- Check not already checked in
                SELECT COUNT(*) INTO v_AlreadyIn
                FROM ProjectAttendance WHERE SessionId = v_SessionId AND UserId = p_UserId;

                IF v_AlreadyIn > 0 THEN
                    SELECT 0 AS IsSuccess, 'You have already checked in for today''s session.' AS Message, v_SessionId AS SessionId;
                ELSE
                    SELECT lv.LookupValueId INTO v_CheckedInLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

                    SELECT lv.LookupValueId INTO v_InProgressLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'IN_PROGRESS' LIMIT 1;

                    INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
                    VALUES (v_SessionId, p_UserId, NOW(), v_CheckedInLkpId, p_UserId);

                    UPDATE ProjectSessions SET SessionStatusLkpId = v_InProgressLkpId
                    WHERE SessionId = v_SessionId;

                    SELECT 1 AS IsSuccess, 'Checked in successfully.' AS Message, v_SessionId AS SessionId;
                END IF;
            END IF;
        END IF;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.7  Project_FlexCheckOut (NEW)
--      FLEXIBLE project check-out. Computes hours, applies MaxDailyHours cap.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_FlexCheckOut //
CREATE PROCEDURE Project_FlexCheckOut(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode         VARCHAR(20);
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionEnd       TIME;
    DECLARE v_BufferMins       INT DEFAULT 30;
    DECLARE v_CheckedInLkpId   INT UNSIGNED;
    DECLARE v_AttendedLkpId    INT UNSIGNED;
    DECLARE v_AttendId         INT UNSIGNED DEFAULT NULL;
    DECLARE v_CheckInTime      DATETIME;
    DECLARE v_HoursLogged      DECIMAL(6,2) DEFAULT 0;
    DECLARE v_MaxDailyHours    DECIMAL(4,2) DEFAULT NULL;

    SELECT ptv.ValueCode, p.MaxDailyHours INTO v_TypeCode, v_MaxDailyHours
    FROM Projects p JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    IF v_TypeCode != 'FLEXIBLE' THEN
        SELECT 0 AS IsSuccess, 'Check-out is only available for FLEXIBLE projects.' AS Message, 0 AS HoursLogged;
    ELSE
        SELECT COALESCE(CAST(SettingValue AS UNSIGNED), 30) INTO v_BufferMins
        FROM Settings WHERE SettingKey = 'FLEX_CHECKOUT_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;

        SELECT ps.SessionId, ps.EndTime INTO v_SessionId, v_SessionEnd
        FROM ProjectSessions ps
        WHERE ps.ProjectId = p_ProjectId AND ps.SessionDate = CURDATE() AND ps.IsDeleted = 0
        LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No session found for today.' AS Message, 0 AS HoursLogged;
        ELSEIF ADDTIME(v_SessionEnd, SEC_TO_TIME(v_BufferMins * 60)) < CURTIME() THEN
            SELECT 0 AS IsSuccess, 'Check-out window has closed. Your session will be marked as missed.' AS Message, 0 AS HoursLogged;
        ELSE
            SELECT lv.LookupValueId INTO v_CheckedInLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

            SELECT pa.AttendanceId, pa.CheckInTime INTO v_AttendId, v_CheckInTime
            FROM ProjectAttendance pa
            WHERE pa.SessionId = v_SessionId AND pa.UserId = p_UserId
              AND pa.AttendStatusLkpId = v_CheckedInLkpId
            LIMIT 1;

            IF v_AttendId IS NULL THEN
                SELECT 0 AS IsSuccess, 'No active check-in found. Please check in first.' AS Message, 0 AS HoursLogged;
            ELSE
                SELECT lv.LookupValueId INTO v_AttendedLkpId
                FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

                SET v_HoursLogged = ROUND(TIMESTAMPDIFF(MINUTE, v_CheckInTime, NOW()) / 60.0, 2);

                -- Apply MaxDailyHours cap
                IF v_MaxDailyHours IS NOT NULL AND v_HoursLogged > v_MaxDailyHours THEN
                    SET v_HoursLogged = v_MaxDailyHours;
                END IF;

                UPDATE ProjectAttendance
                SET CheckOutTime = NOW(), HoursLogged = v_HoursLogged,
                    AttendStatusLkpId = v_AttendedLkpId, UpdatedAt = NOW()
                WHERE AttendanceId = v_AttendId;

                SELECT 1 AS IsSuccess, 'Checked out successfully.' AS Message, v_HoursLogged AS HoursLogged;
            END IF;
        END IF;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.8  Project_TransitionToClosing (NEW)
--      Called by Hangfire daily job. ACTIVE→CLOSING for projects
--      past their end date + offset.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_TransitionToClosing //
CREATE PROCEDURE Project_TransitionToClosing()
BEGIN
    DECLARE v_ActiveLkpId  INT UNSIGNED;
    DECLARE v_ClosingLkpId INT UNSIGNED;
    DECLARE v_OffsetDays   INT DEFAULT 0;
    DECLARE v_Count        INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 0) INTO v_OffsetDays
    FROM Settings WHERE SettingKey = 'CLOSING_TRIGGER_OFFSET_DAYS' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    -- RECURRING projects past RecurEnd + offset
    UPDATE Projects p
    JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET p.StatusLkpId = v_ClosingLkpId, p.UpdatedAt = NOW()
    WHERE p.StatusLkpId = v_ActiveLkpId AND p.IsDeleted = 0
      AND ptv.ValueCode = 'RECURRING'
      AND p.RecurEnd IS NOT NULL
      AND DATE_ADD(p.RecurEnd, INTERVAL v_OffsetDays DAY) < CURDATE();

    SET v_Count = v_Count + ROW_COUNT();

    -- FLEXIBLE projects past FlexToDate + offset
    UPDATE Projects p
    JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET p.StatusLkpId = v_ClosingLkpId, p.UpdatedAt = NOW()
    WHERE p.StatusLkpId = v_ActiveLkpId AND p.IsDeleted = 0
      AND ptv.ValueCode = 'FLEXIBLE'
      AND p.FlexToDate IS NOT NULL
      AND DATE_ADD(p.FlexToDate, INTERVAL v_OffsetDays DAY) < CURDATE();

    SET v_Count = v_Count + ROW_COUNT();

    SELECT 1 AS IsSuccess,
           CONCAT('Transitioned ', v_Count, ' project(s) to CLOSING.') AS Message,
           v_Count AS TransCount;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.9  Project_FinalizeClosing (NEW)
--      Admin calls when marking project COMPLETED.
--      Aggregates UserSessionSkillRatings → UserSkillRatings (AVG).
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_FinalizeClosing //
CREATE PROCEDURE Project_FinalizeClosing(
    IN p_ProjectId       INT UNSIGNED,
    IN p_CompletedBy     INT UNSIGNED,
    IN p_ImpactSummary   TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId          INT UNSIGNED;
    DECLARE v_CompletedLkpId INT UNSIGNED;
    DECLARE v_CompletedSessionLkpId INT UNSIGNED;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        -- 1. Aggregate per-session ratings → UserSkillRatings (project-level AVG)
        INSERT INTO UserSkillRatings (UserId, OrgId, ProjectId, SkillId, Rating, RatedBy, Notes)
        SELECT
            ssr.UserId,
            v_OrgId,
            p_ProjectId,
            ssr.SkillId,
            ROUND(AVG(ssr.Rating), 2),
            ssr.RatedBy,
            NULL
        FROM UserSessionSkillRatings ssr
        JOIN ProjectSessions ps ON ssr.SessionId = ps.SessionId
        WHERE ps.ProjectId = p_ProjectId
        GROUP BY ssr.UserId, ssr.SkillId, ssr.RatedBy
        ON DUPLICATE KEY UPDATE Rating = ROUND(VALUES(Rating), 2), UpdatedAt = NOW();

        -- 2. Mark all project sessions COMPLETED
        SELECT lv.LookupValueId INTO v_CompletedSessionLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

        UPDATE ProjectSessions SET SessionStatusLkpId = v_CompletedSessionLkpId, UpdatedAt = NOW()
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        -- 3. Transition project → COMPLETED
        SELECT lv.LookupValueId INTO v_CompletedLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

        UPDATE Projects SET
            StatusLkpId      = v_CompletedLkpId,
            CompletedAt      = NOW(),
            CompletedBy      = p_CompletedBy,
            ImpactSummary    = COALESCE(p_ImpactSummary,    ImpactSummary),
            BeneficiaryCount = COALESCE(p_BeneficiaryCount, BeneficiaryCount),
            UpdatedAt        = NOW()
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project finalized and marked as COMPLETED.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.10 Project_AutoActivate (NEW)
--      Hangfire daily job: UPCOMING → ACTIVE + generate sessions.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_AutoActivate //
CREATE PROCEDURE Project_AutoActivate()
BEGIN
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_ActiveLkpId   INT UNSIGNED;
    DECLARE v_LeadDays      INT DEFAULT 0;
    DECLARE v_Count         INT DEFAULT 0;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_Done          INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 0) INTO v_LeadDays
    FROM Settings WHERE SettingKey = 'AUTO_ACTIVATE_LEAD_DAYS' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    BEGIN
        DECLARE proj_cursor CURSOR FOR
            SELECT p.ProjectId
            FROM Projects p
            JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
            WHERE p.StatusLkpId = v_UpcomingLkpId AND p.IsDeleted = 0
              AND ptv.ValueCode IN ('RECURRING', 'FLEXIBLE')
              AND (
                  (ptv.ValueCode = 'RECURRING' AND p.RecurStart IS NOT NULL
                   AND DATE_SUB(p.RecurStart,  INTERVAL v_LeadDays DAY) <= CURDATE())
               OR (ptv.ValueCode = 'FLEXIBLE'  AND p.FlexFromDate IS NOT NULL
                   AND DATE_SUB(p.FlexFromDate, INTERVAL v_LeadDays DAY) <= CURDATE())
              );
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN proj_cursor;
        read_loop: LOOP
            FETCH proj_cursor INTO v_ProjectId;
            IF v_Done THEN LEAVE read_loop; END IF;

            UPDATE Projects SET StatusLkpId = v_ActiveLkpId, UpdatedAt = NOW()
            WHERE ProjectId = v_ProjectId AND IsDeleted = 0;

            CALL Project_GenerateSessions(v_ProjectId, 1);

            SET v_Count = v_Count + 1;
        END LOOP;
        CLOSE proj_cursor;
    END;

    SELECT 1 AS IsSuccess, CONCAT('Activated ', v_Count, ' project(s).') AS Message, v_Count AS ActivatedCount;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.11 Project_MarkNoShows (NEW)
--      Hangfire job: marks RECURRING session absentees as NO_SHOW.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_MarkNoShows //
CREATE PROCEDURE Project_MarkNoShows()
BEGIN
    DECLARE v_NoShowLkpId  INT UNSIGNED;
    DECLARE v_GraceMins    INT DEFAULT 30;
    DECLARE v_Count        INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 30) INTO v_GraceMins
    FROM Settings WHERE SettingKey = 'RECURRING_NOSHOW_GRACE_MINUTES' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    -- Insert NO_SHOW for approved volunteers who missed RECURRING sessions
    INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, CreatedBy)
    SELECT ps.SessionId, appr.UserId, NOW(), 0, v_NoShowLkpId, 1
    FROM ProjectSessions ps
    JOIN Projects p ON ps.ProjectId = p.ProjectId
    JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    -- All APPROVED volunteers for this project
    JOIN (
        SELECT pa.ProjectId, pa.UserId
        FROM ProjectApplications pa
        JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE pa.IsDeleted = 0 AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'
    ) appr ON appr.ProjectId = ps.ProjectId
    WHERE ptv.ValueCode = 'RECURRING'
      AND ps.IsDeleted = 0
      AND ps.SessionDate = CURDATE()
      AND ADDTIME(ps.EndTime, SEC_TO_TIME(v_GraceMins * 60)) < CURTIME()
      -- Not already in attendance table
      AND NOT EXISTS (
          SELECT 1 FROM ProjectAttendance pa2
          WHERE pa2.SessionId = ps.SessionId AND pa2.UserId = appr.UserId
      )
      -- Not opted out
      AND NOT EXISTS (
          SELECT 1 FROM VolunteerSessionOptOuts oo
          WHERE oo.SessionId = ps.SessionId AND oo.UserId = appr.UserId
      )
    ON DUPLICATE KEY UPDATE UpdatedAt = NOW();

    SET v_Count = ROW_COUNT();
    SELECT 1 AS IsSuccess, CONCAT('Marked ', v_Count, ' volunteer(s) as NO_SHOW.') AS Message, v_Count AS NoShowCount;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.12 Project_AutoCheckoutMissed (NEW)
--      Hangfire job: marks FLEXIBLE volunteers who forgot checkout.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_AutoCheckoutMissed //
CREATE PROCEDURE Project_AutoCheckoutMissed()
BEGIN
    DECLARE v_CheckedInLkpId      INT UNSIGNED;
    DECLARE v_CheckoutMissedLkpId INT UNSIGNED;
    DECLARE v_BufferMins          INT DEFAULT 30;
    DECLARE v_Count               INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 30) INTO v_BufferMins
    FROM Settings WHERE SettingKey = 'FLEX_CHECKOUT_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckoutMissedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKOUT_MISSED' LIMIT 1;

    UPDATE ProjectAttendance pa
    JOIN   ProjectSessions  ps  ON pa.SessionId = ps.SessionId
    JOIN   Projects          p   ON ps.ProjectId = p.ProjectId
    JOIN   LookupValues      ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET    pa.CheckOutTime       = ADDTIME(ps.EndTime, SEC_TO_TIME(v_BufferMins * 60)),
           pa.HoursLogged        = 0,
           pa.AttendStatusLkpId  = v_CheckoutMissedLkpId,
           pa.UpdatedAt          = NOW()
    WHERE  ptv.ValueCode = 'FLEXIBLE'
      AND  pa.AttendStatusLkpId = v_CheckedInLkpId
      AND  ps.SessionDate = CURDATE()
      AND  ADDTIME(ps.EndTime, SEC_TO_TIME(v_BufferMins * 60)) < CURTIME();

    SET v_Count = ROW_COUNT();
    SELECT 1 AS IsSuccess, CONCAT('Marked ', v_Count, ' volunteer(s) as CHECKOUT_MISSED.') AS Message, v_Count AS Count;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.13 Project_GetVolunteerEligibility (NEW)
--      Returns attendance stats + certificate eligibility for a volunteer.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_GetVolunteerEligibility //
CREATE PROCEDURE Project_GetVolunteerEligibility(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalSessions   INT DEFAULT 0;
    DECLARE v_EligSessions    INT DEFAULT 0;
    DECLARE v_AttendedCount   INT DEFAULT 0;
    DECLARE v_HoursLogged     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_MinAttendPct    DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_ApprovalDate    DATETIME DEFAULT NULL;
    DECLARE v_AttendPct       DECIMAL(5,2) DEFAULT 0;
    DECLARE v_IsEligible      TINYINT(1) DEFAULT 0;
    DECLARE v_AttendedLkpId   INT UNSIGNED;

    SELECT p.MinAttendPct INTO v_MinAttendPct
    FROM Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    SELECT pa.StatusUpdatedAt INTO v_ApprovalDate
    FROM ProjectApplications pa
    JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    -- Eligible = sessions on/after approval date (mid-project join rule)
    SELECT COUNT(*) INTO v_EligSessions
    FROM ProjectSessions ps
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
      AND (v_ApprovalDate IS NULL OR ps.SessionDate >= DATE(v_ApprovalDate));

    SELECT COUNT(*), COALESCE(SUM(pa.HoursLogged), 0)
    INTO   v_AttendedCount, v_HoursLogged
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE  ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND  pa.AttendStatusLkpId = v_AttendedLkpId;

    IF v_EligSessions > 0 THEN
        SET v_AttendPct = ROUND((v_AttendedCount / v_EligSessions) * 100, 2);
    END IF;

    SET v_IsEligible = IF(v_MinAttendPct IS NULL OR v_AttendPct >= v_MinAttendPct, 1, 0);

    SELECT
        v_TotalSessions  AS TotalSessions,
        v_EligSessions   AS EligibleSessions,
        v_AttendedCount  AS AttendedCount,
        v_HoursLogged    AS TotalHoursLogged,
        v_AttendPct      AS AttendancePct,
        v_MinAttendPct   AS MinAttendPct,
        v_IsEligible     AS IsEligibleForCert;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.14 Project_GetMySessionList (NEW)
--      Per-session breakdown for a volunteer in a project.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_GetMySessionList //
CREATE PROCEDURE Project_GetMySessionList(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ps.SessionId,
        DATE_FORMAT(ps.SessionDate, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(ps.StartTime, '%H:%i')      AS StartTime,
        TIME_FORMAT(ps.EndTime,   '%H:%i')      AS EndTime,
        ssv.ValueCode  AS SessionStatus,
        ssv.ValueName  AS SessionStatusName,
        pa.CheckInTime,
        pa.CheckOutTime,
        pa.HoursLogged,
        asv.ValueCode  AS AttendanceStatus,
        asv.ValueName  AS AttendanceStatusName,
        pa.IsNoShowExcused,
        pa.AdminNote,
        oo.OptOutId,
        oov.ValueCode  AS OptOutType,
        oov.ValueName  AS OptOutTypeName,
        oo.Reason      AS OptOutReason,
        (SELECT COUNT(*) FROM UserSessionSkillRatings ssr WHERE ssr.SessionId = ps.SessionId AND ssr.UserId = p_UserId) AS RatingCount
    FROM   ProjectSessions ps
    LEFT JOIN ProjectAttendance       pa  ON pa.SessionId  = ps.SessionId AND pa.UserId = p_UserId
    LEFT JOIN VolunteerSessionOptOuts oo  ON oo.SessionId  = ps.SessionId AND oo.UserId = p_UserId
    LEFT JOIN LookupValues            ssv ON ps.SessionStatusLkpId  = ssv.LookupValueId
    LEFT JOIN LookupValues            asv ON pa.AttendStatusLkpId   = asv.LookupValueId
    LEFT JOIN LookupValues            oov ON oo.OptOutTypeLkpId     = oov.LookupValueId
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate ASC, ps.StartTime ASC;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.15 Session_Cancel (NEW — admin)
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Session_Cancel //
CREATE PROCEDURE Session_Cancel(
    IN p_SessionId   INT UNSIGNED,
    IN p_CancelledBy INT UNSIGNED,
    IN p_Reason      TEXT
)
BEGIN
    DECLARE v_CancelledLkpId INT UNSIGNED;
    DECLARE v_Exists         INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_CancelledLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

        UPDATE ProjectSessions
        SET SessionStatusLkpId = v_CancelledLkpId, UpdatedBy = p_CancelledBy, UpdatedAt = NOW()
        WHERE SessionId = p_SessionId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Session cancelled successfully.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.16 Session_OptOut (NEW — volunteer or admin)
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Session_OptOut //
CREATE PROCEDURE Session_OptOut(
    IN p_SessionId   INT UNSIGNED,
    IN p_UserId      INT UNSIGNED,
    IN p_OptOutType  VARCHAR(20),
    IN p_Reason      TEXT,
    IN p_CreatedBy   INT UNSIGNED
)
BEGIN
    DECLARE v_OptOutTypeLkpId INT UNSIGNED;
    DECLARE v_ProjectId       INT UNSIGNED;

    SELECT ps.ProjectId INTO v_ProjectId
    FROM ProjectSessions ps WHERE ps.SessionId = p_SessionId AND ps.IsDeleted = 0;

    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_OptOutTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE'
          AND lv.ValueCode = COALESCE(p_OptOutType, 'SELF') LIMIT 1;

        INSERT INTO VolunteerSessionOptOuts (SessionId, UserId, ProjectId, OptOutTypeLkpId, Reason, CreatedBy)
        VALUES (p_SessionId, p_UserId, v_ProjectId, v_OptOutTypeLkpId, p_Reason, p_CreatedBy)
        ON DUPLICATE KEY UPDATE OptOutTypeLkpId = v_OptOutTypeLkpId, Reason = p_Reason;

        SELECT 1 AS IsSuccess, 'Opt-out recorded successfully.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.17 Certificate_IssueBulk (NEW)
--      Issues certificates to all eligible volunteers in one call.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Certificate_IssueBulk //
CREATE PROCEDURE Certificate_IssueBulk(
    IN p_ProjectId INT UNSIGNED,
    IN p_IssuedBy  INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED
)
BEGIN
    DECLARE v_UserId           INT UNSIGNED;
    DECLARE v_IssuedCount      INT DEFAULT 0;
    DECLARE v_SkippedCount     INT DEFAULT 0;
    DECLARE v_MinAttendPct     DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_TotalSessions    INT DEFAULT 0;
    DECLARE v_AttendedCount    INT DEFAULT 0;
    DECLARE v_AttendPct        DECIMAL(5,2) DEFAULT 0;
    DECLARE v_TotalHours       DECIMAL(6,2) DEFAULT 0;
    DECLARE v_CertCode         VARCHAR(20);
    DECLARE v_Done             INT DEFAULT 0;
    DECLARE v_AttendedLkpId    INT UNSIGNED;

    SELECT MinAttendPct INTO v_MinAttendPct FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    BEGIN
        DECLARE vol_cursor CURSOR FOR
            SELECT pa.UserId FROM ProjectApplications pa
            JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
            JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
              AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED';
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN vol_cursor;
        read_loop: LOOP
            FETCH vol_cursor INTO v_UserId;
            IF v_Done THEN LEAVE read_loop; END IF;

            -- Skip if cert already issued
            IF EXISTS (SELECT 1 FROM VolunteerCertificates WHERE ProjectId = p_ProjectId AND UserId = v_UserId AND IsDeleted = 0) THEN
                SET v_SkippedCount = v_SkippedCount + 1;
            ELSE
                SELECT COUNT(*), COALESCE(SUM(pa2.HoursLogged), 0)
                INTO   v_AttendedCount, v_TotalHours
                FROM   ProjectAttendance pa2
                JOIN   ProjectSessions   ps2 ON pa2.SessionId = ps2.SessionId
                WHERE  ps2.ProjectId = p_ProjectId AND pa2.UserId = v_UserId
                  AND  pa2.AttendStatusLkpId = v_AttendedLkpId;

                SET v_AttendPct = IF(v_TotalSessions > 0, ROUND((v_AttendedCount / v_TotalSessions) * 100, 2), 0);

                IF v_MinAttendPct IS NULL OR v_AttendPct >= v_MinAttendPct THEN
                    UPDATE IdSequences SET LastValue = LastValue + 1
                    WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

                    SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
                    FROM IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

                    INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
                    VALUES (v_CertCode, p_ProjectId, v_UserId, p_OrgId, v_TotalHours, p_IssuedBy);

                    SET v_IssuedCount = v_IssuedCount + 1;
                ELSE
                    SET v_SkippedCount = v_SkippedCount + 1;
                END IF;
            END IF;
        END LOOP;
        CLOSE vol_cursor;
    END;

    SELECT 1 AS IsSuccess,
           CONCAT('Issued ', v_IssuedCount, ' certificate(s). Skipped ', v_SkippedCount, '.') AS Message,
           v_IssuedCount AS IssuedCount,
           v_SkippedCount AS SkippedCount;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.18 UserSessionSkillRating_AddUpdate (NEW)
--      Admin rates a volunteer's skill for a specific session.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS UserSessionSkillRating_AddUpdate //
CREATE PROCEDURE UserSessionSkillRating_AddUpdate(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_SkillId   INT UNSIGNED,
    IN p_Rating    DECIMAL(3,2),
    IN p_RatedBy   INT UNSIGNED,
    IN p_Notes     TEXT
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;

    SELECT ProjectId INTO v_ProjectId FROM ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0;

    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        INSERT INTO UserSessionSkillRatings (SessionId, UserId, ProjectId, SkillId, Rating, RatedBy, Notes)
        VALUES (p_SessionId, p_UserId, v_ProjectId, p_SkillId, p_Rating, p_RatedBy, p_Notes)
        ON DUPLICATE KEY UPDATE Rating = p_Rating, Notes = p_Notes, RatedBy = p_RatedBy, UpdatedAt = NOW();

        SELECT 1 AS IsSuccess, 'Session skill rating saved.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- 5.19 Project_CheckMilestoneNotification (NEW)
--      Returns current attendance % and which milestone was crossed
--      (25 / 50 / 75). C# caller decides if push is needed.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_CheckMilestoneNotification //
CREATE PROCEDURE Project_CheckMilestoneNotification(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalSessions INT DEFAULT 0;
    DECLARE v_AttendedCount INT DEFAULT 0;
    DECLARE v_AttendPct     DECIMAL(5,2) DEFAULT 0;
    DECLARE v_Milestone     INT DEFAULT 0;
    DECLARE v_AttendedLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_AttendedCount
    FROM ProjectAttendance pa
    JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND pa.AttendStatusLkpId = v_AttendedLkpId;

    IF v_TotalSessions > 0 THEN
        SET v_AttendPct = ROUND((v_AttendedCount / v_TotalSessions) * 100, 2);
    END IF;

    SET v_Milestone = CASE
        WHEN v_AttendPct >= 75 THEN 75
        WHEN v_AttendPct >= 50 THEN 50
        WHEN v_AttendPct >= 25 THEN 25
        ELSE 0
    END;

    SELECT
        v_TotalSessions AS TotalSessions,
        v_AttendedCount AS AttendedCount,
        v_AttendPct     AS AttendancePct,
        v_Milestone     AS MilestoneReached;
END //

DELIMITER ;

-- ═══════════════════════════════════════════════════════════════
-- END OF PATCH v5.1
-- ═══════════════════════════════════════════════════════════════
INSERT IGNORE INTO SchemaVersion (Version, Description, AppliedBy)
VALUES ('v5.1', 'RECURRING + FLEXIBLE project flow: 3 new Projects columns, 2 new tables (UserSessionSkillRatings, VolunteerSessionOptOuts), new lookups (CLOSING, CHECKED_IN, CHECKOUT_MISSED, SESSION_OPT_OUT_TYPE), 15 new settings, 4 updated SPs, 15 new SPs.', 'System');

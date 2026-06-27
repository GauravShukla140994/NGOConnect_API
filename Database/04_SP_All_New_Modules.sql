-- ============================================================
-- NGO Connect — All New Module Stored Procedures
-- File: 04_SP_All_New_Modules.sql  |  v2.1 — DB-Aligned
-- Covers: Settings, Organisations, Projects, Applications,
--         Posts/Feed, Community/Polls, Donations, SOS, Notifications
-- Run after: NGOConnect_DB_Complete_Setup.sql
-- ============================================================
--
-- DB COLUMN CORRECTIONS vs v2.0 (key changes):
--   Users.Mobile            (not MobileNumber)
--   UserProfiles.Bio        (not About), ProfilePhoto (not ProfilePhotoUrl)
--   UserSkills              text-based (SkillName), no LkpId FKs
--   Organisations.RegNumber (not RegistrationNo), OrgTypeLkpId (not OrgTypeId)
--   Organisations.ContactEmail/ContactPhone (not Email/Phone)
--   Organisations.StatusLkpId INT FK (not IsVerified BOOL)
--   OrgMembers.RoleLkpId + StatusLkpId INT FK (not Role VARCHAR)
--   Projects.ProjectName    (not Title)
--   Projects.StatusLkpId/ProjectTypeLkpId/LocationTypeLkpId/JoinTypeLkpId INT FK
--   ProjectSessions: SessionDate DATE + StartTime TIME + EndTime TIME (no Title/Location)
--   ProjectSessions.SessionStatusLkpId INT FK, QrCode UUID-based
--   ProjectApplications.Motivation (not Note), StatusLkpId INT FK
--   Posts.PostTypeLkpId + VisibilityLkpId INT FK (not PostType VARCHAR)
--   PostMedia.FileUrl + MediaTypeLkpId INT FK (not MediaUrl)
--   PostReports.ReasonLkpId + StatusLkpId INT FK, ReportedByUserId (not UserId)
--   CommunityPosts.Title (NOT NULL), PostTypeLkpId, AudienceLkpId INT FK (no Tags)
--   CommunityPosts.PollEndsAt (not ExpiresAt), no IsPoll column
--   DonationCampaigns.CampaignName (not Title), TargetAmount (not GoalAmount)
--   DonationCampaigns.CampaignTypeLkpId + StatusLkpId + VisibilityLkpId INT FK
--   DonationTransactions: DonationId (not DonationRef), DonorUserId (not UserId)
--   DonationTransactions.DonationAmount, GatewayOrderId, PayStatusLkpId INT FK
--   RecurringDonations.RecurringDonId PK, DonorUserId, FrequencyLkpId+StatusLkpId INT FK
--   RecurringDonations.NextChargeDate DATE (not NextRunAt DATETIME)
--   IdSequences: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
--   SosIncidents.SosIncidentId PK, AlertTypeLkpId + StatusLkpId INT FK (not SosId/SosType/Status)
--   SosResponders.SosIncidentId (not SosId), ApprovalStatusLkpId INT FK
--   SosLocationLogs.SosIncidentId (not SosId)
--   Notifications: RefId (not EntityId), no IsDeleted column
-- ============================================================

-- ============================================================
-- CREATE TABLES NOT IN NGOConnect_DB_Complete_Setup.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS Settings (
    SettingId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SettingGroup VARCHAR(50)   NOT NULL,
    SettingKey   VARCHAR(100)  NOT NULL,
    SettingValue TEXT          NOT NULL,
    DataType     VARCHAR(20)   NOT NULL DEFAULT 'STRING',
    Description  VARCHAR(500)  NULL,
    IsPublic     TINYINT(1)    NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)    NOT NULL DEFAULT 0,
    UpdatedAt    DATETIME      NULL,
    UpdatedBy    INT UNSIGNED  NULL,
    PRIMARY KEY (SettingId),
    UNIQUE KEY uq_settings_key (SettingKey, IsDeleted),
    INDEX idx_settings_group  (SettingGroup),
    INDEX idx_settings_public (IsPublic)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS UserDeviceTokens (
    DeviceTokenId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId        INT UNSIGNED NOT NULL,
    Token         VARCHAR(512) NOT NULL,
    Platform      VARCHAR(20)  NOT NULL DEFAULT 'ANDROID',  -- ANDROID / IOS / WEB
    CreatedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt     DATETIME     NULL,
    PRIMARY KEY (DeviceTokenId),
    UNIQUE KEY uq_device_user_platform (UserId, Platform),
    INDEX idx_device_user (UserId),
    CONSTRAINT fk_devicetoken_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================
-- SEED: Settings
-- ============================================================

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('OTP',        'OTP_EXPIRY_MINUTES',   '10',                      'NUMBER',  'OTP expiry in minutes',                 0),
('OTP',        'OTP_MAX_ATTEMPTS',     '3',                       'NUMBER',  'Max OTP verification attempts',         0),
('OTP',        'OTP_RATE_LIMIT',       '3',                       'NUMBER',  'Max OTPs per 10 minutes per recipient', 0),
('AUTH',       'JWT_EXPIRY_MINUTES',   '15',                      'NUMBER',  'JWT access token expiry in minutes',    0),
('AUTH',       'REFRESH_EXPIRY_DAYS',  '30',                      'NUMBER',  'Refresh token expiry in days',          0),
('AUTH',       'MAX_SESSIONS',         '5',                       'NUMBER',  'Max concurrent sessions per user',      0),
('PAGINATION', 'DEFAULT_PAGE_SIZE',    '20',                      'NUMBER',  'Default page size for list APIs',       1),
('PAGINATION', 'MAX_PAGE_SIZE',        '100',                     'NUMBER',  'Maximum allowed page size',             1),
('PLATFORM',   'APP_NAME',             'NGO Connect',             'STRING',  'Platform display name',                 1),
('PLATFORM',   'SUPPORT_EMAIL',        'support@ngoconnect.app',  'STRING',  'Support email address',                 1),
('FEATURE',    'SOS_ENABLED',          'true',                    'BOOLEAN', 'Toggle SOS feature on/off',             0),
('FEATURE',    'DONATIONS_ENABLED',    'true',                    'BOOLEAN', 'Toggle donations feature on/off',       0),
('DONATION',   'MIN_DONATION_AMOUNT',  '10',                      'NUMBER',  'Minimum donation amount in INR',        1),
('DONATION',   'RAZORPAY_KEY_ID',      'rzp_test_xxxx',           'STRING',  'Razorpay Key ID (public)',              1),
('UPLOAD',     'MAX_FILE_SIZE_MB',     '10',                      'NUMBER',  'Maximum file upload size in MB',        1);


DELIMITER //

-- ============================================================
-- SETTINGS MODULE
-- ============================================================

DROP PROCEDURE IF EXISTS Settings_GetPublic //
CREATE PROCEDURE Settings_GetPublic()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description
    FROM   Settings
    WHERE  IsPublic = 1 AND IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_GetByGroup //
CREATE PROCEDURE Settings_GetByGroup(IN p_SettingGroup VARCHAR(50))
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  SettingGroup = p_SettingGroup AND IsDeleted = 0
    ORDER  BY SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_GetAll //
CREATE PROCEDURE Settings_GetAll()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_Update //
CREATE PROCEDURE Settings_Update(
    IN p_SettingKey   VARCHAR(100),
    IN p_SettingValue TEXT,
    IN p_UpdatedBy    INT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Settings WHERE SettingKey = p_SettingKey AND IsDeleted = 0) THEN
        SELECT 0 AS IsSuccess, 'Setting key not found.' AS Message;
    ELSE
        UPDATE Settings
        SET    SettingValue = p_SettingValue,
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UpdatedBy
        WHERE  SettingKey   = p_SettingKey AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Setting updated successfully.' AS Message;
    END IF;
END //


-- ============================================================
-- ORGANISATIONS MODULE
-- DB notes: RegNumber (not RegistrationNo), OrgTypeLkpId (not OrgTypeId),
--           ContactEmail (not Email), ContactPhone (not Phone),
--           StatusLkpId INT FK (not IsVerified BOOL)
--           OrgMembers: RoleLkpId + StatusLkpId INT FK (not Role VARCHAR)
-- ============================================================

DROP PROCEDURE IF EXISTS Org_Register //
CREATE PROCEDURE Org_Register(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgName        VARCHAR(200),
    IN p_RegistrationNo VARCHAR(100),    -- API param; maps to DB column: RegNumber
    IN p_Category       VARCHAR(100),
    IN p_About          TEXT,
    IN p_Website        VARCHAR(255),
    IN p_Phone          VARCHAR(20),     -- API param; maps to DB column: ContactPhone
    IN p_Email          VARCHAR(150),    -- API param; maps to DB column: ContactEmail
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Country        VARCHAR(100),
    IN p_OrgTypeLkpId   INT UNSIGNED    -- was p_OrgTypeId
)
BEGIN
    DECLARE v_PendingStatusId INT UNSIGNED DEFAULT 0;
    DECLARE v_FounderRoleId   INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedMemStatus INT UNSIGNED DEFAULT 0;
    DECLARE v_Duplicate       INT DEFAULT 0;

    -- Check duplicate registration number
    IF p_RegistrationNo IS NOT NULL THEN
        SELECT COUNT(*) INTO v_Duplicate FROM Organisations
        WHERE  RegNumber = p_RegistrationNo AND IsDeleted = 0;
    END IF;

    IF v_Duplicate > 0 THEN
        SELECT 0 AS IsSuccess, 'Organisation with this registration number already exists.' AS Message, NULL AS OrgId;
    ELSE
        -- Resolve status LkpIds from LookupValues
        SELECT lv.LookupValueId INTO v_PendingStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        SELECT lv.LookupValueId INTO v_FounderRoleId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1;

        SELECT lv.LookupValueId INTO v_ApprovedMemStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        -- Fallback to 1 if seed not present
        IF v_PendingStatusId = 0 THEN SET v_PendingStatusId = 1; END IF;
        IF v_FounderRoleId   = 0 THEN SET v_FounderRoleId   = 1; END IF;
        IF v_ApprovedMemStatus = 0 THEN SET v_ApprovedMemStatus = 1; END IF;

        INSERT INTO Organisations (
            OrgName, RegNumber, OrgTypeLkpId, Category,
            About, Website, ContactPhone, ContactEmail,
            City, State, Country, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgName, p_RegistrationNo, p_OrgTypeLkpId, COALESCE(p_Category, 'Community Service'),
            p_About, p_Website, p_Phone, p_Email,
            p_City, p_State, COALESCE(p_Country, 'India'), v_PendingStatusId, p_UserId
        );

        SET @NewOrgId = LAST_INSERT_ID();

        -- Add registering user as FOUNDER with APPROVED status
        INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
        VALUES (@NewOrgId, p_UserId, v_FounderRoleId, v_ApprovedMemStatus, NOW(), p_UserId);

        -- Initialise org donation settings row
        INSERT INTO OrgDonationSettings (OrgId, KycStatusLkpId)
        SELECT @NewOrgId,
               (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'KYC_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1);

        SELECT 1 AS IsSuccess, 'Organisation registered successfully. Pending verification.' AS Message, @NewOrgId AS OrgId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category,
        o.About, o.Mission, o.Vision,
        o.Website, o.ContactPhone, o.ContactEmail,
        o.City, o.State, o.Country, o.LogoUrl,
        lv_type.ValueName   AS OrgType,
        lv_status.ValueName AS OrgStatus,
        o.CreatedAt,
        (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = o.OrgId AND IsDeleted = 0) AS MemberCount
    FROM   Organisations o
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = o.OrgTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = o.StatusLkpId
    WHERE  o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Org_Update //
CREATE PROCEDURE Org_Update(
    IN p_OrgId   INT UNSIGNED,
    IN p_UserId  INT UNSIGNED,
    IN p_About   TEXT,
    IN p_Website VARCHAR(255),
    IN p_Phone   VARCHAR(20),
    IN p_City    VARCHAR(100),
    IN p_State   VARCHAR(100),
    IN p_Country VARCHAR(100)
)
BEGIN
    DECLARE v_IsAdmin INT DEFAULT 0;

    -- Check caller has ADMIN or FOUNDER role in this org (with APPROVED member status)
    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can update.' AS Message;
    ELSE
        UPDATE Organisations
        SET    About        = COALESCE(p_About,   About),
               Website      = COALESCE(p_Website, Website),
               ContactPhone = COALESCE(p_Phone,   ContactPhone),
               City         = COALESCE(p_City,    City),
               State        = COALESCE(p_State,   State),
               Country      = COALESCE(p_Country, Country),
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UserId
        WHERE  OrgId = p_OrgId AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Organisation updated successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT o.OrgId, o.OrgName, o.Category, o.City, o.State, o.LogoUrl,
           lv_type.ValueName   AS OrgType,
           lv_status.ValueName AS OrgStatus,
           (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = o.OrgId AND IsDeleted = 0) AS MemberCount
    FROM   Organisations o
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = o.OrgTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = o.StatusLkpId
    WHERE  o.IsDeleted = 0
      AND  (p_Search IS NULL
            OR o.OrgName   LIKE CONCAT('%', p_Search, '%')
            OR o.City      LIKE CONCAT('%', p_Search, '%')
            OR o.Category  LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY o.OrgName
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Organisations o
    WHERE  o.IsDeleted = 0
      AND  (p_Search IS NULL
            OR o.OrgName  LIKE CONCAT('%', p_Search, '%')
            OR o.City     LIKE CONCAT('%', p_Search, '%')
            OR o.Category LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Org_GetMembers //
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,                          -- was AvatarUrl
        lv_role.ValueName   AS RoleCode,
        lv_status.ValueName AS StatusCode,
        om.JoinedAt
    FROM   OrgMembers om
    JOIN   UserProfiles up ON up.UserId = om.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues lv_role   ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = om.StatusLkpId
    WHERE  om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER  BY om.JoinedAt;
END //

DROP PROCEDURE IF EXISTS Org_AddMember //
CREATE PROCEDURE Org_AddMember(
    IN p_OrgId         INT UNSIGNED,
    IN p_RequestedBy   INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_RoleLkpId     INT UNSIGNED    -- was p_Role VARCHAR
)
BEGIN
    DECLARE v_IsAdmin        INT DEFAULT 0;
    DECLARE v_Exists         INT DEFAULT 0;
    DECLARE v_ApprovedStatus INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RequestedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    SELECT COUNT(*) INTO v_Exists
    FROM   OrgMembers WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can add members.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'User is already a member of this organisation.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_ApprovedStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        IF v_ApprovedStatus = 0 THEN SET v_ApprovedStatus = 1; END IF;

        INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
        VALUES (p_OrgId, p_UserId, p_RoleLkpId, v_ApprovedStatus, NOW(), p_RequestedBy);

        SELECT 1 AS IsSuccess, 'Member added successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_RemoveMember //
CREATE PROCEDURE Org_RemoveMember(
    IN p_OrgId        INT UNSIGNED,
    IN p_RequestedBy  INT UNSIGNED,
    IN p_OrgMemberId  INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin INT DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RequestedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can remove members.' AS Message;
    ELSE
        UPDATE OrgMembers
        SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_RequestedBy
        WHERE  OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Member removed successfully.' AS Message;
    END IF;
END //


-- ============================================================
-- PROJECTS + SESSIONS MODULE
-- DB notes: ProjectName (not Title), StatusLkpId/ProjectTypeLkpId/
--           LocationTypeLkpId/JoinTypeLkpId INT FK
--           ProjectSessions: SessionDate DATE, StartTime TIME, EndTime TIME
--           No Title/Location columns on ProjectSessions
--           SessionStatusLkpId INT FK required
-- ============================================================

DROP PROCEDURE IF EXISTS Project_Create //
CREATE PROCEDURE Project_Create(
    IN p_UserId             INT UNSIGNED,
    IN p_OrgId              INT UNSIGNED,
    IN p_Title              VARCHAR(200),   -- API param; maps to DB column: ProjectName
    IN p_Category           VARCHAR(100),
    IN p_Description        TEXT,
    IN p_City               VARCHAR(100),
    IN p_State              VARCHAR(100),
    IN p_ProjectTypeLkpId   INT UNSIGNED,
    IN p_LocationTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId      INT UNSIGNED,
    IN p_MaxVolunteers      INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin       INT DEFAULT 0;
    DECLARE v_DraftStatusId INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/moderator can create projects.' AS Message, NULL AS ProjectId;
    ELSE
        SELECT lv.LookupValueId INTO v_DraftStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

        IF v_DraftStatusId = 0 THEN SET v_DraftStatusId = 1; END IF;

        INSERT INTO Projects (
            OrgId, ProjectName, Category, Description,
            City, State,
            ProjectTypeLkpId, LocationTypeLkpId, JoinTypeLkpId,
            MaxVolunteers, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgId,
            p_Title,                    -- inserted into ProjectName
            COALESCE(p_Category, 'Community Service'),
            p_Description,
            p_City, p_State,
            p_ProjectTypeLkpId, p_LocationTypeLkpId, p_JoinTypeLkpId,
            p_MaxVolunteers,
            v_DraftStatusId,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName,
        p.ProjectName,                  -- not Title
        p.Category, p.Description,
        p.City, p.State,
        lv_type.ValueName   AS ProjectType,
        lv_loc.ValueName    AS LocationType,
        lv_join.ValueName   AS JoinType,
        lv_status.ValueName AS Status,
        p.MaxVolunteers,
        p.IsPublic,
        p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS AppliedCount
    FROM   Projects p
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = p.ProjectTypeLkpId
    LEFT   JOIN LookupValues lv_loc    ON lv_loc.LookupValueId    = p.LocationTypeLkpId
    LEFT   JOIN LookupValues lv_join   ON lv_join.LookupValueId   = p.JoinTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = p.StatusLkpId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Project_Update //
CREATE PROCEDURE Project_Update(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_Title        VARCHAR(200),
    IN p_Description  TEXT,
    IN p_City         VARCHAR(100),
    IN p_State        VARCHAR(100),
    IN p_MaxVolunteers INT UNSIGNED,
    IN p_StatusLkpId  INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId   INT UNSIGNED;
    DECLARE v_IsAdmin INT DEFAULT 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message;
    ELSE
        UPDATE Projects
        SET    ProjectName    = COALESCE(p_Title,         ProjectName),
               Description    = COALESCE(p_Description,   Description),
               City           = COALESCE(p_City,          City),
               State          = COALESCE(p_State,         State),
               MaxVolunteers  = COALESCE(p_MaxVolunteers, MaxVolunteers),
               StatusLkpId    = COALESCE(p_StatusLkpId,   StatusLkpId),
               UpdatedAt      = NOW(),
               UpdatedBy      = p_UserId
        WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Project updated.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.ProjectId, p.OrgId, o.OrgName,
        p.ProjectName, p.Category, p.City, p.State,
        lv_status.ValueName AS Status,
        p.MaxVolunteers,
        p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS AppliedCount
    FROM   Projects p
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = p.StatusLkpId
    WHERE  p.IsDeleted = 0 AND p.IsPublic = 1
      AND  (p_OrgId  IS NULL OR p.OrgId = p_OrgId)
      AND  (p_Search IS NULL
            OR p.ProjectName LIKE CONCAT('%', p_Search, '%')
            OR p.City        LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Projects p
    WHERE  p.IsDeleted = 0 AND p.IsPublic = 1
      AND  (p_OrgId  IS NULL OR p.OrgId = p_OrgId)
      AND  (p_Search IS NULL
            OR p.ProjectName LIKE CONCAT('%', p_Search, '%')
            OR p.City        LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Project_AddSession //
CREATE PROCEDURE Project_AddSession(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_SessionDate  DATE,
    IN p_StartTime    VARCHAR(5),   -- "HH:mm" from CreateSessionRequest.StartTime
    IN p_EndTime      VARCHAR(5),   -- "HH:mm" from CreateSessionRequest.EndTime
    IN p_MaxVolunteers INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId          INT UNSIGNED;
    DECLARE v_IsAdmin        INT DEFAULT 0;
    DECLARE v_UpcomingStatus INT UNSIGNED DEFAULT 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message, NULL AS SessionId;
    ELSE
        SELECT lv.LookupValueId INTO v_UpcomingStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

        IF v_UpcomingStatus = 0 THEN SET v_UpcomingStatus = 1; END IF;

        SET @QrCode = UUID();   -- UUID as session QR (not SHA256 hash)

        -- DB columns: SessionDate DATE, StartTime TIME, EndTime TIME, QrCode, QrExpiresAt, SessionStatusLkpId
        INSERT INTO ProjectSessions (
            ProjectId, SessionDate, StartTime, EndTime,
            MaxVolunteers, QrCode, QrExpiresAt, SessionStatusLkpId, CreatedBy
        )
        VALUES (
            p_ProjectId,
            p_SessionDate,
            STR_TO_DATE(p_StartTime, '%H:%i'),
            STR_TO_DATE(p_EndTime,   '%H:%i'),
            p_MaxVolunteers,
            @QrCode,
            DATE_ADD(CONCAT(p_SessionDate, ' ', p_EndTime), INTERVAL 30 MINUTE),
            v_UpcomingStatus,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Session added successfully.' AS Message, LAST_INSERT_ID() AS SessionId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_GetSessions //
CREATE PROCEDURE Project_GetSessions(IN p_ProjectId INT UNSIGNED)
BEGIN
    SELECT
        ps.SessionId, ps.ProjectId,
        ps.SessionDate, ps.StartTime, ps.EndTime,
        ps.MaxVolunteers, ps.QrCode, ps.QrExpiresAt,
        lv_status.ValueName AS SessionStatus,
        (SELECT COUNT(*) FROM ProjectAttendance WHERE SessionId = ps.SessionId) AS AttendeeCount
    FROM   ProjectSessions ps
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = ps.SessionStatusLkpId
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate, ps.StartTime;
END //

DROP PROCEDURE IF EXISTS Project_GetSessionQr //
CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;
    DECLARE v_OrgId     INT UNSIGNED;
    DECLARE v_IsAdmin   INT DEFAULT 0;

    SELECT ProjectId INTO v_ProjectId FROM ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0;
    SELECT OrgId     INTO v_OrgId     FROM Projects WHERE ProjectId = v_ProjectId;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT NULL AS SessionId, NULL AS QrCode, NULL AS SessionDate;
    ELSE
        SELECT ps.SessionId, ps.QrCode, ps.QrExpiresAt,
               ps.SessionDate, ps.StartTime, ps.EndTime
        FROM   ProjectSessions ps
        WHERE  ps.SessionId = p_SessionId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_CheckIn //
CREATE PROCEDURE Project_CheckIn(
    IN p_UserId  INT UNSIGNED,
    IN p_QrToken VARCHAR(100)   -- matches QrCode UUID in ProjectSessions
)
BEGIN
    DECLARE v_SessionId      INT UNSIGNED;
    DECLARE v_QrExpiresAt    DATETIME;
    DECLARE v_AlreadyIn      INT DEFAULT 0;
    DECLARE v_AttendStatusId INT UNSIGNED DEFAULT 0;

    -- Find session by QR token
    SELECT SessionId, QrExpiresAt
    INTO   v_SessionId, v_QrExpiresAt
    FROM   ProjectSessions
    WHERE  QrCode = p_QrToken AND IsDeleted = 0
    LIMIT  1;

    IF v_SessionId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid QR code.' AS Message;
    ELSEIF NOW() > v_QrExpiresAt THEN
        SELECT 0 AS IsSuccess, 'QR code has expired.' AS Message;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyIn
        FROM   ProjectAttendance WHERE SessionId = v_SessionId AND UserId = p_UserId;

        IF v_AlreadyIn > 0 THEN
            SELECT 0 AS IsSuccess, 'Already checked in for this session.' AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_AttendStatusId
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

            IF v_AttendStatusId = 0 THEN SET v_AttendStatusId = 1; END IF;

            INSERT INTO ProjectAttendance (
                SessionId, UserId, CheckInTime, QrScannedAt, AttendStatusLkpId
            )
            VALUES (v_SessionId, p_UserId, NOW(), NOW(), v_AttendStatusId);

            SELECT 1 AS IsSuccess, 'Check-in successful.' AS Message;
        END IF;
    END IF;
END //


-- ============================================================
-- APPLICATIONS MODULE
-- DB notes: Motivation (not Note), StatusLkpId INT FK (not Status VARCHAR)
--           No AppliedAt column (use CreatedAt default)
-- ============================================================

DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_Note      TEXT          -- API param "Note"; maps to DB column: Motivation
)
BEGIN
    DECLARE v_IsActive  INT DEFAULT 0;
    DECLARE v_Exists    INT DEFAULT 0;
    DECLARE v_PendingId INT UNSIGNED DEFAULT 0;

    -- Check project is ACTIVE via StatusLkpId
    SELECT COUNT(*) INTO v_IsActive
    FROM   Projects p
    JOIN   LookupValues lv ON lv.LookupValueId = p.StatusLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  p.ProjectId = p_ProjectId AND lt.TypeCode = 'PROJECT_STATUS'
      AND  lv.ValueCode = 'ACTIVE' AND p.IsDeleted = 0;

    SELECT COUNT(*) INTO v_Exists
    FROM   ProjectApplications
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsActive = 0 THEN
        SELECT 0 AS IsSuccess, 'Project is not accepting applications.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already applied to this project.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingId = 0 THEN SET v_PendingId = 1; END IF;

        INSERT INTO ProjectApplications (ProjectId, UserId, Motivation, StatusLkpId)
        VALUES (p_ProjectId, p_UserId, p_Note, v_PendingId);

        SELECT 1 AS IsSuccess, 'Application submitted successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Application_GetByProject //
CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusLkpId INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName AS ProjectTitle,
        pa.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        lv_status.ValueName AS Status,
        pa.Motivation,              -- was Note
        pa.CreatedAt AS AppliedAt,
        pa.StatusUpdatedAt AS ReviewedAt
    FROM   ProjectApplications pa
    JOIN   Projects p ON p.ProjectId = pa.ProjectId
    JOIN   UserProfiles up ON up.UserId = pa.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = pa.StatusLkpId
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (p_StatusLkpId IS NULL OR pa.StatusLkpId = p_StatusLkpId)
    ORDER  BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM ProjectApplications pa
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (p_StatusLkpId IS NULL OR pa.StatusLkpId = p_StatusLkpId);
END //

DROP PROCEDURE IF EXISTS Application_Review //
CREATE PROCEDURE Application_Review(
    IN p_ApplicationId INT UNSIGNED,
    IN p_ReviewedBy    INT UNSIGNED,
    IN p_StatusLkpId   INT UNSIGNED,  -- was p_Status VARCHAR
    IN p_Note          TEXT
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;
    DECLARE v_OrgId     INT UNSIGNED;
    DECLARE v_IsAdmin   INT DEFAULT 0;

    SELECT ProjectId INTO v_ProjectId
    FROM   ProjectApplications WHERE ApplicationId = p_ApplicationId AND IsDeleted = 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = v_ProjectId;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_ReviewedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message;
    ELSE
        UPDATE ProjectApplications
        SET    StatusLkpId      = p_StatusLkpId,
               RejectionReason  = CASE WHEN p_Note IS NOT NULL THEN p_Note ELSE RejectionReason END,
               StatusUpdatedBy  = p_ReviewedBy,
               StatusUpdatedAt  = NOW()
        WHERE  ApplicationId = p_ApplicationId;

        SELECT 1 AS IsSuccess, 'Application reviewed.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName AS ProjectTitle,
        o.OrgName, lv_status.ValueName AS Status,
        pa.Motivation, pa.CreatedAt AS AppliedAt,
        pa.StatusUpdatedAt AS ReviewedAt,
        p.City, p.State
    FROM   ProjectApplications pa
    JOIN   Projects p ON p.ProjectId = pa.ProjectId
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = pa.StatusLkpId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0
    ORDER  BY pa.CreatedAt DESC;
END //


-- ============================================================
-- POSTS / FEED MODULE
-- DB notes: PostTypeLkpId + VisibilityLkpId INT FK (not PostType VARCHAR)
--           PostMedia.FileUrl + MediaTypeLkpId INT FK (not MediaUrl)
--           PostReports.ReasonLkpId + StatusLkpId INT FK, ReportedByUserId (not UserId)
-- ============================================================

DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,
    IN p_PostTypeLkpId   INT UNSIGNED,  -- was p_PostType VARCHAR
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_DefaultTypeLkpId       INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultVisibilityLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_ImageTypeLkpId         INT UNSIGNED DEFAULT 0;

    -- Resolve defaults from LookupValues
    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
        SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
    END IF;

    IF p_VisibilityLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultVisibilityLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;
        SET p_VisibilityLkpId = COALESCE(v_DefaultVisibilityLkpId, 1);
    END IF;

    INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
    VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

    SET @NewPostId = LAST_INSERT_ID();

    -- Store media URLs (mapped to PostMedia.FileUrl + default IMAGE type)
    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN
        SELECT lv.LookupValueId INTO v_ImageTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

        IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;

        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT @NewPostId, TRIM(j.val), v_ImageTypeLkpId, j.rn
        FROM JSON_TABLE(CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
                        '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')) AS j
        WHERE TRIM(j.val) != '';
    END IF;

    SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
END //

DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId, p.Content, lv_type.ValueName AS PostType,
        p.LikeCount, p.CommentCount, p.CreatedAt,
        p.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId, o.OrgName,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe
    FROM   Posts p
    JOIN   UserProfiles up ON up.UserId = p.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    WHERE  p.IsDeleted = 0
    ORDER  BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Posts WHERE IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_GetById //
CREATE PROCEDURE Post_GetById(
    IN p_PostId INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        p.PostId, p.Content, lv_type.ValueName AS PostType,
        p.LikeCount, p.CommentCount, p.CreatedAt,
        p.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId, o.OrgName,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe
    FROM   Posts p
    JOIN   UserProfiles up ON up.UserId = p.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    WHERE  p.PostId = p_PostId AND p.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_Like //
CREATE PROCEDURE Post_Like(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    IF EXISTS (SELECT 1 FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId) THEN
        SELECT 0 AS IsSuccess, 'Already liked this post.' AS Message;
    ELSE
        INSERT INTO PostLikes (PostId, UserId) VALUES (p_PostId, p_UserId);
        UPDATE Posts SET LikeCount = LikeCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Post liked.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Post_Unlike //
CREATE PROCEDURE Post_Unlike(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DELETE FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId;
    UPDATE Posts SET LikeCount = GREATEST(LikeCount - 1, 0) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post unliked.' AS Message;
END //

DROP PROCEDURE IF EXISTS Post_AddComment //
CREATE PROCEDURE Post_AddComment(
    IN p_PostId          INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_ParentCommentId INT UNSIGNED
)
BEGIN
    INSERT INTO PostComments (PostId, UserId, Content, ParentCommentId)
    VALUES (p_PostId, p_UserId, p_Content, p_ParentCommentId);

    UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;

    SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId;
END //

DROP PROCEDURE IF EXISTS Post_GetComments //
CREATE PROCEDURE Post_GetComments(
    IN p_PostId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        pc.CommentId, pc.ParentCommentId, pc.Content, pc.CreatedAt,
        pc.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto
    FROM   PostComments pc
    JOIN   UserProfiles up ON up.UserId = pc.UserId AND up.IsDeleted = 0
    WHERE  pc.PostId = p_PostId AND pc.IsDeleted = 0
    ORDER  BY pc.CreatedAt
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM PostComments WHERE PostId = p_PostId AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId       INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_ReasonLkpId  INT UNSIGNED,  -- was p_Reason TEXT
    IN p_Details      TEXT
)
BEGIN
    DECLARE v_Exists         INT DEFAULT 0;
    DECLARE v_PendingStatusId INT UNSIGNED DEFAULT 0;

    -- PostReports uses ReportedByUserId (not UserId)
    SELECT COUNT(*) INTO v_Exists
    FROM   PostReports WHERE PostId = p_PostId AND ReportedByUserId = p_UserId;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingStatusId = 0 THEN SET v_PendingStatusId = 1; END IF;

        INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
        VALUES (p_PostId, p_UserId, p_ReasonLkpId, p_Details, v_PendingStatusId);

        SELECT 1 AS IsSuccess, 'Post reported. Our team will review it.' AS Message;
    END IF;
END //


-- ============================================================
-- COMMUNITY / POLLS MODULE
-- DB notes: CommunityPosts.Title NOT NULL, PostTypeLkpId + AudienceLkpId INT FK
--           No Tags column, no IsPoll column, no ExpiresAt column
--           PollEndsAt DATETIME for poll expiry
-- ============================================================

DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId        INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_Title         VARCHAR(300),   -- NOT NULL in DB
    IN p_Content       TEXT,
    IN p_PostTypeLkpId INT UNSIGNED,
    IN p_AudienceLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    IF p_AudienceLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'ORG_MEMBERS' LIMIT 1;
        SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
    END IF;

    INSERT INTO CommunityPosts (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, CreatedBy)
    VALUES (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_UserId);

    SELECT 1 AS IsSuccess, 'Community post created.' AS Message, LAST_INSERT_ID() AS CommunityPostId;
END //

DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId, cp.Title, cp.Content,
        lv_type.ValueName AS PostType, cp.CreatedAt,
        cp.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName,
        up.ProfilePhoto,
        cp.OrgId, o.OrgName,
        cp.AcknowledgeCount
    FROM   CommunityPosts cp
    JOIN   UserProfiles up ON up.UserId = cp.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = cp.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = cp.PostTypeLkpId
    WHERE  cp.IsDeleted = 0
      AND  (p_OrgId IS NULL OR cp.OrgId = p_OrgId)
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM CommunityPosts WHERE IsDeleted = 0
      AND  (p_OrgId IS NULL OR OrgId = p_OrgId);
END //

DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT
)
BEGIN
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_PollTypeLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

    SELECT lv.LookupValueId INTO v_AudienceLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'ORG_MEMBERS' LIMIT 1;

    IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
    IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

    -- Title stores the poll question; PollEndsAt computed from ExpiresInHours
    INSERT INTO CommunityPosts (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, CreatedBy)
    VALUES (
        p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
        v_AudienceLkpId,
        DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR),
        p_UserId
    );

    SET @PollId = LAST_INSERT_ID();

    INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
    SELECT @PollId, jt.opt, jt.rn
    FROM JSON_TABLE(p_OptionsJson, '$[*]' COLUMNS (
        rn   FOR ORDINALITY,
        opt  VARCHAR(200) PATH '$'
    )) AS jt;

    SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId;
END //

DROP PROCEDURE IF EXISTS Community_Vote //
CREATE PROCEDURE Community_Vote(
    IN p_PollId       INT UNSIGNED,   -- CommunityPostId
    IN p_UserId       INT UNSIGNED,
    IN p_PollOptionId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists   INT DEFAULT 0;
    DECLARE v_Expired  INT DEFAULT 0;

    -- Check poll not expired (PollEndsAt, not ExpiresAt)
    SELECT COUNT(*) INTO v_Expired FROM CommunityPosts
    WHERE  CommunityPostId = p_PollId AND PollEndsAt IS NOT NULL AND PollEndsAt < NOW();

    SELECT COUNT(*) INTO v_Exists FROM PollVotes
    WHERE  CommunityPostId = p_PollId AND UserId = p_UserId;

    IF v_Expired > 0 THEN
        SELECT 0 AS IsSuccess, 'This poll has expired.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already voted on this poll.' AS Message;
    ELSE
        INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId)
        VALUES (p_PollOptionId, p_PollId, p_UserId);

        UPDATE PollOptions SET VoteCount = VoteCount + 1 WHERE PollOptionId = p_PollOptionId;

        SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
    END IF;
END //


-- ============================================================
-- DONATIONS + RAZORPAY MODULE
-- DB notes: CampaignName (not Title), TargetAmount (not GoalAmount)
--           DonationTransactions: DonationId (not DonationRef), DonorUserId (not UserId)
--           DonationAmount (not Amount), GatewayOrderId (not RazorpayOrderId)
--           PayStatusLkpId INT FK (not Status VARCHAR)
--           IdSequences: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
--           RecurringDonations: RecurringDonId PK, DonorUserId, FrequencyLkpId + StatusLkpId INT FK
--           NextChargeDate DATE (not NextRunAt DATETIME), StartDate required
-- ============================================================

DROP PROCEDURE IF EXISTS Donation_CreateCampaign //
CREATE PROCEDURE Donation_CreateCampaign(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgId             INT UNSIGNED,
    IN p_Title             VARCHAR(200),    -- API param; maps to DB column: CampaignName
    IN p_Description       TEXT,
    IN p_GoalAmount        DECIMAL(12,2),   -- API param; maps to DB column: TargetAmount
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_BannerUrl         VARCHAR(500),
    IN p_CampaignTypeLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin         INT DEFAULT 0;
    DECLARE v_ActiveStatusId  INT UNSIGNED DEFAULT 0;
    DECLARE v_PublicVisId     INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message, NULL AS CampaignId;
    ELSE
        SELECT lv.LookupValueId INTO v_ActiveStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

        SELECT lv.LookupValueId INTO v_PublicVisId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;

        IF v_ActiveStatusId = 0 THEN SET v_ActiveStatusId = 1; END IF;
        IF v_PublicVisId    = 0 THEN SET v_PublicVisId    = 1; END IF;

        INSERT INTO DonationCampaigns (
            OrgId, CreatedByUserId, CampaignName, Description,
            CampaignTypeLkpId, TargetAmount, RaisedAmount,
            StartDate, EndDate, BannerUrl,
            VisibilityLkpId, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgId, p_UserId, p_Title, p_Description,
            p_CampaignTypeLkpId, p_GoalAmount, 0.00,
            p_StartDate, p_EndDate, p_BannerUrl,
            v_PublicVisId, v_ActiveStatusId, p_UserId
        );

        SELECT 1 AS IsSuccess, 'Campaign created.' AS Message, LAST_INSERT_ID() AS CampaignId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Donation_GetCampaigns //
CREATE PROCEDURE Donation_GetCampaigns(
    IN p_OrgId      INT UNSIGNED,
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        dc.CampaignId, dc.OrgId, o.OrgName,
        dc.CampaignName AS Title,       -- aliased to Title for API consistency
        dc.TargetAmount AS GoalAmount,  -- aliased to GoalAmount for API consistency
        dc.RaisedAmount, dc.DonorCount,
        dc.StartDate, dc.EndDate, dc.BannerUrl,
        lv_status.ValueName AS Status,
        ROUND((dc.RaisedAmount / NULLIF(dc.TargetAmount, 0)) * 100, 1) AS ProgressPct
    FROM   DonationCampaigns dc
    JOIN   Organisations o ON o.OrgId = dc.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dc.StatusLkpId
    WHERE  dc.IsDeleted = 0
      AND  (p_OrgId  IS NULL OR dc.OrgId = p_OrgId)
      AND  (p_Search IS NULL OR dc.CampaignName LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY dc.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationCampaigns dc
    WHERE  dc.IsDeleted = 0
      AND  (p_OrgId  IS NULL OR dc.OrgId = p_OrgId)
      AND  (p_Search IS NULL OR dc.CampaignName LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Donation_GetCampaignById //
CREATE PROCEDURE Donation_GetCampaignById(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        dc.CampaignId, dc.OrgId, o.OrgName,
        dc.CampaignName AS Title,
        dc.Description,
        dc.TargetAmount AS GoalAmount,
        dc.RaisedAmount, dc.DonorCount,
        dc.StartDate, dc.EndDate, dc.BannerUrl,
        lv_status.ValueName AS Status,
        ROUND((dc.RaisedAmount / NULLIF(dc.TargetAmount, 0)) * 100, 1) AS ProgressPct
    FROM   DonationCampaigns dc
    JOIN   Organisations o ON o.OrgId = dc.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dc.StatusLkpId
    WHERE  dc.CampaignId = p_CampaignId AND dc.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Donation_Initiate //
CREATE PROCEDURE Donation_Initiate(
    IN p_UserId        INT UNSIGNED,
    IN p_CampaignId    INT UNSIGNED,
    IN p_Amount        DECIMAL(10,2),
    IN p_Note          TEXT,
    IN p_IsAnonymous   TINYINT(1),
    IN p_PayMethodLkpId INT UNSIGNED  -- LkpId for UPI/CARD/etc (TypeCode='PAYMENT_METHOD')
)
BEGIN
    DECLARE v_Year        VARCHAR(4);
    DECLARE v_SeqNo       INT UNSIGNED;
    DECLARE v_DonationId  VARCHAR(30);
    DECLARE v_GatewayOrderId VARCHAR(100);
    DECLARE v_OrgId       INT UNSIGNED;
    DECLARE v_PlatformPct DECIMAL(5,2) DEFAULT 1.00;
    DECLARE v_PlatformAmt DECIMAL(10,2);
    DECLARE v_OrgAmt      DECIMAL(12,2);
    DECLARE v_PendingPayStatus INT UNSIGNED DEFAULT 0;
    DECLARE v_OneTimeDonType   INT UNSIGNED DEFAULT 0;
    DECLARE v_PublicVisId      INT UNSIGNED DEFAULT 0;

    SET v_Year = YEAR(NOW());

    -- Generate readable donation ID: DON-2026-000001
    -- IdSequences uses: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
    INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue)
    VALUES ('DON', v_Year, 1)
    ON DUPLICATE KEY UPDATE LastValue = LastValue + 1;

    SELECT LastValue INTO v_SeqNo
    FROM   IdSequences WHERE SequenceName = 'DON' AND CurrentYear = v_Year;

    SET v_DonationId     = CONCAT('DON-', v_Year, '-', LPAD(v_SeqNo, 6, '0'));
    SET v_GatewayOrderId = CONCAT('order_', UNIX_TIMESTAMP(), '_', p_UserId);

    -- Get OrgId and platform fee from campaign
    SELECT dc.OrgId, COALESCE(ods.PlatformFeePct, 1.00)
    INTO   v_OrgId, v_PlatformPct
    FROM   DonationCampaigns dc
    LEFT   JOIN OrgDonationSettings ods ON ods.OrgId = dc.OrgId
    WHERE  dc.CampaignId = p_CampaignId LIMIT 1;

    SET v_PlatformAmt = ROUND(p_Amount * v_PlatformPct / 100, 2);
    SET v_OrgAmt      = p_Amount - v_PlatformAmt;

    -- Resolve required LkpIds
    SELECT lv.LookupValueId INTO v_PendingPayStatus
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'DONATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_OneTimeDonType
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'DONATION_TYPE' AND lv.ValueCode = 'ONE_TIME' LIMIT 1;

    SELECT lv.LookupValueId INTO v_PublicVisId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;

    IF v_PendingPayStatus = 0 THEN SET v_PendingPayStatus = 1; END IF;
    IF v_OneTimeDonType   = 0 THEN SET v_OneTimeDonType   = 1; END IF;
    IF v_PublicVisId      = 0 THEN SET v_PublicVisId      = 1; END IF;

    INSERT INTO DonationTransactions (
        DonationId, CampaignId, OrgId, DonorUserId,
        DonationAmount, PlatformFeePct, PlatformFeeAmt, OrgReceivesAmt,
        DonTypeLkpId, PayMethodLkpId, VisibilityLkpId, PayStatusLkpId,
        GatewayOrderId
    )
    VALUES (
        v_DonationId, p_CampaignId, v_OrgId,
        CASE WHEN p_IsAnonymous = 1 THEN NULL ELSE p_UserId END,
        p_Amount, v_PlatformPct, v_PlatformAmt, v_OrgAmt,
        v_OneTimeDonType, p_PayMethodLkpId, v_PublicVisId, v_PendingPayStatus,
        v_GatewayOrderId
    );

    SELECT v_DonationId     AS DonationRef,
           v_GatewayOrderId AS RazorpayOrderId,
           p_Amount          AS Amount,
           LAST_INSERT_ID()  AS TransactionId;
END //

DROP PROCEDURE IF EXISTS Donation_VerifyPayment //
CREATE PROCEDURE Donation_VerifyPayment(
    IN p_UserId             INT UNSIGNED,
    IN p_DonationRef        VARCHAR(30),    -- API param; maps to DB column: DonationId
    IN p_RazorpayOrderId    VARCHAR(100),
    IN p_RazorpayPaymentId  VARCHAR(100),
    IN p_RazorpaySignature  VARCHAR(256)
)
BEGIN
    DECLARE v_TxnId      INT UNSIGNED;
    DECLARE v_Amount     DECIMAL(12,2);
    DECLARE v_CampaignId INT UNSIGNED;
    DECLARE v_SuccessId  INT UNSIGNED DEFAULT 0;

    -- DonationId is the readable reference (DON-2026-000001)
    SELECT TransactionId, DonationAmount, CampaignId
    INTO   v_TxnId, v_Amount, v_CampaignId
    FROM   DonationTransactions
    WHERE  DonationId = p_DonationRef
      AND  (DonorUserId = p_UserId OR DonorUserId IS NULL)
    LIMIT  1;

    IF v_TxnId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Donation transaction not found.' AS Message;
    ELSE
        -- NOTE: HMAC-SHA256 Razorpay signature verification must happen in C# BEFORE calling this SP
        SELECT lv.LookupValueId INTO v_SuccessId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'DONATION_STATUS' AND lv.ValueCode = 'SUCCESS' LIMIT 1;

        IF v_SuccessId = 0 THEN SET v_SuccessId = 1; END IF;

        UPDATE DonationTransactions
        SET    PayStatusLkpId  = v_SuccessId,
               GatewayPaymentId = p_RazorpayPaymentId,
               GatewayResponse  = p_RazorpaySignature
        WHERE  TransactionId = v_TxnId;

        -- Update campaign raised amount + donor count (denormalized)
        UPDATE DonationCampaigns
        SET    RaisedAmount = RaisedAmount + v_Amount,
               DonorCount  = DonorCount + 1
        WHERE  CampaignId = v_CampaignId;

        SELECT 1 AS IsSuccess, 'Payment verified. Thank you for your donation!' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Donation_GetTransactions //
CREATE PROCEDURE Donation_GetTransactions(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        dt.TransactionId,
        dt.DonationId AS DonationRef,
        dt.DonationAmount AS Amount,
        lv_status.ValueName AS Status,
        dt.CreatedAt,
        dc.CampaignName AS CampaignTitle,
        o.OrgName
    FROM   DonationTransactions dt
    LEFT   JOIN DonationCampaigns dc ON dc.CampaignId = dt.CampaignId
    LEFT   JOIN Organisations o ON o.OrgId = dt.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dt.PayStatusLkpId
    WHERE  dt.DonorUserId = p_UserId AND dt.IsDeleted = 0
    ORDER  BY dt.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationTransactions WHERE DonorUserId = p_UserId AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Donation_GetReceipt //
CREATE PROCEDURE Donation_GetReceipt(IN p_DonationRef VARCHAR(30), IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        dt.DonationId AS DonationRef,
        dt.DonationAmount AS Amount,
        dt.CreatedAt AS CompletedAt,
        dc.CampaignName AS CampaignTitle,
        o.OrgName, o.RegNumber,
        CONCAT(up.FirstName,' ',up.LastName) AS DonorName,
        u.Email,
        '80G' AS ReceiptType
    FROM   DonationTransactions dt
    LEFT   JOIN DonationCampaigns dc ON dc.CampaignId = dt.CampaignId
    LEFT   JOIN Organisations o ON o.OrgId = dt.OrgId
    LEFT   JOIN Users u ON u.UserId = dt.DonorUserId
    LEFT   JOIN UserProfiles up ON up.UserId = dt.DonorUserId AND up.IsDeleted = 0
    WHERE  dt.DonationId = p_DonationRef AND dt.DonorUserId = p_UserId;
END //

DROP PROCEDURE IF EXISTS Donation_SetupRecurring //
CREATE PROCEDURE Donation_SetupRecurring(
    IN p_UserId          INT UNSIGNED,
    IN p_CampaignId      INT UNSIGNED,
    IN p_Amount          DECIMAL(10,2),
    IN p_FrequencyLkpId  INT UNSIGNED,  -- was p_Frequency VARCHAR
    IN p_Note            TEXT           -- stored as... Note doesn't exist in DB — ignored
)
BEGIN
    DECLARE v_OrgId        INT UNSIGNED;
    DECLARE v_ActiveStatus INT UNSIGNED DEFAULT 0;
    DECLARE v_FreqCode     VARCHAR(20);
    DECLARE v_NextDate     DATE;

    SELECT OrgId INTO v_OrgId FROM DonationCampaigns WHERE CampaignId = p_CampaignId LIMIT 1;

    -- Get frequency code to compute NextChargeDate
    SELECT lv.ValueCode INTO v_FreqCode
    FROM   LookupValues lv WHERE lv.LookupValueId = p_FrequencyLkpId LIMIT 1;

    SET v_NextDate = CASE v_FreqCode
        WHEN 'WEEKLY'    THEN DATE_ADD(CURDATE(), INTERVAL 7 DAY)
        WHEN 'QUARTERLY' THEN DATE_ADD(CURDATE(), INTERVAL 3 MONTH)
        WHEN 'YEARLY'    THEN DATE_ADD(CURDATE(), INTERVAL 1 YEAR)
        ELSE DATE_ADD(CURDATE(), INTERVAL 1 MONTH)   -- MONTHLY default
    END;

    SELECT lv.LookupValueId INTO v_ActiveStatus
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    IF v_ActiveStatus = 0 THEN SET v_ActiveStatus = 1; END IF;

    -- DB columns: RecurringDonId (PK), DonorUserId, OrgId, CampaignId, Amount,
    --             FrequencyLkpId, StatusLkpId, StartDate, NextChargeDate
    INSERT INTO RecurringDonations (
        DonorUserId, OrgId, CampaignId, Amount,
        FrequencyLkpId, StatusLkpId,
        StartDate, NextChargeDate
    )
    VALUES (
        p_UserId, v_OrgId, p_CampaignId, p_Amount,
        p_FrequencyLkpId, v_ActiveStatus,
        CURDATE(), v_NextDate
    );

    SELECT 1 AS IsSuccess, 'Recurring donation setup successfully.' AS Message, LAST_INSERT_ID() AS RecurringId;
END //

DROP PROCEDURE IF EXISTS Donation_CancelRecurring //
CREATE PROCEDURE Donation_CancelRecurring(IN p_RecurringId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_Owns        INT DEFAULT 0;
    DECLARE v_CancelledId INT UNSIGNED DEFAULT 0;

    -- PK column is RecurringDonId (not RecurringId)
    SELECT COUNT(*) INTO v_Owns
    FROM   RecurringDonations WHERE RecurringDonId = p_RecurringId AND DonorUserId = p_UserId AND IsDeleted = 0;

    IF v_Owns = 0 THEN
        SELECT 0 AS IsSuccess, 'Recurring donation not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_CancelledId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

        IF v_CancelledId = 0 THEN SET v_CancelledId = 1; END IF;

        UPDATE RecurringDonations
        SET    StatusLkpId  = v_CancelledId,
               CancelledAt  = NOW(),
               UpdatedAt    = NOW()
        WHERE  RecurringDonId = p_RecurringId AND DonorUserId = p_UserId;

        SELECT 1 AS IsSuccess, 'Recurring donation cancelled.' AS Message;
    END IF;
END //


-- ============================================================
-- SOS MODULE
-- DB notes: SosIncidents.SosIncidentId PK (not SosId)
--           AlertTypeLkpId INT FK (not SosType VARCHAR)
--           StatusLkpId INT FK (not Status VARCHAR)
--           SosResponders.SosIncidentId, ApprovalStatusLkpId INT FK
--           SosLocationLogs.SosIncidentId (not SosId)
-- ============================================================

DROP PROCEDURE IF EXISTS Sos_Trigger //
CREATE PROCEDURE Sos_Trigger(
    IN p_UserId          INT UNSIGNED,
    IN p_Latitude        DECIMAL(10,7),
    IN p_Longitude       DECIMAL(10,7),
    IN p_Description     TEXT,
    IN p_AlertTypeLkpId  INT UNSIGNED    -- was p_SosType VARCHAR; maps to DB column: AlertTypeLkpId
)
BEGIN
    DECLARE v_ActiveStatusId   INT UNSIGNED DEFAULT 0;
    DECLARE v_ResolvedStatusId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveStatusId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ResolvedStatusId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'RESOLVED' LIMIT 1;

    IF v_ActiveStatusId   = 0 THEN SET v_ActiveStatusId   = 1; END IF;
    IF v_ResolvedStatusId = 0 THEN SET v_ResolvedStatusId = 2; END IF;

    -- Close any existing active SOS for this user (SosIncidentId is PK)
    UPDATE SosIncidents
    SET    StatusLkpId = v_ResolvedStatusId,
           ResolvedAt  = NOW()
    WHERE  UserId = p_UserId AND StatusLkpId = v_ActiveStatusId AND IsDeleted = 0;

    INSERT INTO SosIncidents (UserId, AlertTypeLkpId, Latitude, Longitude, Description, StatusLkpId)
    VALUES (p_UserId, p_AlertTypeLkpId, p_Latitude, p_Longitude, p_Description, v_ActiveStatusId);

    SELECT 1 AS IsSuccess, 'SOS alert triggered. Help is on the way!' AS Message,
           LAST_INSERT_ID() AS SosId;
END //

DROP PROCEDURE IF EXISTS Sos_Resolve //
CREATE PROCEDURE Sos_Resolve(
    IN p_SosId          INT UNSIGNED,   -- this is SosIncidentId
    IN p_UserId         INT UNSIGNED,
    IN p_ResolutionNote TEXT
)
BEGIN
    DECLARE v_Owns         INT DEFAULT 0;
    DECLARE v_ActiveId     INT UNSIGNED DEFAULT 0;
    DECLARE v_ResolvedId   INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ResolvedId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'RESOLVED' LIMIT 1;

    IF v_ActiveId   = 0 THEN SET v_ActiveId   = 1; END IF;
    IF v_ResolvedId = 0 THEN SET v_ResolvedId = 2; END IF;

    SELECT COUNT(*) INTO v_Owns
    FROM   SosIncidents
    WHERE  SosIncidentId = p_SosId AND UserId = p_UserId AND StatusLkpId = v_ActiveId;

    IF v_Owns = 0 THEN
        SELECT 0 AS IsSuccess, 'SOS not found or already resolved.' AS Message;
    ELSE
        UPDATE SosIncidents
        SET    StatusLkpId = v_ResolvedId,
               CancelReason = p_ResolutionNote,
               ResolvedAt   = NOW()
        WHERE  SosIncidentId = p_SosId;
        SELECT 1 AS IsSuccess, 'SOS resolved.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Sos_Respond //
CREATE PROCEDURE Sos_Respond(
    IN p_SosId  INT UNSIGNED,   -- SosIncidentId
    IN p_UserId INT UNSIGNED,
    IN p_Note   TEXT
)
BEGIN
    DECLARE v_Exists         INT DEFAULT 0;
    DECLARE v_IsOwner        INT DEFAULT 0;
    DECLARE v_PendingApproval INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsOwner
    FROM   SosIncidents WHERE SosIncidentId = p_SosId AND UserId = p_UserId;

    SELECT COUNT(*) INTO v_Exists
    FROM   SosResponders WHERE SosIncidentId = p_SosId AND UserId = p_UserId;

    IF v_IsOwner > 0 THEN
        SELECT 0 AS IsSuccess, 'Cannot respond to your own SOS.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already responded to this SOS.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingApproval
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingApproval = 0 THEN SET v_PendingApproval = 1; END IF;

        INSERT INTO SosResponders (SosIncidentId, UserId, ApprovalStatusLkpId)
        VALUES (p_SosId, p_UserId, v_PendingApproval);

        SELECT 1 AS IsSuccess, 'Response registered. Please proceed to the location.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Sos_UpdateLocation //
CREATE PROCEDURE Sos_UpdateLocation(
    IN p_SosId     INT UNSIGNED,   -- SosIncidentId
    IN p_UserId    INT UNSIGNED,
    IN p_Latitude  DECIMAL(10,7),
    IN p_Longitude DECIMAL(10,7)
)
BEGIN
    -- Log location — SosLocationLogs uses SosIncidentId (not SosId)
    INSERT INTO SosLocationLogs (SosIncidentId, UserId, Latitude, Longitude)
    VALUES (p_SosId, p_UserId, p_Latitude, p_Longitude);

    -- Update current coordinates on the incident row
    UPDATE SosIncidents
    SET    Latitude  = p_Latitude,
           Longitude = p_Longitude
    WHERE  SosIncidentId = p_SosId AND UserId = p_UserId;

    SELECT 1 AS IsSuccess, 'Location updated.' AS Message;
END //


-- ============================================================
-- NOTIFICATIONS MODULE
-- DB notes: Notifications has no IsDeleted column
--           RefId (not EntityId), RefType for entity type string
-- ============================================================

DROP PROCEDURE IF EXISTS Notification_GetList //
CREATE PROCEDURE Notification_GetList(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    -- Note: Notifications table has no IsDeleted column
    SELECT NotificationId, Title, Body, NotifType, RefId, RefType, IsRead, CreatedAt
    FROM   Notifications
    WHERE  UserId = p_UserId
    ORDER  BY CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Notifications WHERE UserId = p_UserId;
END //

DROP PROCEDURE IF EXISTS Notification_MarkRead //
CREATE PROCEDURE Notification_MarkRead(IN p_NotificationId BIGINT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE Notifications
    SET    IsRead = 1, ReadAt = NOW()
    WHERE  NotificationId = p_NotificationId AND UserId = p_UserId;

    SELECT 1 AS IsSuccess, 'Notification marked as read.' AS Message;
END //

DROP PROCEDURE IF EXISTS Notification_MarkAllRead //
CREATE PROCEDURE Notification_MarkAllRead(IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE Notifications
    SET    IsRead = 1, ReadAt = NOW()
    WHERE  UserId = p_UserId AND IsRead = 0;

    SELECT 1 AS IsSuccess, 'All notifications marked as read.' AS Message;
END //

DROP PROCEDURE IF EXISTS Notification_SaveDeviceToken //
CREATE PROCEDURE Notification_SaveDeviceToken(
    IN p_UserId   INT UNSIGNED,
    IN p_Token    VARCHAR(512),
    IN p_Platform VARCHAR(20)
)
BEGIN
    -- Upsert: update token if platform already registered for this user
    INSERT INTO UserDeviceTokens (UserId, Token, Platform)
    VALUES (p_UserId, p_Token, p_Platform)
    ON DUPLICATE KEY UPDATE Token = p_Token, UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Device token registered.' AS Message;
END //


DELIMITER ;

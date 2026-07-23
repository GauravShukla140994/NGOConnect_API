-- ============================================================
-- NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql
--
-- Marketing & Communication Center — Phase 0 (Hangfire foundation +
-- UserCommunicationPreferences + new lookups) and Phase 1 (Campaigns,
-- Push + Email only). See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
--
-- WORKFLOW (per this project's CLAUDE.md):
--   1. This patch has ALREADY been merged into
--      Documents/NGOConnect_Complete_Setup_v4.9.sql (source of truth).
--   2. Run THIS file against your LOCAL dev DB first.
--   3. Do not run against Railway staging/production yet — combine with
--      any other pending patches first, per this project's own patch workflow.
--
-- SAFETY NOTES:
--   - All 6 new tables use CREATE TABLE IF NOT EXISTS — safe to re-run.
--   - The two ALTER TABLE Users ADD INDEX statements are one-time; re-running
--     this file a second time will error on "Duplicate key name" for those
--     two lines specifically — that error is harmless and expected on a
--     second run (drop those two lines if you need to re-run this file).
--   - LookupTypes/LookupValues/Settings INSERTs will error with a duplicate-key
--     message if re-run — also harmless (nothing gets corrupted or duplicated),
--     just re-run only NGOConnect_Complete_Setup_v4.9.sql's fresh-DB path
--     instead if starting a brand new database.
--   - Hangfire's own storage tables (HangfireXxx) are NOT part of this patch —
--     Hangfire.MySqlStorage creates/migrates them automatically on first run
--     (PrepareSchemaIfNecessary=true in ServiceCollectionExtensions.cs).
--
-- Scope decisions locked in 2026-07-23:
--   - SMS channel excluded from Phase 1 (Fast2SMS is test-route only, needs
--     DLT/TRAI registration first) — Push + Email only for now.
--   - WhatsApp is confirmed for a later stage (Phase 4), seeded here as an
--     inert lookup value so activation later is a feature flag, not a schema change.
-- ============================================================

-- ============================================================
-- v5.0 NEW: Marketing & Communication Center — Phase 0 + Phase 1
-- Push + Email only in Phase 1. SMS channel/columns exist but stay
-- disabled (see Settings COMMUNICATION.CAMPAIGN_SMS_ENABLED) until
-- Fast2SMS DLT registration completes. WhatsApp lookup value seeded
-- inert for Phase 4. See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
-- ============================================================

-- Phase 0: per-user opt-in/opt-out for promotional communication.
-- No row for a user = treated as opted-in for everything (SPs default via LEFT JOIN + COALESCE).
-- Transactional messages (OTP, password reset, critical account alerts) never consult this table.
CREATE TABLE IF NOT EXISTS UserCommunicationPreferences (
    UserId                        INT UNSIGNED NOT NULL,
    ReceivePushNotifications      TINYINT(1)   NOT NULL DEFAULT 1,
    ReceivePromotionalEmails      TINYINT(1)   NOT NULL DEFAULT 1,
    ReceivePromotionalSms         TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveNgoUpdates             TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveDonationAlerts         TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveVolunteerOpportunities TINYINT(1)   NOT NULL DEFAULT 1,
    UpdatedAt                     DATETIME     NULL,
    PRIMARY KEY (UserId),
    CONSTRAINT fk_ucp_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Phase 1: one row per marketing/communication campaign.
-- NOTE: named "Campaigns" (marketing), distinct from "DonationCampaigns" (fundraising) —
-- do not confuse with the DONATION module's own CAMPAIGN_TYPE/CAMPAIGN_STATUS lookups below.
CREATE TABLE IF NOT EXISTS Campaigns (
    CampaignId          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignName        VARCHAR(200) NOT NULL,
    InternalNotes       VARCHAR(1000) NULL,
    CampaignTypeLkpId   INT UNSIGNED NOT NULL,
    PriorityLkpId       INT UNSIGNED NOT NULL,
    StatusLkpId         INT UNSIGNED NOT NULL,
    ScheduleType        VARCHAR(20)  NOT NULL DEFAULT 'NOW', -- NOW | SCHEDULED (RECURRING is Phase 2)
    ScheduledAt         DATETIME     NULL,
    TimezoneName        VARCHAR(60)  NOT NULL DEFAULT 'Asia/Kolkata',
    EstimatedRecipients INT UNSIGNED NULL,
    HangfireJobId       VARCHAR(100) NULL,   -- Hangfire job ID, used to cancel a scheduled send
    IsDeleted           TINYINT(1)   NOT NULL DEFAULT 0,
    DeletedAt           DATETIME     NULL,
    DeletedBy           INT UNSIGNED NULL,
    CreatedAt           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy           INT UNSIGNED NOT NULL,
    UpdatedAt           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy           INT UNSIGNED NULL,
    PRIMARY KEY (CampaignId),
    INDEX idx_campaign_status  (StatusLkpId, IsDeleted),
    INDEX idx_campaign_created (CreatedAt DESC),
    CONSTRAINT fk_campaign_type     FOREIGN KEY (CampaignTypeLkpId) REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_campaign_priority FOREIGN KEY (PriorityLkpId)     REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_campaign_status   FOREIGN KEY (StatusLkpId)       REFERENCES LookupValues(LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per channel selected for a campaign (Push and/or Email in Phase 1;
-- SMS/WhatsApp columns reserved so later phases are additive, not a schema change).
CREATE TABLE IF NOT EXISTS CampaignChannels (
    CampaignChannelId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId        INT UNSIGNED NOT NULL,
    ChannelLkpId      INT UNSIGNED NOT NULL,
    PushTitle         VARCHAR(200)  NULL,
    PushBody          VARCHAR(500)  NULL,
    PushImageUrl      VARCHAR(500)  NULL,
    PushDeepLink      VARCHAR(500)  NULL,
    PushActionLabel   VARCHAR(50)   NULL,
    EmailSubject      VARCHAR(255)  NULL,
    EmailHtmlBody     MEDIUMTEXT    NULL,
    CreatedAt         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignChannelId),
    UNIQUE KEY uq_campchannel (CampaignId, ChannelLkpId),
    CONSTRAINT fk_campchannel_campaign FOREIGN KEY (CampaignId)   REFERENCES Campaigns(CampaignId),
    CONSTRAINT fk_campchannel_channel  FOREIGN KEY (ChannelLkpId) REFERENCES LookupValues(LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The audience filter for a campaign. Phase 1 supports exactly ONE rule per campaign
-- (pick one option — e.g. "Inactive 30 days" OR "By Org: X,Y" — not composable
-- combinations across rule types; the full reusable Segment Builder is Phase 2).
-- RuleValueJson keeps this schema stable as new rule types are added later.
CREATE TABLE IF NOT EXISTS CampaignAudienceRules (
    CampaignAudienceRuleId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId    INT UNSIGNED NOT NULL,
    RuleType      VARCHAR(30)  NOT NULL, -- ALL | ACTIVE | INACTIVE | NEW | BY_ORG | BY_ROLE
    RuleValueJson JSON         NULL,     -- {"days":7} or {"orgIds":[1,2]} or {"roleCodes":["FOUNDER"]}
    CreatedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignAudienceRuleId),
    INDEX idx_audiencerule_campaign (CampaignId),
    CONSTRAINT fk_audiencerule_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per user per campaign per channel — the largest table in this module,
-- BIGINT PK per the platform's high-volume append-table convention.
CREATE TABLE IF NOT EXISTS CampaignRecipients (
    CampaignRecipientId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId        INT UNSIGNED NOT NULL,
    UserId            INT UNSIGNED NOT NULL,
    ChannelLkpId      INT UNSIGNED NOT NULL,
    QueueStatus       VARCHAR(20)  NOT NULL DEFAULT 'QUEUED', -- QUEUED|PROCESSING|SENT|DELIVERED|FAILED|SKIPPED_OPTOUT|SKIPPED_NO_ADDRESS
    ProviderMessageId VARCHAR(255) NULL,
    FailReason        VARCHAR(500) NULL,
    RetryCount        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    QueuedAt          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SentAt            DATETIME NULL,
    DeliveredAt       DATETIME NULL,
    OpenedAt          DATETIME NULL,
    ClickedAt         DATETIME NULL,
    PRIMARY KEY (CampaignRecipientId),
    UNIQUE KEY uq_camprecipient (CampaignId, UserId, ChannelLkpId),
    INDEX idx_camprecipient_campaign (CampaignId, QueueStatus),
    INDEX idx_camprecipient_user     (UserId),
    CONSTRAINT fk_camprecipient_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Batch/retry tracking for the Hangfire-driven send process
CREATE TABLE IF NOT EXISTS CampaignQueueJobs (
    CampaignQueueJobId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId    INT UNSIGNED NOT NULL,
    BatchNumber   INT UNSIGNED NOT NULL,
    ChannelLkpId  INT UNSIGNED NOT NULL,
    BatchSize     INT UNSIGNED NOT NULL DEFAULT 0,
    Status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING', -- PENDING|PROCESSING|COMPLETED|FAILED
    RetryCount    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    NextRetryAt   DATETIME NULL,
    StartedAt     DATETIME NULL,
    CompletedAt   DATETIME NULL,
    ErrorMessage  VARCHAR(1000) NULL,
    CreatedAt     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignQueueJobId),
    INDEX idx_queuejob_campaign (CampaignId, Status),
    CONSTRAINT fk_queuejob_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Additive indexes supporting audience-segment resolution (Active/Inactive/New filters).
-- Does not alter any existing column, default, or FK — safe add-on to a live table.
ALTER TABLE Users ADD INDEX idx_users_lastlogin (IsDeleted, LastLoginAt);
ALTER TABLE Users ADD INDEX idx_users_createdat (IsDeleted, CreatedAt);

-- ── v5.0: Communication Center lookups ───────────────────────
-- NOTE: prefixed MKTG_ to avoid colliding with the existing donation-fundraising
-- lookups CAMPAIGN_TYPE / CAMPAIGN_STATUS (see DONATION_STATUS section above —
-- those already use those exact TypeCodes for a completely different feature).
INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('MKTG_CAMPAIGN_TYPE',     'Marketing Campaign Type',     'Category of a marketing/communication campaign', 1, 1),
('MKTG_CAMPAIGN_PRIORITY', 'Marketing Campaign Priority', 'Send priority for a marketing campaign',          1, 1),
('MKTG_CAMPAIGN_STATUS',   'Marketing Campaign Status',   'Lifecycle status of a marketing campaign',        1, 1),
('MKTG_CAMPAIGN_CHANNEL',  'Marketing Campaign Channel',  'Delivery channel for a marketing campaign',       1, 1);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PROMOTION'      AS ValueCode, 'Promotion'      AS ValueName, 1  AS OrderNo UNION ALL
    SELECT 'ANNOUNCEMENT',     'Announcement',                2 UNION ALL
    SELECT 'REMINDER',         'Reminder',                    3 UNION ALL
    SELECT 'FEATURE_LAUNCH',   'Feature Launch',              4 UNION ALL
    SELECT 'DONATION',         'Donation',                    5 UNION ALL
    SELECT 'VOLUNTEER',        'Volunteer',                   6 UNION ALL
    SELECT 'EMERGENCY',        'Emergency',                   7 UNION ALL
    SELECT 'FESTIVAL',         'Festival',                    8 UNION ALL
    SELECT 'SURVEY',           'Survey',                      9 UNION ALL
    SELECT 'CUSTOM',           'Custom',                      10
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE';

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'LOW' AS ValueCode, 'Low' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'NORMAL',           'Normal',            2 UNION ALL
    SELECT 'HIGH',             'High',              3 UNION ALL
    SELECT 'CRITICAL',         'Critical',          4
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY';

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'DRAFT' AS ValueCode, 'Draft' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'SCHEDULED',          'Scheduled',          2 UNION ALL
    SELECT 'RUNNING',            'Running',            3 UNION ALL
    SELECT 'COMPLETED',          'Completed',          4 UNION ALL
    SELECT 'CANCELLED',          'Cancelled',          5 UNION ALL
    SELECT 'FAILED',             'Failed',             6 UNION ALL
    SELECT 'PAUSED',             'Paused',             7
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS';

-- WHATSAPP seeded now (inert) so Phase 4 activation is a feature-flag away, not a schema change
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PUSH' AS ValueCode, 'Push Notification' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'EMAIL',              'Email',                          2 UNION ALL
    SELECT 'SMS',                 'SMS',                            3 UNION ALL
    SELECT 'WHATSAPP',            'WhatsApp',                       4
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL';

-- ============================================================
-- SECTION 4: SEED DATA — Settings + IdSequences
-- ============================================================

INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('OTP',        'OTP_EXPIRY_MINUTES',   '10',                     'NUMBER',  'OTP expiry in minutes',                  0),
('OTP',        'OTP_MAX_ATTEMPTS',     '3',                      'NUMBER',  'Max OTP verification attempts',          0),
('OTP',        'OTP_RATE_LIMIT',       '3',                      'NUMBER',  'Max OTPs per 10 min per recipient',      0),
('AUTH',       'JWT_EXPIRY_MINUTES',   '15',                     'NUMBER',  'JWT access token expiry in minutes',     0),
('AUTH',       'REFRESH_EXPIRY_DAYS',  '30',                     'NUMBER',  'Refresh token expiry in days',           0),
('AUTH',       'MAX_SESSIONS',         '5',                      'NUMBER',  'Max concurrent sessions per user',       0),
('PAGINATION', 'DEFAULT_PAGE_SIZE',    '20',                     'NUMBER',  'Default page size for list APIs',        1),
('PAGINATION', 'MAX_PAGE_SIZE',        '100',                    'NUMBER',  'Maximum allowed page size',              1),
('PLATFORM',   'APP_NAME',             'NGO Connect',            'STRING',  'Platform display name',                  1),
('PLATFORM',   'SUPPORT_EMAIL',        'support@ngoconnect.app', 'STRING',  'Support email address',                  1),
('FEATURE',    'SOS_ENABLED',          'true',                   'BOOLEAN', 'Toggle SOS feature on/off',              0),
('FEATURE',    'DONATIONS_ENABLED',    'true',                   'BOOLEAN', 'Toggle donations feature on/off',        0),
('DONATION',   'MIN_DONATION_AMOUNT',  '10',                     'NUMBER',  'Minimum donation amount in INR',         1),
('DONATION',   'DEFAULT_PLATFORM_FEE', '1.00',                   'NUMBER',  'Default platform fee percentage',        0),
('DONATION',   'RAZORPAY_KEY_ID',      'rzp_test_xxxx',          'STRING',  'Razorpay Key ID (public)',               1),
('UPLOAD',     'MAX_FILE_SIZE_MB',     '10',                     'NUMBER',  'Maximum file upload size in MB',         1),
('UPLOAD',     'ALLOWED_IMAGE_TYPES',  'jpg,jpeg,png,webp',      'STRING',  'Allowed image file extensions',          1),
('UPLOAD',     'ALLOWED_DOC_TYPES',    'pdf,doc,docx',           'STRING',  'Allowed document file extensions',       1),
('SOS',        'SOS_RADIUS_KM',        '5',                      'NUMBER',  'Default SOS alert radius in km',         0),
('SMS',        'SMS_PROVIDER',         'MSG91',                  'STRING',  'SMS provider name',                      0),
('SMS',        'SMS_TEMPLATE_OTP',     'Your OTP is {otp}',      'STRING',  'OTP SMS template',                       0),
-- v4.9: Org Member Invitations
('INVITE',     'INVITE_BASE_URL',          'https://ripplehub.app/invite/', 'URL',     'Base URL for org member invitation deep links (swap per env)', 0),
('INVITE',     'INVITE_TOKEN_EXPIRY_DAYS', '30',                            'NUMBER',  'Invitation link expiry in days',                              0),
('INVITE',     'INVITE_SINGLE_USE',        'true',                          'BOOLEAN', 'Invitation token can only be consumed once',                  0),
('SMS',        'SMS_TEMPLATE_INVITE',      '{inviter} invited you to join {orgName} on RippleHub. Join the community: {link}', 'STRING', 'SMS template for org invitations', 0),
('EMAIL',      'EMAIL_TEMPLATE_INVITE',    'org_invitation',                'STRING',  'Email template key for org invitations',                      0);

-- v5.0 NEW: Marketing & Communication Center
INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('COMMUNICATION', 'CAMPAIGN_BATCH_SIZE',            '500',   'NUMBER',  'Recipients per send batch, per channel',                                     0),
('COMMUNICATION', 'CAMPAIGN_RETRY_MAX_ATTEMPTS',    '3',     'NUMBER',  'Max retry attempts per failed batch',                                        0),
('COMMUNICATION', 'CAMPAIGN_RETRY_BACKOFF_MINUTES', '5',     'NUMBER',  'Base backoff delay between retries in minutes, doubles each attempt',       0),
('COMMUNICATION', 'CAMPAIGN_SMS_ENABLED',           'false', 'BOOLEAN', 'SMS channel toggle — keep false until Fast2SMS DLT registration completes', 0),
('COMMUNICATION', 'HANGFIRE_DASHBOARD_KEY',          '',      'STRING',  'Shared key for /hangfire dashboard access outside Development (query ?key= or X-Hangfire-Key header). Empty = fail-closed — set a real value before relying on the dashboard in Staging/Production.', 0);

-- ════════════════════════════════════════════════════════════════
-- v5.0 NEW: Marketing & Communication Center — Phase 0 + Phase 1
-- Push + Email only. SMS blocked at three layers on purpose (Settings
-- toggle, CampaignChannel_Save guard, dispatcher check) until Fast2SMS
-- DLT registration completes. See MarketingCommunicationCenter_BRD_v1.0.docx.
-- ════════════════════════════════════════════════════════════════

-- ── Phase 0: User Communication Preferences ──────────────────────

DROP PROCEDURE IF EXISTS UserCommunicationPreference_Get;

DELIMITER //
CREATE PROCEDURE UserCommunicationPreference_Get(IN p_UserId INT UNSIGNED)
BEGIN
    -- No row yet = user is opted in to everything (defaults below), so a brand
    -- new user is reachable without needing a preferences row created up front.
    SELECT base.UserId AS UserId,
           COALESCE(ucp.ReceivePushNotifications, 1)      AS ReceivePushNotifications,
           COALESCE(ucp.ReceivePromotionalEmails, 1)      AS ReceivePromotionalEmails,
           COALESCE(ucp.ReceivePromotionalSms, 1)         AS ReceivePromotionalSms,
           COALESCE(ucp.ReceiveNgoUpdates, 1)             AS ReceiveNgoUpdates,
           COALESCE(ucp.ReceiveDonationAlerts, 1)          AS ReceiveDonationAlerts,
           COALESCE(ucp.ReceiveVolunteerOpportunities, 1) AS ReceiveVolunteerOpportunities
    FROM (SELECT p_UserId AS UserId) base
    LEFT JOIN UserCommunicationPreferences ucp ON ucp.UserId = base.UserId;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS UserCommunicationPreference_Update;

DELIMITER //
CREATE PROCEDURE UserCommunicationPreference_Update(
    IN p_UserId                        INT UNSIGNED,
    IN p_ReceivePushNotifications      TINYINT(1),
    IN p_ReceivePromotionalEmails      TINYINT(1),
    IN p_ReceivePromotionalSms         TINYINT(1),
    IN p_ReceiveNgoUpdates             TINYINT(1),
    IN p_ReceiveDonationAlerts         TINYINT(1),
    IN p_ReceiveVolunteerOpportunities TINYINT(1)
)
BEGIN
    INSERT INTO UserCommunicationPreferences (
        UserId, ReceivePushNotifications, ReceivePromotionalEmails, ReceivePromotionalSms,
        ReceiveNgoUpdates, ReceiveDonationAlerts, ReceiveVolunteerOpportunities, UpdatedAt
    ) VALUES (
        p_UserId,
        COALESCE(p_ReceivePushNotifications, 1), COALESCE(p_ReceivePromotionalEmails, 1), COALESCE(p_ReceivePromotionalSms, 1),
        COALESCE(p_ReceiveNgoUpdates, 1), COALESCE(p_ReceiveDonationAlerts, 1), COALESCE(p_ReceiveVolunteerOpportunities, 1),
        NOW()
    )
    ON DUPLICATE KEY UPDATE
        ReceivePushNotifications      = COALESCE(p_ReceivePushNotifications, ReceivePushNotifications),
        ReceivePromotionalEmails      = COALESCE(p_ReceivePromotionalEmails, ReceivePromotionalEmails),
        ReceivePromotionalSms         = COALESCE(p_ReceivePromotionalSms, ReceivePromotionalSms),
        ReceiveNgoUpdates             = COALESCE(p_ReceiveNgoUpdates, ReceiveNgoUpdates),
        ReceiveDonationAlerts         = COALESCE(p_ReceiveDonationAlerts, ReceiveDonationAlerts),
        ReceiveVolunteerOpportunities = COALESCE(p_ReceiveVolunteerOpportunities, ReceiveVolunteerOpportunities),
        UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Preferences updated.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Campaign CRUD ────────────────────────────────────────

DROP PROCEDURE IF EXISTS Campaign_Create;

DELIMITER //
CREATE PROCEDURE Campaign_Create(
    IN p_CampaignName     VARCHAR(200),
    IN p_InternalNotes    VARCHAR(1000),
    IN p_CampaignTypeCode VARCHAR(50),
    IN p_PriorityCode     VARCHAR(50),
    IN p_CreatedBy        INT UNSIGNED
)
BEGIN
    DECLARE v_TypeLkpId        INT UNSIGNED;
    DECLARE v_PriorityLkpId    INT UNSIGNED;
    DECLARE v_DraftStatusLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_TypeLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE' AND lv.ValueCode = p_CampaignTypeCode LIMIT 1;
    SELECT LookupValueId INTO v_PriorityLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY' AND lv.ValueCode = p_PriorityCode LIMIT 1;
    SELECT LookupValueId INTO v_DraftStatusLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS' AND lv.ValueCode = 'DRAFT' LIMIT 1;

    IF v_TypeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown campaign type: ', p_CampaignTypeCode) AS Message, NULL AS CampaignId;
    ELSEIF v_PriorityLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown priority: ', p_PriorityCode) AS Message, NULL AS CampaignId;
    ELSE
        INSERT INTO Campaigns (CampaignName, InternalNotes, CampaignTypeLkpId, PriorityLkpId, StatusLkpId, CreatedBy)
        VALUES (p_CampaignName, p_InternalNotes, v_TypeLkpId, v_PriorityLkpId, v_DraftStatusLkpId, p_CreatedBy);

        SELECT 1 AS IsSuccess, 'Campaign created.' AS Message, LAST_INSERT_ID() AS CampaignId;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_Update;

DELIMITER //
CREATE PROCEDURE Campaign_Update(
    IN p_CampaignId       INT UNSIGNED,
    IN p_CampaignName     VARCHAR(200),
    IN p_InternalNotes    VARCHAR(1000),
    IN p_CampaignTypeCode VARCHAR(50),
    IN p_PriorityCode     VARCHAR(50),
    IN p_ScheduleType     VARCHAR(20),
    IN p_ScheduledAt      DATETIME,
    IN p_TimezoneName     VARCHAR(60),
    IN p_UpdatedBy        INT UNSIGNED
)
BEGIN
    DECLARE v_TypeLkpId     INT UNSIGNED;
    DECLARE v_PriorityLkpId INT UNSIGNED;
    DECLARE v_CurrentStatusCode VARCHAR(50);

    SELECT lv.ValueCode INTO v_CurrentStatusCode
    FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;

    IF v_CurrentStatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Campaign not found.' AS Message;
    ELSEIF v_CurrentStatusCode NOT IN ('DRAFT', 'SCHEDULED') THEN
        SELECT 0 AS IsSuccess, 'Only Draft or Scheduled campaigns can be edited.' AS Message;
    ELSE
        IF p_CampaignTypeCode IS NOT NULL THEN
            SELECT LookupValueId INTO v_TypeLkpId FROM LookupValues lv
                JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE' AND lv.ValueCode = p_CampaignTypeCode LIMIT 1;
        END IF;
        IF p_PriorityCode IS NOT NULL THEN
            SELECT LookupValueId INTO v_PriorityLkpId FROM LookupValues lv
                JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY' AND lv.ValueCode = p_PriorityCode LIMIT 1;
        END IF;

        UPDATE Campaigns SET
            CampaignName      = COALESCE(p_CampaignName, CampaignName),
            InternalNotes     = COALESCE(p_InternalNotes, InternalNotes),
            CampaignTypeLkpId = COALESCE(v_TypeLkpId, CampaignTypeLkpId),
            PriorityLkpId     = COALESCE(v_PriorityLkpId, PriorityLkpId),
            ScheduleType      = COALESCE(p_ScheduleType, ScheduleType),
            ScheduledAt       = COALESCE(p_ScheduledAt, ScheduledAt),
            TimezoneName      = COALESCE(p_TimezoneName, TimezoneName),
            UpdatedBy         = p_UpdatedBy,
            UpdatedAt         = NOW()
        WHERE CampaignId = p_CampaignId;

        SELECT 1 AS IsSuccess, 'Campaign updated.' AS Message;
    END IF;
END //
DELIMITER ;

-- Generic status transition — used by the /cancel endpoint and internally by
-- the Hangfire dispatch job (Running/Completed/Failed). Terminal states
-- (Completed/Cancelled/Failed) can never transition again.
DROP PROCEDURE IF EXISTS Campaign_SetStatus;

DELIMITER //
CREATE PROCEDURE Campaign_SetStatus(
    IN p_CampaignId    INT UNSIGNED,
    IN p_NewStatusCode VARCHAR(50),
    IN p_HangfireJobId VARCHAR(100),
    IN p_UpdatedBy     INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusCode VARCHAR(50);
    DECLARE v_NewStatusLkpId    INT UNSIGNED;

    SELECT lv.ValueCode INTO v_CurrentStatusCode
    FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;

    IF v_CurrentStatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Campaign not found.' AS Message;
    ELSEIF v_CurrentStatusCode IN ('COMPLETED', 'CANCELLED', 'FAILED') THEN
        SELECT 0 AS IsSuccess, CONCAT('Campaign is already ', v_CurrentStatusCode, ' and cannot change state.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_NewStatusLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS' AND lv.ValueCode = p_NewStatusCode LIMIT 1;

        IF v_NewStatusLkpId IS NULL THEN
            SELECT 0 AS IsSuccess, CONCAT('Unknown status: ', p_NewStatusCode) AS Message;
        ELSE
            UPDATE Campaigns SET
                StatusLkpId   = v_NewStatusLkpId,
                HangfireJobId = COALESCE(p_HangfireJobId, HangfireJobId),
                UpdatedBy     = p_UpdatedBy,
                UpdatedAt     = NOW()
            WHERE CampaignId = p_CampaignId;

            SELECT 1 AS IsSuccess, CONCAT('Campaign status set to ', p_NewStatusCode, '.') AS Message;
        END IF;
    END IF;
END //
DELIMITER ;


-- ── Phase 1: Channels (Push + Email only — SMS/WhatsApp guarded here too) ──

DROP PROCEDURE IF EXISTS CampaignChannel_Save;

DELIMITER //
CREATE PROCEDURE CampaignChannel_Save(
    IN p_CampaignId      INT UNSIGNED,
    IN p_ChannelCode     VARCHAR(20),
    IN p_PushTitle       VARCHAR(200),
    IN p_PushBody        VARCHAR(500),
    IN p_PushImageUrl    VARCHAR(500),
    IN p_PushDeepLink    VARCHAR(500),
    IN p_PushActionLabel VARCHAR(50),
    IN p_EmailSubject    VARCHAR(255),
    IN p_EmailHtmlBody   MEDIUMTEXT
)
BEGIN
    DECLARE v_ChannelLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_ChannelLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode LIMIT 1;

    IF v_ChannelLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown channel: ', p_ChannelCode) AS Message;
    ELSEIF p_ChannelCode IN ('SMS', 'WHATSAPP') THEN
        -- Phase 1 scope guard — see Settings.COMMUNICATION.CAMPAIGN_SMS_ENABLED
        SELECT 0 AS IsSuccess, CONCAT(p_ChannelCode, ' channel is not yet enabled for campaigns.') AS Message;
    ELSE
        INSERT INTO CampaignChannels (
            CampaignId, ChannelLkpId, PushTitle, PushBody, PushImageUrl, PushDeepLink, PushActionLabel,
            EmailSubject, EmailHtmlBody
        ) VALUES (
            p_CampaignId, v_ChannelLkpId, p_PushTitle, p_PushBody, p_PushImageUrl, p_PushDeepLink, p_PushActionLabel,
            p_EmailSubject, p_EmailHtmlBody
        )
        ON DUPLICATE KEY UPDATE
            PushTitle       = VALUES(PushTitle),
            PushBody        = VALUES(PushBody),
            PushImageUrl    = VALUES(PushImageUrl),
            PushDeepLink    = VALUES(PushDeepLink),
            PushActionLabel = VALUES(PushActionLabel),
            EmailSubject    = VALUES(EmailSubject),
            EmailHtmlBody   = VALUES(EmailHtmlBody),
            UpdatedAt       = NOW();

        SELECT 1 AS IsSuccess, 'Channel saved.' AS Message;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignChannel_Delete;

DELIMITER //
CREATE PROCEDURE CampaignChannel_Delete(IN p_CampaignId INT UNSIGNED, IN p_ChannelCode VARCHAR(20))
BEGIN
    DELETE cc FROM CampaignChannels cc
    JOIN LookupValues lv ON lv.LookupValueId = cc.ChannelLkpId
    JOIN LookupTypes lt  ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE cc.CampaignId = p_CampaignId AND lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode;

    SELECT 1 AS IsSuccess, 'Channel removed.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Audience Rule (single rule per campaign — see BRD Phase 2 for the
--    composable, reusable Segment Builder) ─────────────────────────────────

DROP PROCEDURE IF EXISTS CampaignAudienceRule_Save;

DELIMITER //
CREATE PROCEDURE CampaignAudienceRule_Save(
    IN p_CampaignId    INT UNSIGNED,
    IN p_RuleType      VARCHAR(30),
    IN p_RuleValueJson JSON
)
BEGIN
    IF p_RuleType NOT IN ('ALL', 'ACTIVE', 'INACTIVE', 'NEW', 'BY_ORG', 'BY_ROLE') THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown audience rule type: ', p_RuleType) AS Message;
    ELSE
        DELETE FROM CampaignAudienceRules WHERE CampaignId = p_CampaignId;
        INSERT INTO CampaignAudienceRules (CampaignId, RuleType, RuleValueJson)
        VALUES (p_CampaignId, p_RuleType, p_RuleValueJson);

        SELECT 1 AS IsSuccess, 'Audience rule saved.' AS Message;
    END IF;
END //
DELIMITER ;

-- Estimates (and caches onto Campaigns.EstimatedRecipients) the recipient count
-- for the campaign's current audience rule. Called on-demand from the wizard
-- (step transitions), not per keystroke — a live COUNT() here is a deliberate,
-- documented simplification of the BRD's fuller pre-aggregated-cache proposal;
-- revisit if usage patterns make this a real hot path.
-- 'BY_ROLE' roleCodes accepts FOUNDER / ADMIN / MODERATOR / MEMBER (MEMBER_ROLE
-- lookup codes) plus the virtual code DONOR (resolved via DonationTransactions,
-- which is not an OrgMembers role at all).
DROP PROCEDURE IF EXISTS Campaign_EstimateAudience;

DELIMITER //
CREATE PROCEDURE Campaign_EstimateAudience(IN p_CampaignId INT UNSIGNED)
BEGIN
    DECLARE v_RuleType VARCHAR(30);
    DECLARE v_RuleJson JSON;
    DECLARE v_Count     INT UNSIGNED DEFAULT 0;

    SELECT RuleType, RuleValueJson INTO v_RuleType, v_RuleJson
    FROM CampaignAudienceRules
    WHERE CampaignId = p_CampaignId
    ORDER BY CampaignAudienceRuleId DESC
    LIMIT 1;

    IF v_RuleType = 'ALL' THEN
        SELECT COUNT(*) INTO v_Count FROM Users WHERE IsDeleted = 0 AND IsActive = 1;

    ELSEIF v_RuleType = 'ACTIVE' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND LastLoginAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'INACTIVE' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND (LastLoginAt IS NULL OR LastLoginAt < DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '30') AS UNSIGNED) DAY));

    ELSEIF v_RuleType = 'NEW' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND CreatedAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'BY_ORG' THEN
        SELECT COUNT(DISTINCT om.UserId) INTO v_Count
        FROM OrgMembers om
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.orgIds', CAST(om.OrgId AS JSON));

    ELSEIF v_RuleType = 'BY_ROLE' THEN
        SELECT COUNT(DISTINCT combined.UserId) INTO v_Count
        FROM (
            SELECT om.UserId
            FROM OrgMembers om
            JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
            JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
            WHERE om.IsDeleted = 0
              AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE(lv.ValueCode))
            UNION
            SELECT dt.DonorUserId
            FROM DonationTransactions dt
            JOIN Users u ON u.UserId = dt.DonorUserId AND u.IsDeleted = 0 AND u.IsActive = 1
            WHERE dt.DonorUserId IS NOT NULL
              AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE('DONOR'))
        ) combined;
    END IF;

    UPDATE Campaigns SET EstimatedRecipients = v_Count WHERE CampaignId = p_CampaignId;

    SELECT p_CampaignId AS CampaignId, v_Count AS EstimatedRecipients, v_RuleType AS RuleType;
END //
DELIMITER ;

-- Resolves the campaign's audience rule into concrete CampaignRecipients rows,
-- fanned out across every selected channel, skipping opted-out users and users
-- with no valid delivery address for that channel. Safe to call more than once
-- (INSERT IGNORE on the CampaignId+UserId+ChannelLkpId unique key).
DROP PROCEDURE IF EXISTS Campaign_ResolveRecipients;

DELIMITER //
CREATE PROCEDURE Campaign_ResolveRecipients(IN p_CampaignId INT UNSIGNED)
BEGIN
    DECLARE v_RuleType VARCHAR(30);
    DECLARE v_RuleJson JSON;

    SELECT RuleType, RuleValueJson INTO v_RuleType, v_RuleJson
    FROM CampaignAudienceRules
    WHERE CampaignId = p_CampaignId
    ORDER BY CampaignAudienceRuleId DESC
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_campaign_audience;
    CREATE TEMPORARY TABLE tmp_campaign_audience (UserId INT UNSIGNED PRIMARY KEY);

    IF v_RuleType = 'ALL' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users WHERE IsDeleted = 0 AND IsActive = 1;

    ELSEIF v_RuleType = 'ACTIVE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND LastLoginAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'INACTIVE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND (LastLoginAt IS NULL OR LastLoginAt < DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '30') AS UNSIGNED) DAY));

    ELSEIF v_RuleType = 'NEW' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND CreatedAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'BY_ORG' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT om.UserId
        FROM OrgMembers om
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.orgIds', CAST(om.OrgId AS JSON));

    ELSEIF v_RuleType = 'BY_ROLE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT om.UserId
        FROM OrgMembers om
        JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE(lv.ValueCode));

        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT dt.DonorUserId
        FROM DonationTransactions dt
        JOIN Users u ON u.UserId = dt.DonorUserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE dt.DonorUserId IS NOT NULL
          AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE('DONOR'));
    END IF;

    INSERT IGNORE INTO CampaignRecipients (CampaignId, UserId, ChannelLkpId, QueueStatus)
    SELECT p_CampaignId, a.UserId, cc.ChannelLkpId,
        CASE
            WHEN lv_ch.ValueCode = 'PUSH'  AND COALESCE(pref.ReceivePushNotifications, 1) = 0 THEN 'SKIPPED_OPTOUT'
            WHEN lv_ch.ValueCode = 'EMAIL' AND COALESCE(pref.ReceivePromotionalEmails, 1) = 0 THEN 'SKIPPED_OPTOUT'
            WHEN lv_ch.ValueCode = 'PUSH'  AND NOT EXISTS (SELECT 1 FROM UserDeviceTokens dt WHERE dt.UserId = a.UserId) THEN 'SKIPPED_NO_ADDRESS'
            WHEN lv_ch.ValueCode = 'EMAIL' AND u.Email IS NULL THEN 'SKIPPED_NO_ADDRESS'
            ELSE 'QUEUED'
        END
    FROM tmp_campaign_audience a
    JOIN Users u ON u.UserId = a.UserId
    JOIN CampaignChannels cc ON cc.CampaignId = p_CampaignId
    JOIN LookupValues lv_ch  ON lv_ch.LookupValueId = cc.ChannelLkpId
    LEFT JOIN UserCommunicationPreferences pref ON pref.UserId = a.UserId;

    DROP TEMPORARY TABLE IF EXISTS tmp_campaign_audience;

    SELECT 1 AS IsSuccess, 'Recipients resolved.' AS Message,
           (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = p_CampaignId) AS TotalRecipients,
           (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = p_CampaignId AND QueueStatus = 'QUEUED') AS QueuedRecipients;
END //
DELIMITER ;


-- ── Phase 1: Dispatch support (called by the Hangfire background job) ─────

DROP PROCEDURE IF EXISTS Campaign_GetQueuedRecipients;

DELIMITER //
CREATE PROCEDURE Campaign_GetQueuedRecipients(
    IN p_CampaignId  INT UNSIGNED,
    IN p_ChannelCode VARCHAR(20),
    IN p_BatchSize   INT
)
BEGIN
    SELECT cr.CampaignRecipientId, cr.UserId, u.Email,
           cc.PushTitle, cc.PushBody, cc.PushImageUrl, cc.PushDeepLink,
           cc.EmailSubject, cc.EmailHtmlBody
    FROM CampaignRecipients cr
    JOIN LookupValues lv      ON lv.LookupValueId = cr.ChannelLkpId
    JOIN Users u              ON u.UserId = cr.UserId
    JOIN CampaignChannels cc  ON cc.CampaignId = cr.CampaignId AND cc.ChannelLkpId = cr.ChannelLkpId
    WHERE cr.CampaignId = p_CampaignId
      AND lv.ValueCode = p_ChannelCode
      AND cr.QueueStatus = 'QUEUED'
    ORDER BY cr.CampaignRecipientId
    LIMIT p_BatchSize;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignRecipient_MarkStatus;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_MarkStatus(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_StatusCode          VARCHAR(20),
    IN p_ProviderMessageId   VARCHAR(255),
    IN p_FailReason          VARCHAR(500)
)
BEGIN
    UPDATE CampaignRecipients SET
        QueueStatus       = p_StatusCode,
        ProviderMessageId = COALESCE(p_ProviderMessageId, ProviderMessageId),
        FailReason        = COALESCE(p_FailReason, FailReason),
        SentAt            = CASE WHEN p_StatusCode = 'SENT'      THEN NOW() ELSE SentAt      END,
        DeliveredAt       = CASE WHEN p_StatusCode = 'DELIVERED' THEN NOW() ELSE DeliveredAt END,
        RetryCount        = CASE WHEN p_StatusCode = 'FAILED'    THEN RetryCount + 1 ELSE RetryCount END
    WHERE CampaignRecipientId = p_CampaignRecipientId;

    SELECT 1 AS IsSuccess, 'Recipient status updated.' AS Message;
END //
DELIMITER ;

-- Hook for future open/click tracking (pixel + redirect endpoints are a small
-- follow-up, not wired in Phase 1 — see MarketingCommunicationCenter_BRD_v1.0.docx
-- Section 8, "Rich HTML Editor" is Phase 2 scope, tracking pixel belongs with it).
DROP PROCEDURE IF EXISTS CampaignRecipient_MarkEngagement;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_MarkEngagement(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_EngagementType      VARCHAR(20) -- OPENED | CLICKED
)
BEGIN
    UPDATE CampaignRecipients SET
        OpenedAt  = CASE WHEN p_EngagementType = 'OPENED'  AND OpenedAt  IS NULL THEN NOW() ELSE OpenedAt  END,
        ClickedAt = CASE WHEN p_EngagementType = 'CLICKED' AND ClickedAt IS NULL THEN NOW() ELSE ClickedAt END
    WHERE CampaignRecipientId = p_CampaignRecipientId;

    SELECT 1 AS IsSuccess, 'Engagement recorded.' AS Message;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignQueueJob_Create;

DELIMITER //
CREATE PROCEDURE CampaignQueueJob_Create(
    IN p_CampaignId   INT UNSIGNED,
    IN p_BatchNumber  INT UNSIGNED,
    IN p_ChannelCode  VARCHAR(20),
    IN p_BatchSize    INT UNSIGNED
)
BEGIN
    DECLARE v_ChannelLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_ChannelLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode LIMIT 1;

    INSERT INTO CampaignQueueJobs (CampaignId, BatchNumber, ChannelLkpId, BatchSize, Status, StartedAt)
    VALUES (p_CampaignId, p_BatchNumber, v_ChannelLkpId, p_BatchSize, 'PROCESSING', NOW());

    SELECT 1 AS IsSuccess, 'Queue job created.' AS Message, LAST_INSERT_ID() AS CampaignQueueJobId;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignQueueJob_MarkStatus;

DELIMITER //
CREATE PROCEDURE CampaignQueueJob_MarkStatus(
    IN p_CampaignQueueJobId BIGINT UNSIGNED,
    IN p_Status             VARCHAR(20),
    IN p_ErrorMessage       VARCHAR(1000)
)
BEGIN
    UPDATE CampaignQueueJobs SET
        Status       = p_Status,
        ErrorMessage = COALESCE(p_ErrorMessage, ErrorMessage),
        RetryCount   = CASE WHEN p_Status = 'FAILED' THEN RetryCount + 1 ELSE RetryCount END,
        CompletedAt  = CASE WHEN p_Status IN ('COMPLETED', 'FAILED') THEN NOW() ELSE CompletedAt END
    WHERE CampaignQueueJobId = p_CampaignQueueJobId;

    SELECT 1 AS IsSuccess, 'Queue job status updated.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Lists, detail, dashboard ─────────────────────────────

DROP PROCEDURE IF EXISTS Campaign_GetList;

DELIMITER //
CREATE PROCEDURE Campaign_GetList(
    IN p_StatusCode VARCHAR(50),
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT c.CampaignId, c.CampaignName, c.ScheduleType, c.ScheduledAt, c.EstimatedRecipients,
           lv_type.ValueCode   AS CampaignTypeCode, lv_type.ValueName AS CampaignTypeName,
           lv_pri.ValueCode    AS PriorityCode,
           lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
           c.CreatedAt, c.CreatedBy,
           CONCAT(up.FirstName, ' ', up.LastName) AS CreatedByName,
           (SELECT GROUP_CONCAT(lv_ch.ValueCode) FROM CampaignChannels cc
              JOIN LookupValues lv_ch ON lv_ch.LookupValueId = cc.ChannelLkpId
              WHERE cc.CampaignId = c.CampaignId) AS Channels,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId) AS TotalRecipients,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus IN ('SENT','DELIVERED')) AS DeliveredCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.OpenedAt IS NOT NULL) AS OpenedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.ClickedAt IS NOT NULL) AS ClickedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus = 'FAILED') AS FailedCount
    FROM Campaigns c
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = c.CampaignTypeLkpId
    JOIN LookupValues lv_pri    ON lv_pri.LookupValueId    = c.PriorityLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    LEFT JOIN UserProfiles up ON up.UserId = c.CreatedBy
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'))
    ORDER BY c.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Campaigns c
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'));
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_GetById;

DELIMITER //
CREATE PROCEDURE Campaign_GetById(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT c.CampaignId, c.CampaignName, c.InternalNotes,
           lv_type.ValueCode   AS CampaignTypeCode,
           lv_pri.ValueCode    AS PriorityCode,
           lv_status.ValueCode AS StatusCode,
           c.ScheduleType, c.ScheduledAt, c.TimezoneName, c.EstimatedRecipients,
           c.CreatedAt, c.CreatedBy, c.UpdatedAt,
           (SELECT RuleType FROM CampaignAudienceRules WHERE CampaignId = c.CampaignId ORDER BY CampaignAudienceRuleId DESC LIMIT 1) AS AudienceRuleType,
           (SELECT RuleValueJson FROM CampaignAudienceRules WHERE CampaignId = c.CampaignId ORDER BY CampaignAudienceRuleId DESC LIMIT 1) AS AudienceRuleValueJson,
           (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                'channelCode',     lv_ch.ValueCode,
                'pushTitle',       cc.PushTitle,
                'pushBody',        cc.PushBody,
                'pushImageUrl',    cc.PushImageUrl,
                'pushDeepLink',    cc.PushDeepLink,
                'pushActionLabel', cc.PushActionLabel,
                'emailSubject',    cc.EmailSubject,
                'emailHtmlBody',   cc.EmailHtmlBody
            ))
            FROM CampaignChannels cc
            JOIN LookupValues lv_ch ON lv_ch.LookupValueId = cc.ChannelLkpId
            WHERE cc.CampaignId = c.CampaignId) AS ChannelsJson
    FROM Campaigns c
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = c.CampaignTypeLkpId
    JOIN LookupValues lv_pri    ON lv_pri.LookupValueId    = c.PriorityLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_GetHistoryDetail;

DELIMITER //
CREATE PROCEDURE Campaign_GetHistoryDetail(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        c.CampaignId, c.CampaignName,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId) AS TotalRecipients,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus IN ('SENT','DELIVERED')) AS DeliveredCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND OpenedAt IS NOT NULL) AS OpenedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND ClickedAt IS NOT NULL) AS ClickedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus = 'FAILED') AS FailedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus LIKE 'SKIPPED%') AS SkippedCount
    FROM Campaigns c
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;
END //
DELIMITER ;

-- Lightweight contact lookup for the /test-send preview action — deliberately
-- does not touch CampaignRecipients (test sends must never pollute real metrics).
DROP PROCEDURE IF EXISTS User_GetContactsByIds;

DELIMITER //
CREATE PROCEDURE User_GetContactsByIds(IN p_UserIdsCsv VARCHAR(2000))
BEGIN
    SELECT UserId, Email FROM Users
    WHERE IsDeleted = 0 AND FIND_IN_SET(UserId, p_UserIdsCsv) > 0;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Communication_GetDashboardStats;

DELIMITER //
CREATE PROCEDURE Communication_GetDashboardStats()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'PUSH'  AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalPushSent,
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'EMAIL' AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalEmailSent,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus = 'FAILED') AS TotalFailed,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus IN ('SENT','DELIVERED')) AS TotalDelivered,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus NOT LIKE 'SKIPPED%') AS TotalAttempted,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE OpenedAt IS NOT NULL) AS TotalOpened,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE ClickedAt IS NOT NULL) AS TotalClicked,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'RUNNING'   AND c.IsDeleted = 0) AS ActiveCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'SCHEDULED' AND c.IsDeleted = 0) AS ScheduledCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'DRAFT'     AND c.IsDeleted = 0) AS DraftCampaigns;
END //
DELIMITER ;

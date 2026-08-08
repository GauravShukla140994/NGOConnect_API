-- ============================================================
-- NGOConnect Patch: Org Member Invitations (v4.9)
-- Date   : 2026-07-21
-- Author : NGO Connect Architect
-- Scope  : NEW table, 2 LookupTypes, 8 LookupValues,
--          5 Settings rows, 7 Stored Procedures
-- Run on : LOCAL first → Railway staging → Railway production
-- Safe   : All CREATE/INSERT are guarded; DROPs are on SPs only
-- ============================================================

-- ============================================================
-- STEP 1: NEW TABLE — OrgInvitations
-- ============================================================

CREATE TABLE IF NOT EXISTS OrgInvitations (
    OrgInvitationId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED    NOT NULL,
    InvitedByUserId   INT UNSIGNED    NOT NULL,
    InviteTypeLkpId   INT UNSIGNED    NOT NULL,   -- INVITE_TYPE: PHONE | EMAIL
    InviteValue       VARCHAR(255)    NOT NULL,    -- normalised phone or email
    CountryCode       VARCHAR(6)      NULL,        -- PHONE only
    InvitedUserId     INT UNSIGNED    NULL,        -- NULL = user not yet on platform
    InviteToken       VARCHAR(128)    NOT NULL,    -- cryptographically random, URL-safe base64
    TokenExpiry       DATETIME        NOT NULL,
    StatusLkpId       INT UNSIGNED    NOT NULL,    -- INVITE_STATUS
    DeliveryStatus    VARCHAR(20)     NULL,        -- SENT | DELIVERED | FAILED
    SentAt            DATETIME        NULL,
    OpenedAt          DATETIME        NULL,
    AcceptedAt        DATETIME        NULL,
    CancelledAt       DATETIME        NULL,
    IsDeleted         TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt         DATETIME        NULL,
    DeletedBy         INT UNSIGNED    NULL,
    CreatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (OrgInvitationId),
    UNIQUE KEY uq_orginvite_token    (InviteToken),
    INDEX idx_orginvite_org          (OrgId, StatusLkpId, IsDeleted),
    INDEX idx_orginvite_value        (InviteValue(100), IsDeleted),
    INDEX idx_orginvite_inviteduser  (InvitedUserId, IsDeleted),
    INDEX idx_orginvite_expiry       (TokenExpiry),
    CONSTRAINT fk_orginvite_org         FOREIGN KEY (OrgId)           REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orginvite_invitedby   FOREIGN KEY (InvitedByUserId) REFERENCES Users(UserId),
    CONSTRAINT fk_orginvite_inviteduser FOREIGN KEY (InvitedUserId)   REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- STEP 2: LOOKUP TYPES — INVITE_TYPE, INVITE_STATUS
-- ============================================================

INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
VALUES
    ('INVITE_TYPE',   'Invite Type',   'Channel used to send an org member invitation', 1, 1),
    ('INVITE_STATUS', 'Invite Status', 'Current state of an org member invitation',     1, 1);

-- ============================================================
-- STEP 3: LOOKUP VALUES
-- ============================================================

-- INVITE_TYPE values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PHONE' AS ValueCode, 'Phone Number' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'EMAIL',              'Email Address',              2
) v ON 1=1
WHERE lt.TypeCode = 'INVITE_TYPE'
  AND NOT EXISTS (
      SELECT 1 FROM LookupValues lv2
      JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
      WHERE lt2.TypeCode = 'INVITE_TYPE' AND lv2.ValueCode = v.ValueCode
  );

-- INVITE_STATUS values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PENDING'   AS ValueCode, 'Pending'   AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'OPENED',                 'Opened',                 2 UNION ALL
    SELECT 'ACCEPTED',               'Accepted',               3 UNION ALL
    SELECT 'REJECTED',               'Rejected',               4 UNION ALL
    SELECT 'CANCELLED',              'Cancelled',              5 UNION ALL
    SELECT 'EXPIRED',                'Expired',                6
) v ON 1=1
WHERE lt.TypeCode = 'INVITE_STATUS'
  AND NOT EXISTS (
      SELECT 1 FROM LookupValues lv2
      JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
      WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = v.ValueCode
  );

-- ============================================================
-- STEP 4: SETTINGS
-- ============================================================

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
    ('INVITE', 'INVITE_BASE_URL',          'https://ripplehub.app/invite/', 'URL',     'Base URL for org member invitation deep links (swap per env)', 0),
    ('INVITE', 'INVITE_TOKEN_EXPIRY_DAYS', '30',                            'NUMBER',  'Invitation link expiry in days',                              0),
    ('INVITE', 'INVITE_SINGLE_USE',        'true',                          'BOOLEAN', 'Invitation token can only be consumed once',                  0),
    ('SMS',    'SMS_TEMPLATE_INVITE',      '{inviter} invited you to join {orgName} on RippleHub. Join the community: {link}', 'STRING', 'SMS template for org invitations', 0),
    ('EMAIL',  'EMAIL_TEMPLATE_INVITE',    'org_invitation',                'STRING',  'Email template key for org invitations',                      0);

-- ============================================================
-- STEP 5: STORED PROCEDURES (7 total)
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Send
-- Sends an org member invitation via Phone or Email.
-- Pre-checks: permission, self-invite, duplicate member,
--             duplicate active invite.
-- Returns: IsSuccess, Message, InvitationId, ExistingUserFound,
--          profile preview (if existing user), InviteLink
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Send //
CREATE PROCEDURE Org_Invite_Send(
    IN p_OrgId            INT UNSIGNED,
    IN p_InvitedByUserId  INT UNSIGNED,
    IN p_InviteTypeCode   VARCHAR(20),
    IN p_InviteValue      VARCHAR(255),
    IN p_CountryCode      VARCHAR(6),
    IN p_InviteToken      VARCHAR(128),
    IN p_TokenExpiry      DATETIME,
    IN p_InviteBaseUrl    VARCHAR(500)
)
main_block: BEGIN
    DECLARE v_InviteTypeLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_InviterRoleCode    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ExistingUserId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_IsMember           TINYINT(1)   DEFAULT 0;
    DECLARE v_PendingInviteId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_NewInvitationId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExistingUserName   VARCHAR(161) DEFAULT NULL;
    DECLARE v_ExistingUserPhoto  VARCHAR(500) DEFAULT NULL;
    DECLARE v_ExistingUserCity   VARCHAR(100) DEFAULT NULL;
    DECLARE v_ExistingUserOrgCt  INT UNSIGNED DEFAULT 0;
    DECLARE v_OrgName            VARCHAR(200) DEFAULT NULL;

    -- 1. Verify inviter has FOUNDER or ADMIN role
    SELECT lv.ValueCode INTO v_InviterRoleCode
    FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = p_OrgId AND om.UserId = p_InvitedByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_InviterRoleCode IS NULL OR v_InviterRoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to invite members.' AS Message,
               NULL AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- 2. Resolve existing user by phone or email
    IF p_InviteTypeCode = 'PHONE' THEN
        SELECT UserId INTO v_ExistingUserId FROM Users
        WHERE Mobile = p_InviteValue AND IsDeleted = 0 LIMIT 1;
    ELSE
        SELECT UserId INTO v_ExistingUserId FROM Users
        WHERE Email = LOWER(p_InviteValue) AND IsDeleted = 0 LIMIT 1;
    END IF;

    -- Guard: self-invite
    IF v_ExistingUserId = p_InvitedByUserId THEN
        SELECT 0 AS IsSuccess, 'You cannot invite yourself.' AS Message,
               NULL AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- Guard: already a member
    IF v_ExistingUserId IS NOT NULL THEN
        SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
        WHERE OrgId = p_OrgId AND UserId = v_ExistingUserId AND IsDeleted = 0;

        IF v_IsMember > 0 THEN
            SELECT 0 AS IsSuccess, 'This user is already a member of your organisation.' AS Message,
                   NULL AS InvitationId, 1 AS ExistingUserFound, v_ExistingUserId AS ExistingUserId,
                   NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
                   0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
            LEAVE main_block;
        END IF;
    END IF;

    -- Guard: duplicate active invitation
    SELECT OrgInvitationId INTO v_PendingInviteId
    FROM OrgInvitations
    WHERE OrgId = p_OrgId
      AND InviteValue = p_InviteValue
      AND IsDeleted = 0
      AND TokenExpiry > NOW()
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                         JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                         WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING')
    LIMIT 1;

    IF v_PendingInviteId IS NOT NULL THEN
        SELECT 0 AS IsSuccess, 'An active invitation already exists for this contact. Use Resend Invitation to refresh it.' AS Message,
               v_PendingInviteId AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- 3. Resolve lookup IDs
    SELECT LookupValueId INTO v_InviteTypeLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_TYPE' AND lv.ValueCode = p_InviteTypeCode LIMIT 1;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- 4. Insert invitation
    INSERT INTO OrgInvitations (
        OrgId, InvitedByUserId, InviteTypeLkpId, InviteValue, CountryCode,
        InvitedUserId, InviteToken, TokenExpiry, StatusLkpId, SentAt
    ) VALUES (
        p_OrgId, p_InvitedByUserId, v_InviteTypeLkpId, p_InviteValue, p_CountryCode,
        v_ExistingUserId, p_InviteToken, p_TokenExpiry, v_StatusLkpId, NOW()
    );

    SET v_NewInvitationId = LAST_INSERT_ID();

    -- 5. In-app notification if existing user
    IF v_ExistingUserId IS NOT NULL THEN
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = p_OrgId LIMIT 1;

        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_ExistingUserId, p_OrgId,
            'ORG_INVITE',
            CONCAT(v_OrgName, ' invited you to join their organisation'),
            CONCAT('You have been invited to join ', v_OrgName, '. Tap to view the organisation and accept the invitation.'),
            v_NewInvitationId, 'ORG_INVITATION'
        );

        SELECT CONCAT(up.FirstName, ' ', up.LastName), up.ProfilePhoto, up.City
        INTO v_ExistingUserName, v_ExistingUserPhoto, v_ExistingUserCity
        FROM UserProfiles up WHERE up.UserId = v_ExistingUserId LIMIT 1;

        SELECT COUNT(*) INTO v_ExistingUserOrgCt FROM OrgMembers
        WHERE UserId = v_ExistingUserId AND IsDeleted = 0;
    END IF;

    -- 6. Return
    SELECT 1 AS IsSuccess,
           IF(v_ExistingUserId IS NOT NULL,
              'Invitation sent. The user has been notified in-app.',
              'Invitation created. Send the link via SMS or Email.') AS Message,
           v_NewInvitationId AS InvitationId,
           IF(v_ExistingUserId IS NOT NULL, 1, 0) AS ExistingUserFound,
           v_ExistingUserId       AS ExistingUserId,
           v_ExistingUserName     AS ExistingUserName,
           v_ExistingUserPhoto    AS ExistingUserPhoto,
           v_ExistingUserCity     AS ExistingUserCity,
           v_ExistingUserOrgCt    AS ExistingUserOrgCount,
           p_InviteToken          AS InviteToken,
           CONCAT(p_InviteBaseUrl, p_InviteToken) AS InviteLink;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_VerifyToken
-- Called by deep link handler (public, before login).
-- Returns org info + invitation details + marks as OPENED.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_VerifyToken //
CREATE PROCEDURE Org_Invite_VerifyToken(
    IN p_Token VARCHAR(128)
)
main_block: BEGIN
    DECLARE v_StatusCode  VARCHAR(20) DEFAULT NULL;

    SELECT lv.ValueCode INTO v_StatusCode
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.InviteToken = p_Token AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_StatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'INVALID_TOKEN'   AS ErrorCode, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode = 'CANCELLED' THEN
        SELECT 0 AS IsSuccess, 'INVITE_CANCELLED' AS ErrorCode, 'This invitation has been cancelled.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode = 'ACCEPTED' THEN
        SELECT 0 AS IsSuccess, 'INVITE_USED'      AS ErrorCode, 'This invitation has already been accepted.' AS Message;
        LEAVE main_block;
    END IF;

    -- Auto-expire lapsed PENDING invites
    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE InviteToken = p_Token AND TokenExpiry < NOW()
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                         JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                         WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING')
      AND IsDeleted = 0;

    -- Return full context
    SELECT
        1                       AS IsSuccess,
        NULL                    AS ErrorCode,
        'Valid invitation.'     AS Message,
        oi.OrgInvitationId,
        oi.OrgId,
        o.OrgName,
        o.LogoUrl               AS OrgLogo,
        o.City                  AS OrgCity,
        o.About                 AS OrgAbout,
        lv_status.ValueCode     AS StatusCode,
        lv_type.ValueCode       AS InviteType,
        oi.InviteValue,
        oi.CountryCode,
        oi.InvitedUserId,
        oi.TokenExpiry,
        CONCAT(up.FirstName, ' ', up.LastName) AS InvitedByName,
        up.ProfilePhoto         AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN Organisations o         ON o.OrgId = oi.OrgId
    JOIN LookupValues lv_status  ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN LookupValues lv_type    ON lv_type.LookupValueId   = oi.InviteTypeLkpId
    JOIN UserProfiles up         ON up.UserId = oi.InvitedByUserId
    WHERE oi.InviteToken = p_Token AND oi.IsDeleted = 0
    LIMIT 1;

    -- Mark PENDING → OPENED (idempotent)
    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'OPENED'),
        OpenedAt    = IFNULL(OpenedAt, NOW())
    WHERE InviteToken = p_Token
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                         JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                         WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING')
      AND IsDeleted = 0;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Accept
-- Authenticated user accepts an invitation.
-- Creates OrgMembershipRequest (pending admin approval).
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Accept //
CREATE PROCEDURE Org_Invite_Accept(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId           INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode      VARCHAR(20)  DEFAULT NULL;
    DECLARE v_IsMember        TINYINT(1)   DEFAULT 0;
    DECLARE v_HasRequest      TINYINT(1)   DEFAULT 0;
    DECLARE v_AcceptedLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_PendingReqLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName         VARCHAR(200) DEFAULT NULL;

    SELECT oi.OrgId, lv.ValueCode
    INTO v_OrgId, v_StatusCode
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message, NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess,
               CASE v_StatusCode
                   WHEN 'ACCEPTED'  THEN 'This invitation has already been accepted.'
                   WHEN 'CANCELLED' THEN 'This invitation has been cancelled.'
                   WHEN 'EXPIRED'   THEN 'This invitation has expired.'
                   ELSE 'Invitation is no longer valid.'
               END AS Message,
               NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    IF NOW() > (SELECT TokenExpiry FROM OrgInvitations WHERE OrgInvitationId = p_InvitationId) THEN
        SELECT 0 AS IsSuccess, 'This invitation has expired.' AS Message, NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsMember > 0 THEN
        SELECT 0 AS IsSuccess, 'You are already a member of this organisation.' AS Message, NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    SELECT COUNT(*) INTO v_HasRequest FROM OrgMembershipRequests
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    SELECT LookupValueId INTO v_AcceptedLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'ACCEPTED' LIMIT 1;

    SELECT LookupValueId INTO v_PendingReqLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    UPDATE OrgInvitations
    SET StatusLkpId   = v_AcceptedLkpId,
        AcceptedAt    = NOW(),
        InvitedUserId = p_UserId
    WHERE OrgInvitationId = p_InvitationId;

    IF v_HasRequest = 0 THEN
        INSERT INTO OrgMembershipRequests (OrgId, UserId, WhyJoin, StatusLkpId)
        VALUES (v_OrgId, p_UserId, 'Accepted via invitation link.', v_PendingReqLkpId);
    END IF;

    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId;

    SELECT 1 AS IsSuccess,
           CONCAT('Your request to join ', v_OrgName, ' has been submitted. You will be notified when approved.') AS Message,
           'REQUEST_SUBMITTED' AS JoinType,
           v_OrgId AS OrgId,
           v_OrgName AS OrgName;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Cancel
-- Admin cancels a PENDING or OPENED invitation.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Cancel //
CREATE PROCEDURE Org_Invite_Cancel(
    IN p_InvitationId      INT UNSIGNED,
    IN p_CancelledByUserId INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode VARCHAR(20)  DEFAULT NULL;
    DECLARE v_RoleCode   VARCHAR(50)  DEFAULT NULL;

    SELECT oi.OrgId, lv.ValueCode INTO v_OrgId, v_StatusCode
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = v_OrgId AND om.UserId = p_CancelledByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to cancel invitations.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess, 'Only pending or opened invitations can be cancelled.' AS Message;
        LEAVE main_block;
    END IF;

    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'CANCELLED'),
        CancelledAt = NOW(),
        DeletedBy   = p_CancelledByUserId
    WHERE OrgInvitationId = p_InvitationId;

    SELECT 1 AS IsSuccess, 'Invitation cancelled.' AS Message;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Resend
-- Refreshes token + expiry, resets to PENDING.
-- C# layer re-delivers SMS/Email with the new link.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Resend //
CREATE PROCEDURE Org_Invite_Resend(
    IN p_InvitationId      INT UNSIGNED,
    IN p_RequestedByUserId INT UNSIGNED,
    IN p_NewToken          VARCHAR(128),
    IN p_NewExpiry         DATETIME,
    IN p_InviteBaseUrl     VARCHAR(500)
)
main_block: BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT NULL;
    DECLARE v_RoleCode      VARCHAR(50)  DEFAULT NULL;
    DECLARE v_InviteValue   VARCHAR(255) DEFAULT NULL;
    DECLARE v_CountryCode   VARCHAR(6)   DEFAULT NULL;
    DECLARE v_InvitedUserId INT UNSIGNED DEFAULT NULL;

    SELECT oi.OrgId, oi.InviteValue, oi.CountryCode, oi.InvitedUserId
    INTO v_OrgId, v_InviteValue, v_CountryCode, v_InvitedUserId
    FROM OrgInvitations oi
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message, NULL AS InviteToken, NULL AS InviteLink, NULL AS InviteValue, NULL AS CountryCode, NULL AS InvitedUserId;
        LEAVE main_block;
    END IF;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = v_OrgId AND om.UserId = p_RequestedByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to resend invitations.' AS Message, NULL AS InviteToken, NULL AS InviteLink, NULL AS InviteValue, NULL AS CountryCode, NULL AS InvitedUserId;
        LEAVE main_block;
    END IF;

    UPDATE OrgInvitations
    SET InviteToken  = p_NewToken,
        TokenExpiry  = p_NewExpiry,
        StatusLkpId  = (SELECT LookupValueId FROM LookupValues lv
                        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                        WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING'),
        SentAt       = NOW(),
        OpenedAt     = NULL
    WHERE OrgInvitationId = p_InvitationId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Invitation refreshed.' AS Message,
           p_NewToken       AS InviteToken,
           CONCAT(p_InviteBaseUrl, p_NewToken) AS InviteLink,
           v_InviteValue    AS InviteValue,
           v_CountryCode    AS CountryCode,
           v_InvitedUserId  AS InvitedUserId;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_List
-- Paged list of invitations for an org (admin view).
-- Auto-expires lapsed PENDING tokens before returning.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_List //
CREATE PROCEDURE Org_Invite_List(
    IN p_OrgId       INT UNSIGNED,
    IN p_RequestorId INT UNSIGNED,
    IN p_StatusCode  VARCHAR(20),
    IN p_PageNumber  INT UNSIGNED,
    IN p_PageSize    INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_RoleCode VARCHAR(50)   DEFAULT NULL;
    DECLARE v_Offset   INT UNSIGNED;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = p_OrgId AND om.UserId = p_RequestorId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'Permission denied.' AS Message;
        LEAVE main_block;
    END IF;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    -- Auto-expire lapsed PENDING invitations for this org
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.OrgId = p_OrgId AND oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                            JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                            WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING');

    -- Result set 1: rows
    SELECT
        oi.OrgInvitationId,
        lv_type.ValueCode       AS InviteType,
        oi.InviteValue,
        oi.CountryCode,
        lv_status.ValueCode     AS StatusCode,
        lv_status.ValueName     AS StatusName,
        oi.SentAt,
        oi.TokenExpiry,
        oi.OpenedAt,
        oi.AcceptedAt,
        oi.CancelledAt,
        oi.DeliveryStatus,
        oi.InvitedUserId,
        up_inv.FirstName        AS InviteeName,
        up_inv.LastName         AS InviteeLastName,
        up_inv.ProfilePhoto     AS InviteePhoto,
        up_by.FirstName         AS InvitedByName,
        up_by.ProfilePhoto      AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = oi.InviteTypeLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up_by     ON up_by.UserId = oi.InvitedByUserId
    LEFT JOIN UserProfiles up_inv ON up_inv.UserId = oi.InvitedUserId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode)
    ORDER BY oi.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count for pagination
    SELECT COUNT(*) AS TotalCount
    FROM OrgInvitations oi
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode);
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_GetPendingForUser
-- Called after login to surface pending invitations that
-- match the logged-in user's phone or email.
-- Auto-expires lapsed tokens before returning.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_GetPendingForUser //
CREATE PROCEDURE Org_Invite_GetPendingForUser(
    IN p_UserId INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_Mobile VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email  VARCHAR(150) DEFAULT NULL;

    SELECT Mobile, Email INTO v_Mobile, v_Email
    FROM Users WHERE UserId = p_UserId AND IsDeleted = 0 LIMIT 1;

    -- Auto-expire lapsed tokens matched to this user
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND (oi.InviteValue = v_Mobile OR oi.InviteValue = LOWER(IFNULL(v_Email,'')))
      AND oi.StatusLkpId IN (
          SELECT LookupValueId FROM LookupValues lv2
          JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
          WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode IN ('PENDING','OPENED')
      );

    SELECT
        oi.OrgInvitationId,
        oi.OrgId,
        o.OrgName,
        o.LogoUrl               AS OrgLogo,
        o.City                  AS OrgCity,
        oi.InviteToken,
        lv_status.ValueCode     AS StatusCode,
        oi.TokenExpiry,
        CONCAT(up.FirstName, ' ', up.LastName) AS InvitedByName,
        up.ProfilePhoto         AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN Organisations o         ON o.OrgId = oi.OrgId
    JOIN LookupValues lv_status  ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up         ON up.UserId = oi.InvitedByUserId
    WHERE oi.IsDeleted = 0
      AND lv_status.ValueCode IN ('PENDING','OPENED')
      AND oi.TokenExpiry > NOW()
      AND (oi.InviteValue = v_Mobile OR oi.InviteValue = LOWER(IFNULL(v_Email,'')))
    ORDER BY oi.CreatedAt DESC
    LIMIT 5;
END //

DELIMITER ;

-- ============================================================
-- VERIFICATION QUERIES (run after applying the patch)
-- ============================================================

-- 1. Confirm table was created
SELECT COUNT(*) AS OrgInvitations_exists
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'OrgInvitations';

-- 2. Confirm lookup types
SELECT TypeCode, TypeName FROM LookupTypes
WHERE TypeCode IN ('INVITE_TYPE','INVITE_STATUS');

-- 3. Confirm lookup values (should be 8 rows)
SELECT lt.TypeCode, lv.ValueCode, lv.ValueName
FROM LookupValues lv
JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
WHERE lt.TypeCode IN ('INVITE_TYPE','INVITE_STATUS')
ORDER BY lt.TypeCode, lv.OrderNo;

-- 4. Confirm settings (should be 5 rows)
SELECT SettingGroup, SettingKey, SettingValue
FROM Settings WHERE SettingGroup IN ('INVITE','SMS','EMAIL')
  AND SettingKey LIKE '%INVITE%' OR SettingKey = 'SMS_TEMPLATE_INVITE'
ORDER BY SettingGroup, SettingKey;

-- 5. Confirm all 7 SPs exist
SELECT ROUTINE_NAME FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE()
  AND ROUTINE_NAME LIKE 'Org_Invite_%'
ORDER BY ROUTINE_NAME;

-- ============================================================
-- END OF PATCH
-- ============================================================

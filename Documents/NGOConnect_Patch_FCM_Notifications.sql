-- ============================================================
-- NGO Connect — FCM Notifications Patch
-- Fixes schema mismatches in existing Notification SPs and adds
-- new SPs for FCM token management.
-- Apply to: Railway Staging → Railway Production
-- ============================================================

DELIMITER //

-- ────────────────────────────────────────────────────────────
-- FIX 1: Notification_GetByUser
-- Old SP referenced NotificationTypeLkpId / EntityId / EntityType / IsDeleted
-- Notifications table uses: NotifType / RefId / RefType (no IsDeleted column)
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetByUser //
CREATE PROCEDURE Notification_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_OnlyUnread TINYINT(1),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT n.NotificationId, n.Title, n.Body, n.NotifType,
           n.RefId, n.RefType, n.IsRead, n.ReadAt, n.CreatedAt
    FROM   Notifications n
    WHERE  n.UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR n.IsRead = 0)
    ORDER  BY n.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Notifications
    WHERE  UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR IsRead = 0);
END //

-- ────────────────────────────────────────────────────────────
-- FIX 2: Notification_GetUnreadCount
-- Old SP referenced IsDeleted column which does not exist on Notifications table
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetUnreadCount //
CREATE PROCEDURE Notification_GetUnreadCount(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT COUNT(*) AS UnreadCount
    FROM   Notifications
    WHERE  UserId = p_UserId AND IsRead = 0;
END //

-- ────────────────────────────────────────────────────────────
-- FIX 3: Notification_Create
-- Old SP inserted into NotificationTypeLkpId / EntityId / EntityType
-- Notifications table uses: NotifType VARCHAR(50) / RefId / RefType
-- Also marks IsSent = 0 initially; FCMService updates it to 1 on send
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_Create //
CREATE PROCEDURE Notification_Create(
    IN p_UserId    INT UNSIGNED,
    IN p_Title     VARCHAR(200),
    IN p_Body      TEXT,
    IN p_NotifType VARCHAR(50),
    IN p_RefId     INT UNSIGNED,
    IN p_RefType   VARCHAR(50)
)
BEGIN
    INSERT INTO Notifications (UserId, Title, Body, NotifType, RefId, RefType, IsSent)
    VALUES (p_UserId, p_Title, p_Body, p_NotifType, p_RefId, p_RefType, 0);

    SELECT 1 AS IsSuccess, 'Notification created.' AS Message,
           LAST_INSERT_ID() AS NotificationId;
END //

-- ────────────────────────────────────────────────────────────
-- NEW: Notification_SaveDeviceToken
-- Upsert FCM device token — one row per user per platform
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_SaveDeviceToken //
CREATE PROCEDURE Notification_SaveDeviceToken(
    IN p_UserId   INT UNSIGNED,
    IN p_Token    VARCHAR(512),
    IN p_Platform VARCHAR(20)
)
BEGIN
    INSERT INTO UserDeviceTokens (UserId, Token, Platform, UpdatedAt)
    VALUES (p_UserId, p_Token, p_Platform, NOW())
    ON DUPLICATE KEY UPDATE Token = p_Token, UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Token saved.' AS Message;
END //

-- ────────────────────────────────────────────────────────────
-- NEW: Notification_GetTokenByUserId
-- Returns FCM token(s) for a single user (may have android + ios)
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetTokenByUserId //
CREATE PROCEDURE Notification_GetTokenByUserId(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT Token, Platform
    FROM   UserDeviceTokens
    WHERE  UserId = p_UserId AND Token IS NOT NULL AND Token != '';
END //

-- ────────────────────────────────────────────────────────────
-- NEW: Notification_GetTokensByOrgId
-- Returns FCM tokens for all APPROVED members of an org.
-- Pass p_ExcludeUserId to skip the sender (e.g. SOS victim skip themselves).
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetTokensByOrgId //
CREATE PROCEDURE Notification_GetTokensByOrgId(
    IN p_OrgId         INT UNSIGNED,
    IN p_ExcludeUserId INT UNSIGNED
)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN OrgMembers om ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
    INNER JOIN LookupValues lv ON lv.LookupValueId = om.StatusLkpId
    INNER JOIN LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
      AND  om.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != ''
      AND  (p_ExcludeUserId IS NULL OR dt.UserId != p_ExcludeUserId);
END //

-- ────────────────────────────────────────────────────────────
-- NEW: Notification_GetAdminTokensByOrgId
-- Returns FCM tokens for FOUNDER + ADMIN members of an org only.
-- Used for admin notifications (new application, new membership request, etc.)
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetAdminTokensByOrgId //
CREATE PROCEDURE Notification_GetAdminTokensByOrgId(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN OrgMembers om ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
    INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
    INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
    INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
    INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
    WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
      AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN')
      AND  om.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

-- ────────────────────────────────────────────────────────────
-- NEW: Notification_GetTokensByProjectId
-- Returns FCM tokens for project applicants with a given status.
-- p_StatusCode: APPROVED | ATTENDED | PENDING (pass NULL for all)
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Notification_GetTokensByProjectId //
CREATE PROCEDURE Notification_GetTokensByProjectId(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(20)
)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN ProjectApplications pa ON pa.UserId = dt.UserId AND pa.ProjectId = p_ProjectId
    INNER JOIN LookupValues lv ON lv.LookupValueId = pa.StatusLkpId
    INNER JOIN LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS'
      AND  (p_StatusCode IS NULL OR lv.ValueCode = p_StatusCode)
      AND  pa.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

-- ── SOS RESPONDER TOKEN SP ───────────────────────────────────────────────────
-- Returns FCM tokens for all APPROVED responders on an SOS incident
-- Used to notify responders when the incident is resolved/cancelled
DROP PROCEDURE IF EXISTS Notification_GetTokensBySosIncidentId //
CREATE PROCEDURE Notification_GetTokensBySosIncidentId(IN p_SosIncidentId INT UNSIGNED)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN SosResponders sr ON sr.UserId = dt.UserId AND sr.SosIncidentId = p_SosIncidentId
    INNER JOIN LookupValues  lv ON lv.LookupValueId = sr.ApprovalStatusLkpId
    INNER JOIN LookupTypes   lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'APPROVED'
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

DELIMITER ;

-- ============================================================
-- SP CONTEXT CHANGES — Add extra columns to write-result rows
-- so DAL can fire push notifications without extra round-trips
-- ============================================================

DELIMITER //

-- Application_Apply: return OrgId so DAL can notify org admins of new application
DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, AppliedAt)
    VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, NOW());

    SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
           LAST_INSERT_ID() AS ApplicationId,
           (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;
END //

-- Application_Review: return ApplicantUserId + ProjectId so DAL can notify the applicant
DROP PROCEDURE IF EXISTS Application_Review //
CREATE PROCEDURE Application_Review(
    IN p_ApplicationId INT UNSIGNED,
    IN p_ReviewedBy    INT UNSIGNED,
    IN p_StatusCode    VARCHAR(50),
    IN p_RejectionReason TEXT
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    UPDATE ProjectApplications
    SET    StatusLkpId = v_StatusLkpId, StatusUpdatedAt = NOW(),
           StatusUpdatedBy = p_ReviewedBy, RejectionReason = p_RejectionReason
    WHERE  ApplicationId = p_ApplicationId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, CONCAT('Application ', p_StatusCode, '.') AS Message,
           (SELECT UserId   FROM ProjectApplications WHERE ApplicationId = p_ApplicationId) AS ApplicantUserId,
           (SELECT ProjectId FROM ProjectApplications WHERE ApplicationId = p_ApplicationId) AS ProjectId;
END //

-- Org_ReviewMembership: return ApplicantUserId + OrgId (already in local vars)
DROP PROCEDURE IF EXISTS Org_ReviewMembership //
CREATE PROCEDURE Org_ReviewMembership(
    IN p_RequestId  INT UNSIGNED,
    IN p_ReviewedBy INT UNSIGNED,
    IN p_StatusCode VARCHAR(50),
    IN p_ReviewNote TEXT
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_OrgId       INT UNSIGNED;
    DECLARE v_UserId      INT UNSIGNED;

    SELECT OrgId, UserId INTO v_OrgId, v_UserId
    FROM   OrgMembershipRequests WHERE RequestId = p_RequestId AND IsDeleted = 0;

    SELECT LookupValueId INTO v_StatusLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    UPDATE OrgMembershipRequests
    SET    StatusLkpId = v_StatusLkpId, ReviewedBy = p_ReviewedBy,
           ReviewedAt = NOW(), ReviewNote = p_ReviewNote
    WHERE  RequestId = p_RequestId;

    IF p_StatusCode = 'APPROVED' THEN
        CALL Org_AddMember(v_OrgId, v_UserId, 'MEMBER', p_ReviewedBy);
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Request ', p_StatusCode, '.') AS Message,
           v_UserId AS ApplicantUserId, v_OrgId AS OrgId;
END //

-- Sos_ApproveResponder: return ResponderUserId + SosIncidentId
DROP PROCEDURE IF EXISTS Sos_ApproveResponder //
CREATE PROCEDURE Sos_ApproveResponder(
    IN p_SosResponderId  INT UNSIGNED,
    IN p_ApprovedBy      INT UNSIGNED,
    IN p_CanViewLocation TINYINT(1)
)
BEGIN
    DECLARE v_StatusLkpId   INT UNSIGNED;
    DECLARE v_ResponderUserId INT UNSIGNED;
    DECLARE v_SosIncidentId   INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT UserId, SosIncidentId INTO v_ResponderUserId, v_SosIncidentId
    FROM   SosResponders WHERE SosResponderId = p_SosResponderId;

    UPDATE SosResponders
    SET    ApprovalStatusLkpId = v_StatusLkpId,
           ApprovedAt = NOW(), ApprovedBy = p_ApprovedBy,
           CanViewLocation = COALESCE(p_CanViewLocation, 0)
    WHERE  SosResponderId = p_SosResponderId;

    SELECT 1 AS IsSuccess, 'Responder approved.' AS Message,
           v_ResponderUserId AS ResponderUserId, v_SosIncidentId AS SosIncidentId;
END //

-- Donation_ConfirmPayment: return DonorUserId + OrgId
DROP PROCEDURE IF EXISTS Donation_ConfirmPayment //
CREATE PROCEDURE Donation_ConfirmPayment(
    IN p_TransactionId  INT UNSIGNED,
    IN p_StatusCode     VARCHAR(50),
    IN p_GatewayResponse JSON
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_Amount      DECIMAL(15,2);
    DECLARE v_CampaignId  INT UNSIGNED;
    DECLARE v_DonorUserId INT UNSIGNED;
    DECLARE v_OrgId       INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    SELECT DonationAmount, CampaignId, DonorUserId, OrgId
    INTO   v_Amount, v_CampaignId, v_DonorUserId, v_OrgId
    FROM   DonationTransactions WHERE TransactionId = p_TransactionId;

    UPDATE DonationTransactions
    SET    PayStatusLkpId = v_StatusLkpId, GatewayResponse = p_GatewayResponse, UpdatedAt = NOW()
    WHERE  TransactionId = p_TransactionId;

    IF p_StatusCode = 'SUCCESS' THEN
        UPDATE DonationCampaigns SET RaisedAmount = RaisedAmount + v_Amount WHERE CampaignId = v_CampaignId;
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Payment ', p_StatusCode, '.') AS Message,
           v_DonorUserId AS DonorUserId, v_OrgId AS OrgId, v_CampaignId AS CampaignId;
END //

DELIMITER ;

-- ============================================================
-- END OF PATCH
-- ============================================================

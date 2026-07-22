-- ============================================================
-- NGOConnect Patch: Invite Accept/Decline Admin Notifications
-- Adds in-app notification to org FOUNDER/ADMIN when invitee
-- accepts or declines a membership invitation.
-- Apply to Railway staging and production.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_Invite_Accept //
CREATE PROCEDURE Org_Invite_Accept(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId           INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode      VARCHAR(20)  DEFAULT NULL;
    DECLARE v_InviteValue     VARCHAR(255) DEFAULT NULL;
    DECLARE v_IsMember        TINYINT(1)   DEFAULT 0;
    DECLARE v_HasRequest      TINYINT(1)   DEFAULT 0;
    DECLARE v_AcceptedLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_PendingReqLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName         VARCHAR(200) DEFAULT NULL;
    DECLARE v_InviteeName     VARCHAR(200) DEFAULT NULL;
    DECLARE v_AdminUserId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_AdminDone       TINYINT(1)   DEFAULT 0;

    DECLARE admin_cur CURSOR FOR
        SELECT DISTINCT om.UserId
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = v_OrgId
          AND  lt.TypeCode = 'MEMBER_ROLE'
          AND  lv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_AdminDone = 1;

    -- Validate invitation
    SELECT oi.OrgId, lv.ValueCode, oi.InviteValue
    INTO v_OrgId, v_StatusCode, v_InviteValue
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message, NULL AS JoinType;
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
               NULL AS JoinType;
        LEAVE main_block;
    END IF;

    IF NOW() > (SELECT TokenExpiry FROM OrgInvitations WHERE OrgInvitationId = p_InvitationId) THEN
        SELECT 0 AS IsSuccess, 'This invitation has expired.' AS Message, NULL AS JoinType;
        LEAVE main_block;
    END IF;

    -- Already a member?
    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsMember > 0 THEN
        SELECT 0 AS IsSuccess, 'You are already a member of this organisation.' AS Message, NULL AS JoinType;
        LEAVE main_block;
    END IF;

    -- Already has a pending request?
    SELECT COUNT(*) INTO v_HasRequest FROM OrgMembershipRequests
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    SELECT LookupValueId INTO v_AcceptedLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'ACCEPTED' LIMIT 1;

    SELECT LookupValueId INTO v_PendingReqLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- Mark invitation as ACCEPTED
    UPDATE OrgInvitations
    SET StatusLkpId = v_AcceptedLkpId,
        AcceptedAt  = NOW(),
        InvitedUserId = p_UserId
    WHERE OrgInvitationId = p_InvitationId;

    -- Create membership request if not already submitted
    IF v_HasRequest = 0 THEN
        INSERT INTO OrgMembershipRequests (OrgId, UserId, WhyJoin, StatusLkpId)
        VALUES (v_OrgId, p_UserId, 'Accepted via invitation link.', v_PendingReqLkpId);
    END IF;

    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;

    -- Get invitee display name
    SELECT CONCAT(up.FirstName, ' ', up.LastName) INTO v_InviteeName
    FROM UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    -- Notify each FOUNDER/ADMIN of the org
    SET v_AdminDone = 0;
    OPEN admin_cur;
    admin_loop: LOOP
        FETCH admin_cur INTO v_AdminUserId;
        IF v_AdminDone = 1 THEN LEAVE admin_loop; END IF;
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_AdminUserId, v_OrgId,
            'INVITE_ACCEPTED',
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' accepted your invitation'),
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' accepted the invitation to join ',
                   v_OrgName, '. Their membership request is pending your approval.'),
            v_OrgId, 'ORG'
        );
    END LOOP;
    CLOSE admin_cur;

    SELECT 1 AS IsSuccess,
           CONCAT('Your request to join ', v_OrgName, ' has been submitted. You will be notified when approved.') AS Message,
           'REQUEST_SUBMITTED' AS JoinType,
           v_OrgId   AS OrgId,
           v_OrgName AS OrgName;
END //

DROP PROCEDURE IF EXISTS Org_Invite_Decline //
CREATE PROCEDURE Org_Invite_Decline(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_InviteValue  VARCHAR(150) DEFAULT NULL;
    DECLARE v_StatusCode   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Mobile       VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email        VARCHAR(150) DEFAULT NULL;
    DECLARE v_CancelledId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName      VARCHAR(200) DEFAULT NULL;
    DECLARE v_InviteeName  VARCHAR(200) DEFAULT NULL;
    DECLARE v_AdminUserId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_AdminDone    TINYINT(1)   DEFAULT 0;

    DECLARE admin_cur CURSOR FOR
        SELECT DISTINCT om.UserId
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = v_OrgId
          AND  lt.TypeCode = 'MEMBER_ROLE'
          AND  lv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_AdminDone = 1;

    -- Fetch invitation + current status + org
    SELECT oi.OrgId, oi.InviteValue, lv.ValueCode
    INTO   v_OrgId, v_InviteValue, v_StatusCode
    FROM   OrgInvitations oi
    JOIN   LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE  oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT  1;

    IF v_StatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('This invitation is already ', LOWER(v_StatusCode), '.') AS Message;
        LEAVE main_block;
    END IF;

    -- Verify caller is the invitee by matching phone / email
    SELECT u.Mobile, u.Email
    INTO   v_Mobile, v_Email
    FROM   Users u
    WHERE  u.UserId = p_UserId AND u.IsDeleted = 0
    LIMIT  1;

    IF v_InviteValue != v_Mobile AND v_InviteValue != LOWER(IFNULL(v_Email,'')) THEN
        SELECT 0 AS IsSuccess, 'You are not the recipient of this invitation.' AS Message;
        LEAVE main_block;
    END IF;

    -- Get CANCELLED lookup value
    SELECT lv.LookupValueId INTO v_CancelledId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'CANCELLED'
    LIMIT  1;

    UPDATE OrgInvitations
    SET    StatusLkpId = v_CancelledId,
           CancelledAt = NOW(),
           UpdatedAt   = NOW()
    WHERE  OrgInvitationId = p_InvitationId;

    -- Get org name and invitee name for notification
    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;

    SELECT CONCAT(up.FirstName, ' ', up.LastName) INTO v_InviteeName
    FROM UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    -- Notify each FOUNDER/ADMIN of the org
    SET v_AdminDone = 0;
    OPEN admin_cur;
    admin_loop: LOOP
        FETCH admin_cur INTO v_AdminUserId;
        IF v_AdminDone = 1 THEN LEAVE admin_loop; END IF;
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_AdminUserId, v_OrgId,
            'INVITE_DECLINED',
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' declined your invitation'),
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' has declined the invitation to join ',
                   v_OrgName, '.'),
            v_OrgId, 'ORG'
        );
    END LOOP;
    CLOSE admin_cur;

    SELECT 1 AS IsSuccess, 'Invitation declined.' AS Message, v_OrgId AS OrgId;
END //

DELIMITER ;

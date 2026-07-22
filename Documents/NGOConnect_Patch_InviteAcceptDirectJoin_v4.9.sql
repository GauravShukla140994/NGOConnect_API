-- ═══════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Invite Accept → Direct Member Join (v4.9)
-- Date   : 2026-07-22
-- Fix    :
--   Org_Invite_Accept previously created an OrgMembershipRequests row
--   with APPLICATION_STATUS = PENDING, requiring a separate admin
--   approval step. Since an admin personally sent the invitation, the
--   invite itself IS the approval. This patch changes the SP to INSERT
--   directly into OrgMembers (MEMBER_ROLE = MEMBER, MEMBER_STATUS =
--   APPROVED) so the user is immediately visible in the Members tab.
--
--   Changes:
--   • Removes OrgMembershipRequests INSERT and APPLICATION_STATUS lookup
--   • Adds MEMBER_ROLE → MEMBER and MEMBER_STATUS → APPROVED lookups
--   • Inserts into OrgMembers with ON DUPLICATE KEY UPDATE (idempotent)
--   • Notification body updated: "has joined" not "pending approval"
--   • Returns JoinType = 'DIRECT_JOINED' (was REQUEST_SUBMITTED)
--   • Returns "Welcome to <Org>! You are now a member." message
--   • ALREADY_MEMBER case now returns IsSuccess=1 (not 0) with message
--
-- Apply  : Run on Railway staging → verify → run on Railway production.
-- ═══════════════════════════════════════════════════════════════════════

DELIMITER //

DROP PROCEDURE IF EXISTS Org_Invite_Accept //
CREATE PROCEDURE Org_Invite_Accept(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId             INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode        VARCHAR(20)  DEFAULT NULL;
    DECLARE v_IsMember          TINYINT(1)   DEFAULT 0;
    DECLARE v_AcceptedLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_MemberRoleLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedMemLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName           VARCHAR(200) DEFAULT NULL;
    DECLARE v_InviteeName       VARCHAR(200) DEFAULT NULL;
    DECLARE v_AdminUserId       INT UNSIGNED DEFAULT NULL;
    DECLARE v_AdminDone         TINYINT(1)   DEFAULT 0;

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
    SELECT oi.OrgId, lv.ValueCode
    INTO   v_OrgId, v_StatusCode
    FROM   OrgInvitations oi
    JOIN   LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE  oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT  1;

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

    -- Already a member?
    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsMember > 0 THEN
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;
        SELECT 1 AS IsSuccess, CONCAT('You are already a member of ', v_OrgName, '.') AS Message,
               'ALREADY_MEMBER' AS JoinType, v_OrgId AS OrgId, v_OrgName AS OrgName;
        LEAVE main_block;
    END IF;

    -- Lookup IDs
    SELECT LookupValueId INTO v_AcceptedLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'ACCEPTED' LIMIT 1;

    SELECT LookupValueId INTO v_MemberRoleLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'MEMBER' LIMIT 1;

    SELECT LookupValueId INTO v_ApprovedMemLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Mark invitation as ACCEPTED
    UPDATE OrgInvitations
    SET    StatusLkpId  = v_AcceptedLkpId,
           AcceptedAt   = NOW(),
           InvitedUserId = p_UserId
    WHERE  OrgInvitationId = p_InvitationId;

    -- Direct join: invitation = admin approval, no separate review needed
    INSERT INTO OrgMembers
        (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
    VALUES
        (v_OrgId, p_UserId, v_MemberRoleLkpId, v_ApprovedMemLkpId, NOW(), p_UserId)
    ON DUPLICATE KEY UPDATE
        StatusLkpId     = v_ApprovedMemLkpId,
        JoinedAt        = NOW(),
        IsDeleted       = 0,
        DeletedAt       = NULL,
        DeletedBy       = NULL;

    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;

    -- Get invitee display name
    SELECT CONCAT(up.FirstName, ' ', up.LastName) INTO v_InviteeName
    FROM   UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    -- Notify each FOUNDER/ADMIN (they can see the new member immediately)
    SET v_AdminDone = 0;
    OPEN admin_cur;
    admin_loop: LOOP
        FETCH admin_cur INTO v_AdminUserId;
        IF v_AdminDone = 1 THEN LEAVE admin_loop; END IF;
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_AdminUserId, v_OrgId,
            'INVITE_ACCEPTED',
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' joined ', v_OrgName),
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' accepted your invitation and has joined ',
                   v_OrgName, ' as a member.'),
            v_OrgId, 'ORG'
        );
    END LOOP;
    CLOSE admin_cur;

    SELECT 1 AS IsSuccess,
           CONCAT('Welcome to ', v_OrgName, '! You are now a member.') AS Message,
           'DIRECT_JOINED' AS JoinType,
           v_OrgId   AS OrgId,
           v_OrgName AS OrgName;
END //

DELIMITER ;

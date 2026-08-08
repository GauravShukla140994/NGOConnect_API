-- ============================================================
-- Patch: Org_Invite_Decline SP
-- Version: v4.9
-- Date: 2026-07-22
-- Purpose: Allow invitees to decline a pending invitation.
--          Verifies caller by matching their phone/email to InviteValue.
--          Distinct from Org_Invite_Cancel (admin-only).
-- Run on: Railway staging + production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_Invite_Decline //
CREATE PROCEDURE Org_Invite_Decline(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_InviteValue  VARCHAR(150) DEFAULT NULL;
    DECLARE v_StatusCode   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Mobile       VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email        VARCHAR(150) DEFAULT NULL;
    DECLARE v_CancelledId  INT UNSIGNED DEFAULT NULL;

    SELECT oi.InviteValue, lv.ValueCode
    INTO   v_InviteValue, v_StatusCode
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

    SELECT u.Mobile, u.Email
    INTO   v_Mobile, v_Email
    FROM   Users u
    WHERE  u.UserId = p_UserId AND u.IsDeleted = 0
    LIMIT  1;

    IF v_InviteValue != v_Mobile AND v_InviteValue != LOWER(IFNULL(v_Email,'')) THEN
        SELECT 0 AS IsSuccess, 'You are not the recipient of this invitation.' AS Message;
        LEAVE main_block;
    END IF;

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

    SELECT 1 AS IsSuccess, 'Invitation declined.' AS Message;
END //

DELIMITER ;

-- Verify:
-- CALL Org_Invite_Decline(1, 99);   -- should return 'You are not the recipient…'
-- CALL Org_Invite_Decline(1, <invitee_userId>);   -- should return 'Invitation declined.'

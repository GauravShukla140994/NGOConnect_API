-- =============================================================================
-- Patch: Sos_DeclineResponder — victim can decline a responder request
--
-- New endpoint: PUT /api/v1/sos/{id}/decline-responder
-- Called when victim taps the Decline (✕) button next to a pending responder.
-- Sets SosResponders.ApprovalStatusLkpId to the REJECTED lookup value.
--
-- Prerequisites:
--   LookupTypes: TypeCode = 'RESPONDER_STATUS'
--   LookupValues: ValueCode IN ('PENDING', 'APPROVED', 'REJECTED') for that type
--   These are already seeded in NGOConnect_Complete_Setup_v4.2.sql
--
-- Safe to re-run: uses DROP PROCEDURE IF EXISTS.
-- =============================================================================

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_DeclineResponder //
CREATE PROCEDURE Sos_DeclineResponder(
    IN p_SosIncidentId  INT UNSIGNED,
    IN p_SosResponderId INT UNSIGNED,
    IN p_DeclinedBy     INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_RejectedLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OwnerUserId   INT UNSIGNED DEFAULT NULL;

    -- 1. Look up the REJECTED status ID
    SELECT lv.LookupValueId
    INTO   v_RejectedLkpId
    FROM   LookupValues  lv
    JOIN   LookupTypes   lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode   = 'RESPONDER_STATUS'
      AND  lv.ValueCode  = 'REJECTED'
    LIMIT 1;

    IF v_RejectedLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'REJECTED status lookup not configured.' AS Message;
        LEAVE main_block;
    END IF;

    -- 2. Verify the caller is the SOS victim (owner)
    SELECT UserId INTO v_OwnerUserId
    FROM   SosIncidents
    WHERE  SosIncidentId = p_SosIncidentId
      AND  IsDeleted     = 0
    LIMIT 1;

    IF v_OwnerUserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'SOS incident not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_OwnerUserId <> p_DeclinedBy THEN
        SELECT 0 AS IsSuccess, 'Only the SOS victim can decline responders.' AS Message;
        LEAVE main_block;
    END IF;

    -- 3. Update the responder status
    UPDATE SosResponders
    SET    ApprovalStatusLkpId = v_RejectedLkpId
    WHERE  SosResponderId = p_SosResponderId
      AND  SosIncidentId  = p_SosIncidentId;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Responder record not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Responder declined.' AS Message;
    END IF;

END //

DELIMITER ;

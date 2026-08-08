-- ============================================================
-- NGOConnect Patch: Org_CancelMembershipRequest
-- Date:    2026-07-31
-- Changes:
--   New SP: user cancels their own PENDING join request.
--   Soft-deletes the OrgMembershipRequests row (IsDeleted = 1).
--   Only works while the request is still PENDING — once the
--   admin has approved or rejected it, this SP returns IsSuccess=0.
-- Endpoint: DELETE /api/v1/org/{orgId}/membership-request
-- Apply to: Railway Staging, then Railway Production
-- SAFE to re-apply (DROP + CREATE pattern)
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_CancelMembershipRequest //

CREATE PROCEDURE Org_CancelMembershipRequest(
    IN p_OrgId   INT UNSIGNED,
    IN p_UserId  INT UNSIGNED
)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;
    DECLARE v_Rows         INT DEFAULT 0;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT  1;

    UPDATE OrgMembershipRequests
    SET    IsDeleted = 1
    WHERE  OrgId       = p_OrgId
      AND  UserId      = p_UserId
      AND  StatusLkpId = v_PendingLkpId
      AND  IsDeleted   = 0;

    SET v_Rows = ROW_COUNT();

    IF v_Rows > 0 THEN
        SELECT 1 AS IsSuccess, 'Membership request cancelled.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'No pending request found for this organisation.' AS Message;
    END IF;
END //

DELIMITER ;

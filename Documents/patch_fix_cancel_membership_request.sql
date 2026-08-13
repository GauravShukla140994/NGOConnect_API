-- ============================================================
-- Patch: Fix Org_CancelMembershipRequest — hard DELETE instead
--        of soft-delete to prevent duplicate-key crash on 2nd cancel
--
-- Root cause:
--   UNIQUE KEY uq_memreq_org_user (OrgId, UserId, IsDeleted) allows
--   only one row with IsDeleted=1 per (OrgId, UserId) pair.
--   After the first cancel cycle an IsDeleted=1 row already exists.
--   A second cancel attempt ran UPDATE ... SET IsDeleted=1 on the new
--   PENDING row, which violated the unique constraint → MySQL exception
--   → DAL catch block → "An error occurred" on the mobile screen.
--
-- Fix:
--   DELETE the PENDING row outright. Org_RequestMembership checks only
--   IsDeleted=0 rows before allowing re-apply, so a hard delete here
--   lets the user reapply cleanly (fresh INSERT on next join attempt).
--
-- Apply to: local DB → Railway staging → Railway production
-- ============================================================

-- ── Add missing NOTIFICATION_TYPE LookupValues ───────────────
-- MEMBERSHIP_REQUEST was missing from seed; MEMBERSHIP_CANCELLED is new.
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT lt.LookupTypeId, 'MEMBERSHIP_REQUEST', 'Membership Request', 12, 1, 0
FROM   LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT lt.LookupTypeId, 'MEMBERSHIP_CANCELLED', 'Membership Request Withdrawn', 13, 1, 0
FROM   LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

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

    DELETE FROM OrgMembershipRequests
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

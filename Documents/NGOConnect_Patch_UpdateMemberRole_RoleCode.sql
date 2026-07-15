-- ============================================================
-- NGO Connect — Patch: Org_UpdateMemberRole — accept RoleCode instead of RoleLkpId
-- Problem: SP took p_RoleLkpId (INT) but mobile only has roleCode string.
--          Mobile had no "Save Role" button — role changes were never persisted.
-- Fix:     SP now takes p_RoleCode VARCHAR(50) and resolves to LkpId internally,
--          consistent with the Org_AddMember pattern (Core Mandate: Dynamic).
-- Apply to: Railway staging + production
-- Date: 2026-07-14
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_UpdateMemberRole //
CREATE PROCEDURE Org_UpdateMemberRole(
    IN p_OrgId     INT,
    IN p_MemberId  INT,
    IN p_RoleCode  VARCHAR(50),
    IN p_UpdatedBy INT
)
BEGIN
    DECLARE v_RoleLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_RoleLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = p_RoleCode
    LIMIT  1;

    IF v_RoleLkpId = 0 THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown role: ', p_RoleCode) AS Message;
    ELSE
        UPDATE OrgMembers
        SET RoleLkpId = v_RoleLkpId,
            UpdatedAt = NOW(),
            UpdatedBy = p_UpdatedBy
        WHERE OrgMemberId = p_MemberId
          AND OrgId       = p_OrgId
          AND IsDeleted   = 0;

        IF ROW_COUNT() = 0 THEN
            SELECT 0 AS IsSuccess, 'Member not found or already deleted.' AS Message;
        ELSE
            SELECT 1 AS IsSuccess, 'Member role updated.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- NGOConnect Patch: Org_UpdateMemberRole — push latest version to Railway
-- Date:    2026-07-28
-- Problem:
--   "An error occurred" on Save Role button. The previous
--   NGOConnect_Patch_MemberUpdateSPs.sql only pushed
--   Org_UpdateMemberPermissions (Save Permissions — now works).
--   Org_UpdateMemberRole on Railway may still be the v4.1 version
--   which used p_RoleLkpId (INT) — the DAL sends p_RoleCode (VARCHAR).
--   MySqlConnector throws a parameter mismatch error → caught in
--   DAL catch block → "An error occurred."
--
-- Fix:
--   Push the latest correct version (from NGOConnect_Patch_FCM_SPOutputs.sql):
--   - Accepts p_RoleCode VARCHAR(50), resolves internally to LkpId
--   - On success returns UserId for fire-and-forget FCM notification
--   - On unknown roleCode returns IsSuccess=0 + "Unknown role: X"
--   - On member-not-found returns IsSuccess=0 + "Member not found..."
--
-- Apply to: Railway Staging, then Railway Production
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
            SELECT 0 AS IsSuccess, 'Member not found or already deleted.' AS Message, NULL AS UserId;
        ELSE
            SELECT 1 AS IsSuccess, 'Member role updated.' AS Message,
                   (SELECT UserId FROM OrgMembers WHERE OrgMemberId = p_MemberId LIMIT 1) AS UserId;
        END IF;
    END IF;
END //

DELIMITER ;

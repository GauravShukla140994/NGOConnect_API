-- ============================================================
-- NGOConnect Patch: Member Update SPs
-- Date:    2026-07-28
-- Purpose: Fix "An error occurred" on Save Permissions + Save Role
--          buttons in Admin > Volunteers > Member Details sheet.
--
-- Root cause:
--   Org_UpdateMemberPermissions has NEVER appeared in any
--   standalone patch file (only in complete setup SQL files).
--   If Railway staging was not rebuilt from setup SQL after v4.0,
--   this SP may be missing or on a wrong/old version.
--
-- SPs in this patch:
--   1. Org_UpdateMemberPermissions — push current correct version
--      (already correct in v4.9 setup SQL; param names match DAL)
--
-- Note on Org_UpdateMemberRole:
--   Already patched twice (v4.1 → RoleCode, v4.8 → returns UserId).
--   NOT included here to avoid overwriting the FCM version that
--   returns UserId. Latest correct version is in
--   NGOConnect_Patch_FCM_SPOutputs.sql.
--
-- Apply to: Railway Staging, then Railway Production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_UpdateMemberPermissions //
CREATE PROCEDURE Org_UpdateMemberPermissions(
    IN p_OrgMemberId          INT UNSIGNED,
    IN p_OrgId                INT UNSIGNED,
    IN p_UpdatedBy            INT UNSIGNED,
    IN p_CanPost              TINYINT(1),
    IN p_CanComment           TINYINT(1),
    IN p_CanCommunityPost     TINYINT(1),
    IN p_MaxPostsPerDay       TINYINT,
    IN p_LocationSharingLkpId INT UNSIGNED
)
BEGIN
    UPDATE OrgMembers SET
        CanPost              = COALESCE(p_CanPost, CanPost),
        CanComment           = COALESCE(p_CanComment, CanComment),
        CanCommunityPost     = COALESCE(p_CanCommunityPost, CanCommunityPost),
        MaxPostsPerDay       = COALESCE(p_MaxPostsPerDay, MaxPostsPerDay),
        LocationSharingLkpId = COALESCE(p_LocationSharingLkpId, LocationSharingLkpId),
        UpdatedBy            = p_UpdatedBy,
        UpdatedAt            = NOW()
    WHERE OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Permissions updated.' AS Message;
END //

DELIMITER ;

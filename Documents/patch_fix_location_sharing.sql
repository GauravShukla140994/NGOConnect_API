-- ── patch_fix_location_sharing.sql ───────────────────────────────────────────
-- Bug   : Location Sharing toggle on the Admin → Volunteer → Member Details
--         screen never persisted after "Save Permissions".
--
-- Root cause (3 layers):
--   1. Mobile saveAll() omitted locationSharing from the API payload entirely.
--   2. Backend model had LocationSharingLkpId (int?) — no mapping from the
--      mobile's boolean field → always deserialised as null.
--   3. SP used COALESCE(p_LocationSharingLkpId, LocationSharingLkpId): when
--      null was received the old value was silently kept, hiding the bug.
--
-- Fix:
--   SP : p_LocationSharingLkpId INT UNSIGNED → p_LocationSharing TINYINT(1).
--        SP resolves the LkpId for ALWAYS/NEVER internally (one lookup SELECT).
--   C# : UpdateMemberPermissionsRequest.LocationSharingLkpId → LocationSharing bool?
--        OrgDal passes 1/0/DBNull to the new param name.
--   RN : AdminVolunteersScreen saveAll() now sends { locationSharing: locSharing }.
--
-- No table or column changes. Safe to re-run.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Org_UpdateMemberPermissions //

CREATE PROCEDURE Org_UpdateMemberPermissions(
    IN p_OrgMemberId      INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_UpdatedBy        INT UNSIGNED,
    IN p_CanPost          TINYINT(1),
    IN p_CanComment       TINYINT(1),
    IN p_CanCommunityPost TINYINT(1),
    IN p_MaxPostsPerDay   TINYINT,
    IN p_LocationSharing  TINYINT(1)
)
BEGIN
    DECLARE v_LocLkpId INT UNSIGNED DEFAULT NULL;

    -- Resolve boolean → LookupValueId for LOCATION_SHARING (ALWAYS / NEVER)
    IF p_LocationSharing IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode  = 'LOCATION_SHARING'
          AND  lv.ValueCode = IF(p_LocationSharing = 1, 'ALWAYS', 'NEVER')
        LIMIT 1;
    END IF;

    UPDATE OrgMembers SET
        CanPost              = COALESCE(p_CanPost,          CanPost),
        CanComment           = COALESCE(p_CanComment,       CanComment),
        CanCommunityPost     = COALESCE(p_CanCommunityPost, CanCommunityPost),
        MaxPostsPerDay       = COALESCE(p_MaxPostsPerDay,   MaxPostsPerDay),
        LocationSharingLkpId = COALESCE(v_LocLkpId, LocationSharingLkpId),
        UpdatedBy            = p_UpdatedBy,
        UpdatedAt            = NOW()
    WHERE OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Permissions updated.' AS Message;
END //

DELIMITER ;

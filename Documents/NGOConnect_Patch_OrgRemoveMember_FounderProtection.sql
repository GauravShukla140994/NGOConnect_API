-- ============================================================
-- Patch: Org_RemoveMember — add admin check + founder protection
-- Date: 2026-07-28
-- Changes:
--   1. Added requester access check: only ADMIN or FOUNDER can remove members
--   2. Added target protection: FOUNDER cannot be removed by anyone
--   3. Aligned param names to match DAL (p_UserId, p_RemovedBy)
--      Previously setup SQL had no access control at all.
--      Previously 04_SP_All_New_Modules.sql used p_RequestedBy + p_OrgMemberId
--      which did NOT match the DAL — both are now fixed.
-- Apply to: Railway Staging, Railway Production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_RemoveMember //
CREATE PROCEDURE Org_RemoveMember(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,    -- Target member's UserId (to be removed)
    IN p_RemovedBy  INT UNSIGNED     -- Admin/Founder making the request
)
BEGIN
    DECLARE v_IsAdmin         INT DEFAULT 0;
    DECLARE v_TargetIsFounder INT DEFAULT 0;

    -- Check requester is ADMIN or FOUNDER of the org
    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RemovedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin or founder can remove members.' AS Message;
    ELSE
        -- Founders cannot be removed — protect org ownership
        SELECT COUNT(*) INTO v_TargetIsFounder
        FROM   OrgMembers om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
          AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER'
          AND  om.IsDeleted = 0;

        IF v_TargetIsFounder > 0 THEN
            SELECT 0 AS IsSuccess, 'Founder cannot be removed from the organisation.' AS Message;
        ELSE
            UPDATE OrgMembers
            SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_RemovedBy
            WHERE  OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

            SELECT 1 AS IsSuccess, 'Member removed successfully.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

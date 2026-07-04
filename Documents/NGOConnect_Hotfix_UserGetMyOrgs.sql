-- ============================================================
-- NGO Connect — Hotfix: User_GetMyOrgs SP
-- Date: 2026-07-03
--
-- BUGS FIXED:
--   1. Wrong column: om.ApprovalStatusLkpId → om.StatusLkpId
--      (ApprovalStatusLkpId does not exist in OrgMembers — caused SP to
--       return 0 rows, so newly registered orgs never appeared on the
--       My Organizations screen)
--
--   2. Filter only APPROVED → now returns BOTH APPROVED + PENDING
--      (Pending join requests were invisible to the user)
--
--   3. Added MemberStatusCode + OrgStatusCode to the result set
--      so the app can correctly bucket orgs into:
--        • Linked Organizations  (APPROVED member, org ACTIVE)
--        • Pending Requests      (PENDING join request, OR founder
--                                 whose newly registered org is PENDING approval)
--
-- Run on: NGOConnect database
-- Safe to run multiple times (DROP IF EXISTS before CREATE)
-- ============================================================

USE NGOConnect;
DELIMITER //

DROP PROCEDURE IF EXISTS User_GetMyOrgs //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName  AS OrgType,
        o.City,
        o.State,
        rv.ValueName  AS Role,
        rv.ValueCode  AS RoleCode,
        sv.ValueCode  AS MemberStatusCode,   -- APPROVED | PENDING (user's membership status)
        os.ValueCode  AS OrgStatusCode,      -- ACTIVE | PENDING | SUSPENDED (org's own status)
        o.MemberCount,
        om.CreatedAt  AS JoinedAt
    FROM OrgMembers om
    JOIN Organisations o   ON om.OrgId   = o.OrgId   AND o.IsDeleted = 0
    JOIN LookupValues sv   ON om.StatusLkpId = sv.LookupValueId       -- FIXED: was ApprovalStatusLkpId
    JOIN LookupValues rv   ON om.RoleLkpId   = rv.LookupValueId
    JOIN LookupValues os   ON o.StatusLkpId  = os.LookupValueId       -- org approval status
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId    = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode IN ('APPROVED', 'PENDING')    -- FIXED: was only 'APPROVED'
    ORDER BY om.CreatedAt DESC;
END //

DELIMITER ;

-- Verify: quick test query (replace 1 with a real UserId)
-- CALL User_GetMyOrgs(1);

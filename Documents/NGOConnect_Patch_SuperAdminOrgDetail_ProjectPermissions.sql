-- ============================================================
-- Patch: SuperAdmin_Org_GetDetail — return CanCreateRecurring/CanCreateFlexible
--        + OrgMaxVolunteers
-- ============================================================
-- The v5.1-org-perms migration (Organisations.CanCreateRecurring/CanCreateFlexible
-- + SuperAdmin_UpdateOrgProjectPermissions) added these flags to Org_GetProfile
-- (mobile-facing) but never to SuperAdmin_Org_GetDetail — the SP actually behind
-- GET /api/v1/superadmin/orgs/{orgId}, which the Super Admin website's org detail
-- drawer calls. Without this, the Project Permissions section has no way to know
-- the org's current flag/limit state on load. OrgMaxVolunteers repeated the exact
-- same gap when it was added later — fixed here in the same pass.
--
-- Requires Organisations.OrgMaxVolunteers and Documents/patch_org_project_permissions.sql
-- (Organisations.CanCreateRecurring/CanCreateFlexible) to already be applied.
--
-- Apply to: local dev DB, Railway staging, Railway production.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetDetail //
CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.Is80GEligible, o.Is12AEligible,
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        founder.UserId AS FounderUserId,
        CONCAT(fp.FirstName, ' ', fp.LastName) AS FounderName,
        u.Email AS FounderEmail, u.Mobile AS FounderMobile,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason,
        (SELECT COUNT(*) FROM OrgMembers om2
          JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
          WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
            AND sv2.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    LEFT JOIN OrgMembers founder ON founder.OrgId = o.OrgId AND founder.IsDeleted = 0
        AND founder.RoleLkpId = (
            SELECT LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
    LEFT JOIN Users u ON founder.UserId = u.UserId
    LEFT JOIN UserProfiles fp ON founder.UserId = fp.UserId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DELIMITER ;

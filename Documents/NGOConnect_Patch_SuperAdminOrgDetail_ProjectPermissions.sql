-- ============================================================
-- Patch: SuperAdmin_Org_GetDetail — return CanCreateRecurring/CanCreateFlexible
--        + OrgMaxVolunteers, and fix SuperAdmin_UpdateOrgProjectPermissions
--        to actually accept/persist OrgMaxVolunteers
-- ============================================================
-- The v5.1-org-perms migration (Organisations.CanCreateRecurring/CanCreateFlexible
-- + SuperAdmin_UpdateOrgProjectPermissions) added these flags to Org_GetProfile
-- (mobile-facing) but never to SuperAdmin_Org_GetDetail — the SP actually behind
-- GET /api/v1/superadmin/orgs/{orgId}, which the Super Admin website's org detail
-- drawer calls. Without this, the Project Permissions section has no way to know
-- the org's current flag/limit state on load.
--
-- OrgMaxVolunteers repeated the exact same read-side gap when it was added later
-- (fixed below), and ALSO exposed a second, more serious gap discovered
-- 2026-08-17: the column itself and the write-side SP were never patched onto
-- an already-existing database either.
--   - Organisations.OrgMaxVolunteers only existed in the setup SQL's CREATE
--     TABLE (fresh installs), never in a patch — so it doesn't exist on any
--     DB that was created before this column was added to the setup SQL.
--   - SuperAdmin_UpdateOrgProjectPermissions on any already-patched DB is
--     still the OLD 4-parameter version from patch_org_project_permissions.sql
--     (OrgId, CanCreateRecurring, CanCreateFlexible, UpdatedBy) — it has no
--     p_OrgMaxVolunteers parameter at all, even though the DAL has been
--     calling it with 5 parameters. This is why "Max Volunteers" updates from
--     the Super Admin website silently failed to persist: either an unknown-
--     column error (if the column was missing) or a parameter-count mismatch
--     against the stale SP.
-- This patch fixes both, so it is now self-contained — it does NOT require
-- OrgMaxVolunteers to already exist. It still requires
-- Documents/patch_org_project_permissions.sql (Organisations.CanCreateRecurring/
-- CanCreateFlexible + the original 4-param SuperAdmin_UpdateOrgProjectPermissions)
-- to already be applied.
--
-- Apply to: local dev DB, Railway staging, Railway production.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS / DROP+CREATE are idempotent.
-- ============================================================

-- ============================================================
-- STEP 0: Add OrgMaxVolunteers column (never patched before this)
-- ============================================================

ALTER TABLE Organisations
    ADD COLUMN IF NOT EXISTS OrgMaxVolunteers INT UNSIGNED NOT NULL DEFAULT 100
        COMMENT 'Super Admin sets per-org max volunteers per project. Enforced in Project_Create + Project_Update.';

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

-- ============================================================
-- STEP 2: SuperAdmin_UpdateOrgProjectPermissions — replace the old
-- 4-param version with the 5-param version that also writes
-- OrgMaxVolunteers. Matches NGOConnect_Complete_Setup_v5.0.sql exactly.
-- ============================================================

DROP PROCEDURE IF EXISTS SuperAdmin_UpdateOrgProjectPermissions //
CREATE PROCEDURE SuperAdmin_UpdateOrgProjectPermissions(
    IN p_OrgId              INT UNSIGNED,
    IN p_CanCreateRecurring TINYINT(1),
    IN p_CanCreateFlexible  TINYINT(1),
    IN p_OrgMaxVolunteers   INT UNSIGNED,
    IN p_UpdatedBy          INT UNSIGNED
)
BEGIN
    DECLARE v_Error VARCHAR(500) DEFAULT NULL;
    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SET v_Error = 'Organisation not found.';
    END IF;
    IF v_Error IS NULL AND p_OrgMaxVolunteers IS NOT NULL AND p_OrgMaxVolunteers = 0 THEN
        SET v_Error = 'Max volunteers per project must be at least 1.';
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE
        UPDATE Organisations
        SET CanCreateRecurring = COALESCE(p_CanCreateRecurring, CanCreateRecurring),
            CanCreateFlexible  = COALESCE(p_CanCreateFlexible,  CanCreateFlexible),
            OrgMaxVolunteers   = COALESCE(p_OrgMaxVolunteers,   OrgMaxVolunteers),
            UpdatedAt          = NOW(),
            UpdatedBy          = p_UpdatedBy
        WHERE OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Organisation limits updated successfully.' AS Message;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- VERIFICATION QUERY (run after applying)
-- ============================================================
-- SELECT OrgId, OrgName, CanCreateRecurring, CanCreateFlexible, OrgMaxVolunteers
-- FROM Organisations WHERE IsDeleted = 0 ORDER BY OrgId;
-- Expected: OrgMaxVolunteers = 100 for every existing row (column default).

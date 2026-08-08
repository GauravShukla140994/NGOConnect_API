-- ============================================================
-- NGO Connect — Final Patch: User_GetMyOrgs
-- Date    : 2026-07-09
--
-- ROOT CAUSE OF BUG:
--   The database was running the original User_GetMyOrgs SP (from
--   NGOConnect_Complete_Setup_v4.3.sql) which does NOT return the
--   MemberStatusCode or OrgStatusCode columns.
--
--   BaseDal.Col<T> safely handles missing columns (returns default/"")
--   so no exception is thrown — but UserOrgModel gets:
--       MemberStatusCode = ""
--       OrgStatusCode    = ""
--
--   MyOrgsScreen.tsx then filters:
--       activeOrgs:  o.memberStatusCode === 'APPROVED'  → "" === 'APPROVED'  → false ❌
--       pendingOrgs: o.memberStatusCode === 'PENDING'   → "" === 'PENDING'   → false ❌
--
--   Result: org never appears in either section even though the user IS
--   a member (Org_GetProfile correctly shows "✓ Member" because its
--   patch was applied separately).
--
-- FIX:
--   UNION of two parts:
--     Part 1 — APPROVED rows from OrgMembers
--     Part 2 — PENDING rows from OrgMembershipRequests
--
--   Key hardening vs. previous patch:
--     • rv (role) and ot (org type) are LEFT JOINs — NULL RoleLkpId or
--       OrgTypeLkpId no longer silently drops the row
--     • os (org status) is LEFT JOIN — NULL org StatusLkpId handled
--       gracefully (frontend defaults orgStatusCode → 'ACTIVE')
--
-- Apply: Run against NGOConnect database.
-- Safe to run multiple times.
-- ============================================================

USE NGOConnect;

DROP PROCEDURE IF EXISTS User_GetMyOrgs;

DELIMITER //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- ── Part 1: Approved memberships via OrgMembers ───────────────────────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName  AS OrgType,
        o.City,
        o.State,
        COALESCE(rv.ValueName, 'Member')  AS Role,
        COALESCE(rv.ValueCode, 'MEMBER')  AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
             JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
             JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
             WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
               AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        om.CreatedAt  AS JoinedAt,
        sv.ValueCode  AS MemberStatusCode,   -- always 'APPROVED' here
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId       = o.OrgId              AND o.IsDeleted  = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId     -- MEMBER_STATUS
    LEFT JOIN LookupValues  rv ON om.RoleLkpId   = rv.LookupValueId -- MEMBER_ROLE (nullable-safe)
    LEFT JOIN LookupValues  os ON o.StatusLkpId  = os.LookupValueId -- ORG_STATUS  (nullable-safe)
    LEFT JOIN LookupValues  ot ON o.OrgTypeLkpId = ot.LookupValueId -- ORG_TYPE    (nullable-safe)
    WHERE om.UserId    = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- ── Part 2: Pending join requests via OrgMembershipRequests ──────────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName           AS OrgType,
        o.City,
        o.State,
        'Member'               AS Role,
        'MEMBER'               AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
             JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
             JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
             WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
               AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        mr.CreatedAt           AS JoinedAt,
        'PENDING'              AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId       = o.OrgId              AND o.IsDeleted  = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId     -- MEMBER_STATUS
    LEFT JOIN LookupValues  os ON o.StatusLkpId  = os.LookupValueId -- ORG_STATUS  (nullable-safe)
    LEFT JOIN LookupValues  ot ON o.OrgTypeLkpId = ot.LookupValueId -- ORG_TYPE    (nullable-safe)
    WHERE mr.UserId    = p_UserId
      AND mr.IsDeleted = 0
      AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;

END //

DELIMITER ;

-- ── Verify: replace 4 with the affected UserId ───────────────────────────────
-- CALL User_GetMyOrgs(4);

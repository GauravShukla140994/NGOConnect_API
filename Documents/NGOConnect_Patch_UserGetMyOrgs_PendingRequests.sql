-- ============================================================
-- NGO CONNECT — PATCH: User_GetMyOrgs — include pending requests
-- Date    : 2026-07-08
-- Problem : SP only read OrgMembers with sv.ValueCode = 'APPROVED',
--           so pending membership requests (in OrgMembershipRequests)
--           were never returned and the Pending Requests section was empty.
-- Fix     : UNION with OrgMembershipRequests for PENDING rows.
--           Both parts now return MemberStatusCode + OrgStatusCode so
--           the frontend partition logic works correctly.
-- ============================================================

USE ngoconnect;

DROP PROCEDURE IF EXISTS User_GetMyOrgs;

DELIMITER //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- ── Part 1: Approved memberships (OrgMembers) ────────────────────────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName   AS OrgType,
        o.City,
        o.State,
        rv.ValueName   AS Role,
        rv.ValueCode   AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
            JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
            JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
              AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        om.CreatedAt   AS JoinedAt,
        sv.ValueCode   AS MemberStatusCode,
        os.ValueCode   AS OrgStatusCode
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId
    JOIN  LookupValues  rv ON om.RoleLkpId   = rv.LookupValueId
    JOIN  LookupValues  os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId    = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- ── Part 2: Pending membership requests (OrgMembershipRequests) ──────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName   AS OrgType,
        o.City,
        o.State,
        'Member'       AS Role,
        'MEMBER'       AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
            JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
            JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
              AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        mr.CreatedAt   AS JoinedAt,
        'PENDING'      AS MemberStatusCode,
        os.ValueCode   AS OrgStatusCode
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId = o.OrgId AND o.IsDeleted = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId
    JOIN  LookupValues  os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE mr.UserId    = p_UserId
      AND mr.IsDeleted = 0
      AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;
END //

DELIMITER ;

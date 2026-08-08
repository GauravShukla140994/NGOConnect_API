-- ============================================================
-- NGOConnect Patch: User_GetMyOrgs — OrgStatusCode + SuspendedAt
-- Date:    2026-07-31
-- Changes:
--   1. OrgStatusCode: old SP (pre-v4.5) didn't return this column.
--      All client-side suspended-org filters rely on it. Without it,
--      orgStatusCode is always "" and suspended NGOs appear everywhere.
--   2. SuspendedAt: new column — returns the most recent SUSPENDED
--      entry from OrgStatusHistory so MyOrgsScreen can show the
--      exact date/time the organisation was suspended.
--   3. UNION with pending join requests (v4.5 feature).
-- Apply to: Railway Staging, then Railway Production
-- SAFE to re-apply (DROP + CREATE pattern)
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS User_GetMyOrgs //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- Approved memberships (OrgStatusCode included — used by client suspended-org filters)
    SELECT
        o.OrgId, o.OrgName, o.LogoUrl,
        ot.ValueName AS OrgType, o.City, o.State,
        COALESCE(rv.ValueName, 'Member') AS Role,
        COALESCE(rv.ValueCode, 'MEMBER') AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        om.CreatedAt AS JoinedAt,
        sv.ValueCode AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode,
        (SELECT h.Reason FROM OrgStatusHistory h
         JOIN LookupValues hv ON h.NewStatusLkpId = hv.LookupValueId
         JOIN LookupTypes  ht ON hv.LookupTypeId  = ht.LookupTypeId
         WHERE h.OrgId = o.OrgId AND ht.TypeCode = 'ORG_STATUS' AND hv.ValueCode = 'REJECTED'
         ORDER BY h.CreatedAt DESC LIMIT 1
        ) AS RejectionReason,
        (SELECT h.CreatedAt FROM OrgStatusHistory h
         JOIN LookupValues hv ON h.NewStatusLkpId = hv.LookupValueId
         JOIN LookupTypes  ht ON hv.LookupTypeId  = ht.LookupTypeId
         WHERE h.OrgId = o.OrgId AND ht.TypeCode = 'ORG_STATUS' AND hv.ValueCode = 'SUSPENDED'
         ORDER BY h.CreatedAt DESC LIMIT 1
        ) AS SuspendedAt
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN LookupValues rv ON om.RoleLkpId   = rv.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId = p_UserId AND om.IsDeleted = 0 AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- Pending join requests (so MyOrgsScreen shows pending orgs too)
    SELECT
        o.OrgId, o.OrgName, o.LogoUrl,
        ot.ValueName AS OrgType, o.City, o.State,
        'Member' AS Role, 'MEMBER' AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        mr.CreatedAt AS JoinedAt,
        'PENDING' AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode,
        NULL AS RejectionReason,
        NULL AS SuspendedAt
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE mr.UserId = p_UserId AND mr.IsDeleted = 0 AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;
END //

DELIMITER ;

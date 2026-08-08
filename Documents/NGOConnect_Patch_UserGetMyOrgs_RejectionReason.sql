-- ============================================================
-- NGOConnect Patch: User_GetMyOrgs — add RejectionReason
-- Created : 2026-07-19 (rev 2)
-- Apply to: local DB → Railway staging → Railway production
-- Safe    : DROP + CREATE is idempotent
-- Purpose : MyOrgsScreen's RejectedOrgCard was showing
--           "No specific reason provided" for all rejections.
--           RejectionReason is stored in OrgStatusHistory.Reason
--           (written by SuperAdmin_Org_Reject). Fetched via
--           correlated subquery — most recent REJECTED entry.
--           NOTE: Organisations table has NO RejectionReason
--           column — earlier patch rev was wrong to reference it.
-- ============================================================

DROP PROCEDURE IF EXISTS User_GetMyOrgs;

DELIMITER //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- Approved memberships (includes REJECTED orgs where founder must resubmit)
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
        ) AS RejectionReason
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN LookupValues rv ON om.RoleLkpId   = rv.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId = p_UserId AND om.IsDeleted = 0 AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- Pending join requests
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
        NULL AS RejectionReason
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE mr.UserId = p_UserId AND mr.IsDeleted = 0 AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;
END //

DELIMITER ;

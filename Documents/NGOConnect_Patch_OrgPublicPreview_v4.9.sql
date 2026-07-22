-- ============================================================
-- NGO Connect — Patch: Org_GetPublicPreview SP
-- Version : v4.9
-- Apply to: Railway staging + production
-- Run once, safe to re-run (DROP IF EXISTS before CREATE)
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetPublicPreview //

-- Public preview — no auth required — used by website deep link landing page (/ngo/{id})
CREATE PROCEDURE Org_GetPublicPreview(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        o.City,
        LEFT(o.About, 200)  AS AboutShort,
        vl.ValueCode        AS VerificationStatusCode,
        (SELECT COUNT(*) FROM OrgMembers om
             JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
             JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
             WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
               AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount
    FROM   Organisations o
    LEFT JOIN LookupValues vl ON o.VerificationStatusLkpId = vl.LookupValueId
    WHERE  o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DELIMITER ;

-- Verify
CALL Org_GetPublicPreview(1);

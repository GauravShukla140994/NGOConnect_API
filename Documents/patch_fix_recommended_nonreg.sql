-- ============================================================
-- Patch: Add IsNonRegistered to Org_ListRecommended SP
-- Problem: Recommended tab in ExploreScreen showed "✓ Reg" for
--          all orgs (including non-registered) because the SP
--          didn't return IsNonRegistered in its SELECT.
-- Affected SP: Org_ListRecommended (modified)
-- Author : NGO Connect
-- Date   : 2026-08-26
-- ============================================================

USE ngoconnect;
DELIMITER //

DROP PROCEDURE IF EXISTS Org_ListRecommended //

-- v5.1 MODIFIED: +o.IsNonRegistered so Recommended tab badge renders correctly
CREATE PROCEDURE Org_ListRecommended(IN p_UserId INT)
BEGIN
    DECLARE v_ApprovedId   INT;
    DECLARE v_OrgCatTypeId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT LookupTypeId INTO v_OrgCatTypeId
    FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1;

    SELECT
        o.OrgId, o.OrgName, o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.LogoUrl, o.City, o.State,
        o.IsNonRegistered,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating, o.Latitude, o.Longitude,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        COUNT(ui.UserInterestId) AS MatchScore
    FROM Organisations o
    JOIN UserInterests ui ON ui.UserId = p_UserId
    JOIN LookupValues  lv ON ui.InterestLkpId = lv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND lv.ValueCode = o.Category
    GROUP BY o.OrgId, o.IsNonRegistered, vv.ValueCode, cv.ValueName
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedAt)
VALUES ('5.1.10', 'Fix Org_ListRecommended — add IsNonRegistered to SELECT', NOW());

-- ============================================================
-- Patch: Restore IsNonRegistered in Org_List + Org_ListRecommended
-- Root cause: patch_org_category_name.sql re-created both SPs
--             without the IsNonRegistered column that was added
--             in patch_non_registered_orgs.sql, silently dropping
--             the field from the explore list response.
-- Effect: All Orgs + Recommended tabs showed ✓ Reg for every
--         org regardless of actual registration status.
-- Affected SPs: Org_List (modified), Org_ListRecommended (modified)
-- Author : NGO Connect
-- Date   : 2026-08-26
-- ============================================================

USE ngoconnect;
DELIMITER //

-- ── 1. Org_List ───────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Org_List //

CREATE PROCEDURE Org_List(
    IN p_Keyword    VARCHAR(200),
    IN p_Category   VARCHAR(100),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset        INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ApprovedId    INT;
    DECLARE v_OrgCatTypeId  INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT LookupTypeId INTO v_OrgCatTypeId
    FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1;

    -- Result set 1: page
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.LogoUrl,
        o.City,
        o.State,
        o.IsNonRegistered,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.FollowerCount,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude
    FROM Organisations o
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY o.OrgName
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

-- ── 2. Org_ListRecommended ────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Org_ListRecommended //

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
VALUES ('5.1.11', 'Fix Org_List + Org_ListRecommended — restore IsNonRegistered dropped by patch_org_category_name', NOW());

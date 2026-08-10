-- ── patch_org_category_name.sql ──────────────────────────────────────────────
-- Fix: Organisation category showing ValueCode instead of ValueName.
--
-- Root cause: Organisations.Category stores the ORG_CATEGORY ValueCode (e.g.
--   "WOMEN_EMP") because Org_Register / Org_Update receive the code from the
--   mobile form.  Three read SPs returned o.Category as-is — no JOIN to
--   LookupValues — so the mobile displayed the raw code.
--
-- Mobile already has "categoryName ?? category" fallback (ExploreScreen,
--   NgoProfileScreen).  Fix: add CategoryName column (resolved ValueName) to
--   all three list/detail SPs.  Category (raw code) is kept for backward-compat
--   filtering; CategoryName is the new display-name column the mobile picks up.
--
-- Affected SPs (3):
--   Org_List          → Explore tab
--   Org_GetProfile    → NgoProfileScreen (public profile)
--   Org_ListRecommended → Home feed recommendations
--
-- No table / column / C# / mobile changes needed — SP-only fix.
-- Apply: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

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
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY o.OrgName
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count (no JOIN needed — no CategoryName here)
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

-- ── 2. Org_GetProfile ─────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED     -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        COALESCE(ods.Is80GEligible, o.Is80GEligible, 0) AS Is80GEligible,
        COALESCE(ods.Is12AEligible, o.Is12AEligible, 0) AS Is12AEligible,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        sv.ValueCode AS OrgStatusCode,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.AvgRating, o.RatingCount, o.Latitude, o.Longitude, o.CreatedAt,
        o.FollowerCount,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = o.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        (SELECT COUNT(*)
         FROM OrgMembers   om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        COALESCE(
            (SELECT lv3.ValueCode FROM OrgMembers   om3
             JOIN LookupValues lv3 ON om3.StatusLkpId = lv3.LookupValueId
             WHERE om3.OrgId = o.OrgId AND om3.UserId = p_UserId AND om3.IsDeleted = 0 LIMIT 1),
            (SELECT lv4.ValueCode FROM OrgMembershipRequests mr4
             JOIN LookupValues lv4 ON mr4.StatusLkpId = lv4.LookupValueId
             WHERE mr4.OrgId = o.OrgId AND mr4.UserId = p_UserId AND mr4.IsDeleted = 0
               AND lv4.ValueCode = 'PENDING' LIMIT 1)
        ) AS MemberStatusCode
    FROM Organisations o
    LEFT JOIN OrgDonationSettings ods ON ods.OrgId = o.OrgId
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category
                              AND cv.LookupTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1)
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- ── 3. Org_ListRecommended ────────────────────────────────────────────────────
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
    GROUP BY o.OrgId, vv.ValueCode, cv.ValueName
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

DELIMITER ;

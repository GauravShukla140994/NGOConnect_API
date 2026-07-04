-- ============================================================
-- TestSeed_ExplorePatches.sql  (v2 — corrected column names)
-- Fixes for Explore screen: Recommended + Trending tabs
-- + Org_List SP enhanced with optional lat/lng distance sort
-- + Org_ListRecommended SP fixed with LEFT JOIN fallback
-- + Campaign_ListPublicTrending SP fixed (no IsActive/IsEmergency cols)
-- Run AFTER TestSeed_ExploreNGOs.sql
-- ============================================================

DELIMITER //

-- ────────────────────────────────────────────────────────────
-- 1. Fix Category values in test NGOs → match INTEREST_TYPE ValueCodes
-- ────────────────────────────────────────────────────────────
UPDATE Organisations SET Category = 'ANIMAL_WELFARE' WHERE Category = 'Animal Welfare' AND RegNumber LIKE 'TEST-%' //
UPDATE Organisations SET Category = 'COMMUNITY'      WHERE Category = 'Community Dev'  AND RegNumber LIKE 'TEST-%' //
UPDATE Organisations SET Category = 'EDUCATION'      WHERE Category = 'Education'      AND RegNumber LIKE 'TEST-%' //
UPDATE Organisations SET Category = 'ENVIRONMENT'    WHERE Category = 'Environment'    AND RegNumber LIKE 'TEST-%' //
UPDATE Organisations SET Category = 'HEALTHCARE'     WHERE Category = 'Healthcare'     AND RegNumber LIKE 'TEST-%' //

-- ────────────────────────────────────────────────────────────
-- 2. Add UserInterests for userId=1
-- ────────────────────────────────────────────────────────────
DELETE FROM UserInterests WHERE UserId = 1 //

INSERT INTO UserInterests (UserId, InterestLkpId)
SELECT 1, lv.LookupValueId
FROM LookupValues lv
JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
WHERE lt.TypeCode = 'INTEREST_TYPE'
  AND lv.ValueCode IN ('EDUCATION','HEALTHCARE','ENVIRONMENT','COMMUNITY','ANIMAL_WELFARE') //

-- ────────────────────────────────────────────────────────────
-- 3. Add DonationCampaigns — using correct table columns:
--    StatusLkpId    → CAMPAIGN_STATUS 'ACTIVE'
--    CampaignTypeLkpId → CAMPAIGN_TYPE 'GENERAL' or 'EMERGENCY'
--    VisibilityLkpId   → POST_VISIBILITY 'PUBLIC'
--    No IsActive / IsEmergency boolean columns (they don't exist)
-- ────────────────────────────────────────────────────────────
SET @chd1 = (SELECT OrgId FROM Organisations WHERE RegNumber = 'TEST-CHD-001' LIMIT 1) //
SET @chd2 = (SELECT OrgId FROM Organisations WHERE RegNumber = 'TEST-CHD-002' LIMIT 1) //
SET @chd3 = (SELECT OrgId FROM Organisations WHERE RegNumber = 'TEST-CHD-003' LIMIT 1) //
SET @blr2 = (SELECT OrgId FROM Organisations WHERE RegNumber = 'TEST-BLR-002' LIMIT 1) //
SET @blr3 = (SELECT OrgId FROM Organisations WHERE RegNumber = 'TEST-BLR-003' LIMIT 1) //

SET @status_active = (
    SELECT lv.LookupValueId FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1
) //

SET @type_general = (
    SELECT lv.LookupValueId FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_TYPE' AND lv.ValueCode = 'GENERAL' LIMIT 1
) //

SET @type_emergency = (
    SELECT lv.LookupValueId FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_TYPE' AND lv.ValueCode = 'EMERGENCY' LIMIT 1
) //

SET @vis_public = (
    SELECT lv.LookupValueId FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1
) //

-- Campaign 1 — Education (high donor count → ranks high)
INSERT INTO DonationCampaigns
  (OrgId, CreatedByUserId, CampaignName, Description, CampaignTypeLkpId,
   TargetAmount, RaisedAmount, DonorCount,
   StartDate, EndDate, VisibilityLkpId, StatusLkpId, IsDeleted, CreatedBy)
VALUES
  (@chd1, 1, 'Digital Classroom Initiative 2026',
   'Equip 500 underprivileged students in Chandigarh with tablets and broadband access.',
   @type_general, 500000, 312000, 87,
   DATE_SUB(CURDATE(), INTERVAL 30 DAY), DATE_ADD(CURDATE(), INTERVAL 60 DAY),
   @vis_public, @status_active, 0, 1) //

-- Campaign 2 — Environment EMERGENCY (IsEmergency=CAMPAIGN_TYPE → ranks first)
INSERT INTO DonationCampaigns
  (OrgId, CreatedByUserId, CampaignName, Description, CampaignTypeLkpId,
   TargetAmount, RaisedAmount, DonorCount,
   StartDate, EndDate, VisibilityLkpId, StatusLkpId, IsDeleted, CreatedBy)
VALUES
  (@chd2, 1, 'Sukhna Lake Emergency Cleanup',
   'Emergency restoration of Sukhna Lake after monsoon pollution. Every rupee counts.',
   @type_emergency, 200000, 178000, 134,
   DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_ADD(CURDATE(), INTERVAL 15 DAY),
   @vis_public, @status_active, 0, 1) //

-- Campaign 3 — Healthcare
INSERT INTO DonationCampaigns
  (OrgId, CreatedByUserId, CampaignName, Description, CampaignTypeLkpId,
   TargetAmount, RaisedAmount, DonorCount,
   StartDate, EndDate, VisibilityLkpId, StatusLkpId, IsDeleted, CreatedBy)
VALUES
  (@chd3, 1, 'Free Health Camps — Rural Punjab',
   'Funding 12 free medical camps across rural Punjab villages this quarter.',
   @type_general, 300000, 95000, 43,
   DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 40 DAY),
   @vis_public, @status_active, 0, 1) //

-- Campaign 4 — Environment Bangalore
INSERT INTO DonationCampaigns
  (OrgId, CreatedByUserId, CampaignName, Description, CampaignTypeLkpId,
   TargetAmount, RaisedAmount, DonorCount,
   StartDate, EndDate, VisibilityLkpId, StatusLkpId, IsDeleted, CreatedBy)
VALUES
  (@blr2, 1, 'Zero Waste Bangalore — Phase 2',
   'Scale our dry waste collection network to 10,000 more households in South Bangalore.',
   @type_general, 400000, 267000, 112,
   DATE_SUB(CURDATE(), INTERVAL 45 DAY), DATE_ADD(CURDATE(), INTERVAL 30 DAY),
   @vis_public, @status_active, 0, 1) //

-- Campaign 5 — Healthcare Bangalore
INSERT INTO DonationCampaigns
  (OrgId, CreatedByUserId, CampaignName, Description, CampaignTypeLkpId,
   TargetAmount, RaisedAmount, DonorCount,
   StartDate, EndDate, VisibilityLkpId, StatusLkpId, IsDeleted, CreatedBy)
VALUES
  (@blr3, 1, 'Mobile Health Unit for Slum Communities',
   'Purchase a mobile medical van to serve 5,000+ residents of KR Puram slum clusters.',
   @type_general, 750000, 189000, 61,
   DATE_SUB(CURDATE(), INTERVAL 10 DAY), DATE_ADD(CURDATE(), INTERVAL 50 DAY),
   @vis_public, @status_active, 0, 1) //

-- ────────────────────────────────────────────────────────────
-- 4. Fix Campaign_ListPublicTrending SP
--    Old version wrongly used dc.IsActive and dc.IsEmergency.
--    Correct: JOIN on StatusLkpId (ACTIVE) and CampaignTypeLkpId (EMERGENCY).
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Campaign_ListPublicTrending //
CREATE PROCEDURE Campaign_ListPublicTrending(IN p_PageSize INT)
BEGIN
    DECLARE v_ActiveStatusId  INT;
    DECLARE v_EmergencyTypeId INT;

    SELECT lv.LookupValueId INTO v_ActiveStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_EmergencyTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_TYPE' AND lv.ValueCode = 'EMERGENCY' LIMIT 1;

    SELECT
        dc.CampaignId,
        dc.CampaignName,
        o.OrgName,
        o.LogoUrl                                           AS OrgLogoUrl,
        dc.RaisedAmount,
        dc.TargetAmount,
        dc.DonorCount,
        ROUND(IF(dc.TargetAmount > 0,
                 dc.RaisedAmount / dc.TargetAmount * 100, 0), 2) AS ProgressPct,
        dc.EndDate,
        dc.BannerUrl,
        -- IsEmergency: 1 when CampaignType = EMERGENCY, else 0
        IF(dc.CampaignTypeLkpId = v_EmergencyTypeId, 1, 0) AS IsEmergency
    FROM DonationCampaigns dc
    JOIN Organisations o ON dc.OrgId = o.OrgId
    WHERE dc.StatusLkpId = v_ActiveStatusId
      AND dc.IsDeleted   = 0
      AND o.IsDeleted    = 0
    ORDER BY
        IF(dc.CampaignTypeLkpId = v_EmergencyTypeId, 1, 0) DESC,  -- emergency first
        dc.DonorCount    DESC,
        dc.RaisedAmount  DESC
    LIMIT p_PageSize;
END //

-- ────────────────────────────────────────────────────────────
-- 5. Fix Org_ListRecommended — LEFT JOIN fallback
--    Works for users with no interests (shows top-rated orgs, MatchScore=0)
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_ListRecommended //
CREATE PROCEDURE Org_ListRecommended(IN p_UserId INT)
BEGIN
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude,
        COUNT(ui.UserInterestId) AS MatchScore
    FROM Organisations o
    LEFT JOIN UserInterests ui ON ui.UserId = p_UserId
    LEFT JOIN LookupValues  lv ON ui.InterestLkpId = lv.LookupValueId
                               AND lv.ValueCode = o.Category
    WHERE o.IsDeleted   = 0
      AND o.StatusLkpId = v_ApprovedId
    GROUP BY o.OrgId, o.OrgName, o.Category, o.LogoUrl, o.City, o.State,
             o.AvgRating, o.Latitude, o.Longitude
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

-- ────────────────────────────────────────────────────────────
-- 6. Update Org_List — add optional p_Lat / p_Lng for distance sort
--    NULL = sort by AvgRating (existing behaviour preserved)
--    Provided = sort nearest-first via server-side Haversine
-- ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Keyword    VARCHAR(200),
    IN p_Category   VARCHAR(100),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_Lat        DECIMAL(10,7),
    IN p_Lng        DECIMAL(10,7)
)
BEGIN
    DECLARE v_ApprovedId INT;
    DECLARE v_Offset     INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude,
        CASE
            WHEN p_Lat IS NOT NULL AND p_Lng IS NOT NULL
                 AND o.Latitude IS NOT NULL AND o.Longitude IS NOT NULL
            THEN ROUND(6371 * ACOS(GREATEST(-1, LEAST(1,
                    COS(RADIANS(p_Lat)) * COS(RADIANS(o.Latitude))
                    * COS(RADIANS(o.Longitude) - RADIANS(p_Lng))
                    + SIN(RADIANS(p_Lat)) * SIN(RADIANS(o.Latitude))
                 ))), 2)
            ELSE NULL
        END AS DistanceKm
    FROM Organisations o
    WHERE o.IsDeleted   = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword  IS NULL OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY
        CASE
            WHEN p_Lat IS NOT NULL AND p_Lng IS NOT NULL
                 AND o.Latitude IS NOT NULL AND o.Longitude IS NOT NULL
            THEN 6371 * ACOS(GREATEST(-1, LEAST(1,
                    COS(RADIANS(p_Lat)) * COS(RADIANS(o.Latitude))
                    * COS(RADIANS(o.Longitude) - RADIANS(p_Lng))
                    + SIN(RADIANS(p_Lat)) * SIN(RADIANS(o.Latitude))
                 )))
            ELSE 99999
        END ASC,
        o.AvgRating DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted   = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword  IS NULL OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

DELIMITER ;

-- ── Verification ─────────────────────────────────────────────
SELECT 'UserInterests for userId=1' AS Label, COUNT(*) AS Count_ FROM UserInterests WHERE UserId = 1;
SELECT 'Active campaigns'           AS Label, COUNT(*) AS Count_
FROM DonationCampaigns dc
JOIN LookupValues lv ON dc.StatusLkpId = lv.LookupValueId
JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
WHERE lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' AND dc.IsDeleted = 0;
SELECT o.OrgName, o.Category, o.City FROM Organisations o WHERE RegNumber LIKE 'TEST-%' ORDER BY o.City, o.Category;

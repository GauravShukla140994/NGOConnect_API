-- ============================================================
-- Fix_ExploreCategory.sql
-- Run this if:
--   a) All NGOs tab is blank  → applies updated Org_List SP (adds p_Lat / p_Lng)
--   b) Trending category filter does not work → adds OrgCategory column to result
-- Safe to re-run — uses DROP PROCEDURE IF EXISTS before each CREATE.
-- ============================================================

DELIMITER //

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Campaign_ListPublicTrending — adds o.Category AS OrgCategory
--    Required for client-side category filtering on the Trending tab.
-- ────────────────────────────────────────────────────────────────────────────
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
        o.OrgId,
        o.OrgName,
        o.LogoUrl                                           AS OrgLogoUrl,
        o.Category                                          AS OrgCategory,   -- NEW: for client-side filtering
        dc.RaisedAmount,
        dc.TargetAmount,
        dc.DonorCount,
        ROUND(IF(dc.TargetAmount > 0,
                 dc.RaisedAmount / dc.TargetAmount * 100, 0), 2) AS ProgressPct,
        dc.EndDate,
        dc.BannerUrl,
        IF(dc.CampaignTypeLkpId = v_EmergencyTypeId, 1, 0) AS IsEmergency
    FROM DonationCampaigns dc
    JOIN Organisations o ON dc.OrgId = o.OrgId
    WHERE dc.StatusLkpId = v_ActiveStatusId
      AND dc.IsDeleted   = 0
      AND o.IsDeleted    = 0
    ORDER BY
        IF(dc.CampaignTypeLkpId = v_EmergencyTypeId, 1, 0) DESC,
        dc.DonorCount    DESC,
        dc.RaisedAmount  DESC
    LIMIT p_PageSize;
END //

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Org_List — adds optional p_Lat / p_Lng for nearest-first sorting
--    If you already ran TestSeed_ExplorePatches.sql (v2) this is a no-op.
--    If not, this fixes the "All NGOs blank" issue (C# was passing 6 params
--    to the old 4-param SP → MySQL error → silent blank screen).
-- ────────────────────────────────────────────────────────────────────────────
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

    -- Data rows
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

    -- Total count (2nd result set for paging)
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted   = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword  IS NULL OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

DELIMITER ;

-- ── Quick verification ────────────────────────────────────────────────────────
CALL Org_List(NULL, NULL, 1, 5, NULL, NULL);
CALL Campaign_ListPublicTrending(5);

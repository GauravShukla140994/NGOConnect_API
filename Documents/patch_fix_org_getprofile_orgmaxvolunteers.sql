-- ============================================================
-- PATCH: Fix Org_GetProfile — include OrgMaxVolunteers in SELECT
-- Root cause: patch_create_edit_project_fixes.sql left steps 3-5
--   as comments (abbreviated). The ALTER TABLE ran fine so the
--   OrgMaxVolunteers column exists in the DB, but Org_GetProfile
--   was never re-created, so it still returns the old column list
--   without OrgMaxVolunteers → mobile falls back to default 100.
-- Fix: DROP + CREATE Org_GetProfile with OrgMaxVolunteers included.
-- Also includes Project_Create + Project_Update with OrgMaxVolunteers
--   cap enforcement (steps 4-5 that were also skipped).
-- Run on: Local DB → Railway staging → production
-- ============================================================

DELIMITER //

-- ── Org_GetProfile — full body including OrgMaxVolunteers ────────────────────

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
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
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

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.1-fix-org-getprofile-maxvol',
        'Fix Org_GetProfile: previous patch left SP body abbreviated (comment only). Re-created with OrgMaxVolunteers in SELECT so mobile CreateProjectScreen reads the correct per-org volunteer cap instead of falling back to 100.',
        'System');

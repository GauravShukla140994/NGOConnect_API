-- ============================================================
-- NGOConnect Patch: Org_GetProfile — add Is80GEligible / Is12AEligible
-- Created : 2026-07-18
-- Apply to: local DB → Railway staging → Railway production
-- Safe    : DROP + CREATE is idempotent
-- Purpose : Admin Org Screen needs to display 80G / 12A status.
--           These columns were missing from the SELECT — always
--           returned NULL → displayed as "No" regardless of DB value.
-- ============================================================

DROP PROCEDURE IF EXISTS Org_GetProfile;

DELIMITER //

CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED     -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.Is80GEligible, o.Is12AEligible,
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
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DELIMITER ;

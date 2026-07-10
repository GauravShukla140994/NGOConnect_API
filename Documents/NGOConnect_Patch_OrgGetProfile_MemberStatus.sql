-- ============================================================
-- NGO Connect — Patch: Org_GetProfile + MemberStatusCode
-- Version : v4.3 patch
-- Date    : 2026-07-08
-- Purpose : Add p_UserId param to Org_GetProfile so the API
--           can return the calling user's membership status
--           (APPROVED / PENDING / REJECTED / NULL).
--           Used by NgoProfileScreen to disable the
--           "Request to Join" button for existing/pending members.
-- Apply   : Run against NGOConnect database.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED      -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName  AS OrgType,
        o.StatusLkpId,
        sv.ValueName  AS OrgStatus,
        o.AvgRating, o.RatingCount,
        o.Latitude, o.Longitude,
        o.CreatedAt,

        -- Active member count (APPROVED members only)
        (SELECT COUNT(*)
         FROM OrgMembers   om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,

        -- Calling user's membership status:
        --   1. Check OrgMembers first (APPROVED / active members)
        --   2. Fall back to OrgMembershipRequests (PENDING request)
        --   Returns NULL if no record at all (never applied)
        COALESCE(
            (SELECT lv3.ValueCode
             FROM OrgMembers   om3
             JOIN LookupValues lv3 ON om3.StatusLkpId = lv3.LookupValueId
             WHERE om3.OrgId = o.OrgId AND om3.UserId = p_UserId AND om3.IsDeleted = 0
             LIMIT 1),
            (SELECT lv4.ValueCode
             FROM OrgMembershipRequests mr4
             JOIN LookupValues          lv4 ON mr4.StatusLkpId = lv4.LookupValueId
             WHERE mr4.OrgId = o.OrgId AND mr4.UserId = p_UserId AND mr4.IsDeleted = 0
               AND lv4.ValueCode = 'PENDING'
             LIMIT 1)
        ) AS MemberStatusCode

    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DELIMITER ;

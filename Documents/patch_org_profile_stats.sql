-- ─────────────────────────────────────────────────────────────────────────────
-- patch_org_profile_stats.sql
-- Fix: Org public profile page shows 0h Hours and incorrect Projects count.
--
-- Root cause:
--   The mobile calls GET /org/{orgId} → Org_GetProfile SP.
--   Org_GetProfile had no TotalProjectCount or TotalVolunteerHours columns.
--   - Projects count showed via fallback (activeProjects + completedProjects from
--     separate list calls), which was correct but fragile.
--   - Hours showed 0 because org.totalVolunteerHours was undefined → ?? 0 = 0.
--
-- Fix: add TotalProjectCount and TotalVolunteerHours to Org_GetProfile.
--
-- No table/column changes. Apply to Railway staging + production.
-- Safe to re-run (DROP + CREATE is idempotent).
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED     -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.RegistrationDate, o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        -- Is80GEligible / Is12AEligible: prefer OrgDonationSettings, fall back to Organisations columns
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
        ) AS MemberStatusCode,
        -- Total projects (excl. CANCELLED) — used for the "Projects" stat on the profile header
        (SELECT COUNT(*) FROM Projects p
             JOIN LookupValues sv4 ON p.StatusLkpId = sv4.LookupValueId
             WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
               AND sv4.ValueCode NOT IN ('CANCELLED')) AS TotalProjectCount,
        -- Total volunteer hours logged (ATTENDED only) across all org projects
        COALESCE((SELECT SUM(pa.HoursLogged)
             FROM ProjectAttendance pa
             JOIN ProjectSessions   ps ON pa.SessionId  = ps.SessionId
             JOIN Projects          pr ON ps.ProjectId  = pr.ProjectId
             JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
             JOIN LookupTypes       lt ON lv.LookupTypeId      = lt.LookupTypeId
             WHERE pr.OrgId = o.OrgId
               AND lt.TypeCode = 'ATTENDANCE_STATUS'
               AND lv.ValueCode = 'ATTENDED'
             ), 0) AS TotalVolunteerHours
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

SELECT 'patch_org_profile_stats applied successfully.' AS Status;

-- Verify: CALL Org_GetProfile(<your_org_id>, 0);
-- Expected: TotalProjectCount and TotalVolunteerHours columns in result.

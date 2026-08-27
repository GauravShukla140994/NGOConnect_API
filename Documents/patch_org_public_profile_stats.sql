-- ─────────────────────────────────────────────────────────────────────────────
-- patch_org_public_profile_stats.sql
-- Fix: Org public profile page shows 0 Projects and 0h Hours.
--
-- Root cause:
--   1. Mobile read org.activeProjects (field name mismatch with SP's activeProjectCount)
--      and fell back to activeProjects.length = 0 (no active projects). Fixed in mobile.
--   2. SP had no TotalVolunteerHours field → always 0h. Added here.
--   3. "Projects" stat should show total projects (excl. CANCELLED), not active-only.
--      Added TotalProjectCount.
--
-- No table/column changes. Apply to Railway staging + production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetPublicProfile //
CREATE PROCEDURE Org_GetPublicProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_StatusCode VARCHAR(20) DEFAULT NULL;
    DECLARE v_IsDeleted  TINYINT(1)  DEFAULT 1;

    SELECT sv.ValueCode, o.IsDeleted INTO v_StatusCode, v_IsDeleted
    FROM Organisations o
    LEFT JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId
    LIMIT 1;

    IF v_StatusCode IS NULL OR v_IsDeleted = 1 THEN
        SELECT 'NOT_FOUND' AS ProfileState, NULL AS OrgId, NULL AS OrgName;

    ELSEIF v_StatusCode != 'APPROVED' THEN
        SELECT 'UNAVAILABLE' AS ProfileState, o.OrgId, o.OrgName
        FROM Organisations o WHERE o.OrgId = p_OrgId;

    ELSE
        SELECT
            'ACTIVE' AS ProfileState,
            o.OrgId, o.OrgName, o.ContactPerson, o.RegNumber,
            tv.ValueName AS OrgType,
            COALESCE(cv.ValueName, o.Category) AS Category,
            o.LogoUrl, o.About, o.Mission, o.Vision,
            o.ContactEmail, o.ContactPhone, o.Website,
            o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
            o.Latitude, o.Longitude,
            COALESCE(ods.Is80GEligible, o.Is80GEligible, 0) AS Is80GEligible,
            COALESCE(ods.Is12AEligible, o.Is12AEligible, 0) AS Is12AEligible,
            COALESCE(ods.IsDonationEnabled, 0)              AS IsDonationEnabled,
            o.AvgRating, o.RatingCount, o.FollowerCount,
            COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
            o.CreatedAt AS OnPlatformSince,
            (SELECT COUNT(*) FROM OrgMembers om
                 JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
                 JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                 WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
                   AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount,
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv2 ON p.StatusLkpId = sv2.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv2.ValueCode IN ('UPCOMING', 'ACTIVE')) AS ActiveProjectCount,
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv3 ON p.StatusLkpId = sv3.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv3.ValueCode = 'COMPLETED') AS CompletedProjectCount,
            -- Total projects excluding CANCELLED (used for "Projects" stat on profile)
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv4 ON p.StatusLkpId = sv4.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv4.ValueCode NOT IN ('CANCELLED')) AS TotalProjectCount,
            -- Total volunteer hours logged across all org projects (ATTENDED only)
            COALESCE((SELECT SUM(pa.HoursLogged)
                 FROM ProjectAttendance pa
                 JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                 JOIN Projects          pr ON ps.ProjectId = pr.ProjectId
                 JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                 JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                 WHERE pr.OrgId = o.OrgId
                   AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalVolunteerHours
        FROM Organisations o
        LEFT JOIN OrgDonationSettings ods ON ods.OrgId = o.OrgId
        LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
        LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
        LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category
                                  AND cv.LookupTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1)
        WHERE o.OrgId = p_OrgId;
    END IF;
END //

DELIMITER ;

SELECT 'patch_org_public_profile_stats applied successfully.' AS Status;

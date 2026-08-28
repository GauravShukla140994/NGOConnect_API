-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_project_getbyid_visibility.sql
-- Fix: "Could not load project details" when tapping a COMPLETED project on
--      the org's public profile page.
--
-- Root cause:
--   Project_GetById blocks access when IsPublic = 0 and the user is not an
--   approved org member. COMPLETED/EXPIRED projects on the public profile are
--   historical records — any authenticated user should be able to view them.
--
-- Fix: Add OR sv.ValueCode IN ('COMPLETED', 'EXPIRED') to the visibility gate.
--   Past projects are always readable; only ACTIVE/UPCOMING private projects
--   remain restricted to approved members.
--
-- No table/column changes. Apply to Railway staging + production.
-- Safe to re-run (DROP + CREATE is idempotent).
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        DATE_FORMAT(p.RecurStart,    '%Y-%m-%d') AS RecurStart,
        DATE_FORMAT(p.RecurEnd,      '%Y-%m-%d') AS RecurEnd,
        p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        DATE_FORMAT(p.OneTimeDate,   '%Y-%m-%d') AS OneTimeDate,
        DATE_FORMAT(p.FlexFromDate,  '%Y-%m-%d') AS FlexFromDate,
        DATE_FORMAT(p.FlexToDate,    '%Y-%m-%d') AS FlexToDate,
        p.MinHoursRequired,
        p.MinAttendPct, p.MaxDailyHours, p.MinSessionHours,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedCount,
        (SELECT COUNT(*) FROM ProjectSessions WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS TotalSessions,
        (SELECT lv2.ValueCode FROM ProjectApplications pa2
            JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
            WHERE pa2.ProjectId = p.ProjectId AND pa2.UserId = p_UserId AND pa2.IsDeleted = 0
            LIMIT 1) AS ApplicationStatusCode
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0
      AND (
          p.IsPublic = 1
          OR p_UserId IS NULL OR p_UserId = 0
          -- Past projects (COMPLETED/EXPIRED/CANCELLED) are historical records —
          -- always visible on an org's public profile to any authenticated user.
          OR sv.ValueCode IN ('COMPLETED', 'EXPIRED', 'CANCELLED')
          OR EXISTS (
              SELECT 1 FROM OrgMembers om
              JOIN LookupValues omv ON om.StatusLkpId  = omv.LookupValueId
              JOIN LookupTypes  omt ON omv.LookupTypeId = omt.LookupTypeId
              WHERE om.OrgId = p.OrgId AND om.UserId = p_UserId
                AND om.IsDeleted = 0
                AND omt.TypeCode = 'MEMBER_STATUS' AND omv.ValueCode = 'APPROVED'
          )
      );
END //

DELIMITER ;

SELECT 'patch_fix_project_getbyid_visibility applied successfully.' AS Status;

-- Verify: CALL Project_GetById(268, <non_member_user_id>);
-- Expected: returns project details (previously returned empty = NOT_FOUND).

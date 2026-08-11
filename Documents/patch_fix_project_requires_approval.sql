-- ── patch_fix_project_requires_approval.sql ──────────────────────────────────
-- Problem : Project_GetById SP does not return RequiresApproval in its SELECT.
--           The column was introduced in the new Project_Create / Project_Update
--           SPs (v4.8+) but was never back-ported to Project_GetById.
--
--           Result in the app:
--           Admin Dashboard → Project → Manage → Edit opens CreateProjectScreen
--           in edit mode. The prefill reads p.requiresApproval but the API
--           response never contains that key → (undefined ?? false) = false →
--           "Required Approval for Attendance" toggle always shows OFF even when
--           the project has RequiresApproval = 1.
--
-- Fix : Add IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval to the
--       Project_GetById SELECT.  jtv is already LEFT JOINed on JoinTypeLkpId,
--       so this is a zero-cost derived column — no schema change, no DAL change.
--       DynamicRow auto-camelCases it → requiresApproval arrives on the mobile.
--
-- Note: The same IF(...) AS RequiresApproval pattern is used by all Project_List
--       SPs (Project_ListByOrg, Project_ListVolunteer, etc.). This patch makes
--       Project_GetById consistent with the rest.
--
-- Safe to re-run. Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

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
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
END //

DELIMITER ;

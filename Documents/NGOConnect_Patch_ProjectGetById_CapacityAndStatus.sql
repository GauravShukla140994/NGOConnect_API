-- ============================================================
-- Patch: Fix Project_GetById — capacity + application status
-- ============================================================
-- Fixes two bugs in the volunteer Project Detail screen:
--
--   BUG 1: SP returned ApprovedVolunteers but mobile reads approvedCount.
--           Result: isFull was always false → "Apply" button showed on
--           capacity-full projects.
--
--   BUG 2: SP returned MyApplicationStatusId (raw LookupValueId int) but
--           mobile reads applicationStatusCode (string like 'APPROVED').
--           Result: Pending / Approved states never rendered correctly.
--
-- Fix: Rename ApprovedVolunteers → ApprovedCount (matching Project_GetNearbyFeed).
--      Replace MyApplicationStatusId raw-int subquery with a JOIN that
--      returns ValueCode AS ApplicationStatusCode.
--
-- Apply to: local dev DB, Railway staging, Railway production.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        p.RecurStart, p.RecurEnd, p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.MinHoursRequired,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        -- FIX: was ApprovedVolunteers — renamed to ApprovedCount to match
        --      Project_GetNearbyFeed and the mobile Project type (approvedCount)
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedCount,
        -- FIX: was MyApplicationStatusId (raw int FK) — now returns ValueCode string
        --      so mobile applicationStatusCode check ('APPROVED'/'PENDING') works
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

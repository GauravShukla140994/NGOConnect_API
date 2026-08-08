-- ============================================================
-- NGO Connect — Patch: Org_GetDashboard active project count
-- Version : v5.0 patch
-- Date    : 2026-08-08
-- Apply to: Railway staging → Railway production
-- ============================================================
--
-- Problem
-- -------
-- The Admin Dashboard "Active Projects" KPI was only counting
-- projects with status = ACTIVE. Because Hangfire status
-- auto-transition (UPCOMING → ACTIVE) is not yet implemented,
-- projects remain in UPCOMING status even after their start date
-- passes. The count was therefore often showing 0 or a number
-- lower than the actual projects currently in play.
--
-- All other KPI counts (TotalMembers, NewMembersThisMonth,
-- ActiveVolunteers, ActiveRatePct, VolunteerHoursMonth,
-- PendingApplications, PendingProjectApplications, FollowerCount)
-- were audited and are correct.
--
-- Fix
-- ---
-- ActiveProjects now counts projects with status ACTIVE OR UPCOMING.
-- COMPLETED, CANCELLED, and DRAFT statuses are excluded.
-- The DECLARE v_ActiveProjectStatusId variable was removed (no
-- longer needed after switching to an IN subquery on ValueCode).
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetDashboard //
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedMemberStatusId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
        ) AS TotalMembers,

        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
           AND YEAR(JoinedAt) = YEAR(NOW()) AND MONTH(JoinedAt) = MONTH(NOW())
        ) AS NewMembersThisMonth,

        (SELECT COUNT(DISTINCT pa.UserId)
         FROM ProjectAttendance pa
         JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
         JOIN Projects           p ON ps.ProjectId = p.ProjectId
         JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
         JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId
           AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
           AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ) AS ActiveVolunteers,

        ROUND(CASE
            WHEN (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                  AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0) = 0 THEN 0
            ELSE (SELECT COUNT(DISTINCT pa.UserId)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW()))
                 * 100.0
                 / (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                    AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0)
        END, 1) AS ActiveRatePct,

        COALESCE((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        -- FIX: was StatusLkpId = v_ActiveProjectStatusId (ACTIVE only).
        -- Now counts ACTIVE + UPCOMING, but excludes expired projects (treated as cancelled).
        -- DB status is never auto-transitioned (Hangfire not yet wired), so projects
        -- remain UPCOMING/ACTIVE past their end date. Expiry is checked using the
        -- same date fields that the mobile isProjectExpired() helper checks:
        --   ONE_TIME  → OneTimeDate < CURDATE()
        --   RECURRING → RecurEnd    < CURDATE()
        --   FLEXIBLE  → FlexToDate  < CURDATE()
        -- Projects with no end date set are treated as not expired.
        (SELECT COUNT(*) FROM Projects p
         JOIN LookupValues lv ON p.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
           AND lt.TypeCode = 'PROJECT_STATUS'
           AND lv.ValueCode IN ('ACTIVE', 'UPCOMING')
           AND NOT (
               (p.OneTimeDate IS NOT NULL AND p.OneTimeDate < CURDATE())
            OR (p.RecurEnd    IS NOT NULL AND p.RecurEnd    < CURDATE())
            OR (p.FlexToDate  IS NOT NULL AND p.FlexToDate  < CURDATE())
           )
        ) AS ActiveProjects,

        (SELECT COUNT(*)
         FROM OrgMembershipRequests mr
         JOIN LookupValues lv ON mr.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE mr.OrgId = p_OrgId AND mr.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingApplications,

        (SELECT COUNT(*)
         FROM ProjectApplications pa
         JOIN Projects    p  ON pa.ProjectId = p.ProjectId
         JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND pa.IsDeleted = 0
           AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingProjectApplications,

        (SELECT FollowerCount FROM Organisations WHERE OrgId = p_OrgId) AS FollowerCount;
END //

DELIMITER ;

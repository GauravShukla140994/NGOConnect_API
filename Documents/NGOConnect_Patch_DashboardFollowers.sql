-- ══════════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Org_GetDashboard + FollowerCount KPI
-- Date   : 2026-07-12
-- Author : NGO Connect Dev
-- Scope  : 1 SP updated
-- Run on : Railway staging → verify → Railway production
-- ══════════════════════════════════════════════════════════════════════════════
--
-- Change:
--   Org_GetDashboard now returns FollowerCount (denormalized from
--   Organisations.FollowerCount) so the NGO Admin Dashboard screen can
--   display the follower count as a KPI card.
--
-- Prerequisite:
--   NGOConnect_Patch_OrgFollow.sql must already be applied (adds
--   Organisations.FollowerCount column and OrgFollowers table).
--
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetDashboard //
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedMemberStatusId INT UNSIGNED;
    DECLARE v_ActiveProjectStatusId  INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveProjectStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

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

        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveProjectStatusId AND IsDeleted = 0
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

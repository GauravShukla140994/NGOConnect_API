-- ============================================================
-- NGO Connect — Patch: Org_GetDashboard — Correct Pending Counts + Schema Fixes
-- Version : v4.3 patch (rev 4)
-- Date    : 2026-07-07
-- Fixes   :
--   1. PendingApplications — inline JOIN on OrgMembershipRequests (not OrgMembers)
--   2. PendingProjectApplications — added (was missing entirely)
--   3. ActiveVolunteers / ActiveRatePct / VolunteerHoursMonth —
--      ProjectAttendance has NO pa.ProjectId (route via ProjectSessions),
--      NO pa.AttendanceStatus (use AttendStatusLkpId + inline JOIN),
--      NO pa.MarkedAt (use pa.CreatedAt)
-- Apply   : Run against NGOConnect database.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetDashboard //
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedMemberStatusId INT UNSIGNED;
    DECLARE v_ActiveProjectStatusId  INT UNSIGNED;

    -- Lookup: APPROVED member
    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Lookup: ACTIVE project
    SELECT lv.LookupValueId INTO v_ActiveProjectStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT
        -- KPI: Total approved members
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
        ) AS TotalMembers,

        -- KPI: New members this calendar month (JoinedAt, not CreatedAt)
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
           AND YEAR(JoinedAt) = YEAR(NOW()) AND MONTH(JoinedAt) = MONTH(NOW())
        ) AS NewMembersThisMonth,

        -- KPI: Unique volunteers who attended at least one session this month.
        -- ProjectAttendance has no ProjectId column — route through ProjectSessions.
        -- AttendanceStatus column does not exist — JOIN through AttendStatusLkpId.
        -- MarkedAt column does not exist — use CreatedAt (check-in timestamp).
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

        -- KPI: Active rate % (active volunteers / total approved members * 100)
        ROUND(
            CASE
                WHEN (SELECT COUNT(*) FROM OrgMembers
                      WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0) = 0
                THEN 0
                ELSE
                    (SELECT COUNT(DISTINCT pa.UserId)
                     FROM ProjectAttendance pa
                     JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                     JOIN Projects           p ON ps.ProjectId = p.ProjectId
                     JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                     JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                     WHERE p.OrgId = p_OrgId
                       AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                       AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW()))
                    * 100.0
                    / (SELECT COUNT(*) FROM OrgMembers
                       WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0)
            END, 1
        ) AS ActiveRatePct,

        -- KPI: Volunteer hours this month (sum of session durations for attended check-ins)
        COALESCE((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM ProjectAttendance pa
            JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
            JOIN Projects           p ON ps.ProjectId = p.ProjectId
            JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
            JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE p.OrgId = p_OrgId
              AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
              AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        -- KPI: Active projects
        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveProjectStatusId AND IsDeleted = 0
        ) AS ActiveProjects,

        -- Pending Actions: member join requests
        -- OrgMembershipRequests holds PENDING requests; OrgMembers only holds APPROVED.
        -- Use inline JOIN (not DECLARE+SELECT INTO) — avoids NULL variable bug.
        (SELECT COUNT(*)
         FROM OrgMembershipRequests mr
         JOIN LookupValues lv ON mr.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE mr.OrgId = p_OrgId AND mr.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingApplications,

        -- Pending Actions: volunteer project applications
        (SELECT COUNT(*)
         FROM ProjectApplications pa
         JOIN Projects    p  ON pa.ProjectId = p.ProjectId
         JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND pa.IsDeleted = 0
           AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingProjectApplications;
END //

DELIMITER ;

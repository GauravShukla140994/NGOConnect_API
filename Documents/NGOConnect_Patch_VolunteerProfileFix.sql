-- ══════════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Org_GetVolunteerProfile fix
-- Date   : 2026-07-12
-- Scope  : 1 SP updated
-- Run on : Railway staging → verify → Railway production
-- ══════════════════════════════════════════════════════════════════════════════
--
-- Fixes in Org_GetVolunteerProfile:
--   1. AttendanceStatus column does not exist → use AttendStatusLkpId via
--      declared LookupValueId variables (same pattern as Org_GetDashboard)
--   2. pa.ProjectId does not exist on ProjectAttendance →
--      route through ProjectSessions (pa → ps → Projects)
--   3. ReliabilityPct inline FROM subquery used AttendanceStatus string →
--      rewritten as single HAVING aggregate using v_AttendedLkpId/v_ExcusedLkpId
--
-- NOTE: p_ReviewNote param mismatch (Org_ReviewMembership) is a C# DAL fix only
--       — the SP itself is correct. No SQL change needed for that bug.
--
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetVolunteerProfile //
CREATE PROCEDURE Org_GetVolunteerProfile(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_ExcusedLkpId  INT UNSIGNED;
    DECLARE v_NoShowLkpId   INT UNSIGNED;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_ExcusedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'EXCUSED' LIMIT 1;

    SELECT LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.City, up.State, up.Occupation, up.ProfilePhoto, up.Bio, up.VolunteerExp,
        IFNULL((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT ps.ProjectId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                JOIN Projects p ON ps.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS OrgCount,
        ROUND(IFNULL((SELECT SUM(CASE WHEN pa.AttendStatusLkpId IN (v_AttendedLkpId, v_ExcusedLkpId) THEN 1 ELSE 0 END)
                            / COUNT(*) * 100
                      FROM ProjectAttendance pa
                      WHERE pa.UserId = p_UserId
                      HAVING COUNT(*) > 0), 100), 2) AS ReliabilityPct,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_NoShowLkpId), 0) AS NoShowCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_ExcusedLkpId), 0) AS ExcusedCount,
        IFNULL((SELECT COUNT(*) FROM PostReports pr JOIN Posts po ON pr.PostId = po.PostId WHERE po.UserId = p_UserId), 0) AS ComplaintCount,
        lv_role.ValueCode AS RoleCode, lv_role.ValueName AS RoleName,
        lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
        om.CreatedAt AS JoinedAt,
        mr.PrevNgoExperience, mr.VolunteerSkills, mr.AreasOfInterest, mr.WhyJoin,
        mr.CreatedAt AS RequestedAt
    FROM Users u
    JOIN  UserProfiles     up       ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om       ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role   ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT JOIN LookupValues lv_status ON lv_status.LookupValueId = om.StatusLkpId
    LEFT JOIN OrgMembershipRequests mr ON mr.RequestId = (
        SELECT RequestId FROM OrgMembershipRequests
        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0
        ORDER BY CreatedAt DESC LIMIT 1
    )
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

DELIMITER ;

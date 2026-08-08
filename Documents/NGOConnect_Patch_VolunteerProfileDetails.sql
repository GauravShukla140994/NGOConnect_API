-- ============================================================
-- NGO CONNECT — PATCH: Org_GetVolunteerProfile membership details
-- Date    : 2026-07-08
-- Changes : Adds Bio, VolunteerExp, State from UserProfiles
--           Adds PrevNgoExperience, VolunteerSkills, AreasOfInterest,
--           WhyJoin, RequestedAt from OrgMembershipRequests (most recent request).
-- ============================================================

USE ngoconnect;

DROP PROCEDURE IF EXISTS Org_GetVolunteerProfile;

DELIMITER //

CREATE PROCEDURE Org_GetVolunteerProfile(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.City,
        up.State,
        up.Occupation,
        up.ProfilePhoto,
        up.Bio,
        up.VolunteerExp,

        -- ── Impact stats ──────────────────────────────────────────────────────
        IFNULL((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM   ProjectAttendance pa
            JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
            WHERE  pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'
        ), 0) AS TotalHours,

        IFNULL((
            SELECT COUNT(DISTINCT pa.ProjectId)
            FROM   ProjectAttendance pa
            WHERE  pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'
        ), 0) AS ProjectCount,

        IFNULL((
            SELECT COUNT(DISTINCT p.OrgId)
            FROM   ProjectAttendance pa
            JOIN   Projects p ON pa.ProjectId = p.ProjectId
            WHERE  pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'
        ), 0) AS OrgCount,

        -- ── Reliability (admin-only) ──────────────────────────────────────────
        ROUND(IFNULL((
            SELECT attended / total * 100
            FROM (
                SELECT
                    SUM(CASE WHEN AttendanceStatus IN ('ATTENDED','EXCUSED') THEN 1 ELSE 0 END) AS attended,
                    COUNT(*) AS total
                FROM ProjectAttendance
                WHERE UserId = p_UserId
            ) r
            WHERE total > 0
        ), 100), 2) AS ReliabilityPct,

        IFNULL((
            SELECT AVG(usr.RatingValue)
            FROM   UserSkillRatings usr
            JOIN   ProjectSkills    ps2 ON usr.ProjectSkillId = ps2.ProjectSkillId
            JOIN   Projects         p2  ON ps2.ProjectId = p2.ProjectId
            WHERE  usr.RatedUserId = p_UserId AND p2.OrgId = p_OrgId
        ), 0) AS AvgRating,

        IFNULL((
            SELECT COUNT(*)
            FROM   ProjectAttendance
            WHERE  UserId = p_UserId AND AttendanceStatus = 'NO_SHOW'
        ), 0) AS NoShowCount,

        IFNULL((
            SELECT COUNT(*)
            FROM   ProjectAttendance
            WHERE  UserId = p_UserId AND AttendanceStatus = 'EXCUSED'
        ), 0) AS ExcusedCount,

        IFNULL((
            SELECT COUNT(*)
            FROM   PostReports pr
            JOIN   Posts po ON pr.PostId = po.PostId
            WHERE  po.UserId = p_UserId
        ), 0) AS ComplaintCount,

        -- ── Membership in this org ────────────────────────────────────────────
        lv_role.ValueCode   AS RoleCode,
        lv_role.ValueName   AS RoleName,
        lv_status.ValueCode AS StatusCode,
        lv_status.ValueName AS StatusName,
        om.CreatedAt        AS JoinedAt,

        -- ── Membership request fields (most recent request for this org) ──────
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.WhyJoin,
        mr.CreatedAt        AS RequestedAt

    FROM Users u
    JOIN  UserProfiles     up         ON up.UserId  = u.UserId  AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om         ON om.OrgId   = p_OrgId   AND om.UserId    = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role    ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT JOIN LookupValues lv_status  ON lv_status.LookupValueId = om.StatusLkpId
    LEFT JOIN OrgMembershipRequests mr ON mr.RequestId = (
        SELECT RequestId
        FROM   OrgMembershipRequests
        WHERE  OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0
        ORDER  BY CreatedAt DESC
        LIMIT  1
    )
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

DELIMITER ;

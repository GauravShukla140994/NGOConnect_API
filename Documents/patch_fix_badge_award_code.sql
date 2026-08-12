-- ── patch_fix_badge_award_code.sql ───────────────────────────────────────────
-- Change : UserBadge_Award SP accepts p_BadgeCode VARCHAR(50) (ValueCode string)
--          instead of p_BadgeLkpId INT UNSIGNED.
--          The SP now resolves the LookupValueId internally from BADGE_TYPE.
--
-- Why    : Mobile BADGE_DEFS uses ValueCode strings (STAR_VOL, TEAM_PLAYER, etc.).
--          Passing a LookupValueId from the client required the client to know DB
--          internal IDs — violates the Core Mandate (Dynamic / Efficient).
--          Accepting the ValueCode string is cleaner and future-proof.
--
-- Impact : OrgDal.AwardBadgeAsync + BadgeDal.AwardAsync updated in same session.
--          No table schema changes. Safe to re-run.
-- Run    : local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS UserBadge_Award //
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId    INT UNSIGNED,
    IN p_BadgeCode VARCHAR(50),
    IN p_AwardedBy INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_ProjectId INT UNSIGNED
)
BEGIN
    DECLARE v_BadgeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_BadgeName  VARCHAR(100) DEFAULT 'Badge';
    DECLARE v_Exists     INT DEFAULT 0;

    -- Resolve LookupValueId from ValueCode
    SELECT lv.LookupValueId INTO v_BadgeLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'BADGE_TYPE' AND lv.ValueCode = p_BadgeCode LIMIT 1;

    IF v_BadgeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Unknown badge code: ', p_BadgeCode) AS Message,
               NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
    ELSE
        -- Prevent double-awarding the same badge on the same project
        SELECT COUNT(*) INTO v_Exists
        FROM   UserBadges
        WHERE  UserId     = p_UserId
          AND  BadgeLkpId = v_BadgeLkpId
          AND  (p_ProjectId IS NULL OR ProjectId = p_ProjectId)
          AND  IsDeleted   = 0;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess,
                   'This badge has already been awarded to this volunteer.' AS Message,
                   NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
        ELSE
            SELECT ValueName INTO v_BadgeName
            FROM   LookupValues WHERE LookupValueId = v_BadgeLkpId LIMIT 1;

            INSERT INTO UserBadges
                (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
            VALUES
                (p_UserId, v_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());

            SELECT 1 AS IsSuccess,
                   'Badge awarded successfully.' AS Message,
                   LAST_INSERT_ID() AS BadgeId,
                   v_BadgeName      AS BadgeName,
                   p_UserId         AS UserId;
        END IF;
    END IF;
END //

DELIMITER ;

-- ── Also add AwardedBadgeCodes to Org_GetVolunteerProfile ────────────────────
-- Allows VolunteerProfileScreen to read fresh badge data from DB on every mount,
-- eliminating the need for any local cache.

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
        mr.CreatedAt AS RequestedAt,
        (SELECT GROUP_CONCAT(DISTINCT lv_b.ValueCode ORDER BY lv_b.ValueCode SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv_b ON ub.BadgeLkpId = lv_b.LookupValueId
         WHERE  ub.UserId = p_UserId AND ub.IsDeleted = 0) AS AwardedBadgeCodes
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

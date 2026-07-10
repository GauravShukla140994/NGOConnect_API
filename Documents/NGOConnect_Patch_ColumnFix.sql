-- ============================================================
-- NGO Connect — Patch: Column Name Fixes
-- Version : v4.3 patch
-- Date    : 2026-07-09
-- Purpose : Fix SP column mismatches vs actual table schema
--
--   1. User_GetBadges  — UserBadges.BadgeType (VARCHAR) not BadgeLkpId (FK)
--                        UserBadges has no ProjectId column
--   2. User_GetImpact  — ProjectAttendance.AttendStatusLkpId (INT FK) not
--                        AttendanceStatus (VARCHAR)
--                        Final SELECT anchored on Users (not UserProfiles)
--                        so the SP always returns a row even if the profile
--                        has not been filled in yet.
--
-- Apply   : Run against NGOConnect database. Safe to re-run (DROP IF EXISTS).
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. User_GetBadges
--    Actual schema:  UserBadges.BadgeType VARCHAR(50)  — no BadgeLkpId FK
--                    UserBadges has no ProjectId column
--    C# compat:      Returns BadgeLkpId = 0 (satisfies Col<int> in DAL)
--                    BadgeCode = BadgeType, BadgeName = BadgeType
-- ─────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_GetBadges //
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        0              AS BadgeLkpId,   -- no FK column; 0 satisfies DAL Col<int>
        ub.BadgeType   AS BadgeName,
        ub.BadgeType   AS BadgeCode,
        o.OrgName,
        NULL           AS ProjectName,  -- no ProjectId in UserBadges table
        ub.AwardedAt
    FROM  UserBadges ub
    LEFT  JOIN Organisations o ON ub.OrgId = o.OrgId
    WHERE ub.UserId    = p_UserId
      AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;
END //


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. User_GetImpact (full rebuild)
--    Fixes vs NGOConnect_Patch_ImpactSPs.sql:
--      a) All 6 occurrences of pa.AttendanceStatus replaced with
--         pa.AttendStatusLkpId compared against declared LookupValueId vars
--      b) Final SELECT anchored on Users LEFT JOIN UserProfiles so the SP
--         always returns exactly one row (fixes "Volunteer" name bug when
--         UserProfiles row has not been created yet)
-- ─────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_GetImpact //
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalMinutes      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_TotalHours        DECIMAL(8,2)  DEFAULT 0;
    DECLARE v_ProjCompleted     INT           DEFAULT 0;
    DECLARE v_NgosJoined        INT           DEFAULT 0;
    DECLARE v_CertCount         INT           DEFAULT 0;
    DECLARE v_BadgeCount        INT           DEFAULT 0;
    DECLARE v_SkillCount        INT           DEFAULT 0;
    DECLARE v_NoShows           INT           DEFAULT 0;
    DECLARE v_Withdrawals       INT           DEFAULT 0;
    DECLARE v_ImpactScore       INT           DEFAULT 0;
    DECLARE v_Attended          INT           DEFAULT 0;
    DECLARE v_TotalSessions     INT           DEFAULT 0;
    DECLARE v_ReliabilityPct    DECIMAL(5,2)  DEFAULT 0;
    DECLARE v_ProjApplied       INT           DEFAULT 0;
    DECLARE v_PendingApps       INT           DEFAULT 0;
    DECLARE v_ApprovedApps      INT           DEFAULT 0;
    DECLARE v_RankNumber        INT           DEFAULT 1;
    DECLARE v_TotalRanked       INT           DEFAULT 0;
    DECLARE v_AttStatusAttended INT UNSIGNED  DEFAULT 0;
    DECLARE v_AttStatusNoShow   INT UNSIGNED  DEFAULT 0;

    -- 0. Resolve attendance status LookupValueIds (avoids string comparisons in every step)
    SELECT LookupValueId INTO v_AttStatusAttended
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
    LIMIT  1;

    SELECT LookupValueId INTO v_AttStatusNoShow
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW'
    LIMIT  1;

    -- 1. Total volunteer hours (attended sessions only)
    SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)), 0)
    INTO   v_TotalMinutes
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;
    SET v_TotalHours = ROUND(v_TotalMinutes / 60.0, 1);

    -- 2. Projects completed (at least one attended session in a COMPLETED/EXPIRED project)
    --    ProjectAttendance has no ProjectId — must go through ProjectSessions
    SELECT COUNT(DISTINCT ps.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId  = ps.SessionId
    JOIN   Projects        p  ON ps.ProjectId  = p.ProjectId
    JOIN   LookupValues    lv ON p.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId
      AND  pa.AttendStatusLkpId = v_AttStatusAttended
      AND  lv.ValueCode IN ('COMPLETED', 'EXPIRED');

    -- 3. NGOs joined (APPROVED membership)
    SELECT COUNT(*)
    INTO   v_NgosJoined
    FROM   OrgMembers   om
    JOIN   LookupValues lv ON om.StatusLkpId = lv.LookupValueId
    WHERE  om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    -- 4. Certificates
    SELECT COUNT(*) INTO v_CertCount
    FROM   VolunteerCertificates WHERE UserId = p_UserId;   -- no IsDeleted column on this table

    -- 5. Badges
    SELECT COUNT(*) INTO v_BadgeCount
    FROM   UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;

    -- 6. Skills
    SELECT COUNT(*) INTO v_SkillCount
    FROM   UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;

    -- 7. Unexcused no-shows
    SELECT COUNT(*) INTO v_NoShows
    FROM   ProjectAttendance
    WHERE  UserId = p_UserId
      AND  AttendStatusLkpId = v_AttStatusNoShow
      AND  IsNoShowExcused   = 0;

    -- 8. Rejected / withdrawn applications
    SELECT COUNT(*) INTO v_Withdrawals
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND  lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

    -- 9. Impact Score formula
    --    Points:     Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5
    --    Deductions: NoShows×20 + Withdrawals×15
    --    Floor: 0
    SET v_ImpactScore = GREATEST(0, ROUND(
        (v_TotalHours    * 10
         + v_ProjCompleted * 50
         + v_NgosJoined    * 30
         + v_CertCount     * 25
         + v_BadgeCount    * 15
         + v_SkillCount    * 5)
        - (v_NoShows * 20 + v_Withdrawals * 15)
    ));

    -- 10. Reliability % (attended / (attended + no-show) × 100)
    SELECT
        SUM(CASE WHEN AttendStatusLkpId = v_AttStatusAttended                       THEN 1 ELSE 0 END),
        SUM(CASE WHEN AttendStatusLkpId IN (v_AttStatusAttended, v_AttStatusNoShow) THEN 1 ELSE 0 END)
    INTO v_Attended, v_TotalSessions
    FROM ProjectAttendance WHERE UserId = p_UserId;

    IF COALESCE(v_TotalSessions, 0) > 0 THEN
        SET v_ReliabilityPct = ROUND(COALESCE(v_Attended, 0) * 100.0 / v_TotalSessions, 1);
    END IF;

    -- 11. Application counts
    SELECT COUNT(*) INTO v_ProjApplied
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_PendingApps
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'PENDING';

    SELECT COUNT(*) INTO v_ApprovedApps
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    -- 12. Rank position
    SELECT COUNT(*) + 1 INTO v_RankNumber
    FROM   UserProfiles up2
    JOIN   Users u2 ON up2.UserId = u2.UserId
    WHERE  up2.ImpactScore > v_ImpactScore AND u2.IsDeleted = 0;

    SELECT COUNT(*) INTO v_TotalRanked
    FROM   UserProfiles up2
    JOIN   Users u2 ON up2.UserId = u2.UserId
    WHERE  u2.IsDeleted = 0 AND up2.ImpactScore > 0;

    -- 13. Return full result set
    --     Anchored on Users (not UserProfiles) so we always get a row even
    --     when UserProfiles has not been created yet for this user.
    SELECT
        v_ImpactScore     AS ImpactScore,
        v_ReliabilityPct  AS ReliabilityPct,
        v_ProjCompleted   AS ProjectsCompleted,
        v_TotalHours      AS TotalHours,
        v_BadgeCount      AS BadgeCount,
        v_SkillCount      AS SkillCount,
        v_ProjApplied     AS ProjectsApplied,
        v_CertCount       AS CertificateCount,
        COALESCE(up.CreatedAt, u.CreatedAt) AS MemberSince,
        v_NgosJoined      AS NgosJoined,
        v_PendingApps     AS PendingApplications,
        v_ApprovedApps    AS ApprovedApplications,
        v_RankNumber      AS RankNumber,
        v_TotalRanked     AS TotalRanked,
        CASE
            WHEN v_ImpactScore >= 20000 THEN 'Elite'
            WHEN v_ImpactScore >= 10000 THEN 'Diamond'
            WHEN v_ImpactScore >= 5000  THEN 'Platinum'
            WHEN v_ImpactScore >= 2500  THEN 'Gold'
            WHEN v_ImpactScore >= 1500  THEN 'Committed Volunteer'
            WHEN v_ImpactScore >= 500   THEN 'Active Volunteer'
            WHEN v_ImpactScore >= 100   THEN 'Helper'
            ELSE                             'Newcomer'
        END               AS RankName,
        up.FirstName,
        up.LastName,
        up.ProfilePhoto,
        up.Bio
    FROM  Users u
    LEFT  JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    WHERE u.UserId    = p_UserId
      AND u.IsDeleted = 0;
END //


DELIMITER ;

-- ══════════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Profile Stats Sync  (v4.9)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- Problem fixed
-- ─────────────
-- Profile screen showed Hours = 0, Projects = 0 because User_GetProfile did not
-- return TotalHours / ProjectsCount.  NGOs count was wrong (included pending
-- memberships, not just approved).  ImpactScore on Profile was stale because
-- User_GetImpact computed the score fresh but never wrote it back.
--
-- Changes in this patch
-- ─────────────────────
-- 1. User_GetProfile  — adds TotalHours, ProjectsCount, NgosJoined subqueries
--                       (identical logic to User_GetImpact).
-- 2. User_GetImpact   — adds UPDATE UserProfiles SET ImpactScore = v_ImpactScore
--                       so the stored column stays in sync.
--
-- Apply order: run this file once on local DB, then on Railway staging/production.
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── 1. User_GetProfile ───────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_GetProfile //

-- v4.9: added TotalHours, ProjectsCount, NgosJoined so Profile screen stats
--       match Impact screen (same subquery logic as User_GetImpact).
CREATE PROCEDURE User_GetProfile(IN p_UserId INT UNSIGNED, IN p_RequestingUserId INT UNSIGNED)
BEGIN
    SELECT
        u.UserId, u.Mobile, u.Email, u.CountryCode, u.IsVerified,
        up.FirstName, up.LastName, up.Bio, up.ProfilePhoto,
        up.DateOfBirth, up.Occupation, up.Organisation, up.VolunteerExp,
        up.GenderLkpId,
        gv.ValueName AS Gender,    gv.ValueCode AS GenderCode,
        up.EducationLkpId,
        ev.ValueName AS Education, ev.ValueCode AS EducationCode,
        up.FieldOfStudy,
        up.WorkExpLkpId,
        wv.ValueName AS WorkExperience, wv.ValueCode AS WorkExpCode,
        up.AddressLine1, up.AddressLine2, up.City, up.State, up.Pincode, up.Country,
        up.ImpactScore, up.ReliabilityPct,
        u.CreatedAt AS MemberSince,
        up.UpdatedAt,
        CASE
            WHEN up.FirstName IS NOT NULL AND TRIM(up.FirstName) != ''
             AND up.LastName  IS NOT NULL AND TRIM(up.LastName)  != ''
            THEN 1 ELSE 0
        END AS IsProfileComplete,
        -- ── Impact stats (same logic as User_GetImpact) ──────────────────────
        ROUND(IFNULL((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps  ON pa2.SessionId         = ps.SessionId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId      = lta.LookupTypeId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
        ), 0), 1) AS TotalHours,
        IFNULL((
            SELECT COUNT(DISTINCT ps2.ProjectId)
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps2 ON pa2.SessionId         = ps2.SessionId
            JOIN   Projects          pr  ON ps2.ProjectId         = pr.ProjectId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId      = lta.LookupTypeId
            JOIN   LookupValues      lpv ON pr.StatusLkpId        = lpv.LookupValueId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
              AND  lpv.ValueCode IN ('COMPLETED', 'EXPIRED')
        ), 0) AS ProjectsCount,
        IFNULL((
            SELECT COUNT(*)
            FROM   OrgMembers   om2
            JOIN   LookupValues lvo ON om2.StatusLkpId = lvo.LookupValueId
            WHERE  om2.UserId = p_UserId AND om2.IsDeleted = 0
              AND  lvo.ValueCode = 'APPROVED'
        ), 0) AS NgosJoined
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues gv ON up.GenderLkpId    = gv.LookupValueId
    LEFT JOIN LookupValues ev ON up.EducationLkpId = ev.LookupValueId
    LEFT JOIN LookupValues wv ON up.WorkExpLkpId   = wv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //


-- ── 2. User_GetImpact ────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_GetImpact //

-- v4.9: added UPDATE UserProfiles SET ImpactScore = v_ImpactScore so the
--       stored column (read by User_GetProfile) stays in sync with the live
--       computed value.
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

    SELECT LookupValueId INTO v_AttStatusAttended
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_AttStatusNoShow
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)), 0)
    INTO   v_TotalMinutes
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;
    SET v_TotalHours = ROUND(v_TotalMinutes / 60.0, 1);

    SELECT COUNT(DISTINCT ps.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId  = ps.SessionId
    JOIN   Projects        p  ON ps.ProjectId  = p.ProjectId
    JOIN   LookupValues    lv ON p.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId
      AND  pa.AttendStatusLkpId = v_AttStatusAttended
      AND  lv.ValueCode IN ('COMPLETED', 'EXPIRED');

    SELECT COUNT(*) INTO v_NgosJoined
    FROM   OrgMembers   om JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
    WHERE  om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    SELECT COUNT(*) INTO v_CertCount FROM VolunteerCertificates WHERE UserId = p_UserId;
    SELECT COUNT(*) INTO v_BadgeCount FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;
    SELECT COUNT(*) INTO v_SkillCount FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_NoShows FROM ProjectAttendance
    WHERE  UserId = p_UserId AND AttendStatusLkpId = v_AttStatusNoShow AND IsNoShowExcused = 0;

    SELECT COUNT(*) INTO v_Withdrawals
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

    SET v_ImpactScore = GREATEST(0, ROUND(
        (v_TotalHours * 10 + v_ProjCompleted * 50 + v_NgosJoined * 30
         + v_CertCount * 25 + v_BadgeCount * 15 + v_SkillCount * 5)
        - (v_NoShows * 20 + v_Withdrawals * 15)
    ));

    -- Write computed score back so User_GetProfile (and any caller reading the
    -- stored column) always sees an up-to-date value.
    UPDATE UserProfiles
    SET    ImpactScore = v_ImpactScore
    WHERE  UserId = p_UserId AND IsDeleted = 0;

    SELECT
        SUM(CASE WHEN AttendStatusLkpId = v_AttStatusAttended THEN 1 ELSE 0 END),
        SUM(CASE WHEN AttendStatusLkpId IN (v_AttStatusAttended, v_AttStatusNoShow) THEN 1 ELSE 0 END)
    INTO v_Attended, v_TotalSessions
    FROM ProjectAttendance WHERE UserId = p_UserId;

    IF COALESCE(v_TotalSessions, 0) > 0 THEN
        SET v_ReliabilityPct = ROUND(COALESCE(v_Attended, 0) * 100.0 / v_TotalSessions, 1);
    END IF;

    SELECT COUNT(*) INTO v_ProjApplied FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_PendingApps
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'PENDING';

    SELECT COUNT(*) INTO v_ApprovedApps
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    SELECT COUNT(*) + 1 INTO v_RankNumber
    FROM   UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId
    WHERE  up2.ImpactScore > v_ImpactScore
      AND  u2.IsDeleted = 0 AND up2.IsDeleted = 0;

    SELECT COUNT(*) INTO v_TotalRanked
    FROM   UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId
    WHERE  u2.IsDeleted = 0 AND up2.IsDeleted = 0;

    SELECT
        v_ImpactScore    AS ImpactScore,
        v_ReliabilityPct AS ReliabilityPct,
        v_ProjCompleted  AS ProjectsCompleted,
        v_TotalHours     AS TotalHours,
        v_BadgeCount     AS BadgeCount,
        v_SkillCount     AS SkillCount,
        v_ProjApplied    AS ProjectsApplied,
        v_CertCount      AS CertificateCount,
        COALESCE(up.CreatedAt, u.CreatedAt) AS MemberSince,
        v_NgosJoined     AS NgosJoined,
        v_PendingApps    AS PendingApplications,
        v_ApprovedApps   AS ApprovedApplications,
        v_RankNumber     AS RankNumber,
        v_TotalRanked    AS TotalRanked,
        CASE
            WHEN v_ImpactScore >= 20000 THEN 'Elite'
            WHEN v_ImpactScore >= 10000 THEN 'Diamond'
            WHEN v_ImpactScore >= 5000  THEN 'Platinum'
            WHEN v_ImpactScore >= 2500  THEN 'Gold'
            WHEN v_ImpactScore >= 1500  THEN 'Committed Volunteer'
            WHEN v_ImpactScore >= 500   THEN 'Active Volunteer'
            WHEN v_ImpactScore >= 100   THEN 'Helper'
            ELSE                             'Newcomer'
        END              AS RankName,
        up.FirstName,
        up.LastName,
        up.ProfilePhoto,
        up.ReliabilityPct AS ReliabilityPctStored
    FROM   UserProfiles up
    JOIN   Users        u  ON up.UserId = u.UserId
    WHERE  up.UserId = p_UserId AND up.IsDeleted = 0;
END //

DELIMITER ;

-- CALL User_GetProfile(1, 1);
-- CALL User_GetImpact(1);

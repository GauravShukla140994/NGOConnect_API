-- ============================================================
-- NGO Connect — Patch: Impact Screen SPs
-- Version : v4.3 patch
-- Date    : 2026-07-07
-- Purpose : Rebuild User_GetImpact (full fields + inline score calc)
--           Rebuild Application_GetByUser (schedule/location/project status)
-- Apply   : Run against NGOConnect database BEFORE running the app.
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. User_GetImpact — Full rebuild
--    Calculates ImpactScore inline from attendance, projects, NGOs, etc.
--    Returns: score, rank, profile info, application counts, reliability %
-- ─────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_GetImpact //
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalMinutes    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_TotalHours      DECIMAL(8,2)  DEFAULT 0;
    DECLARE v_ProjCompleted   INT           DEFAULT 0;
    DECLARE v_NgosJoined      INT           DEFAULT 0;
    DECLARE v_CertCount       INT           DEFAULT 0;
    DECLARE v_BadgeCount      INT           DEFAULT 0;
    DECLARE v_SkillCount      INT           DEFAULT 0;
    DECLARE v_NoShows         INT           DEFAULT 0;
    DECLARE v_Withdrawals     INT           DEFAULT 0;
    DECLARE v_ImpactScore     INT           DEFAULT 0;
    DECLARE v_Attended        INT           DEFAULT 0;
    DECLARE v_TotalSessions   INT           DEFAULT 0;
    DECLARE v_ReliabilityPct  DECIMAL(5,2)  DEFAULT 0;
    DECLARE v_ProjApplied     INT           DEFAULT 0;
    DECLARE v_PendingApps     INT           DEFAULT 0;
    DECLARE v_ApprovedApps    INT           DEFAULT 0;
    DECLARE v_RankNumber      INT           DEFAULT 1;
    DECLARE v_TotalRanked     INT           DEFAULT 0;

    -- 1. Total volunteer hours (attended sessions only)
    SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)), 0)
    INTO   v_TotalMinutes
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED';
    SET v_TotalHours = ROUND(v_TotalMinutes / 60.0, 1);

    -- 2. Projects completed (at least one attended session in a COMPLETED/EXPIRED project)
    SELECT COUNT(DISTINCT pa.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectAttendance pa
    JOIN   Projects p   ON pa.ProjectId = p.ProjectId
    JOIN   LookupValues lv ON p.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId
      AND  pa.AttendanceStatus = 'ATTENDED'
      AND  lv.ValueCode IN ('COMPLETED', 'EXPIRED');

    -- 3. NGOs joined (APPROVED membership)
    SELECT COUNT(*)
    INTO   v_NgosJoined
    FROM   OrgMembers om
    JOIN   LookupValues lv ON om.StatusLkpId = lv.LookupValueId
    WHERE  om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    -- 4. Certificates
    SELECT COUNT(*) INTO v_CertCount
    FROM   VolunteerCertificates WHERE UserId = p_UserId AND IsDeleted = 0;

    -- 5. Badges
    SELECT COUNT(*) INTO v_BadgeCount
    FROM   UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;

    -- 6. Skills
    SELECT COUNT(*) INTO v_SkillCount
    FROM   UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;

    -- 7. Unexcused no-shows (deduction trigger)
    SELECT COUNT(*) INTO v_NoShows
    FROM   ProjectAttendance
    WHERE  UserId = p_UserId
      AND  AttendanceStatus = 'NO_SHOW'
      AND  IsNoShowExcused = 0;

    -- 8. Rejected applications (withdrawal/rejection deduction)
    SELECT COUNT(*) INTO v_Withdrawals
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND  lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

    -- 9. Impact Score formula
    --    Points: Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5
    --    Deductions: NoShows×20 + Withdrawals×15
    --    Floor: 0
    SET v_ImpactScore = GREATEST(0, ROUND(
        (v_TotalHours * 10
         + v_ProjCompleted * 50
         + v_NgosJoined   * 30
         + v_CertCount    * 25
         + v_BadgeCount   * 15
         + v_SkillCount   * 5)
        - (v_NoShows * 20 + v_Withdrawals * 15)
    ));

    -- 10. Reliability % (attended / (attended + no-show) × 100)
    SELECT
        SUM(CASE WHEN AttendanceStatus = 'ATTENDED'               THEN 1 ELSE 0 END),
        SUM(CASE WHEN AttendanceStatus IN ('ATTENDED', 'NO_SHOW') THEN 1 ELSE 0 END)
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

    -- 12. Rank position (uses stored ImpactScore for performance; updated by Hangfire job)
    SELECT COUNT(*) + 1 INTO v_RankNumber
    FROM   UserProfiles up2
    JOIN   Users u2 ON up2.UserId = u2.UserId
    WHERE  up2.ImpactScore > v_ImpactScore AND u2.IsDeleted = 0;

    SELECT COUNT(*) INTO v_TotalRanked
    FROM   UserProfiles up2
    JOIN   Users u2 ON up2.UserId = u2.UserId
    WHERE  u2.IsDeleted = 0 AND up2.ImpactScore > 0;

    -- 13. Return full result set
    SELECT
        v_ImpactScore    AS ImpactScore,
        v_ReliabilityPct AS ReliabilityPct,
        v_ProjCompleted  AS ProjectsCompleted,
        v_TotalHours     AS TotalHours,
        v_BadgeCount     AS BadgeCount,
        v_SkillCount     AS SkillCount,
        v_ProjApplied    AS ProjectsApplied,
        v_CertCount      AS CertificateCount,
        up.CreatedAt     AS MemberSince,
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
        up.Bio
    FROM   UserProfiles up
    WHERE  up.UserId = p_UserId;
END //


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Application_GetByUser — Full rebuild
--    Adds: OrgLogoUrl, ScheduleTypeCode/Name, RecurStart/End/Days,
--          SessionStartTime/EndTime, Landmark, City,
--          ProjectStatusCode/Name, StatusUpdatedAt
--    Params: p_PageNumber + p_PageSize (default 1 / 200)
-- ─────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT UNSIGNED,
    IN p_PageSize   INT UNSIGNED
)
BEGIN
    DECLARE v_Offset INT DEFAULT 0;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    -- Row result
    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl                   AS OrgLogoUrl,
        -- Application status
        asv.ValueCode               AS StatusCode,
        asv.ValueName               AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        -- Schedule type
        stlv.ValueCode              AS ScheduleTypeCode,
        stlv.ValueName              AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.Landmark,
        p.City,
        -- Project status (for tab routing on mobile)
        pslv.ValueCode              AS ProjectStatusCode,
        pslv.ValueName              AS ProjectStatus
    FROM ProjectApplications pa
    JOIN Projects      p    ON pa.ProjectId   = p.ProjectId
    JOIN Organisations o    ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues asv  ON pa.StatusLkpId      = asv.LookupValueId
    LEFT JOIN LookupValues stlv ON p.ScheduleTypeLkpId = stlv.LookupValueId
    LEFT JOIN LookupValues pslv ON p.StatusLkpId       = pslv.LookupValueId
    WHERE pa.UserId    = p_UserId
      AND pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- Count result (second result set — used when caller wants pagination)
    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications
    WHERE  UserId = p_UserId AND IsDeleted = 0;
END //

DELIMITER ;

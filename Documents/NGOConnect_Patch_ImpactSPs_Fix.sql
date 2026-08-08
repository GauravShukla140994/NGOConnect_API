-- ============================================================
-- NGOConnect Patch: User_GetImpact + Application_GetByUser
-- Date:    2026-07-31
-- Bug:     Impact screen shows 0 ProjectsCompleted and empty
--          Completed tab even after approved projects finish.
--
-- Root cause 1 — User_GetImpact (Railway has old version):
--   Old SP used pa.AttendanceStatus (VARCHAR) which no longer
--   exists on ProjectAttendance (column was replaced by the FK
--   AttendStatusLkpId INT UNSIGNED). Every attendance query
--   returned NULL → ProjectsCompleted always 0.
--   Also: even the fixed SP required explicit ProjectAttendance
--   rows marked ATTENDED — only created when admin manually
--   records per-session attendance, which is often skipped when
--   completing a project. Changed to count APPROVED applications
--   on COMPLETED/EXPIRED projects — far more reliable signal.
--
-- Root cause 2 — Application_GetByUser (Railway has old version):
--   Old SP returned only StatusCode/Status/CreatedAt — no
--   ProjectStatusCode field. Mobile isCompleted filter checked
--   a.projectStatusCode which was undefined → always false →
--   Completed tab always empty.
--
-- Endpoints affected:
--   GET /api/v1/user/impact              (User_GetImpact)
--   GET /api/v1/applications/my          (Application_GetByUser)
--
-- Apply to: Railway Staging, then Railway Production
-- SAFE to re-apply (DROP + CREATE pattern)
-- ============================================================

DELIMITER //

-- ── Fix 1: User_GetImpact ────────────────────────────────────
-- v_ProjCompleted now counts APPROVED applications on COMPLETED/EXPIRED
-- projects instead of requiring explicit ProjectAttendance rows.
-- ImpactScore formula is unchanged.

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

    -- Count projects where user had an APPROVED application AND project is COMPLETED/EXPIRED.
    -- More reliable than requiring explicit ProjectAttendance rows (only created when admin
    -- manually marks per-session attendance — often skipped when completing a project).
    SELECT COUNT(DISTINCT pa.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectApplications pa
    JOIN   Projects        p   ON pa.ProjectId   = p.ProjectId
    JOIN   LookupValues    apv ON pa.StatusLkpId = apv.LookupValueId
    JOIN   LookupValues    prv ON p.StatusLkpId  = prv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
      AND  apv.ValueCode  = 'APPROVED'
      AND  prv.ValueCode IN ('COMPLETED', 'EXPIRED');

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
        up.Bio
    FROM  Users u
    LEFT  JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //


-- ── Fix 2: Application_GetByUser ─────────────────────────────
-- Old Railway version returned no ProjectStatusCode — Completed
-- tab on the mobile Impact screen was always empty.
-- New version adds ProjectStatusCode, ScheduleTypeCode, and all
-- schedule date/time fields needed by the mobile app.

DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        appSv.ValueCode  AS StatusCode,
        appSv.ValueName  AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        ptv.ValueCode    AS ScheduleTypeCode,
        ptv.ValueName    AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.OneTimeDate,
        p.FlexFromDate,
        p.FlexToDate,
        p.Landmark       AS LocationName,
        p.City,
        projSv.ValueCode AS ProjectStatusCode,
        projSv.ValueName AS ProjectStatus
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId   = p.ProjectId
    JOIN   Organisations o     ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId        = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId         = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId    = ptv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //

DELIMITER ;

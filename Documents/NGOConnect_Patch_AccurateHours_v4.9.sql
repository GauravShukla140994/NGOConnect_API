-- ============================================================
-- NGOConnect_Patch_AccurateHours_v4.9.sql
-- Purpose : Fix hours not showing for completed projects
-- Changes :
--   1. ALTER ProjectAttendance.HoursLogged → DECIMAL(6,2)
--      (DECIMAL(4,2) max=99.99, overflows long recurring projects)
--   2. Project_Complete — accurate total hours for RECURRING projects
--      (session_hours × days_per_week × weeks, not just one session)
--   3. User_GetImpact — switch TotalHours from TIMESTAMPDIFF(session)
--      to SUM(att.HoursLogged) so stored per-project values are used
--   4. User_GetImpactSummary RS6 — same fix as #3
--   5. BACKFILL — create sessions + attendance for all COMPLETED
--      projects whose APPROVED volunteers have no ATTENDED record yet
-- Apply order: run top-to-bottom on Railway staging, then production
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- 1. Widen HoursLogged column
-- ─────────────────────────────────────────────────────────────
ALTER TABLE ProjectAttendance
    MODIFY COLUMN HoursLogged DECIMAL(6,2) NULL //

-- ─────────────────────────────────────────────────────────────
-- 2. Project_Complete — accurate hours for all schedule types
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_Complete //
CREATE PROCEDURE Project_Complete(
    IN p_ProjectId        INT UNSIGNED,
    IN p_CompletedBy      INT UNSIGNED,
    IN p_ImpactSummary    TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_CompletedStatusId  INT UNSIGNED;
    DECLARE v_ApprovedLkpId      INT UNSIGNED;
    DECLARE v_AttendedLkpId      INT UNSIGNED;
    DECLARE v_SessionId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionDate        DATE;
    DECLARE v_StartTime          TIME;
    DECLARE v_EndTime            TIME;
    DECLARE v_MaxVol             INT UNSIGNED DEFAULT 0;
    DECLARE v_SessionHours       DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_HoursLogged        DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_TypeCode           VARCHAR(50)  DEFAULT '';
    DECLARE v_RecurStart         DATE         DEFAULT NULL;
    DECLARE v_RecurEnd           DATE         DEFAULT NULL;
    DECLARE v_RecurDays          VARCHAR(50)  DEFAULT NULL;
    DECLARE v_DaysPerWeek        INT          DEFAULT 1;
    DECLARE v_Weeks              INT          DEFAULT 1;

    -- 1. Lookup IDs
    SELECT LookupValueId INTO v_CompletedStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    SELECT LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    -- 2. Mark project COMPLETED
    UPDATE Projects
    SET    StatusLkpId      = v_CompletedStatusId,
           CompletedAt      = NOW(),
           CompletedBy      = p_CompletedBy,
           ImpactSummary    = p_ImpactSummary,
           BeneficiaryCount = p_BeneficiaryCount,
           UpdatedAt        = NOW()
    WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

    -- 3. Load project schedule info
    SELECT
        COALESCE(ptv.ValueCode, 'ONE_TIME'),
        COALESCE(p.SessionStartTime, '09:00:00'),
        COALESCE(p.SessionEndTime,   '17:00:00'),
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        COALESCE(p.MaxVolunteers, 0)
    INTO v_TypeCode, v_StartTime, v_EndTime, v_RecurStart, v_RecurEnd, v_RecurDays, v_MaxVol
    FROM Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    -- 4. Find existing session or auto-create one
    SELECT ps.SessionId, ps.SessionDate, ps.StartTime, ps.EndTime
    INTO   v_SessionId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions ps
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate DESC LIMIT 1;

    IF v_SessionId IS NULL THEN
        SELECT COALESCE(p.OneTimeDate, p.RecurStart, p.FlexFromDate, CURDATE())
        INTO   v_SessionDate
        FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

        INSERT INTO ProjectSessions
            (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, CreatedBy)
        VALUES
            (p_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, p_CompletedBy);

        SET v_SessionId = LAST_INSERT_ID();
    END IF;

    -- 5. Calculate hours per session (minimum 0.5h)
    SET v_SessionHours = GREATEST(
        ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2),
        0.50
    );

    -- 6. Total hours = session_hours × number of scheduled occurrences
    --    For RECURRING: count how many days per week × number of weeks
    --    For ONE_TIME / FLEX: just one session
    IF v_TypeCode = 'RECURRING'
       AND v_RecurStart IS NOT NULL
       AND v_RecurEnd   IS NOT NULL
       AND v_RecurDays  IS NOT NULL
       AND v_RecurDays  <> ''
    THEN
        -- Days per week = comma count + 1  (e.g. "MON,WED,FRI" → 3)
        SET v_DaysPerWeek = LENGTH(v_RecurDays)
                          - LENGTH(REPLACE(v_RecurDays, ',', ''))
                          + 1;
        -- Weeks between start and end (at least 1)
        SET v_Weeks = GREATEST(CEIL(DATEDIFF(v_RecurEnd, v_RecurStart) / 7.0), 1);
        SET v_HoursLogged = LEAST(v_SessionHours * v_DaysPerWeek * v_Weeks, 9999.99);
    ELSE
        SET v_HoursLogged = v_SessionHours;
    END IF;

    -- 7. Bulk-insert ATTENDED records for APPROVED volunteers with no existing ATTENDED record
    INSERT INTO ProjectAttendance
        (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, AdminNote, CreatedBy)
    SELECT
        v_SessionId,
        pa.UserId,
        NOW(),
        v_HoursLogged,
        v_AttendedLkpId,
        'Auto-marked attended on project completion.',
        p_CompletedBy
    FROM ProjectApplications pa
    WHERE pa.ProjectId   = p_ProjectId
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND pa.IsDeleted   = 0
      AND NOT EXISTS (
          SELECT 1
          FROM   ProjectAttendance att2
          JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
          WHERE  att2.UserId              = pa.UserId
            AND  ps2.ProjectId            = p_ProjectId
            AND  att2.AttendStatusLkpId   = v_AttendedLkpId
            AND  ps2.IsDeleted            = 0
      )
    ON DUPLICATE KEY UPDATE
        AttendStatusLkpId = v_AttendedLkpId,
        HoursLogged       = v_HoursLogged,
        AdminNote         = 'Auto-marked attended on project completion.',
        UpdatedAt         = NOW(),
        UpdatedBy         = p_CompletedBy;

    SELECT 1 AS IsSuccess, 'Project marked as completed.' AS Message;
END //

-- ─────────────────────────────────────────────────────────────
-- 3. User_GetImpact — TotalHours from SUM(att.HoursLogged)
--    instead of TIMESTAMPDIFF(session start, end).
--    Reason: Project_Complete stores accurate total hours per
--    volunteer in HoursLogged (including recurring multiplier).
--    Using session TIMESTAMPDIFF only gives one session's worth.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetImpact //
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
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

    -- Sum stored HoursLogged (accurate per-project totals, incl. recurring multiplier)
    SELECT ROUND(COALESCE(SUM(pa.HoursLogged), 0), 1)
    INTO   v_TotalHours
    FROM   ProjectAttendance pa
    WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;

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
    FROM   OrgMembers om JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
    WHERE  om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    SELECT COUNT(*) INTO v_CertCount  FROM VolunteerCertificates WHERE UserId = p_UserId;
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
    WHERE  up2.ImpactScore > v_ImpactScore AND u2.IsDeleted = 0 AND up2.IsDeleted = 0;

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

-- ─────────────────────────────────────────────────────────────
-- 4. User_GetImpactSummary — RS6 block same fix as above
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetImpactSummary //
CREATE PROCEDURE User_GetImpactSummary(
    IN p_UserId     INT UNSIGNED,
    IN p_AppLimit   INT,
    IN p_BadgeLimit INT
)
BEGIN
    DECLARE v_PendingLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_RejectedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_WithdrawnLkpId  INT UNSIGNED DEFAULT 0;
    DECLARE v_UpcomingProjId  INT UNSIGNED DEFAULT 0;
    DECLARE v_ActiveProjId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CompletedProjId INT UNSIGNED DEFAULT 0;
    DECLARE v_ExpiredProjId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CancelledProjId INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_PendingLkpId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'   LIMIT 1;
    SELECT LookupValueId INTO v_ApprovedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'  LIMIT 1;
    SELECT LookupValueId INTO v_RejectedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'REJECTED'  LIMIT 1;
    SELECT LookupValueId INTO v_WithdrawnLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN' LIMIT 1;
    SELECT LookupValueId INTO v_UpcomingProjId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING'   LIMIT 1;
    SELECT LookupValueId INTO v_ActiveProjId    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'     LIMIT 1;
    SELECT LookupValueId INTO v_CompletedProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED'  LIMIT 1;
    SELECT LookupValueId INTO v_ExpiredProjId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'EXPIRED'    LIMIT 1;
    SELECT LookupValueId INTO v_CancelledProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'  LIMIT 1;

    -- RS1: Applied tab
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId = v_PendingLkpId
    ORDER BY pa.CreatedAt DESC LIMIT p_AppLimit;

    -- RS2: Upcoming tab
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId = v_ApprovedLkpId AND p.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId)
    ORDER BY p.RecurStart ASC LIMIT p_AppLimit;

    -- RS3: Completed tab — includes HoursLogged + HasCertificate
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn,
        COALESCE((
            SELECT SUM(ata2.HoursLogged)
            FROM ProjectAttendance ata2
            JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId
            WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId
        ), 0) AS HoursLogged,
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc WHERE vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0), 1, 0) AS HasCertificate
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId) AND p.StatusLkpId = v_CompletedProjId
    ORDER BY pa.StatusUpdatedAt DESC LIMIT p_AppLimit;

    -- RS4: Cancelled tab
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId) OR p.StatusLkpId IN (v_ExpiredProjId, v_CancelledProjId))
    ORDER BY pa.CreatedAt DESC LIMIT p_AppLimit;

    -- RS5: Badges
    SELECT ub.UserBadgeId, ub.BadgeLkpId, lv.ValueName AS BadgeName, lv.ValueCode AS BadgeCode,
           o.OrgName, p.ProjectName, ub.CreatedAt AS AwardedAt
    FROM   UserBadges ub
    JOIN   LookupValues lv    ON ub.BadgeLkpId     = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId      = p.ProjectId
    WHERE  ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC LIMIT p_BadgeLimit;

    -- RS6: Counts
    SELECT
        (SELECT COUNT(*) FROM ProjectApplications pa WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_PendingLkpId) AS TotalApplied,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_ApprovedLkpId AND p2.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId)) AS TotalUpcoming,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId) AND p2.StatusLkpId = v_CompletedProjId) AS TotalCompleted,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId) OR p2.StatusLkpId IN (v_ExpiredProjId, v_CancelledProjId))) AS TotalCancelled,
        (SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0) AS TotalBadges;

    -- RS7: Impact stats — SUM(HoursLogged) instead of TIMESTAMPDIFF
    BEGIN
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

        SELECT LookupValueId INTO v_AttStatusAttended FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;
        SELECT LookupValueId INTO v_AttStatusNoShow   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW'   LIMIT 1;

        -- Use SUM(HoursLogged) — reflects accurate per-project totals
        SELECT ROUND(COALESCE(SUM(pa.HoursLogged), 0), 1)
        INTO   v_TotalHours
        FROM   ProjectAttendance pa
        WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;

        SELECT COUNT(DISTINCT pa.ProjectId) INTO v_ProjCompleted
        FROM ProjectApplications pa JOIN Projects p ON pa.ProjectId = p.ProjectId
        JOIN LookupValues apv ON pa.StatusLkpId = apv.LookupValueId
        JOIN LookupValues prv ON p.StatusLkpId  = prv.LookupValueId
        WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND apv.ValueCode = 'APPROVED' AND prv.ValueCode IN ('COMPLETED', 'EXPIRED');

        SELECT COUNT(*) INTO v_NgosJoined FROM OrgMembers om JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId WHERE om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';
        SELECT COUNT(*) INTO v_CertCount  FROM VolunteerCertificates WHERE UserId = p_UserId;
        SELECT COUNT(*) INTO v_BadgeCount FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_SkillCount FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_NoShows    FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_AttStatusNoShow AND IsNoShowExcused = 0;
        SELECT COUNT(*) INTO v_Withdrawals FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

        SET v_ImpactScore = GREATEST(0, ROUND(
            (v_TotalHours * 10 + v_ProjCompleted * 50 + v_NgosJoined * 30 + v_CertCount * 25 + v_BadgeCount * 15 + v_SkillCount * 5)
            - (v_NoShows * 20 + v_Withdrawals * 15)
        ));

        UPDATE UserProfiles SET ImpactScore = v_ImpactScore WHERE UserId = p_UserId AND IsDeleted = 0;

        SELECT
            SUM(CASE WHEN AttendStatusLkpId = v_AttStatusAttended THEN 1 ELSE 0 END),
            SUM(CASE WHEN AttendStatusLkpId IN (v_AttStatusAttended, v_AttStatusNoShow) THEN 1 ELSE 0 END)
        INTO v_Attended, v_TotalSessions FROM ProjectAttendance WHERE UserId = p_UserId;

        IF COALESCE(v_TotalSessions, 0) > 0 THEN
            SET v_ReliabilityPct = ROUND(COALESCE(v_Attended, 0) * 100.0 / v_TotalSessions, 1);
        END IF;

        SELECT COUNT(*) INTO v_ProjApplied  FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_PendingApps  FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'PENDING';
        SELECT COUNT(*) INTO v_ApprovedApps FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';
        SELECT COUNT(*) + 1 INTO v_RankNumber FROM UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId WHERE up2.ImpactScore > v_ImpactScore AND u2.IsDeleted = 0 AND up2.IsDeleted = 0;
        SELECT COUNT(*) INTO v_TotalRanked FROM UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId WHERE u2.IsDeleted = 0 AND up2.IsDeleted = 0;

        SELECT
            v_ImpactScore AS ImpactScore, v_ReliabilityPct AS ReliabilityPct,
            v_ProjCompleted AS ProjectsCompleted, v_TotalHours AS TotalHours,
            v_BadgeCount AS BadgeCount, v_SkillCount AS SkillCount,
            v_ProjApplied AS ProjectsApplied, v_CertCount AS CertificateCount,
            COALESCE(up.CreatedAt, u.CreatedAt) AS MemberSince,
            v_NgosJoined AS NgosJoined, v_PendingApps AS PendingApplications,
            v_ApprovedApps AS ApprovedApplications, v_RankNumber AS RankNumber,
            v_TotalRanked AS TotalRanked,
            CASE WHEN v_ImpactScore >= 20000 THEN 'Elite'
                 WHEN v_ImpactScore >= 10000 THEN 'Diamond'
                 WHEN v_ImpactScore >= 5000  THEN 'Platinum'
                 WHEN v_ImpactScore >= 2500  THEN 'Gold'
                 WHEN v_ImpactScore >= 1500  THEN 'Committed Volunteer'
                 WHEN v_ImpactScore >= 500   THEN 'Active Volunteer'
                 WHEN v_ImpactScore >= 100   THEN 'Helper'
                 ELSE                             'Newcomer'
            END AS RankName,
            up.FirstName, up.LastName, up.ProfilePhoto, up.Bio
        FROM  Users u
        LEFT  JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
    END;
END //

DELIMITER ;

-- ─────────────────────────────────────────────────────────────
-- 5. BACKFILL — existing COMPLETED projects
--    For every COMPLETED project where an APPROVED volunteer has
--    no ATTENDED ProjectAttendance record:
--      a) Find or create a ProjectSession
--      b) Calculate hours (recurring = session_hrs × days × weeks)
--      c) Insert ATTENDED record
-- This is a one-time data fix for test data completed before
-- this patch was applied.
-- ─────────────────────────────────────────────────────────────
DELIMITER //

DROP PROCEDURE IF EXISTS _BackfillCompletedHours //
CREATE PROCEDURE _BackfillCompletedHours()
BEGIN
    DECLARE done           INT DEFAULT FALSE;
    DECLARE v_ProjectId    INT UNSIGNED;
    DECLARE v_UserId       INT UNSIGNED;
    DECLARE v_SessionId    INT UNSIGNED;
    DECLARE v_SessionDate  DATE;
    DECLARE v_StartTime    TIME;
    DECLARE v_EndTime      TIME;
    DECLARE v_MaxVol       INT UNSIGNED DEFAULT 0;
    DECLARE v_SessionHours DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_HoursLogged  DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_TypeCode     VARCHAR(50)  DEFAULT '';
    DECLARE v_RecurStart   DATE;
    DECLARE v_RecurEnd     DATE;
    DECLARE v_RecurDays    VARCHAR(50);
    DECLARE v_DaysPerWeek  INT DEFAULT 1;
    DECLARE v_Weeks        INT DEFAULT 1;
    DECLARE v_AttendedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT 0;

    -- Cursor: APPROVED volunteers on COMPLETED projects with no ATTENDED record
    DECLARE cur CURSOR FOR
        SELECT pa.ProjectId, pa.UserId
        FROM   ProjectApplications pa
        JOIN   Projects p ON pa.ProjectId = p.ProjectId
        JOIN   LookupValues appv ON pa.StatusLkpId = appv.LookupValueId
        JOIN   LookupValues prjv ON p.StatusLkpId  = prjv.LookupValueId
        WHERE  pa.IsDeleted = 0
          AND  appv.ValueCode = 'APPROVED'
          AND  prjv.ValueCode = 'COMPLETED'
          AND  NOT EXISTS (
              SELECT 1
              FROM   ProjectAttendance att2
              JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
              JOIN   LookupValues      lv2 ON att2.AttendStatusLkpId = lv2.LookupValueId
              WHERE  att2.UserId    = pa.UserId
                AND  ps2.ProjectId  = pa.ProjectId
                AND  lv2.ValueCode  = 'ATTENDED'
                AND  ps2.IsDeleted  = 0
          );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    SELECT LookupValueId INTO v_AttendedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'  LIMIT 1;
    SELECT LookupValueId INTO v_ApprovedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'  LIMIT 1;
    SELECT LookupValueId INTO v_CompletedLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'      AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_ProjectId, v_UserId;
        IF done THEN LEAVE read_loop; END IF;

        -- Load project schedule
        SELECT
            COALESCE(ptv.ValueCode, 'ONE_TIME'),
            COALESCE(p.SessionStartTime, '09:00:00'),
            COALESCE(p.SessionEndTime,   '17:00:00'),
            p.RecurStart, p.RecurEnd, p.RecurDays,
            COALESCE(p.MaxVolunteers, 0)
        INTO v_TypeCode, v_StartTime, v_EndTime, v_RecurStart, v_RecurEnd, v_RecurDays, v_MaxVol
        FROM Projects p
        LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
        WHERE p.ProjectId = v_ProjectId AND p.IsDeleted = 0;

        -- Find or create a session for this project
        SELECT ps.SessionId, ps.SessionDate, ps.StartTime, ps.EndTime
        INTO   v_SessionId, v_SessionDate, v_StartTime, v_EndTime
        FROM   ProjectSessions ps
        WHERE  ps.ProjectId = v_ProjectId AND ps.IsDeleted = 0
        ORDER  BY ps.SessionDate DESC LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT COALESCE(p.OneTimeDate, p.RecurStart, p.FlexFromDate, CURDATE())
            INTO   v_SessionDate
            FROM   Projects p WHERE p.ProjectId = v_ProjectId AND p.IsDeleted = 0;

            INSERT INTO ProjectSessions
                (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, CreatedBy)
            VALUES
                (v_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, 1);

            SET v_SessionId = LAST_INSERT_ID();
        END IF;

        -- Hours per session
        SET v_SessionHours = GREATEST(
            ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2),
            0.50
        );

        -- Total hours based on project type
        IF v_TypeCode = 'RECURRING'
           AND v_RecurStart IS NOT NULL
           AND v_RecurEnd   IS NOT NULL
           AND v_RecurDays  IS NOT NULL
           AND v_RecurDays  <> ''
        THEN
            SET v_DaysPerWeek = LENGTH(v_RecurDays) - LENGTH(REPLACE(v_RecurDays, ',', '')) + 1;
            SET v_Weeks = GREATEST(CEIL(DATEDIFF(v_RecurEnd, v_RecurStart) / 7.0), 1);
            SET v_HoursLogged = LEAST(v_SessionHours * v_DaysPerWeek * v_Weeks, 9999.99);
        ELSE
            SET v_HoursLogged = v_SessionHours;
        END IF;

        -- Insert backfilled attendance record
        INSERT IGNORE INTO ProjectAttendance
            (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, AdminNote, CreatedBy)
        VALUES
            (v_SessionId, v_UserId, NOW(), v_HoursLogged, v_AttendedLkpId,
             'Backfilled: auto-attendance on completed project.', 1);

    END LOOP;
    CLOSE cur;

    SELECT CONCAT('Backfill complete at ', NOW()) AS Result;
END //

DELIMITER ;

-- Run the backfill
CALL _BackfillCompletedHours();

-- Clean up helper procedure
DROP PROCEDURE IF EXISTS _BackfillCompletedHours;

-- ============================================================
-- PATCH: Fix admin-remove vs self-withdraw label
-- Adds WasRemovedByAdmin computed column to:
--   - User_GetImpactSummary  (RS3 Cancelled result set)
--   - Application_GetByUser  (main SELECT)
-- Logic: IF(StatusUpdatedBy IS NOT NULL AND StatusUpdatedBy != UserId, 1, 0)
-- Mobile reads this flag and shows "Removed by Admin" instead of "Withdrawn by You".
-- Also fixes ProjectDetailScreen apply button — WITHDRAWN now shows "Removed from Project"
-- (mobile-only change, no SP required).
-- ============================================================

DELIMITER //

-- ── 1. User_GetImpactSummary — add WasRemovedByAdmin to RS3 (Cancelled) ──────

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

    -- RS0: Applied — PENDING
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
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
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_PendingLkpId
    ORDER BY pa.CreatedAt DESC LIMIT p_AppLimit;

    -- RS1: Upcoming — APPROVED + project UPCOMING/ACTIVE
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
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

    -- RS2: Completed — not REJECTED/WITHDRAWN + project COMPLETED
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
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

    -- RS3: Cancelled — REJECTED/WITHDRAWN OR project EXPIRED/CANCELLED
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn,
        -- Distinguish admin-remove from self-withdraw: StatusUpdatedBy is set to admin when removed
        IF(pa.StatusUpdatedBy IS NOT NULL AND pa.StatusUpdatedBy != p_UserId, 1, 0) AS WasRemovedByAdmin
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

    -- RS4: Badges — latest N
    SELECT ub.UserBadgeId, ub.BadgeLkpId, lv.ValueName AS BadgeName, lv.ValueCode AS BadgeCode,
           o.OrgName, p.ProjectName, ub.CreatedAt AS AwardedAt
    FROM   UserBadges ub
    JOIN   LookupValues lv   ON ub.BadgeLkpId      = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId       = p.ProjectId
    WHERE  ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC LIMIT p_BadgeLimit;

    -- RS5: Counts
    SELECT
        (SELECT COUNT(*) FROM ProjectApplications pa WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_PendingLkpId) AS TotalApplied,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_ApprovedLkpId AND p2.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId)) AS TotalUpcoming,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId) AND p2.StatusLkpId = v_CompletedProjId) AS TotalCompleted,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId) OR p2.StatusLkpId IN (v_ExpiredProjId, v_CancelledProjId))) AS TotalCancelled,
        (SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0) AS TotalBadges;

    -- RS6: Impact stats
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


-- ── 2. Application_GetByUser — add WasRemovedByAdmin ─────────────────────────

DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset         INT;
    DECLARE v_AttendedLkpId  INT UNSIGNED;
    DECLARE v_CheckedInLkpId INT UNSIGNED;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        pa.UserId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl              AS OrgLogoUrl,
        appSv.ValueCode        AS StatusCode,
        appSv.ValueName        AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        ptv.ValueCode          AS ScheduleTypeCode,
        ptv.ValueName          AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.OneTimeDate,
        p.FlexFromDate,
        p.FlexToDate,
        p.Landmark             AS LocationName,
        p.City,
        p.Category             AS CategoryName,
        projSv.ValueCode       AS ProjectStatusCode,
        projSv.ValueName       AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        -- RECURRING: sessions this volunteer attended
        (SELECT COUNT(*)
         FROM   ProjectAttendance ata
         JOIN   ProjectSessions   pss ON ata.SessionId = pss.SessionId
         WHERE  pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId
           AND  ata.AttendStatusLkpId = v_AttendedLkpId
        ) AS MyAttendedSessions,
        -- RECURRING: sessions eligible (from approval date onward)
        (SELECT COUNT(*)
         FROM   ProjectSessions ps2
         WHERE  ps2.ProjectId  = p.ProjectId
           AND  ps2.SessionDate >= DATE(pa.StatusUpdatedAt)
           AND  ps2.IsDeleted   = 0
        ) AS MyEligibleSessions,
        -- FLEXIBLE: hours logged
        COALESCE((
            SELECT SUM(ata2.HoursLogged)
            FROM   ProjectAttendance ata2
            JOIN   ProjectSessions   pss2 ON ata2.SessionId = pss2.SessionId
            WHERE  pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId
              AND  ata2.AttendStatusLkpId = v_AttendedLkpId
        ), 0) AS MyHoursLogged,
        -- FLEXIBLE: required hours
        ROUND(
            DATEDIFF(p.FlexToDate, p.FlexFromDate) *
            (TIMESTAMPDIFF(MINUTE, p.SessionStartTime, p.SessionEndTime) / 60.0) *
            COALESCE(p.MinAttendPct, 70) / 100.0
        , 2) AS MyRequiredHours,
        p.MinAttendPct,
        p.MaxDailyHours,
        -- FLEXIBLE: active (open) check-in record
        (SELECT ata3.AttendanceId
         FROM   ProjectAttendance ata3
         JOIN   ProjectSessions   pss3 ON ata3.SessionId = pss3.SessionId
         WHERE  pss3.ProjectId = p.ProjectId AND ata3.UserId = p_UserId
           AND  ata3.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata3.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInId,
        (SELECT ata3.CheckInTime
         FROM   ProjectAttendance ata3
         JOIN   ProjectSessions   pss3 ON ata3.SessionId = pss3.SessionId
         WHERE  pss3.ProjectId = p.ProjectId AND ata3.UserId = p_UserId
           AND  ata3.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata3.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInTime,
        -- Certificate (if issued)
        (SELECT vc.CertCode
         FROM   VolunteerCertificates vc
         WHERE  vc.ProjectId = p.ProjectId AND vc.UserId = p_UserId AND vc.IsDeleted = 0
         LIMIT  1
        ) AS MyCertCode,
        IF(EXISTS(
            SELECT 1 FROM VolunteerCertificates vc
            WHERE  vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0
        ), 1, 0) AS HasCertificate,
        -- Any attendance record exists (for QR/checkin indicator)
        IF(EXISTS(
            SELECT 1 FROM ProjectAttendance ata4
            JOIN   ProjectSessions pss4 ON ata4.SessionId = pss4.SessionId
            WHERE  pss4.ProjectId = p.ProjectId AND ata4.UserId = p_UserId
        ), 1, 0) AS IsCheckedIn,
        -- Distinguish admin-remove from self-withdraw
        IF(pa.StatusUpdatedBy IS NOT NULL AND pa.StatusUpdatedBy != pa.UserId, 1, 0) AS WasRemovedByAdmin
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId        = p.ProjectId
    JOIN   Organisations o     ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId      = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId       = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId     = jtv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.1-withdrawn-label', 'Fix admin-remove vs self-withdraw label: User_GetImpactSummary RS3 and Application_GetByUser now return WasRemovedByAdmin (1 if StatusUpdatedBy != UserId). Mobile CancelledCard shows "Removed by Admin" for flag=1. ProjectDetailScreen apply button shows "Removed from Project" for WITHDRAWN status.', 'System');

-- ════════════════════════════════════════════════════════════════════════════
-- NGOConnect_Patch_CertificateIssuance.sql
-- ════════════════════════════════════════════════════════════════════════════
-- Purpose : Add per-volunteer certificate issuance status to admin and
--           volunteer views; enables admin to issue certs from ParticipantsScreen.
--
-- Changes
--   1. Application_GetByProject   — adds HasCertificate column
--   2. User_GetImpactSummary      — adds HasCertificate to RS2 (Completed tab)
--
-- Apply to : Railway staging, then production.
-- Run as   : source NGOConnect_Patch_CertificateIssuance.sql
-- ════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── 1. Application_GetByProject ─────────────────────────────────────────────
-- Adds HasCertificate (1/0) per volunteer row so ParticipantsScreen knows
-- whether to show "Issue Certificate" or "✓ Certificate Issued" on ATTENDED cards.
DROP PROCEDURE IF EXISTS Application_GetByProject //
CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_FilterLkpId INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_FilterLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId,
        pa.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)     AS ApplicantName,
        up.ProfilePhoto,
        up.City,
        up.Occupation                               AS Profession,
        pa.Motivation,
        pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode)  AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName)  AS Status,
        pa.StatusUpdatedAt,
        pa.CreatedAt,
        DATE_FORMAT(CONVERT_TZ(att.CheckInTime, '+00:00', '+05:30'), '%Y-%m-%dT%H:%i:%s') AS CheckedInAt,
        att.HoursLogged,
        att.IsNoShowExcused                         AS IsExcused,
        att.QrScannedAt,
        att.AdminNote,
        ps.SessionDate,
        ps.StartTime   AS SessionStartTime,
        ps.EndTime     AS SessionEndTime,
        (SELECT GROUP_CONCAT(lv2.ValueCode ORDER BY ub.CreatedAt SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv2 ON ub.BadgeLkpId = lv2.LookupValueId
         WHERE  ub.UserId     = pa.UserId
           AND  ub.ProjectId  = pa.ProjectId
           AND  ub.IsDeleted  = 0
        )                                           AS AwardedBadgeCodes,
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc2
                  WHERE vc2.ProjectId = pa.ProjectId
                    AND vc2.UserId    = pa.UserId
                    AND vc2.IsDeleted = 0), 1, 0)   AS HasCertificate
    FROM   ProjectApplications pa
    JOIN   UserProfiles up   ON pa.UserId        = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    LEFT JOIN LookupValues   attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps   ON ps.SessionId          = att.SessionId
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           )
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications pa
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           );
END //


-- ── 2. User_GetImpactSummary ─────────────────────────────────────────────────
-- RS2 (Completed tab) gains HasCertificate (1/0) per application row so the
-- volunteer ImpactScreen only shows the Certificate button when a cert exists.
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
    -- HasCertificate: 1 if a VolunteerCertificate row exists, 0 otherwise
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

    -- RS6: Impact stats (same logic as User_GetImpact — computes from scratch, no stored columns)
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

        SELECT LookupValueId INTO v_AttStatusAttended FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;
        SELECT LookupValueId INTO v_AttStatusNoShow   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW'   LIMIT 1;

        SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)), 0) INTO v_TotalMinutes
        FROM ProjectAttendance pa JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
        WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;
        SET v_TotalHours = ROUND(v_TotalMinutes / 60.0, 1);

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

SELECT 'Patch applied: Application_GetByProject (HasCertificate), User_GetImpactSummary (RS2 HasCertificate)' AS Result;

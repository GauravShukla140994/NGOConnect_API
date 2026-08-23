-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_impact_summary_progress.sql
-- Adds progress tracking fields to User_GetImpactSummary RS1 (Upcoming).
--
-- Changes:
--   RS1 now includes: MyAttendedSessions, MyEligibleSessions, MyHoursLogged,
--   MyRequiredHours, MinAttendPct, ActiveCheckInId, MyCertCode
--   RS1 now includes CLOSING projects (was only UPCOMING + ACTIVE)
--
-- Impact: ImpactScreen UpcomingCard progress bars now show real data for
--         RECURRING (session %) and FLEXIBLE (hours %) projects.
-- ONE_TIME: RS0/RS2/RS3 completely unchanged.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

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
    DECLARE v_ClosingProjId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CompletedProjId INT UNSIGNED DEFAULT 0;
    DECLARE v_ExpiredProjId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CancelledProjId INT UNSIGNED DEFAULT 0;
    DECLARE v_AttendedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CheckedInLkpId  INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_PendingLkpId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'    LIMIT 1;
    SELECT LookupValueId INTO v_ApprovedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'   LIMIT 1;
    SELECT LookupValueId INTO v_RejectedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'REJECTED'   LIMIT 1;
    SELECT LookupValueId INTO v_WithdrawnLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN'  LIMIT 1;
    SELECT LookupValueId INTO v_UpcomingProjId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING'   LIMIT 1;
    SELECT LookupValueId INTO v_ActiveProjId    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'     LIMIT 1;
    SELECT LookupValueId INTO v_ClosingProjId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING'    LIMIT 1;
    SELECT LookupValueId INTO v_CompletedProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED'  LIMIT 1;
    SELECT LookupValueId INTO v_ExpiredProjId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'EXPIRED'    LIMIT 1;
    SELECT LookupValueId INTO v_CancelledProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'  LIMIT 1;
    SELECT LookupValueId INTO v_AttendedLkpId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'   LIMIT 1;
    SELECT LookupValueId INTO v_CheckedInLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    -- RS0: Applied — PENDING (unchanged)
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

    -- RS1: Upcoming — APPROVED + UPCOMING/ACTIVE/CLOSING + progress fields
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
        -- RECURRING: sessions attended
        (SELECT COUNT(*) FROM ProjectAttendance ata2 JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId
         WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId AND ata2.AttendStatusLkpId = v_AttendedLkpId
        ) AS MyAttendedSessions,
        -- RECURRING: eligible sessions from volunteer's approval date
        (SELECT COUNT(*) FROM ProjectSessions ps3
         WHERE ps3.ProjectId = p.ProjectId AND ps3.SessionDate >= DATE(pa.StatusUpdatedAt) AND ps3.IsDeleted = 0
        ) AS MyEligibleSessions,
        -- FLEXIBLE: hours logged
        COALESCE((SELECT SUM(ata4.HoursLogged) FROM ProjectAttendance ata4 JOIN ProjectSessions pss4 ON ata4.SessionId = pss4.SessionId
         WHERE pss4.ProjectId = p.ProjectId AND ata4.UserId = p_UserId AND ata4.AttendStatusLkpId = v_AttendedLkpId
        ), 0) AS MyHoursLogged,
        -- FLEXIBLE: required hours (date range × daily window × minAttendPct%)
        ROUND(DATEDIFF(p.FlexToDate, p.FlexFromDate) * (TIMESTAMPDIFF(MINUTE, p.SessionStartTime, p.SessionEndTime) / 60.0) * COALESCE(p.MinAttendPct, 70) / 100.0, 2) AS MyRequiredHours,
        p.MinAttendPct,
        -- FLEXIBLE: active CHECKED_IN record (not yet checked out)
        (SELECT ata5.AttendanceId FROM ProjectAttendance ata5 JOIN ProjectSessions pss5 ON ata5.SessionId = pss5.SessionId
         WHERE pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId AND ata5.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata5.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInId,
        -- Certificate (if already issued)
        (SELECT vc.CertCode FROM VolunteerCertificates vc
         WHERE vc.ProjectId = p.ProjectId AND vc.UserId = p_UserId AND vc.IsDeleted = 0 LIMIT 1
        ) AS MyCertCode
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND p.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId, v_ClosingProjId)
    ORDER BY p.RecurStart ASC LIMIT p_AppLimit;

    -- RS2: Completed (unchanged)
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
        COALESCE((SELECT SUM(ata2.HoursLogged) FROM ProjectAttendance ata2 JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId), 0) AS HoursLogged,
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc WHERE vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0), 1, 0) AS HasCertificate
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId)
      AND p.StatusLkpId = v_CompletedProjId
    ORDER BY pa.StatusUpdatedAt DESC LIMIT p_AppLimit;

    -- RS3: Cancelled (unchanged)
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
        IF(pa.StatusLkpId = v_WithdrawnLkpId AND pa.StatusUpdatedBy != p_UserId, 1, 0) AS IsAdminRemoved
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId)
           OR p.StatusLkpId IN (v_ExpiredProjId, v_CancelledProjId))
    ORDER BY pa.StatusUpdatedAt DESC LIMIT p_AppLimit;

    -- RS4: Impact score + badges (unchanged)
    SELECT up.ImpactScore, up.ReliabilityScore
    FROM UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    SELECT ub.BadgeId, lv.ValueCode AS BadgeCode, lv.ValueName AS BadgeName,
           lv.Icon AS BadgeIcon, ub.EarnedAt
    FROM UserBadges ub
    JOIN LookupValues lv ON ub.BadgeLkpId = lv.LookupValueId
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.EarnedAt DESC LIMIT p_BadgeLimit;

END //

DELIMITER ;

SELECT 'patch_fix_impact_summary_progress applied successfully.' AS Status;

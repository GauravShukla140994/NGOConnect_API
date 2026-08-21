-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_attendance_status_display.sql
-- Application_GetByUser — add AttendanceStatusCode + AttendanceIsExcused
--   to support correct attendance display on volunteer completed-project cards.
-- Run on: local → Railway staging → Railway production
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

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
        -- FLEXIBLE: required hours (available window × session hours per day × MinAttendPct %)
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
        -- Most recent attendance status for this user on this project (ATTENDED | NO_SHOW | null)
        (SELECT lv_att.ValueCode
         FROM   ProjectAttendance ata5
         JOIN   ProjectSessions   pss5 ON ata5.SessionId = pss5.SessionId
         JOIN   LookupValues      lv_att ON ata5.AttendStatusLkpId = lv_att.LookupValueId
         WHERE  pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId
         ORDER BY pss5.SessionDate DESC, ata5.CreatedAt DESC
         LIMIT  1
        )                                               AS AttendanceStatusCode,
        -- Whether the most recent no-show was excused
        (SELECT ata5.IsNoShowExcused
         FROM   ProjectAttendance ata5
         JOIN   ProjectSessions   pss5 ON ata5.SessionId = pss5.SessionId
         WHERE  pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId
         ORDER BY pss5.SessionDate DESC, ata5.CreatedAt DESC
         LIMIT  1
        )                                               AS AttendanceIsExcused,
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

//

DELIMITER ;

-- ── Patch: QR Attendance Fixes (2026-08-01) ─────────────────────────────────
--
-- Fix 1 · Application_GetByUser
--   Added:  RequiresApproval (derived from JoinTypeLkpId = APPROVE_REQ)
--   Added:  IsCheckedIn (1 if user has any ProjectAttendance row for this project)
--   Effect: Volunteer My Projects screen can hide QR button after scan
--
-- Fix 2 · Application_GetByProject
--   Changed: att.CheckInTime AS CheckedInAt
--        to: DATE_FORMAT(CONVERT_TZ(att.CheckInTime,'+00:00','+05:30'),'%H:%i') AS CheckedInAt
--   Reason:  CheckInTime is stored as UTC (Railway MySQL server = UTC).
--            Admin screen was showing UTC time, which is 5h30m behind IST.
--            Now returns IST "HH:MM" which fmtTime / fmtTime12 both format correctly.
--
-- Apply to: Railway staging → Railway production
-- ──────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── Fix 1: Application_GetByUser ─────────────────────────────────────────────
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
        projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(
            SELECT 1 FROM ProjectAttendance ata
            JOIN   ProjectSessions pss ON ata.SessionId = pss.SessionId
            WHERE  pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId
        ), 1, 0) AS IsCheckedIn
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId   = p.ProjectId
    JOIN   Organisations o     ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId        = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId         = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId    = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId       = jtv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //


-- ── Fix 2: Application_GetByProject ──────────────────────────────────────────
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
        pa.ApplicationId, pa.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS ApplicantName,
        up.ProfilePhoto, up.City,
        up.Occupation                          AS Profession,
        pa.Motivation, pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode) AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName) AS Status,
        pa.StatusUpdatedAt, pa.CreatedAt,
        DATE_FORMAT(CONVERT_TZ(att.CheckInTime, '+00:00', '+05:30'), '%Y-%m-%dT%H:%i:%s') AS CheckedInAt,
        att.HoursLogged,
        att.IsNoShowExcused AS IsExcused,
        att.QrScannedAt, att.AdminNote,
        ps.SessionDate, ps.StartTime AS SessionStartTime, ps.EndTime AS SessionEndTime
    FROM   ProjectApplications pa
    JOIN   UserProfiles up ON pa.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId FROM ProjectAttendance att2
        JOIN ProjectSessions ps2 ON att2.SessionId = ps2.SessionId
        WHERE att2.UserId = pa.UserId AND ps2.ProjectId = pa.ProjectId AND ps2.IsDeleted = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC LIMIT 1
    )
    LEFT JOIN LookupValues attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps ON ps.SessionId = att.SessionId
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
    FROM   ProjectApplications
    WHERE  ProjectId  = p_ProjectId
      AND  IsDeleted  = 0;
END //

DELIMITER ;

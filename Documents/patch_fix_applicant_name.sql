-- ── patch_fix_applicant_name.sql ────────────────────────────────────────────
-- Fixes two bugs:
--   1. Application_GetByProject returned NULL ApplicantName when volunteer
--      had not filled FirstName/LastName (CONCAT with NULL returns NULL).
--      Fix: CONCAT_WS (skips NULLs) + JOIN Users for phone/email fallback.
--   2. NEW_APPLICATION notification body was generic ("A new volunteer has
--      applied…"). Fix: Application_Apply now returns ApplicantName so the
--      DAL can include the real name in the notification body.
-- Apply to: Railway staging → production
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── 1. Application_GetByProject — fix NULL name + Users JOIN ─────────────────
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
        -- CONCAT_WS skips NULLs; fall back to phone/email for unfinished profiles
        COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''),
                 u.Mobile, u.Email)             AS ApplicantName,
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
        att.AttendanceId,
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
    JOIN   Users u           ON u.UserId         = pa.UserId
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
        WHERE  att2.UserId    = pa.UserId
          AND  ps2.ProjectId  = pa.ProjectId
          AND  ps2.IsDeleted  = 0
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


-- ── 2. Application_Apply — return ApplicantName for notification body ─────────
DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_PendingLkpId   INT UNSIGNED;
    DECLARE v_ExistingId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExistingStatus VARCHAR(50)  DEFAULT NULL;
    DECLARE v_AgeRestriction TINYINT(1)   DEFAULT 0;
    DECLARE v_IsPublic       TINYINT(1)   DEFAULT 1;
    DECLARE v_OrgId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_UserDob        DATE         DEFAULT NULL;
    DECLARE v_UserAge        INT          DEFAULT NULL;
    DECLARE v_MembershipOk   TINYINT(1)   DEFAULT 1;
    DECLARE v_ApplicantName  VARCHAR(200) DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT p.AgeRestriction, p.IsPublic, p.OrgId
    INTO   v_AgeRestriction, v_IsPublic, v_OrgId
    FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    IF v_IsPublic = 0 THEN
        IF NOT EXISTS (
            SELECT 1 FROM OrgMembers om
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId
            WHERE om.OrgId = v_OrgId AND om.UserId = p_UserId
              AND om.IsDeleted = 0
              AND st.TypeCode = 'MEMBER_STATUS' AND sv.ValueCode = 'APPROVED'
        ) THEN
            SET v_MembershipOk = 0;
            SELECT 0 AS IsSuccess,
                   'This project is only available to organisation members.' AS Message,
                   NULL AS ApplicationId, NULL AS OrgId, NULL AS ApplicantName;
        END IF;
    END IF;

    IF v_MembershipOk = 1 AND v_AgeRestriction = 1 THEN
        SELECT up.DateOfBirth INTO v_UserDob
        FROM   UserProfiles up WHERE up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        IF v_UserDob IS NULL THEN
            SELECT 0 AS IsSuccess,
                   'This project is for volunteers aged 18 and above. Please update your date of birth in your profile before applying.' AS Message,
                   NULL AS ApplicationId, NULL AS OrgId, NULL AS ApplicantName;
        ELSE
            SET v_UserAge = TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE());
            IF v_UserAge < 18 THEN
                SELECT 0 AS IsSuccess,
                       CONCAT('This project requires volunteers to be at least 18 years old. Your current age (', v_UserAge, ') does not meet the requirement.') AS Message,
                       NULL AS ApplicationId, NULL AS OrgId, NULL AS ApplicantName;
            END IF;
        END IF;
    END IF;

    IF v_MembershipOk = 1
       AND (
           (v_AgeRestriction = 0)
           OR (v_AgeRestriction = 1 AND v_UserDob IS NOT NULL AND TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE()) >= 18)
       )
    THEN

    SELECT pa.ApplicationId, lv.ValueCode
    INTO   v_ExistingId, v_ExistingStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
    LIMIT  1;

    IF v_ExistingStatus IN ('PENDING', 'APPROVED') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('You already have a ', v_ExistingStatus, ' application for this project.') AS Message,
               NULL AS ApplicationId, NULL AS OrgId, NULL AS ApplicantName;

    ELSEIF v_ExistingStatus = 'REJECTED' THEN
        UPDATE ProjectApplications
        SET    StatusLkpId       = v_PendingLkpId,
               Motivation        = p_Motivation,
               RequestedSessions = p_RequestedSessions,
               RejectionReason   = NULL,
               StatusUpdatedAt   = NOW(),
               StatusUpdatedBy   = p_UserId,
               UpdatedBy         = p_UserId,
               UpdatedAt         = NOW()
        WHERE  ApplicationId = v_ExistingId;

        SELECT COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''), u.Mobile, u.Email)
        INTO   v_ApplicantName
        FROM   UserProfiles up JOIN Users u ON u.UserId = p_UserId
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        SELECT 1 AS IsSuccess, 'Application re-submitted successfully.' AS Message,
               v_ExistingId AS ApplicationId,
               v_OrgId AS OrgId,
               v_ApplicantName AS ApplicantName;

    ELSE
        INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
        VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

        SELECT COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''), u.Mobile, u.Email)
        INTO   v_ApplicantName
        FROM   UserProfiles up JOIN Users u ON u.UserId = p_UserId
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
               LAST_INSERT_ID() AS ApplicationId,
               v_OrgId AS OrgId,
               v_ApplicantName AS ApplicantName;
    END IF;

    END IF;
END //

DELIMITER ;

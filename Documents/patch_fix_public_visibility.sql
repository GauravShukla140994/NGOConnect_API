-- ============================================================
-- NGO Connect — Patch: IsPublic visibility enforcement
-- Applies to: staging and production Railway DBs
-- Safe to re-run (DROP IF EXISTS + CREATE)
-- ============================================================

DELIMITER //

-- ── 1. Project_GetById: enforce IsPublic → org membership ──────────────────
-- Non-members cannot fetch private project details.
-- v5.1 MODIFIED: returns all 17 schedule/location/restriction fields + MinAttendPct/MaxDailyHours/MinSessionHours/TotalSessions
DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        DATE_FORMAT(p.RecurStart,    '%Y-%m-%d') AS RecurStart,
        DATE_FORMAT(p.RecurEnd,      '%Y-%m-%d') AS RecurEnd,
        p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        DATE_FORMAT(p.OneTimeDate,   '%Y-%m-%d') AS OneTimeDate,
        DATE_FORMAT(p.FlexFromDate,  '%Y-%m-%d') AS FlexFromDate,
        DATE_FORMAT(p.FlexToDate,    '%Y-%m-%d') AS FlexToDate,
        p.MinHoursRequired,
        p.MinAttendPct, p.MaxDailyHours, p.MinSessionHours,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedCount,
        (SELECT COUNT(*) FROM ProjectSessions WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS TotalSessions,
        (SELECT lv2.ValueCode FROM ProjectApplications pa2
            JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
            WHERE pa2.ProjectId = p.ProjectId AND pa2.UserId = p_UserId AND pa2.IsDeleted = 0
            LIMIT 1) AS ApplicationStatusCode
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0
      AND (
          p.IsPublic = 1
          OR p_UserId IS NULL OR p_UserId = 0
          OR EXISTS (
              SELECT 1 FROM OrgMembers om
              JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
              JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId
              WHERE om.OrgId = p.OrgId AND om.UserId = p_UserId
                AND om.IsDeleted = 0
                AND st.TypeCode = 'MEMBER_STATUS' AND sv.ValueCode = 'APPROVED'
          )
      );
END //

-- ── 2. Application_Apply: enforce IsPublic + age restriction ───────────────
-- Private project → must be approved member.
-- 18+ project → must have DoB and meet age threshold.
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

    -- Resolve PENDING lookup id
    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- Read project attributes in one query
    SELECT p.AgeRestriction, p.IsPublic, p.OrgId
    INTO   v_AgeRestriction, v_IsPublic, v_OrgId
    FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    -- ── IsPublic check — private projects require approved membership ─────
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
                   NULL AS ApplicationId, NULL AS OrgId;
        END IF;
    END IF;

    -- ── Age restriction check ─────────────────────────────────────────────
    IF v_MembershipOk = 1 AND v_AgeRestriction = 1 THEN
        SELECT up.DateOfBirth INTO v_UserDob
        FROM   UserProfiles up WHERE up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        IF v_UserDob IS NULL THEN
            SELECT 0 AS IsSuccess,
                   'This project is for volunteers aged 18 and above. Please update your date of birth in your profile before applying.' AS Message,
                   NULL AS ApplicationId, NULL AS OrgId;
        ELSE
            SET v_UserAge = TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE());
            IF v_UserAge < 18 THEN
                SELECT 0 AS IsSuccess,
                       CONCAT('This project requires volunteers to be at least 18 years old. Your current age (', v_UserAge, ') does not meet the requirement.') AS Message,
                       NULL AS ApplicationId, NULL AS OrgId;
            END IF;
        END IF;
    END IF;

    -- Only proceed if both checks passed
    IF v_MembershipOk = 1
       AND (
           (v_AgeRestriction = 0)
           OR (v_AgeRestriction = 1 AND v_UserDob IS NOT NULL AND TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE()) >= 18)
       )
    THEN

    -- Check for any existing non-deleted application for this user + project
    SELECT pa.ApplicationId, lv.ValueCode
    INTO   v_ExistingId, v_ExistingStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
    LIMIT  1;

    IF v_ExistingStatus IN ('PENDING', 'APPROVED') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('You already have a ', v_ExistingStatus, ' application for this project.') AS Message,
               NULL AS ApplicationId,
               NULL AS OrgId;

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

        SELECT 1 AS IsSuccess, 'Application re-submitted successfully.' AS Message,
               v_ExistingId AS ApplicationId,
               v_OrgId AS OrgId;

    ELSE
        INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
        VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
               LAST_INSERT_ID() AS ApplicationId,
               v_OrgId AS OrgId;
    END IF;

    END IF; -- end checks gate
END //

DELIMITER ;

-- ── Verify ──────────────────────────────────────────────────────────────────
SELECT ROUTINE_NAME, LAST_ALTERED
FROM   INFORMATION_SCHEMA.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE()
  AND  ROUTINE_NAME IN ('Project_GetById', 'Application_Apply')
ORDER  BY ROUTINE_NAME;

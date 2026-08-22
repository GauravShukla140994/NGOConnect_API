-- ============================================================
-- patch_age_restriction_apply.sql
-- Enforces 18+ age restriction check in Application_Apply SP.
-- Safe to re-run (DROP IF EXISTS).
-- ============================================================

DELIMITER //

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
    DECLARE v_UserDob        DATE         DEFAULT NULL;
    DECLARE v_UserAge        INT          DEFAULT NULL;

    -- Resolve PENDING lookup id
    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- ── Age restriction check ────────────────────────────────────────────────
    SELECT p.AgeRestriction INTO v_AgeRestriction
    FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    IF v_AgeRestriction = 1 THEN
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

    -- Only proceed if age check passed (no result returned above)
    IF (v_AgeRestriction = 0)
       OR (v_AgeRestriction = 1 AND v_UserDob IS NOT NULL AND TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE()) >= 18)
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
               NULL AS ApplicationId, NULL AS OrgId;

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
               (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;

    ELSE
        INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
        VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
               LAST_INSERT_ID() AS ApplicationId,
               (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;
    END IF;

    END IF; -- end age-restriction gate
END //

DELIMITER ;

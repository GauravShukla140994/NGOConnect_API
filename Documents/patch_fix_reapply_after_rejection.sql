-- ── patch_fix_reapply_after_rejection.sql ────────────────────────────────────
-- Bug  : Rejected volunteer gets "an error occurred" when trying to re-apply
--        to the same project.
--
-- Root cause:
--   Application_Apply did a plain INSERT with no duplicate check.
--   ProjectApplications has UNIQUE KEY (ProjectId, UserId, IsDeleted).
--   After rejection the row still exists with IsDeleted=0, so re-applying
--   hits the duplicate key constraint → MySQL throws an error → API returns 500.
--
-- Fix:
--   Before INSERT, check if a non-deleted application already exists:
--     PENDING / APPROVED → block with a user-friendly message
--     REJECTED           → UPDATE the existing row back to PENDING (re-application)
--     None               → fresh INSERT (original path)
--
-- No table or column changes. Safe to re-run.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

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

    -- Resolve PENDING lookup id
    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- Check for any existing non-deleted application for this user + project
    SELECT pa.ApplicationId, lv.ValueCode
    INTO   v_ExistingId, v_ExistingStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
    LIMIT  1;

    IF v_ExistingStatus IN ('PENDING', 'APPROVED') THEN
        -- Cannot re-apply while a live application exists
        SELECT 0 AS IsSuccess,
               CONCAT('You already have a ', v_ExistingStatus, ' application for this project.') AS Message,
               NULL AS ApplicationId,
               NULL AS OrgId;

    ELSEIF v_ExistingStatus = 'REJECTED' THEN
        -- Re-application: reset the rejected row to PENDING
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
        -- No existing application — fresh INSERT
        INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
        VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
               LAST_INSERT_ID() AS ApplicationId,
               (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;
    END IF;
END //

DELIMITER ;

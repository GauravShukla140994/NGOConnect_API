-- ─────────────────────────────────────────────────────────────────────────────
-- NGOConnect Patch: Fix Application_Apply SP — remove non-existent AppliedAt column
-- Date   : 2026-07-17
-- Reason : Application_Apply inserted into ProjectApplications.AppliedAt which does
--          not exist on the table (table uses CreatedAt DEFAULT CURRENT_TIMESTAMP).
--          This caused "Unknown column 'AppliedAt' in 'field list'" on every apply.
-- Apply  : Run once on Railway staging, then Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
    VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

    SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
           LAST_INSERT_ID() AS ApplicationId,
           (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;
END //

DELIMITER ;

-- ============================================================
-- NGOConnect Patch: Project_Cancel SP (clean — no Project_List overwrite)
-- Date:    2026-07-27
-- Problem:
--   Project_Cancel SP was never added to any setup SQL.
--   The old NGOConnect_Patch_Project_Cancel.sql also clobbered Project_List
--   with an outdated version using wrong column names — do NOT re-run that file.
--   This patch adds ONLY the Project_Cancel SP, safe to apply on any environment.
--
-- Apply to: Railway Staging, then Railway Production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_Cancel //

CREATE PROCEDURE Project_Cancel(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_CancelReason TEXT
)
BEGIN
    DECLARE v_CancelledStatusId INT UNSIGNED;

    -- Resolve CANCELLED status LkpId dynamically (never hardcode)
    SELECT lv.LookupValueId INTO v_CancelledStatusId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'
    LIMIT  1;

    IF v_CancelledStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project status lookup not found.' AS Message;
    ELSEIF NOT EXISTS (
        SELECT 1 FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0
    ) THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        UPDATE Projects
        SET    StatusLkpId  = v_CancelledStatusId,
               CancelReason = p_CancelReason,
               CancelledBy  = p_UserId,
               CancelledAt  = NOW(),
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UserId
        WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project cancelled successfully.' AS Message;
    END IF;
END //

DELIMITER ;

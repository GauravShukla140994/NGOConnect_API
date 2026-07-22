-- ════════════════════════════════════════════════════════════════
-- Patch: Application_Withdraw SP
-- Feature: Volunteer can withdraw a PENDING application
-- Rule: blocked within 24 hours of project start (ONE_TIME / RECURRING)
-- Apply to: Railway Staging → Railway Production
-- ════════════════════════════════════════════════════════════════

DROP PROCEDURE IF EXISTS Application_Withdraw;

DELIMITER //
CREATE PROCEDURE Application_Withdraw(
    IN p_ApplicationId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED
)
BEGIN
    DECLARE v_ProjectId      INT UNSIGNED;
    DECLARE v_StatusCode     VARCHAR(50);
    DECLARE v_RecurStart     DATE;
    DECLARE v_SessionStart   TIME;
    DECLARE v_SchType        VARCHAR(50);
    DECLARE v_WithdrawnLkpId INT UNSIGNED;

    -- Fetch application + linked project schedule info
    SELECT
        pa.ProjectId,
        lv_app.ValueCode        AS StatusCode,
        p.RecurStart,
        p.SessionStartTime,
        lv_sched.ValueCode      AS SchedType
    INTO v_ProjectId, v_StatusCode, v_RecurStart, v_SessionStart, v_SchType
    FROM ProjectApplications pa
    JOIN LookupValues lv_app   ON lv_app.LookupValueId  = pa.StatusLkpId
    JOIN Projects p            ON p.ProjectId            = pa.ProjectId
    JOIN LookupValues lv_sched ON lv_sched.LookupValueId = p.ProjectTypeLkpId
    WHERE pa.ApplicationId = p_ApplicationId
      AND pa.UserId        = p_UserId
      AND pa.IsDeleted     = 0
    LIMIT 1;

    -- Application not found or doesn't belong to user
    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;

    -- Already withdrawn, rejected, or completed
    ELSEIF v_StatusCode NOT IN ('PENDING', 'APPROVED') THEN
        SELECT 0 AS IsSuccess, 'This application cannot be withdrawn.' AS Message;

    -- APPROVED: enforce 24-hour gate for fixed-schedule projects
    -- PENDING: always allow (admin has not reviewed yet)
    ELSEIF v_StatusCode = 'APPROVED'
       AND v_SchType IN ('ONE_TIME', 'RECURRING') AND v_RecurStart IS NOT NULL
       AND TIMESTAMPDIFF(HOUR, NOW(),
             CASE WHEN v_SessionStart IS NOT NULL
                  THEN TIMESTAMP(v_RecurStart, v_SessionStart)
                  ELSE TIMESTAMP(v_RecurStart, '00:00:00')
             END) < 24 THEN
        SELECT 0 AS IsSuccess,
               'You cannot withdraw within 24 hours of the project start.' AS Message;

    ELSE
        SELECT lv2.LookupValueId INTO v_WithdrawnLkpId
        FROM LookupValues lv2
        JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
        WHERE lt2.TypeCode = 'APPLICATION_STATUS' AND lv2.ValueCode = 'WITHDRAWN'
        LIMIT 1;

        UPDATE ProjectApplications
        SET    StatusLkpId = v_WithdrawnLkpId,
               UpdatedAt   = NOW(),
               UpdatedBy   = p_UserId
        WHERE  ApplicationId = p_ApplicationId
          AND  UserId        = p_UserId;

        SELECT 1 AS IsSuccess, 'Your application has been withdrawn.' AS Message;
    END IF;
END //
DELIMITER ;

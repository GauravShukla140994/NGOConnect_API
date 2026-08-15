-- ============================================================
-- patch_admin_remove_volunteer.sql
-- Feature: Admin remove volunteer from project (all schedule types)
-- Effect:  ProjectApplications → WITHDRAWN, CurrentVolunteers--
-- ============================================================
-- Run on: Local DB → Railway staging → production
-- ============================================================

-- Step 1: Seed APP_REMOVED notification type LookupValue
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsActive)
SELECT LookupTypeId, 'APP_REMOVED', 'Removed from Project', 3, 1, 1
FROM   LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE';

-- Step 2: SP
DROP PROCEDURE IF EXISTS Project_AdminRemoveVolunteer;

DELIMITER //

CREATE PROCEDURE Project_AdminRemoveVolunteer(
    IN p_ProjectId   INT UNSIGNED,
    IN p_UserId      INT UNSIGNED,
    IN p_RemovedBy   INT UNSIGNED
)
BEGIN
    DECLARE v_Error           VARCHAR(500) DEFAULT NULL;
    DECLARE v_WithdrawnLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectStatus   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_AppId           INT UNSIGNED DEFAULT NULL;

    -- Resolve lookup IDs
    SELECT lv.LookupValueId INTO v_WithdrawnLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Validate project exists + not in a terminal state
    SELECT sv.ValueCode INTO v_ProjectStatus
    FROM   Projects p
    JOIN   LookupValues sv ON p.StatusLkpId = sv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    IF v_ProjectStatus IS NULL THEN
        SET v_Error = 'Project not found.';
    END IF;

    IF v_Error IS NULL AND v_ProjectStatus IN ('COMPLETED', 'CANCELLED', 'EXPIRED') THEN
        SET v_Error = 'Cannot remove a volunteer from a project that is already completed, cancelled, or expired.';
    END IF;

    -- Validate the volunteer has an APPROVED application
    IF v_Error IS NULL THEN
        SELECT ApplicationId INTO v_AppId
        FROM   ProjectApplications
        WHERE  ProjectId    = p_ProjectId
          AND  UserId       = p_UserId
          AND  StatusLkpId  = v_ApprovedLkpId
          AND  IsDeleted    = 0
        LIMIT  1;

        IF v_AppId IS NULL THEN
            SET v_Error = 'No approved application found for this volunteer on this project.';
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE
        -- Mark application as WITHDRAWN
        UPDATE ProjectApplications
        SET    StatusLkpId     = v_WithdrawnLkpId,
               StatusUpdatedAt = NOW(),
               StatusUpdatedBy = p_RemovedBy,
               UpdatedAt       = NOW(),
               UpdatedBy       = p_RemovedBy
        WHERE  ApplicationId = v_AppId;

        -- Decrement CurrentVolunteers (floor at 0)
        UPDATE Projects
        SET    CurrentVolunteers = GREATEST(0, CurrentVolunteers - 1),
               UpdatedAt         = NOW(),
               UpdatedBy         = p_RemovedBy
        WHERE  ProjectId = p_ProjectId;

        SELECT 1 AS IsSuccess, 'Volunteer removed from project. Slot has been freed.' AS Message;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.1-admin-remove-vol', 'Admin remove volunteer: Project_AdminRemoveVolunteer SP — sets application WITHDRAWN, frees slot (CurrentVolunteers--). Works for all schedule types.', 'System');

-- Verify:
-- CALL Project_AdminRemoveVolunteer(1, 2, 1);
-- Expected: IsSuccess=1, Message='Volunteer removed from project. Slot has been freed.'

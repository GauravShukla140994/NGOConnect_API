-- ══════════════════════════════════════════════════════════════════════════════
-- Patch: Fix 2 Hangfire SP bugs found in Railway staging logs
-- Date : 2026-08-25
-- Fixes:
--   1. Project_AutoCompleteSessions used ps.StatusLkpId — column does not exist.
--      Correct column name is ps.SessionStatusLkpId (SET and WHERE clause).
--   2. Project_GetCheckoutReminderTargets joined UserDevices — table does not exist.
--      Correct table is UserDeviceTokens. Column is Token (aliased AS FcmToken).
--      Removed ud.IsActive filter (no such column on UserDeviceTokens).
--   3. Project_GetCheckoutReminderTargets used att.IsDeleted — column does not exist
--      on ProjectAttendance table. Removed the condition.
-- Run order: standalone — no dependencies.
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── Fix 1: Project_AutoCompleteSessions ──────────────────────────────────────

DROP PROCEDURE IF EXISTS Project_AutoCompleteSessions //
CREATE PROCEDURE Project_AutoCompleteSessions()
BEGIN
    DECLARE v_ScheduledLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ScheduledLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'SCHEDULED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CompletedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE ProjectSessions ps
    SET    ps.SessionStatusLkpId = v_CompletedLkpId, ps.UpdatedAt = NOW()
    WHERE  ps.IsDeleted          = 0
      AND  ps.SessionStatusLkpId IN (v_ScheduledLkpId, v_ActiveLkpId)
      AND  CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00') < NOW();

    SELECT 1 AS IsSuccess, CONCAT('Auto-completed ', ROW_COUNT(), ' sessions.') AS Message;
END //

-- ── Fix 2: Project_GetCheckoutReminderTargets ─────────────────────────────────

DROP PROCEDURE IF EXISTS Project_GetCheckoutReminderTargets //
CREATE PROCEDURE Project_GetCheckoutReminderTargets(IN p_MinutesBefore INT)
BEGIN
    DECLARE v_CheckedInLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT att.UserId, p.ProjectId, p.ProjectName, ud.Token AS FcmToken,
           TIME_FORMAT(ps.EndTime, '%H:%i') AS EndTime
    FROM   ProjectAttendance    att
    JOIN   ProjectSessions      ps ON ps.SessionId = att.SessionId AND ps.IsDeleted = 0
    JOIN   Projects             p  ON p.ProjectId  = ps.ProjectId  AND p.IsDeleted  = 0
    JOIN   Users                u  ON u.UserId     = att.UserId
    LEFT JOIN UserDeviceTokens  ud ON ud.UserId     = att.UserId
    WHERE  att.AttendStatusLkpId = v_CheckedInLkpId
      AND  att.CheckOutTime      IS NULL
      AND  p.ProjectTypeLkpId    = v_FlexibleTypeId
      AND  ps.SessionDate        = CURDATE()
      AND  TIMESTAMPDIFF(MINUTE, NOW(),
               CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00'))
           BETWEEN (p_MinutesBefore - 1) AND (p_MinutesBefore + 1);
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('patch-fix-hangfire-sp-bugs',
        'Fix Project_AutoCompleteSessions (ps.StatusLkpId → ps.SessionStatusLkpId) and Project_GetCheckoutReminderTargets (UserDevices → UserDeviceTokens, FcmToken → Token AS FcmToken, removed att.IsDeleted which does not exist on ProjectAttendance).',
        'System');

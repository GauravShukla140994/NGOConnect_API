-- ============================================================
-- NGOConnect Micro-Patch: Settings_GetAll SP (v4.9)
-- Date   : 2026-07-22
-- Reason : Settings_GetAll was missing from the Railway DB,
--          causing SettingsCache.RefreshAsync() to throw on
--          startup and preventing the API from starting.
-- Run on : Railway staging → Railway production
-- Safe   : DROP + CREATE only — no table or data changes
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Settings_GetAll //
CREATE PROCEDURE Settings_GetAll()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

DELIMITER ;

-- ── Verify ──────────────────────────────────────────────────
SELECT ROUTINE_NAME, ROUTINE_TYPE
FROM   information_schema.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE()
  AND  ROUTINE_NAME   = 'Settings_GetAll';
-- Expected: 1 row — Settings_GetAll | PROCEDURE

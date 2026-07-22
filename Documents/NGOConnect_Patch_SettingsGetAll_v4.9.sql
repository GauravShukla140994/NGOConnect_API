-- ══════════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Settings SP Column Alignment  (v4.9)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- Problem fixed
-- ─────────────
-- Settings_GetPublic and Settings_GetByGroup had incomplete SELECT lists.
-- The DAL MapSetting mapper reads 7 columns (SettingId, SettingGroup, SettingKey,
-- SettingValue, DataType, Description, IsPublic) but both SPs were returning
-- fewer columns, causing SettingId, SettingGroup, and/or Description to always
-- be their default values (0 / null) at runtime.
--
-- Changes in this patch
-- ─────────────────────
-- 1. Settings_GetPublic  — full 7-column SELECT matching MapSetting
-- 2. Settings_GetByGroup — full 7-column SELECT matching MapSetting
--
-- Apply order: run once on local DB, then Railway staging / production.
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── 1. Settings_GetPublic ────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Settings_GetPublic //

CREATE PROCEDURE Settings_GetPublic()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsPublic = 1 AND IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //


-- ── 2. Settings_GetByGroup ───────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Settings_GetByGroup //

CREATE PROCEDURE Settings_GetByGroup(IN p_Group VARCHAR(50))
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  SettingGroup = p_Group AND IsDeleted = 0
    ORDER  BY SettingKey;
END //

DELIMITER ;

-- CALL Settings_GetPublic();
-- CALL Settings_GetByGroup('AUTH');

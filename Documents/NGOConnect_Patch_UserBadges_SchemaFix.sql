-- ============================================================
-- PATCH: UserBadges — Schema Fix (CRITICAL — fixes 0 KPIs bug)
-- Date   : 2026-08-01
-- Apply  : Railway Staging → Railway Production (local DB optional)
--
-- Root cause of the bug
-- ─────────────────────
-- The UserBadges table was created with the OLD schema:
--   BadgeType VARCHAR(50) NOT NULL   ← legacy
--   AwardedByUserId INT UNSIGNED NOT NULL  ← legacy
--   (no BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, CreatedAt)
--
-- The badge patch applied on 2026-08-01 added Application_GetByProject
-- with this subquery:
--   FROM UserBadges ub
--   JOIN LookupValues lv2 ON ub.BadgeLkpId = lv2.LookupValueId  ← MISSING
--   WHERE ub.UserId = pa.UserId AND ub.ProjectId = pa.ProjectId  ← MISSING
--
-- MySQL raises "Unknown column 'ub.BadgeLkpId'" on EVERY call to
-- Application_GetByProject. The C# catch block returns INTERNAL_ERROR.
-- The frontend sees isSuccess=0 and skips setting apps[] → ALL KPI
-- boxes show 0, Participants section shows empty, for every project.
--
-- Same columns missing from UserBadge_Award insert and User_GetBadges.
--
-- Fix
-- ───
-- ALTER TABLE: add the missing columns, relax NOT NULL on old ones
-- so new SP INSERTs (which omit BadgeType / AwardedByUserId) succeed.
-- No SP changes needed — all SPs already reference the new column names.
-- ============================================================

USE ngoconnect;

-- ============================================================
-- PART 1: Safe conditional ALTER TABLE
-- ─────────────────────────────────────
-- Uses a helper procedure to check INFORMATION_SCHEMA before
-- each ADD COLUMN — safe to re-run on a DB that already has
-- some or all of these columns from a prior partial apply.
-- ============================================================

DROP PROCEDURE IF EXISTS _patch_userbadges_schema;

DELIMITER //
CREATE PROCEDURE _patch_userbadges_schema()
BEGIN
    -- ── Relax old NOT NULL columns (MODIFY is always safe to re-run) ──
    ALTER TABLE UserBadges
      MODIFY COLUMN BadgeType       VARCHAR(50)  NULL DEFAULT '',
      MODIFY COLUMN AwardedByUserId INT UNSIGNED NULL;

    -- ── Add BadgeLkpId if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND COLUMN_NAME = 'BadgeLkpId'
    ) THEN
        ALTER TABLE UserBadges ADD COLUMN BadgeLkpId INT UNSIGNED NULL AFTER UserId;
    END IF;

    -- ── Add AwardedBy if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND COLUMN_NAME = 'AwardedBy'
    ) THEN
        ALTER TABLE UserBadges ADD COLUMN AwardedBy INT UNSIGNED NULL AFTER BadgeLkpId;
    END IF;

    -- ── Add AwardedByOrgId if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND COLUMN_NAME = 'AwardedByOrgId'
    ) THEN
        ALTER TABLE UserBadges ADD COLUMN AwardedByOrgId INT UNSIGNED NULL AFTER AwardedBy;
    END IF;

    -- ── Add ProjectId if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND COLUMN_NAME = 'ProjectId'
    ) THEN
        ALTER TABLE UserBadges ADD COLUMN ProjectId INT UNSIGNED NULL AFTER AwardedByOrgId;
    END IF;

    -- ── Add CreatedAt if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND COLUMN_NAME = 'CreatedAt'
    ) THEN
        ALTER TABLE UserBadges ADD COLUMN CreatedAt DATETIME NULL DEFAULT CURRENT_TIMESTAMP;
    END IF;

    -- ── Add indexes if missing ──
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND INDEX_NAME = 'idx_badge_lkpid'
    ) THEN
        ALTER TABLE UserBadges ADD INDEX idx_badge_lkpid (BadgeLkpId);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserBadges' AND INDEX_NAME = 'idx_badge_project'
    ) THEN
        ALTER TABLE UserBadges ADD INDEX idx_badge_project (ProjectId, UserId);
    END IF;
END //
DELIMITER ;

CALL _patch_userbadges_schema();
DROP PROCEDURE IF EXISTS _patch_userbadges_schema;

-- Verify schema
SELECT 'UserBadges schema fix applied. Participants will now load correctly.' AS Result;
DESCRIBE UserBadges;

-- ============================================================
-- PART 2: Fix User_GetBadges SP
-- ─────────────────────────────
-- Old SP returned ub.BadgeType AS BadgeCode (raw VARCHAR from
-- legacy schema). New SP joins LookupValues to return the correct
-- ValueCode (STAR_VOL, TEAM_PLAYER, TOP_PERFORM) so the mobile
-- ImpactScreen BADGE_META map resolves the right emoji and color.
-- ============================================================

DROP PROCEDURE IF EXISTS User_GetBadges;

DELIMITER //
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        ub.BadgeLkpId,
        lv.ValueName  AS BadgeName,
        lv.ValueCode  AS BadgeCode,
        o.OrgName,
        p.ProjectName,
        ub.CreatedAt  AS AwardedAt
    FROM UserBadges ub
    JOIN  LookupValues  lv ON ub.BadgeLkpId    = lv.LookupValueId
    LEFT JOIN Organisations o  ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects     p  ON ub.ProjectId       = p.ProjectId
    WHERE ub.UserId    = p_UserId
      AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC;
END //
DELIMITER ;

SELECT 'User_GetBadges SP updated — BadgeCode now uses LookupValues.ValueCode.' AS Result;

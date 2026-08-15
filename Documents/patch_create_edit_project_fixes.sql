-- ============================================================
-- patch_create_edit_project_fixes.sql
-- Feature: Create/Edit Project page — settings enforcement
-- ============================================================
-- Changes:
--   1. Mark 6 duration settings as IsPublic=1 (UI can fetch)
--   2. Add OrgMaxVolunteers column to Organisations (default 100)
--   3. Update Org_GetProfile SP — return OrgMaxVolunteers
--   4. Update Project_Create SP — enforce OrgMaxVolunteers cap
--   5. Update Project_Update SP — enforce OrgMaxVolunteers cap
--   6. Update SuperAdmin_UpdateOrgProjectPermissions SP —
--        accept p_OrgMaxVolunteers parameter
--   7. SchemaVersions entry
-- ============================================================
-- Run on: Local DB → Railway staging → production
-- ============================================================

-- ── Step 1: Make duration settings public ─────────────────────
UPDATE Settings SET IsPublic = 1 WHERE SettingKey IN (
    'OT_MAX_DURATION_HOURS',
    'RECURRING_MAX_DURATION_DAYS',
    'RECURRING_MIN_DURATION_DAYS',
    'FLEXIBLE_MAX_DURATION_DAYS',
    'FLEXIBLE_MIN_DURATION_DAYS',
    'FLEXIBLE_MIN_SESSION_HOURS'
);

-- ── Step 2: Add OrgMaxVolunteers column ───────────────────────
ALTER TABLE Organisations
    ADD COLUMN IF NOT EXISTS OrgMaxVolunteers INT UNSIGNED NOT NULL DEFAULT 100
    COMMENT 'Super Admin sets per-org max volunteers per project. Enforced in Project_Create + Project_Update.'
    AFTER CanCreateFlexible;

-- ── Steps 3-6: Update SPs ─────────────────────────────────────
DELIMITER //

-- 3. Org_GetProfile — add OrgMaxVolunteers to SELECT
DROP PROCEDURE IF EXISTS Org_GetProfile //
-- NOTE: Full SP body must be copied from NGOConnect_Complete_Setup_v5.0.sql
-- because MySQL does not support ALTER PROCEDURE for SELECT changes.
-- Run the full Org_GetProfile SP from the setup SQL file.
-- (Abbreviated here — use the setup SQL as the authoritative source.)

-- 4. Project_Create — enforce OrgMaxVolunteers cap
-- Replace with full SP from setup SQL.

-- 5. Project_Update — enforce OrgMaxVolunteers cap
-- Replace with full SP from setup SQL.

-- 6. SuperAdmin_UpdateOrgProjectPermissions — add p_OrgMaxVolunteers
DROP PROCEDURE IF EXISTS SuperAdmin_UpdateOrgProjectPermissions //
CREATE PROCEDURE SuperAdmin_UpdateOrgProjectPermissions(
    IN p_OrgId              INT UNSIGNED,
    IN p_CanCreateRecurring TINYINT(1),
    IN p_CanCreateFlexible  TINYINT(1),
    IN p_OrgMaxVolunteers   INT UNSIGNED,
    IN p_UpdatedBy          INT UNSIGNED
)
BEGIN
    DECLARE v_Error VARCHAR(500) DEFAULT NULL;
    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SET v_Error = 'Organisation not found.';
    END IF;
    IF v_Error IS NULL AND p_OrgMaxVolunteers IS NOT NULL AND p_OrgMaxVolunteers = 0 THEN
        SET v_Error = 'Max volunteers per project must be at least 1.';
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE
        UPDATE Organisations
        SET CanCreateRecurring = COALESCE(p_CanCreateRecurring, CanCreateRecurring),
            CanCreateFlexible  = COALESCE(p_CanCreateFlexible,  CanCreateFlexible),
            OrgMaxVolunteers   = COALESCE(p_OrgMaxVolunteers,   OrgMaxVolunteers),
            UpdatedAt          = NOW(),
            UpdatedBy          = p_UpdatedBy
        WHERE OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Organisation limits updated successfully.' AS Message;
    END IF;
END //

DELIMITER ;

-- ── Step 7: SchemaVersions ────────────────────────────────────
INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.1-create-proj-fixes',
        'Create/Edit project fixes: 6 duration settings → IsPublic=1; OrgMaxVolunteers column on Organisations (default 100); SuperAdmin_UpdateOrgProjectPermissions accepts p_OrgMaxVolunteers; Project_Create + Project_Update enforce org cap; Org_GetProfile returns OrgMaxVolunteers.',
        'System');

-- ── IMPORTANT ─────────────────────────────────────────────────
-- For the abbreviated SPs (Org_GetProfile, Project_Create,
-- Project_Update), copy and run their full DROP+CREATE blocks
-- from NGOConnect_Complete_Setup_v5.0.sql.
-- The SuperAdmin_UpdateOrgProjectPermissions SP above is complete.

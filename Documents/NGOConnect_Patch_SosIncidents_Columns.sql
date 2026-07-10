-- =============================================================================
-- Patch: SosIncidents — add v4.2 columns missing from v4.1 schema
--
-- Problem: The v4.2 setup SQL added IsDeleted, CancelReason (and kept
--   ResolvedAt, ResolvedByLkpId) to SosIncidents. If the DB was created
--   from the v4.1 setup and never had the v4.2 complete script run, these
--   columns are missing, causing ALL SOS SPs that use IsDeleted to fail:
--     - Sos_GetActive    (community SOS card never shows)
--     - Sos_GetMyActive  (SosActiveScreen shows "No Active SOS")
--     - Sos_Resolve      (cannot resolve or cancel)
--
-- Fix: Uses a temporary helper procedure to add each column only if absent.
--   This is MySQL 8.0-compatible and safe to re-run multiple times.
--
-- Run this patch BEFORE running the app if SOS features are broken.
-- =============================================================================

USE ngoconnect;

DELIMITER //

-- ── Helper: add IsDeleted ────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS _patch_add_sos_isdeleted //
CREATE PROCEDURE _patch_add_sos_isdeleted()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'IsDeleted'
    ) THEN
        ALTER TABLE SosIncidents
            ADD COLUMN IsDeleted TINYINT(1) NOT NULL DEFAULT 0
            AFTER ResolvedByLkpId;
        SELECT 'SosIncidents.IsDeleted added.' AS PatchNote;
    ELSE
        SELECT 'SosIncidents.IsDeleted already exists — skipped.' AS PatchNote;
    END IF;
END //
CALL _patch_add_sos_isdeleted() //
DROP PROCEDURE IF EXISTS _patch_add_sos_isdeleted //

-- ── Helper: add CancelReason ─────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS _patch_add_sos_cancelreason //
CREATE PROCEDURE _patch_add_sos_cancelreason()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'CancelReason'
    ) THEN
        ALTER TABLE SosIncidents
            ADD COLUMN CancelReason TEXT NULL
            AFTER Description;
        SELECT 'SosIncidents.CancelReason added.' AS PatchNote;
    ELSE
        SELECT 'SosIncidents.CancelReason already exists — skipped.' AS PatchNote;
    END IF;
END //
CALL _patch_add_sos_cancelreason() //
DROP PROCEDURE IF EXISTS _patch_add_sos_cancelreason //

-- ── Helper: add ResolvedAt (safety — present in both v4.1 and v4.2, but verify) ──
DROP PROCEDURE IF EXISTS _patch_add_sos_resolvedat //
CREATE PROCEDURE _patch_add_sos_resolvedat()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'ResolvedAt'
    ) THEN
        ALTER TABLE SosIncidents
            ADD COLUMN ResolvedAt      DATETIME     NULL AFTER StatusLkpId,
            ADD COLUMN ResolvedByLkpId INT UNSIGNED NULL AFTER ResolvedAt;
        SELECT 'SosIncidents.ResolvedAt + ResolvedByLkpId added.' AS PatchNote;
    ELSE
        SELECT 'SosIncidents.ResolvedAt already exists — skipped.' AS PatchNote;
    END IF;
END //
CALL _patch_add_sos_resolvedat() //
DROP PROCEDURE IF EXISTS _patch_add_sos_resolvedat //

DELIMITER ;

DELIMITER //

-- ── Helper: add idx_sos_deleted index safely ──────────────────────────────────
DROP PROCEDURE IF EXISTS _patch_add_sos_idx //
CREATE PROCEDURE _patch_add_sos_idx()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND INDEX_NAME   = 'idx_sos_deleted'
    ) THEN
        ALTER TABLE SosIncidents ADD INDEX idx_sos_deleted (IsDeleted);
        SELECT 'SosIncidents.idx_sos_deleted index added.' AS PatchNote;
    ELSE
        SELECT 'SosIncidents.idx_sos_deleted already exists — skipped.' AS PatchNote;
    END IF;
END //
CALL _patch_add_sos_idx() //
DROP PROCEDURE IF EXISTS _patch_add_sos_idx //

DELIMITER ;

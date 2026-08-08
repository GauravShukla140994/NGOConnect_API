-- =============================================================================
-- NGOConnect_Patch_SosFix_GetById.sql
--
-- Fixes "No Active SOS" shown after SOS trigger or on SosActive screen.
--
-- Root causes (any one of these breaks the flow):
--   1. IsDeleted column missing from SosIncidents  → Sos_GetById throws MySQL error
--   2. Old Sos_GetById had INNER JOIN to Users table → returns 0 rows if join mismatches
--   3. Old Sos_GetById missing AlertTypeName        → UI shows undefined alert type name
--   4. Old Sos_GetById missing StatusName           → UI shows undefined status name
--
-- This patch (safe to re-run):
--   Step 1 — Adds IsDeleted, CancelReason, ResolvedAt, ResolvedByLkpId to SosIncidents
--             if they are missing (idempotent via INFORMATION_SCHEMA checks)
--   Step 2 — Replaces Sos_GetById with a robust version:
--             LEFT JOINs for all optional tables, AlertTypeName + StatusName added
--   Step 3 — Quick sanity SELECT to confirm SOS incidents in DB
-- =============================================================================

USE ngoconnect;

-- ── Step 1: Add missing columns to SosIncidents ──────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS _patch_sos_cols //
CREATE PROCEDURE _patch_sos_cols()
BEGIN
    -- IsDeleted
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'IsDeleted'
    ) THEN
        ALTER TABLE SosIncidents
            ADD COLUMN IsDeleted TINYINT(1) NOT NULL DEFAULT 0;
        SELECT 'IsDeleted column ADDED.' AS Step1_IsDeleted;
    ELSE
        SELECT 'IsDeleted already exists — OK.' AS Step1_IsDeleted;
    END IF;

    -- CancelReason
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'CancelReason'
    ) THEN
        ALTER TABLE SosIncidents ADD COLUMN CancelReason TEXT NULL;
        SELECT 'CancelReason column ADDED.' AS Step1_CancelReason;
    ELSE
        SELECT 'CancelReason already exists — OK.' AS Step1_CancelReason;
    END IF;

    -- ResolvedAt
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'SosIncidents'
          AND COLUMN_NAME  = 'ResolvedAt'
    ) THEN
        ALTER TABLE SosIncidents
            ADD COLUMN ResolvedAt      DATETIME     NULL,
            ADD COLUMN ResolvedByLkpId INT UNSIGNED NULL;
        SELECT 'ResolvedAt + ResolvedByLkpId ADDED.' AS Step1_ResolvedAt;
    ELSE
        SELECT 'ResolvedAt already exists — OK.' AS Step1_ResolvedAt;
    END IF;
END //
CALL _patch_sos_cols() //
DROP PROCEDURE IF EXISTS _patch_sos_cols //

DELIMITER ;

-- ── Step 2: Replace Sos_GetById with robust version ──────────────────────────
-- Key changes vs. v4.0:
--   - Removed INNER JOIN to Users table (was redundant, caused 0-row returns)
--   - Changed JOIN UserProfiles → LEFT JOIN (SOS incident still shows even if profile has edge cases)
--   - Added AlertTypeName (ValueName) — was missing, caused undefined in UI
--   - Added StatusName  (ValueName) — was missing
--   - Kept IsDeleted = 0 filter (safe now that Step 1 guaranteed the column exists)

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_GetById //
CREATE PROCEDURE Sos_GetById(
    IN p_SosIncidentId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED      -- kept for auth checks in future; currently unused in query
)
BEGIN
    -- Result set 1: incident details (single row)
    SELECT
        si.SosIncidentId,
        si.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS UserName,
        up.ProfilePhoto,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CancelReason,
        si.ResolvedAt,
        si.CancelledAt,
        si.CreatedAt,
        si.OrgId,
        o.OrgName
    FROM  SosIncidents si
    LEFT  JOIN UserProfiles  up  ON si.UserId          = up.UserId
                                AND up.IsDeleted        = 0
    LEFT  JOIN Organisations o   ON si.OrgId           = o.OrgId
    LEFT  JOIN LookupValues  atv ON si.AlertTypeLkpId  = atv.LookupValueId
    LEFT  JOIN LookupValues  sv  ON si.StatusLkpId     = sv.LookupValueId
    WHERE  si.SosIncidentId = p_SosIncidentId
      AND  si.IsDeleted     = 0;

    -- Result set 2: responders list
    SELECT
        sr.SosResponderId,
        sr.UserId,
        CONCAT(COALESCE(up2.FirstName,''), ' ', COALESCE(up2.LastName,'')) AS ResponderName,
        up2.ProfilePhoto,
        rv.ValueCode   AS ApprovalStatus,
        rv.ValueName   AS ApprovalStatusName,
        sr.RespondedAt,
        sr.CanViewLocation
    FROM  SosResponders  sr
    LEFT  JOIN UserProfiles  up2 ON sr.UserId              = up2.UserId
                                 AND up2.IsDeleted          = 0
    LEFT  JOIN LookupValues  rv  ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE  sr.SosIncidentId = p_SosIncidentId
    ORDER  BY sr.RespondedAt ASC;
END //

DELIMITER ;

-- ── Step 3: Sanity check — what's currently in SosIncidents? ─────────────────
SELECT
    si.SosIncidentId,
    si.UserId,
    sv.ValueCode   AS Status,
    si.IsDeleted,
    si.CreatedAt
FROM  SosIncidents si
LEFT  JOIN LookupValues sv ON si.StatusLkpId = sv.LookupValueId
ORDER BY si.CreatedAt DESC
LIMIT 10;

-- If the above SELECT fails with "Unknown column 'si.IsDeleted'",
-- Step 1 did not run — re-run this file from the top.

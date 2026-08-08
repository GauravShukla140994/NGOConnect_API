-- ============================================================
-- NGO Connect — Patch: Application_Apply SP Fix
-- Date   : 2026-07-13
-- Fixes  : Apply button "An error occurred" on HomeScreen Nearby Projects
--
-- ROOT CAUSE:
--   Railway DB has the OLD Application_Apply SP (from 04_SP_All_New_Modules.sql)
--   with parameter IN p_Note TEXT (no p_Motivation, no p_RequestedSessions).
--   ApplicationDal.cs calls it with p_Motivation + p_RequestedSessions →
--   MySQL throws "PROCEDURE does not have a parameter p_Motivation" →
--   caught by DAL catch block → "An error occurred." shown to user.
--
-- WHAT THIS PATCH DOES:
--   1. Adds RequestedSessions column to ProjectApplications if it is missing
--   2. Drops and recreates Application_Apply with correct parameters
--      p_Motivation + p_RequestedSessions (matching ApplicationDal.cs)
--
-- SAFE TO RUN MULTIPLE TIMES (DROP IF EXISTS + INFORMATION_SCHEMA check).
-- ============================================================

USE NGOConnect;

DELIMITER //

-- ── Step 1: Add RequestedSessions column if it does not exist ─────────────
CREATE PROCEDURE _Patch_AddRequestedSessions()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   INFORMATION_SCHEMA.COLUMNS
        WHERE  TABLE_SCHEMA = DATABASE()
          AND  TABLE_NAME   = 'ProjectApplications'
          AND  COLUMN_NAME  = 'RequestedSessions'
    ) THEN
        ALTER TABLE ProjectApplications
            ADD COLUMN RequestedSessions VARCHAR(200) NULL AFTER Motivation;
    END IF;
END //

DELIMITER ;
CALL _Patch_AddRequestedSessions();
DROP PROCEDURE IF EXISTS _Patch_AddRequestedSessions;

-- ── Step 2: Recreate Application_Apply with correct parameter names ────────
DELIMITER //

DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_Exists      INT DEFAULT 0;
    DECLARE v_StatusLkpId INT UNSIGNED DEFAULT 0;

    -- Prevent duplicate application
    SELECT COUNT(*) INTO v_Exists
    FROM   ProjectApplications
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already applied to this project.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'
        LIMIT  1;

        IF v_StatusLkpId = 0 THEN
            SET v_StatusLkpId = 1; -- fallback guard
        END IF;

        INSERT INTO ProjectApplications
            (ProjectId, UserId, Motivation, RequestedSessions, StatusLkpId, CreatedBy)
        VALUES
            (p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions, v_StatusLkpId, p_UserId);

        SELECT 1 AS IsSuccess, 'Application submitted successfully.' AS Message,
               LAST_INSERT_ID() AS ApplicationId;
    END IF;
END //

DELIMITER ;

-- ── Verify ────────────────────────────────────────────────────────────────
-- Run these after applying to confirm the fix:
--
-- SELECT PARAM_NAME, DATA_TYPE
-- FROM   INFORMATION_SCHEMA.PARAMETERS
-- WHERE  SPECIFIC_SCHEMA = DATABASE()
--   AND  SPECIFIC_NAME   = 'Application_Apply'
-- ORDER  BY ORDINAL_POSITION;
-- Expected: p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions
--
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ProjectApplications'
--   AND COLUMN_NAME = 'RequestedSessions';
-- Expected: 1 row

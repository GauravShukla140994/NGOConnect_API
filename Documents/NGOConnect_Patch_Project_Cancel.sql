-- ============================================================
-- NGOConnect Patch: Project_Cancel SP
-- Also patches Projects table to add CancelReason / CancelledBy columns
-- Run against: ngodb (any environment)
-- Date: 2026-07-05
-- ============================================================

DELIMITER //

-- ── 1. Add cancel columns to Projects table (idempotent) ──────────────────────
DROP PROCEDURE IF EXISTS _AddColumnIfNotExists //
CREATE PROCEDURE _AddColumnIfNotExists(
    IN p_table VARCHAR(100),
    IN p_col   VARCHAR(100),
    IN p_def   VARCHAR(500)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_col
    ) THEN
        SET @sql = CONCAT('ALTER TABLE ', p_table, ' ADD COLUMN ', p_col, ' ', p_def);
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END //

CALL _AddColumnIfNotExists('Projects', 'CancelReason',  'TEXT NULL') //
CALL _AddColumnIfNotExists('Projects', 'CancelledBy',   'INT UNSIGNED NULL') //
CALL _AddColumnIfNotExists('Projects', 'CancelledAt',   'DATETIME NULL') //
CALL _AddColumnIfNotExists('Projects', 'ImpactSummary', 'TEXT NULL') //
CALL _AddColumnIfNotExists('Projects', 'TotalHours',    'INT UNSIGNED NULL DEFAULT 0') //
CALL _AddColumnIfNotExists('Projects', 'TotalVolunteers','INT UNSIGNED NULL DEFAULT 0') //

DROP PROCEDURE IF EXISTS _AddColumnIfNotExists //

-- ── 2. Project_Cancel SP ──────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_Cancel //

CREATE PROCEDURE Project_Cancel(
    IN p_ProjectId   INT UNSIGNED,
    IN p_UserId      INT UNSIGNED,
    IN p_CancelReason TEXT
)
BEGIN
    DECLARE v_CancelledStatusId INT UNSIGNED;

    -- Resolve CANCELLED status LkpId
    SELECT lv.LookupValueId INTO v_CancelledStatusId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'
    LIMIT 1;

    IF v_CancelledStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project status lookup not found.' AS Message;
    ELSEIF NOT EXISTS (
        SELECT 1 FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0
    ) THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        UPDATE Projects
        SET
            StatusLkpId  = v_CancelledStatusId,
            CancelReason = p_CancelReason,
            CancelledBy  = p_UserId,
            CancelledAt  = NOW(),
            UpdatedAt    = NOW(),
            UpdatedBy    = p_UserId
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project cancelled successfully.' AS Message;
    END IF;
END //

-- ── 3. Project_List — ensure cancel+impact fields are returned ────────────────
-- NOTE: Run this only if your existing Project_List SP does not already return
-- CancelReason, CancelledAt, CancelledBy, ImpactSummary, TotalHours, TotalVolunteers.
-- If your SP already returns them, skip sections marked [SKIP IF EXISTS].
--
-- Example minimal Project_List SP that includes the new fields:
DROP PROCEDURE IF EXISTS Project_List //

CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        p.Title,
        p.Description,
        lt_type.ValueCode   AS ProjectTypeCode,
        lt_type.ValueName   AS CategoryName,
        lt_status.ValueCode AS StatusCode,
        lt_status.ValueName AS StatusName,
        p.MaxVolunteers,
        p.ScheduleType,
        p.RecurrenceDays,
        p.StartDate,
        p.EndDate,
        p.StartTime,
        p.EndTime,
        p.DurationMinutes,
        p.City,
        p.Address,
        p.LocationName,
        p.Latitude,
        p.Longitude,
        p.IsPublic,
        p.RequiresApproval,
        p.CoverImageUrl,
        -- Cancel info
        p.CancelReason,
        p.CancelledAt,
        u_cancel.FullName   AS CancelledByName,
        -- Completion info
        p.ImpactSummary,
        p.TotalHours,
        p.TotalVolunteers,
        -- Live counts
        (SELECT COUNT(*) FROM ProjectApplications pa
         WHERE pa.ProjectId = p.ProjectId AND pa.StatusCode = 'APPROVED') AS ApprovedCount,
        -- Schedule summary (computed)
        CASE p.ScheduleType
            WHEN 'ONE_TIME'   THEN DATE_FORMAT(p.StartDate, '%b %d, %Y')
            WHEN 'RECURRING'  THEN CONCAT('Recurring · ', p.RecurrenceDays, ' · ',
                                    DATE_FORMAT(p.StartDate,'%b %Y'), '–', DATE_FORMAT(p.EndDate,'%b %Y'))
            WHEN 'FLEXIBLE'   THEN CONCAT('Flexible · ', DATE_FORMAT(p.StartDate,'%b %d'), '–', DATE_FORMAT(p.EndDate,'%b %d, %Y'))
            ELSE 'Flexible'
        END AS ScheduleSummary,
        p.CreatedAt
    FROM Projects p
    JOIN Organisations o        ON p.OrgId          = o.OrgId
    LEFT JOIN LookupValues lt_type   ON p.ProjectTypeLkpId = lt_type.LookupValueId
    LEFT JOIN LookupValues lt_status ON p.StatusLkpId      = lt_status.LookupValueId
    LEFT JOIN Users u_cancel         ON p.CancelledBy       = u_cancel.UserId
    WHERE p.IsDeleted = 0
      AND (p_OrgId      IS NULL OR p.OrgId     = p_OrgId)
      AND (p_City       IS NULL OR p.City       LIKE CONCAT('%', p_City, '%'))
      AND (p_StatusCode IS NULL OR lt_status.ValueCode = p_StatusCode)
      AND (p_TypeCode   IS NULL OR lt_type.ValueCode   = p_TypeCode)
      AND (p_Category   IS NULL OR lt_type.ValueName LIKE CONCAT('%', p_Category, '%'))
    ORDER BY p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- TotalCount (second result set for paged response)
    SELECT COUNT(*) AS TotalCount
    FROM Projects p
    LEFT JOIN LookupValues lt_type   ON p.ProjectTypeLkpId = lt_type.LookupValueId
    LEFT JOIN LookupValues lt_status ON p.StatusLkpId      = lt_status.LookupValueId
    WHERE p.IsDeleted = 0
      AND (p_OrgId      IS NULL OR p.OrgId     = p_OrgId)
      AND (p_City       IS NULL OR p.City       LIKE CONCAT('%', p_City, '%'))
      AND (p_StatusCode IS NULL OR lt_status.ValueCode = p_StatusCode)
      AND (p_TypeCode   IS NULL OR lt_type.ValueCode   = p_TypeCode)
      AND (p_Category   IS NULL OR lt_type.ValueName LIKE CONCAT('%', p_Category, '%'));
END //

DELIMITER ;

-- ============================================================
-- patch_hotfix_projects_v51_columns.sql
-- HOTFIX: Railway Projects table missing v5.1 columns.
-- These exist in setup SQL but the ALTER was never run on Railway.
-- Run IMMEDIATELY on Railway staging + production to fix:
--   "Unknown column 'MinAttendPct' in 'field list'"
--
-- Safe to re-run: ALTER TABLE ... ADD COLUMN IF NOT EXISTS
-- ============================================================

ALTER TABLE Projects
    ADD COLUMN IF NOT EXISTS MinAttendPct    DECIMAL(5,2) NULL COMMENT '% attendance required for cert eligibility',
    ADD COLUMN IF NOT EXISTS MaxDailyHours   DECIMAL(4,2) NULL COMMENT 'FLEXIBLE: max hours per day cap',
    ADD COLUMN IF NOT EXISTS MinSessionHours DECIMAL(4,2) NULL COMMENT 'Min session hours to count as attended';

-- Verify:
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_NAME = 'Projects' AND COLUMN_NAME IN ('MinAttendPct','MaxDailyHours','MinSessionHours');
-- Expected: 3 rows.

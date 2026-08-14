-- ============================================================
-- patch_attendance_defaults.sql
-- v5.1 — Attendance Rule System Defaults
-- Run on: local → Railway staging → Railway production
-- ============================================================

-- Add two new PUBLIC settings so the mobile CreateProject
-- screen can fetch them via GET /api/v1/settings/public and
-- use them as minimum-floor values for per-project overrides.

INSERT IGNORE INTO Settings
  (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
  ('PROJECT', 'DEFAULT_MIN_ATTEND_PCT',  '70', 'NUMBER',
   'System default: min % of sessions a volunteer must attend to earn a certificate (RECURRING/FLEXIBLE). Admins can raise this per project but not lower below this value.',
   1),
  ('PROJECT', 'DEFAULT_MAX_DAILY_HOURS', '8',  'NUMBER',
   'System default: max hours a volunteer can log per day on FLEXIBLE projects. Admins can raise this per project but not lower below this value.',
   1);

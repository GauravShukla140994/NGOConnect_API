-- ─────────────────────────────────────────────────────────────────────────────
-- cleanup_legacy_profile_update_notifications.sql
-- One-time DATA cleanup — NOT a schema/SP patch. No DROP/CREATE PROCEDURE here.
--
-- Background: before the 2026-08-23 notification-dedup fix
-- (patch_profile_update_notification_fix.sql), SuperAdmin_User_RequestUpdate
-- inserted a Notifications row with the real admin-typed reason under
-- NotifType='PROFILE_UPDATE_REQUESTED', while SuperAdminDal.cs's
-- RequestMemberUpdateAsync ALSO inserted a second row under a DIFFERENT type,
-- NotifType='PROFILE_UPDATE_REQUIRED', with generic hardcoded text:
--   "Please review and update your profile to continue using NGO Connect."
--
-- User_GetProfile's new ProfileUpdateReason subquery reads the LATEST
-- Notifications.Body where NotifType='PROFILE_UPDATE_REQUIRED' — so for any
-- user whose "Request update" happened before the fix shipped, it surfaces
-- that old generic text instead of the real reason (which is stuck under the
-- old, now-unused type string).
--
-- This script:
--   1. Deletes the old generic-text duplicate rows (exact Body match — safe,
--      won't touch any row with real content).
--   2. Renames any surviving PROFILE_UPDATE_REQUESTED rows (the ones with the
--      real reason) to the new canonical PROFILE_UPDATE_REQUIRED type, so
--      they become visible to both the ProfileUpdateReason subquery and the
--      app's notification-tap routing.
--
-- Safe to re-run — step 1 has nothing left to delete after first run, step 2
-- has nothing left to rename after first run.
-- Apply: local DB first → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

-- NOTE: SQL_SAFE_UPDATES is disabled for these two statements because neither
-- WHERE clause references a KEY column (NotificationId) — MySQL Workbench's
-- safe mode requires one. Re-enabled immediately after (same pattern used in
-- NGOConnect_Patch_HoursLogged.sql).
SET SQL_SAFE_UPDATES = 0;

-- Step 1: remove the old duplicate rows with the generic hardcoded body.
DELETE FROM Notifications
WHERE NotifType = 'PROFILE_UPDATE_REQUIRED'
  AND Body = 'Please review and update your profile to continue using NGO Connect.';

-- Step 2: normalise any surviving legacy-typed rows (the ones carrying the
-- REAL admin reason) onto the current canonical NotifType.
UPDATE Notifications
SET NotifType = 'PROFILE_UPDATE_REQUIRED'
WHERE NotifType = 'PROFILE_UPDATE_REQUESTED';

SET SQL_SAFE_UPDATES = 1;

-- Verify
SELECT
    (SELECT COUNT(*) FROM Notifications WHERE NotifType = 'PROFILE_UPDATE_REQUESTED') AS RemainingLegacyRows,
    (SELECT COUNT(*) FROM Notifications WHERE NotifType = 'PROFILE_UPDATE_REQUIRED')  AS TotalCanonicalRows;

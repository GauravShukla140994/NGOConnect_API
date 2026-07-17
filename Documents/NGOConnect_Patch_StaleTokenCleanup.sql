-- ============================================================
-- NGO Connect — Patch: Stale FCM Token Auto-Cleanup
-- Date   : 2026-07-17
--
-- PURPOSE:
--   Adds Notification_DeleteStaleToken SP.
--   Called automatically by FCMService when Firebase returns
--   MessagingErrorCode.Unregistered (NotRegistered) for a token.
--   Deletes the row from UserDeviceTokens so future fan-outs
--   don't waste FCM quota on dead registrations.
--
-- SAFE TO RUN MULTIPLE TIMES (DROP IF EXISTS).
-- ============================================================

USE NGOConnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Notification_DeleteStaleToken //
CREATE PROCEDURE Notification_DeleteStaleToken(IN p_Token VARCHAR(512))
BEGIN
    DELETE FROM UserDeviceTokens WHERE Token = p_Token;
END //

DELIMITER ;

-- ── Verify ────────────────────────────────────────────────────
-- SHOW PROCEDURE STATUS WHERE Db = DATABASE() AND Name = 'Notification_DeleteStaleToken';
-- Expected: 1 row

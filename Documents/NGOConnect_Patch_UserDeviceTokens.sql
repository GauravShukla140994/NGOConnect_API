-- ============================================================
-- NGO Connect — UserDeviceTokens Table Patch
-- Problem: NGOConnect_Patch_FCM_Notifications.sql created all
--          FCM SPs but omitted the CREATE TABLE statement.
--          Result: every device-token registration call returned
--          200 OK but silently failed (table did not exist).
-- Apply to: Railway Staging → Railway Production
-- Run BEFORE testing FCM push delivery.
-- ============================================================

-- Create the table if it doesn't already exist
CREATE TABLE IF NOT EXISTS UserDeviceTokens (
    DeviceTokenId INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    UserId        INT UNSIGNED     NOT NULL,
    Token         VARCHAR(512)     NOT NULL,
    Platform      VARCHAR(20)      NOT NULL DEFAULT 'ANDROID',
    CreatedAt     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt     DATETIME         NULL,
    PRIMARY KEY (DeviceTokenId),
    UNIQUE KEY uq_device_user_platform (UserId, Platform),
    INDEX idx_device_user (UserId),
    CONSTRAINT fk_devicetoken_user
        FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Re-apply Notification_SaveDeviceToken to confirm it targets the now-existing table
-- (safe to run even if the SP already exists on Railway)
DELIMITER //

DROP PROCEDURE IF EXISTS Notification_SaveDeviceToken //
CREATE PROCEDURE Notification_SaveDeviceToken(
    IN p_UserId   INT UNSIGNED,
    IN p_Token    VARCHAR(512),
    IN p_Platform VARCHAR(20)
)
BEGIN
    INSERT INTO UserDeviceTokens (UserId, Token, Platform, UpdatedAt)
    VALUES (p_UserId, p_Token, p_Platform, NOW())
    ON DUPLICATE KEY UPDATE Token = p_Token, UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Token saved.' AS Message;
END //

DELIMITER ;

-- ============================================================
-- Verification query — run after applying the patch:
--   SELECT COUNT(*) FROM UserDeviceTokens;
-- Should return 0 (empty but existing table).
-- Then open the app and register a device token via:
--   POST /api/v1/notifications/device-token
-- Then run:
--   SELECT * FROM UserDeviceTokens ORDER BY CreatedAt DESC LIMIT 5;
-- You should see a row with your FCM token.
-- ============================================================

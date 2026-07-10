-- ============================================================
-- NGO Connect — Patch: Project_GetSessionQr — Fix SP Parameter Mismatch
-- Version : v4.3 patch
-- Date    : 2026-07-07
-- Problem : SP was defined as (p_SessionId, p_QrCode, p_ExpiryMinutes)
--           but DAL calls it as (p_SessionId, p_UserId).
--           SP also relied on caller to supply the QR token (wrong pattern).
-- Fix     : SP now takes (p_SessionId, p_UserId), generates UUID internally,
--           uses 60-minute expiry (extend via Settings.QR_EXPIRY_MINUTES later).
-- Apply   : Run against NGOConnect database.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetSessionQr //
CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_QrCode     VARCHAR(100);
    DECLARE v_Expiry     INT DEFAULT 60;
    DECLARE v_RowsHit    INT DEFAULT 0;

    -- Generate a UUID-based token (no dashes, 32 chars)
    SET v_QrCode = REPLACE(UUID(), '-', '');

    -- Try to read expiry from Settings (optional — defaults to 60 min if not present)
    SELECT CAST(SettingValue AS UNSIGNED) INTO v_Expiry
    FROM Settings
    WHERE SettingKey = 'QR_EXPIRY_MINUTES'
    LIMIT 1;

    IF v_Expiry IS NULL OR v_Expiry = 0 THEN
        SET v_Expiry = 60;
    END IF;

    -- Stamp the QR code and expiry onto the session
    UPDATE ProjectSessions
    SET
        QrCode      = v_QrCode,
        QrExpiresAt = DATE_ADD(NOW(), INTERVAL v_Expiry MINUTE),
        UpdatedBy   = p_UserId,
        UpdatedAt   = NOW()
    WHERE SessionId = p_SessionId AND IsDeleted = 0;

    SET v_RowsHit = ROW_COUNT();

    IF v_RowsHit = 0 THEN
        SELECT 0 AS IsSuccess, 'Session not found or already deleted.' AS Message, NULL AS QrToken;
    ELSE
        SELECT 1 AS IsSuccess, 'QR generated.' AS Message, v_QrCode AS QrToken;
    END IF;
END //

DELIMITER ;

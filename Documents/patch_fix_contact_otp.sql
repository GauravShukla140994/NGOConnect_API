-- ══════════════════════════════════════════════════════════════════════════════
-- Patch: Fix Contact OTP SPs (Edit Profile — Add Phone / Add Email)
-- Date : 2026-08-24
-- Fixes:
--   1. User_SendContactOtp used 'CHANGE_MOBILE' lookup code which is not seeded.
--      Correct seeded values are ADD_PHONE (OrderNo 5) and ADD_EMAIL (OrderNo 6).
--      Both SPs now use ADD_PHONE / ADD_EMAIL consistently.
--   2. User_SendContactOtp had no uniqueness check — a phone/email already linked
--      to another account could be added. Now returns a clear error if taken.
-- Run order: standalone — no dependencies on other patches.
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── Step 1: Fix User_SendContactOtp ──────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_SendContactOtp //
CREATE PROCEDURE User_SendContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(20),
    IN p_Value     VARCHAR(150),
    IN p_OtpCode   VARCHAR(10),
    IN p_IpAddress VARCHAR(45)
)
BEGIN
    DECLARE v_PurposeLkpId  INT UNSIGNED;
    DECLARE v_RecentCount   INT DEFAULT 0;
    DECLARE v_ExpiryMins    INT DEFAULT 10;
    DECLARE v_AlreadyUsed   INT DEFAULT 0;

    -- Map type to OTP purpose (ADD_PHONE / ADD_EMAIL are the seeded values for this flow)
    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE'
      AND lv.ValueCode = IF(UPPER(p_Type) = 'EMAIL', 'ADD_EMAIL', 'ADD_PHONE')
    LIMIT 1;

    IF v_PurposeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid contact type.' AS Message;
    ELSE
        -- Uniqueness check: phone/email must not already belong to another account
        IF UPPER(p_Type) = 'EMAIL' THEN
            SELECT COUNT(*) INTO v_AlreadyUsed
            FROM Users
            WHERE Email = p_Value AND UserId != p_UserId AND IsDeleted = 0;
        ELSE
            SELECT COUNT(*) INTO v_AlreadyUsed
            FROM Users
            WHERE Mobile = p_Value AND UserId != p_UserId AND IsDeleted = 0;
        END IF;

        IF v_AlreadyUsed > 0 THEN
            SELECT 0 AS IsSuccess,
                   CONCAT(IF(UPPER(p_Type) = 'EMAIL', 'This email address', 'This phone number'),
                          ' is already linked to another account.') AS Message;
        ELSE
            -- Rate limit: max 3 per 10 min
            SELECT COUNT(*) INTO v_RecentCount
            FROM OtpTokens
            WHERE Recipient    = p_Value
              AND PurposeLkpId = v_PurposeLkpId
              AND CreatedAt   >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
              AND IsUsed       = 0;

            IF v_RecentCount >= 3 THEN
                SELECT 0 AS IsSuccess, 'Too many OTP requests. Please wait before trying again.' AS Message;
            ELSE
                -- Invalidate previous OTPs for this recipient + purpose
                UPDATE OtpTokens SET IsUsed = 1
                WHERE Recipient = p_Value AND PurposeLkpId = v_PurposeLkpId AND IsUsed = 0;

                INSERT INTO OtpTokens (UserId, Recipient, OtpCode, PurposeLkpId, IpAddress, ExpiresAt)
                VALUES (p_UserId, p_Value, p_OtpCode, v_PurposeLkpId, p_IpAddress,
                        DATE_ADD(NOW(), INTERVAL v_ExpiryMins MINUTE));

                SELECT 1 AS IsSuccess, 'OTP sent.' AS Message;
            END IF;
        END IF;
    END IF;
END //

-- ── Step 2: Fix User_VerifyContactOtp ────────────────────────────────────────

DROP PROCEDURE IF EXISTS User_VerifyContactOtp //
CREATE PROCEDURE User_VerifyContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(20),
    IN p_Value     VARCHAR(150),
    IN p_OtpCode   VARCHAR(10),
    IN p_IpAddress VARCHAR(45)
)
BEGIN
    DECLARE v_PurposeLkpId INT UNSIGNED;
    DECLARE v_OtpTokenId   INT UNSIGNED;
    DECLARE v_Attempts     TINYINT DEFAULT 0;
    DECLARE v_IsExpired    TINYINT DEFAULT 0;

    -- Map type to OTP purpose (must match what User_SendContactOtp used)
    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE'
      AND lv.ValueCode = IF(UPPER(p_Type) = 'EMAIL', 'ADD_EMAIL', 'ADD_PHONE')
    LIMIT 1;

    IF v_PurposeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid contact type.' AS Message;
    ELSE
        SELECT OtpTokenId, AttemptCount,
               IF(ExpiresAt < NOW(), 1, 0)
        INTO v_OtpTokenId, v_Attempts, v_IsExpired
        FROM OtpTokens
        WHERE Recipient    = p_Value
          AND PurposeLkpId = v_PurposeLkpId
          AND IsUsed       = 0
        ORDER BY CreatedAt DESC LIMIT 1;

        IF v_OtpTokenId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No OTP found. Please request a new one.' AS Message;
        ELSEIF v_IsExpired = 1 THEN
            UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;
            SELECT 0 AS IsSuccess, 'OTP has expired. Please request a new one.' AS Message;
        ELSEIF v_Attempts >= 3 THEN
            SELECT 0 AS IsSuccess, 'Too many incorrect attempts. Please request a new OTP.' AS Message;
        ELSE
            -- Verify code
            IF NOT EXISTS (
                SELECT 1 FROM OtpTokens WHERE OtpTokenId = v_OtpTokenId AND OtpCode = p_OtpCode
            ) THEN
                UPDATE OtpTokens SET AttemptCount = AttemptCount + 1 WHERE OtpTokenId = v_OtpTokenId;
                SELECT 0 AS IsSuccess, 'Invalid OTP.' AS Message;
            ELSE
                -- Mark used and update user contact
                UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;

                IF UPPER(p_Type) = 'EMAIL' THEN
                    UPDATE Users SET Email = p_Value, IsVerified = 1, UpdatedAt = NOW()
                    WHERE UserId = p_UserId;
                ELSE
                    UPDATE Users SET Mobile = p_Value, IsVerified = 1, UpdatedAt = NOW()
                    WHERE UserId = p_UserId;
                END IF;

                SELECT 1 AS IsSuccess, CONCAT(IF(UPPER(p_Type) = 'EMAIL', 'Email', 'Mobile'), ' updated successfully.') AS Message;
            END IF;
        END IF;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('patch-fix-contact-otp', 'Fix User_SendContactOtp/VerifyContactOtp: wrong OTP_PURPOSE lookup code (CHANGE_MOBILE→ADD_PHONE, CHANGE_EMAIL→ADD_EMAIL) + uniqueness check added.', 'System');

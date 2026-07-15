-- ============================================================
-- Patch: Auth_VerifyOTP — CountryCode fix
-- Issue: New users always got CountryCode = '+91' regardless
--        of which country they selected in the app.
-- Root cause: p_CountryCode param was missing from the SP;
--             '+91' was hardcoded in both INSERT branches.
-- Fix: Add p_CountryCode param (default '+91' for safety),
--      use it in both email and mobile INSERT statements.
-- Affects: staging + production
-- Date: 2026-07-15
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Auth_VerifyOTP //
CREATE PROCEDURE Auth_VerifyOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45),
    IN p_CountryCode   VARCHAR(6)
)
BEGIN
    DECLARE v_OtpTokenId     INT UNSIGNED DEFAULT 0;
    DECLARE v_StoredOtp      VARCHAR(6)   DEFAULT '';
    DECLARE v_AttemptCount   TINYINT      DEFAULT 0;
    DECLARE v_ExpiresAt      DATETIME;
    DECLARE v_UserId         INT UNSIGNED DEFAULT 0;
    DECLARE v_IsNewUser      TINYINT(1)   DEFAULT 0;

    -- Fetch the latest active OTP for this recipient + purpose
    SELECT OtpTokenId, OtpCode, AttemptCount, ExpiresAt
    INTO   v_OtpTokenId, v_StoredOtp, v_AttemptCount, v_ExpiresAt
    FROM   OtpTokens
    WHERE  Recipient    = p_Recipient
      AND  PurposeLkpId = p_PurposeLkpId
      AND  IsUsed       = 0
    ORDER  BY CreatedAt DESC
    LIMIT  1;

    -- Not found
    IF v_OtpTokenId = 0 THEN
        SELECT 0 AS IsSuccess,
               'OTP not found or has already been used. Please request a new OTP.' AS Message,
               0 AS UserId,
               0 AS IsNewUser;

    -- Max attempts exceeded
    ELSEIF v_AttemptCount >= 3 THEN
        SELECT 0 AS IsSuccess,
               'Maximum OTP attempts exceeded. Please request a new OTP.' AS Message,
               0 AS UserId,
               0 AS IsNewUser;

    -- OTP expired
    ELSEIF NOW() > v_ExpiresAt THEN
        UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;
        SELECT 0 AS IsSuccess,
               'OTP has expired. Please request a new OTP.' AS Message,
               0 AS UserId,
               0 AS IsNewUser;

    -- Wrong OTP code
    ELSEIF v_StoredOtp != p_OtpCode THEN
        UPDATE OtpTokens
        SET    AttemptCount = AttemptCount + 1
        WHERE  OtpTokenId   = v_OtpTokenId;

        SELECT 0 AS IsSuccess,
               'Invalid OTP. Please try again.' AS Message,
               0 AS UserId,
               0 AS IsNewUser;

    ELSE
        -- OTP is valid — mark as used
        UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;

        -- Check if user exists by mobile
        SELECT UserId INTO v_UserId
        FROM   Users
        WHERE  Mobile    = p_Recipient
          AND  IsDeleted = 0
        LIMIT  1;

        IF v_UserId = 0 THEN
            -- Try email match
            SELECT UserId INTO v_UserId
            FROM   Users
            WHERE  Email     = p_Recipient
              AND  IsDeleted = 0
            LIMIT  1;
        END IF;

        IF v_UserId = 0 THEN
            -- NEW USER — create user row with correct CountryCode
            IF p_Recipient LIKE '%@%' THEN
                INSERT INTO Users (Email, CountryCode, IsVerified)
                VALUES (p_Recipient, IFNULL(NULLIF(p_CountryCode, ''), '+91'), 1);
            ELSE
                INSERT INTO Users (Mobile, CountryCode, IsVerified)
                VALUES (p_Recipient, IFNULL(NULLIF(p_CountryCode, ''), '+91'), 1);
            END IF;

            SET v_UserId    = LAST_INSERT_ID();
            SET v_IsNewUser = 1;

            -- Empty profile — FirstName/LastName NOT NULL, filled later
            INSERT INTO UserProfiles (UserId, FirstName, LastName)
            VALUES (v_UserId, '', '');

        ELSE
            -- EXISTING USER — ensure verified
            UPDATE Users
            SET    IsVerified = 1,
                   UpdatedAt  = NOW()
            WHERE  UserId     = v_UserId;

            SET v_IsNewUser = 0;
        END IF;

        SELECT 1            AS IsSuccess,
               CASE WHEN v_IsNewUser = 1
                    THEN 'Registration successful. Welcome to NGO Connect!'
                    ELSE 'Login successful.'
               END           AS Message,
               v_UserId      AS UserId,
               v_IsNewUser   AS IsNewUser;
    END IF;
END //

DELIMITER ;

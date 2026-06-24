-- =============================================================================
-- NGO Connect — Stored Procedures: Auth Module
-- Run AFTER 01_Tables_Auth_User.sql
-- SPs: Auth_SendOTP, Auth_VerifyOTP, Auth_SaveRefreshToken,
--      Auth_GetRefreshToken, Auth_RevokeRefreshToken, Auth_RevokeRefreshTokenById
-- =============================================================================

DELIMITER //

-- ── Auth_SendOTP ──────────────────────────────────────────────────────────────
-- Called by: AuthDal.SendOtpAsync
-- Params: Recipient (mobile/email), CountryCode, OtpCode (6-digit from C#),
--         PurposeLkpId, IpAddress, ExpiryMinutes
-- Returns: IsSuccess INT, Message VARCHAR
-- Rate limit: max 3 OTPs per 10 min per Recipient+Purpose
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_SendOTP //
CREATE PROCEDURE Auth_SendOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_CountryCode   VARCHAR(5),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45),
    IN p_ExpiryMinutes INT
)
BEGIN
    DECLARE v_RecentCount INT DEFAULT 0;

    -- Rate limit: max 3 OTP requests in last 10 minutes for same recipient+purpose
    SELECT COUNT(*) INTO v_RecentCount
    FROM   OtpTokens
    WHERE  Recipient     = p_Recipient
      AND  PurposeLkpId  = p_PurposeLkpId
      AND  CreatedAt    >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
      AND  IsUsed        = 0;

    IF v_RecentCount >= 3 THEN
        SELECT 0 AS IsSuccess,
               'Too many OTP requests. Please wait 10 minutes before trying again.' AS Message;
    ELSE
        -- Invalidate all previous unused OTPs for this recipient + purpose
        UPDATE OtpTokens
        SET    IsUsed = 1
        WHERE  Recipient    = p_Recipient
          AND  PurposeLkpId = p_PurposeLkpId
          AND  IsUsed       = 0;

        -- Insert new OTP
        INSERT INTO OtpTokens (Recipient, CountryCode, OtpCode, PurposeLkpId, IpAddress, ExpiresAt)
        VALUES (
            p_Recipient,
            p_CountryCode,
            p_OtpCode,
            p_PurposeLkpId,
            p_IpAddress,
            DATE_ADD(NOW(), INTERVAL p_ExpiryMinutes MINUTE)
        );

        SELECT 1 AS IsSuccess, 'OTP generated successfully.' AS Message;
    END IF;
END //


-- ── Auth_VerifyOTP ────────────────────────────────────────────────────────────
-- Called by: AuthDal.VerifyOtpAsync
-- Params: Recipient, OtpCode (user-entered), PurposeLkpId, IpAddress
-- Returns: IsSuccess INT, Message VARCHAR, UserId INT, IsNewUser TINYINT
-- Logic: validates OTP → creates user if new → returns UserId
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_VerifyOTP //
CREATE PROCEDURE Auth_VerifyOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45)
)
BEGIN
    DECLARE v_OtpTokenId    INT UNSIGNED DEFAULT 0;
    DECLARE v_StoredOtp     VARCHAR(6)   DEFAULT '';
    DECLARE v_AttemptCount  TINYINT      DEFAULT 0;
    DECLARE v_ExpiresAt     DATETIME;
    DECLARE v_OtpCountryCode VARCHAR(5)  DEFAULT '+91';
    DECLARE v_UserId        INT UNSIGNED DEFAULT 0;
    DECLARE v_IsNewUser     TINYINT(1)   DEFAULT 0;
    DECLARE v_DefaultRoleId INT UNSIGNED DEFAULT 0;

    -- Fetch the latest active OTP for this recipient + purpose
    SELECT OtpTokenId, OtpCode, AttemptCount, ExpiresAt, CountryCode
    INTO   v_OtpTokenId, v_StoredOtp, v_AttemptCount, v_ExpiresAt, v_OtpCountryCode
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
        -- Increment attempt count before returning failure
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

        -- Check if user already exists (by mobile number)
        SELECT UserId INTO v_UserId
        FROM   Users
        WHERE  MobileNumber = p_Recipient
          AND  IsDeleted    = 0
        LIMIT  1;

        IF v_UserId = 0 THEN
            -- ── NEW USER ── Create user + empty profile
            -- Resolve default role: VOLUNTEER from LookupValues
            SELECT lv.LookupValueId INTO v_DefaultRoleId
            FROM   LookupValues  lv
            JOIN   LookupTypes   lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode   = 'USER_ROLE'
              AND  lv.ValueCode  = 'VOLUNTEER'
            LIMIT  1;

            -- Fallback if lookup not seeded yet
            IF v_DefaultRoleId = 0 THEN SET v_DefaultRoleId = 1; END IF;

            INSERT INTO Users (MobileNumber, CountryCode, RoleLkpId, IsVerified)
            VALUES (p_Recipient, v_OtpCountryCode, v_DefaultRoleId, 1);

            SET v_UserId    = LAST_INSERT_ID();
            SET v_IsNewUser = 1;

            -- Create empty profile row (prevents LEFT JOIN miss in User_GetProfile)
            INSERT INTO UserProfiles (UserId) VALUES (v_UserId);

        ELSE
            -- ── EXISTING USER ── ensure verified flag is set
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


-- ── Auth_SaveRefreshToken ─────────────────────────────────────────────────────
-- Called by: AuthDal (after VerifyOTP and RefreshToken)
-- Params: UserId, Token (SHA-256 hashed), DeviceInfo, IpAddress, ExpiresAt
-- Logic: Enforce max 5 concurrent sessions — drops oldest beyond limit
-- Returns: no result set (called via ExecuteNonQueryAsync)
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_SaveRefreshToken //
CREATE PROCEDURE Auth_SaveRefreshToken(
    IN p_UserId     INT UNSIGNED,
    IN p_Token      VARCHAR(512),
    IN p_DeviceInfo VARCHAR(500),
    IN p_IpAddress  VARCHAR(45),
    IN p_ExpiresAt  DATETIME
)
BEGIN
    -- Enforce max 5 concurrent active sessions per user
    -- Delete the oldest sessions beyond the 4 most recent (1 slot freed for the new token)
    DELETE FROM RefreshTokens
    WHERE  UserId     = p_UserId
      AND  IsRevoked  = 0
      AND  RefreshTokenId NOT IN (
            SELECT RefreshTokenId FROM (
                SELECT RefreshTokenId
                FROM   RefreshTokens
                WHERE  UserId    = p_UserId
                  AND  IsRevoked = 0
                ORDER  BY CreatedAt DESC
                LIMIT  4
            ) AS recent
        );

    -- Insert new refresh token
    INSERT INTO RefreshTokens (UserId, Token, DeviceInfo, IpAddress, ExpiresAt)
    VALUES (p_UserId, p_Token, p_DeviceInfo, p_IpAddress, p_ExpiresAt);
END //


-- ── Auth_GetRefreshToken ──────────────────────────────────────────────────────
-- Called by: AuthDal.RefreshTokenAsync
-- Params: Token (SHA-256 hashed)
-- Returns: IsSuccess, Message, UserId, Recipient, RefreshTokenId
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_GetRefreshToken //
CREATE PROCEDURE Auth_GetRefreshToken(
    IN p_Token VARCHAR(512)
)
BEGIN
    DECLARE v_TokenId     INT UNSIGNED DEFAULT 0;
    DECLARE v_UserId      INT UNSIGNED DEFAULT 0;
    DECLARE v_IsRevoked   TINYINT(1)   DEFAULT 0;
    DECLARE v_ExpiresAt   DATETIME;

    SELECT RefreshTokenId, UserId, IsRevoked, ExpiresAt
    INTO   v_TokenId, v_UserId, v_IsRevoked, v_ExpiresAt
    FROM   RefreshTokens
    WHERE  Token = p_Token
    LIMIT  1;

    IF v_TokenId = 0 THEN
        SELECT 0 AS IsSuccess, 'Invalid refresh token.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSEIF v_IsRevoked = 1 THEN
        SELECT 0 AS IsSuccess, 'Refresh token has been revoked.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSEIF NOW() > v_ExpiresAt THEN
        SELECT 0 AS IsSuccess, 'Refresh token has expired. Please login again.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSE
        SELECT 1                                                       AS IsSuccess,
               'Token valid.'                                          AS Message,
               u.UserId                                               AS UserId,
               COALESCE(u.Email, u.MobileNumber)                      AS Recipient,
               v_TokenId                                               AS RefreshTokenId
        FROM   Users u
        WHERE  u.UserId = v_UserId;
    END IF;
END //


-- ── Auth_RevokeRefreshToken ───────────────────────────────────────────────────
-- Called by: AuthDal.RevokeTokenAsync (logout)
-- Params: Token (SHA-256 hashed)
-- Returns: IsSuccess INT, Message VARCHAR
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_RevokeRefreshToken //
CREATE PROCEDURE Auth_RevokeRefreshToken(
    IN p_Token VARCHAR(512)
)
BEGIN
    UPDATE RefreshTokens
    SET    IsRevoked = 1
    WHERE  Token     = p_Token
      AND  IsRevoked = 0;

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'Token revoked successfully.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Token not found or already revoked.' AS Message;
    END IF;
END //


-- ── Auth_RevokeRefreshTokenById ───────────────────────────────────────────────
-- Called by: AuthDal.RevokeRefreshTokenByIdAsync (during token rotation)
-- Params: RefreshTokenId
-- Returns: no result set (called via ExecuteNonQueryAsync)
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_RevokeRefreshTokenById //
CREATE PROCEDURE Auth_RevokeRefreshTokenById(
    IN p_RefreshTokenId INT UNSIGNED
)
BEGIN
    UPDATE RefreshTokens
    SET    IsRevoked = 1
    WHERE  RefreshTokenId = p_RefreshTokenId;
END //


DELIMITER ;

-- ============================================================
-- NGOConnect Patch — User Contact Update Feature
-- Apply to: Railway staging + production
-- Date: 2026-07-12
-- Changes:
--   1. Seed ADD_PHONE + ADD_EMAIL into LookupValues (OTP_PURPOSE)
--   2. Create User_SendContactOtp SP
--   3. Create User_VerifyContactOtp SP
-- ============================================================

-- 1. Seed new OTP_PURPOSE lookup values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ADD_PHONE', 'Add Phone', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE'
ON DUPLICATE KEY UPDATE ValueName = VALUES(ValueName);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ADD_EMAIL', 'Add Email', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE'
ON DUPLICATE KEY UPDATE ValueName = VALUES(ValueName);

DELIMITER //

-- 2. User_SendContactOtp
DROP PROCEDURE IF EXISTS User_SendContactOtp //
CREATE PROCEDURE User_SendContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(10),    -- 'EMAIL' or 'PHONE'
    IN p_Value     VARCHAR(200),
    IN p_OtpCode   VARCHAR(6),
    IN p_IpAddress VARCHAR(45)
)
proc: BEGIN
    DECLARE v_PurposeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_DuplicateCount INT          DEFAULT 0;
    DECLARE v_RecentCount    INT          DEFAULT 0;
    DECLARE v_ValueCode      VARCHAR(20);

    IF p_Type = 'EMAIL' THEN
        SET v_ValueCode = 'ADD_EMAIL';
        SELECT COUNT(*) INTO v_DuplicateCount
        FROM Users
        WHERE Email = p_Value AND UserId != p_UserId AND IsDeleted = 0;
    ELSE
        SET v_ValueCode = 'ADD_PHONE';
        SELECT COUNT(*) INTO v_DuplicateCount
        FROM Users
        WHERE Mobile = p_Value AND UserId != p_UserId AND IsDeleted = 0;
    END IF;

    IF v_DuplicateCount > 0 THEN
        SELECT 0 AS IsSuccess, 'This contact is already registered with another account.' AS Message;
        LEAVE proc;
    END IF;

    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE' AND lv.ValueCode = v_ValueCode AND lv.IsDeleted = 0
    LIMIT 1;

    IF v_PurposeLkpId = 0 THEN
        SELECT 0 AS IsSuccess, 'OTP purpose not configured. Please contact support.' AS Message;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_RecentCount
    FROM OtpTokens
    WHERE Recipient    = p_Value
      AND PurposeLkpId = v_PurposeLkpId
      AND CreatedAt   >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
      AND IsUsed       = 0;

    IF v_RecentCount >= 3 THEN
        SELECT 0 AS IsSuccess, 'Too many OTP requests. Please wait 10 minutes before trying again.' AS Message;
        LEAVE proc;
    END IF;

    UPDATE OtpTokens
    SET    IsUsed = 1
    WHERE  Recipient    = p_Value
      AND  PurposeLkpId = v_PurposeLkpId
      AND  IsUsed       = 0;

    INSERT INTO OtpTokens (UserId, Recipient, OtpCode, PurposeLkpId, IpAddress, ExpiresAt)
    VALUES (p_UserId, p_Value, p_OtpCode, v_PurposeLkpId, p_IpAddress, DATE_ADD(NOW(), INTERVAL 10 MINUTE));

    SELECT 1 AS IsSuccess, 'OTP sent successfully.' AS Message;
END proc //

-- 3. User_VerifyContactOtp
DROP PROCEDURE IF EXISTS User_VerifyContactOtp //
CREATE PROCEDURE User_VerifyContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(10),    -- 'EMAIL' or 'PHONE'
    IN p_Value     VARCHAR(200),
    IN p_OtpCode   VARCHAR(6),
    IN p_IpAddress VARCHAR(45)
)
proc: BEGIN
    DECLARE v_PurposeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_OtpTokenId     INT UNSIGNED DEFAULT 0;
    DECLARE v_StoredOtp      VARCHAR(6)   DEFAULT '';
    DECLARE v_AttemptCount   TINYINT      DEFAULT 0;
    DECLARE v_ExpiresAt      DATETIME;
    DECLARE v_DuplicateCount INT          DEFAULT 0;
    DECLARE v_ValueCode      VARCHAR(20);

    IF p_Type = 'EMAIL' THEN
        SET v_ValueCode = 'ADD_EMAIL';
        SELECT COUNT(*) INTO v_DuplicateCount
        FROM Users
        WHERE Email = p_Value AND UserId != p_UserId AND IsDeleted = 0;
    ELSE
        SET v_ValueCode = 'ADD_PHONE';
        SELECT COUNT(*) INTO v_DuplicateCount
        FROM Users
        WHERE Mobile = p_Value AND UserId != p_UserId AND IsDeleted = 0;
    END IF;

    IF v_DuplicateCount > 0 THEN
        SELECT 0 AS IsSuccess, 'This contact is already registered with another account.' AS Message;
        LEAVE proc;
    END IF;

    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE' AND lv.ValueCode = v_ValueCode AND lv.IsDeleted = 0
    LIMIT 1;

    IF v_PurposeLkpId = 0 THEN
        SELECT 0 AS IsSuccess, 'OTP purpose not configured.' AS Message;
        LEAVE proc;
    END IF;

    SELECT OtpTokenId, OtpCode, AttemptCount, ExpiresAt
    INTO   v_OtpTokenId, v_StoredOtp, v_AttemptCount, v_ExpiresAt
    FROM   OtpTokens
    WHERE  Recipient    = p_Value
      AND  PurposeLkpId = v_PurposeLkpId
      AND  IsUsed       = 0
    ORDER  BY CreatedAt DESC
    LIMIT  1;

    IF v_OtpTokenId = 0 THEN
        SELECT 0 AS IsSuccess, 'OTP not found or already used. Please request a new OTP.' AS Message;
        LEAVE proc;
    END IF;

    IF v_AttemptCount >= 3 THEN
        SELECT 0 AS IsSuccess, 'Maximum OTP attempts exceeded. Please request a new OTP.' AS Message;
        LEAVE proc;
    END IF;

    IF NOW() > v_ExpiresAt THEN
        UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;
        SELECT 0 AS IsSuccess, 'OTP has expired. Please request a new OTP.' AS Message;
        LEAVE proc;
    END IF;

    IF v_StoredOtp != p_OtpCode THEN
        UPDATE OtpTokens SET AttemptCount = AttemptCount + 1 WHERE OtpTokenId = v_OtpTokenId;
        SELECT 0 AS IsSuccess, 'Invalid OTP. Please try again.' AS Message;
        LEAVE proc;
    END IF;

    UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;

    IF p_Type = 'EMAIL' THEN
        UPDATE Users SET Email = p_Value WHERE UserId = p_UserId AND IsDeleted = 0;
    ELSE
        UPDATE Users SET Mobile = p_Value WHERE UserId = p_UserId AND IsDeleted = 0;
    END IF;

    SELECT 1 AS IsSuccess, 'Contact verified and saved successfully.' AS Message;
END proc //

DELIMITER ;

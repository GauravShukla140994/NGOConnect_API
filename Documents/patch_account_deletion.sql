-- ─────────────────────────────────────────────────────────────────────────────
-- patch_account_deletion.sql
-- Feature: Account Deletion + 30-Day Revival Grace Period
--
-- Changes:
--   0. Unique key redesign on Users.Mobile + Users.Email
--      — drop simple unique (blocks re-registration after soft-delete)
--      — add generated columns (MobileActive / EmailActive) + unique on those
--      — result: only ONE active user per mobile/email enforced;
--        multiple soft-deleted rows with same mobile/email allowed
--   1. ALTER TABLE Users — add ScheduledDeletionAt DATETIME NULL
--   2. SP User_RequestAccountDeletion — sets ScheduledDeletionAt (30-day grace)
--   3. SP Auth_VerifyOTP — detects grace-period users, returns IsPendingDeletion=1
--   4. SP User_ReviveAccount — resets soft-delete within grace period
--
-- Safe to re-run (ALTER IF NOT EXISTS + DROP + CREATE are idempotent).
-- Apply to: local → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 0 — Conditional unique key for Mobile and Email
--   MySQL has no partial indexes, so we use VIRTUAL generated columns.
--   MobileActive = Mobile when IsDeleted=0, NULL when IsDeleted=1.
--   NULLs are never compared in UNIQUE indexes → multiple deleted rows allowed.
--   Same pattern for EmailActive.
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop old unconditional unique keys if they exist
ALTER TABLE Users DROP INDEX IF EXISTS uq_users_mobile;
ALTER TABLE Users DROP INDEX IF EXISTS uq_users_email;

-- Add generated columns + conditional unique indexes
ALTER TABLE Users
    ADD COLUMN IF NOT EXISTS MobileActive VARCHAR(20)
        GENERATED ALWAYS AS (IF(IsDeleted = 0, Mobile, NULL)) VIRTUAL,
    ADD COLUMN IF NOT EXISTS EmailActive VARCHAR(255)
        GENERATED ALWAYS AS (IF(IsDeleted = 0, Email, NULL)) VIRTUAL;

-- Add unique indexes on the generated columns (separate ALTER to avoid conflicts)
ALTER TABLE Users
    ADD UNIQUE KEY IF NOT EXISTS uq_users_mobile_active (MobileActive),
    ADD UNIQUE KEY IF NOT EXISTS uq_users_email_active  (EmailActive);

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1 — Add ScheduledDeletionAt column to Users
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE Users
    ADD COLUMN IF NOT EXISTS ScheduledDeletionAt DATETIME NULL DEFAULT NULL AFTER DeletedBy;

DELIMITER //

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2 — User_RequestAccountDeletion
--   1. Block if user is sole FOUNDER of any APPROVED org.
--   2. Soft-delete + set ScheduledDeletionAt = NOW() + 30 days + revoke tokens.
-- ─────────────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_RequestAccountDeletion //
CREATE PROCEDURE User_RequestAccountDeletion(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_SoleFounderOrgName VARCHAR(200) DEFAULT NULL;

    SELECT o.OrgName INTO v_SoleFounderOrgName
    FROM OrgMembers om
    JOIN LookupValues rv ON om.RoleLkpId    = rv.LookupValueId
    JOIN LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
    JOIN Organisations o ON om.OrgId        = o.OrgId
    JOIN LookupValues sv ON o.StatusLkpId   = sv.LookupValueId
    WHERE om.UserId     = p_UserId
      AND om.IsDeleted  = 0
      AND rt.TypeCode   = 'MEMBER_ROLE'
      AND rv.ValueCode  = 'FOUNDER'
      AND o.IsDeleted   = 0
      AND sv.ValueCode  = 'APPROVED'
      AND NOT EXISTS (
          SELECT 1
          FROM OrgMembers om2
          JOIN LookupValues rv2 ON om2.RoleLkpId    = rv2.LookupValueId
          JOIN LookupTypes  rt2 ON rv2.LookupTypeId = rt2.LookupTypeId
          WHERE om2.OrgId    = om.OrgId
            AND om2.UserId  != p_UserId
            AND om2.IsDeleted = 0
            AND rt2.TypeCode  = 'MEMBER_ROLE'
            AND rv2.ValueCode = 'FOUNDER'
      )
    LIMIT 1;

    IF v_SoleFounderOrgName IS NOT NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('You are the only Founder of "', v_SoleFounderOrgName,
                      '". Please transfer ownership or close the organisation before deleting your account.') AS Message,
               'SOLE_FOUNDER' AS ErrorCode;
    ELSE
        -- Soft-delete + 30-day grace window
        UPDATE Users
        SET IsDeleted           = 1,
            DeletedAt           = NOW(),
            DeletedBy           = p_UserId,
            ScheduledDeletionAt = DATE_ADD(NOW(), INTERVAL 30 DAY)
        WHERE UserId    = p_UserId
          AND IsDeleted = 0;

        -- Revoke all active refresh tokens immediately
        UPDATE RefreshTokens
        SET IsRevoked = 1,
            RevokedAt = NOW()
        WHERE UserId    = p_UserId
          AND IsRevoked = 0;

        SELECT 1 AS IsSuccess,
               'Your account has been scheduled for deletion. You have 30 days to sign back in and recover it.' AS Message,
               NULL AS ErrorCode;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3 — Auth_VerifyOTP (updated)
--   After the normal IsDeleted=0 lookups, also check for grace-period deleted
--   users. If found: still issue tokens but flag IsPendingDeletion=1 so the
--   mobile can intercept and offer account revival before navigating home.
-- ─────────────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Auth_VerifyOTP //
CREATE PROCEDURE Auth_VerifyOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45),
    IN p_CountryCode   VARCHAR(6)
)
BEGIN
    DECLARE v_OtpTokenId        INT UNSIGNED DEFAULT 0;
    DECLARE v_StoredOtp         VARCHAR(6)   DEFAULT '';
    DECLARE v_AttemptCount      TINYINT      DEFAULT 0;
    DECLARE v_ExpiresAt         DATETIME;
    DECLARE v_UserId            INT UNSIGNED DEFAULT 0;
    DECLARE v_IsNewUser         TINYINT(1)   DEFAULT 0;
    DECLARE v_IsPendingDeletion TINYINT(1)   DEFAULT 0;

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
               0 AS UserId, 0 AS IsNewUser, 0 AS IsPendingDeletion;

    -- Max attempts exceeded
    ELSEIF v_AttemptCount >= 3 THEN
        SELECT 0 AS IsSuccess,
               'Maximum OTP attempts exceeded. Please request a new OTP.' AS Message,
               0 AS UserId, 0 AS IsNewUser, 0 AS IsPendingDeletion;

    -- OTP expired
    ELSEIF NOW() > v_ExpiresAt THEN
        UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;
        SELECT 0 AS IsSuccess,
               'OTP has expired. Please request a new OTP.' AS Message,
               0 AS UserId, 0 AS IsNewUser, 0 AS IsPendingDeletion;

    -- Wrong OTP code
    ELSEIF v_StoredOtp != p_OtpCode THEN
        UPDATE OtpTokens
        SET    AttemptCount = AttemptCount + 1
        WHERE  OtpTokenId   = v_OtpTokenId;

        SELECT 0 AS IsSuccess,
               'Invalid OTP. Please try again.' AS Message,
               0 AS UserId, 0 AS IsNewUser, 0 AS IsPendingDeletion;

    ELSE
        -- OTP is valid — mark as used
        UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;

        -- 1. Look up active (non-deleted) user by mobile
        SELECT UserId INTO v_UserId
        FROM   Users
        WHERE  Mobile    = p_Recipient
          AND  IsDeleted = 0
        LIMIT  1;

        -- 2. Try email if mobile not found
        IF v_UserId = 0 THEN
            SELECT UserId INTO v_UserId
            FROM   Users
            WHERE  Email     = p_Recipient
              AND  IsDeleted = 0
            LIMIT  1;
        END IF;

        -- 3. Check for grace-period deleted user by mobile
        IF v_UserId = 0 THEN
            SELECT UserId INTO v_UserId
            FROM   Users
            WHERE  Mobile               = p_Recipient
              AND  IsDeleted            = 1
              AND  ScheduledDeletionAt  > NOW()
            LIMIT  1;

            IF v_UserId > 0 THEN
                SET v_IsPendingDeletion = 1;
            END IF;
        END IF;

        -- 4. Check for grace-period deleted user by email
        IF v_UserId = 0 THEN
            SELECT UserId INTO v_UserId
            FROM   Users
            WHERE  Email                = p_Recipient
              AND  IsDeleted            = 1
              AND  ScheduledDeletionAt  > NOW()
            LIMIT  1;

            IF v_UserId > 0 THEN
                SET v_IsPendingDeletion = 1;
            END IF;
        END IF;

        IF v_UserId = 0 THEN
            -- NEW USER — create user row
            IF p_Recipient LIKE '%@%' THEN
                INSERT INTO Users (Email, CountryCode, IsVerified)
                VALUES (p_Recipient, IFNULL(NULLIF(p_CountryCode, ''), '+91'), 1);
            ELSE
                INSERT INTO Users (Mobile, CountryCode, IsVerified)
                VALUES (p_Recipient, IFNULL(NULLIF(p_CountryCode, ''), '+91'), 1);
            END IF;

            SET v_UserId    = LAST_INSERT_ID();
            SET v_IsNewUser = 1;

            INSERT INTO UserProfiles (UserId, FirstName, LastName)
            VALUES (v_UserId, '', '');

        ELSEIF v_IsPendingDeletion = 0 THEN
            -- EXISTING ACTIVE USER — ensure verified
            UPDATE Users
            SET    IsVerified = 1,
                   UpdatedAt  = NOW()
            WHERE  UserId     = v_UserId;
        END IF;
        -- Note: grace-period users are NOT updated here — revival SP handles that

        SELECT 1                    AS IsSuccess,
               CASE
                   WHEN v_IsPendingDeletion = 1 THEN 'Account pending deletion.'
                   WHEN v_IsNewUser = 1         THEN 'Registration successful. Welcome to Ripple Hub!'
                   ELSE                              'Login successful.'
               END                  AS Message,
               v_UserId             AS UserId,
               v_IsNewUser          AS IsNewUser,
               v_IsPendingDeletion  AS IsPendingDeletion;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4 — User_ReviveAccount
--   Resets soft-delete within the 30-day grace window.
--   Also resets IsVerified=1 (was already 1 before deletion).
-- ─────────────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_ReviveAccount //
CREATE PROCEDURE User_ReviveAccount(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ScheduledDeletionAt DATETIME DEFAULT NULL;

    SELECT ScheduledDeletionAt INTO v_ScheduledDeletionAt
    FROM   Users
    WHERE  UserId = p_UserId AND IsDeleted = 1
    LIMIT  1;

    IF v_ScheduledDeletionAt IS NULL THEN
        SELECT 0 AS IsSuccess,
               'Account not found or not scheduled for deletion.' AS Message;

    ELSEIF v_ScheduledDeletionAt <= NOW() THEN
        SELECT 0 AS IsSuccess,
               'The 30-day recovery window has passed. This account has been permanently deleted.' AS Message;

    ELSE
        UPDATE Users
        SET IsDeleted           = 0,
            DeletedAt           = NULL,
            DeletedBy           = NULL,
            ScheduledDeletionAt = NULL,
            IsVerified          = 1,
            UpdatedAt           = NOW()
        WHERE UserId = p_UserId;

        SELECT 1 AS IsSuccess,
               'Welcome back! Your account has been fully restored.' AS Message;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5 — Auth_CreateFreshAccount
--   Called when a grace-period user taps "No thanks, start fresh".
--   Reads the old (soft-deleted) user's Mobile/Email/CountryCode and creates
--   a brand-new Users + UserProfiles row. The old row stays as IsDeleted=1
--   (audit trail). MobileActive generated column is NULL on the old row, so
--   the new row's uq_users_mobile_active unique key is satisfied cleanly.
-- ─────────────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Auth_CreateFreshAccount //
CREATE PROCEDURE Auth_CreateFreshAccount(IN p_OldUserId INT UNSIGNED)
BEGIN
    DECLARE v_Mobile      VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email       VARCHAR(150) DEFAULT NULL;
    DECLARE v_CountryCode VARCHAR(6)   DEFAULT '+91';
    DECLARE v_NewUserId   INT UNSIGNED DEFAULT 0;

    -- Pull contact info from the soft-deleted row
    SELECT Mobile, Email, CountryCode
    INTO   v_Mobile, v_Email, v_CountryCode
    FROM   Users
    WHERE  UserId    = p_OldUserId
      AND  IsDeleted = 1
    LIMIT  1;

    IF v_Mobile IS NULL AND v_Email IS NULL THEN
        SELECT 0 AS IsSuccess,
               'Original account not found or is not in a deleted state.' AS Message,
               NULL AS UserId;
    ELSE
        -- Create fresh Users row (IsVerified=1 — they just proved OTP ownership)
        INSERT INTO Users (Mobile, Email, CountryCode, IsVerified, IsActive)
        VALUES (v_Mobile, v_Email, v_CountryCode, 1, 1);

        SET v_NewUserId = LAST_INSERT_ID();

        INSERT INTO UserProfiles (UserId, FirstName, LastName)
        VALUES (v_NewUserId, '', '');

        SELECT 1           AS IsSuccess,
               'Fresh account created. Welcome!' AS Message,
               v_NewUserId AS UserId;
    END IF;
END //

DELIMITER ;

SELECT 'patch_account_deletion applied successfully.' AS Status;

-- Verify:
-- SHOW INDEX FROM Users WHERE Key_name IN ('uq_users_mobile_active','uq_users_email_active');
--   → should show 2 rows (generated column indexes)
-- CALL User_RequestAccountDeletion(<userId>);         → IsSuccess=1, ScheduledDeletionAt set
-- CALL User_ReviveAccount(<userId>);                  → IsSuccess=1, account restored
-- CALL Auth_VerifyOTP('<mobile>', '<otp>', 1, '127.0.0.1', '+91');
--   → active user:       IsSuccess=1, IsPendingDeletion=0
--   → grace-period user: IsSuccess=1, IsPendingDeletion=1
--   → expired / new:     IsSuccess=1, IsNewUser=1 (fresh UserId created)

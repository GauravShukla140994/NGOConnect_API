-- ─────────────────────────────────────────────────────────────────────────────
-- patch_rebrand_ripple_hub.sql
-- Rebrand cleanup: replaces remaining "NGO Connect" occurrences in live,
-- user-visible SQL text with "Ripple Hub". The mobile app and Website repos
-- were already fully rebranded — this patch covers the backend's remaining
-- leftovers (SP notification/message text + the APP_NAME platform setting).
--
-- Covers:
--   1. Settings.APP_NAME seed value: 'NGO Connect' -> 'Ripple Hub'
--      (rendered as an editable field on Website Super Admin > Settings)
--   2. Auth_VerifyOTP — registration welcome message
--   3. SuperAdmin_Org_Approve — org-approved notification body
--   4. SuperAdmin_User_Reactivate — account-reactivated notification body
--   5. SuperAdmin_User_VerifyProfile — profile-verified notification body
--
-- Companion C# changes (not in this SQL file): SuperAdminDal.cs
-- (ReactivateMemberAsync push text), PostDal.cs (post-report admin email
-- subject + footer), NotificationModels.cs (default test-push body),
-- appsettings.Development.json (email FromName), ServiceCollectionExtensions.cs
-- + Program.cs (Swagger title/description/contact — dev-tool only, no deploy
-- action needed beyond redeploying the API).
--
-- Apply: local DB first → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Step 1: Settings.APP_NAME ────────────────────────────────────────────────
UPDATE Settings
SET SettingValue = 'Ripple Hub'
WHERE SettingGroup = 'PLATFORM' AND SettingKey = 'APP_NAME' AND SettingValue = 'NGO Connect';

DELIMITER //

-- ── Step 2: Auth_VerifyOTP ───────────────────────────────────────────────────
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
                    THEN 'Registration successful. Welcome to Ripple Hub!'
                    ELSE 'Login successful.'
               END           AS Message,
               v_UserId      AS UserId,
               v_IsNewUser   AS IsNewUser;
    END IF;
END //

-- ── Step 3: SuperAdmin_Org_Approve ───────────────────────────────────────────
DROP PROCEDURE IF EXISTS SuperAdmin_Org_Approve //
CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved',
                    'Congratulations — your organisation is now live on Ripple Hub.', p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

-- ── Step 4: SuperAdmin_User_Reactivate ───────────────────────────────────────
DROP PROCEDURE IF EXISTS SuperAdmin_User_Reactivate //
CREATE PROCEDURE SuperAdmin_User_Reactivate(
    IN p_UserId         INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM Users
    WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'User not found.' AS Message;
    ELSE
        UPDATE Users SET IsActive = 1, UpdatedAt = NOW()
        WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'ACCOUNT_REACTIVATED', 'Account reactivated',
                'Your Ripple Hub account has been reactivated. Welcome back!',
                p_UserId, 'USER');

        SELECT 1 AS IsSuccess, 'User account reactivated.' AS Message;
    END IF;
END //

-- ── Step 5: SuperAdmin_User_VerifyProfile ────────────────────────────────────
DROP PROCEDURE IF EXISTS SuperAdmin_User_VerifyProfile //
CREATE PROCEDURE SuperAdmin_User_VerifyProfile(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists   TINYINT DEFAULT 0;
    DECLARE v_VerifiedId INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM Users
    WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'User not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_VerifiedId
        FROM LookupValues lv
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv.ValueCode = 'VERIFIED'
        LIMIT 1;

        UPDATE Users
        SET ProfileVerificationLkpId = v_VerifiedId, UpdatedAt = NOW()
        WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'PROFILE_VERIFIED', 'Profile verified',
                'Your profile has been reviewed and verified by the Ripple Hub team.',
                p_UserId, 'USER');

        SELECT 1 AS IsSuccess, 'User profile verified.' AS Message;
    END IF;
END //

DELIMITER ;

-- Verify
SELECT 'patch_rebrand_ripple_hub applied successfully.' AS Status;

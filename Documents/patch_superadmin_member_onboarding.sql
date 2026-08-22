-- ============================================================
-- patch_superadmin_member_onboarding.sql
-- SuperAdmin_CreateMemberWithOrg — proactive Super Admin onboarding.
-- Creates a User + UserProfile + (new or existing) Organisation +
-- OrgMembers association in ONE atomic operation (explicit
-- START TRANSACTION / ROLLBACK on error — see SP comments in the
-- setup SQL for why this is the first SP in the codebase to do so).
--
-- No table/column changes — reuses existing Users, UserProfiles,
-- Organisations, OrgMembers, LookupValues/LookupTypes.
--
-- Run on: local → Railway staging → Railway production
-- Safe to re-run: DROP+CREATE is idempotent.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_CreateMemberWithOrg //
CREATE PROCEDURE SuperAdmin_CreateMemberWithOrg(
    -- Member / user
    IN p_FirstName        VARCHAR(80),
    IN p_LastName         VARCHAR(80),
    IN p_Email            VARCHAR(150),
    IN p_Mobile           VARCHAR(20),
    IN p_CountryCode      VARCHAR(6),
    IN p_GenderLkpId      INT UNSIGNED,
    IN p_DateOfBirth      DATE,
    IN p_ProfilePhoto     VARCHAR(500),
    IN p_AddressLine1     VARCHAR(200),
    IN p_AddressLine2     VARCHAR(200),
    IN p_City             VARCHAR(100),
    IN p_State            VARCHAR(100),
    IN p_Pincode          VARCHAR(20),
    IN p_Country          VARCHAR(100),
    -- Organisation mode
    IN p_OrgMode          VARCHAR(10),    -- 'NEW' | 'EXISTING'
    IN p_ExistingOrgId    INT UNSIGNED,
    -- Organisation (NEW mode only)
    IN p_OrgName          VARCHAR(200),
    IN p_OrgTypeLkpId     INT UNSIGNED,
    IN p_RegNumber        VARCHAR(100),
    IN p_Category         VARCHAR(100),
    IN p_About            TEXT,
    IN p_Mission          TEXT,
    IN p_Vision           TEXT,
    IN p_LogoUrl          VARCHAR(500),
    IN p_ContactEmail     VARCHAR(150),
    IN p_ContactPhone     VARCHAR(20),
    IN p_Website          VARCHAR(255),
    IN p_OrgAddressLine1  VARCHAR(200),
    IN p_OrgAddressLine2  VARCHAR(200),
    IN p_OrgCity          VARCHAR(100),
    IN p_OrgState         VARCHAR(100),
    IN p_OrgPincode       VARCHAR(20),
    IN p_OrgCountry       VARCHAR(100),
    -- Role + audit
    IN p_RoleCode         VARCHAR(20),    -- MEMBER_ROLE: FOUNDER | ADMIN | MODERATOR | MEMBER
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Error               VARCHAR(500)  DEFAULT NULL;
    DECLARE v_UserId              INT UNSIGNED  DEFAULT NULL;
    DECLARE v_OrgId               INT UNSIGNED  DEFAULT NULL;
    DECLARE v_RoleLkpId           INT UNSIGNED  DEFAULT NULL;
    DECLARE v_MemberStatusLkpId   INT UNSIGNED  DEFAULT NULL;
    DECLARE v_OrgStatusLkpId      INT UNSIGNED  DEFAULT NULL;
    DECLARE v_VerifiedStatusLkpId INT UNSIGNED  DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 0 AS IsSuccess,
               'An unexpected error occurred while creating the member. No records were saved.' AS Message,
               NULL AS UserId, NULL AS OrgId;
    END;

    -- ── Validation (all up front — nothing is inserted until this passes) ──
    IF (p_Email IS NULL OR p_Email = '') AND (p_Mobile IS NULL OR p_Mobile = '') THEN
        SET v_Error = 'At least one of Email or Mobile must be provided.';
    END IF;

    IF v_Error IS NULL AND p_Email IS NOT NULL AND p_Email != ''
       AND EXISTS (SELECT 1 FROM Users WHERE Email = p_Email AND IsDeleted = 0) THEN
        SET v_Error = 'A user with this email already exists.';
    END IF;

    IF v_Error IS NULL AND p_Mobile IS NOT NULL AND p_Mobile != ''
       AND EXISTS (SELECT 1 FROM Users WHERE Mobile = p_Mobile AND IsDeleted = 0) THEN
        SET v_Error = 'A user with this mobile number already exists.';
    END IF;

    IF v_Error IS NULL AND p_OrgMode = 'EXISTING' THEN
        IF p_ExistingOrgId IS NULL
           OR NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_ExistingOrgId AND IsDeleted = 0) THEN
            SET v_Error = 'Selected organisation was not found.';
        END IF;
    ELSEIF v_Error IS NULL AND p_OrgMode = 'NEW' THEN
        IF p_OrgName IS NULL OR p_OrgName = '' THEN
            SET v_Error = 'Organisation name is required.';
        ELSEIF p_RegNumber IS NULL OR p_RegNumber = '' THEN
            SET v_Error = 'Organisation registration number is required.';
        ELSEIF p_OrgTypeLkpId IS NULL THEN
            SET v_Error = 'Organisation type is required.';
        ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE RegNumber = p_RegNumber AND IsDeleted = 0) THEN
            SET v_Error = 'An organisation with this registration number already exists.';
        ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE LOWER(TRIM(OrgName)) = LOWER(TRIM(p_OrgName)) AND IsDeleted = 0) THEN
            SET v_Error = 'An organisation with this name already exists.';
        END IF;
    ELSEIF v_Error IS NULL THEN
        SET v_Error = 'OrgMode must be NEW or EXISTING.';
    END IF;

    IF v_Error IS NULL THEN
        SELECT lv.LookupValueId INTO v_RoleLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = p_RoleCode LIMIT 1;

        IF v_RoleLkpId IS NULL THEN
            SET v_Error = CONCAT('Invalid organisation role: ', IFNULL(p_RoleCode, '(none)'));
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS UserId, NULL AS OrgId;
    ELSE
        SELECT lv.LookupValueId INTO v_MemberStatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        SELECT lv.LookupValueId INTO v_OrgStatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        SELECT lv.LookupValueId INTO v_VerifiedStatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv.ValueCode = 'VERIFIED' LIMIT 1;

        START TRANSACTION;

        INSERT INTO Users (Mobile, Email, CountryCode, IsVerified, IsActive, CreatedBy)
        VALUES (
            NULLIF(p_Mobile, ''), NULLIF(p_Email, ''),
            IFNULL(NULLIF(p_CountryCode, ''), '+91'), 0, 1, p_SuperAdminUserId
        );
        SET v_UserId = LAST_INSERT_ID();

        INSERT INTO UserProfiles (
            UserId, FirstName, LastName, DateOfBirth, GenderLkpId, ProfilePhoto,
            AddressLine1, AddressLine2, City, State, Pincode, Country, CreatedBy
        ) VALUES (
            v_UserId, IFNULL(p_FirstName, ''), IFNULL(p_LastName, ''), p_DateOfBirth, p_GenderLkpId, p_ProfilePhoto,
            p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, IFNULL(NULLIF(p_Country, ''), 'India'),
            p_SuperAdminUserId
        );

        IF p_OrgMode = 'NEW' THEN
            INSERT INTO Organisations (
                OrgName, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision, LogoUrl,
                ContactEmail, ContactPhone, Website,
                AddressLine1, AddressLine2, City, State, Pincode, Country,
                StatusLkpId, VerificationStatusLkpId, CreatedBy
            ) VALUES (
                p_OrgName, p_OrgTypeLkpId, p_RegNumber, IFNULL(NULLIF(p_Category, ''), 'General'),
                p_About, p_Mission, p_Vision, p_LogoUrl,
                p_ContactEmail, p_ContactPhone, p_Website,
                p_OrgAddressLine1, p_OrgAddressLine2, p_OrgCity, p_OrgState, p_OrgPincode,
                IFNULL(NULLIF(p_OrgCountry, ''), 'India'),
                v_OrgStatusLkpId, v_VerifiedStatusLkpId, v_UserId
            );
            SET v_OrgId = LAST_INSERT_ID();
        ELSE
            SET v_OrgId = p_ExistingOrgId;
        END IF;

        INSERT INTO OrgMembers (
            OrgId, UserId, RoleLkpId, StatusLkpId, StatusUpdatedAt, StatusUpdatedBy, JoinedAt, CreatedBy
        ) VALUES (
            v_OrgId, v_UserId, v_RoleLkpId, v_MemberStatusLkpId, NOW(), p_SuperAdminUserId, NOW(), p_SuperAdminUserId
        );

        COMMIT;

        SELECT 1 AS IsSuccess,
               'Member created and associated with organisation successfully.' AS Message,
               v_UserId AS UserId, v_OrgId AS OrgId;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.3-superadmin-member-onboarding', 'SuperAdmin_CreateMemberWithOrg — proactive Super Admin onboarding: creates User+UserProfile+Organisation(optional)+OrgMembers atomically.', 'System');

-- ============================================================
-- VERIFICATION (run after applying)
-- ============================================================
-- CALL SuperAdmin_CreateMemberWithOrg(
--   'Test','User','test.member@example.com',NULL,'+91',NULL,NULL,NULL,
--   NULL,NULL,NULL,NULL,NULL,NULL,
--   'EXISTING', 1,
--   NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--   NULL,NULL,NULL,NULL,NULL,NULL,
--   'MEMBER', 1
-- );
-- Then roll it back manually (DELETE the test rows) — this is a real INSERT, not a dry run.

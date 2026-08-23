-- ============================================================
-- patch_superadmin_profile_edit.sql  (v5.5)
--
-- Post-creation profile correction flow for Super Admin — lets Super Admin
-- fix a typo'd org name, wrong contact email, wrong address, etc. after
-- using the Create Member wizard (or for any existing org/member).
--
-- New:
--   SuperAdmin_Org_UpdateProfile   — full-profile overwrite for an org,
--                                    re-validates OrgName/RegNumber
--                                    uniqueness excluding itself.
--   SuperAdmin_User_UpdateProfile  — full-profile overwrite for a member.
--                                    Email/Mobile are ONLY applied while
--                                    Users.IsVerified = 0 (member has never
--                                    logged in) — enforced in the SP itself,
--                                    not just the API layer, so a live login
--                                    identity can never be silently
--                                    overwritten. Confirmed with product
--                                    2026-08-23.
--
-- Modified (additive SELECT columns only — no breaking changes):
--   SuperAdmin_Org_GetDetail       — added o.OrgTypeLkpId (needed to
--                                    pre-select the org type dropdown when
--                                    editing; only the resolved name was
--                                    returned before).
--   SuperAdmin_User_GetFullProfile — added u.CountryCode, up.AddressLine1,
--                                    up.AddressLine2, up.Pincode,
--                                    up.GenderLkpId (needed to pre-fill the
--                                    member edit form; several of these
--                                    weren't returned at all before).
--
-- Run on: local -> Railway staging -> Railway production
-- Safe to re-run: all DROP+CREATE, idempotent.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetDetail //
CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.Is80GEligible, o.Is12AEligible,
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
        -- v5.5: OrgTypeLkpId added — needed so the Super Admin website can
        -- pre-select the org type dropdown when editing an org's profile
        -- (only the resolved name, tv.ValueName, was returned before).
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        founder.UserId AS FounderUserId,
        CONCAT(fp.FirstName, ' ', fp.LastName) AS FounderName,
        u.Email AS FounderEmail, u.Mobile AS FounderMobile,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason,
        (SELECT COUNT(*) FROM OrgMembers om2
          JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
          WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
            AND sv2.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    LEFT JOIN OrgMembers founder ON founder.OrgId = o.OrgId AND founder.IsDeleted = 0
        AND founder.RoleLkpId = (
            SELECT LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
    LEFT JOIN Users u ON founder.UserId = u.UserId
    LEFT JOIN UserProfiles fp ON founder.UserId = fp.UserId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_User_GetFullProfile //
CREATE PROCEDURE SuperAdmin_User_GetFullProfile(IN p_UserId INT UNSIGNED)
BEGIN
    -- Result Set 0: core profile
    SELECT
        u.UserId, u.Email, u.Mobile, u.IsActive, u.IsVerified,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        COALESCE(pv.ValueName, 'Not Reviewed') AS ProfileVerificationStatusName,
        u.LastLoginAt, u.CreatedAt AS RegisteredAt,
        -- v5.5: CountryCode added alongside the existing Mobile column —
        -- needed by the Super Admin website's member edit form.
        u.CountryCode,
        up.FirstName, up.LastName,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.DateOfBirth, up.Bio, up.ProfilePhoto,
        up.Occupation, up.Organisation AS OrganisationName,
        -- v5.5: AddressLine1/2, Pincode, GenderLkpId added — only City/State/
        -- Country and resolved Gender NAME were returned before, which isn't
        -- enough to pre-fill a full edit form.
        up.AddressLine1, up.AddressLine2, up.City, up.State, up.Pincode, up.Country,
        up.GenderLkpId,
        up.ImpactScore, up.ReliabilityPct,
        gv.ValueName AS Gender,
        ev.ValueName AS Education,
        wv.ValueName AS WorkExperience
    FROM Users u
    JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    LEFT JOIN LookupValues gv ON up.GenderLkpId   = gv.LookupValueId
    LEFT JOIN LookupValues ev ON up.EducationLkpId = ev.LookupValueId
    LEFT JOIN LookupValues wv ON up.WorkExpLkpId   = wv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;

    -- Result Set 1: skills
    SELECT s.ValueName AS SkillName, s.ValueCode AS SkillCode
    FROM UserSkills us
    JOIN LookupValues s ON us.SkillLkpId = s.LookupValueId
    WHERE us.UserId = p_UserId AND us.IsDeleted = 0;

    -- Result Set 2: interests
    SELECT iv.ValueName, iv.ValueCode
    FROM UserInterests ui
    JOIN LookupValues iv ON ui.InterestLkpId = iv.LookupValueId
    WHERE ui.UserId = p_UserId AND ui.IsDeleted = 0;

    -- Result Set 3: badges
    SELECT ub.BadgeType, ub.BadgeName, ub.AwardedAt, ub.AwardedBy,
           ub.OrgId, o.OrgName
    FROM UserBadges ub
    LEFT JOIN Organisations o ON ub.OrgId = o.OrgId AND o.IsDeleted = 0
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;

    -- Result Set 4: other orgs (membership history)
    SELECT o.OrgId, o.OrgName, o.LogoUrl,
           rv.ValueName AS Role, sv.ValueName AS MembershipStatus,
           om.JoinedAt
    FROM OrgMembers om
    JOIN Organisations  o  ON om.OrgId  = o.OrgId  AND o.IsDeleted  = 0
    JOIN LookupValues   rv ON om.RoleLkpId   = rv.LookupValueId
    JOIN LookupValues   sv ON om.StatusLkpId = sv.LookupValueId
    WHERE om.UserId = p_UserId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt DESC;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_UpdateProfile //
CREATE PROCEDURE SuperAdmin_Org_UpdateProfile(
    IN p_OrgId           INT UNSIGNED,
    IN p_OrgName         VARCHAR(200),
    IN p_OrgTypeLkpId    INT UNSIGNED,
    IN p_RegNumber       VARCHAR(100),
    IN p_Category        VARCHAR(100),
    IN p_ContactPerson   VARCHAR(100),
    IN p_About           TEXT,
    IN p_Mission         TEXT,
    IN p_Vision          TEXT,
    IN p_LogoUrl         VARCHAR(500),
    IN p_ContactEmail    VARCHAR(150),
    IN p_ContactPhone    VARCHAR(20),
    IN p_Website         VARCHAR(255),
    IN p_AddressLine1    VARCHAR(200),
    IN p_AddressLine2    VARCHAR(200),
    IN p_City            VARCHAR(100),
    IN p_State           VARCHAR(100),
    IN p_Pincode         VARCHAR(20),
    IN p_Country         VARCHAR(100),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Error VARCHAR(500) DEFAULT NULL;

    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SET v_Error = 'Organisation not found.';
    ELSEIF p_OrgName IS NULL OR p_OrgName = '' THEN
        SET v_Error = 'Organisation name is required.';
    ELSEIF p_RegNumber IS NULL OR p_RegNumber = '' THEN
        SET v_Error = 'Organisation registration number is required.';
    ELSEIF p_OrgTypeLkpId IS NULL THEN
        SET v_Error = 'Organisation type is required.';
    ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE RegNumber = p_RegNumber AND IsDeleted = 0 AND OrgId != p_OrgId) THEN
        SET v_Error = 'Another organisation is already using this registration number.';
    ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE LOWER(TRIM(OrgName)) = LOWER(TRIM(p_OrgName)) AND IsDeleted = 0 AND OrgId != p_OrgId) THEN
        SET v_Error = 'Another organisation is already using this name.';
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS OrgId;
    ELSE
        UPDATE Organisations
        SET OrgName       = p_OrgName,
            OrgTypeLkpId   = p_OrgTypeLkpId,
            RegNumber      = p_RegNumber,
            Category       = IFNULL(NULLIF(p_Category, ''), 'General'),
            ContactPerson  = p_ContactPerson,
            About          = p_About,
            Mission        = p_Mission,
            Vision         = p_Vision,
            LogoUrl        = p_LogoUrl,
            ContactEmail   = p_ContactEmail,
            ContactPhone   = p_ContactPhone,
            Website        = p_Website,
            AddressLine1   = p_AddressLine1,
            AddressLine2   = p_AddressLine2,
            City           = p_City,
            State          = p_State,
            Pincode        = p_Pincode,
            Country        = IFNULL(NULLIF(p_Country, ''), 'India'),
            UpdatedBy      = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Organisation profile updated.' AS Message, p_OrgId AS OrgId;
    END IF;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_User_UpdateProfile //
CREATE PROCEDURE SuperAdmin_User_UpdateProfile(
    IN p_UserId          INT UNSIGNED,
    IN p_FirstName       VARCHAR(80),
    IN p_LastName        VARCHAR(80),
    IN p_Email           VARCHAR(150),   -- only applied if user IsVerified = 0
    IN p_Mobile          VARCHAR(20),    -- only applied if user IsVerified = 0
    IN p_CountryCode     VARCHAR(6),
    IN p_GenderLkpId     INT UNSIGNED,
    IN p_DateOfBirth     DATE,
    IN p_ProfilePhoto    VARCHAR(500),
    IN p_AddressLine1    VARCHAR(200),
    IN p_AddressLine2    VARCHAR(200),
    IN p_City            VARCHAR(100),
    IN p_State           VARCHAR(100),
    IN p_Pincode         VARCHAR(20),
    IN p_Country         VARCHAR(100),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Error      VARCHAR(500) DEFAULT NULL;
    DECLARE v_IsVerified TINYINT(1)   DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 0 AS IsSuccess,
               'An unexpected error occurred while updating the member. No changes were saved.' AS Message,
               NULL AS UserId, NULL AS EmailMobileLocked;
    END;

    SELECT IsVerified INTO v_IsVerified FROM Users WHERE UserId = p_UserId AND IsDeleted = 0 LIMIT 1;

    IF v_IsVerified IS NULL THEN
        SET v_Error = 'Member not found.';
    ELSEIF p_FirstName IS NULL OR p_FirstName = '' THEN
        SET v_Error = 'First name is required.';
    ELSEIF v_IsVerified = 0 THEN
        -- Not yet logged in — Email/Mobile are still safe to correct here.
        IF (p_Email IS NULL OR p_Email = '') AND (p_Mobile IS NULL OR p_Mobile = '') THEN
            SET v_Error = 'At least one of Email or Mobile must be provided.';
        ELSEIF p_Email IS NOT NULL AND p_Email != ''
               AND EXISTS (SELECT 1 FROM Users WHERE Email = p_Email AND IsDeleted = 0 AND UserId != p_UserId) THEN
            SET v_Error = 'Another user already has this email.';
        ELSEIF p_Mobile IS NOT NULL AND p_Mobile != ''
               AND EXISTS (SELECT 1 FROM Users WHERE Mobile = p_Mobile AND IsDeleted = 0 AND UserId != p_UserId) THEN
            SET v_Error = 'Another user already has this mobile number.';
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS UserId, NULL AS EmailMobileLocked;
    ELSE
        START TRANSACTION;

        -- Email/Mobile only touched pre-first-login. Once IsVerified = 1 this
        -- block is skipped entirely — enforced here, not just in the API layer,
        -- so a stale/forced request can never overwrite a live login identity.
        IF v_IsVerified = 0 THEN
            UPDATE Users
            SET Email       = NULLIF(p_Email, ''),
                Mobile      = NULLIF(p_Mobile, ''),
                CountryCode = IFNULL(NULLIF(p_CountryCode, ''), CountryCode),
                UpdatedBy   = p_SuperAdminUserId
            WHERE UserId = p_UserId;
        END IF;

        UPDATE UserProfiles
        SET FirstName     = p_FirstName,
            LastName      = IFNULL(p_LastName, ''),
            DateOfBirth   = p_DateOfBirth,
            GenderLkpId   = p_GenderLkpId,
            ProfilePhoto  = p_ProfilePhoto,
            AddressLine1  = p_AddressLine1,
            AddressLine2  = p_AddressLine2,
            City          = p_City,
            State         = p_State,
            Pincode       = p_Pincode,
            Country       = IFNULL(NULLIF(p_Country, ''), 'India'),
            UpdatedBy     = p_SuperAdminUserId
        WHERE UserId = p_UserId;

        COMMIT;

        SELECT 1 AS IsSuccess, 'Member profile updated.' AS Message,
               p_UserId AS UserId, (v_IsVerified = 1) AS EmailMobileLocked;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.5-superadmin-profile-edit', 'SuperAdmin_Org_UpdateProfile + SuperAdmin_User_UpdateProfile — post-creation field correction for Super Admin onboarded orgs/members. Email/Mobile edit locked once Users.IsVerified = 1. Also extends SuperAdmin_Org_GetDetail (+OrgTypeLkpId) and SuperAdmin_User_GetFullProfile (+CountryCode/AddressLine1/AddressLine2/Pincode/GenderLkpId) so the edit forms can be pre-filled.', 'System');

-- ============================================================
-- VERIFICATION (run after applying)
-- ============================================================
-- CALL SuperAdmin_Org_GetDetail(1);           -- confirm OrgTypeLkpId now present
-- CALL SuperAdmin_User_GetFullProfile(1);      -- confirm new columns present
-- CALL SuperAdmin_Org_UpdateProfile(1, 'Test Org', 1, 'REG-TEST-001', 'General', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1);
-- CALL SuperAdmin_User_UpdateProfile(1, 'Test', 'User', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1);

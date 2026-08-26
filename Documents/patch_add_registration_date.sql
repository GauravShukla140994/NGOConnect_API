-- ============================================================
-- Patch: Add RegistrationDate to Organisations
-- Feature: Capture govt registration date separately from
--          RippleHub CreatedAt date.
--          RegistrationDate is NULL when IsNonRegistered = 1.
-- Affected table : Organisations (new column)
-- Affected SPs   : Org_Register, Org_GetProfile, Org_Resubmit
-- Schema version : 5.1.12
-- Author         : NGO Connect
-- Date           : 2026-08-26
-- ============================================================

USE ngoconnect;

-- ── 1. Add column ─────────────────────────────────────────────────────────────
-- Note: ADD COLUMN IF NOT EXISTS requires MySQL 8.0.31+ which Railway may not have.
-- Run this patch only once; the column does not exist on Railway yet.
ALTER TABLE Organisations
    ADD COLUMN RegistrationDate DATE NULL
        COMMENT 'Date org was officially registered with govt — NULL when IsNonRegistered = 1'
        AFTER IsNonRegistered;

DELIMITER //

-- ── 2. Org_Register ──────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Org_Register //

CREATE PROCEDURE Org_Register(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgName           VARCHAR(200),
    IN p_RegistrationNo    VARCHAR(100),
    IN p_IsNonRegistered   TINYINT(1),          -- 1 = no govt registration number
    IN p_OrgTypeLkpId      INT UNSIGNED,
    IN p_Category          VARCHAR(100),
    IN p_ContactPerson     VARCHAR(100),
    IN p_About             TEXT,
    IN p_Mission           TEXT,
    IN p_Vision            TEXT,
    IN p_LogoUrl           VARCHAR(500),
    IN p_ContactEmail      VARCHAR(150),
    IN p_ContactPhone      VARCHAR(20),
    IN p_Website           VARCHAR(255),
    IN p_AddressLine1      VARCHAR(200),
    IN p_AddressLine2      VARCHAR(200),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_Pincode           VARCHAR(20),
    IN p_Country           VARCHAR(100),
    IN p_Is80GEligible     TINYINT(1),
    IN p_Is12AEligible     TINYINT(1),
    IN p_RegistrationDate  DATE                 -- NULL when IsNonRegistered = 1
)
BEGIN
    DECLARE v_Exists       INT DEFAULT 0;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_RoleLkpId    INT UNSIGNED;
    DECLARE v_MemStatLkpId INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    -- Uniqueness check only for registered orgs with a non-blank reg number
    IF p_IsNonRegistered = 0 AND (p_RegistrationNo IS NOT NULL AND TRIM(p_RegistrationNo) != '') THEN
        SELECT COUNT(*) INTO v_Exists FROM Organisations WHERE RegNumber = p_RegistrationNo AND IsDeleted = 0;
    END IF;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'Registration number already exists.' AS Message, NULL AS OrgId;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;
        SELECT LookupValueId INTO v_RoleLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1;
        SELECT LookupValueId INTO v_MemStatLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        INSERT INTO Organisations
            (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, IsNonRegistered, RegistrationDate, Category, About, Mission, Vision,
             LogoUrl, ContactEmail, ContactPhone, Website,
             AddressLine1, AddressLine2, City, State, Pincode, Country,
             Is80GEligible, Is12AEligible, StatusLkpId, CreatedBy)
        VALUES
            (p_OrgName, p_ContactPerson, p_OrgTypeLkpId,
             NULLIF(TRIM(COALESCE(p_RegistrationNo, '')), ''),
             IFNULL(p_IsNonRegistered, 0),
             IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL, p_RegistrationDate),
             p_Category, p_About, p_Mission, p_Vision, p_LogoUrl,
             p_ContactEmail, p_ContactPhone, p_Website,
             p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode,
             COALESCE(p_Country, 'India'),
             IFNULL(p_Is80GEligible, 0), IFNULL(p_Is12AEligible, 0),
             v_StatusLkpId, p_UserId);

        SET v_OrgId = LAST_INSERT_ID();

        INSERT INTO OrgMembers
            (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
        VALUES
            (v_OrgId, p_UserId, v_RoleLkpId, v_MemStatLkpId, 1, 1, 1, 50, NOW(), p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation registered successfully.' AS Message, v_OrgId AS OrgId;
    END IF;
END //

-- ── 3. Org_GetProfile ────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Org_GetProfile //

CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED     -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.RegistrationDate, o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        -- Is80GEligible / Is12AEligible: prefer OrgDonationSettings, fall back to Organisations columns
        COALESCE(ods.Is80GEligible, o.Is80GEligible, 0) AS Is80GEligible,
        COALESCE(ods.Is12AEligible, o.Is12AEligible, 0) AS Is12AEligible,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        sv.ValueCode AS OrgStatusCode,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.AvgRating, o.RatingCount, o.Latitude, o.Longitude, o.CreatedAt,
        o.FollowerCount,
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = o.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        (SELECT COUNT(*)
         FROM OrgMembers   om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        COALESCE(
            (SELECT lv3.ValueCode FROM OrgMembers   om3
             JOIN LookupValues lv3 ON om3.StatusLkpId = lv3.LookupValueId
             WHERE om3.OrgId = o.OrgId AND om3.UserId = p_UserId AND om3.IsDeleted = 0 LIMIT 1),
            (SELECT lv4.ValueCode FROM OrgMembershipRequests mr4
             JOIN LookupValues lv4 ON mr4.StatusLkpId = lv4.LookupValueId
             WHERE mr4.OrgId = o.OrgId AND mr4.UserId = p_UserId AND mr4.IsDeleted = 0
               AND lv4.ValueCode = 'PENDING' LIMIT 1)
        ) AS MemberStatusCode
    FROM Organisations o
    LEFT JOIN OrgDonationSettings ods ON ods.OrgId = o.OrgId
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category
                              AND cv.LookupTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1)
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- ── 4. Org_Resubmit ──────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Org_Resubmit //

CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId            INT UNSIGNED,
    IN p_UserId           INT UNSIGNED,
    IN p_OrgName          VARCHAR(200),
    IN p_Category         VARCHAR(100),
    IN p_ContactPerson    VARCHAR(100),
    IN p_About            TEXT,
    IN p_Mission          TEXT,
    IN p_Vision           TEXT,
    IN p_LogoUrl          VARCHAR(500),
    IN p_ContactEmail     VARCHAR(150),
    IN p_ContactPhone     VARCHAR(20),
    IN p_Website          VARCHAR(255),
    IN p_AddressLine1     VARCHAR(200),
    IN p_AddressLine2     VARCHAR(200),
    IN p_City             VARCHAR(100),
    IN p_State            VARCHAR(100),
    IN p_Pincode          VARCHAR(20),
    IN p_Country          VARCHAR(100),
    IN p_RegistrationNo   VARCHAR(100),
    IN p_IsNonRegistered  TINYINT(1),
    IN p_Is80GEligible    TINYINT(1),
    IN p_Is12AEligible    TINYINT(1),
    IN p_RegistrationDate DATE                                    -- NULL when IsNonRegistered = 1
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_PendingId       INT UNSIGNED;
    DECLARE v_IsFounder       INT DEFAULT 0;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsFounder FROM OrgMembers om
        JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
        WHERE om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0 AND rv.ValueCode = 'FOUNDER';

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_IsFounder = 0 THEN
        SELECT 0 AS IsSuccess, 'Only the founder can resubmit this organisation.' AS Message;
    ELSEIF v_CurrentCode <> 'REJECTED' THEN
        SELECT 0 AS IsSuccess, 'Only a rejected organisation can be resubmitted.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_PendingId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        UPDATE Organisations SET
            OrgName = p_OrgName, Category = p_Category, ContactPerson = p_ContactPerson,
            About = p_About, Mission = p_Mission, Vision = p_Vision, LogoUrl = p_LogoUrl,
            ContactEmail = p_ContactEmail, ContactPhone = p_ContactPhone, Website = p_Website,
            AddressLine1 = p_AddressLine1, AddressLine2 = p_AddressLine2, City = p_City,
            State = p_State, Pincode = p_Pincode, Country = p_Country,
            -- Allow founder to correct registration status on resubmit
            IsNonRegistered  = IFNULL(p_IsNonRegistered, 0),
            RegNumber        = IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL,
                                  NULLIF(TRIM(COALESCE(p_RegistrationNo, '')), '')),
            RegistrationDate = IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL, p_RegistrationDate),
            Is80GEligible = p_Is80GEligible, Is12AEligible = p_Is12AEligible,
            StatusLkpId = v_PendingId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedAt)
VALUES ('5.1.12', 'Add RegistrationDate to Organisations + update Org_Register, Org_GetProfile, Org_Resubmit SPs', NOW());

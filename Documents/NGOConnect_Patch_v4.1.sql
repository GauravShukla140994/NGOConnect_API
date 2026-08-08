-- ============================================================
-- NGO Connect — Database Patch v4.0 → v4.1
-- Run this AFTER NGOConnect_Complete_Setup_v4.0.sql
-- Date: 2026-06-27
-- Changes:
--   1. UserProfiles      — ADD COLUMN VolunteerExp
--   2. UserSafetyPreferences — ADD COLUMNs EmergencyContact*
--   3. User_GetProfile   — return VolunteerExp
--   4. User_UpdateProfile — add p_VolunteerExp param
--   5. User_UpdateSafetyPrefs — add emergency contact params
--   6. Lookup_GetValueByCode — add OrderNo, IsDefault to SELECT
-- ============================================================

USE NGOConnect;
DELIMITER //

-- ============================================================
-- SECTION 1: TABLE ALTERATIONS
-- ============================================================

-- 1. Add VolunteerExp to UserProfiles
--    Stores free-text previous NGO / volunteer experience (Edit Profile Step 3)
ALTER TABLE UserProfiles
    ADD COLUMN VolunteerExp TEXT NULL AFTER Organisation //

-- 2. Add Emergency Contact columns to UserSafetyPreferences
--    Stores the user's emergency contact for SOS situations (Edit Profile Step 1)
ALTER TABLE UserSafetyPreferences
    ADD COLUMN EmergencyContactName     VARCHAR(100) NULL AFTER AllowLocDuringProj,
    ADD COLUMN EmergencyContactPhone    VARCHAR(20)  NULL AFTER EmergencyContactName,
    ADD COLUMN EmergencyContactRelation VARCHAR(50)  NULL AFTER EmergencyContactPhone //

-- ============================================================
-- SECTION 2: STORED PROCEDURE UPDATES
-- ============================================================

-- 3. User_GetProfile — add VolunteerExp + GenderLkpId/EducationLkpId/WorkExpLkpId to SELECT
DROP PROCEDURE IF EXISTS User_GetProfile //
CREATE PROCEDURE User_GetProfile(IN p_UserId INT UNSIGNED, IN p_RequestingUserId INT UNSIGNED)
BEGIN
    SELECT
        u.UserId, u.Mobile, u.Email, u.CountryCode, u.IsVerified,
        up.FirstName, up.LastName, up.Bio, up.ProfilePhoto,
        up.DateOfBirth, up.Occupation, up.Organisation, up.VolunteerExp,
        up.GenderLkpId,
        gv.ValueName AS Gender,    gv.ValueCode AS GenderCode,
        up.EducationLkpId,
        ev.ValueName AS Education, ev.ValueCode AS EducationCode,
        up.FieldOfStudy,
        up.WorkExpLkpId,
        wv.ValueName AS WorkExperience, wv.ValueCode AS WorkExpCode,
        up.AddressLine1, up.AddressLine2, up.City, up.State, up.Pincode, up.Country,
        up.ImpactScore, up.ReliabilityPct,
        u.CreatedAt AS MemberSince,
        up.UpdatedAt,
        CASE
            WHEN up.FirstName IS NOT NULL AND TRIM(up.FirstName) != ''
             AND up.LastName  IS NOT NULL AND TRIM(up.LastName)  != ''
            THEN 1 ELSE 0
        END AS IsProfileComplete
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues gv ON up.GenderLkpId    = gv.LookupValueId
    LEFT JOIN LookupValues ev ON up.EducationLkpId = ev.LookupValueId
    LEFT JOIN LookupValues wv ON up.WorkExpLkpId   = wv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- 4. User_UpdateProfile — add p_VolunteerExp parameter (v4.1: 19 params)
DROP PROCEDURE IF EXISTS User_UpdateProfile //
CREATE PROCEDURE User_UpdateProfile(
    IN p_UserId         INT UNSIGNED,
    IN p_FirstName      VARCHAR(80),
    IN p_LastName       VARCHAR(80),
    IN p_Bio            TEXT,
    IN p_ProfilePhoto   VARCHAR(500),
    IN p_GenderLkpId    INT UNSIGNED,
    IN p_DateOfBirth    DATE,
    IN p_Occupation     VARCHAR(150),
    IN p_Organisation   VARCHAR(150),
    IN p_VolunteerExp   TEXT,
    IN p_EducationLkpId INT UNSIGNED,
    IN p_FieldOfStudy   VARCHAR(150),
    IN p_WorkExpLkpId   INT UNSIGNED,
    IN p_AddressLine1   VARCHAR(200),
    IN p_AddressLine2   VARCHAR(200),
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Pincode        VARCHAR(20),
    IN p_Country        VARCHAR(100)
)
BEGIN
    UPDATE UserProfiles SET
        FirstName      = COALESCE(p_FirstName,      FirstName),
        LastName       = COALESCE(p_LastName,       LastName),
        Bio            = COALESCE(p_Bio,            Bio),
        ProfilePhoto   = COALESCE(p_ProfilePhoto,   ProfilePhoto),
        GenderLkpId    = COALESCE(p_GenderLkpId,    GenderLkpId),
        DateOfBirth    = COALESCE(p_DateOfBirth,    DateOfBirth),
        Occupation     = COALESCE(p_Occupation,     Occupation),
        Organisation   = COALESCE(p_Organisation,   Organisation),
        VolunteerExp   = COALESCE(p_VolunteerExp,   VolunteerExp),
        EducationLkpId = COALESCE(p_EducationLkpId, EducationLkpId),
        FieldOfStudy   = COALESCE(p_FieldOfStudy,   FieldOfStudy),
        WorkExpLkpId   = COALESCE(p_WorkExpLkpId,   WorkExpLkpId),
        AddressLine1   = COALESCE(p_AddressLine1,   AddressLine1),
        AddressLine2   = COALESCE(p_AddressLine2,   AddressLine2),
        City           = COALESCE(p_City,           City),
        State          = COALESCE(p_State,          State),
        Pincode        = COALESCE(p_Pincode,        Pincode),
        Country        = COALESCE(p_Country,        Country),
        UpdatedAt      = NOW()
    WHERE UserId = p_UserId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Profile updated.' AS Message;
END //

-- 5. User_UpdateSafetyPrefs — add emergency contact params (v4.1: 8 params)
DROP PROCEDURE IF EXISTS User_UpdateSafetyPrefs //
CREATE PROCEDURE User_UpdateSafetyPrefs(
    IN p_UserId                   INT UNSIGNED,
    IN p_EmergVisibilityLkpId     INT UNSIGNED,
    IN p_AutoShareDurLkpId        INT UNSIGNED,
    IN p_AllowLocDuringSos        TINYINT(1),
    IN p_AllowLocDuringProj       TINYINT(1),
    IN p_EmergencyContactName     VARCHAR(100),
    IN p_EmergencyContactPhone    VARCHAR(20),
    IN p_EmergencyContactRelation VARCHAR(50)
)
BEGIN
    INSERT INTO UserSafetyPreferences
        (UserId, EmergVisibilityLkpId, AutoShareDurLkpId, AllowLocDuringSos, AllowLocDuringProj,
         EmergencyContactName, EmergencyContactPhone, EmergencyContactRelation)
    VALUES
        (p_UserId, p_EmergVisibilityLkpId, p_AutoShareDurLkpId, p_AllowLocDuringSos, p_AllowLocDuringProj,
         p_EmergencyContactName, p_EmergencyContactPhone, p_EmergencyContactRelation)
    ON DUPLICATE KEY UPDATE
        EmergVisibilityLkpId     = COALESCE(p_EmergVisibilityLkpId,     EmergVisibilityLkpId),
        AutoShareDurLkpId        = COALESCE(p_AutoShareDurLkpId,        AutoShareDurLkpId),
        AllowLocDuringSos        = COALESCE(p_AllowLocDuringSos,        AllowLocDuringSos),
        AllowLocDuringProj       = COALESCE(p_AllowLocDuringProj,       AllowLocDuringProj),
        EmergencyContactName     = COALESCE(p_EmergencyContactName,     EmergencyContactName),
        EmergencyContactPhone    = COALESCE(p_EmergencyContactPhone,    EmergencyContactPhone),
        EmergencyContactRelation = COALESCE(p_EmergencyContactRelation, EmergencyContactRelation),
        UpdatedAt                = NOW();
    SELECT 1 AS IsSuccess, 'Safety preferences saved.' AS Message;
END //

-- 6. Lookup_GetValueByCode — add OrderNo, IsDefault to SELECT
DROP PROCEDURE IF EXISTS Lookup_GetValueByCode //
CREATE PROCEDURE Lookup_GetValueByCode(IN p_TypeCode VARCHAR(50), IN p_ValueCode VARCHAR(50))
BEGIN
    SELECT lv.LookupValueId, lv.ValueCode, lv.ValueName, lv.Description, lv.OrderNo, lv.IsDefault
    FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = p_TypeCode AND lv.ValueCode = p_ValueCode AND lv.IsDeleted = 0
    LIMIT 1;
END //

DELIMITER ;

-- ============================================================
-- SECTION 3: INTEREST_TYPE LOOKUP + UserInterests REDESIGN
-- Replaces free-text InterestName with LookupValueId FK
-- ============================================================

-- 7. Add INTEREST_TYPE LookupType
INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
VALUES ('INTEREST_TYPE', 'Interest Type', 'Volunteer areas of interest / cause categories', 1, 1);

-- 8. Seed 8 interest values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EDUCATION',    'Education',       1, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'HEALTHCARE',   'Healthcare',      2, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ENVIRONMENT',  'Environment',     3, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'SPORTS',       'Sports',          4, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ARTS',         'Arts',            5, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'TECHNOLOGY',   'Technology',      6, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'COMMUNITY',    'Community',       7, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ANIMAL_WELFARE','Animal Welfare', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE';

-- 9. Alter UserInterests — replace InterestName with InterestLkpId FK
ALTER TABLE UserInterests
    DROP COLUMN InterestName,
    ADD COLUMN InterestLkpId INT UNSIGNED NOT NULL AFTER UserId,
    ADD CONSTRAINT fk_interest_lkp FOREIGN KEY (InterestLkpId) REFERENCES LookupValues(LookupValueId);

-- 10. Rewrite User_SaveInterests — accept JSON int array of LookupValueIds
DELIMITER //
DROP PROCEDURE IF EXISTS User_SaveInterests //
CREATE PROCEDURE User_SaveInterests(
    IN p_UserId         INT UNSIGNED,
    IN p_InterestLkpIds JSON    -- e.g. [1, 2, 3] — LookupValueIds from INTEREST_TYPE
)
BEGIN
    DELETE FROM UserInterests WHERE UserId = p_UserId;
    INSERT INTO UserInterests (UserId, InterestLkpId)
    SELECT p_UserId, lkp_id
    FROM JSON_TABLE(p_InterestLkpIds, '$[*]' COLUMNS (lkp_id INT UNSIGNED PATH '$')) j
    WHERE lkp_id IS NOT NULL;
    SELECT 1 AS IsSuccess, 'Interests saved.' AS Message;
END //
DELIMITER ;

-- ============================================================
-- SECTION 4: MEDIA / FILE UPLOAD — Settings seed
-- These settings are read by LocalF
-- ============================================================
-- SECTION 5: MISSING READ ENDPOINTS — Edit Profile + Impact + My Orgs
-- All SPs are new (CREATE only, no DROP needed on first run)
-- ============================================================

DELIMITER //

-- NOTE: User_GetProfile already patched with LkpIds in Section 2 above.

-- 13. User_GetSafetyPrefs — for Edit Profile safety step pre-fill
CREATE PROCEDURE User_GetSafetyPrefs(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        sp.EmergVisibilityLkpId,
        ev.ValueName AS EmergVisibility,
        sp.AutoShareDurLkpId,
        av.ValueName AS AutoShareDuration,
        sp.AllowLocDuringSos,
        sp.AllowLocDuringProj,
        sp.EmergencyContactName,
        sp.EmergencyContactPhone,
        sp.EmergencyContactRelation
    FROM UserSafetyPreferences sp
    LEFT JOIN LookupValues ev ON sp.EmergVisibilityLkpId = ev.LookupValueId
    LEFT JOIN LookupValues av ON sp.AutoShareDurLkpId    = av.LookupValueId
    WHERE sp.UserId = p_UserId AND sp.IsDeleted = 0;
END //

-- 14. User_GetInterests — for Edit Profile interests step pre-fill
CREATE PROCEDURE User_GetInterests(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ui.InterestLkpId,
        lv.ValueName AS InterestName,
        lv.ValueCode AS InterestCode
    FROM UserInterests ui
    JOIN LookupValues lv ON ui.InterestLkpId = lv.LookupValueId
    WHERE ui.UserId = p_UserId
    ORDER BY lv.OrderNo;
END //

-- 15. User_GetMyOrgs — for s-my-orgs screen
-- FIX: was joining on om.ApprovalStatusLkpId (wrong column — column is om.StatusLkpId)
-- FIX: now returns BOTH APPROVED and PENDING members, plus MemberStatusCode + OrgStatusCode
DROP PROCEDURE IF EXISTS User_GetMyOrgs //
CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName  AS OrgType,
        o.City,
        o.State,
        rv.ValueName  AS Role,
        rv.ValueCode  AS RoleCode,
        sv.ValueCode  AS MemberStatusCode,   -- APPROVED | PENDING
        os.ValueCode  AS OrgStatusCode,      -- ACTIVE | PENDING | SUSPENDED
        o.MemberCount,
        om.CreatedAt  AS JoinedAt
    FROM OrgMembers om
    JOIN Organisations o   ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    JOIN LookupValues sv   ON om.StatusLkpId = sv.LookupValueId          -- member status (FIXED column)
    JOIN LookupValues rv   ON om.RoleLkpId   = rv.LookupValueId          -- member role
    JOIN LookupValues os   ON o.StatusLkpId  = os.LookupValueId          -- org approval status
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId    = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode IN ('APPROVED', 'PENDING')    -- include join requests + active members
    ORDER BY om.CreatedAt DESC;
END //

-- 16. User_GetBadges — for s-impact screen
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        ub.BadgeLkpId,
        lv.ValueName AS BadgeName,
        lv.ValueCode AS BadgeCode,
        o.OrgName,
        p.Title AS ProjectName,
        ub.AwardedAt
    FROM UserBadges ub
    JOIN LookupValues lv  ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.OrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId = p.ProjectId
    WHERE ub.UserId = p_UserId
    ORDER BY ub.AwardedAt DESC;
END //

-- 17. User_GetImpact — for s-impact dashboard
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        -- from UserProfiles (denormalized)
        up.ImpactScore,
        up.ReliabilityPct,
        -- Projects completed
        (SELECT COUNT(*) FROM ProjectAttendance pa
            JOIN Projects pr ON pa.ProjectId = pr.ProjectId
            WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED') AS ProjectsCompleted,
        -- Total volunteer hours (sum of session durations where attended)
        COALESCE((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM ProjectAttendance pa
            JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
            WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'
        ), 0) AS TotalHours,
        -- Badge count
        (SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId) AS BadgeCount,
        -- Skill count
        (SELECT COUNT(*) FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0) AS SkillCount,
        -- Applications made
        (SELECT COUNT(*) FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0) AS ProjectsApplied,
        -- Certificates earned
        (SELECT COUNT(*) FROM VolunteerCertificates WHERE UserId = p_UserId) AS CertificateCount,
        u.CreatedAt AS MemberSince
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

DELIMITER ;

-- ============================================================
-- Patch v4.1 Section 5 complete.
-- ============================================================
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
-- ============================================================
-- SECTION 6: ORGANISATION MODULE FIXES
-- - ADD ContactPerson to Organisations table
-- - Patch Org_Register SP (add ContactPerson + fix param name)
-- - Patch Org_Update SP (add ContactPerson + Country)
-- - Patch Org_GetProfile SP (return OrgTypeLkpId + StatusLkpId)
-- - NEW Org_GetDashboard SP (admin dashboard KPIs)
-- ============================================================

USE NGOConnect;

-- 18. Add ContactPerson column to Organisations
ALTER TABLE Organisations
    ADD COLUMN ContactPerson VARCHAR(100) NULL AFTER OrgName;

DELIMITER //

-- 19. Org_Register — add ContactPerson, fix param name (p_RegistrationNo not p_RegistrationNumber)
DROP PROCEDURE IF EXISTS Org_Register //
CREATE PROCEDURE Org_Register(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgName        VARCHAR(200),
    IN p_RegistrationNo VARCHAR(100),
    IN p_OrgTypeLkpId   INT UNSIGNED,
    IN p_Category       VARCHAR(100),
    IN p_ContactPerson  VARCHAR(100),
    IN p_About          TEXT,
    IN p_Mission        TEXT,
    IN p_Vision         TEXT,
    IN p_LogoUrl        VARCHAR(500),
    IN p_ContactEmail   VARCHAR(150),
    IN p_ContactPhone   VARCHAR(20),
    IN p_Website        VARCHAR(255),
    IN p_AddressLine1   VARCHAR(200),
    IN p_AddressLine2   VARCHAR(200),
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Pincode        VARCHAR(20),
    IN p_Country        VARCHAR(100)
)
BEGIN
    DECLARE v_Exists       INT DEFAULT 0;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_RoleLkpId    INT UNSIGNED;
    DECLARE v_MemStatLkpId INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM Organisations WHERE RegNumber = p_RegistrationNo AND IsDeleted = 0;
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
            (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
             LogoUrl, ContactEmail, ContactPhone, Website,
             AddressLine1, AddressLine2, City, State, Pincode, Country, StatusLkpId, CreatedBy)
        VALUES
            (p_OrgName, p_ContactPerson, p_OrgTypeLkpId, p_RegistrationNo, p_Category,
             p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website,
             p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode,
             COALESCE(p_Country, 'India'), v_StatusLkpId, p_UserId);

        SET v_OrgId = LAST_INSERT_ID();

        INSERT INTO OrgMembers
            (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
        VALUES
            (v_OrgId, p_UserId, v_RoleLkpId, v_MemStatLkpId, 1, 1, 1, 50, NOW(), p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation registered successfully.' AS Message, v_OrgId AS OrgId;
    END IF;
END //

-- 20. Org_Update — add ContactPerson + Country
DROP PROCEDURE IF EXISTS Org_Update //
CREATE PROCEDURE Org_Update(
    IN p_OrgId         INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_OrgName       VARCHAR(200),
    IN p_Category      VARCHAR(100),
    IN p_ContactPerson VARCHAR(100),
    IN p_About         TEXT,
    IN p_Mission       TEXT,
    IN p_Vision        TEXT,
    IN p_LogoUrl       VARCHAR(500),
    IN p_ContactEmail  VARCHAR(150),
    IN p_ContactPhone  VARCHAR(20),
    IN p_Website       VARCHAR(255),
    IN p_AddressLine1  VARCHAR(200),
    IN p_AddressLine2  VARCHAR(200),
    IN p_City          VARCHAR(100),
    IN p_State         VARCHAR(100),
    IN p_Pincode       VARCHAR(20),
    IN p_Country       VARCHAR(100)
)
BEGIN
    UPDATE Organisations SET
        OrgName       = COALESCE(p_OrgName,       OrgName),
        Category      = COALESCE(p_Category,      Category),
        ContactPerson = COALESCE(p_ContactPerson, ContactPerson),
        About         = COALESCE(p_About,         About),
        Mission       = COALESCE(p_Mission,       Mission),
        Vision        = COALESCE(p_Vision,        Vision),
        LogoUrl       = COALESCE(p_LogoUrl,       LogoUrl),
        ContactEmail  = COALESCE(p_ContactEmail,  ContactEmail),
        ContactPhone  = COALESCE(p_ContactPhone,  ContactPhone),
        Website       = COALESCE(p_Website,       Website),
        AddressLine1  = COALESCE(p_AddressLine1,  AddressLine1),
        AddressLine2  = COALESCE(p_AddressLine2,  AddressLine2),
        City          = COALESCE(p_City,          City),
        State         = COALESCE(p_State,         State),
        Pincode       = COALESCE(p_Pincode,       Pincode),
        Country       = COALESCE(p_Country,       Country),
        UpdatedBy     = p_UserId,
        UpdatedAt     = NOW()
    WHERE OrgId = p_OrgId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Organisation updated.' AS Message;
END //

-- 21. Org_GetProfile — add OrgTypeLkpId + StatusLkpId + ContactPerson for edit pre-fill
DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        o.CreatedAt,
        (SELECT COUNT(*) FROM OrgMembers om
            JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
            JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
              AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- 22. Org_GetDashboard — admin dashboard KPIs (s-admin screen)
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedStatusId INT UNSIGNED;
    DECLARE v_ActiveStatusId   INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT
        -- Total approved members
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0
        ) AS TotalMembers,

        -- New members joined this calendar month
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0
           AND YEAR(CreatedAt) = YEAR(NOW()) AND MONTH(CreatedAt) = MONTH(NOW())
        ) AS NewMembersThisMonth,

        -- Volunteers who attended ≥1 session this month
        (SELECT COUNT(DISTINCT pa.UserId) FROM ProjectAttendance pa
         JOIN Projects p ON pa.ProjectId = p.ProjectId
         WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
           AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW())
        ) AS ActiveVolunteers,

        -- Active rate % (avoid divide-by-zero)
        ROUND(
            CASE WHEN (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0) = 0
                 THEN 0
                 ELSE (SELECT COUNT(DISTINCT pa.UserId) FROM ProjectAttendance pa
                       JOIN Projects p ON pa.ProjectId = p.ProjectId
                       WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
                         AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW()))
                      * 100.0
                      / (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0)
            END, 1
        ) AS ActiveRatePct,

        -- Total volunteer hours attended this month
        COALESCE((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM ProjectAttendance pa
            JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
            JOIN Projects p ON pa.ProjectId = p.ProjectId
            WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
              AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        -- Active projects
        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveStatusId AND IsDeleted = 0
        ) AS ActiveProjects,

        -- Pending membership applications
        (SELECT COUNT(*) FROM OrgMembers om
         JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingApplications;
END //

DELIMITER ;

-- ============================================================
-- Patch v4.1 Section 6 complete.
-- =============================================================

-- ============================================================
-- SECTION 7: Explore & Admin Donor/Volunteer SPs
--   7.1 ALTER TABLE Organisations — add AvgRating, RatingCount, Latitude, Longitude
--   7.2 Org_List (FIXED — keyword + category, always APPROVED, returns rating + coords)
--   7.3 Org_ListRecommended  (match user interests to org category)
--   7.4 Campaign_ListPublicTrending
--   7.5 Org_GetDonationDashboard
--   7.6 Org_GetDonors
--   7.7 Org_GetTransactions
--   7.8 Org_GetVolunteerProfile
--   7.9 Org_GetMemberImpact
--   7.10 Org_UpdateMemberRole
--   7.11 UserBadge_Award
--   7.12 Attendance_ExcuseNoShow
-- ============================================================

-- ── 7.1 ALTER TABLE Organisations ────────────────────────────
ALTER TABLE Organisations
    ADD COLUMN IF NOT EXISTS AvgRating   DECIMAL(3,2) NOT NULL DEFAULT 0.00 COMMENT 'Avg NGO rating (0-5), updated on each rating write',
    ADD COLUMN IF NOT EXISTS RatingCount INT UNSIGNED  NOT NULL DEFAULT 0    COMMENT 'Number of ratings contributing to AvgRating',
    ADD COLUMN IF NOT EXISTS Latitude    DECIMAL(10,7)          NULL         COMMENT 'NGO pin latitude for client-side distance calc',
    ADD COLUMN IF NOT EXISTS Longitude   DECIMAL(10,7)          NULL         COMMENT 'NGO pin longitude';

-- ── 7.2 Org_List ─────────────────────────────────────────────
DELIMITER //
DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Keyword    VARCHAR(200),
    IN p_Category   VARCHAR(100),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ApprovedId  INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Result set 1: page of orgs
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY o.OrgName
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count for pagination
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

-- ── 7.3 Org_ListRecommended ───────────────────────────────────
DROP PROCEDURE IF EXISTS Org_ListRecommended //
CREATE PROCEDURE Org_ListRecommended(
    IN p_UserId INT
)
BEGIN
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Match user interests (by ValueCode) to org Category; rank by match count then avg rating
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude,
        COUNT(ui.UserInterestId) AS MatchScore
    FROM Organisations o
    JOIN UserInterests ui ON 1=1   -- cross to user interests
    JOIN LookupValues  lv ON ui.InterestLkpId = lv.LookupValueId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND ui.UserId = p_UserId
      AND lv.ValueCode = o.Category   -- interest ValueCode matches org Category
    GROUP BY o.OrgId
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

-- ── 7.4 Campaign_ListPublicTrending ──────────────────────────
DROP PROCEDURE IF EXISTS Campaign_ListPublicTrending //
CREATE PROCEDURE Campaign_ListPublicTrending(
    IN p_PageSize INT
)
BEGIN
    SELECT
        dc.CampaignId,
        dc.CampaignName,
        o.OrgName,
        o.LogoUrl           AS OrgLogoUrl,
        dc.RaisedAmount,
        dc.TargetAmount,
        dc.DonorCount,
        ROUND(IF(dc.TargetAmount > 0, dc.RaisedAmount / dc.TargetAmount * 100, 0), 2) AS ProgressPct,
        dc.EndDate,
        dc.BannerUrl,
        dc.IsEmergency
    FROM DonationCampaigns dc
    JOIN Organisations o ON dc.OrgId = o.OrgId
    WHERE dc.IsActive = 1
      AND dc.IsDeleted = 0
      AND o.IsDeleted  = 0
    ORDER BY dc.IsEmergency DESC, dc.DonorCount DESC, dc.RaisedAmount DESC
    LIMIT p_PageSize;
END //

-- ── 7.5 Org_GetDonationDashboard ──────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetDonationDashboard //
CREATE PROCEDURE Org_GetDonationDashboard(
    IN p_OrgId INT
)
BEGIN
    SELECT
        -- All-time total (successful)
        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'), 0) AS TotalRaisedAllTime,

        -- This calendar month
        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND YEAR(dt.CreatedAt) = YEAR(NOW()) AND MONTH(dt.CreatedAt) = MONTH(NOW())), 0) AS ThisMonthRaised,

        -- Last calendar month
        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND YEAR(dt.CreatedAt) = YEAR(DATE_SUB(NOW(), INTERVAL 1 MONTH))
                  AND MONTH(dt.CreatedAt) = MONTH(DATE_SUB(NOW(), INTERVAL 1 MONTH))), 0) AS LastMonthRaised,

        -- Today
        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND DATE(dt.CreatedAt) = CURDATE()), 0) AS TodayRaised,

        IFNULL((SELECT COUNT(*) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND DATE(dt.CreatedAt) = CURDATE()), 0) AS TodayTransactionCount,

        -- Active recurring donations
        IFNULL((SELECT SUM(rd.Amount) FROM RecurringDonations rd
                 JOIN DonationCampaigns dc ON rd.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND rd.IsActive = 1), 0) AS RecurringMonthlyAmount,

        IFNULL((SELECT COUNT(DISTINCT rd.UserId) FROM RecurringDonations rd
                 JOIN DonationCampaigns dc ON rd.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND rd.IsActive = 1), 0) AS ActiveRecurringDonors,

        -- Campaigns
        IFNULL((SELECT COUNT(*) FROM DonationCampaigns WHERE OrgId = p_OrgId AND IsDeleted = 0), 0) AS TotalCampaigns,
        IFNULL((SELECT COUNT(*) FROM DonationCampaigns WHERE OrgId = p_OrgId AND IsDeleted = 0 AND IsActive = 1), 0) AS ActiveCampaigns;
END //

-- ── 7.6 Org_GetDonors ─────────────────────────────────────────
-- tab: ALL | RECURRING | TOP
DROP PROCEDURE IF EXISTS Org_GetDonors //
CREATE PROCEDURE Org_GetDonors(
    IN p_OrgId      INT,
    IN p_Tab        VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    -- Result set 1: donors
    SELECT
        u.UserId,
        IF(dt_agg.IsAnonymous = 1, NULL, up.FullName)  AS FullName,
        IF(dt_agg.IsAnonymous = 1, NULL, u.Email)       AS Email,
        IF(dt_agg.IsAnonymous = 1, NULL, u.MobileNumber) AS Phone,
        dt_agg.TotalDonated,
        dt_agg.DonationCount,
        dt_agg.LastDonatedAt,
        dt_agg.IsAnonymous,
        IF(rd_agg.ActiveCount > 0, 1, 0) AS IsRecurring
    FROM (
        SELECT
            dt.UserId,
            SUM(dt.Amount)    AS TotalDonated,
            COUNT(*)          AS DonationCount,
            MAX(dt.CreatedAt) AS LastDonatedAt,
            MAX(dt.IsAnonymous) AS IsAnonymous
        FROM DonationTransactions dt
        JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
        WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
          AND (p_Tab != 'RECURRING' OR dt.UserId IN (
                SELECT rd.UserId FROM RecurringDonations rd
                JOIN DonationCampaigns dc2 ON rd.CampaignId = dc2.CampaignId
                WHERE dc2.OrgId = p_OrgId AND rd.IsActive = 1))
        GROUP BY dt.UserId
    ) dt_agg
    JOIN Users u ON u.UserId = dt_agg.UserId
    LEFT JOIN UserProfiles up ON up.UserId = u.UserId
    LEFT JOIN (
        SELECT rd.UserId, COUNT(*) AS ActiveCount
        FROM RecurringDonations rd
        JOIN DonationCampaigns dc ON rd.CampaignId = dc.CampaignId
        WHERE dc.OrgId = p_OrgId AND rd.IsActive = 1
        GROUP BY rd.UserId
    ) rd_agg ON rd_agg.UserId = u.UserId
    ORDER BY
        CASE WHEN p_Tab = 'TOP' THEN dt_agg.TotalDonated END DESC,
        dt_agg.LastDonatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count
    SELECT COUNT(DISTINCT dt.UserId) AS TotalCount
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
      AND (p_Tab != 'RECURRING' OR dt.UserId IN (
            SELECT rd.UserId FROM RecurringDonations rd
            JOIN DonationCampaigns dc2 ON rd.CampaignId = dc2.CampaignId
            WHERE dc2.OrgId = p_OrgId AND rd.IsActive = 1));
END //

-- ── 7.7 Org_GetTransactions ───────────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetTransactions //
CREATE PROCEDURE Org_GetTransactions(
    IN p_OrgId      INT,
    IN p_StatusCode VARCHAR(30),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    -- Result set 1: transactions
    SELECT
        dt.TransactionId,
        dt.ReadableId,
        IF(dt.IsAnonymous = 1, NULL, up.FullName) AS DonorName,
        dt.Amount,
        dt.NetAmount,
        dc.CampaignName,
        dt.StatusCode,
        lv.ValueName    AS StatusName,
        dt.PaymentMethod,
        dt.CreatedAt,
        dt.IsAnonymous
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    JOIN LookupValues lv      ON dt.StatusLkpId = lv.LookupValueId
    LEFT JOIN UserProfiles up ON up.UserId = dt.UserId
    WHERE dc.OrgId = p_OrgId
      AND (p_StatusCode IS NULL OR dt.StatusCode = p_StatusCode)
    ORDER BY dt.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count
    SELECT COUNT(*) AS TotalCount
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    WHERE dc.OrgId = p_OrgId
      AND (p_StatusCode IS NULL OR dt.StatusCode = p_StatusCode);
END //

-- ── 7.8 Org_GetVolunteerProfile ───────────────────────────────
-- Admin view: includes reliability score (never return this in public API)
DROP PROCEDURE IF EXISTS Org_GetVolunteerProfile //
CREATE PROCEDURE Org_GetVolunteerProfile(
    IN p_OrgId  INT,
    IN p_UserId INT
)
BEGIN
    SELECT
        u.UserId,
        up.FullName,
        up.City,
        up.Occupation,
        up.ProfilePhoto,
        -- Public impact
        IFNULL((SELECT SUM(ps.DurationHours)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0)       AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT pa.ProjectId)
                FROM ProjectAttendance pa WHERE pa.UserId = p_UserId
                  AND pa.AttendanceStatus = 'ATTENDED'), 0)                                AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId)
                FROM ProjectAttendance pa
                JOIN Projects p ON pa.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0)       AS OrgCount,
        -- Reliability (admin-only)
        ROUND(IFNULL(
            (SELECT attended / total * 100 FROM (
                SELECT
                    SUM(CASE WHEN AttendanceStatus IN ('ATTENDED','EXCUSED') THEN 1 ELSE 0 END) AS attended,
                    COUNT(*) AS total
                FROM ProjectAttendance WHERE UserId = p_UserId
            ) r WHERE total > 0), 100), 2)                                                AS ReliabilityPct,
        IFNULL((SELECT AVG(usr.RatingValue)
                FROM UserSkillRatings usr
                JOIN ProjectSkills ps2 ON usr.ProjectSkillId = ps2.ProjectSkillId
                JOIN Projects p2       ON ps2.ProjectId = p2.ProjectId
                WHERE usr.RatedUserId = p_UserId AND p2.OrgId = p_OrgId), 0)              AS AvgRating,
        IFNULL((SELECT AVG(usr2.RatingValue)
                FROM UserSkillRatings usr2
                WHERE usr2.RatedUserId = p_UserId AND usr2.RaterType = 'PEER'), 0)        AS PeerRating,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId
                AND AttendanceStatus = 'NO_SHOW'), 0)                                     AS NoShowCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId
                AND AttendanceStatus = 'EXCUSED'), 0)                                     AS ExcusedCount,
        0                                                                                  AS ComplaintCount, -- placeholder
        -- Membership in this org
        lv_role.ValueCode   AS RoleCode,
        lv_role.ValueName   AS RoleName,
        lv_status.ValueCode AS StatusCode,
        lv_status.ValueName AS StatusName,
        om.CreatedAt        AS JoinedAt
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId
    LEFT JOIN OrgMembers om        ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role ON lv_role.LookupValueId = om.RoleLkpId
    LEFT JOIN LookupValues lv_status ON lv_status.LookupValueId = om.StatusLkpId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- ── 7.9 Org_GetMemberImpact ───────────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetMemberImpact //
CREATE PROCEDURE Org_GetMemberImpact(
    IN p_OrgId  INT,
    IN p_UserId INT
)
BEGIN
    SELECT
        u.UserId,
        up.FullName,
        up.Occupation,
        up.City,
        lv_role.ValueName AS RoleName,
        up.ImpactScore,
        ROUND(IFNULL(
            (SELECT attended / total * 100 FROM (
                SELECT
                    SUM(CASE WHEN AttendanceStatus IN ('ATTENDED','EXCUSED') THEN 1 ELSE 0 END) AS attended,
                    COUNT(*) AS total
                FROM ProjectAttendance WHERE UserId = p_UserId
            ) r WHERE total > 0), 100), 2)                                               AS ReliabilityPct,
        IFNULL((SELECT SUM(ps.DurationHours)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0)     AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT pa.ProjectId)
                FROM ProjectAttendance pa WHERE pa.UserId = p_UserId
                  AND pa.AttendanceStatus = 'ATTENDED'), 0)                              AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId)
                FROM ProjectAttendance pa
                JOIN Projects p ON pa.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0)     AS OrgCount,
        IFNULL((SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0), 0) AS BadgeCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId
                AND AttendanceStatus = 'NO_SHOW'), 0)                                    AS NoShowCount,
        0                                                                                 AS ComplaintCount
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId
    LEFT JOIN OrgMembers om        ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role ON lv_role.LookupValueId = om.RoleLkpId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- ── 7.10 Org_UpdateMemberRole ─────────────────────────────────
DROP PROCEDURE IF EXISTS Org_UpdateMemberRole //
CREATE PROCEDURE Org_UpdateMemberRole(
    IN p_OrgId     INT,
    IN p_MemberId  INT,   -- OrgMembers.OrgMemberId
    IN p_RoleLkpId INT,
    IN p_UpdatedBy INT
)
BEGIN
    UPDATE OrgMembers
    SET RoleLkpId = p_RoleLkpId,
        UpdatedAt = NOW(),
        UpdatedBy = p_UpdatedBy
    WHERE OrgMemberId = p_MemberId
      AND OrgId       = p_OrgId
      AND IsDeleted   = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Member not found or already deleted.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Member role updated.' AS Message;
    END IF;
END //

-- ── 7.11 UserBadge_Award ─────────────────────────────────────
DROP PROCEDURE IF EXISTS UserBadge_Award //
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId    INT,
    IN p_BadgeLkpId INT,
    IN p_AwardedBy INT,
    IN p_OrgId     INT,
    IN p_ProjectId INT
)
BEGIN
    INSERT INTO UserBadges (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
    VALUES (p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());

    SELECT 1 AS IsSuccess, 'Badge awarded successfully.' AS Message, LAST_INSERT_ID() AS BadgeId;
END //

-- ── 7.12 Attendance_ExcuseNoShow ──────────────────────────────
DROP PROCEDURE IF EXISTS Attendance_ExcuseNoShow //
CREATE PROCEDURE Attendance_ExcuseNoShow(
    IN p_AttendanceId INT,
    IN p_OrgId        INT,
    IN p_ExcusedBy    INT
)
BEGIN
    UPDATE ProjectAttendance pa
    JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
    JOIN Projects p         ON ps.ProjectId = p.ProjectId
    SET pa.AttendanceStatus = 'EXCUSED',
        pa.UpdatedAt        = NOW()
    WHERE pa.AttendanceId = p_AttendanceId
      AND pa.AttendanceStatus = 'NO_SHOW'
      AND p.OrgId = p_OrgId;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Attendance record not found or not a no-show in this org.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show excused. Reliability score will adjust.' AS Message;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- Patch v4.1 Section 7 complete.
-- Run this file once on the MySQL 8 database.
-- Total changes: 6 DB ALTERs + 11 new/fixed SPs.
-- ============================================================

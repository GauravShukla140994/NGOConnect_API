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
        up.IsProfileComplete
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
CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName AS OrgType,
        o.City,
        o.State,
        rv.ValueName AS Role,
        rv.ValueCode AS RoleCode,
        o.MemberCount,
        om.CreatedAt AS JoinedAt
    FROM OrgMembers om
    JOIN Organisations o  ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    JOIN LookupValues sv  ON om.ApprovalStatusLkpId = sv.LookupValueId
    JOIN LookupValues rv  ON om.RoleLkpId = rv.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode = 'APPROVED'
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

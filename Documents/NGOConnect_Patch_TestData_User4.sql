-- =============================================================================
-- NGO Connect — Test Data Patch: UserId = 4
-- Purpose : Pre-populate all Edit-Profile fields for UserId 4.
-- Fix     : LookupValues has LookupTypeId FK — TypeCode lives on LookupTypes.
--           All subqueries now JOIN LookupTypes to resolve TypeCode.
-- Run     : MySQL Workbench → run once against your dev database.
-- =============================================================================

-- Helper: shorthand function-style subquery we reuse many times
-- Pattern: lv = LookupValues alias, lt = LookupTypes alias

-- ── 1. UserProfiles UPSERT ────────────────────────────────────────────────────
-- UNIQUE KEY uq_profile_user (UserId, IsDeleted) triggers ON DUPLICATE KEY UPDATE
-- when a row with (UserId=4, IsDeleted=0) already exists.

INSERT INTO UserProfiles (
    UserId,
    FirstName,
    LastName,
    DateOfBirth,
    GenderLkpId,
    Bio,
    ProfilePhoto,
    Occupation,
    Organisation,
    VolunteerExp,
    EducationLkpId,
    FieldOfStudy,
    WorkExpLkpId,
    AddressLine1,
    AddressLine2,
    City,
    State,
    Pincode,
    Country
)
VALUES (
    4,
    'Gaurav',
    'Shukla',
    '1990-09-14',
    -- GenderLkpId: join LookupTypes to get LookupValueId for MALE
    (SELECT lv.LookupValueId
     FROM   LookupValues lv
     JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
     WHERE  lt.TypeCode  = 'GENDER'
       AND  lv.ValueCode = 'MALE'
     LIMIT  1),
    'Passionate project manager and software developer committed to leveraging technology for social impact. 12+ years of experience in C# and .NET, now channelling that expertise into building NGO Connect — a platform that bridges volunteers, donors, and NGOs across India.',
    NULL,
    'Project Manager & Software Developer',
    'NGO Connect',
    'Conducted coding bootcamps for underprivileged youth (2 years). Organised blood donation drives with Red Cross. Mentored first-generation college students through NSS.',
    -- EducationLkpId: BACHELOR
    (SELECT lv.LookupValueId
     FROM   LookupValues lv
     JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
     WHERE  lt.TypeCode  = 'EDUCATION'
       AND  lv.ValueCode = 'BACHELOR'
     LIMIT  1),
    'Computer Science & Engineering',
    -- WorkExpLkpId: pick the 10+ years option (ValueCode varies by seed — take last OrderNo)
    (SELECT lv.LookupValueId
     FROM   LookupValues lv
     JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
     WHERE  lt.TypeCode  = 'WORK_EXP'
     ORDER  BY lv.OrderNo DESC
     LIMIT  1),
    'Flat 402, Skyview Apartments',
    'Sector 21, Dwarka',
    'New Delhi',
    'Delhi',
    '110075',
    'India'
)
ON DUPLICATE KEY UPDATE
    FirstName      = VALUES(FirstName),
    LastName       = VALUES(LastName),
    DateOfBirth    = VALUES(DateOfBirth),
    GenderLkpId    = VALUES(GenderLkpId),
    Bio            = VALUES(Bio),
    Occupation     = VALUES(Occupation),
    Organisation   = VALUES(Organisation),
    VolunteerExp   = VALUES(VolunteerExp),
    EducationLkpId = VALUES(EducationLkpId),
    FieldOfStudy   = VALUES(FieldOfStudy),
    WorkExpLkpId   = VALUES(WorkExpLkpId),
    AddressLine1   = VALUES(AddressLine1),
    AddressLine2   = VALUES(AddressLine2),
    City           = VALUES(City),
    State          = VALUES(State),
    Pincode        = VALUES(Pincode),
    Country        = VALUES(Country),
    UpdatedAt      = NOW();

-- ── 2. UserSafetyPreferences UPSERT ──────────────────────────────────────────
-- UNIQUE KEY uq_safepref_user (UserId) triggers ON DUPLICATE KEY UPDATE.

INSERT INTO UserSafetyPreferences (
    UserId,
    EmergVisibilityLkpId,
    AutoShareDurLkpId,
    AllowLocDuringSos,
    AllowLocDuringProj,
    EmergencyContactName,
    EmergencyContactPhone,
    EmergencyContactRelation
)
VALUES (
    4,
    -- EmergVisibilityLkpId: Admin + Moderators (recommended)
    (SELECT lv.LookupValueId
     FROM   LookupValues lv
     JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
     WHERE  lt.TypeCode  = 'EMERGENCY_VISIBILITY'
       AND  lv.ValueCode = 'ADMIN_MODS'
     LIMIT  1),
    -- AutoShareDurLkpId: 1 Hour
    (SELECT lv.LookupValueId
     FROM   LookupValues lv
     JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
     WHERE  lt.TypeCode  = 'AUTO_SHARE_DURATION'
       AND  lv.ValueCode = 'HOUR_1'
     LIMIT  1),
    1,
    1,
    'Priya Shukla',
    '+919876543210',
    'Spouse'
)
ON DUPLICATE KEY UPDATE
    EmergVisibilityLkpId     = VALUES(EmergVisibilityLkpId),
    AutoShareDurLkpId        = VALUES(AutoShareDurLkpId),
    AllowLocDuringSos        = 1,
    AllowLocDuringProj       = 1,
    EmergencyContactName     = 'Priya Shukla',
    EmergencyContactPhone    = '+919876543210',
    EmergencyContactRelation = 'Spouse',
    UpdatedAt                = NOW();

-- ── 3. UserSkills — INSERT IGNORE (UNIQUE on UserId + SkillName + IsDeleted) ──

INSERT IGNORE INTO UserSkills (UserId, SkillName)
VALUES
    (4, 'Project Management'),
    (4, 'C# / .NET Development'),
    (4, 'SQL & Database Design'),
    (4, 'Team Leadership'),
    (4, 'Volunteer Coordination');

-- ── 4. UserInterests — INSERT IGNORE (UNIQUE on UserId + InterestLkpId) ───────
-- Pick the first 3 INTEREST lookup values seeded in the DB.

INSERT IGNORE INTO UserInterests (UserId, InterestLkpId)
SELECT 4, lv.LookupValueId
FROM   LookupValues lv
JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
WHERE  lt.TypeCode  = 'INTEREST_TYPE'
  AND  lv.IsDeleted = 0
ORDER  BY lv.OrderNo ASC
LIMIT  3;

-- ── 5. Verify ─────────────────────────────────────────────────────────────────

SELECT
    u.UserId,
    u.Email,
    up.FirstName,
    up.LastName,
    up.City,
    up.Occupation,
    gv.ValueName   AS Gender,
    ev.ValueName   AS Education,
    wv.ValueName   AS WorkExp,
    sp.AllowLocDuringSos,
    sp.AllowLocDuringProj,
    emv.ValueName  AS EmergVisibility,
    asv.ValueName  AS AutoShareDuration
FROM       Users                 u
LEFT JOIN  UserProfiles          up  ON up.UserId  = u.UserId  AND up.IsDeleted = 0
LEFT JOIN  LookupValues          gv  ON gv.LookupValueId = up.GenderLkpId
LEFT JOIN  LookupValues          ev  ON ev.LookupValueId = up.EducationLkpId
LEFT JOIN  LookupValues          wv  ON wv.LookupValueId = up.WorkExpLkpId
LEFT JOIN  UserSafetyPreferences sp  ON sp.UserId  = u.UserId  AND sp.IsDeleted = 0
LEFT JOIN  LookupValues          emv ON emv.LookupValueId = sp.EmergVisibilityLkpId
LEFT JOIN  LookupValues          asv ON asv.LookupValueId = sp.AutoShareDurLkpId
WHERE  u.UserId = 4;

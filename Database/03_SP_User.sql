-- =============================================================================
-- NGO Connect — Stored Procedures: User Module
-- Run AFTER 01_Tables_Auth_User.sql and 02_SP_Auth.sql
-- SPs: User_GetProfile, User_GetPublicProfile, User_UpdateProfile,
--      User_GetSkills, User_AddSkill, User_RemoveSkill
--
-- DB Column corrections vs original:
--   UserProfiles.Bio           (not About)
--   UserProfiles.ProfilePhoto  (not ProfilePhotoUrl)
--   NO DisplayName, LinkedInUrl, WebsiteUrl columns in DB
--   Users.Mobile               (not MobileNumber)
--   UserSkills: text-based (SkillName VARCHAR, AvgRating, RatingCount)
--               NOT FK-based (no SkillLkpId, no ProficiencyLkpId)
-- =============================================================================

DELIMITER //

-- ── User_GetProfile ───────────────────────────────────────────────────────────
-- Called by: UserDal.GetProfileAsync (ExecuteGetAsync → typed UserProfileModel)
-- Params: UserId
-- Returns: Full profile row including PII — only for authenticated own-profile fetch
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_GetProfile //
CREATE PROCEDURE User_GetProfile(
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        u.UserId,
        u.Mobile,                                                       -- was MobileNumber
        u.CountryCode,
        u.Email,
        up.FirstName,
        up.LastName,
        up.Bio                                                          AS Bio,          -- was About
        lv.ValueCode                                                    AS GenderValueCode,
        up.DateOfBirth,
        up.ProfilePhoto                                                 AS ProfilePhoto, -- was ProfilePhotoUrl
        up.Occupation,
        up.Organisation,
        up.City,
        up.State,
        up.Country,
        up.ImpactScore,
        up.ReliabilityPct,
        u.CreatedAt,
        u.UpdatedAt,
        CASE WHEN up.FirstName IS NOT NULL AND up.FirstName != ''
              AND up.LastName  IS NOT NULL AND up.LastName  != ''
             THEN 1 ELSE 0
        END                                                             AS IsProfileComplete
    FROM       Users        u
    LEFT JOIN  UserProfiles up ON up.UserId        = u.UserId AND up.IsDeleted = 0
    LEFT JOIN  LookupValues lv ON lv.LookupValueId = up.GenderLkpId
    WHERE  u.UserId    = p_UserId
      AND  u.IsDeleted = 0;
END //


-- ── User_GetPublicProfile ─────────────────────────────────────────────────────
-- Called by: UserDal.GetPublicProfileAsync (ExecuteDynamicGetAsync → DynamicRow)
-- Params: UserId
-- Returns: Public-safe fields only — no mobile, no email
-- DynamicRow benefit: add a new column here → appears in JSON immediately, zero C# change
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_GetPublicProfile //
CREATE PROCEDURE User_GetPublicProfile(
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        u.UserId,
        CONCAT_WS(' ', up.FirstName, up.LastName)                       AS FullName,
        up.FirstName,
        up.LastName,
        up.Bio                                                          AS Bio,
        lv.ValueName                                                    AS Gender,
        up.ProfilePhoto                                                 AS ProfilePhoto,
        up.Occupation,
        up.City,
        up.State,
        up.Country,
        up.ImpactScore,
        up.ReliabilityPct,
        u.CreatedAt                                                     AS MemberSince
    FROM       Users        u
    LEFT JOIN  UserProfiles up ON up.UserId        = u.UserId AND up.IsDeleted = 0
    LEFT JOIN  LookupValues lv ON lv.LookupValueId = up.GenderLkpId
    WHERE  u.UserId    = p_UserId
      AND  u.IsDeleted = 0
      AND  u.IsActive  = 1;
END //


-- ── User_UpdateProfile ────────────────────────────────────────────────────────
-- Called by: UserDal.UpdateProfileAsync (ExecuteWriteAsync → WriteResult)
-- Params: match UpdateProfileRequest C# model (p_About maps to DB column Bio)
-- Returns: IsSuccess INT, Message VARCHAR
-- Pattern: UPSERT (ON DUPLICATE KEY) — profile row always exists after first login
-- PATCH semantics: only non-null params overwrite existing data
-- Note: DisplayName, LinkedInUrl, WebsiteUrl params removed — do not exist in DB
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_UpdateProfile //
CREATE PROCEDURE User_UpdateProfile(
    IN p_UserId       INT UNSIGNED,
    IN p_FirstName    VARCHAR(80),
    IN p_LastName     VARCHAR(80),
    IN p_About        TEXT,           -- maps to DB column: Bio
    IN p_GenderLkpId  INT UNSIGNED,
    IN p_DateOfBirth  DATE,
    IN p_Occupation   VARCHAR(150),
    IN p_City         VARCHAR(100),
    IN p_State        VARCHAR(100),
    IN p_Country      VARCHAR(100)
)
BEGIN
    IF EXISTS (SELECT 1 FROM UserProfiles WHERE UserId = p_UserId AND IsDeleted = 0) THEN
        -- PATCH UPDATE — only overwrite non-null params
        UPDATE UserProfiles
        SET
            FirstName   = COALESCE(p_FirstName,   FirstName),
            LastName    = COALESCE(p_LastName,    LastName),
            Bio         = COALESCE(p_About,       Bio),          -- API param "About" → DB column "Bio"
            GenderLkpId = COALESCE(p_GenderLkpId, GenderLkpId),
            DateOfBirth = COALESCE(p_DateOfBirth, DateOfBirth),
            Occupation  = COALESCE(p_Occupation,  Occupation),
            City        = COALESCE(p_City,        City),
            State       = COALESCE(p_State,       State),
            Country     = COALESCE(p_Country,     Country),
            UpdatedAt   = NOW()
        WHERE UserId    = p_UserId
          AND IsDeleted = 0;
    ELSE
        -- Profile row missing (shouldn't happen after VerifyOTP, but handle gracefully)
        INSERT INTO UserProfiles (
            UserId, FirstName, LastName, Bio, GenderLkpId,
            DateOfBirth, Occupation, City, State, Country
        )
        VALUES (
            p_UserId,
            COALESCE(p_FirstName, ''),
            COALESCE(p_LastName, ''),
            p_About,
            p_GenderLkpId,
            p_DateOfBirth,
            p_Occupation,
            p_City,
            p_State,
            p_Country
        );
    END IF;

    -- Sync UpdatedAt on Users table too
    UPDATE Users SET UpdatedAt = NOW() WHERE UserId = p_UserId;

    SELECT 1 AS IsSuccess, 'Profile updated successfully.' AS Message;
END //


-- ── User_GetSkills ────────────────────────────────────────────────────────────
-- Called by: UserDal.GetSkillsAsync (ExecuteReaderListAsync → DataReader, typed)
-- Params: UserId
-- Returns: UserSkillId, SkillName, AvgRating, RatingCount
-- DB structure: UserSkills(UserSkillId, UserId, SkillName VARCHAR(100), AvgRating, RatingCount)
-- NOT FK-based — skills are free-text, rated by peers after project sessions
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_GetSkills //
CREATE PROCEDURE User_GetSkills(
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        us.UserSkillId,
        us.SkillName,
        us.AvgRating,
        us.RatingCount
    FROM   UserSkills us
    WHERE  us.UserId    = p_UserId
      AND  us.IsDeleted = 0
    ORDER BY us.SkillName ASC;
END //


-- ── User_AddSkill ─────────────────────────────────────────────────────────────
-- Called by: UserDal.AddSkillAsync (ExecuteWriteAsync → WriteResult)
-- Params: UserId, SkillName (free text)
-- Returns: IsSuccess INT, Message VARCHAR, UserSkillId INT
-- Logic: UPSERT on (UserId, SkillName) — if skill exists, undeletes it; else inserts
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_AddSkill //
CREATE PROCEDURE User_AddSkill(
    IN p_UserId    INT UNSIGNED,
    IN p_SkillName VARCHAR(100)
)
BEGIN
    DECLARE v_ExistingId INT UNSIGNED DEFAULT 0;

    -- Check if skill already exists (active or soft-deleted)
    SELECT UserSkillId INTO v_ExistingId
    FROM   UserSkills
    WHERE  UserId    = p_UserId
      AND  SkillName = p_SkillName
    LIMIT  1;

    IF v_ExistingId > 0 THEN
        -- Undelete if soft-deleted; otherwise it already exists (no-op)
        UPDATE UserSkills
        SET    IsDeleted  = 0,
               UpdatedAt  = NOW()
        WHERE  UserSkillId = v_ExistingId;

        SELECT 1 AS IsSuccess, 'Skill already in profile.' AS Message, v_ExistingId AS UserSkillId;
    ELSE
        INSERT INTO UserSkills (UserId, SkillName)
        VALUES (p_UserId, p_SkillName);

        SELECT 1 AS IsSuccess, 'Skill added successfully.' AS Message, LAST_INSERT_ID() AS UserSkillId;
    END IF;
END //


-- ── User_RemoveSkill ──────────────────────────────────────────────────────────
-- Called by: UserDal.RemoveSkillAsync (ExecuteWriteAsync → WriteResult)
-- Params: UserId, UserSkillId
-- Returns: IsSuccess INT, Message VARCHAR
-- Security: UserId check ensures users can only remove their own skills
-- Uses soft delete (IsDeleted = 1) to preserve skill rating history
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_RemoveSkill //
CREATE PROCEDURE User_RemoveSkill(
    IN p_UserId      INT UNSIGNED,
    IN p_UserSkillId INT UNSIGNED
)
BEGIN
    UPDATE UserSkills
    SET    IsDeleted  = 1,
           UpdatedAt  = NOW()
    WHERE  UserSkillId = p_UserSkillId
      AND  UserId      = p_UserId
      AND  IsDeleted   = 0;

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'Skill removed successfully.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Skill not found or you do not own this skill.' AS Message;
    END IF;
END //


DELIMITER ;

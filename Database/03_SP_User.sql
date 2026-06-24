-- =============================================================================
-- NGO Connect — Stored Procedures: User Module
-- Run AFTER 01_Tables_Auth_User.sql and 02_SP_Auth.sql
-- SPs: User_GetProfile, User_GetPublicProfile, User_UpdateProfile,
--      User_GetSkills, User_AddSkill, User_RemoveSkill
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
        u.MobileNumber,
        u.CountryCode,
        u.Email,
        up.FirstName,
        up.LastName,
        up.DisplayName,
        up.About,
        lv.ValueCode                                                    AS GenderValueCode,
        up.DateOfBirth,
        up.ProfilePhotoUrl,
        up.City,
        up.State,
        up.Country,
        up.LinkedInUrl,
        up.WebsiteUrl,
        u.CreatedAt,
        u.UpdatedAt,
        -- IsProfileComplete: true when at minimum FirstName AND LastName are filled
        CASE WHEN up.FirstName IS NOT NULL AND up.LastName IS NOT NULL
             THEN 1 ELSE 0
        END                                                             AS IsProfileComplete
    FROM       Users        u
    LEFT JOIN  UserProfiles up ON up.UserId        = u.UserId
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
        COALESCE(
            up.DisplayName,
            CONCAT_WS(' ', up.FirstName, up.LastName)
        )                                                               AS DisplayName,
        up.FirstName,
        up.LastName,
        up.About,
        lv.ValueName                                                    AS Gender,
        up.ProfilePhotoUrl,
        up.City,
        up.State,
        up.Country,
        up.LinkedInUrl,
        up.WebsiteUrl,
        u.CreatedAt                                                     AS MemberSince
    FROM       Users        u
    LEFT JOIN  UserProfiles up ON up.UserId        = u.UserId
    LEFT JOIN  LookupValues lv ON lv.LookupValueId = up.GenderLkpId
    WHERE  u.UserId    = p_UserId
      AND  u.IsDeleted = 0
      AND  u.IsActive  = 1;
END //


-- ── User_UpdateProfile ────────────────────────────────────────────────────────
-- Called by: UserDal.UpdateProfileAsync (ExecuteWriteAsync → WriteResult)
-- Params: All profile fields (all nullable — COALESCE preserves existing values)
-- Returns: IsSuccess INT, Message VARCHAR
-- Pattern: UPSERT (ON DUPLICATE KEY) — profile row always exists after first login
-- PATCH semantics: only non-null params overwrite existing data
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_UpdateProfile //
CREATE PROCEDURE User_UpdateProfile(
    IN p_UserId       INT UNSIGNED,
    IN p_FirstName    VARCHAR(100),
    IN p_LastName     VARCHAR(100),
    IN p_DisplayName  VARCHAR(200),
    IN p_About        TEXT,
    IN p_GenderLkpId  INT UNSIGNED,
    IN p_DateOfBirth  DATE,
    IN p_City         VARCHAR(100),
    IN p_State        VARCHAR(100),
    IN p_Country      VARCHAR(100),
    IN p_LinkedInUrl  VARCHAR(500),
    IN p_WebsiteUrl   VARCHAR(500)
)
BEGIN
    INSERT INTO UserProfiles (
        UserId, FirstName, LastName, DisplayName, About,
        GenderLkpId, DateOfBirth, City, State, Country,
        LinkedInUrl, WebsiteUrl, UpdatedAt
    )
    VALUES (
        p_UserId,
        p_FirstName,  p_LastName,    p_DisplayName, p_About,
        p_GenderLkpId, p_DateOfBirth, p_City,       p_State, p_Country,
        p_LinkedInUrl, p_WebsiteUrl,  NOW()
    )
    ON DUPLICATE KEY UPDATE
        -- COALESCE: only overwrite if the incoming param is NOT NULL
        -- This enables true PATCH semantics from a single SP
        FirstName    = COALESCE(p_FirstName,    FirstName),
        LastName     = COALESCE(p_LastName,     LastName),
        DisplayName  = COALESCE(p_DisplayName,  DisplayName),
        About        = COALESCE(p_About,        About),
        GenderLkpId  = COALESCE(p_GenderLkpId,  GenderLkpId),
        DateOfBirth  = COALESCE(p_DateOfBirth,  DateOfBirth),
        City         = COALESCE(p_City,         City),
        State        = COALESCE(p_State,        State),
        Country      = COALESCE(p_Country,      Country),
        LinkedInUrl  = COALESCE(p_LinkedInUrl,  LinkedInUrl),
        WebsiteUrl   = COALESCE(p_WebsiteUrl,   WebsiteUrl),
        UpdatedAt    = NOW();

    -- Sync UpdatedAt on Users table too
    UPDATE Users SET UpdatedAt = NOW() WHERE UserId = p_UserId;

    SELECT 1 AS IsSuccess, 'Profile updated successfully.' AS Message;
END //


-- ── User_GetSkills ────────────────────────────────────────────────────────────
-- Called by: UserDal.GetSkillsAsync (ExecuteReaderListAsync → DataReader, typed)
-- Params: UserId
-- Returns: skill rows joined with lookup names
-- DataReader: streamed for speed — called on every profile load
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_GetSkills //
CREATE PROCEDURE User_GetSkills(
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        us.UserSkillId,
        us.SkillLkpId,
        lv_skill.ValueName                                              AS SkillName,
        us.ProficiencyLkpId,
        lv_prof.ValueName                                               AS ProficiencyName
    FROM       UserSkills   us
    JOIN       LookupValues lv_skill ON lv_skill.LookupValueId = us.SkillLkpId
    JOIN       LookupValues lv_prof  ON lv_prof.LookupValueId  = us.ProficiencyLkpId
    WHERE      us.UserId = p_UserId
    ORDER BY   lv_skill.ValueName ASC;
END //


-- ── User_AddSkill ─────────────────────────────────────────────────────────────
-- Called by: UserDal.AddSkillAsync (ExecuteWriteAsync → WriteResult)
-- Params: UserId, SkillLkpId, ProficiencyLkpId
-- Returns: IsSuccess INT, Message VARCHAR
-- Logic: UPSERT — if skill exists for user, updates proficiency; else inserts new
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_AddSkill //
CREATE PROCEDURE User_AddSkill(
    IN p_UserId           INT UNSIGNED,
    IN p_SkillLkpId       INT UNSIGNED,
    IN p_ProficiencyLkpId INT UNSIGNED
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM UserSkills
        WHERE  UserId = p_UserId AND SkillLkpId = p_SkillLkpId
    ) THEN
        -- Skill already added — update proficiency level
        UPDATE UserSkills
        SET    ProficiencyLkpId = p_ProficiencyLkpId
        WHERE  UserId           = p_UserId
          AND  SkillLkpId       = p_SkillLkpId;

        SELECT 1 AS IsSuccess, 'Skill proficiency updated successfully.' AS Message;
    ELSE
        -- New skill — insert
        INSERT INTO UserSkills (UserId, SkillLkpId, ProficiencyLkpId)
        VALUES (p_UserId, p_SkillLkpId, p_ProficiencyLkpId);

        SELECT 1 AS IsSuccess, 'Skill added successfully.' AS Message;
    END IF;
END //


-- ── User_RemoveSkill ──────────────────────────────────────────────────────────
-- Called by: UserDal.RemoveSkillAsync (ExecuteWriteAsync → WriteResult)
-- Params: UserId, UserSkillId
-- Returns: IsSuccess INT, Message VARCHAR
-- Security: UserId check ensures users can only remove their own skills
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS User_RemoveSkill //
CREATE PROCEDURE User_RemoveSkill(
    IN p_UserId      INT UNSIGNED,
    IN p_UserSkillId INT UNSIGNED
)
BEGIN
    DELETE FROM UserSkills
    WHERE  UserSkillId = p_UserSkillId
      AND  UserId      = p_UserId;     -- ownership check — cannot remove other users' skills

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'Skill removed successfully.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Skill not found or you do not own this skill.' AS Message;
    END IF;
END //


DELIMITER ;

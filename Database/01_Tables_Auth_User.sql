-- =============================================================================
-- NGO Connect — Table DDL: Auth + User Groups
-- Run this ONCE on a fresh database (or use IF NOT EXISTS for safety)
-- Groups: 1-Auth (Users, OtpTokens, RefreshTokens)
--         2-Profiles (UserProfiles, UserSkills)
-- =============================================================================

-- ── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS Users (
    UserId        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    MobileNumber  VARCHAR(15)     NOT NULL,
    CountryCode   VARCHAR(5)      NOT NULL DEFAULT '+91',
    Email         VARCHAR(255)    NULL,
    RoleLkpId     INT UNSIGNED    NOT NULL,               -- FK → LookupValues (TypeCode='USER_ROLE')
    IsActive      TINYINT(1)      NOT NULL DEFAULT 1,
    IsVerified    TINYINT(1)      NOT NULL DEFAULT 0,
    IsDeleted     TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt     DATETIME        NULL,
    DeletedBy     INT UNSIGNED    NULL,
    CreatedAt     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt     DATETIME        NULL,
    PRIMARY KEY (UserId),
    UNIQUE KEY uq_mobile_country (MobileNumber, CountryCode),
    UNIQUE KEY uq_email (Email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── OtpTokens ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS OtpTokens (
    OtpTokenId    INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId        INT UNSIGNED    NULL,                   -- NULL for unregistered users
    Recipient     VARCHAR(255)    NOT NULL,               -- mobile number or email
    CountryCode   VARCHAR(5)      NOT NULL DEFAULT '+91',
    OtpCode       VARCHAR(6)      NOT NULL,               -- 6-digit, stored plain (generated in C#)
    PurposeLkpId  INT UNSIGNED    NOT NULL,               -- FK → LookupValues (TypeCode='OTP_PURPOSE')
    AttemptCount  TINYINT         NOT NULL DEFAULT 0,     -- max 3 attempts then lock
    IsUsed        TINYINT(1)      NOT NULL DEFAULT 0,
    IpAddress     VARCHAR(45)     NULL,
    ExpiresAt     DATETIME        NOT NULL,
    CreatedAt     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (OtpTokenId),
    INDEX idx_recipient_purpose (Recipient, PurposeLkpId),
    INDEX idx_expires (ExpiresAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── RefreshTokens ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS RefreshTokens (
    RefreshTokenId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    Token           VARCHAR(512)    NOT NULL,              -- SHA-256 hashed in C# before storing
    DeviceInfo      VARCHAR(500)    NULL,
    IpAddress       VARCHAR(45)     NULL,
    IsRevoked       TINYINT(1)      NOT NULL DEFAULT 0,
    ExpiresAt       DATETIME        NOT NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (RefreshTokenId),
    INDEX idx_token (Token),
    INDEX idx_user_active (UserId, IsRevoked, ExpiresAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── UserProfiles ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS UserProfiles (
    UserProfileId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    FirstName       VARCHAR(100)    NULL,
    LastName        VARCHAR(100)    NULL,
    DisplayName     VARCHAR(200)    NULL,
    About           TEXT            NULL,
    GenderLkpId     INT UNSIGNED    NULL,                  -- FK → LookupValues (TypeCode='GENDER')
    DateOfBirth     DATE            NULL,
    ProfilePhotoUrl VARCHAR(500)    NULL,
    City            VARCHAR(100)    NULL,
    State           VARCHAR(100)    NULL,
    Country         VARCHAR(100)    NULL DEFAULT 'India',
    LinkedInUrl     VARCHAR(500)    NULL,
    WebsiteUrl      VARCHAR(500)    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NULL,
    PRIMARY KEY (UserProfileId),
    UNIQUE KEY uq_user (UserId)                            -- one profile per user
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── UserSkills ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS UserSkills (
    UserSkillId       INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId            INT UNSIGNED    NOT NULL,
    SkillLkpId        INT UNSIGNED    NOT NULL,            -- FK → LookupValues (TypeCode='SKILL')
    ProficiencyLkpId  INT UNSIGNED    NOT NULL,            -- FK → LookupValues (TypeCode='SKILL_PROFICIENCY')
    CreatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (UserSkillId),
    UNIQUE KEY uq_user_skill (UserId, SkillLkpId),
    INDEX idx_user (UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

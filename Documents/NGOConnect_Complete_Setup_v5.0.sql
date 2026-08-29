-- ============================================================
-- NGO CONNECT — COMPLETE DATABASE SETUP
-- Version    : 4.8
-- Date       : 2026-07-13
-- Database   : MySQL 8.0+  |  utf8mb4_unicode_ci
-- Tables     : 53  |  Stored Procedures : 143
-- Run on a BLANK MySQL instance. This drops and recreates NGOConnect.
--
-- v4.8 changes (cumulative — this file creates a fresh v4.8 DB):
--   TABLES ADDED      : PostSaves, FeedInteractions
--   TABLE COLS ADDED  : Posts.IsEmergency, IsEvergreen, ShareCount, SaveCount
--                       Posts.idx_post_emergency (IsEmergency, CreatedAt)
--                       ProjectSkills.idx_projskill_project (ProjectId, SkillName) covering index
--   LOOKUP VALUES     : OTP_PURPOSE: ADD_PHONE (OrderNo 5), ADD_EMAIL (OrderNo 6)
--   SETTINGS SEEDS    : 22 FEED_* settings (FEED group)
--   SPs ADDED   (8)  : Feed_GetPersonalized, Post_Save, Post_Unsave, Feed_TrackInteraction,
--                       Project_GetNearbyFeed, User_SendContactOtp, User_VerifyContactOtp,
--                       (SuperAdmin_NGOApproval set from v4.6 patch)
--   SPs FIXED         : Post_GetFeed, Post_GetById (IsLiked alias), User_GetImpact (TotalRanked)
--                       Community_CreatePost (AUDIENCE_TYPE), Community_CreatePoll (p_IsMultiChoice)
--                       Community_GetFeed (v4.3 columns), Community_GetFeed (PollOptionsJson)
-- v4.1 changes (cumulative — this file creates a fresh v4.1 DB):
--   TABLE COLS ADDED : UserProfiles.VolunteerExp
--                      UserSafetyPreferences.EmergencyContactName/Phone/Relation
--                      UserInterests.InterestLkpId (replaced InterestName FK)
--                      Organisations.ContactPerson, AvgRating, RatingCount, Latitude, Longitude
--   NEW LOOKUP       : INTEREST_TYPE (LookupType #45, 8 values)
--   SPs REPLACED (10): User_GetProfile, User_UpdateProfile, User_UpdateSafetyPrefs,
--                       User_SaveInterests, Lookup_GetValueByCode,
--                       Org_Register, Org_Update, Org_GetProfile, Org_List, UserBadge_Award
--   SPs ADDED (15)   : User_GetSafetyPrefs, User_GetInterests, User_GetMyOrgs,
--                       User_GetBadges, User_GetImpact,
--                       Org_GetDashboard, Org_ListRecommended, Campaign_ListPublicTrending,
--                       Org_GetDonationDashboard, Org_GetDonors, Org_GetTransactions,
--                       Org_GetVolunteerProfile, Org_GetMemberImpact,
--                       Org_UpdateMemberRole, Attendance_ExcuseNoShow
-- ============================================================

SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = '+05:30';

DROP DATABASE IF EXISTS ngoconnect;
CREATE DATABASE ngoconnect CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ngoconnect;
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
-- SECTION 1: TABLES (45 total)
-- ============================================================

-- ── GROUP 1: AUTH (3 tables) ──────────────────────────────────

CREATE TABLE Users (
    UserId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    Mobile          VARCHAR(20)     NULL,
    Email           VARCHAR(150)    NULL,
    PasswordHash    VARCHAR(255)    NULL,
    CountryCode     VARCHAR(6)      NOT NULL DEFAULT '+91',
    IsVerified      TINYINT(1)      NOT NULL DEFAULT 0,
    IsActive        TINYINT(1)      NOT NULL DEFAULT 1,
    ProfileVerificationLkpId INT UNSIGNED NULL,
    LastLoginAt     DATETIME        NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    ScheduledDeletionAt DATETIME    NULL DEFAULT NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    -- Generated columns: Mobile/Email when active (IsDeleted=0), NULL when soft-deleted.
    -- NULLs are never compared in UNIQUE indexes → multiple deleted rows per mobile/email allowed,
    -- but only ONE active row per mobile/email enforced.
    MobileActive    VARCHAR(20)     GENERATED ALWAYS AS (IF(IsDeleted = 0, Mobile, NULL)) VIRTUAL,
    EmailActive     VARCHAR(150)    GENERATED ALWAYS AS (IF(IsDeleted = 0, Email,  NULL)) VIRTUAL,
    PRIMARY KEY (UserId),
    UNIQUE KEY uq_users_mobile_active (MobileActive),
    UNIQUE KEY uq_users_email_active  (EmailActive),
    INDEX idx_users_isactive          (IsActive, IsDeleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OtpTokens (
    OtpTokenId      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NULL,
    Recipient       VARCHAR(150)    NOT NULL,
    OtpCode         VARCHAR(10)     NOT NULL,
    PurposeLkpId    INT UNSIGNED    NOT NULL,
    ExpiresAt       DATETIME        NOT NULL,
    AttemptCount    TINYINT         NOT NULL DEFAULT 0,
    IsUsed          TINYINT(1)      NOT NULL DEFAULT 0,
    IpAddress       VARCHAR(45)     NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (OtpTokenId),
    INDEX idx_otp_recipient_purpose (Recipient, PurposeLkpId, IsUsed),
    INDEX idx_otp_expiry            (ExpiresAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE RefreshTokens (
    RefreshTokenId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    Token           VARCHAR(500)    NOT NULL,
    DeviceInfo      VARCHAR(255)    NULL,
    IpAddress       VARCHAR(45)     NULL,
    ExpiresAt       DATETIME        NOT NULL,
    IsRevoked       TINYINT(1)      NOT NULL DEFAULT 0,
    RevokedAt       DATETIME        NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (RefreshTokenId),
    INDEX idx_rt_userid (UserId),
    INDEX idx_rt_token  (Token(100)),
    INDEX idx_rt_expiry (ExpiresAt),
    CONSTRAINT fk_rt_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 2: PROFILES (7 tables) ──────────────────────────────

CREATE TABLE UserProfiles (
    UserProfileId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    FirstName       VARCHAR(80)     NOT NULL,
    LastName        VARCHAR(80)     NOT NULL,
    DateOfBirth     DATE            NULL,
    GenderLkpId     INT UNSIGNED    NULL,
    Bio             TEXT            NULL,
    ProfilePhoto    VARCHAR(500)    NULL,
    Occupation      VARCHAR(150)    NULL,
    Organisation    VARCHAR(150)    NULL,
    VolunteerExp    TEXT            NULL,
    EducationLkpId  INT UNSIGNED    NULL,
    FieldOfStudy    VARCHAR(150)    NULL,
    WorkExpLkpId    INT UNSIGNED    NULL,
    AddressLine1    VARCHAR(200)    NULL,
    AddressLine2    VARCHAR(200)    NULL,
    City            VARCHAR(100)    NULL,
    State           VARCHAR(100)    NULL,
    Pincode         VARCHAR(20)     NULL,
    Country         VARCHAR(100)    NOT NULL DEFAULT 'India',
    ImpactScore     INT UNSIGNED    NOT NULL DEFAULT 0,
    ReliabilityPct  DECIMAL(5,2)    NOT NULL DEFAULT 100.00,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (UserProfileId),
    UNIQUE KEY uq_profile_user (UserId, IsDeleted),
    INDEX idx_profile_city   (City, IsDeleted),
    INDEX idx_profile_impact (ImpactScore DESC),
    CONSTRAINT fk_profile_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserDocuments (
    UserDocumentId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId            INT UNSIGNED  NOT NULL,
    DocumentTypeLkpId INT UNSIGNED  NOT NULL,
    FileUrl           VARCHAR(500)  NOT NULL,
    FileName          VARCHAR(255)  NOT NULL,
    FileSizeKb        INT UNSIGNED  NULL,
    IsVerified        TINYINT(1)    NOT NULL DEFAULT 0,
    VerifiedAt        DATETIME      NULL,
    VerifiedBy        INT UNSIGNED  NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt         DATETIME      NULL,
    DeletedBy         INT UNSIGNED  NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (UserDocumentId),
    INDEX idx_udoc_user (UserId, IsDeleted),
    INDEX idx_udoc_type (DocumentTypeLkpId),
    CONSTRAINT fk_udoc_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserSkills (
    UserSkillId  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId       INT UNSIGNED  NOT NULL,
    SkillName    VARCHAR(100)  NOT NULL,
    AvgRating    DECIMAL(3,2)  NOT NULL DEFAULT 0.00,
    RatingCount  INT UNSIGNED  NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (UserSkillId),
    UNIQUE KEY uq_skill_user_name (UserId, SkillName, IsDeleted),
    INDEX idx_skill_name          (SkillName),
    CONSTRAINT fk_skill_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserSkillRatings (
    SkillRatingId  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    UserId         INT UNSIGNED   NOT NULL,              -- volunteer being rated
    OrgId          INT UNSIGNED   NULL,                  -- org context
    ProjectId      INT UNSIGNED   NULL,                  -- project context
    SkillId        INT UNSIGNED   NOT NULL,              -- ProjectSkills.ProjectSkillId
    Rating         DECIMAL(3,2)   NOT NULL,              -- 1.0 – 5.0
    RatedBy        INT UNSIGNED   NOT NULL,              -- admin who rated
    Notes          TEXT           NULL,
    CreatedAt      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SkillRatingId),
    UNIQUE KEY uq_rating (UserId, ProjectId, SkillId),  -- one rating per skill per project per volunteer
    INDEX idx_rating_user    (UserId),
    INDEX idx_rating_project (ProjectId),
    CONSTRAINT fk_skillrating_user    FOREIGN KEY (UserId)   REFERENCES Users(UserId),
    CONSTRAINT fk_skillrating_ratedby FOREIGN KEY (RatedBy)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserBadges (
    UserBadgeId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId         INT UNSIGNED  NOT NULL,
    BadgeLkpId     INT UNSIGNED  NOT NULL,              -- FK→LookupValues (BADGE_TYPE ValueCode)
    AwardedBy      INT UNSIGNED  NOT NULL,              -- FK→Users (admin who awarded)
    AwardedByOrgId INT UNSIGNED  NULL,                  -- FK→Organisations (context)
    ProjectId      INT UNSIGNED  NULL,                  -- FK→Projects (context)
    IsDeleted      TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (UserBadgeId),
    INDEX idx_badge_user    (UserId, IsDeleted),
    INDEX idx_badge_lkpid   (BadgeLkpId),
    INDEX idx_badge_project (ProjectId, UserId),
    CONSTRAINT fk_badge_user      FOREIGN KEY (UserId)         REFERENCES Users(UserId),
    CONSTRAINT fk_badge_lkpid     FOREIGN KEY (BadgeLkpId)     REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_badge_awardedby FOREIGN KEY (AwardedBy)      REFERENCES Users(UserId),
    CONSTRAINT fk_badge_org       FOREIGN KEY (AwardedByOrgId) REFERENCES Organisations(OrgId),
    CONSTRAINT fk_badge_project   FOREIGN KEY (ProjectId)      REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserInterests (
    UserInterestId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId         INT UNSIGNED  NOT NULL,
    InterestLkpId  INT UNSIGNED  NOT NULL,
    CreatedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (UserInterestId),
    UNIQUE KEY uq_user_interest (UserId, InterestLkpId),
    INDEX idx_interest_user (UserId),
    CONSTRAINT fk_interest_lkp  FOREIGN KEY (InterestLkpId) REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_interest_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserSafetyPreferences (
    UserSafetyPrefId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId               INT UNSIGNED  NOT NULL,
    EmergVisibilityLkpId INT UNSIGNED  NOT NULL,
    AutoShareDurLkpId    INT UNSIGNED  NOT NULL,
    AllowLocDuringSos    TINYINT(1)    NOT NULL DEFAULT 1,
    AllowLocDuringProj      TINYINT(1)    NOT NULL DEFAULT 1,
    EmergencyContactName    VARCHAR(100)  NULL,
    EmergencyContactPhone   VARCHAR(20)   NULL,
    EmergencyContactRelation VARCHAR(50)  NULL,
    IsDeleted               TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (UserSafetyPrefId),
    UNIQUE KEY uq_safepref_user (UserId),
    CONSTRAINT fk_safepref_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 3: ORGANISATIONS (5 tables) ─────────────────────────

CREATE TABLE Organisations (
    OrgId           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgName         VARCHAR(200)    NOT NULL,
    ContactPerson   VARCHAR(100)    NULL,
    OrgTypeLkpId    INT UNSIGNED    NOT NULL,
    RegNumber           VARCHAR(100)    NULL,                              -- NULL when IsNonRegistered = 1
    IsNonRegistered     TINYINT(1)      NOT NULL DEFAULT 0 COMMENT '1 = approved without govt registration number',
    RegistrationDate    DATE            NULL COMMENT 'Date org was officially registered with govt — NULL when IsNonRegistered = 1',
    Category        VARCHAR(100)    NOT NULL,
    LogoUrl         VARCHAR(500)    NULL,
    About           TEXT            NULL,
    Mission         TEXT            NULL,
    Vision          TEXT            NULL,
    ContactEmail    VARCHAR(150)    NULL,
    ContactPhone    VARCHAR(20)     NULL,
    Website         VARCHAR(255)    NULL,
    AddressLine1    VARCHAR(200)    NULL,
    AddressLine2    VARCHAR(200)    NULL,
    City            VARCHAR(100)    NULL,
    State           VARCHAR(100)    NULL,
    Pincode         VARCHAR(20)     NULL,
    Country         VARCHAR(100)    NOT NULL DEFAULT 'India',
    Is80GEligible   TINYINT(1)      NOT NULL DEFAULT 0    COMMENT '80G tax exemption eligibility (base value; overridden by OrgDonationSettings)',
    Is12AEligible   TINYINT(1)      NOT NULL DEFAULT 0    COMMENT '12A registration eligibility (base value; overridden by OrgDonationSettings)',
    AvgRating       DECIMAL(3,2)    NOT NULL DEFAULT 0.00 COMMENT 'Avg NGO rating (0-5)',
    RatingCount     INT UNSIGNED    NOT NULL DEFAULT 0    COMMENT 'Number of ratings',
    Latitude        DECIMAL(10,7)   NULL COMMENT 'NGO pin latitude for distance calc',
    Longitude       DECIMAL(10,7)   NULL COMMENT 'NGO pin longitude',
    StatusLkpId     INT UNSIGNED    NOT NULL,
    StatusUpdatedAt DATETIME        NULL,
    StatusUpdatedBy INT UNSIGNED    NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NOT NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    FollowerCount           INT UNSIGNED    NOT NULL DEFAULT 0    COMMENT 'Denormalized follower count — maintained by Org_Follow / Org_Unfollow SPs',
    VerificationStatusLkpId INT UNSIGNED    NULL     COMMENT 'Super Admin document/legal verification state — FK to ORG_VERIFICATION_STATUS LookupType',
    CanCreateRecurring      TINYINT(1)      NOT NULL DEFAULT 0    COMMENT 'Super Admin grants right to create RECURRING projects (subscription/plan gate)',
    CanCreateFlexible       TINYINT(1)      NOT NULL DEFAULT 0    COMMENT 'Super Admin grants right to create FLEXIBLE projects (subscription/plan gate)',
    OrgMaxVolunteers        INT UNSIGNED    NOT NULL DEFAULT 100   COMMENT 'Super Admin sets per-org max volunteers per project. Enforced in Project_Create + Project_Update.',
    PRIMARY KEY (OrgId),
    UNIQUE KEY uq_org_regnumber (RegNumber, IsDeleted),
    INDEX idx_org_status       (StatusLkpId, IsDeleted),
    INDEX idx_org_city         (City, IsDeleted),
    INDEX idx_org_category     (Category, IsDeleted),
    INDEX idx_org_verification (VerificationStatusLkpId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgDocuments (
    OrgDocumentId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED  NOT NULL,
    DocumentTypeLkpId INT UNSIGNED  NOT NULL,
    FileUrl           VARCHAR(500)  NOT NULL,
    FileName          VARCHAR(255)  NOT NULL,
    IsVerified        TINYINT(1)    NOT NULL DEFAULT 0,
    VerifiedAt        DATETIME      NULL,
    VerifiedBy        INT UNSIGNED  NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (OrgDocumentId),
    INDEX idx_orgdoc_org (OrgId, IsDeleted),
    CONSTRAINT fk_orgdoc_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v4.0: Added LocationSharingLkpId
CREATE TABLE OrgMembers (
    OrgMemberId          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId                INT UNSIGNED  NOT NULL,
    UserId               INT UNSIGNED  NOT NULL,
    RoleLkpId            INT UNSIGNED  NOT NULL,
    StatusLkpId          INT UNSIGNED  NOT NULL,
    StatusUpdatedAt      DATETIME      NULL,
    StatusUpdatedBy      INT UNSIGNED  NULL,
    CanPost              TINYINT(1)    NOT NULL DEFAULT 1,
    CanComment           TINYINT(1)    NOT NULL DEFAULT 1,
    CanCommunityPost     TINYINT(1)    NOT NULL DEFAULT 1,
    MaxPostsPerDay       TINYINT       NOT NULL DEFAULT 10,
    LocationSharingLkpId INT UNSIGNED  NULL,
    JoinedAt             DATETIME      NULL,
    IsDeleted            TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt            DATETIME      NULL,
    DeletedBy            INT UNSIGNED  NULL,
    CreatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy            INT UNSIGNED  NULL,
    UpdatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy            INT UNSIGNED  NULL,
    PRIMARY KEY (OrgMemberId),
    UNIQUE KEY uq_orgmember_org_user (OrgId, UserId, IsDeleted),
    INDEX idx_orgmember_userid  (UserId, IsDeleted),
    INDEX idx_orgmember_status  (StatusLkpId),
    CONSTRAINT fk_orgmember_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orgmember_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v4.0: NEW TABLE
CREATE TABLE OrgMembershipRequests (
    RequestId          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId              INT UNSIGNED  NOT NULL,
    UserId             INT UNSIGNED  NOT NULL,
    PrevNgoExperience  TEXT          NULL,
    VolunteerSkills    TEXT          NULL,
    AreasOfInterest    TEXT          NULL,
    WhyJoin            TEXT          NULL,
    StatusLkpId        INT UNSIGNED  NOT NULL,
    ReviewedBy         INT UNSIGNED  NULL,
    ReviewedAt         DATETIME      NULL,
    ReviewNote         TEXT          NULL,
    IsDeleted          TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (RequestId),
    UNIQUE KEY uq_memreq_org_user (OrgId, UserId, IsDeleted),
    INDEX idx_memreq_org  (OrgId, StatusLkpId),
    INDEX idx_memreq_user (UserId),
    CONSTRAINT fk_memreq_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_memreq_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgDonationSettings (
    OrgDonSettingId   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED  NOT NULL,
    IsDonationEnabled TINYINT(1)    NOT NULL DEFAULT 0,
    PlatformFeePct    DECIMAL(5,2)  NOT NULL DEFAULT 1.00,
    BankAccNumber     VARCHAR(50)   NULL,
    BankIfsc          VARCHAR(20)   NULL,
    BankName          VARCHAR(100)  NULL,
    AccountHolderName VARCHAR(150)  NULL,
    Pan               VARCHAR(20)   NULL,
    Is80GEligible     TINYINT(1)    NOT NULL DEFAULT 0,
    Is12AEligible     TINYINT(1)    NOT NULL DEFAULT 0,
    RazorpayAccountId VARCHAR(100)  NULL,
    KycStatusLkpId    INT UNSIGNED  NOT NULL,
    KycVerifiedAt     DATETIME      NULL,
    KycVerifiedBy     INT UNSIGNED  NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (OrgDonSettingId),
    UNIQUE KEY uq_orgdon_org (OrgId),
    CONSTRAINT fk_orgdon_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- (Source: NGOConnect_Patch_OrgFollow.sql)
CREATE TABLE OrgFollowers (
    OrgFollowerId  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    OrgId          INT UNSIGNED NOT NULL,
    UserId         INT UNSIGNED NOT NULL,
    IsFollowing    TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '1 = currently following, 0 = unfollowed',
    FollowedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Last follow timestamp',
    UnfollowedAt   DATETIME     NULL     COMMENT 'Last unfollow timestamp; NULL if currently following',
    PRIMARY KEY (OrgFollowerId),
    UNIQUE KEY uq_org_user            (OrgId, UserId),
    KEY idx_orgfollowers_org          (OrgId,  IsFollowing),
    KEY idx_orgfollowers_user         (UserId, IsFollowing),
    CONSTRAINT fk_orgfollowers_org    FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orgfollowers_user   FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v5.0: Org Member Invitations
CREATE TABLE OrgInvitations (
    OrgInvitationId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED    NOT NULL,
    InvitedByUserId   INT UNSIGNED    NOT NULL,
    InviteTypeLkpId   INT UNSIGNED    NOT NULL,   -- INVITE_TYPE: PHONE | EMAIL
    InviteValue       VARCHAR(255)    NOT NULL,    -- normalised phone or email
    CountryCode       VARCHAR(6)      NULL,        -- PHONE only
    InvitedUserId     INT UNSIGNED    NULL,        -- NULL = user not yet on platform
    InviteToken       VARCHAR(128)    NOT NULL,    -- cryptographically random, URL-safe base64
    TokenExpiry       DATETIME        NOT NULL,
    StatusLkpId       INT UNSIGNED    NOT NULL,    -- INVITE_STATUS
    DeliveryStatus    VARCHAR(20)     NULL,        -- SENT | DELIVERED | FAILED (lightweight, no lookup)
    SentAt            DATETIME        NULL,
    OpenedAt          DATETIME        NULL,
    AcceptedAt        DATETIME        NULL,
    CancelledAt       DATETIME        NULL,
    IsDeleted         TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt         DATETIME        NULL,
    DeletedBy         INT UNSIGNED    NULL,
    CreatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (OrgInvitationId),
    UNIQUE KEY uq_orginvite_token    (InviteToken),
    INDEX idx_orginvite_org          (OrgId, StatusLkpId, IsDeleted),
    INDEX idx_orginvite_value        (InviteValue(100), IsDeleted),
    INDEX idx_orginvite_inviteduser  (InvitedUserId, IsDeleted),
    INDEX idx_orginvite_expiry       (TokenExpiry),
    CONSTRAINT fk_orginvite_org         FOREIGN KEY (OrgId)           REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orginvite_invitedby   FOREIGN KEY (InvitedByUserId) REFERENCES Users(UserId),
    CONSTRAINT fk_orginvite_inviteduser FOREIGN KEY (InvitedUserId)   REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 4: PROJECTS (6 tables) ───────────────────────────────

CREATE TABLE Projects (
    ProjectId         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED  NOT NULL,
    ProjectName       VARCHAR(200)  NOT NULL,
    Category          VARCHAR(100)  NOT NULL,
    Description       TEXT          NULL,
    ProjectTypeLkpId  INT UNSIGNED  NOT NULL,
    ScheduleTypeLkpId INT UNSIGNED  NULL,
    RecurStart        DATE          NULL,
    RecurEnd          DATE          NULL,
    RecurDays         VARCHAR(20)   NULL,
    SessionStartTime  TIME          NULL,
    SessionEndTime    TIME          NULL,
    OneTimeDate       DATE          NULL,
    FlexFromDate      DATE          NULL,
    FlexToDate        DATE          NULL,
    MinHoursRequired  INT UNSIGNED  NULL,
    MinAttendPct      DECIMAL(5,2)  NULL COMMENT '% attendance required for cert eligibility',
    MaxDailyHours     DECIMAL(4,2)  NULL COMMENT 'FLEXIBLE: max hours per day cap',
    MinSessionHours   DECIMAL(4,2)  NULL COMMENT 'Min session hours to count as attended',
    LocationTypeLkpId INT UNSIGNED  NOT NULL,
    AddressLine       VARCHAR(300)  NULL,
    Landmark          VARCHAR(200)  NULL,
    City              VARCHAR(100)  NULL,
    State             VARCHAR(100)  NULL,
    Latitude          DECIMAL(10,7) NULL,
    Longitude         DECIMAL(10,7) NULL,
    GoogleMapsUrl     VARCHAR(500)  NULL,
    MaxVolunteers     INT UNSIGNED  NULL,
    JoinTypeLkpId     INT UNSIGNED  NOT NULL,
    IsPublic          TINYINT(1)    NOT NULL DEFAULT 1,
    AgeRestriction    TINYINT(1)    NOT NULL DEFAULT 0,
    IdVerRequired     TINYINT(1)    NOT NULL DEFAULT 0,
    MinReliability    DECIMAL(5,2)  NOT NULL DEFAULT 0,
    StatusLkpId       INT UNSIGNED  NOT NULL,
    CancelledAt       DATETIME      NULL,
    CancelledBy       INT UNSIGNED  NULL,
    CancelReason      TEXT          NULL,
    CompletedAt       DATETIME      NULL,
    CompletedBy       INT UNSIGNED  NULL,
    ImpactSummary     TEXT          NULL,
    BeneficiaryCount  INT UNSIGNED  NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt         DATETIME      NULL,
    DeletedBy         INT UNSIGNED  NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NOT NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (ProjectId),
    INDEX idx_project_org    (OrgId, IsDeleted),
    INDEX idx_project_status (StatusLkpId, IsDeleted),
    INDEX idx_project_city   (City, IsDeleted),
    INDEX idx_project_type   (ProjectTypeLkpId),
    CONSTRAINT fk_project_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ProjectSkills (
    ProjectSkillId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    ProjectId      INT UNSIGNED  NOT NULL,
    SkillName      VARCHAR(100)  NOT NULL,
    PRIMARY KEY (ProjectSkillId),
    INDEX idx_projskill_project (ProjectId, SkillName),   -- covering index for skill-match subquery in Project_GetNearbyFeed
    CONSTRAINT fk_projskill_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ProjectSessions (
    SessionId          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    ProjectId          INT UNSIGNED  NOT NULL,
    SessionDate        DATE          NOT NULL,
    StartTime          TIME          NOT NULL,
    EndTime            TIME          NOT NULL,
    MaxVolunteers      INT UNSIGNED  NULL,
    QrCode             VARCHAR(100)  NULL,
    QrExpiresAt        DATETIME      NULL,
    SessionStatusLkpId INT UNSIGNED  NOT NULL,
    IsDeleted          TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy          INT UNSIGNED  NULL,
    UpdatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy          INT UNSIGNED  NULL,
    PRIMARY KEY (SessionId),
    UNIQUE KEY uq_session_qr  (QrCode),
    INDEX idx_session_project (ProjectId, IsDeleted),
    INDEX idx_session_date    (SessionDate),
    CONSTRAINT fk_session_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ProjectApplications (
    ApplicationId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    ProjectId         INT UNSIGNED  NOT NULL,
    UserId            INT UNSIGNED  NOT NULL,
    Motivation        TEXT          NULL,
    RequestedSessions VARCHAR(200)  NULL,
    StatusLkpId       INT UNSIGNED  NOT NULL,
    StatusUpdatedAt   DATETIME      NULL,
    StatusUpdatedBy   INT UNSIGNED  NULL,
    RejectionReason   TEXT          NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt         DATETIME      NULL,
    DeletedBy         INT UNSIGNED  NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (ApplicationId),
    UNIQUE KEY uq_application_proj_user (ProjectId, UserId, IsDeleted),
    INDEX idx_app_user   (UserId, IsDeleted),
    INDEX idx_app_status (StatusLkpId),
    CONSTRAINT fk_app_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_app_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ProjectAttendance (
    AttendanceId      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SessionId         INT UNSIGNED  NOT NULL,
    UserId            INT UNSIGNED  NOT NULL,
    CheckInTime       DATETIME      NOT NULL,
    CheckOutTime      DATETIME      NULL,
    HoursLogged       DECIMAL(6,2)  NULL,
    QrScannedAt       DATETIME      NULL,
    AttendStatusLkpId INT UNSIGNED  NOT NULL,
    NoShowReason      TEXT          NULL,
    IsNoShowExcused   TINYINT(1)    NOT NULL DEFAULT 0,
    AdminNote         TEXT          NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (AttendanceId),
    UNIQUE KEY uq_attendance_session_user (SessionId, UserId),
    INDEX idx_attend_user (UserId),
    CONSTRAINT fk_attend_session FOREIGN KEY (SessionId) REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_attend_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v5.1: Per-session skill ratings for RECURRING + FLEXIBLE projects
CREATE TABLE UserSessionSkillRatings (
    SessionSkillRatingId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SessionId            INT UNSIGNED  NOT NULL,
    UserId               INT UNSIGNED  NOT NULL,
    ProjectId            INT UNSIGNED  NOT NULL,
    SkillId              INT UNSIGNED  NOT NULL,   -- ProjectSkills.ProjectSkillId
    Rating               DECIMAL(3,2) NOT NULL,   -- 1.0–5.0
    RatedBy              INT UNSIGNED  NOT NULL,
    Notes                TEXT          NULL,
    CreatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SessionSkillRatingId),
    UNIQUE KEY uq_ssr (SessionId, UserId, SkillId),
    INDEX idx_ssr_user    (UserId),
    INDEX idx_ssr_session (SessionId),
    INDEX idx_ssr_project (ProjectId),
    CONSTRAINT fk_ssr_session  FOREIGN KEY (SessionId)  REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_ssr_user     FOREIGN KEY (UserId)     REFERENCES Users(UserId),
    CONSTRAINT fk_ssr_ratedby  FOREIGN KEY (RatedBy)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v5.1: Session-level opt-outs (SELF / ADMIN_EXCUSED / ADMIN_REMOVED)
CREATE TABLE VolunteerSessionOptOuts (
    OptOutId        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SessionId       INT UNSIGNED  NOT NULL,
    UserId          INT UNSIGNED  NOT NULL,
    ProjectId       INT UNSIGNED  NOT NULL,
    OptOutTypeLkpId INT UNSIGNED  NOT NULL,
    Reason          TEXT          NULL,
    CreatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED  NOT NULL,
    PRIMARY KEY (OptOutId),
    UNIQUE KEY uq_session_optout (SessionId, UserId),
    INDEX idx_optout_user    (UserId),
    INDEX idx_optout_session (SessionId),
    INDEX idx_optout_project (ProjectId),
    CONSTRAINT fk_optout_session FOREIGN KEY (SessionId) REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_optout_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE VolunteerCertificates (
    CertificateId  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    CertCode       VARCHAR(20)    NOT NULL,              -- e.g. CERT-2026-000001 (used in verify URL)
    ProjectId      INT UNSIGNED   NOT NULL,
    UserId         INT UNSIGNED   NOT NULL,
    OrgId          INT UNSIGNED   NOT NULL,
    TotalHours     DECIMAL(6,2)   NULL,
    CertificateUrl VARCHAR(500)   NULL,                 -- Azure Blob URL to PDF (future)
    IssuedAt       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IssuedBy       INT UNSIGNED   NULL,
    IsDeleted      TINYINT(1)     NOT NULL DEFAULT 0,
    PRIMARY KEY (CertificateId),
    UNIQUE KEY uq_cert_code         (CertCode),
    UNIQUE KEY uq_cert_project_user (ProjectId, UserId),
    INDEX idx_cert_user (UserId),
    CONSTRAINT fk_cert_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_cert_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId),
    CONSTRAINT fk_cert_org     FOREIGN KEY (OrgId)     REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 5: CONTENT & COMMUNITY (10 tables) ──────────────────

CREATE TABLE Posts (
    PostId          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId           INT UNSIGNED  NULL,
    UserId          INT UNSIGNED  NOT NULL,
    PostTypeLkpId   INT UNSIGNED  NOT NULL,
    Content         TEXT          NOT NULL,
    VisibilityLkpId INT UNSIGNED  NOT NULL,
    IsPinned        TINYINT(1)    NOT NULL DEFAULT 0,
    IsEmergency     TINYINT(1)    NOT NULL DEFAULT 0 COMMENT '1 = emergency — bypasses feed ranking',
    IsEvergreen     TINYINT(1)    NOT NULL DEFAULT 0 COMMENT '1 = evergreen — stays in pool beyond 7 days',
    PinnedAt        DATETIME      NULL,
    PinnedBy        INT UNSIGNED  NULL,
    LikeCount       INT UNSIGNED  NOT NULL DEFAULT 0,
    CommentCount    INT UNSIGNED  NOT NULL DEFAULT 0,
    ShareCount      INT UNSIGNED  NOT NULL DEFAULT 0 COMMENT 'Denormalized share count',
    SaveCount       INT UNSIGNED  NOT NULL DEFAULT 0 COMMENT 'Denormalized save count',
    ViewCount       INT UNSIGNED  NOT NULL DEFAULT 0 COMMENT 'Denormalized unique-user view count — incremented by Feed_BulkMarkViewed',
    IsDeleted       TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt       DATETIME      NULL,
    DeletedBy       INT UNSIGNED  NULL,
    CreatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED  NULL,
    UpdatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED  NULL,
    PRIMARY KEY (PostId),
    INDEX idx_post_org       (OrgId, IsDeleted),
    INDEX idx_post_user      (UserId, IsDeleted),
    INDEX idx_post_created   (CreatedAt DESC),
    INDEX idx_post_pinned    (IsPinned, OrgId),
    INDEX idx_post_emergency (IsEmergency, CreatedAt DESC),
    CONSTRAINT fk_post_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_post_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PostMedia (
    PostMediaId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PostId         INT UNSIGNED  NOT NULL,
    FileUrl        VARCHAR(500)  NOT NULL,
    MediaTypeLkpId INT UNSIGNED  NOT NULL,
    SortOrder      TINYINT       NOT NULL DEFAULT 1,
    CreatedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostMediaId),
    INDEX idx_postmedia_post (PostId),
    CONSTRAINT fk_postmedia_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PostLikes (
    PostLikeId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PostId     INT UNSIGNED  NOT NULL,
    UserId     INT UNSIGNED  NOT NULL,
    CreatedAt  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostLikeId),
    UNIQUE KEY uq_postlike_post_user (PostId, UserId),
    INDEX idx_postlike_user          (UserId),
    CONSTRAINT fk_postlike_post FOREIGN KEY (PostId) REFERENCES Posts(PostId),
    CONSTRAINT fk_postlike_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PostComments (
    CommentId       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PostId          INT UNSIGNED  NOT NULL,
    UserId          INT UNSIGNED  NOT NULL,
    ParentCommentId INT UNSIGNED  NULL,
    Content         TEXT          NOT NULL,
    LikeCount       INT UNSIGNED  NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt       DATETIME      NULL,
    DeletedBy       INT UNSIGNED  NULL,
    CreatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CommentId),
    INDEX idx_comment_post   (PostId, IsDeleted),
    INDEX idx_comment_user   (UserId),
    INDEX idx_comment_parent (ParentCommentId),
    CONSTRAINT fk_comment_post   FOREIGN KEY (PostId)          REFERENCES Posts(PostId),
    CONSTRAINT fk_comment_user   FOREIGN KEY (UserId)          REFERENCES Users(UserId),
    CONSTRAINT fk_comment_parent FOREIGN KEY (ParentCommentId) REFERENCES PostComments(CommentId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PostReports (
    PostReportId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PostId           INT UNSIGNED  NOT NULL,
    ReportedByUserId INT UNSIGNED  NOT NULL,
    ReasonLkpId      INT UNSIGNED  NOT NULL,
    Details          TEXT          NULL,
    StatusLkpId      INT UNSIGNED  NOT NULL,
    ReviewedBy       INT UNSIGNED  NULL,
    ReviewedAt       DATETIME      NULL,
    CreatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostReportId),
    INDEX idx_report_post   (PostId),
    INDEX idx_report_status (StatusLkpId),
    CONSTRAINT fk_report_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PostSaves (
    PostSaveId  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    PostId      INT UNSIGNED    NOT NULL,
    UserId      INT UNSIGNED    NOT NULL,
    CreatedAt   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostSaveId),
    UNIQUE KEY  uq_postsave_post_user (PostId, UserId),
    INDEX       idx_postsave_user     (UserId),
    CONSTRAINT  fk_postsave_post FOREIGN KEY (PostId)  REFERENCES Posts(PostId),
    CONSTRAINT  fk_postsave_user FOREIGN KEY (UserId)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE FeedInteractions (
    InteractionId   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    PostId          INT UNSIGNED    NOT NULL,
    InteractionType VARCHAR(30)     NOT NULL COMMENT 'IMPRESSION|VIEW|LIKE|COMMENT|SHARE|SAVE|VOLUNTEER_CLICK|DONATION_CLICK|NGO_VISIT|HIDE|REPORT',
    DurationMs      INT UNSIGNED    NULL     COMMENT 'Read duration ms (VIEW only)',
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (InteractionId),
    INDEX idx_feedint_user (UserId, CreatedAt),
    INDEX idx_feedint_post (PostId, InteractionType),
    CONSTRAINT fk_feedint_user FOREIGN KEY (UserId) REFERENCES Users(UserId),
    CONSTRAINT fk_feedint_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE CommunityPosts (
    CommunityPostId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId               INT UNSIGNED  NOT NULL,
    UserId              INT UNSIGNED  NOT NULL,
    PostTypeLkpId       INT UNSIGNED  NOT NULL,
    Title               VARCHAR(300)  NOT NULL,
    Content             TEXT          NULL,
    AudienceLkpId       INT UNSIGNED  NOT NULL,
    LikeCount           INT UNSIGNED  NOT NULL DEFAULT 0,
    CommentCount        INT UNSIGNED  NOT NULL DEFAULT 0,
    AcknowledgeCount    INT UNSIGNED  NOT NULL DEFAULT 0,
    IsPinned            TINYINT(1)    NOT NULL DEFAULT 0,
    BestAnswerCommentId INT UNSIGNED  NULL,
    AssignedToUserId    INT UNSIGNED  NULL,
    DueDate             DATETIME      NULL,
    TaskStatusLkpId     INT UNSIGNED  NULL,
    PollEndsAt          DATETIME      NULL,
    PollIsMultiChoice   TINYINT(1)    NULL,
    EventRef            VARCHAR(200)  NULL,
    VolunteersNeeded    INT UNSIGNED  NULL,
    ResourceFileUrl     VARCHAR(500)  NULL,
    IsDeleted           TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt           DATETIME      NULL,
    DeletedBy           INT UNSIGNED  NULL,
    CreatedAt           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy           INT UNSIGNED  NULL,
    UpdatedAt           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy           INT UNSIGNED  NULL,
    PRIMARY KEY (CommunityPostId),
    INDEX idx_commpost_org     (OrgId, IsDeleted),
    INDEX idx_commpost_user    (UserId, IsDeleted),
    INDEX idx_commpost_type    (PostTypeLkpId),
    INDEX idx_commpost_created (CreatedAt DESC),
    CONSTRAINT fk_commpost_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_commpost_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v4.0: NEW — acknowledgement tracking
CREATE TABLE CommunityPostAcknowledgements (
    AckId           INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    CommunityPostId INT UNSIGNED  NOT NULL,
    UserId          INT UNSIGNED  NOT NULL,
    AcknowledgedAt  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (AckId),
    UNIQUE KEY uq_ack_post_user (CommunityPostId, UserId),
    CONSTRAINT fk_ack_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId),
    CONSTRAINT fk_ack_user FOREIGN KEY (UserId)          REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PollOptions (
    PollOptionId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    CommunityPostId INT UNSIGNED  NOT NULL,
    OptionText      VARCHAR(200)  NOT NULL,
    VoteCount       INT UNSIGNED  NOT NULL DEFAULT 0,
    SortOrder       TINYINT       NOT NULL DEFAULT 1,
    PRIMARY KEY (PollOptionId),
    INDEX idx_polloption_post (CommunityPostId),
    CONSTRAINT fk_polloption_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PollVotes (
    PollVoteId      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PollOptionId    INT UNSIGNED  NOT NULL,
    CommunityPostId INT UNSIGNED  NOT NULL,
    UserId          INT UNSIGNED  NOT NULL,
    VotedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PollVoteId),
    UNIQUE KEY uq_pollvote_user_post (UserId, CommunityPostId),
    CONSTRAINT fk_pollvote_option FOREIGN KEY (PollOptionId) REFERENCES PollOptions(PollOptionId),
    CONSTRAINT fk_pollvote_user   FOREIGN KEY (UserId)       REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Notifications (
    NotificationId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId         INT UNSIGNED    NOT NULL,
    OrgId          INT UNSIGNED    NULL,
    NotifType      VARCHAR(50)     NOT NULL,
    Title          VARCHAR(200)    NOT NULL,
    Body           TEXT            NOT NULL,
    RefId          INT UNSIGNED    NULL,
    RefType        VARCHAR(50)     NULL,
    IsRead         TINYINT(1)      NOT NULL DEFAULT 0,
    ReadAt         DATETIME        NULL,
    IsSent         TINYINT(1)      NOT NULL DEFAULT 0,
    SentAt         DATETIME        NULL,
    CreatedAt      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (NotificationId),
    INDEX idx_notif_user    (UserId, IsRead),
    INDEX idx_notif_created (CreatedAt DESC),
    CONSTRAINT fk_notif_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 6: SOS (3 tables) ─────────────────────────────────────

CREATE TABLE SosIncidents (
    SosIncidentId   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED  NOT NULL,
    OrgId           INT UNSIGNED  NULL,
    AlertTypeLkpId  INT UNSIGNED  NOT NULL,
    Description     TEXT          NULL,
    ApproxLocation  VARCHAR(300)  NULL,
    Latitude        DECIMAL(10,7) NULL,
    Longitude       DECIMAL(10,7) NULL,
    StatusLkpId     INT UNSIGNED  NOT NULL,
    ResolvedAt      DATETIME      NULL,
    ResolvedByLkpId INT UNSIGNED  NULL,
    CancelReason    TEXT          NULL,
    CancelledAt     DATETIME      NULL,
    IsDeleted       TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SosIncidentId),
    INDEX idx_sos_user   (UserId),
    INDEX idx_sos_org    (OrgId),
    INDEX idx_sos_status (StatusLkpId),
    CONSTRAINT fk_sos_user FOREIGN KEY (UserId) REFERENCES Users(UserId),
    CONSTRAINT fk_sos_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE SosResponders (
    SosResponderId      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SosIncidentId       INT UNSIGNED  NOT NULL,
    UserId              INT UNSIGNED  NOT NULL,
    RespondedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ApprovalStatusLkpId INT UNSIGNED  NOT NULL,
    ApprovedAt          DATETIME      NULL,
    ApprovedBy          INT UNSIGNED  NULL,
    CanViewLocation     TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (SosResponderId),
    UNIQUE KEY uq_sosresponder_inc_user (SosIncidentId, UserId),
    CONSTRAINT fk_sosresponder_incident FOREIGN KEY (SosIncidentId) REFERENCES SosIncidents(SosIncidentId),
    CONSTRAINT fk_sosresponder_user     FOREIGN KEY (UserId)        REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE SosLocationLogs (
    SosLocationLogId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    SosIncidentId    INT UNSIGNED    NOT NULL,
    UserId           INT UNSIGNED    NOT NULL,
    Latitude         DECIMAL(10,7)   NOT NULL,
    Longitude        DECIMAL(10,7)   NOT NULL,
    Accuracy         DECIMAL(8,2)    NULL,
    LoggedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (SosLocationLogId),
    INDEX idx_sosloc_incident (SosIncidentId),
    INDEX idx_sosloc_logged   (LoggedAt DESC),
    CONSTRAINT fk_sosloc_incident FOREIGN KEY (SosIncidentId) REFERENCES SosIncidents(SosIncidentId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 7: DONATIONS (6 tables) ──────────────────────────────

CREATE TABLE DonationCampaigns (
    CampaignId        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED  NOT NULL,
    CreatedByUserId   INT UNSIGNED  NOT NULL,
    CampaignName      VARCHAR(200)  NOT NULL,
    Description       TEXT          NULL,
    CampaignTypeLkpId INT UNSIGNED  NOT NULL,
    TargetAmount      DECIMAL(12,2) NOT NULL,
    RaisedAmount      DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    DonorCount        INT UNSIGNED  NOT NULL DEFAULT 0,
    StartDate         DATE          NOT NULL,
    EndDate           DATE          NULL,
    BannerUrl         VARCHAR(500)  NULL,
    ProjectId         INT UNSIGNED  NULL,
    VisibilityLkpId   INT UNSIGNED  NOT NULL,
    StatusLkpId       INT UNSIGNED  NOT NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt         DATETIME      NULL,
    DeletedBy         INT UNSIGNED  NULL,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED  NULL,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (CampaignId),
    INDEX idx_campaign_org    (OrgId, IsDeleted),
    INDEX idx_campaign_status (StatusLkpId, IsDeleted),
    CONSTRAINT fk_campaign_org     FOREIGN KEY (OrgId)     REFERENCES Organisations(OrgId),
    CONSTRAINT fk_campaign_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE DonationTransactions (
    TransactionId    INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    DonationId       VARCHAR(30)    NOT NULL,
    CampaignId       INT UNSIGNED   NULL,
    OrgId            INT UNSIGNED   NOT NULL,
    DonorUserId      INT UNSIGNED   NULL,
    DonorName        VARCHAR(150)   NULL,
    DonorEmail       VARCHAR(150)   NULL,
    DonorMobile      VARCHAR(20)    NULL,
    DonorPan         VARCHAR(20)    NULL,
    DonationAmount   DECIMAL(12,2)  NOT NULL,
    PlatformFeePct   DECIMAL(5,2)   NOT NULL,
    PlatformFeeAmt   DECIMAL(10,2)  NOT NULL,
    OrgReceivesAmt   DECIMAL(12,2)  NOT NULL,
    DonTypeLkpId     INT UNSIGNED   NOT NULL,
    PayMethodLkpId   INT UNSIGNED   NOT NULL,
    VisibilityLkpId  INT UNSIGNED   NOT NULL,
    PayStatusLkpId   INT UNSIGNED   NOT NULL,
    GatewayOrderId   VARCHAR(100)   NULL,
    GatewayPaymentId VARCHAR(100)   NULL,
    GatewayResponse  TEXT           NULL,
    FailureReason    TEXT           NULL,
    IsDeleted        TINYINT(1)     NOT NULL DEFAULT 0,
    CreatedAt        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (TransactionId),
    UNIQUE KEY uq_donation_donationid (DonationId),
    INDEX idx_donation_org      (OrgId),
    INDEX idx_donation_user     (DonorUserId),
    INDEX idx_donation_campaign (CampaignId),
    INDEX idx_donation_status   (PayStatusLkpId),
    INDEX idx_donation_created  (CreatedAt DESC),
    CONSTRAINT fk_donation_org      FOREIGN KEY (OrgId)       REFERENCES Organisations(OrgId),
    CONSTRAINT fk_donation_campaign FOREIGN KEY (CampaignId)  REFERENCES DonationCampaigns(CampaignId),
    CONSTRAINT fk_donation_user     FOREIGN KEY (DonorUserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE RecurringDonations (
    RecurringDonId  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    DonorUserId     INT UNSIGNED   NOT NULL,
    OrgId           INT UNSIGNED   NOT NULL,
    CampaignId      INT UNSIGNED   NULL,
    Amount          DECIMAL(12,2)  NOT NULL,
    FrequencyLkpId  INT UNSIGNED   NOT NULL,
    StatusLkpId     INT UNSIGNED   NOT NULL,
    StartDate       DATE           NOT NULL,
    NextChargeDate  DATE           NOT NULL,
    PausedAt        DATETIME       NULL,
    CancelledAt     DATETIME       NULL,
    GatewaySubId    VARCHAR(100)   NULL,
    SuccessCount    INT UNSIGNED   NOT NULL DEFAULT 0,
    FailureCount    INT UNSIGNED   NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)     NOT NULL DEFAULT 0,
    CreatedAt       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (RecurringDonId),
    INDEX idx_recdon_user       (DonorUserId, IsDeleted),
    INDEX idx_recdon_org        (OrgId),
    INDEX idx_recdon_nextcharge (NextChargeDate, StatusLkpId),
    CONSTRAINT fk_recdon_user     FOREIGN KEY (DonorUserId) REFERENCES Users(UserId),
    CONSTRAINT fk_recdon_org      FOREIGN KEY (OrgId)       REFERENCES Organisations(OrgId),
    CONSTRAINT fk_recdon_campaign FOREIGN KEY (CampaignId)  REFERENCES DonationCampaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE DonationReceipts (
    ReceiptId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    TransactionId INT UNSIGNED  NOT NULL,
    ReceiptNumber VARCHAR(50)   NOT NULL,
    ReceiptUrl    VARCHAR(500)  NOT NULL,
    FiscalYear    VARCHAR(10)   NOT NULL,
    IssuedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ReceiptId),
    UNIQUE KEY uq_receipt_transaction (TransactionId),
    INDEX idx_receipt_fiscal (FiscalYear),
    CONSTRAINT fk_receipt_transaction FOREIGN KEY (TransactionId) REFERENCES DonationTransactions(TransactionId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE WithdrawalRequests (
    WithdrawalId      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    WithdrawalRef     VARCHAR(30)   NOT NULL,
    OrgId             INT UNSIGNED  NOT NULL,
    RequestedByUserId INT UNSIGNED  NOT NULL,
    Amount            DECIMAL(12,2) NOT NULL,
    Purpose           TEXT          NOT NULL,
    StatusLkpId       INT UNSIGNED  NOT NULL,
    ReviewedBy        INT UNSIGNED  NULL,
    ReviewedAt        DATETIME      NULL,
    RejectionReason   TEXT          NULL,
    TransferredAt     DATETIME      NULL,
    BankRef           VARCHAR(100)  NULL,
    IsDeleted         TINYINT(1)    NOT NULL DEFAULT 0,
    CreatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED  NULL,
    PRIMARY KEY (WithdrawalId),
    UNIQUE KEY uq_withdrawal_ref (WithdrawalRef),
    INDEX idx_withdrawal_org    (OrgId),
    INDEX idx_withdrawal_status (StatusLkpId),
    CONSTRAINT fk_withdrawal_org  FOREIGN KEY (OrgId)             REFERENCES Organisations(OrgId),
    CONSTRAINT fk_withdrawal_user FOREIGN KEY (RequestedByUserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE PaymentGatewayLogs (
    GatewayLogId  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    TransactionId INT UNSIGNED  NULL,
    EventType     VARCHAR(100)  NOT NULL,
    GatewayRef    VARCHAR(200)  NULL,
    Payload       MEDIUMTEXT    NOT NULL,
    ProcessedAt   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsProcessed   TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (GatewayLogId),
    INDEX idx_gwlog_transaction (TransactionId),
    INDEX idx_gwlog_event       (EventType),
    INDEX idx_gwlog_processed   (IsProcessed)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── GROUP 8-11: SYSTEM + LOOKUP + SCHEMA VERSION ───────────────

CREATE TABLE AuditLogs (
    AuditLogId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId     INT UNSIGNED    NULL,
    Action     VARCHAR(100)    NOT NULL,
    EntityName VARCHAR(100)    NOT NULL,
    EntityId   INT UNSIGNED    NULL,
    OldValue   MEDIUMTEXT      NULL,
    NewValue   MEDIUMTEXT      NULL,
    IpAddress  VARCHAR(45)     NULL,
    UserAgent  VARCHAR(300)    NULL,
    CreatedAt  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (AuditLogId),
    INDEX idx_audit_entity  (EntityName, EntityId),
    INDEX idx_audit_user    (UserId),
    INDEX idx_audit_created (CreatedAt DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IdSequences (
    SequenceName VARCHAR(50)  NOT NULL,
    CurrentYear  YEAR         NOT NULL,
    LastValue    INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (SequenceName, CurrentYear)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Settings (
    SettingId    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SettingGroup VARCHAR(50)   NOT NULL,
    SettingKey   VARCHAR(100)  NOT NULL,
    SettingValue TEXT          NOT NULL,
    DataType     VARCHAR(20)   NOT NULL DEFAULT 'STRING',
    Description  VARCHAR(500)  NULL,
    IsPublic     TINYINT(1)    NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)    NOT NULL DEFAULT 0,
    UpdatedAt    DATETIME      NULL,
    UpdatedBy    INT UNSIGNED  NULL,
    PRIMARY KEY (SettingId),
    UNIQUE KEY uq_settings_key (SettingKey, IsDeleted),
    INDEX idx_settings_group  (SettingGroup),
    INDEX idx_settings_public (IsPublic)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserDeviceTokens (
    DeviceTokenId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId        INT UNSIGNED NOT NULL,
    Token         VARCHAR(512) NOT NULL,
    Platform      VARCHAR(20)  NOT NULL DEFAULT 'ANDROID',
    CreatedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt     DATETIME     NULL,
    PRIMARY KEY (DeviceTokenId),
    UNIQUE KEY uq_device_user_platform (UserId, Platform),
    INDEX idx_device_user (UserId),
    CONSTRAINT fk_devicetoken_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE LookupTypes (
    LookupTypeId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    TypeCode     VARCHAR(50)   NOT NULL,
    TypeName     VARCHAR(100)  NOT NULL,
    Description  VARCHAR(300)  NULL,
    IsSystemType TINYINT(1)    NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt    DATETIME      NULL,
    DeletedBy    INT UNSIGNED  NULL,
    CreatedAt    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy    INT UNSIGNED  NULL,
    UpdatedAt    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy    INT UNSIGNED  NULL,
    PRIMARY KEY (LookupTypeId),
    UNIQUE KEY uq_lookuptype_code (TypeCode, IsDeleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE LookupValues (
    LookupValueId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    LookupTypeId  INT UNSIGNED  NOT NULL,
    ValueCode     VARCHAR(50)   NOT NULL,
    ValueName     VARCHAR(100)  NOT NULL,
    Description   VARCHAR(300)  NULL,
    OrderNo       SMALLINT      NOT NULL DEFAULT 0,
    IsDefault     TINYINT(1)    NOT NULL DEFAULT 0,
    IsSystemValue TINYINT(1)    NOT NULL DEFAULT 0,
    IsDeleted     TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt     DATETIME      NULL,
    DeletedBy     INT UNSIGNED  NULL,
    CreatedAt     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy     INT UNSIGNED  NULL,
    UpdatedAt     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy     INT UNSIGNED  NULL,
    PRIMARY KEY (LookupValueId),
    UNIQUE KEY uq_lookupval_type_code (LookupTypeId, ValueCode, IsDeleted),
    INDEX idx_lookupval_type          (LookupTypeId, IsDeleted, OrderNo),
    CONSTRAINT fk_lookupval_type FOREIGN KEY (LookupTypeId) REFERENCES LookupTypes(LookupTypeId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v4.0: NEW — tracks DB schema change history
CREATE TABLE SchemaVersions (
    VersionId   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Version     VARCHAR(20)   NOT NULL,
    Description TEXT          NULL,
    AppliedAt   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    AppliedBy   VARCHAR(100)  NULL,
    PRIMARY KEY (VersionId),
    UNIQUE KEY uq_schema_version (Version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ProfileVerificationLkpId FK added via ALTER after seed (LookupValues must exist first)
-- See bottom of SECTION 3 for the ALTER TABLE statement.

-- ============================================================
-- SECTION 2: SEED DATA — LookupTypes (44 total)
-- ============================================================

INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('GENDER',              'Gender',                    'User gender options',                          1, 1),
('ORG_TYPE',            'Organisation Type',         'Legal structure of NGO',                       1, 1),
('ORG_CATEGORY',        'Organisation Category',     'Primary cause area of NGO',                    1, 1),
('ORG_STATUS',          'Organisation Status',       'Verification status of NGO on platform',       1, 1),
('MEMBER_ROLE',         'Member Role',               'Role of a user within an organisation',        1, 1),
('MEMBER_STATUS',       'Member Status',             'Status of membership',                         1, 1),
('DOCUMENT_TYPE_USER',  'User Document Type',        'Acceptable identity/address proof for users',  1, 1),
('DOCUMENT_TYPE_ORG',   'Org Document Type',         'Acceptable documents for NGO verification',    1, 1),
('EDUCATION',           'Education Level',           'Highest qualification of a volunteer',         1, 1),
('WORK_EXPERIENCE',     'Work Experience',           'Years of work experience brackets',            1, 1),
('PROJECT_TYPE',        'Project Type',              'Schedule type of a volunteer project',         1, 1),
('PROJECT_STATUS',      'Project Status',            'Current state of a project',                   1, 1),
('PROJECT_JOIN_TYPE',   'Project Join Type',         'How volunteers join a project',                1, 1),
('APPLICATION_STATUS',  'Application Status',        'Status of a volunteer application',            1, 1),
('ATTENDANCE_STATUS',   'Attendance Status',         'Volunteer attendance outcome',                  1, 1),
('POST_TYPE_FEED',      'Feed Post Type',            'Type of post on the public feed',              1, 1),
('POST_TYPE_COMMUNITY', 'Community Post Type',       'Type of post in an org community',             1, 1),
('POST_VISIBILITY',     'Post Visibility',           'Who can see a feed post',                      1, 1),
('REPORT_REASON',       'Report Reason',             'Reason for reporting a post',                  1, 1),
('REPORT_STATUS',       'Report Status',             'Review status of a post report',               1, 1),
('SOS_ALERT_TYPE',      'SOS Alert Type',            'Type of emergency alert',                      1, 1),
('SOS_STATUS',          'SOS Status',                'Current state of an SOS incident',             1, 1),
('RESPONDER_STATUS',    'Responder Approval Status', 'Admin approval status of an SOS responder',    1, 1),
('PAYMENT_METHOD',      'Payment Method',            'Payment options for donation',                 1, 1),
('DONATION_TYPE',       'Donation Type',             'One-time vs recurring donation',               1, 1),
('DONATION_STATUS',     'Donation Status',           'Payment processing status',                    1, 1),
('CAMPAIGN_TYPE',       'Campaign Type',             'Fundraising campaign category',                1, 1),
('CAMPAIGN_STATUS',     'Campaign Status',           'Current state of a donation campaign',         1, 1),
('RECURRING_FREQUENCY', 'Recurring Frequency',       'How often a recurring donation is charged',    1, 1),
('RECURRING_STATUS',    'Recurring Donation Status', 'Status of a recurring donation',               1, 1),
('WITHDRAWAL_STATUS',   'Withdrawal Status',         'State of an NGO withdrawal request',           1, 1),
('OTP_PURPOSE',         'OTP Purpose',               'Why an OTP was sent',                          1, 1),
('NOTIFICATION_TYPE',   'Notification Type',         'Category of in-app notification',              1, 1),
('LOCATION_TYPE',       'Location Type',             'Whether project is in-person or remote',       1, 1),
('EMERGENCY_VISIBILITY','Emergency Visibility',      'Who can see SOS alerts for a user',            1, 1),
('AUTO_SHARE_DURATION', 'Auto Share Duration',       'How long to share live location during SOS',   1, 1),
('BADGE_TYPE',          'Badge Type',                'Volunteer achievement badge categories',       1, 1),
('KYC_STATUS',          'KYC Status',                'KYC verification state for NGO donations',     1, 1),
('SCHEDULE_TYPE',       'Schedule Type',             'Recurring project schedule pattern',           1, 1),
('SESSION_STATUS',      'Session Status',            'State of a single project session',            1, 1),
('TASK_STATUS',         'Task Status',               'Status of a community task post',              1, 1),
('MEDIA_TYPE',          'Media Type',                'Type of media file attached to a post',        1, 1),
('SOS_RESOLVED_BY',     'SOS Resolved By',           'Who resolved the SOS incident',                1, 1),
('AUDIENCE_TYPE',       'Audience Type',             'Target audience for community posts',          1, 1),
('LOCATION_SHARING',    'Location Sharing',          'When a member shares location with org',       1, 1),
('PROFILE_VERIFICATION_STATUS', 'Profile Verification Status', 'Super Admin document/profile verification state for a member', 1, 1),
('ORG_VERIFICATION_STATUS',     'Org Verification Status',     'Super Admin legal document verification state for an organisation', 1, 1),
-- v5.0: Org Member Invitations
('INVITE_TYPE',   'Invite Type',   'Channel used to send an org member invitation', 1, 1),
('INVITE_STATUS', 'Invite Status', 'Current state of an org member invitation',     1, 1);
-- ^ #44 is LOCATION_SHARING, #45 is PROFILE_VERIFICATION_STATUS, #46 is ORG_VERIFICATION_STATUS — added v4.8
-- ^ #47 is INVITE_TYPE, #48 is INVITE_STATUS — added v5.0

-- ============================================================
-- SECTION 3: SEED DATA — LookupValues
-- ============================================================

-- GENDER
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'MALE', 'Male', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER' UNION ALL
SELECT LookupTypeId, 'FEMALE', 'Female', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER' UNION ALL
SELECT LookupTypeId, 'OTHER', 'Other', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER';

-- ORG_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'TRUST', 'Trust', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE' UNION ALL
SELECT LookupTypeId, 'SOCIETY', 'Society', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE' UNION ALL
SELECT LookupTypeId, 'SECTION_8', 'Section 8 Company', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE';

-- ORG_CATEGORY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EDUCATION', 'Education', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'ENVIRONMENT', 'Environment', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'HEALTHCARE', 'Healthcare', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'ANIMAL_WELFARE', 'Animal Welfare', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'WOMEN_EMP', 'Women Empowerment', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'COMMUNITY', 'Community Service', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'DISASTER', 'Disaster Relief', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'RURAL_DEV', 'Rural Development', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'CHILD_WELFARE', 'Child Welfare', 9, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'SENIOR', 'Senior Citizens', 10, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'ARTS_CULTURE', 'Arts & Culture', 11, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY';

-- ORG_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'UNDER_REVIEW', 'Under Review', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'SUSPENDED', 'Suspended', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
-- v5.2: org-level equivalent of the member NEEDS_UPDATE/RESUBMITTED pair — lets
-- Super Admin request a fix from an already-APPROVED org without a full reject.
-- Org is hidden from public listings while in either state (StatusLkpId gates
-- visibility for orgs, unlike Users which have a separate verification field).
SELECT LookupTypeId, 'NEEDS_UPDATE', 'Needs Update', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'RESUBMITTED', 'Resubmitted', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'ARCHIVED', 'Archived', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS';

-- MEMBER_ROLE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'FOUNDER', 'Founder', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'ADMIN', 'Admin', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'MODERATOR', 'Moderator', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'MEMBER', 'Member', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE';

-- MEMBER_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'SUSPENDED', 'Suspended', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS';

-- DOCUMENT_TYPE_USER
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PHOTO_ID',    'Government Photo ID', 0, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'AADHAAR',     'Aadhaar Card',        1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'PAN',         'PAN Card',            2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'PASSPORT',    'Passport',            3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'VOTER_ID',    'Voter ID',            4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'DRIVING_LIC', 'Driving Licence',     5, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'ADDR_PROOF',  'Address Proof',       6, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'OTHER',       'Other',               7, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER';

-- DOCUMENT_TYPE_ORG
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'REG_CERT', 'Registration Certificate', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'ORG_PAN', 'PAN Card', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'DOC_80G', '80G Certificate', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'DOC_12A', '12A Certificate', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'BANK_STMT', 'Bank Statement', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'OTHER', 'Other', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG';

-- EDUCATION
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'HIGH_SCHOOL', 'High School', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'DIPLOMA', 'Diploma', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'BACHELOR', 'Bachelor Degree', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'MASTER', 'Master Degree', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'PHD', 'PhD', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION';

-- WORK_EXPERIENCE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EXP_0_2', '0-2 years', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_3_5', '3-5 years', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_5_10', '5-10 years', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_10P', '10+ years', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE';

-- PROJECT_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ONE_TIME', 'One-time', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE' UNION ALL
SELECT LookupTypeId, 'FLEXIBLE', 'Flexible', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE';

-- PROJECT_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DRAFT', 'Draft', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'ACTIVE', 'Active', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'UPCOMING', 'Upcoming', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED', 'Completed', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS';

-- PROJECT_JOIN_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'APPROVE_REQ', 'Apply and get approved', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE' UNION ALL
SELECT LookupTypeId, 'SLOT_PICK', 'Pick session slots', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE' UNION ALL
SELECT LookupTypeId, 'OPEN_SIGNUP', 'Open signup', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE';

-- APPLICATION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'WITHDRAWN', 'Withdrawn', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS';

-- ATTENDANCE_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ATTENDED', 'Attended', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS' UNION ALL
SELECT LookupTypeId, 'NO_SHOW', 'No Show', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS' UNION ALL
SELECT LookupTypeId, 'EXCUSED', 'Excused', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS';

-- POST_TYPE_FEED
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'GENERAL', 'General Post', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'ANNOUNCEMENT', 'Announcement', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'EVENT', 'Event Promotion', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'VOL_REQUEST', 'Volunteer Requirement', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'FUNDRAISING', 'Fundraising', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'SUCCESS', 'Success Story', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'ACHIEVEMENT', 'Achievement', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'PHOTO_VIDEO', 'Photo / Video', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED';

-- POST_TYPE_COMMUNITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DISCUSSION', 'Discussion', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'QUESTION', 'Question', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'POLL', 'Poll', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'ANNOUNCEMENT', 'Announcement', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'EVENT_UPDATE', 'Event Update', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'VOL_REQUEST', 'Volunteer Request', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'TASK', 'Task', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'RESOURCE', 'Resource / File', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY';

-- POST_VISIBILITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PUBLIC', 'Public', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ORG_MEMBERS', 'Organisation Members', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'FOLLOWERS', 'Followers', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY';

-- REPORT_REASON
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SPAM', 'Spam or misleading', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'HATE', 'Hate speech', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'INAPPROPRIATE', 'Inappropriate', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'SCAM', 'Scam / Fraud', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'OTHER', 'Other', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON';

-- REPORT_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT LookupTypeId, 'PENDING',  'Pending Review', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS' UNION ALL
SELECT LookupTypeId, 'REVIEWED', 'Reviewed',       2, 1, 0 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS' UNION ALL
SELECT LookupTypeId, 'RESOLVED', 'Resolved',       3, 1, 0 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS';

-- SOS_ALERT_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SOS', 'SOS Alert', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'HELP_REQUEST', 'Help Request', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'MISSING_VOL', 'Missing Volunteer', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'SAFE_ARRIVAL', 'Safe Arrival', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE';

-- SOS_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ACTIVE', 'Active', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS' UNION ALL
SELECT LookupTypeId, 'RESOLVED', 'Resolved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS';

-- RESPONDER_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS' UNION ALL
SELECT LookupTypeId, 'DECLINED', 'Declined', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS';

-- PAYMENT_METHOD
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'UPI', 'UPI', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'CARD', 'Credit / Debit Card', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'NET_BANKING', 'Net Banking', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'WALLET', 'Wallet', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD';

-- DONATION_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ONE_TIME', 'One-time', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_TYPE';

-- DONATION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'SUCCESS', 'Success', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'FAILED', 'Failed', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'REFUNDED', 'Refunded', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS';

-- CAMPAIGN_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'GENERAL', 'General Campaign', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'PROJECT', 'Project-Based', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'EMERGENCY', 'Emergency', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring Fund', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE';

-- CAMPAIGN_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DRAFT', 'Draft', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'ACTIVE', 'Active', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'PAUSED', 'Paused', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED', 'Completed', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS';

-- RECURRING_FREQUENCY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'WEEKLY', 'Weekly', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'MONTHLY', 'Monthly', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'QUARTERLY', 'Quarterly', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'YEARLY', 'Yearly', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY';

-- RECURRING_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ACTIVE', 'Active', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS' UNION ALL
SELECT LookupTypeId, 'PAUSED', 'Paused', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS';

-- WITHDRAWAL_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'UNDER_REVIEW', 'Under Review', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'TRANSFERRED', 'Transferred', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS';

-- OTP_PURPOSE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'LOGIN', 'Login', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'REGISTER', 'Register', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'FORGOT_PASSWORD', 'Forgot Password', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'CHANGE_EMAIL', 'Change Email', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'ADD_PHONE',   'Add Phone',   5, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'ADD_EMAIL',   'Add Email',   6, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE';

-- NOTIFICATION_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SOS_ALERT', 'SOS Alert', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'APP_APPROVED', 'Application Approved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'APP_REJECTED', 'Application Rejected', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'APP_REMOVED',  'Removed from Project', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'DONATION_RCVD', 'Donation Received', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'POST_LIKED', 'Post Liked', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'BADGE_AWARDED', 'Badge Awarded', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'CERT_ISSUED', 'Certificate Issued', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'MEM_REQ_REVIEWED', 'Membership Reviewed', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'REVIEW_NEW',      'New Review',          9,  1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'REVIEW_RESPONSE', 'Review Response',     10, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'REVIEW_DELETED',       'Review Deleted',            11, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'MEMBERSHIP_REQUEST',   'Membership Request',         12, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'MEMBERSHIP_CANCELLED', 'Membership Request Withdrawn', 13, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE';

-- LOCATION_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'IN_PERSON', 'In-person', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE' UNION ALL
SELECT LookupTypeId, 'REMOTE', 'Remote', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE' UNION ALL
SELECT LookupTypeId, 'HYBRID', 'Hybrid', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE';

-- EMERGENCY_VISIBILITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ADMIN_ONLY', 'Only Organisation Admin', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ADMIN_MODS', 'Admin + Moderators', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ALL_MEMBERS', 'All Organisation Members', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY';

-- AUTO_SHARE_DURATION
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'MIN_30', '30 Minutes', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_1', '1 Hour', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_2', '2 Hours', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_4', '4 Hours', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'UNTIL_STOPPED', 'Until Stopped', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION';

-- BADGE_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'STAR_VOL', 'Volunteer Star', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'TEAM_PLAYER', 'Team Player', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'GO_GETTER', 'Go-getter', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'TOP_PERFORM', 'Top Performer', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'CHAMPION', 'Champion', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'GREEN_WARRIOR', 'Green Warrior', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'NGO_HERO', 'NGO Hero', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE';

-- KYC_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS' UNION ALL
SELECT LookupTypeId, 'VERIFIED', 'Verified', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS';

-- SCHEDULE_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'WEEKLY_DAYS', 'Weekly - specific days', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE' UNION ALL
SELECT LookupTypeId, 'MONTHLY_DATE', 'Monthly - specific dates', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE' UNION ALL
SELECT LookupTypeId, 'WEEKDAYS', 'Weekdays only (Mon-Fri)', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE';

-- SESSION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'UPCOMING', 'Upcoming', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'IN_PROGRESS', 'In Progress', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED', 'Completed', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS';

-- TASK_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'OPEN', 'Open', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS' UNION ALL
SELECT LookupTypeId, 'IN_PROGRESS', 'In Progress', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS' UNION ALL
SELECT LookupTypeId, 'DONE', 'Done', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS';

-- MEDIA_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'IMAGE', 'Image', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEDIA_TYPE' UNION ALL
SELECT LookupTypeId, 'VIDEO', 'Video', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEDIA_TYPE' UNION ALL
SELECT LookupTypeId, 'DOCUMENT', 'Document', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEDIA_TYPE';

-- SOS_RESOLVED_BY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SELF', 'Resolved by user', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY' UNION ALL
SELECT LookupTypeId, 'ADMIN', 'Resolved by admin', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY' UNION ALL
SELECT LookupTypeId, 'AUTO', 'Auto-resolved', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY';

-- AUDIENCE_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ALL_MEMBERS', 'All Members', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUDIENCE_TYPE' UNION ALL
SELECT LookupTypeId, 'ADMINS_ONLY', 'Admins Only', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUDIENCE_TYPE' UNION ALL
SELECT LookupTypeId, 'VOLUNTEERS', 'Volunteers Only', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUDIENCE_TYPE';

-- LOCATION_SHARING
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ALWAYS', 'Always share location', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_SHARING' UNION ALL
SELECT LookupTypeId, 'DURING_SOS', 'Share only during SOS', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_SHARING' UNION ALL
SELECT LookupTypeId, 'NEVER', 'Never share location', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_SHARING';


-- ── v4.1: INTEREST_TYPE LookupType + Values ──────────────────
INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
VALUES ('INTEREST_TYPE', 'Interest Type', 'Volunteer interest areas matching ORG_CATEGORY ValueCodes', 1, 1);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EDUCATION',     'Education',      1, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'HEALTHCARE',    'Healthcare',     2, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ENVIRONMENT',   'Environment',    3, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'SPORTS',        'Sports',         4, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ARTS',          'Arts',           5, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'TECHNOLOGY',    'Technology',     6, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'COMMUNITY',     'Community',      7, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE' UNION ALL
SELECT LookupTypeId, 'ANIMAL_WELFARE','Animal Welfare', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'INTEREST_TYPE';
-- PROFILE_VERIFICATION_STATUS (v4.6 NEW, v4.8 added REJECTED)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PENDING'      AS ValueCode, 'Not Reviewed' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'VERIFIED',       'Verified',               2 UNION ALL
    SELECT 'NEEDS_UPDATE',   'Needs Update',            3 UNION ALL
    SELECT 'REJECTED',       'Rejected',                4 UNION ALL
    SELECT 'RESUBMITTED',    'Resubmitted',             5
) v ON 1=1
WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS';

-- ORG_VERIFICATION_STATUS (v4.8 NEW)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PENDING'  AS ValueCode, 'Pending Review' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'VERIFIED',   'Verified',                  2 UNION ALL
    SELECT 'REJECTED',   'Rejected',                  3
) v ON 1=1
WHERE lt.TypeCode = 'ORG_VERIFICATION_STATUS';

-- INVITE_TYPE (v5.0 NEW)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PHONE' AS ValueCode, 'Phone Number' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'EMAIL',              'Email Address',              2
) v ON 1=1
WHERE lt.TypeCode = 'INVITE_TYPE';

-- INVITE_STATUS (v5.0 NEW)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PENDING'   AS ValueCode, 'Pending'   AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'OPENED',                 'Opened',                 2 UNION ALL
    SELECT 'ACCEPTED',               'Accepted',               3 UNION ALL
    SELECT 'REJECTED',               'Rejected',               4 UNION ALL
    SELECT 'CANCELLED',              'Cancelled',              5 UNION ALL
    SELECT 'EXPIRED',                'Expired',                6
) v ON 1=1
WHERE lt.TypeCode = 'INVITE_STATUS';

-- FK: Users.ProfileVerificationLkpId → LookupValues (v4.6 NEW)
ALTER TABLE Users ADD CONSTRAINT fk_users_profileverification
    FOREIGN KEY (ProfileVerificationLkpId) REFERENCES LookupValues(LookupValueId);

-- FK: Organisations.VerificationStatusLkpId → LookupValues (v4.8 NEW)
ALTER TABLE Organisations ADD CONSTRAINT fk_orgs_verificationstatus
    FOREIGN KEY (VerificationStatusLkpId) REFERENCES LookupValues(LookupValueId);

-- ============================================================
-- v5.0 NEW: Marketing & Communication Center — Phase 0 + Phase 1
-- Push + Email only in Phase 1. SMS channel/columns exist but stay
-- disabled (see Settings COMMUNICATION.CAMPAIGN_SMS_ENABLED) until
-- Fast2SMS DLT registration completes. WhatsApp lookup value seeded
-- inert for Phase 4. See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
-- ============================================================

-- Phase 0: per-user opt-in/opt-out for promotional communication.
-- No row for a user = treated as opted-in for everything (SPs default via LEFT JOIN + COALESCE).
-- Transactional messages (OTP, password reset, critical account alerts) never consult this table.
CREATE TABLE UserCommunicationPreferences (
    UserId                        INT UNSIGNED NOT NULL,
    ReceivePushNotifications      TINYINT(1)   NOT NULL DEFAULT 1,
    ReceivePromotionalEmails      TINYINT(1)   NOT NULL DEFAULT 1,
    ReceivePromotionalSms         TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveNgoUpdates             TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveDonationAlerts         TINYINT(1)   NOT NULL DEFAULT 1,
    ReceiveVolunteerOpportunities TINYINT(1)   NOT NULL DEFAULT 1,
    UpdatedAt                     DATETIME     NULL,
    PRIMARY KEY (UserId),
    CONSTRAINT fk_ucp_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Phase 1: one row per marketing/communication campaign.
-- NOTE: named "Campaigns" (marketing), distinct from "DonationCampaigns" (fundraising) —
-- do not confuse with the DONATION module's own CAMPAIGN_TYPE/CAMPAIGN_STATUS lookups below.
CREATE TABLE Campaigns (
    CampaignId          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignName        VARCHAR(200) NOT NULL,
    InternalNotes       VARCHAR(1000) NULL,
    CampaignTypeLkpId   INT UNSIGNED NOT NULL,
    PriorityLkpId       INT UNSIGNED NOT NULL,
    StatusLkpId         INT UNSIGNED NOT NULL,
    ScheduleType        VARCHAR(20)  NOT NULL DEFAULT 'NOW', -- NOW | SCHEDULED (RECURRING is Phase 2)
    ScheduledAt         DATETIME     NULL,
    TimezoneName        VARCHAR(60)  NOT NULL DEFAULT 'Asia/Kolkata',
    EstimatedRecipients INT UNSIGNED NULL,
    HangfireJobId       VARCHAR(100) NULL,   -- Hangfire job ID, used to cancel a scheduled send
    IsDeleted           TINYINT(1)   NOT NULL DEFAULT 0,
    DeletedAt           DATETIME     NULL,
    DeletedBy           INT UNSIGNED NULL,
    CreatedAt           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy           INT UNSIGNED NOT NULL,
    UpdatedAt           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy           INT UNSIGNED NULL,
    PRIMARY KEY (CampaignId),
    INDEX idx_campaign_status  (StatusLkpId, IsDeleted),
    INDEX idx_campaign_created (CreatedAt DESC),
    CONSTRAINT fk_campaign_type     FOREIGN KEY (CampaignTypeLkpId) REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_campaign_priority FOREIGN KEY (PriorityLkpId)     REFERENCES LookupValues(LookupValueId),
    CONSTRAINT fk_campaign_status   FOREIGN KEY (StatusLkpId)       REFERENCES LookupValues(LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per channel selected for a campaign (Push and/or Email in Phase 1;
-- SMS/WhatsApp columns reserved so later phases are additive, not a schema change).
CREATE TABLE CampaignChannels (
    CampaignChannelId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId        INT UNSIGNED NOT NULL,
    ChannelLkpId      INT UNSIGNED NOT NULL,
    PushTitle         VARCHAR(200)  NULL,
    PushBody          VARCHAR(500)  NULL,
    PushImageUrl      VARCHAR(500)  NULL,
    PushDeepLink      VARCHAR(500)  NULL,
    PushActionLabel   VARCHAR(50)   NULL,
    EmailSubject      VARCHAR(255)  NULL,
    EmailHtmlBody     MEDIUMTEXT    NULL,
    CreatedAt         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignChannelId),
    UNIQUE KEY uq_campchannel (CampaignId, ChannelLkpId),
    CONSTRAINT fk_campchannel_campaign FOREIGN KEY (CampaignId)   REFERENCES Campaigns(CampaignId),
    CONSTRAINT fk_campchannel_channel  FOREIGN KEY (ChannelLkpId) REFERENCES LookupValues(LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The audience filter for a campaign. Phase 1 supports exactly ONE rule per campaign
-- (pick one option — e.g. "Inactive 30 days" OR "By Org: X,Y" — not composable
-- combinations across rule types; the full reusable Segment Builder is Phase 2).
-- RuleValueJson keeps this schema stable as new rule types are added later.
CREATE TABLE CampaignAudienceRules (
    CampaignAudienceRuleId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId    INT UNSIGNED NOT NULL,
    RuleType      VARCHAR(30)  NOT NULL, -- ALL | ACTIVE | INACTIVE | NEW | BY_ORG | BY_ROLE
    RuleValueJson JSON         NULL,     -- {"days":7} or {"orgIds":[1,2]} or {"roleCodes":["FOUNDER"]}
    CreatedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignAudienceRuleId),
    INDEX idx_audiencerule_campaign (CampaignId),
    CONSTRAINT fk_audiencerule_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per user per campaign per channel — the largest table in this module,
-- BIGINT PK per the platform's high-volume append-table convention.
CREATE TABLE CampaignRecipients (
    CampaignRecipientId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId        INT UNSIGNED NOT NULL,
    UserId            INT UNSIGNED NOT NULL,
    ChannelLkpId      INT UNSIGNED NOT NULL,
    QueueStatus       VARCHAR(20)  NOT NULL DEFAULT 'QUEUED', -- QUEUED|PROCESSING|SENT|DELIVERED|FAILED|SKIPPED_OPTOUT|SKIPPED_NO_ADDRESS
    ProviderMessageId VARCHAR(255) NULL,
    FailReason        VARCHAR(500) NULL,
    RetryCount        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    QueuedAt          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SentAt            DATETIME NULL,
    DeliveredAt       DATETIME NULL,
    OpenedAt          DATETIME NULL,
    ClickedAt         DATETIME NULL,
    PRIMARY KEY (CampaignRecipientId),
    UNIQUE KEY uq_camprecipient (CampaignId, UserId, ChannelLkpId),
    INDEX idx_camprecipient_campaign (CampaignId, QueueStatus),
    INDEX idx_camprecipient_user     (UserId),
    CONSTRAINT fk_camprecipient_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Batch/retry tracking for the Hangfire-driven send process
CREATE TABLE CampaignQueueJobs (
    CampaignQueueJobId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    CampaignId    INT UNSIGNED NOT NULL,
    BatchNumber   INT UNSIGNED NOT NULL,
    ChannelLkpId  INT UNSIGNED NOT NULL,
    BatchSize     INT UNSIGNED NOT NULL DEFAULT 0,
    Status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING', -- PENDING|PROCESSING|COMPLETED|FAILED
    RetryCount    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    NextRetryAt   DATETIME NULL,
    StartedAt     DATETIME NULL,
    CompletedAt   DATETIME NULL,
    ErrorMessage  VARCHAR(1000) NULL,
    CreatedAt     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CampaignQueueJobId),
    INDEX idx_queuejob_campaign (CampaignId, Status),
    CONSTRAINT fk_queuejob_campaign FOREIGN KEY (CampaignId) REFERENCES Campaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Additive indexes supporting audience-segment resolution (Active/Inactive/New filters).
-- Does not alter any existing column, default, or FK — safe add-on to a live table.
ALTER TABLE Users ADD INDEX idx_users_lastlogin (IsDeleted, LastLoginAt);
ALTER TABLE Users ADD INDEX idx_users_createdat (IsDeleted, CreatedAt);

-- ── v5.0: Communication Center lookups ───────────────────────
-- NOTE: prefixed MKTG_ to avoid colliding with the existing donation-fundraising
-- lookups CAMPAIGN_TYPE / CAMPAIGN_STATUS (see DONATION_STATUS section above —
-- those already use those exact TypeCodes for a completely different feature).
INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('MKTG_CAMPAIGN_TYPE',     'Marketing Campaign Type',     'Category of a marketing/communication campaign', 1, 1),
('MKTG_CAMPAIGN_PRIORITY', 'Marketing Campaign Priority', 'Send priority for a marketing campaign',          1, 1),
('MKTG_CAMPAIGN_STATUS',   'Marketing Campaign Status',   'Lifecycle status of a marketing campaign',        1, 1),
('MKTG_CAMPAIGN_CHANNEL',  'Marketing Campaign Channel',  'Delivery channel for a marketing campaign',       1, 1);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PROMOTION'      AS ValueCode, 'Promotion'      AS ValueName, 1  AS OrderNo UNION ALL
    SELECT 'ANNOUNCEMENT',     'Announcement',                2 UNION ALL
    SELECT 'REMINDER',         'Reminder',                    3 UNION ALL
    SELECT 'FEATURE_LAUNCH',   'Feature Launch',              4 UNION ALL
    SELECT 'DONATION',         'Donation',                    5 UNION ALL
    SELECT 'VOLUNTEER',        'Volunteer',                   6 UNION ALL
    SELECT 'EMERGENCY',        'Emergency',                   7 UNION ALL
    SELECT 'FESTIVAL',         'Festival',                    8 UNION ALL
    SELECT 'SURVEY',           'Survey',                      9 UNION ALL
    SELECT 'CUSTOM',           'Custom',                      10
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE';

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'LOW' AS ValueCode, 'Low' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'NORMAL',           'Normal',            2 UNION ALL
    SELECT 'HIGH',             'High',              3 UNION ALL
    SELECT 'CRITICAL',         'Critical',          4
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY';

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'DRAFT' AS ValueCode, 'Draft' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'SCHEDULED',          'Scheduled',          2 UNION ALL
    SELECT 'RUNNING',            'Running',            3 UNION ALL
    SELECT 'COMPLETED',          'Completed',          4 UNION ALL
    SELECT 'CANCELLED',          'Cancelled',          5 UNION ALL
    SELECT 'FAILED',             'Failed',             6 UNION ALL
    SELECT 'PAUSED',             'Paused',             7
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS';

-- WHATSAPP seeded now (inert) so Phase 4 activation is a feature-flag away, not a schema change
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PUSH' AS ValueCode, 'Push Notification' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'EMAIL',              'Email',                          2 UNION ALL
    SELECT 'SMS',                 'SMS',                            3 UNION ALL
    SELECT 'WHATSAPP',            'WhatsApp',                       4
) v ON 1=1
WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL';

-- ============================================================
-- SECTION 4: SEED DATA — Settings + IdSequences
-- ============================================================

INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('OTP',        'OTP_EXPIRY_MINUTES',   '10',                     'NUMBER',  'OTP expiry in minutes',                  0),
('OTP',        'OTP_MAX_ATTEMPTS',     '3',                      'NUMBER',  'Max OTP verification attempts',          0),
('OTP',        'OTP_RATE_LIMIT',       '3',                      'NUMBER',  'Max OTPs per 10 min per recipient',      0),
('AUTH',       'JWT_EXPIRY_MINUTES',   '15',                     'NUMBER',  'JWT access token expiry in minutes',     0),
('AUTH',       'REFRESH_EXPIRY_DAYS',  '30',                     'NUMBER',  'Refresh token expiry in days',           0),
('AUTH',       'MAX_SESSIONS',         '5',                      'NUMBER',  'Max concurrent sessions per user',       0),
('PAGINATION', 'DEFAULT_PAGE_SIZE',    '20',                     'NUMBER',  'Default page size for list APIs',        1),
('PAGINATION', 'MAX_PAGE_SIZE',        '100',                    'NUMBER',  'Maximum allowed page size',              1),
('PLATFORM',   'APP_NAME',             'Ripple Hub',             'STRING',  'Platform display name',                  1),
('PLATFORM',   'SUPPORT_EMAIL',        'support@ngoconnect.app', 'STRING',  'Support email address',                  1),
('FEATURE',    'SOS_ENABLED',          'true',                   'BOOLEAN', 'Toggle SOS feature on/off',              0),
('FEATURE',    'DONATIONS_ENABLED',    'true',                   'BOOLEAN', 'Toggle donations feature on/off',        0),
('DONATION',   'MIN_DONATION_AMOUNT',  '10',                     'NUMBER',  'Minimum donation amount in INR',         1),
('DONATION',   'DEFAULT_PLATFORM_FEE', '1.00',                   'NUMBER',  'Default platform fee percentage',        0),
('DONATION',   'RAZORPAY_KEY_ID',      'rzp_test_xxxx',          'STRING',  'Razorpay Key ID (public)',               1),
('UPLOAD',     'MAX_FILE_SIZE_MB',     '10',                     'NUMBER',  'Maximum file upload size in MB',         1),
('UPLOAD',     'ALLOWED_IMAGE_TYPES',  'jpg,jpeg,png,webp',      'STRING',  'Allowed image file extensions',          1),
('UPLOAD',     'ALLOWED_DOC_TYPES',    'pdf,doc,docx',           'STRING',  'Allowed document file extensions',       1),
('SOS',        'SOS_RADIUS_KM',        '5',                      'NUMBER',  'Default SOS alert radius in km',         0),
('SMS',        'SMS_PROVIDER',         'MSG91',                  'STRING',  'SMS provider name',                      0),
('SMS',        'SMS_TEMPLATE_OTP',     'Your OTP is {otp}',      'STRING',  'OTP SMS template',                       0),
-- v5.0: Org Member Invitations
('INVITE',     'INVITE_BASE_URL',          'https://ripplehub.app/invite/', 'URL',     'Base URL for org member invitation deep links (swap per env)', 0),
('INVITE',     'INVITE_TOKEN_EXPIRY_DAYS', '30',                            'NUMBER',  'Invitation link expiry in days',                              0),
('INVITE',     'INVITE_SINGLE_USE',        'true',                          'BOOLEAN', 'Invitation token can only be consumed once',                  0),
('SMS',        'SMS_TEMPLATE_INVITE',      '{inviter} invited you to join {orgName} on RippleHub. Join the community: {link}', 'STRING', 'SMS template for org invitations', 0),
('EMAIL',      'EMAIL_TEMPLATE_INVITE',    'org_invitation',                'STRING',  'Email template key for org invitations',                      0);

-- v5.0 NEW: Marketing & Communication Center
INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('COMMUNICATION', 'CAMPAIGN_BATCH_SIZE',            '500',   'NUMBER',  'Recipients per send batch, per channel',                                     0),
('COMMUNICATION', 'CAMPAIGN_RETRY_MAX_ATTEMPTS',    '3',     'NUMBER',  'Max retry attempts per failed batch',                                        0),
('COMMUNICATION', 'CAMPAIGN_RETRY_BACKOFF_MINUTES', '5',     'NUMBER',  'Base backoff delay between retries in minutes, doubles each attempt',       0),
('COMMUNICATION', 'CAMPAIGN_SMS_ENABLED',           'false', 'BOOLEAN', 'SMS channel toggle — keep false until Fast2SMS DLT registration completes', 0),
('COMMUNICATION', 'HANGFIRE_DASHBOARD_KEY',          '',      'STRING',  'Shared key for /hangfire dashboard access outside Development (query ?key= or X-Hangfire-Key header). Empty = fail-closed — set a real value before relying on the dashboard in Staging/Production.', 0);

-- v5.1 NEW: Feed seen-post expiry
INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('FEED', 'FEED_SEEN_EXPIRY_DAYS', '30', 'NUMBER', 'Days to remember a post as seen by a user. After expiry the post becomes eligible to reappear in the feed as a last-resort fallback.', 0);

INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue) VALUES
('DON',  YEAR(CURDATE()), 0),
('WDR',  YEAR(CURDATE()), 0),
('REC',  YEAR(CURDATE()), 0),
('CERT', YEAR(CURDATE()), 0);
-- Note: Railway DB actual columns are SequenceName/CurrentYear/LastValue
-- (DON/WDR SPs incorrectly reference Prefix/SeqYear/LastNumber — pre-existing bug, separate fix needed)

-- ============================================================
-- SECTION 5: DUMMY TEST DATA
-- ============================================================

-- Test Users (UserId 1 = admin/founder, 2 = volunteer, 3 = donor)
INSERT INTO Users (Mobile, CountryCode, IsVerified, IsActive) VALUES ('9876543210', '+91', 1, 1);
SET @user1 = LAST_INSERT_ID();
INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, Occupation, City, State, Country)
    VALUES (@user1, 'Gaurav', 'Shukla', 'Platform founder and admin.', 'Project Manager', 'Pune', 'Maharashtra', 'India');

INSERT INTO Users (Mobile, CountryCode, IsVerified, IsActive) VALUES ('9876500001', '+91', 1, 1);
SET @user2 = LAST_INSERT_ID();
INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, Occupation, City, State, Country)
    VALUES (@user2, 'Priya', 'Sharma', 'Passionate volunteer in education.', 'Teacher', 'Mumbai', 'Maharashtra', 'India');

INSERT INTO Users (Email, CountryCode, IsVerified, IsActive) VALUES ('donor@test.com', '+91', 1, 1);
SET @user3 = LAST_INSERT_ID();
INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, City, State, Country)
    VALUES (@user3, 'Rahul', 'Mehta', 'Regular donor supporting education NGOs.', 'Delhi', 'Delhi', 'India');

-- Test Organisation
INSERT INTO Organisations (OrgName, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision, ContactEmail, ContactPhone, City, State, StatusLkpId, CreatedBy)
    SELECT 'Green Future NGO',
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE' AND lv.ValueCode='TRUST'),
           'NGO-2024-001', 'ENVIRONMENT',
           'Environmental NGO focused on urban tree plantations and waste management.',
           'Make every city green by 2035.',
           'A sustainable, pollution-free India.',
           'contact@greenfuture.org', '9800012345', 'Pune', 'Maharashtra',
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_STATUS' AND lv.ValueCode='APPROVED'),
           @user1;
SET @org1 = LAST_INSERT_ID();

INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt)
    SELECT @org1, @user1,
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE' AND lv.ValueCode='FOUNDER'),
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='MEMBER_STATUS' AND lv.ValueCode='APPROVED'),
           1, 1, 1, 50, NOW();

-- Test Project
INSERT INTO Projects (OrgId, ProjectName, Category, Description, ProjectTypeLkpId, LocationTypeLkpId, JoinTypeLkpId, City, State, StatusLkpId, CreatedBy)
    SELECT @org1, 'Tree Plantation Drive 2026', 'ENVIRONMENT',
           'Monthly tree plantation sessions across Pune parks.',
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='PROJECT_TYPE' AND lv.ValueCode='RECURRING'),
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='LOCATION_TYPE' AND lv.ValueCode='IN_PERSON'),
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='PROJECT_JOIN_TYPE' AND lv.ValueCode='OPEN_SIGNUP'),
           'Pune', 'Maharashtra',
           (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='PROJECT_STATUS' AND lv.ValueCode='ACTIVE'),
           @user1;

-- ============================================================
-- SECTION 6: STORED PROCEDURES
-- ============================================================

DELIMITER //

-- ── AUTH SPs ────────────────────────────────────────────────────
-- Source of truth: 02_SP_Auth.sql
-- Called by: AuthDal (AuthDal.cs)

DROP PROCEDURE IF EXISTS Auth_SendOTP //
CREATE PROCEDURE Auth_SendOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_CountryCode   VARCHAR(5),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45),
    IN p_ExpiryMinutes INT
)
BEGIN
    DECLARE v_RecentCount INT DEFAULT 0;

    -- Rate limit: max 3 OTP requests in last 10 minutes for same recipient+purpose
    SELECT COUNT(*) INTO v_RecentCount
    FROM   OtpTokens
    WHERE  Recipient     = p_Recipient
      AND  PurposeLkpId  = p_PurposeLkpId
      AND  CreatedAt    >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
      AND  IsUsed        = 0;

    IF v_RecentCount >= 3 THEN
        SELECT 0 AS IsSuccess,
               'Too many OTP requests. Please wait 10 minutes before trying again.' AS Message;
    ELSE
        -- Invalidate all previous unused OTPs for this recipient + purpose
        UPDATE OtpTokens
        SET    IsUsed = 1
        WHERE  Recipient    = p_Recipient
          AND  PurposeLkpId = p_PurposeLkpId
          AND  IsUsed       = 0;

        -- Insert new OTP (CountryCode lives on Users, not OtpTokens — not stored here)
        INSERT INTO OtpTokens (Recipient, OtpCode, PurposeLkpId, IpAddress, ExpiresAt)
        VALUES (
            p_Recipient,
            p_OtpCode,
            p_PurposeLkpId,
            p_IpAddress,
            DATE_ADD(NOW(), INTERVAL p_ExpiryMinutes MINUTE)
        );

        SELECT 1 AS IsSuccess, 'OTP generated successfully.' AS Message;
    END IF;
END //

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

DROP PROCEDURE IF EXISTS Auth_SaveRefreshToken //
CREATE PROCEDURE Auth_SaveRefreshToken(
    IN p_UserId     INT UNSIGNED,
    IN p_Token      VARCHAR(512),
    IN p_DeviceInfo VARCHAR(500),
    IN p_IpAddress  VARCHAR(45),
    IN p_ExpiresAt  DATETIME
)
BEGIN
    -- Enforce max 5 concurrent active sessions per user
    DELETE FROM RefreshTokens
    WHERE  UserId     = p_UserId
      AND  IsRevoked  = 0
      AND  RefreshTokenId NOT IN (
            SELECT RefreshTokenId FROM (
                SELECT RefreshTokenId
                FROM   RefreshTokens
                WHERE  UserId    = p_UserId
                  AND  IsRevoked = 0
                ORDER  BY CreatedAt DESC
                LIMIT  4
            ) AS recent
        );

    INSERT INTO RefreshTokens (UserId, Token, DeviceInfo, IpAddress, ExpiresAt)
    VALUES (p_UserId, p_Token, p_DeviceInfo, p_IpAddress, p_ExpiresAt);
END //

DROP PROCEDURE IF EXISTS Auth_GetRefreshToken //
CREATE PROCEDURE Auth_GetRefreshToken(
    IN p_Token VARCHAR(512)
)
BEGIN
    DECLARE v_TokenId     INT UNSIGNED DEFAULT 0;
    DECLARE v_UserId      INT UNSIGNED DEFAULT 0;
    DECLARE v_IsRevoked   TINYINT(1)   DEFAULT 0;
    DECLARE v_ExpiresAt   DATETIME;

    SELECT RefreshTokenId, UserId, IsRevoked, ExpiresAt
    INTO   v_TokenId, v_UserId, v_IsRevoked, v_ExpiresAt
    FROM   RefreshTokens
    WHERE  Token = p_Token
    LIMIT  1;

    IF v_TokenId = 0 THEN
        SELECT 0 AS IsSuccess, 'Invalid refresh token.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSEIF v_IsRevoked = 1 THEN
        SELECT 0 AS IsSuccess, 'Refresh token has been revoked.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSEIF NOW() > v_ExpiresAt THEN
        SELECT 0 AS IsSuccess, 'Refresh token has expired. Please login again.' AS Message,
               0 AS UserId, '' AS Recipient, 0 AS RefreshTokenId;

    ELSE
        SELECT 1                                  AS IsSuccess,
               'Token valid.'                     AS Message,
               u.UserId                           AS UserId,
               COALESCE(u.Email, u.Mobile)        AS Recipient,
               v_TokenId                          AS RefreshTokenId
        FROM   Users u
        WHERE  u.UserId = v_UserId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Auth_RevokeRefreshToken //
CREATE PROCEDURE Auth_RevokeRefreshToken(
    IN p_Token VARCHAR(512)
)
BEGIN
    UPDATE RefreshTokens
    SET    IsRevoked = 1
    WHERE  Token     = p_Token
      AND  IsRevoked = 0;

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'Token revoked successfully.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Token not found or already revoked.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Auth_RevokeRefreshTokenById //
CREATE PROCEDURE Auth_RevokeRefreshTokenById(
    IN p_RefreshTokenId INT UNSIGNED
)
BEGIN
    UPDATE RefreshTokens
    SET    IsRevoked = 1
    WHERE  RefreshTokenId = p_RefreshTokenId;
END //

-- ── SETTINGS + LOOKUP SPs ──────────────────────────────────────

CREATE PROCEDURE Settings_GetAll()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

CREATE PROCEDURE Settings_GetPublic()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsPublic = 1 AND IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

CREATE PROCEDURE Settings_GetByGroup(IN p_Group VARCHAR(50))
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  SettingGroup = p_Group AND IsDeleted = 0
    ORDER  BY SettingKey;
END //

CREATE PROCEDURE Settings_Update(IN p_Key VARCHAR(100), IN p_Value TEXT, IN p_UpdatedBy INT UNSIGNED)
BEGIN
    UPDATE Settings SET SettingValue = p_Value, UpdatedAt = NOW(), UpdatedBy = p_UpdatedBy WHERE SettingKey = p_Key AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Setting updated.' AS Message;
END //

CREATE PROCEDURE Lookup_GetAllTypes()
BEGIN
    SELECT LookupTypeId, TypeCode, TypeName, Description FROM LookupTypes WHERE IsDeleted = 0 ORDER BY TypeCode;
END //

CREATE PROCEDURE Lookup_GetValuesByTypeCode(IN p_TypeCode VARCHAR(50))
BEGIN
    SELECT lv.LookupValueId, lv.ValueCode, lv.ValueName, lv.Description, lv.OrderNo, lv.IsDefault
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = p_TypeCode AND lv.IsDeleted = 0 AND lt.IsDeleted = 0
    ORDER BY lv.OrderNo;
END //

CREATE PROCEDURE Lookup_GetValueByCode(IN p_TypeCode VARCHAR(50), IN p_ValueCode VARCHAR(50))
BEGIN
    SELECT lv.LookupValueId, lv.ValueCode, lv.ValueName, lv.Description, lv.OrderNo, lv.IsDefault
    FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = p_TypeCode AND lv.ValueCode = p_ValueCode AND lv.IsDeleted = 0
    LIMIT 1;
END //

-- ── USER SPs ─────────────────────────────────────────────────────

-- v4.0 MODIFIED: returns all profile fields incl. Education/WorkExp/Address
-- v5.0 MODIFIED: added TotalHours, ProjectsCount, NgosJoined so Profile screen
--                stats match Impact screen (same logic as User_GetImpact)
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
        -- v5.1: expose profile verification state + the Super Admin's remarks so the
        -- app can show an "action required" banner instead of burying the reason in
        -- notification history only (ProfileScreen reads these two fields).
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode,
        (
            SELECT n.Body FROM Notifications n
            WHERE n.UserId = u.UserId AND n.NotifType = 'PROFILE_UPDATE_REQUIRED'
            ORDER BY n.CreatedAt DESC LIMIT 1
        ) AS ProfileUpdateReason,
        CASE
            WHEN up.FirstName IS NOT NULL AND TRIM(up.FirstName) != ''
             AND up.LastName  IS NOT NULL AND TRIM(up.LastName)  != ''
            THEN 1 ELSE 0
        END AS IsProfileComplete,
        -- ── Impact stats (same logic as User_GetImpact) ──────────────────────
        ROUND(IFNULL((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps  ON pa2.SessionId       = ps.SessionId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId    = lta.LookupTypeId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
        ), 0), 1) AS TotalHours,
        IFNULL((
            SELECT COUNT(DISTINCT ps2.ProjectId)
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps2 ON pa2.SessionId        = ps2.SessionId
            JOIN   Projects          pr  ON ps2.ProjectId        = pr.ProjectId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId     = lta.LookupTypeId
            JOIN   LookupValues      lpv ON pr.StatusLkpId       = lpv.LookupValueId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
              AND  lpv.ValueCode IN ('COMPLETED', 'EXPIRED')
        ), 0) AS ProjectsCount,
        IFNULL((
            SELECT COUNT(*)
            FROM   OrgMembers   om2
            JOIN   LookupValues lvo ON om2.StatusLkpId = lvo.LookupValueId
            WHERE  om2.UserId = p_UserId AND om2.IsDeleted = 0
              AND  lvo.ValueCode = 'APPROVED'
        ), 0) AS NgosJoined
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues gv ON up.GenderLkpId    = gv.LookupValueId
    LEFT JOIN LookupValues ev ON up.EducationLkpId = ev.LookupValueId
    LEFT JOIN LookupValues wv ON up.WorkExpLkpId   = wv.LookupValueId
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

CREATE PROCEDURE User_GetPublicProfile(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        u.UserId, up.FirstName, up.LastName, up.Bio, up.ProfilePhoto,
        up.City, up.State, up.Country, up.Occupation,
        up.ImpactScore, up.ReliabilityPct,
        gv.ValueName AS Gender
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues gv ON up.GenderLkpId = gv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0 AND u.IsActive = 1;
END //

-- v4.0 MODIFIED: accepts all 17 profile params
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

    -- v5.1: if a Super Admin had flagged this profile NEEDS_UPDATE, editing the
    -- profile now flips it to RESUBMITTED so the Super Admin's member list shows
    -- this member needs a fresh look — distinct from NEEDS_UPDATE (nothing done
    -- yet) and from PENDING (never reviewed at all).
    UPDATE Users u
    JOIN LookupValues lv ON u.ProfileVerificationLkpId = lv.LookupValueId
    SET u.ProfileVerificationLkpId = (
            SELECT lv2.LookupValueId FROM LookupValues lv2
            JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE lt2.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv2.ValueCode = 'RESUBMITTED'
            LIMIT 1
        ),
        u.UpdatedAt = NOW()
    WHERE u.UserId = p_UserId AND lv.ValueCode = 'NEEDS_UPDATE';

    SELECT 1 AS IsSuccess, 'Profile updated.' AS Message;
END //

CREATE PROCEDURE User_GetSkills(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT UserSkillId, SkillName, AvgRating, RatingCount FROM UserSkills
    WHERE UserId = p_UserId AND IsDeleted = 0 ORDER BY AvgRating DESC;
END //

CREATE PROCEDURE User_AddSkill(IN p_UserId INT UNSIGNED, IN p_SkillName VARCHAR(100))
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM UserSkills WHERE UserId = p_UserId AND SkillName = p_SkillName AND IsDeleted = 0;
    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'Skill already added.' AS Message, NULL AS UserSkillId;
    ELSE
        INSERT INTO UserSkills (UserId, SkillName) VALUES (p_UserId, p_SkillName);
        SELECT 1 AS IsSuccess, 'Skill added.' AS Message, LAST_INSERT_ID() AS UserSkillId;
    END IF;
END //

CREATE PROCEDURE User_RemoveSkill(IN p_UserId INT UNSIGNED, IN p_UserSkillId INT UNSIGNED)
BEGIN
    UPDATE UserSkills SET IsDeleted = 1 WHERE UserSkillId = p_UserSkillId AND UserId = p_UserId;
    SELECT 1 AS IsSuccess, 'Skill removed.' AS Message;
END //

-- v4.0 NEW: Safety preferences UPSERT
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

-- v4.0 NEW: Replace all interests for a user
CREATE PROCEDURE User_SaveInterests(
    IN p_UserId         INT UNSIGNED,
    IN p_InterestLkpIds JSON
)
BEGIN
    DELETE FROM UserInterests WHERE UserId = p_UserId;
    INSERT INTO UserInterests (UserId, InterestLkpId)
    SELECT p_UserId, lkp_id
    FROM JSON_TABLE(p_InterestLkpIds, '$[*]' COLUMNS (lkp_id INT UNSIGNED PATH '$')) j
    WHERE lkp_id IS NOT NULL;
    SELECT 1 AS IsSuccess, 'Interests saved.' AS Message;
END //

-- v4.0 NEW: Upload user identity document
CREATE PROCEDURE User_UploadDocument(
    IN p_UserId            INT UNSIGNED,
    IN p_DocumentTypeLkpId INT UNSIGNED,
    IN p_FileUrl           VARCHAR(500),
    IN p_FileName          VARCHAR(255),
    IN p_FileSizeKb        INT UNSIGNED
)
BEGIN
    INSERT INTO UserDocuments (UserId, DocumentTypeLkpId, FileUrl, FileName, FileSizeKb, CreatedBy)
    VALUES (p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb, p_UserId);
    SELECT 1 AS IsSuccess, 'Document uploaded.' AS Message, LAST_INSERT_ID() AS UserDocumentId;
END //

-- ── ORG SPs ──────────────────────────────────────────────────────

-- v5.1 MODIFIED: +IsNonRegistered param; RegNumber is now nullable; reg-number uniqueness check skipped for non-registered orgs
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
    IN p_RegistrationDate  DATE                                  -- NULL when IsNonRegistered = 1
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

-- v4.0 MODIFIED: returns AddressLine1/2, Pincode
CREATE PROCEDURE Org_GetProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName  AS OrgStatus,
        sv.ValueCode  AS OrgStatusCode,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.AvgRating, o.RatingCount,
        o.Latitude, o.Longitude,
        o.CreatedAt,
        o.FollowerCount,
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
        (SELECT COUNT(*) FROM OrgMembers om
            JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
            JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
              AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- Public preview — no auth required — used by website deep link landing page (/ngo/{id})
CREATE PROCEDURE Org_GetPublicPreview(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        o.City,
        LEFT(o.About, 200)  AS AboutShort,
        vl.ValueCode        AS VerificationStatusCode,
        (SELECT COUNT(*) FROM OrgMembers om
             JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
             JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
             WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
               AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount
    FROM   Organisations o
    LEFT JOIN LookupValues vl ON o.VerificationStatusLkpId = vl.LookupValueId
    WHERE  o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- v4.0 MODIFIED: accepts all org fields
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
    IN p_Country       VARCHAR(100),
    IN p_Is80GEligible TINYINT(1),
    IN p_Is12AEligible TINYINT(1)
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
        Is80GEligible = COALESCE(p_Is80GEligible, Is80GEligible),
        Is12AEligible = COALESCE(p_Is12AEligible, Is12AEligible),
        UpdatedBy     = p_UserId,
        UpdatedAt     = NOW()
    WHERE OrgId = p_OrgId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Organisation updated.' AS Message;
END //

-- v4.0 MODIFIED: returns LogoUrl in list
-- (Source: NGOConnect_Patch_OrgFollow.sql — adds FollowerCount)
DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Keyword    VARCHAR(200),
    IN p_Category   VARCHAR(100),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset        INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ApprovedId    INT;
    DECLARE v_OrgCatTypeId  INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Resolve ORG_CATEGORY LookupTypeId once for the JOIN below
    SELECT LookupTypeId INTO v_OrgCatTypeId
    FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1;

    -- Result set 1: page
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.LogoUrl,
        o.City,
        o.State,
        o.IsNonRegistered,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.FollowerCount,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude
    FROM Organisations o
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY o.OrgName
    LIMIT p_PageSize OFFSET v_Offset;

    -- Result set 2: total count
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

-- v4.0 MODIFIED: returns all permission columns
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT om.OrgMemberId, om.UserId,
           CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
           up.ProfilePhoto,
           rv.ValueCode AS RoleCode, rv.ValueName AS RoleName,
           sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
           om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay,
           lsv.ValueCode AS LocationSharingCode,
           om.JoinedAt
    FROM OrgMembers om
    JOIN UserProfiles up ON om.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv ON om.RoleLkpId   = rv.LookupValueId
    LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN LookupValues lsv ON om.LocationSharingLkpId = lsv.LookupValueId
    WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt ASC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM OrgMembers WHERE OrgId = p_OrgId AND IsDeleted = 0;
END //

CREATE PROCEDURE Org_AddMember(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_RoleCode VARCHAR(50), IN p_AddedBy INT UNSIGNED)
BEGIN
    DECLARE v_RoleLkpId   INT UNSIGNED;
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_RoleLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = p_RoleCode LIMIT 1;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
    VALUES (p_OrgId, p_UserId, v_RoleLkpId, v_StatusLkpId, NOW(), p_AddedBy)
    ON DUPLICATE KEY UPDATE RoleLkpId = v_RoleLkpId, IsDeleted = 0, JoinedAt = NOW(), UpdatedBy = p_AddedBy;
    SELECT 1 AS IsSuccess, 'Member added.' AS Message;
END //

CREATE PROCEDURE Org_RemoveMember(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,    -- Target member's UserId (to be removed)
    IN p_RemovedBy  INT UNSIGNED     -- Admin/Founder making the request
)
BEGIN
    DECLARE v_IsAdmin         INT DEFAULT 0;
    DECLARE v_TargetIsFounder INT DEFAULT 0;

    -- Check requester is ADMIN or FOUNDER of the org
    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RemovedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin or founder can remove members.' AS Message;
    ELSE
        -- Founders cannot be removed — protect org ownership
        SELECT COUNT(*) INTO v_TargetIsFounder
        FROM   OrgMembers om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
          AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER'
          AND  om.IsDeleted = 0;

        IF v_TargetIsFounder > 0 THEN
            SELECT 0 AS IsSuccess, 'Founder cannot be removed from the organisation.' AS Message;
        ELSE
            UPDATE OrgMembers
            SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_RemovedBy
            WHERE  OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

            SELECT 1 AS IsSuccess, 'Member removed successfully.' AS Message;
        END IF;
    END IF;
END //

-- v4.0 NEW: Submit join request with full params stored in DB
-- (Source: NGOConnect_Patch_OrgFollow.sql — adds auto-follow on join request)
DROP PROCEDURE IF EXISTS Org_RequestMembership //
CREATE PROCEDURE Org_RequestMembership(
    IN p_OrgId             INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_PrevNgoExperience TEXT,
    IN p_VolunteerSkills   TEXT,
    IN p_AreasOfInterest   TEXT,
    IN p_WhyJoin           TEXT
)
BEGIN
    DECLARE v_Exists       INT DEFAULT 0;
    DECLARE v_IsMember     INT DEFAULT 0;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_WasFollowing TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;
    IF v_IsMember > 0 THEN
        SELECT 0 AS IsSuccess, 'Already a member of this organisation.' AS Message, NULL AS RequestId;
    ELSE
        -- Only block on an active PENDING request.
        -- APPROVED / REJECTED rows are historical — a user who was a member
        -- and later deactivated (or was rejected) must be allowed to re-apply.
        SELECT COUNT(*) INTO v_Exists
        FROM   OrgMembershipRequests omr
        JOIN   LookupValues lv ON lv.LookupValueId = omr.StatusLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  omr.OrgId = p_OrgId AND omr.UserId = p_UserId
          AND  omr.IsDeleted = 0
          AND  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING';
        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess, 'Request already submitted.' AS Message, NULL AS RequestId;
        ELSE
            SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            -- OrgMembershipRequests has UNIQUE KEY (OrgId, UserId, IsDeleted).
            -- A re-joining user may have an old APPROVED/REJECTED row with IsDeleted=0
            -- that would cause a duplicate-key error on INSERT.
            -- Fix: UPDATE the existing non-deleted row to PENDING (re-use it with
            --      fresh form data). Only INSERT if no such row exists.
            UPDATE OrgMembershipRequests
            SET    StatusLkpId       = v_StatusLkpId,
                   PrevNgoExperience = p_PrevNgoExperience,
                   VolunteerSkills   = p_VolunteerSkills,
                   AreasOfInterest   = p_AreasOfInterest,
                   WhyJoin           = p_WhyJoin,
                   ReviewedBy        = NULL,
                   ReviewedAt        = NULL,
                   ReviewNote        = NULL
            WHERE  OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

            IF ROW_COUNT() > 0 THEN
                -- Re-join: existing APPROVED/REJECTED row reset to PENDING
                SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message,
                       (SELECT RequestId FROM OrgMembershipRequests
                        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0 LIMIT 1) AS RequestId;
            ELSE
                -- First-time join: no existing row, safe to INSERT
                INSERT INTO OrgMembershipRequests
                    (OrgId, UserId, PrevNgoExperience, VolunteerSkills, AreasOfInterest, WhyJoin, StatusLkpId)
                VALUES
                    (p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin, v_StatusLkpId);
                SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message, LAST_INSERT_ID() AS RequestId;
            END IF;

            -- ── Auto-follow on join request ────────────────────────────────────
            -- Joining an NGO implies following it. The follow persists even if the
            -- request is later rejected or withdrawn. Only an explicit unfollow
            -- (DELETE /org/{orgId}/follow) can remove the follow.
            SELECT IFNULL(IsFollowing, 0) INTO v_WasFollowing
            FROM OrgFollowers WHERE OrgId = p_OrgId AND UserId = p_UserId;

            INSERT INTO OrgFollowers (OrgId, UserId, IsFollowing, FollowedAt, UnfollowedAt)
            VALUES (p_OrgId, p_UserId, 1, NOW(), NULL)
            ON DUPLICATE KEY UPDATE
                IsFollowing  = 1,
                FollowedAt   = NOW(),
                UnfollowedAt = NULL;

            -- Increment counter only when transitioning from not-following → following
            IF v_WasFollowing = 0 THEN
                UPDATE Organisations SET FollowerCount = FollowerCount + 1 WHERE OrgId = p_OrgId;
            END IF;
        END IF;
    END IF;
END //

-- v5.0 NEW: User cancels their own pending join request
DROP PROCEDURE IF EXISTS Org_CancelMembershipRequest //
CREATE PROCEDURE Org_CancelMembershipRequest(
    IN p_OrgId   INT UNSIGNED,
    IN p_UserId  INT UNSIGNED
)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;
    DECLARE v_Rows         INT DEFAULT 0;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT  1;

    -- Hard-delete instead of soft-delete (IsDeleted=1).
    --
    -- Root cause of intermittent "An error occurred":
    --   The unique key uq_memreq_org_user is on (OrgId, UserId, IsDeleted).
    --   After a first cancel cycle a row with IsDeleted=1 already exists.
    --   A second cancel attempt tried UPDATE ... SET IsDeleted=1 on the new
    --   PENDING row, producing a duplicate-key violation → MySQL exception.
    --
    -- Hard-delete is safe: Org_RequestMembership only checks for IsDeleted=0
    -- rows before allowing re-apply, so deleting the PENDING row here lets
    -- the user re-apply cleanly with a fresh INSERT on the next attempt.
    DELETE FROM OrgMembershipRequests
    WHERE  OrgId       = p_OrgId
      AND  UserId      = p_UserId
      AND  StatusLkpId = v_PendingLkpId
      AND  IsDeleted   = 0;

    SET v_Rows = ROW_COUNT();

    IF v_Rows > 0 THEN
        SELECT 1 AS IsSuccess, 'Membership request cancelled.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'No pending request found for this organisation.' AS Message;
    END IF;
END //

-- v4.0 NEW: Approve or reject a membership request
CREATE PROCEDURE Org_ReviewMembership(
    IN p_RequestId   INT UNSIGNED,
    IN p_ReviewedBy  INT UNSIGNED,
    IN p_StatusCode  VARCHAR(50),
    IN p_ReviewNote  TEXT
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_OrgId       INT UNSIGNED;
    DECLARE v_UserId      INT UNSIGNED;

    SELECT OrgId, UserId INTO v_OrgId, v_UserId FROM OrgMembershipRequests WHERE RequestId = p_RequestId AND IsDeleted = 0;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    UPDATE OrgMembershipRequests SET StatusLkpId = v_StatusLkpId, ReviewedBy = p_ReviewedBy,
        ReviewedAt = NOW(), ReviewNote = p_ReviewNote WHERE RequestId = p_RequestId;

    IF p_StatusCode = 'APPROVED' THEN
        CALL Org_AddMember(v_OrgId, v_UserId, 'MEMBER', p_ReviewedBy);
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Request ', p_StatusCode, '.') AS Message,
           v_UserId AS ApplicantUserId, v_OrgId AS OrgId;
END //

-- v4.0 NEW: List pending membership requests for an org
-- Fix: alias RequestId AS MembershipRequestId (mobile OrgMember.membershipRequestId)
--      + IFNULL defaults for PageNumber/PageSize so DAL can omit them
CREATE PROCEDURE Org_GetPendingMembers(IN p_OrgId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_PageSize    INT;
    DECLARE v_PageNumber  INT;
    DECLARE v_PendingLkpId INT UNSIGNED;
    SET v_PageNumber = IFNULL(p_PageNumber, 1);
    SET v_PageSize   = IFNULL(p_PageSize,   100);
    SET v_Offset     = (v_PageNumber - 1) * v_PageSize;

    SELECT LookupValueId INTO v_PendingLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT mr.RequestId AS MembershipRequestId, mr.UserId,
           CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
           up.ProfilePhoto, up.City, up.State,
           mr.PrevNgoExperience, mr.VolunteerSkills, mr.AreasOfInterest, mr.WhyJoin,
           mr.CreatedAt AS RequestedAt
    FROM OrgMembershipRequests mr
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    WHERE mr.OrgId = p_OrgId AND mr.StatusLkpId = v_PendingLkpId AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC
    LIMIT v_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM OrgMembershipRequests
    WHERE OrgId = p_OrgId AND StatusLkpId = v_PendingLkpId AND IsDeleted = 0;
END //

-- v4.0 NEW: Update per-member permissions + location sharing
-- v5.1 FIX: p_LocationSharingLkpId → p_LocationSharing TINYINT(1); SP resolves LkpId internally
CREATE PROCEDURE Org_UpdateMemberPermissions(
    IN p_OrgMemberId      INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_UpdatedBy        INT UNSIGNED,
    IN p_CanPost          TINYINT(1),
    IN p_CanComment       TINYINT(1),
    IN p_CanCommunityPost TINYINT(1),
    IN p_MaxPostsPerDay   TINYINT,
    IN p_LocationSharing  TINYINT(1)
)
BEGIN
    DECLARE v_LocLkpId INT UNSIGNED DEFAULT NULL;

    -- Resolve boolean → LookupValueId for LOCATION_SHARING (ALWAYS / NEVER)
    IF p_LocationSharing IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode   = 'LOCATION_SHARING'
          AND  lv.ValueCode  = IF(p_LocationSharing = 1, 'ALWAYS', 'NEVER')
        LIMIT 1;
    END IF;

    UPDATE OrgMembers SET
        CanPost              = COALESCE(p_CanPost,          CanPost),
        CanComment           = COALESCE(p_CanComment,       CanComment),
        CanCommunityPost     = COALESCE(p_CanCommunityPost, CanCommunityPost),
        MaxPostsPerDay       = COALESCE(p_MaxPostsPerDay,   MaxPostsPerDay),
        -- v_LocLkpId is NULL when p_LocationSharing was not sent → COALESCE keeps old value
        LocationSharingLkpId = COALESCE(v_LocLkpId, LocationSharingLkpId),
        UpdatedBy            = p_UpdatedBy,
        UpdatedAt            = NOW()
    WHERE OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Permissions updated.' AS Message;
END //

-- v4.0 NEW: Upload org document
CREATE PROCEDURE Org_UploadDocument(
    IN p_OrgId             INT UNSIGNED,
    IN p_UploadedBy        INT UNSIGNED,
    IN p_DocumentTypeLkpId INT UNSIGNED,
    IN p_FileUrl           VARCHAR(500),
    IN p_FileName          VARCHAR(255)
)
BEGIN
    INSERT INTO OrgDocuments (OrgId, DocumentTypeLkpId, FileUrl, FileName, CreatedBy)
    VALUES (p_OrgId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_UploadedBy);
    SELECT 1 AS IsSuccess, 'Document uploaded.' AS Message, LAST_INSERT_ID() AS OrgDocumentId;
END //

-- v4.8 NEW: List org documents — for org admin (founder/admin role)
CREATE PROCEDURE Org_GetDocuments(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT od.OrgDocumentId, od.DocumentTypeLkpId,
           dt.ValueCode AS DocumentTypeCode,
           dt.ValueName AS DocumentType,
           od.FileUrl, od.FileName, od.IsVerified, od.VerifiedAt, od.CreatedAt
    FROM OrgDocuments od
    LEFT JOIN LookupValues dt ON od.DocumentTypeLkpId = dt.LookupValueId
    WHERE od.OrgId = p_OrgId AND od.IsDeleted = 0
    ORDER BY od.CreatedAt ASC;
END //

-- ── PROJECT SPs ──────────────────────────────────────────────────

-- v4.0 MODIFIED: inserts all 17 schedule/location params
CREATE PROCEDURE Project_Create(
    IN p_OrgId             INT UNSIGNED,
    IN p_CreatedBy         INT UNSIGNED,
    IN p_ProjectName       VARCHAR(200),
    IN p_Category          VARCHAR(100),
    IN p_Description       TEXT,
    IN p_ProjectTypeLkpId  INT UNSIGNED,
    IN p_ScheduleTypeLkpId INT UNSIGNED,
    IN p_RecurStart        DATE,
    IN p_RecurEnd          DATE,
    IN p_RecurDays         VARCHAR(20),
    IN p_SessionStartTime  TIME,
    IN p_SessionEndTime    TIME,
    IN p_OneTimeDate       DATE,
    IN p_FlexFromDate      DATE,
    IN p_FlexToDate        DATE,
    IN p_MinHoursRequired  INT UNSIGNED,
    IN p_LocationTypeLkpId INT UNSIGNED,
    IN p_AddressLine       VARCHAR(300),
    IN p_Landmark          VARCHAR(200),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_JoinTypeLkpId     INT UNSIGNED,
    IN p_IsPublic          TINYINT(1),
    IN p_AgeRestriction    TINYINT(1),
    IN p_IdVerRequired     TINYINT(1),
    IN p_MinReliability    DECIMAL(5,2)
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'DRAFT' LIMIT 1;

    INSERT INTO Projects
        (OrgId, ProjectName, Category, Description, ProjectTypeLkpId,
         ScheduleTypeLkpId, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
         OneTimeDate, FlexFromDate, FlexToDate, MinHoursRequired,
         LocationTypeLkpId, AddressLine, Landmark, City, State,
         Latitude, Longitude, GoogleMapsUrl,
         MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
         StatusLkpId, CreatedBy)
    VALUES
        (p_OrgId, p_ProjectName, p_Category, p_Description, p_ProjectTypeLkpId,
         p_ScheduleTypeLkpId, p_RecurStart, p_RecurEnd, p_RecurDays, p_SessionStartTime, p_SessionEndTime,
         p_OneTimeDate, p_FlexFromDate, p_FlexToDate, p_MinHoursRequired,
         p_LocationTypeLkpId, p_AddressLine, p_Landmark, p_City, p_State,
         p_Latitude, p_Longitude, p_GoogleMapsUrl,
         p_MaxVolunteers, p_JoinTypeLkpId, COALESCE(p_IsPublic,1), COALESCE(p_AgeRestriction,0),
         COALESCE(p_IdVerRequired,0), COALESCE(p_MinReliability,0),
         v_StatusLkpId, p_CreatedBy);

    SELECT 1 AS IsSuccess, 'Project created.' AS Message, LAST_INSERT_ID() AS ProjectId;
END //

-- v5.1 MODIFIED: returns all 17 schedule/location/restriction fields + MinAttendPct/MaxDailyHours/MinSessionHours/TotalSessions
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        DATE_FORMAT(p.RecurStart,    '%Y-%m-%d') AS RecurStart,
        DATE_FORMAT(p.RecurEnd,      '%Y-%m-%d') AS RecurEnd,
        p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        DATE_FORMAT(p.OneTimeDate,   '%Y-%m-%d') AS OneTimeDate,
        DATE_FORMAT(p.FlexFromDate,  '%Y-%m-%d') AS FlexFromDate,
        DATE_FORMAT(p.FlexToDate,    '%Y-%m-%d') AS FlexToDate,
        p.MinHoursRequired,
        p.MinAttendPct, p.MaxDailyHours, p.MinSessionHours,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedCount,
        (SELECT COUNT(*) FROM ProjectSessions WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS TotalSessions,
        (SELECT lv2.ValueCode FROM ProjectApplications pa2
            JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
            WHERE pa2.ProjectId = p.ProjectId AND pa2.UserId = p_UserId AND pa2.IsDeleted = 0
            LIMIT 1) AS ApplicationStatusCode
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0
      AND (
          p.IsPublic = 1
          OR p_UserId IS NULL OR p_UserId = 0
          -- Past projects are historical records — always visible to any authenticated user
          OR sv.ValueCode IN ('COMPLETED', 'EXPIRED', 'CANCELLED')
          OR EXISTS (
              SELECT 1 FROM OrgMembers om
              JOIN LookupValues omv ON om.StatusLkpId  = omv.LookupValueId
              JOIN LookupTypes  omt ON omv.LookupTypeId = omt.LookupTypeId
              WHERE om.OrgId = p.OrgId AND om.UserId = p_UserId
                AND om.IsDeleted = 0
                AND omt.TypeCode = 'MEMBER_STATUS' AND omv.ValueCode = 'APPROVED'
          )
      );
END //

-- v4.0 MODIFIED: accepts all schedule/location fields
CREATE PROCEDURE Project_Update(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UpdatedBy         INT UNSIGNED,
    IN p_ProjectName       VARCHAR(200),
    IN p_Description       TEXT,
    IN p_ScheduleTypeLkpId INT UNSIGNED,
    IN p_RecurStart        DATE,
    IN p_RecurEnd          DATE,
    IN p_RecurDays         VARCHAR(20),
    IN p_SessionStartTime  TIME,
    IN p_SessionEndTime    TIME,
    IN p_OneTimeDate       DATE,
    IN p_FlexFromDate      DATE,
    IN p_FlexToDate        DATE,
    IN p_MinHoursRequired  INT UNSIGNED,
    IN p_AddressLine       VARCHAR(300),
    IN p_Landmark          VARCHAR(200),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_StatusLkpId       INT UNSIGNED,
    IN p_AgeRestriction    TINYINT(1),
    IN p_IdVerRequired     TINYINT(1),
    IN p_MinReliability    DECIMAL(5,2)
)
BEGIN
    UPDATE Projects SET
        ProjectName       = COALESCE(p_ProjectName, ProjectName),
        Description       = COALESCE(p_Description, Description),
        ScheduleTypeLkpId = COALESCE(p_ScheduleTypeLkpId, ScheduleTypeLkpId),
        RecurStart        = COALESCE(p_RecurStart, RecurStart),
        RecurEnd          = COALESCE(p_RecurEnd, RecurEnd),
        RecurDays         = COALESCE(p_RecurDays, RecurDays),
        SessionStartTime  = COALESCE(p_SessionStartTime, SessionStartTime),
        SessionEndTime    = COALESCE(p_SessionEndTime, SessionEndTime),
        OneTimeDate       = COALESCE(p_OneTimeDate, OneTimeDate),
        FlexFromDate      = COALESCE(p_FlexFromDate, FlexFromDate),
        FlexToDate        = COALESCE(p_FlexToDate, FlexToDate),
        MinHoursRequired  = COALESCE(p_MinHoursRequired, MinHoursRequired),
        AddressLine       = COALESCE(p_AddressLine, AddressLine),
        Landmark          = COALESCE(p_Landmark, Landmark),
        City              = COALESCE(p_City, City),
        State             = COALESCE(p_State, State),
        Latitude          = COALESCE(p_Latitude, Latitude),
        Longitude         = COALESCE(p_Longitude, Longitude),
        GoogleMapsUrl     = COALESCE(p_GoogleMapsUrl, GoogleMapsUrl),
        MaxVolunteers     = COALESCE(p_MaxVolunteers, MaxVolunteers),
        StatusLkpId       = COALESCE(p_StatusLkpId, StatusLkpId),
        AgeRestriction    = COALESCE(p_AgeRestriction, AgeRestriction),
        IdVerRequired     = COALESCE(p_IdVerRequired, IdVerRequired),
        MinReliability    = COALESCE(p_MinReliability, MinReliability),
        UpdatedBy         = p_UpdatedBy,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Project updated.' AS Message;
END //

-- v4.0 MODIFIED: returns ProjectType in list
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    DECLARE v_StatusLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId   INT UNSIGNED DEFAULT NULL;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    END IF;
    IF p_TypeCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_TypeLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode LIMIT 1;
    END IF;

    SELECT p.ProjectId, p.OrgId, o.OrgName, p.ProjectName, p.Category,
           ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
           ltv.ValueCode AS LocationTypeCode,
           p.City, p.State, sv.ValueName AS Status,
           p.MaxVolunteers, p.OneTimeDate, p.RecurStart, p.RecurEnd,
           p.CreatedAt
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.IsDeleted = 0 AND p.IsPublic = 1
      AND (p_OrgId       IS NULL OR p.OrgId = p_OrgId)
      AND (p_Category    IS NULL OR p.Category = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Projects p
    WHERE p.IsDeleted = 0 AND p.IsPublic = 1
      AND (p_OrgId       IS NULL OR p.OrgId = p_OrgId)
      AND (p_Category    IS NULL OR p.Category = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //

CREATE PROCEDURE Project_AddSession(IN p_ProjectId INT UNSIGNED, IN p_SessionDate DATE, IN p_StartTime TIME, IN p_EndTime TIME, IN p_MaxVolunteers INT UNSIGNED, IN p_CreatedBy INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
    VALUES (p_ProjectId, p_SessionDate, p_StartTime, p_EndTime, p_MaxVolunteers, v_StatusLkpId, p_CreatedBy);
    SELECT 1 AS IsSuccess, 'Session added.' AS Message, LAST_INSERT_ID() AS SessionId;
END //

CREATE PROCEDURE Project_GetSessions(IN p_ProjectId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;
    SELECT ps.SessionId, ps.SessionDate, ps.StartTime, ps.EndTime, ps.MaxVolunteers,
           sv.ValueName AS Status, ps.QrCode, ps.QrExpiresAt
    FROM ProjectSessions ps
    LEFT JOIN LookupValues sv ON ps.SessionStatusLkpId = sv.LookupValueId
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER BY ps.SessionDate ASC LIMIT p_PageSize OFFSET v_Offset;
    SELECT COUNT(*) AS TotalCount FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;
END //

CREATE PROCEDURE Project_GetSessionQr(IN p_SessionId INT UNSIGNED, IN p_QrCode VARCHAR(100), IN p_ExpiryMinutes INT)
BEGIN
    UPDATE ProjectSessions SET QrCode = p_QrCode, QrExpiresAt = DATE_ADD(NOW(), INTERVAL p_ExpiryMinutes MINUTE)
    WHERE SessionId = p_SessionId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'QR generated.' AS Message, p_QrCode AS QrCode;
END //

CREATE PROCEDURE Project_CheckIn(IN p_QrCode VARCHAR(100), IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_SessionId INT UNSIGNED;
    DECLARE v_StatusLkpId INT UNSIGNED;

    SELECT SessionId INTO v_SessionId FROM ProjectSessions
    WHERE QrCode = p_QrCode AND QrExpiresAt > NOW() AND IsDeleted = 0 LIMIT 1;

    IF v_SessionId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid or expired QR code.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

        INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
        VALUES (v_SessionId, p_UserId, NOW(), v_StatusLkpId, p_UserId)
        ON DUPLICATE KEY UPDATE CheckInTime = NOW(), AttendStatusLkpId = v_StatusLkpId;
        SELECT 1 AS IsSuccess, 'Check-in successful.' AS Message, v_SessionId AS SessionId,
               (SELECT ProjectId FROM ProjectSessions WHERE SessionId = v_SessionId LIMIT 1) AS ProjectId;
    END IF;
END //

-- v4.0 NEW: Add required skill to a project
CREATE PROCEDURE Project_AddSkill(IN p_ProjectId INT UNSIGNED, IN p_SkillName VARCHAR(100))
BEGIN
    INSERT IGNORE INTO ProjectSkills (ProjectId, SkillName) VALUES (p_ProjectId, p_SkillName);
    SELECT 1 AS IsSuccess, 'Skill added to project.' AS Message, LAST_INSERT_ID() AS ProjectSkillId;
END //

-- v4.0 NEW: Get skills for a project
CREATE PROCEDURE Project_GetSkills(IN p_ProjectId INT UNSIGNED)
BEGIN
    SELECT ProjectSkillId, SkillName FROM ProjectSkills WHERE ProjectId = p_ProjectId ORDER BY SkillName;
END //

-- v5.0 UPDATED: Mark a project as completed + auto-mark APPROVED volunteers as ATTENDED
-- Auto-creates a session from project schedule if none exists so HoursLogged is always recorded.
-- Volunteers who already have an ATTENDED record are skipped (idempotent).
CREATE PROCEDURE Project_Complete(
    IN p_ProjectId        INT UNSIGNED,
    IN p_CompletedBy      INT UNSIGNED,
    IN p_ImpactSummary    TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_CompletedStatusId  INT UNSIGNED;
    DECLARE v_ApprovedLkpId      INT UNSIGNED;
    DECLARE v_AttendedLkpId      INT UNSIGNED;
    DECLARE v_NoShowLkpId        INT UNSIGNED;
    DECLARE v_SessionId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionDate        DATE;
    DECLARE v_StartTime          TIME;
    DECLARE v_EndTime            TIME;
    DECLARE v_MaxVol             INT UNSIGNED DEFAULT 0;
    DECLARE v_SessionHours       DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_HoursLogged        DECIMAL(6,2) DEFAULT 1.00;
    DECLARE v_TypeCode           VARCHAR(50)  DEFAULT '';
    DECLARE v_RecurStart         DATE         DEFAULT NULL;
    DECLARE v_RecurEnd           DATE         DEFAULT NULL;
    DECLARE v_RecurDays          VARCHAR(50)  DEFAULT NULL;
    DECLARE v_DaysPerWeek        INT          DEFAULT 1;
    DECLARE v_Weeks              INT          DEFAULT 1;

    -- 1. Get lookup IDs
    SELECT LookupValueId INTO v_CompletedStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    SELECT LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    -- 2. Mark project COMPLETED
    UPDATE Projects
    SET    StatusLkpId    = v_CompletedStatusId,
           CompletedAt    = NOW(),
           CompletedBy    = p_CompletedBy,
           ImpactSummary  = p_ImpactSummary,
           BeneficiaryCount = p_BeneficiaryCount,
           UpdatedAt      = NOW()
    WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

    -- 3. Load project schedule info (type + times + recur details)
    SELECT
        COALESCE(ptv.ValueCode, 'ONE_TIME'),
        COALESCE(p.SessionStartTime, '09:00:00'),
        COALESCE(p.SessionEndTime,   '17:00:00'),
        p.RecurStart, p.RecurEnd, p.RecurDays,
        COALESCE(p.MaxVolunteers, 0)
    INTO v_TypeCode, v_StartTime, v_EndTime, v_RecurStart, v_RecurEnd, v_RecurDays, v_MaxVol
    FROM Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    -- 4. Find an existing past session, or auto-create one
    SELECT ps.SessionId, ps.SessionDate, ps.StartTime, ps.EndTime
    INTO   v_SessionId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions ps
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate DESC LIMIT 1;

    IF v_SessionId IS NULL THEN
        SELECT COALESCE(p.OneTimeDate, p.RecurStart, p.FlexFromDate, CURDATE())
        INTO   v_SessionDate
        FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

        INSERT INTO ProjectSessions
            (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, CreatedBy)
        VALUES
            (p_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, p_CompletedBy);

        SET v_SessionId = LAST_INSERT_ID();
    END IF;

    -- 5. Hours per session (minimum 0.5h)
    SET v_SessionHours = GREATEST(
        ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2),
        0.50
    );

    -- 6. Total hours = session_hours × occurrences (RECURRING: days/week × weeks)
    IF v_TypeCode = 'RECURRING'
       AND v_RecurStart IS NOT NULL AND v_RecurEnd IS NOT NULL
       AND v_RecurDays IS NOT NULL AND v_RecurDays <> ''
    THEN
        SET v_DaysPerWeek = LENGTH(v_RecurDays) - LENGTH(REPLACE(v_RecurDays, ',', '')) + 1;
        SET v_Weeks = GREATEST(CEIL(DATEDIFF(v_RecurEnd, v_RecurStart) / 7.0), 1);
        SET v_HoursLogged = LEAST(v_SessionHours * v_DaysPerWeek * v_Weeks, 9999.99);
    ELSE
        SET v_HoursLogged = v_SessionHours;
    END IF;

    -- 7. Auto-mark NO_SHOW for APPROVED volunteers who never checked in at all.
    --    Volunteers who already have ANY attendance record (ATTENDED via QR/self-check-in,
    --    or NO_SHOW from a prior manual marking) are skipped — do not overwrite their real status.
    --    Volunteers who DID check in (ATTENDED) are handled by step 8 (HoursLogged backfill).
    INSERT INTO ProjectAttendance
        (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, AdminNote, CreatedBy)
    SELECT
        v_SessionId,
        pa.UserId,
        NOW(),
        0.00,
        v_NoShowLkpId,
        'Auto-marked no-show on project completion — volunteer did not check in.',
        p_CompletedBy
    FROM ProjectApplications pa
    WHERE pa.ProjectId   = p_ProjectId
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND pa.IsDeleted   = 0
      AND NOT EXISTS (
          -- Skip if the volunteer has ANY attendance record for this project
          SELECT 1
          FROM   ProjectAttendance att2
          JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
          WHERE  att2.UserId   = pa.UserId
            AND  ps2.ProjectId = p_ProjectId
            AND  ps2.IsDeleted = 0
      )
    ON DUPLICATE KEY UPDATE
        AttendStatusLkpId = v_NoShowLkpId,
        HoursLogged       = 0.00,
        AdminNote         = 'Auto-marked no-show on project completion — volunteer did not check in.',
        UpdatedAt         = NOW(),
        UpdatedBy         = p_CompletedBy;

    -- 8. Backfill HoursLogged for volunteers who checked in via QR or self-check-in
    --    BEFORE project completion. They already had ATTENDED status so step 7 skipped
    --    them, leaving HoursLogged = NULL.
    --    Formula: CheckInTime (UTC stored) → LEAST(completion NOW(), session end IST→UTC).
    --    Minimum 0.50h to avoid zero-duration edge cases.
    UPDATE ProjectAttendance att
    JOIN   ProjectSessions   ps ON att.SessionId = ps.SessionId
    SET    att.HoursLogged = GREATEST(
             ROUND(
               TIMESTAMPDIFF(MINUTE, att.CheckInTime,
                 LEAST(
                   NOW(),
                   CONVERT_TZ(TIMESTAMP(ps.SessionDate, ps.EndTime), '+05:30', '+00:00')
                 )
               ) / 60.0,
             2),
             0.50)
    WHERE  ps.ProjectId          = p_ProjectId
      AND  att.HoursLogged       IS NULL
      AND  att.AttendStatusLkpId = v_AttendedLkpId
      AND  ps.IsDeleted          = 0;

    SELECT 1 AS IsSuccess, 'Project marked as completed.' AS Message;
END //

-- v4.0 NEW: Cancel a project (sets status to CANCELLED, records reason + who)
CREATE PROCEDURE Project_Cancel(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_CancelReason TEXT
)
BEGIN
    DECLARE v_CancelledStatusId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_CancelledStatusId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'
    LIMIT  1;

    IF v_CancelledStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project status lookup not found.' AS Message;
    ELSEIF NOT EXISTS (
        SELECT 1 FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0
    ) THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        UPDATE Projects
        SET    StatusLkpId  = v_CancelledStatusId,
               CancelReason = p_CancelReason,
               CancelledBy  = p_UserId,
               CancelledAt  = NOW(),
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UserId
        WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project cancelled successfully.' AS Message;
    END IF;
END //

-- ── APPLICATION SPs ─────────────────────────────────────────────

-- Superseded by the updated version further in this file (3.04 block).
-- Kept here as initial seed; the DROP+CREATE at section 3.04 is the authoritative definition.
CREATE PROCEDURE Application_Apply(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Motivation TEXT, IN p_RequestedSessions VARCHAR(200))
BEGIN
    DECLARE v_PendingLkpId   INT UNSIGNED;
    DECLARE v_ExistingId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExistingStatus VARCHAR(50)  DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT pa.ApplicationId, lv.ValueCode
    INTO   v_ExistingId, v_ExistingStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
    LIMIT  1;

    IF v_ExistingStatus IN ('PENDING', 'APPROVED') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('You already have a ', v_ExistingStatus, ' application for this project.') AS Message,
               NULL AS ApplicationId;
    ELSEIF v_ExistingStatus = 'REJECTED' THEN
        UPDATE ProjectApplications
        SET    StatusLkpId = v_PendingLkpId, Motivation = p_Motivation,
               RequestedSessions = p_RequestedSessions, RejectionReason = NULL,
               StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId,
               UpdatedBy = p_UserId, UpdatedAt = NOW()
        WHERE  ApplicationId = v_ExistingId;
        SELECT 1 AS IsSuccess, 'Application re-submitted successfully.' AS Message, v_ExistingId AS ApplicationId;
    ELSE
        INSERT INTO ProjectApplications (ProjectId, UserId, Motivation, RequestedSessions, StatusLkpId, CreatedBy)
        VALUES (p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions, v_PendingLkpId, p_UserId);
        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message, LAST_INSERT_ID() AS ApplicationId;
    END IF;
END //

CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_FilterLkpId INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_FilterLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        -- Also try ATTENDANCE_STATUS (ATTENDED, NO_SHOW)
        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId,
        pa.UserId,
        -- CONCAT returns NULL if either part is NULL (unfinished profile).
        -- CONCAT_WS skips NULLs; fall back to phone/email from Users table.
        COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''),
                 u.Mobile, u.Email)             AS ApplicantName,
        up.ProfilePhoto,
        up.City,
        up.Occupation                               AS Profession,
        pa.Motivation,
        pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode)  AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName)  AS Status,
        pa.StatusUpdatedAt,
        pa.CreatedAt,
        -- Check-in time converted to IST (Railway MySQL server = UTC)
        DATE_FORMAT(CONVERT_TZ(att.CheckInTime, '+00:00', '+05:30'), '%Y-%m-%dT%H:%i:%s') AS CheckedInAt,
        att.AttendanceId,
        att.HoursLogged,
        att.IsNoShowExcused                         AS IsExcused,
        IF(att.NoShowReason = 'ADMIN_CONFIRMED', 1, 0) AS IsNoShowConfirmed,
        att.QrScannedAt,
        att.AdminNote,
        ps.SessionDate,
        ps.StartTime   AS SessionStartTime,
        ps.EndTime     AS SessionEndTime,
        -- Badges already awarded to this volunteer on this project (comma-separated ValueCodes)
        (SELECT GROUP_CONCAT(lv2.ValueCode ORDER BY ub.CreatedAt SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv2 ON ub.BadgeLkpId = lv2.LookupValueId
         WHERE  ub.UserId     = pa.UserId
           AND  ub.ProjectId  = pa.ProjectId
           AND  ub.IsDeleted  = 0
        )                                           AS AwardedBadgeCodes,
        -- Whether a certificate has already been issued for this volunteer on this project
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc2
                  WHERE vc2.ProjectId = pa.ProjectId
                    AND vc2.UserId    = pa.UserId
                    AND vc2.IsDeleted = 0), 1, 0)   AS HasCertificate
    FROM   ProjectApplications pa
    JOIN   UserProfiles up   ON pa.UserId        = up.UserId AND up.IsDeleted = 0
    JOIN   Users u           ON u.UserId         = pa.UserId
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    -- Most-recent attendance record for this user on this project
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    LEFT JOIN LookupValues   attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps   ON ps.SessionId          = att.SessionId
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           )
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications
    WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;
END //

CREATE PROCEDURE Application_Review(IN p_ApplicationId INT UNSIGNED, IN p_ReviewedBy INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_RejectionReason TEXT)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    UPDATE ProjectApplications SET StatusLkpId = v_StatusLkpId, StatusUpdatedAt = NOW(),
        StatusUpdatedBy = p_ReviewedBy, RejectionReason = p_RejectionReason
    WHERE ApplicationId = p_ApplicationId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, CONCAT('Application ', p_StatusCode, '.') AS Message,
           (SELECT UserId    FROM ProjectApplications WHERE ApplicationId = p_ApplicationId) AS ApplicantUserId,
           (SELECT ProjectId FROM ProjectApplications WHERE ApplicationId = p_ApplicationId) AS ProjectId;
END //

CREATE PROCEDURE Application_GetByUser(IN p_UserId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;
    SELECT pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName,
           sv.ValueCode AS StatusCode, sv.ValueName AS Status, pa.CreatedAt
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;
    SELECT COUNT(*) AS TotalCount FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //

-- v4.0 NEW: Volunteer cancels their own application
CREATE PROCEDURE Application_Cancel(IN p_ApplicationId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN' LIMIT 1;
    UPDATE ProjectApplications SET StatusLkpId = v_StatusLkpId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
    WHERE ApplicationId = p_ApplicationId AND UserId = p_UserId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Application withdrawn.' AS Message;
END //

-- ── POST / FEED SPs ──────────────────────────────────────────────
-- (Source: NGOConnect_Patch_PostFeed_VideoSupport.sql + NGOConnect_Patch_PostFeed_OrgFilter.sql)

DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,           -- comma-separated remote URLs
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ImageTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_VideoTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultTypeLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve default post type (GENERAL) if not supplied
    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
        SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
    END IF;

    -- Insert post
    INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
    VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

    SET @NewPostId = LAST_INSERT_ID();

    -- Store media with correct type (IMAGE or VIDEO detected from extension)
    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN

        SELECT lv.LookupValueId INTO v_ImageTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

        SELECT lv.LookupValueId INTO v_VideoTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'VIDEO' LIMIT 1;

        IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;
        IF v_VideoTypeLkpId = 0 THEN SET v_VideoTypeLkpId = v_ImageTypeLkpId; END IF;

        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT
            @NewPostId,
            TRIM(j.val),
            CASE
                WHEN LOWER(TRIM(j.val)) REGEXP '\\.(mp4|mov|avi|mkv|webm|m4v|3gp|wmv)$'
                     THEN v_VideoTypeLkpId
                ELSE v_ImageTypeLkpId
            END,
            j.rn
        FROM JSON_TABLE(
            CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
            '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')
        ) AS j
        WHERE TRIM(j.val) != '';

    END IF;

    SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
END //

-- (Source: NGOConnect_Patch_PostFeed_OrgFilter.sql — 4-param with OrgId filter + media grouped)
DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,   -- NULL = all orgs | non-null = filter to one org
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,
        p.LikeCount,
        p.CommentCount,
        p.ViewCount,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLiked,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up         ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o      ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm         ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      AND  NOT EXISTS (
               SELECT 1 FROM PostReports pr
               WHERE pr.PostId = p.PostId AND pr.ReportedByUserId = p_UserId
           )
    GROUP BY
        p.PostId, p.Content, p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount, p.ViewCount,
        p.UserId, up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId, o.OrgName,
        p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      AND  NOT EXISTS (
               SELECT 1 FROM PostReports pr
               WHERE pr.PostId = p.PostId AND pr.ReportedByUserId = p_UserId
           );
END //

-- v4.0 MODIFIED: includes media URLs
CREATE PROCEDURE Post_GetById(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.PostId, p.Content,
        ptv.ValueCode AS PostType, ptv.ValueName AS PostTypeName,
        p.LikeCount, p.CommentCount, p.ViewCount, p.IsPinned, p.CreatedAt, p.UpdatedAt,
        p.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName, up.ProfilePhoto,
        p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        IF(pl.PostLikeId IS NOT NULL, 1, 0) AS IsLiked,
        (SELECT GROUP_CONCAT(pm2.FileUrl ORDER BY pm2.SortOrder SEPARATOR ',') FROM PostMedia pm2 WHERE pm2.PostId = p.PostId) AS MediaUrls,
        (SELECT lv2.ValueCode FROM PostMedia pm3 JOIN LookupValues lv2 ON pm3.MediaTypeLkpId = lv2.LookupValueId WHERE pm3.PostId = p.PostId LIMIT 1) AS MediaType
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.PostTypeLkpId = ptv.LookupValueId
    LEFT JOIN PostLikes pl ON p.PostId = pl.PostId AND pl.UserId = p_UserId
    WHERE p.PostId = p_PostId AND p.IsDeleted = 0;
END //

CREATE PROCEDURE Post_Like(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    INSERT IGNORE INTO PostLikes (PostId, UserId) VALUES (p_PostId, p_UserId);
    UPDATE Posts SET LikeCount = (SELECT COUNT(*) FROM PostLikes WHERE PostId = p_PostId) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post liked.' AS Message,
           p.UserId AS PostAuthorUserId,
           CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM   Posts p
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE  p.PostId = p_PostId AND p.IsDeleted = 0
    LIMIT  1;
END //

CREATE PROCEDURE Post_Unlike(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DELETE FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId;
    UPDATE Posts SET LikeCount = (SELECT COUNT(*) FROM PostLikes WHERE PostId = p_PostId) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post unliked.' AS Message;
END //

-- Updated: enforces CanComment from OrgMembers for org-scoped posts (Permission Enforcement patch)
-- Updated: returns PostAuthorUserId + ActorName for notification dispatch
CREATE PROCEDURE Post_AddComment(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Content TEXT, IN p_ParentCommentId INT UNSIGNED)
BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT 0;
    DECLARE v_AuthorUserId  INT UNSIGNED DEFAULT 0;
    DECLARE v_CanComment    TINYINT(1)  DEFAULT 1;  -- default allow for everyone

    -- Look up the post's OrgId and author
    SELECT OrgId, UserId INTO v_OrgId, v_AuthorUserId
    FROM   Posts WHERE PostId = p_PostId AND IsDeleted = 0 LIMIT 1;

    -- For org posts: block only if admin has explicitly set CanComment = 0 for this member.
    -- Non-members (no row in OrgMembers) are allowed by default.
    IF v_OrgId > 0 THEN
        SELECT COALESCE(om.CanComment, 1) INTO v_CanComment
        FROM   OrgMembers om
        WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
        LIMIT  1;
        -- If no membership row found, COALESCE returns 1 → allowed
    END IF;

    IF v_CanComment = 0 THEN
        SELECT 0    AS IsSuccess,
               'You have been restricted from commenting in this organisation.' AS Message,
               NULL AS CommentId,
               NULL AS PostAuthorUserId,
               NULL AS ActorName;
    ELSE
        INSERT INTO PostComments (PostId, UserId, ParentCommentId, Content)
        VALUES (p_PostId, p_UserId, p_ParentCommentId, p_Content);
        UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId,
               v_AuthorUserId AS PostAuthorUserId,
               CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
        FROM   UserProfiles up
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0
        LIMIT  1;
    END IF;
END //

CREATE PROCEDURE Post_GetComments(IN p_PostId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;
    SELECT c.CommentId, c.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName,
           up.ProfilePhoto, c.Content, c.LikeCount, c.ParentCommentId, c.CreatedAt
    FROM PostComments c
    JOIN UserProfiles up ON c.UserId = up.UserId AND up.IsDeleted = 0
    WHERE c.PostId = p_PostId AND c.IsDeleted = 0
    ORDER BY c.CreatedAt ASC LIMIT p_PageSize OFFSET v_Offset;
    SELECT COUNT(*) AS TotalCount FROM PostComments WHERE PostId = p_PostId AND IsDeleted = 0;
END //

-- v4.0 NEW: Soft-delete a post
CREATE PROCEDURE Post_Delete(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE Posts SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId
    WHERE PostId = p_PostId AND (UserId = p_UserId OR OrgId IN (SELECT OrgId FROM OrgMembers WHERE UserId = p_UserId AND IsDeleted = 0)) AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Post deleted.' AS Message;
END //

-- v4.0 NEW: Pin / unpin a post within an org
CREATE PROCEDURE Post_Pin(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Pin TINYINT(1))
BEGIN
    UPDATE Posts SET IsPinned = p_Pin, PinnedAt = IF(p_Pin = 1, NOW(), NULL), PinnedBy = IF(p_Pin = 1, p_UserId, NULL)
    WHERE PostId = p_PostId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, IF(p_Pin = 1, 'Post pinned.', 'Post unpinned.') AS Message;
END //

-- v4.0 NEW: Edit post content
CREATE PROCEDURE Post_Update(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Content TEXT)
BEGIN
    UPDATE Posts SET Content = p_Content, UpdatedBy = p_UserId, UpdatedAt = NOW()
    WHERE PostId = p_PostId AND UserId = p_UserId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Post updated.' AS Message;
END //

-- ── COMMUNITY SPs ───────────────────────────────────────────────

-- v4.0 MODIFIED: accepts all typed post fields
CREATE PROCEDURE Community_CreatePost(
    IN p_OrgId            INT UNSIGNED,
    IN p_UserId           INT UNSIGNED,
    IN p_PostTypeLkpId    INT UNSIGNED,
    IN p_AudienceLkpId    INT UNSIGNED,
    IN p_Title            VARCHAR(300),
    IN p_Content          TEXT,
    IN p_AssignedToUserId INT UNSIGNED,
    IN p_DueDate          DATETIME,
    IN p_TaskStatusLkpId  INT UNSIGNED,
    IN p_PollEndsAt       DATETIME,
    IN p_PollIsMultiChoice TINYINT(1),
    IN p_VolunteersNeeded INT UNSIGNED,
    IN p_ResourceFileUrl  VARCHAR(500),
    IN p_EventRef         VARCHAR(200)
)
BEGIN
    INSERT INTO CommunityPosts
        (OrgId, UserId, PostTypeLkpId, AudienceLkpId, Title, Content,
         AssignedToUserId, DueDate, TaskStatusLkpId, PollEndsAt, PollIsMultiChoice,
         VolunteersNeeded, ResourceFileUrl, EventRef, CreatedBy)
    VALUES
        (p_OrgId, p_UserId, p_PostTypeLkpId, p_AudienceLkpId, p_Title, p_Content,
         p_AssignedToUserId, p_DueDate, p_TaskStatusLkpId, p_PollEndsAt, p_PollIsMultiChoice,
         p_VolunteersNeeded, p_ResourceFileUrl, p_EventRef, p_UserId);
    SELECT 1 AS IsSuccess, 'Community post created.' AS Message, LAST_INSERT_ID() AS CommunityPostId;
END //

-- v4.0 MODIFIED: returns typed fields + poll info + ack status
CREATE PROCEDURE Community_GetFeed(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT cp.CommunityPostId, cp.Title, cp.Content,
           ptv.ValueCode AS PostType, ptv.ValueName AS PostTypeName,
           av.ValueCode AS AudienceCode,
           cp.IsPinned, cp.AcknowledgeCount,
           cp.AssignedToUserId,
           CONCAT(aup.FirstName,' ',aup.LastName) AS AssignedToName,
           cp.DueDate, tsv.ValueCode AS TaskStatus,
           cp.PollEndsAt, cp.PollIsMultiChoice,
           cp.VolunteersNeeded, cp.ResourceFileUrl, cp.EventRef,
           cp.CreatedAt,
           cp.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName, up.ProfilePhoto,
           IF(cpa.AckId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe
    FROM CommunityPosts cp
    JOIN UserProfiles up ON cp.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN UserProfiles aup ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT JOIN CommunityPostAcknowledgements cpa ON cp.CommunityPostId = cpa.CommunityPostId AND cpa.UserId = p_UserId
    WHERE cp.OrgId = p_OrgId AND cp.IsDeleted = 0
    ORDER BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM CommunityPosts WHERE OrgId = p_OrgId AND IsDeleted = 0;
END //

CREATE PROCEDURE Community_CreatePoll(IN p_CommunityPostId INT UNSIGNED, IN p_Options TEXT)
BEGIN
    INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
    SELECT p_CommunityPostId, TRIM(j.opt), ROW_NUMBER() OVER () AS SortOrder
    FROM JSON_TABLE(
        CONCAT('["', REPLACE(p_Options, ',', '","'), '"]'),
        '$[*]' COLUMNS (opt VARCHAR(200) PATH '$')
    ) j WHERE TRIM(j.opt) != '';
    SELECT 1 AS IsSuccess, 'Poll options created.' AS Message;
END //

CREATE PROCEDURE Community_Vote(IN p_PollOptionId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_CommunityPostId INT UNSIGNED;
    DECLARE v_Exists INT DEFAULT 0;
    SELECT CommunityPostId INTO v_CommunityPostId FROM PollOptions WHERE PollOptionId = p_PollOptionId;
    SELECT COUNT(*) INTO v_Exists FROM PollVotes WHERE CommunityPostId = v_CommunityPostId AND UserId = p_UserId;
    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'Already voted on this poll.' AS Message;
    ELSE
        INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId) VALUES (p_PollOptionId, v_CommunityPostId, p_UserId);
        UPDATE PollOptions SET VoteCount = VoteCount + 1 WHERE PollOptionId = p_PollOptionId;
        SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
    END IF;
END //

-- v4.0 NEW: Get a single community post with poll options
CREATE PROCEDURE Community_GetPostById(IN p_CommunityPostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT cp.CommunityPostId, cp.Title, cp.Content,
           ptv.ValueCode AS PostType, av.ValueCode AS AudienceCode,
           cp.IsPinned, cp.AcknowledgeCount,
           cp.AssignedToUserId, cp.DueDate,
           tsv.ValueCode AS TaskStatus,
           cp.PollEndsAt, cp.PollIsMultiChoice,
           cp.VolunteersNeeded, cp.ResourceFileUrl, cp.EventRef,
           cp.CreatedAt, cp.UpdatedAt,
           cp.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName, up.ProfilePhoto,
           IF(cpa.AckId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe
    FROM CommunityPosts cp
    JOIN UserProfiles up ON cp.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT JOIN CommunityPostAcknowledgements cpa ON cp.CommunityPostId = cpa.CommunityPostId AND cpa.UserId = p_UserId
    WHERE cp.CommunityPostId = p_CommunityPostId AND cp.IsDeleted = 0;

    SELECT po.PollOptionId, po.OptionText, po.VoteCount,
           IF(pv.PollVoteId IS NOT NULL, 1, 0) AS IsVotedByMe
    FROM PollOptions po
    LEFT JOIN PollVotes pv ON po.PollOptionId = pv.PollOptionId AND pv.UserId = p_UserId
    WHERE po.CommunityPostId = p_CommunityPostId ORDER BY po.SortOrder;
END //

-- v4.0 NEW: Soft-delete a community post
CREATE PROCEDURE Community_DeletePost(IN p_CommunityPostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE CommunityPosts SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId
    WHERE CommunityPostId = p_CommunityPostId AND IsDeleted = 0
      AND (UserId = p_UserId OR OrgId IN (SELECT OrgId FROM OrgMembers WHERE UserId = p_UserId AND IsDeleted = 0));
    SELECT 1 AS IsSuccess, 'Community post deleted.' AS Message;
END //

-- v4.0 NEW: Acknowledge toggle
CREATE PROCEDURE Community_AcknowledgePost(IN p_CommunityPostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM CommunityPostAcknowledgements
    WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;
    IF v_Exists = 0 THEN
        INSERT INTO CommunityPostAcknowledgements (CommunityPostId, UserId) VALUES (p_CommunityPostId, p_UserId);
        UPDATE CommunityPosts SET AcknowledgeCount = AcknowledgeCount + 1 WHERE CommunityPostId = p_CommunityPostId;
        SELECT 1 AS IsSuccess, 'Post acknowledged.' AS Message;
    ELSE
        DELETE FROM CommunityPostAcknowledgements WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;
        UPDATE CommunityPosts SET AcknowledgeCount = GREATEST(AcknowledgeCount - 1, 0) WHERE CommunityPostId = p_CommunityPostId;
        SELECT 1 AS IsSuccess, 'Acknowledgement removed.' AS Message;
    END IF;
END //

-- ── SOS SPs ──────────────────────────────────────────────────────

CREATE PROCEDURE Sos_Trigger(IN p_UserId INT UNSIGNED, IN p_OrgId INT UNSIGNED, IN p_AlertTypeLkpId INT UNSIGNED, IN p_Description TEXT, IN p_Latitude DECIMAL(10,7), IN p_Longitude DECIMAL(10,7), IN p_ApproxLocation VARCHAR(300))
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;
    INSERT INTO SosIncidents (UserId, OrgId, AlertTypeLkpId, Description, Latitude, Longitude, ApproxLocation, StatusLkpId)
    VALUES (p_UserId, p_OrgId, p_AlertTypeLkpId, p_Description, p_Latitude, p_Longitude, p_ApproxLocation, v_StatusLkpId);
    SELECT 1 AS IsSuccess, 'SOS triggered.' AS Message, LAST_INSERT_ID() AS SosIncidentId;
END //

CREATE PROCEDURE Sos_Respond(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_VictimUserId INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT UserId INTO v_VictimUserId FROM SosIncidents WHERE SosIncidentId = p_SosIncidentId LIMIT 1;

    INSERT IGNORE INTO SosResponders (SosIncidentId, UserId, ApprovalStatusLkpId)
    VALUES (p_SosIncidentId, p_UserId, v_StatusLkpId);

    SELECT 1 AS IsSuccess, 'Response registered, awaiting approval.' AS Message,
           v_VictimUserId AS VictimUserId;
END //

CREATE PROCEDURE Sos_UpdateLocation(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Latitude DECIMAL(10,7), IN p_Longitude DECIMAL(10,7), IN p_Accuracy DECIMAL(8,2))
BEGIN
    INSERT INTO SosLocationLogs (SosIncidentId, UserId, Latitude, Longitude, Accuracy)
    VALUES (p_SosIncidentId, p_UserId, p_Latitude, p_Longitude, p_Accuracy);
    SELECT 1 AS IsSuccess, 'Location updated.' AS Message;
END //

-- v4.0 MODIFIED: org-scoped, returns OrgId/OrgName
CREATE PROCEDURE Sos_GetActive(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ActiveLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_ActiveLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT si.SosIncidentId, si.UserId,
           CONCAT(up.FirstName,' ',up.LastName) AS UserName, up.ProfilePhoto,
           atv.ValueCode AS AlertType, atv.ValueName AS AlertTypeName,
           si.Description, si.ApproxLocation, si.Latitude, si.Longitude,
           si.OrgId, o.OrgName,
           si.CreatedAt,
           (SELECT COUNT(*) FROM SosResponders WHERE SosIncidentId = si.SosIncidentId) AS ResponderCount
    FROM SosIncidents si
    JOIN UserProfiles up ON si.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN Organisations o ON si.OrgId = o.OrgId
    LEFT JOIN LookupValues atv ON si.AlertTypeLkpId = atv.LookupValueId
    WHERE si.StatusLkpId = v_ActiveLkpId AND si.IsDeleted = 0
      AND (p_OrgId IS NULL OR si.OrgId = p_OrgId)
    ORDER BY si.CreatedAt DESC;
END //

-- v4.0 MODIFIED: handles both RESOLVED and CANCELLED with CancelReason
CREATE PROCEDURE Sos_Resolve(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_CancelReason TEXT)
BEGIN
    DECLARE v_StatusLkpId   INT UNSIGNED;
    DECLARE v_ResolvedByLkpId INT UNSIGNED DEFAULT NULL;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    IF p_StatusCode = 'RESOLVED' THEN
        SELECT LookupValueId INTO v_ResolvedByLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SOS_RESOLVED_BY' AND lv.ValueCode = 'SELF' LIMIT 1;
    END IF;

    UPDATE SosIncidents SET StatusLkpId = v_StatusLkpId,
        ResolvedAt = NOW(), ResolvedByLkpId = v_ResolvedByLkpId,
        CancelReason = p_CancelReason
    WHERE SosIncidentId = p_SosIncidentId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, CONCAT('SOS ', p_StatusCode, '.') AS Message;
END //

-- v4.0 NEW: Admin approves a responder and grants location access
CREATE PROCEDURE Sos_ApproveResponder(IN p_SosResponderId INT UNSIGNED, IN p_ApprovedBy INT UNSIGNED, IN p_CanViewLocation TINYINT(1))
BEGIN
    DECLARE v_StatusLkpId     INT UNSIGNED;
    DECLARE v_ResponderUserId INT UNSIGNED;
    DECLARE v_SosIncidentId   INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;
    SELECT UserId, SosIncidentId INTO v_ResponderUserId, v_SosIncidentId
    FROM   SosResponders WHERE SosResponderId = p_SosResponderId;
    UPDATE SosResponders SET ApprovalStatusLkpId = v_StatusLkpId,
        ApprovedAt = NOW(), ApprovedBy = p_ApprovedBy, CanViewLocation = COALESCE(p_CanViewLocation, 0)
    WHERE SosResponderId = p_SosResponderId;
    SELECT 1 AS IsSuccess, 'Responder approved.' AS Message,
           v_ResponderUserId AS ResponderUserId, v_SosIncidentId AS SosIncidentId;
END //

-- v4.0 NEW: Cancel an active SOS
CREATE PROCEDURE Sos_Cancel(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_CancelReason TEXT)
BEGIN
    CALL Sos_Resolve(p_SosIncidentId, p_UserId, 'CANCELLED', p_CancelReason);
END //

-- v4.0 NEW: Get latest location for an incident (for approved responders)
CREATE PROCEDURE Sos_GetLatestLocation(IN p_SosIncidentId INT UNSIGNED, IN p_RequestingUserId INT UNSIGNED)
BEGIN
    DECLARE v_CanView TINYINT(1) DEFAULT 0;
    -- Check if user is the victim or an approved responder
    SELECT 1 INTO v_CanView FROM SosIncidents WHERE SosIncidentId = p_SosIncidentId AND UserId = p_RequestingUserId LIMIT 1;
    IF v_CanView = 0 THEN
        SELECT 1 INTO v_CanView FROM SosResponders
        WHERE SosIncidentId = p_SosIncidentId AND UserId = p_RequestingUserId AND CanViewLocation = 1 LIMIT 1;
    END IF;

    IF v_CanView = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message, NULL AS Latitude, NULL AS Longitude;
    ELSE
        SELECT Latitude, Longitude, Accuracy, LoggedAt
        FROM SosLocationLogs
        WHERE SosIncidentId = p_SosIncidentId
        ORDER BY LoggedAt DESC LIMIT 1;
    END IF;
END //

-- v4.0 NEW: Get single SOS incident details
CREATE PROCEDURE Sos_GetById(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT si.SosIncidentId, si.UserId,
           CONCAT(up.FirstName,' ',up.LastName) AS UserName, up.ProfilePhoto, up.Mobile,
           atv.ValueCode AS AlertType, sv.ValueCode AS Status,
           si.Description, si.ApproxLocation, si.Latitude, si.Longitude,
           si.CancelReason, si.ResolvedAt, si.CancelledAt, si.CreatedAt,
           si.OrgId, o.OrgName
    FROM SosIncidents si
    JOIN UserProfiles up ON si.UserId = up.UserId AND up.IsDeleted = 0
    JOIN Users u ON si.UserId = u.UserId
    LEFT JOIN Organisations o ON si.OrgId = o.OrgId
    LEFT JOIN LookupValues atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT JOIN LookupValues sv  ON si.StatusLkpId    = sv.LookupValueId
    WHERE si.SosIncidentId = p_SosIncidentId AND si.IsDeleted = 0;

    -- Responders list
    SELECT sr.SosResponderId, sr.UserId, CONCAT(up2.FirstName,' ',up2.LastName) AS ResponderName,
           rv.ValueCode AS ApprovalStatus, sr.RespondedAt, sr.CanViewLocation
    FROM SosResponders sr
    JOIN UserProfiles up2 ON sr.UserId = up2.UserId AND up2.IsDeleted = 0
    LEFT JOIN LookupValues rv ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE sr.SosIncidentId = p_SosIncidentId;
END //

-- ── DONATION SPs ────────────────────────────────────────────────

CREATE PROCEDURE Donation_CreateCampaign(IN p_OrgId INT UNSIGNED, IN p_Title VARCHAR(200), IN p_Description TEXT, IN p_TargetAmount DECIMAL(15,2), IN p_StartDate DATE, IN p_EndDate DATE, IN p_CampaignTypeLkpId INT UNSIGNED, IN p_CreatedBy INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;
    INSERT INTO DonationCampaigns (OrgId, Title, Description, TargetAmount, StartDate, EndDate, CampaignTypeLkpId, StatusLkpId, CreatedBy)
    VALUES (p_OrgId, p_Title, p_Description, p_TargetAmount, p_StartDate, p_EndDate, p_CampaignTypeLkpId, v_StatusLkpId, p_CreatedBy);
    SELECT 1 AS IsSuccess, 'Campaign created.' AS Message, LAST_INSERT_ID() AS CampaignId;
END //

CREATE PROCEDURE Donation_GetCampaigns(IN p_OrgId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    SELECT dc.CampaignId, dc.OrgId, o.OrgName, o.LogoUrl, dc.Title, dc.Description,
           dc.TargetAmount, dc.RaisedAmount, dc.StartDate, dc.EndDate,
           sv.ValueCode AS Status, ctv.ValueCode AS CampaignType, dc.CreatedAt
    FROM DonationCampaigns dc
    JOIN Organisations o ON dc.OrgId = o.OrgId
    LEFT JOIN LookupValues sv  ON dc.StatusLkpId       = sv.LookupValueId
    LEFT JOIN LookupValues ctv ON dc.CampaignTypeLkpId = ctv.LookupValueId
    WHERE dc.IsDeleted = 0
      AND (p_OrgId IS NULL OR dc.OrgId = p_OrgId)
      AND (p_StatusCode IS NULL OR sv.ValueCode = p_StatusCode)
    ORDER BY dc.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationCampaigns dc
    LEFT JOIN LookupValues sv ON dc.StatusLkpId = sv.LookupValueId
    WHERE dc.IsDeleted = 0
      AND (p_OrgId IS NULL OR dc.OrgId = p_OrgId)
      AND (p_StatusCode IS NULL OR sv.ValueCode = p_StatusCode);
END //

CREATE PROCEDURE Donation_Donate(IN p_UserId INT UNSIGNED, IN p_CampaignId INT UNSIGNED, IN p_Amount DECIMAL(15,2), IN p_PaymentGatewayRef VARCHAR(200), IN p_IsAnonymous TINYINT(1), IN p_IsRecurring TINYINT(1), IN p_RecurringFrequencyLkpId INT UNSIGNED, IN p_Message TEXT)
BEGIN
    DECLARE v_DonationId   VARCHAR(30);
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    SELECT OrgId INTO v_OrgId FROM DonationCampaigns WHERE CampaignId = p_CampaignId AND IsDeleted = 0;

    -- Generate readable ID DON-YYYY-NNNNNN
    UPDATE IdSequences SET LastNumber = LastNumber + 1 WHERE Prefix = 'DON' AND SeqYear = YEAR(NOW());
    SELECT CONCAT('DON-', SeqYear, '-', LPAD(LastNumber, 6, '0')) INTO v_DonationId
    FROM IdSequences WHERE Prefix = 'DON' AND SeqYear = YEAR(NOW());

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    INSERT INTO DonationTransactions (DonationId, UserId, OrgId, CampaignId, Amount, PaymentGatewayRef, IsAnonymous, Message, StatusLkpId)
    VALUES (v_DonationId, p_UserId, v_OrgId, p_CampaignId, p_Amount, p_PaymentGatewayRef, COALESCE(p_IsAnonymous,0), p_Message, v_StatusLkpId);

    -- Recurring setup
    IF p_IsRecurring = 1 AND p_RecurringFrequencyLkpId IS NOT NULL THEN
        INSERT INTO RecurringDonations (UserId, CampaignId, Amount, FrequencyLkpId, NextRunAt)
        VALUES (p_UserId, p_CampaignId, p_Amount, p_RecurringFrequencyLkpId, DATE_ADD(NOW(), INTERVAL 1 MONTH));
    END IF;

    SELECT 1 AS IsSuccess, 'Donation initiated.' AS Message, LAST_INSERT_ID() AS TransactionId, v_DonationId AS DonationId;
END //

CREATE PROCEDURE Donation_ConfirmPayment(IN p_TransactionId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_GatewayResponse JSON)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_Amount      DECIMAL(15,2);
    DECLARE v_CampaignId  INT UNSIGNED;
    DECLARE v_DonorUserId INT UNSIGNED;
    DECLARE v_OrgId       INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    SELECT DonationAmount, CampaignId, DonorUserId, OrgId
    INTO   v_Amount, v_CampaignId, v_DonorUserId, v_OrgId
    FROM   DonationTransactions WHERE TransactionId = p_TransactionId;

    UPDATE DonationTransactions SET PayStatusLkpId = v_StatusLkpId, GatewayResponse = p_GatewayResponse, UpdatedAt = NOW()
    WHERE TransactionId = p_TransactionId;

    IF p_StatusCode = 'SUCCESS' THEN
        UPDATE DonationCampaigns SET RaisedAmount = RaisedAmount + v_Amount WHERE CampaignId = v_CampaignId;
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Payment ', p_StatusCode, '.') AS Message,
           v_DonorUserId AS DonorUserId, v_OrgId AS OrgId, v_CampaignId AS CampaignId;
END //

CREATE PROCEDURE Donation_GetHistory(IN p_UserId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    SELECT dt.TransactionId, dt.DonationId, dt.CampaignId, dc.Title AS CampaignTitle,
           dt.OrgId, o.OrgName, dt.Amount, sv.ValueCode AS Status,
           dt.IsAnonymous, dt.Message, dt.CreatedAt
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    JOIN Organisations o ON dt.OrgId = o.OrgId
    LEFT JOIN LookupValues sv ON dt.StatusLkpId = sv.LookupValueId
    WHERE dt.UserId = p_UserId AND dt.IsDeleted = 0
    ORDER BY dt.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationTransactions WHERE UserId = p_UserId AND IsDeleted = 0;
END //

-- v4.0 NEW: Pause a recurring donation
CREATE PROCEDURE Donation_PauseRecurring(IN p_RecurringDonationId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE RecurringDonations SET IsActive = 0, PausedAt = NOW()
    WHERE RecurringDonationId = p_RecurringDonationId AND UserId = p_UserId;
    SELECT 1 AS IsSuccess, 'Recurring donation paused.' AS Message;
END //

-- v4.0 NEW: Resume a paused recurring donation
CREATE PROCEDURE Donation_ResumeRecurring(IN p_RecurringDonationId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE RecurringDonations SET IsActive = 1, PausedAt = NULL, NextRunAt = DATE_ADD(NOW(), INTERVAL 1 MONTH)
    WHERE RecurringDonationId = p_RecurringDonationId AND UserId = p_UserId;
    SELECT 1 AS IsSuccess, 'Recurring donation resumed.' AS Message;
END //

-- v4.0 NEW: Annual giving summary for a user (for 80G receipts)
CREATE PROCEDURE Donation_GetAnnualSummary(IN p_UserId INT UNSIGNED, IN p_Year INT)
BEGIN
    DECLARE v_SuccessLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_SuccessLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = 'SUCCESS' LIMIT 1;

    SELECT YEAR(dt.CreatedAt) AS Year, SUM(dt.Amount) AS TotalDonated, COUNT(*) AS TotalTransactions,
           COUNT(DISTINCT dt.OrgId) AS NGOsSupported
    FROM DonationTransactions dt
    WHERE dt.UserId = p_UserId AND dt.StatusLkpId = v_SuccessLkpId AND dt.IsDeleted = 0
      AND YEAR(dt.CreatedAt) = COALESCE(p_Year, YEAR(NOW()))
    GROUP BY YEAR(dt.CreatedAt);

    -- Per-NGO breakdown
    SELECT o.OrgId, o.OrgName, SUM(dt.Amount) AS Donated, COUNT(*) AS Transactions
    FROM DonationTransactions dt
    JOIN Organisations o ON dt.OrgId = o.OrgId
    WHERE dt.UserId = p_UserId AND dt.StatusLkpId = v_SuccessLkpId AND dt.IsDeleted = 0
      AND YEAR(dt.CreatedAt) = COALESCE(p_Year, YEAR(NOW()))
    GROUP BY o.OrgId ORDER BY Donated DESC;
END //

-- v4.0 NEW: NGOs a user has supported (for donor profile)
CREATE PROCEDURE Donation_GetSupportedNGOs(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_SuccessLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_SuccessLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = 'SUCCESS' LIMIT 1;

    SELECT o.OrgId, o.OrgName, o.LogoUrl, SUM(dt.Amount) AS TotalDonated,
           COUNT(*) AS Transactions, MAX(dt.CreatedAt) AS LastDonatedAt
    FROM DonationTransactions dt
    JOIN Organisations o ON dt.OrgId = o.OrgId
    WHERE dt.UserId = p_UserId AND dt.StatusLkpId = v_SuccessLkpId AND dt.IsDeleted = 0
    GROUP BY o.OrgId ORDER BY LastDonatedAt DESC;
END //

-- v4.0 NEW: Get donors for an NGO campaign (for NGO transparency)
CREATE PROCEDURE Donation_GetDonors(IN p_OrgId INT UNSIGNED, IN p_CampaignId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_SuccessLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_SuccessLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PAYMENT_STATUS' AND lv.ValueCode = 'SUCCESS' LIMIT 1;

    SELECT dt.TransactionId, dt.DonationId,
           IF(dt.IsAnonymous = 1, 'Anonymous', CONCAT(up.FirstName,' ',up.LastName)) AS DonorName,
           IF(dt.IsAnonymous = 1, NULL, up.ProfilePhoto) AS ProfilePhoto,
           dt.Amount, dt.Message, dt.CreatedAt
    FROM DonationTransactions dt
    JOIN UserProfiles up ON dt.UserId = up.UserId AND up.IsDeleted = 0
    WHERE dt.OrgId = p_OrgId AND dt.StatusLkpId = v_SuccessLkpId AND dt.IsDeleted = 0
      AND (p_CampaignId IS NULL OR dt.CampaignId = p_CampaignId)
    ORDER BY dt.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationTransactions dt
    WHERE dt.OrgId = p_OrgId AND dt.StatusLkpId = v_SuccessLkpId AND dt.IsDeleted = 0
      AND (p_CampaignId IS NULL OR dt.CampaignId = p_CampaignId);
END //

-- v4.0 NEW: All transactions for an NGO (finance view)
CREATE PROCEDURE Donation_GetOrgTransactions(IN p_OrgId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    SELECT dt.TransactionId, dt.DonationId, dt.CampaignId, dc.Title AS CampaignTitle,
           IF(dt.IsAnonymous=1,'Anonymous',CONCAT(up.FirstName,' ',up.LastName)) AS DonorName,
           dt.Amount, sv.ValueCode AS Status, dt.PaymentGatewayRef, dt.CreatedAt
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    JOIN UserProfiles up ON dt.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues sv ON dt.StatusLkpId = sv.LookupValueId
    WHERE dt.OrgId = p_OrgId AND dt.IsDeleted = 0
    ORDER BY dt.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationTransactions WHERE OrgId = p_OrgId AND IsDeleted = 0;
END //

-- ── WITHDRAWAL SPs ──────────────────────────────────────────────

-- v4.0 NEW: NGO creates withdrawal request
CREATE PROCEDURE Withdrawal_Create(IN p_OrgId INT UNSIGNED, IN p_CampaignId INT UNSIGNED, IN p_Amount DECIMAL(15,2), IN p_BankAccountName VARCHAR(200), IN p_BankAccountNumber VARCHAR(30), IN p_BankIfsc VARCHAR(20), IN p_Notes TEXT, IN p_RequestedBy INT UNSIGNED)
BEGIN
    DECLARE v_WithdrawalId VARCHAR(30);
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_RaisedAmount DECIMAL(15,2);

    SELECT RaisedAmount INTO v_RaisedAmount FROM DonationCampaigns WHERE CampaignId = p_CampaignId AND OrgId = p_OrgId AND IsDeleted = 0;
    IF v_RaisedAmount IS NULL OR v_RaisedAmount < p_Amount THEN
        SELECT 0 AS IsSuccess, 'Insufficient campaign balance.' AS Message, NULL AS WithdrawalId;
    ELSE
        UPDATE IdSequences SET LastNumber = LastNumber + 1 WHERE Prefix = 'WDR' AND SeqYear = YEAR(NOW());
        SELECT CONCAT('WDR-', SeqYear, '-', LPAD(LastNumber, 4, '0')) INTO v_WithdrawalId
        FROM IdSequences WHERE Prefix = 'WDR' AND SeqYear = YEAR(NOW());

        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'WITHDRAWAL_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        INSERT INTO WithdrawalRequests (WithdrawalId, OrgId, CampaignId, Amount, BankAccountName, BankAccountNumber, BankIfsc, Notes, StatusLkpId, RequestedBy)
        VALUES (v_WithdrawalId, p_OrgId, p_CampaignId, p_Amount, p_BankAccountName, p_BankAccountNumber, p_BankIfsc, p_Notes, v_StatusLkpId, p_RequestedBy);
        SELECT 1 AS IsSuccess, 'Withdrawal request submitted.' AS Message, LAST_INSERT_ID() AS WithdrawalRequestId, v_WithdrawalId AS WithdrawalId;
    END IF;
END //

-- v4.0 NEW: Get withdrawal requests for an NGO
CREATE PROCEDURE Withdrawal_GetByOrg(IN p_OrgId INT UNSIGNED, IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    SELECT wr.WithdrawalRequestId, wr.WithdrawalId, wr.CampaignId, dc.Title AS CampaignTitle,
           wr.Amount, sv.ValueCode AS Status, wr.BankAccountName, wr.BankIfsc,
           wr.Notes, wr.AdminNotes, wr.ProcessedAt, wr.CreatedAt
    FROM WithdrawalRequests wr
    LEFT JOIN DonationCampaigns dc ON wr.CampaignId = dc.CampaignId
    LEFT JOIN LookupValues sv ON wr.StatusLkpId = sv.LookupValueId
    WHERE wr.OrgId = p_OrgId AND wr.IsDeleted = 0
    ORDER BY wr.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM WithdrawalRequests WHERE OrgId = p_OrgId AND IsDeleted = 0;
END //

-- v4.0 NEW: Admin approves or rejects withdrawal
CREATE PROCEDURE Withdrawal_AdminReview(IN p_WithdrawalRequestId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_AdminNotes TEXT, IN p_ReviewedBy INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_Amount       DECIMAL(15,2);
    DECLARE v_CampaignId   INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'WITHDRAWAL_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    SELECT Amount, CampaignId, OrgId INTO v_Amount, v_CampaignId, v_OrgId
    FROM WithdrawalRequests WHERE WithdrawalRequestId = p_WithdrawalRequestId LIMIT 1;

    UPDATE WithdrawalRequests SET StatusLkpId = v_StatusLkpId, AdminNotes = p_AdminNotes,
        ReviewedBy = p_ReviewedBy, ProcessedAt = NOW()
    WHERE WithdrawalRequestId = p_WithdrawalRequestId;

    -- Deduct from campaign raised amount only if approved
    IF p_StatusCode = 'APPROVED' THEN
        UPDATE DonationCampaigns SET RaisedAmount = RaisedAmount - v_Amount WHERE CampaignId = v_CampaignId;
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Withdrawal ', p_StatusCode, '.') AS Message, v_OrgId AS OrgId;
END //

-- ── CERTIFICATE SPs ─────────────────────────────────────────────

-- v4.0 NEW: Get all certificates for a user
CREATE PROCEDURE Certificate_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT vc.CertificateId, vc.CertCode,
           vc.ProjectId, p.ProjectName AS ProjectTitle,
           vc.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
           vc.TotalHours, vc.CertificateUrl, vc.IssuedAt
    FROM VolunteerCertificates vc
    JOIN Projects p      ON vc.ProjectId = p.ProjectId
    JOIN Organisations o ON vc.OrgId     = o.OrgId
    WHERE vc.UserId = p_UserId AND vc.IsDeleted = 0
    ORDER BY vc.IssuedAt DESC;
END //

-- Returns all data needed to render a certificate (used by verify page and app)
-- v5.2: added CoordinatorName (JOIN UserProfiles cp ON vc.IssuedBy = cp.UserId)
CREATE PROCEDURE Certificate_GetData(IN p_CertCode VARCHAR(20))
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt,
        -- Live-computed so late attendance marks are reflected accurately
        COALESCE((SELECT SUM(pa.HoursLogged)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE ps.ProjectId = vc.ProjectId AND pa.UserId = vc.UserId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalHours,
        -- Volunteer
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VolunteerName,
        up.ProfilePhoto,
        -- Project
        p.ProjectId, p.ProjectName,
        -- Organisation
        o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        -- Impact score
        up.ImpactScore,
        -- Coordinator (admin who issued the certificate)
        CONCAT(cp.FirstName, ' ', cp.LastName) AS CoordinatorName,
        -- Skill ratings for this project (pipe-separated SkillName:Rating pairs)
        (SELECT GROUP_CONCAT(ps.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    JOIN  UserProfiles  cp ON vc.IssuedBy  = cp.UserId
    WHERE vc.CertCode = p_CertCode;
END //

-- v5.1 NEW: Same data as Certificate_GetData, keyed by the internal numeric
-- CertificateId instead of the sequential, guessable CertCode (CERT-2026-000001
-- style — an incrementing counter, NOT sparse despite an earlier doc's claim).
-- Used exclusively by the public /verify page via an AES-256-GCM encrypted
-- token (IUrlTokenService, entityType "CERT") that carries this ID — the raw
-- CertificateId is never exposed in a URL, so this SP being keyed by a "guessable"
-- sequential integer is not a problem: the caller can only reach it by first
-- successfully decrypting a token, which requires the server's secret key.
-- v5.2: added CoordinatorName (JOIN UserProfiles cp ON vc.IssuedBy = cp.UserId)
CREATE PROCEDURE Certificate_GetDataById(IN p_CertificateId INT UNSIGNED)
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt,
        -- Live-computed so late attendance marks are reflected accurately
        COALESCE((SELECT SUM(pa.HoursLogged)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE ps.ProjectId = vc.ProjectId AND pa.UserId = vc.UserId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalHours,
        -- Volunteer
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VolunteerName,
        up.ProfilePhoto,
        -- Project
        p.ProjectId, p.ProjectName,
        -- Organisation
        o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        -- Impact score
        up.ImpactScore,
        -- Coordinator (admin who issued the certificate)
        CONCAT(cp.FirstName, ' ', cp.LastName) AS CoordinatorName,
        -- Skill ratings for this project (pipe-separated SkillName:Rating pairs)
        (SELECT GROUP_CONCAT(ps.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    JOIN  UserProfiles  cp ON vc.IssuedBy  = cp.UserId
    WHERE vc.CertificateId = p_CertificateId;
END //

-- v5.1: Issues (or returns existing) certificate. TotalHours computed from DB (p_TotalHours removed).
CREATE PROCEDURE Certificate_Issue(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_IssuedBy  INT UNSIGNED
)
BEGIN
    DECLARE v_CertCode   VARCHAR(20);
    DECLARE v_TotalHours DECIMAL(6,2) DEFAULT 0;

    SELECT COALESCE(SUM(pa.HoursLogged), 0) INTO v_TotalHours
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
    JOIN   LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
    JOIN   LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED';

    SELECT CertCode INTO v_CertCode
    FROM   VolunteerCertificates
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_CertCode IS NOT NULL THEN
        SELECT 1 AS IsSuccess, 'Certificate already issued.' AS Message, v_CertCode AS CertCode;
    ELSE
        -- Self-healing: ensure the current-year row exists (handles year rollover)
        INSERT IGNORE INTO IdSequences (SequenceName, CurrentYear, LastValue)
        VALUES ('CERT', YEAR(NOW()), 0);

        UPDATE IdSequences SET LastValue = LastValue + 1
        WHERE  SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
        FROM   IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
        VALUES (v_CertCode, p_ProjectId, p_UserId, p_OrgId, v_TotalHours, p_IssuedBy);

        SELECT 1 AS IsSuccess, 'Certificate issued successfully.' AS Message, v_CertCode AS CertCode;
    END IF;
END //

-- Returns project skills + existing rating for a specific volunteer (for admin skill rating UI)
CREATE PROCEDURE Project_GetSkillRatings(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ps.ProjectSkillId,
        ps.SkillName,
        COALESCE(usr.Rating, 0)  AS Rating,
        usr.Notes
    FROM  ProjectSkills ps
    LEFT JOIN UserSkillRatings usr
          ON  usr.SkillId    = ps.ProjectSkillId
          AND usr.UserId     = p_UserId
          AND usr.ProjectId  = p_ProjectId
    WHERE ps.ProjectId = p_ProjectId
    ORDER BY ps.SkillName;
END //

-- ── SKILL RATING & BADGE SPs ────────────────────────────────────

-- v4.0 NEW: Add/update a skill rating for a volunteer (by org admin after project)
CREATE PROCEDURE UserSkillRating_Add(IN p_UserId INT UNSIGNED, IN p_OrgId INT UNSIGNED, IN p_ProjectId INT UNSIGNED, IN p_SkillId INT UNSIGNED, IN p_Rating DECIMAL(3,2), IN p_RatedBy INT UNSIGNED, IN p_Notes TEXT)
BEGIN
    INSERT INTO UserSkillRatings (UserId, OrgId, ProjectId, SkillId, Rating, RatedBy, Notes)
    VALUES (p_UserId, p_OrgId, p_ProjectId, p_SkillId, p_Rating, p_RatedBy, p_Notes)
    ON DUPLICATE KEY UPDATE Rating = p_Rating, Notes = p_Notes, UpdatedAt = NOW();
    SELECT 1 AS IsSuccess, 'Skill rating saved.' AS Message;
END //

-- Award a badge to a volunteer (accepts ValueCode string; resolves LookupValueId internally)
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId    INT UNSIGNED,
    IN p_BadgeCode VARCHAR(50),
    IN p_AwardedBy INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_ProjectId INT UNSIGNED
)
BEGIN
    DECLARE v_BadgeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_BadgeName  VARCHAR(100) DEFAULT 'Badge';
    DECLARE v_Exists     INT DEFAULT 0;

    -- Resolve LookupValueId from ValueCode
    SELECT lv.LookupValueId INTO v_BadgeLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'BADGE_TYPE' AND lv.ValueCode = p_BadgeCode LIMIT 1;

    IF v_BadgeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Unknown badge code: ', p_BadgeCode) AS Message,
               NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
    ELSE
        -- Prevent double-awarding the same badge on the same project
        SELECT COUNT(*) INTO v_Exists
        FROM   UserBadges
        WHERE  UserId     = p_UserId
          AND  BadgeLkpId = v_BadgeLkpId
          AND  (p_ProjectId IS NULL OR ProjectId = p_ProjectId)
          AND  IsDeleted   = 0;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess,
                   'This badge has already been awarded to this volunteer.' AS Message,
                   NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
        ELSE
            SELECT ValueName INTO v_BadgeName
            FROM   LookupValues WHERE LookupValueId = v_BadgeLkpId LIMIT 1;

            INSERT INTO UserBadges
                (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
            VALUES
                (p_UserId, v_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());

            SELECT 1 AS IsSuccess,
                   'Badge awarded successfully.' AS Message,
                   LAST_INSERT_ID() AS BadgeId,
                   v_BadgeName      AS BadgeName,
                   p_UserId         AS UserId;
        END IF;
    END IF;
END //

-- ── NOTIFICATION SPs ────────────────────────────────────────────

CREATE PROCEDURE Notification_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_OnlyUnread TINYINT(1),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT n.NotificationId, n.Title, n.Body, n.NotifType,
           n.RefId, n.RefType, n.IsRead, n.ReadAt, n.CreatedAt,
           o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl
    FROM   Notifications n
    LEFT JOIN Organisations o ON o.OrgId = n.OrgId AND o.IsDeleted = 0
    WHERE  n.UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR n.IsRead = 0)
    ORDER  BY n.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Notifications
    WHERE  UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR IsRead = 0);
END //

CREATE PROCEDURE Notification_MarkRead(IN p_NotificationId BIGINT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE Notifications SET IsRead = 1, ReadAt = NOW()
    WHERE NotificationId = p_NotificationId AND UserId = p_UserId;
    SELECT 1 AS IsSuccess, 'Marked as read.' AS Message;
END //

CREATE PROCEDURE Notification_MarkAllRead(IN p_UserId INT UNSIGNED)
BEGIN
    UPDATE Notifications SET IsRead = 1, ReadAt = NOW()
    WHERE UserId = p_UserId AND IsRead = 0;
    SELECT 1 AS IsSuccess, 'All notifications marked as read.' AS Message;
END //

CREATE PROCEDURE Notification_GetUnreadCount(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT COUNT(*) AS UnreadCount
    FROM   Notifications
    WHERE  UserId = p_UserId AND IsRead = 0;
END //

CREATE PROCEDURE Notification_Create(
    IN p_UserId    INT UNSIGNED,
    IN p_Title     VARCHAR(200),
    IN p_Body      TEXT,
    IN p_NotifType VARCHAR(50),
    IN p_RefId     INT UNSIGNED,
    IN p_RefType   VARCHAR(50),
    IN p_OrgId     INT UNSIGNED
)
BEGIN
    INSERT INTO Notifications (UserId, OrgId, Title, Body, NotifType, RefId, RefType, IsSent)
    VALUES (p_UserId, p_OrgId, p_Title, p_Body, p_NotifType, p_RefId, p_RefType, 0);

    SELECT 1 AS IsSuccess, 'Notification created.' AS Message,
           LAST_INSERT_ID() AS NotificationId;
END //

-- ── DEVICE TOKEN SPs ────────────────────────────────────────────

CREATE PROCEDURE Notification_SaveDeviceToken(
    IN p_UserId   INT UNSIGNED,
    IN p_Token    VARCHAR(512),
    IN p_Platform VARCHAR(20)
)
BEGIN
    INSERT INTO UserDeviceTokens (UserId, Token, Platform, UpdatedAt)
    VALUES (p_UserId, p_Token, p_Platform, NOW())
    ON DUPLICATE KEY UPDATE Token = p_Token, UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Token saved.' AS Message;
END //

CREATE PROCEDURE Notification_GetTokenByUserId(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT Token, Platform
    FROM   UserDeviceTokens
    WHERE  UserId = p_UserId AND Token IS NOT NULL AND Token != '';
END //

-- All APPROVED org members (excludes p_ExcludeUserId — pass 0 for none)
CREATE PROCEDURE Notification_GetTokensByOrgId(
    IN p_OrgId         INT UNSIGNED,
    IN p_ExcludeUserId INT UNSIGNED
)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
    INNER JOIN LookupValues lv  ON lv.LookupValueId = om.StatusLkpId
    INNER JOIN LookupTypes  lt  ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
      AND  om.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != ''
      AND  (p_ExcludeUserId = 0 OR dt.UserId != p_ExcludeUserId);
END //

-- FOUNDER + ADMIN members only (for new-application / new-membership admin alerts)
CREATE PROCEDURE Notification_GetAdminTokensByOrgId(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
    INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
    INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
    INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
    INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
    WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
      AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN')
      AND  om.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

-- SOS-specific recipient lookup: respects victim's EmergVisibilityLkpId (EMERGENCY_VISIBILITY lookup type)
-- ADMIN_ONLY  → FOUNDER + ADMIN roles only
-- ADMIN_MODS  → FOUNDER + ADMIN + MODERATOR roles
-- ALL_MEMBERS → all approved members  (default if no preference saved)
CREATE PROCEDURE Notification_GetSosMemberTokens(
    IN p_OrgId        INT UNSIGNED,
    IN p_VictimUserId INT UNSIGNED
)
BEGIN
    DECLARE v_VisCode VARCHAR(50) DEFAULT 'ALL_MEMBERS';

    SELECT lv.ValueCode INTO v_VisCode
    FROM   UserSafetyPreferences sp
    JOIN   LookupValues lv ON lv.LookupValueId = sp.EmergVisibilityLkpId
    WHERE  sp.UserId = p_VictimUserId LIMIT 1;

    IF v_VisCode IS NULL THEN SET v_VisCode = 'ALL_MEMBERS'; END IF;

    IF v_VisCode = 'ALL_MEMBERS' THEN
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    ELSEIF v_VisCode = 'ADMIN_MODS' THEN
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
        INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN','MODERATOR')
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    ELSE -- ADMIN_ONLY
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
        INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    END IF;
END //

-- Project applicants by status code (pass NULL for all)
CREATE PROCEDURE Notification_GetTokensByProjectId(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(20)
)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN ProjectApplications pa ON pa.UserId = dt.UserId AND pa.ProjectId = p_ProjectId
    INNER JOIN LookupValues lv ON lv.LookupValueId = pa.StatusLkpId
    INNER JOIN LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS'
      AND  (p_StatusCode IS NULL OR lv.ValueCode = p_StatusCode)
      AND  pa.IsDeleted = 0
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

-- APPROVED responders for a SOS incident (for resolve/cancel fan-out)
CREATE PROCEDURE Notification_GetTokensBySosIncidentId(IN p_SosIncidentId INT UNSIGNED)
BEGIN
    SELECT DISTINCT dt.UserId, dt.Token
    FROM   UserDeviceTokens dt
    INNER JOIN SosResponders sr ON sr.UserId = dt.UserId AND sr.SosIncidentId = p_SosIncidentId
    INNER JOIN LookupValues  lv ON lv.LookupValueId = sr.ApprovalStatusLkpId
    INNER JOIN LookupTypes   lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'APPROVED'
      AND  dt.Token IS NOT NULL AND dt.Token != '';
END //

CREATE PROCEDURE Notification_DeleteStaleToken(IN p_Token VARCHAR(512))
BEGIN
    -- Called automatically by FCMService when Firebase returns Unregistered/NotRegistered.
    -- Removes the stale token so future fan-outs don't waste FCM quota on dead registrations.
    DELETE FROM UserDeviceTokens WHERE Token = p_Token;
END //


-- ============================================================
-- v4.1 NEW STORED PROCEDURES
-- ============================================================

-- ── User_GetSafetyPrefs ──────────────────────────────────────
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

-- ── User_GetInterests ────────────────────────────────────────
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

-- ── User_GetMyOrgs ───────────────────────────────────────────
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
    JOIN LookupValues sv  ON om.StatusLkpId = sv.LookupValueId
    JOIN LookupValues rv  ON om.RoleLkpId = rv.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode = 'APPROVED'
    ORDER BY om.CreatedAt DESC;
END //

-- ── User_GetBadges ───────────────────────────────────────────
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        ub.BadgeLkpId,
        lv.ValueName AS BadgeName,
        lv.ValueCode AS BadgeCode,
        o.OrgName,
        p.ProjectName,
        ub.CreatedAt AS AwardedAt
    FROM UserBadges ub
    JOIN LookupValues lv  ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId = p.ProjectId
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC;
END //

-- ── User_GetImpact ───────────────────────────────────────────
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        up.ImpactScore,
        up.ReliabilityPct,
        (SELECT COUNT(DISTINCT pa.ProjectId) FROM ProjectAttendance pa
            WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED') AS ProjectsCompleted,
        COALESCE((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM ProjectAttendance pa
            JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
            WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'
        ), 0) AS TotalHours,
        (SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0) AS BadgeCount,
        (SELECT COUNT(*) FROM UserSkills  WHERE UserId = p_UserId AND IsDeleted = 0) AS SkillCount,
        (SELECT COUNT(*) FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0) AS ProjectsApplied,
        (SELECT COUNT(*) FROM VolunteerCertificates WHERE UserId = p_UserId) AS CertificateCount,
        u.CreatedAt AS MemberSince
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- ── Org_GetDashboard ─────────────────────────────────────────
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
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0) AS TotalMembers,

        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0
           AND YEAR(CreatedAt) = YEAR(NOW()) AND MONTH(CreatedAt) = MONTH(NOW())) AS NewMembersThisMonth,

        (SELECT COUNT(DISTINCT pa.UserId) FROM ProjectAttendance pa
         JOIN Projects p ON pa.ProjectId = p.ProjectId
         WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
           AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW())) AS ActiveVolunteers,

        ROUND(
            CASE WHEN (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0) = 0 THEN 0
                 ELSE (SELECT COUNT(DISTINCT pa.UserId) FROM ProjectAttendance pa
                       JOIN Projects p ON pa.ProjectId = p.ProjectId
                       WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
                         AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW()))
                      * 100.0
                      / (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedStatusId AND IsDeleted = 0)
            END, 1) AS ActiveRatePct,

        COALESCE((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM ProjectAttendance pa
            JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
            JOIN Projects p ON pa.ProjectId = p.ProjectId
            WHERE p.OrgId = p_OrgId AND pa.AttendanceStatus = 'ATTENDED'
              AND YEAR(pa.MarkedAt) = YEAR(NOW()) AND MONTH(pa.MarkedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveStatusId AND IsDeleted = 0) AS ActiveProjects,

        (SELECT COUNT(*) FROM OrgMembers om
         JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING') AS PendingApplications;
END //

-- ── Org_ListRecommended ──────────────────────────────────────
CREATE PROCEDURE Org_ListRecommended(IN p_UserId INT)
BEGIN
    DECLARE v_ApprovedId   INT;
    DECLARE v_OrgCatTypeId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT LookupTypeId INTO v_OrgCatTypeId
    FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1;

    SELECT
        o.OrgId, o.OrgName, o.Category,
        COALESCE(cv.ValueName, o.Category) AS CategoryName,
        o.LogoUrl, o.City, o.State,
        o.IsNonRegistered,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating, o.Latitude, o.Longitude,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        COUNT(ui.UserInterestId) AS MatchScore
    FROM Organisations o
    JOIN UserInterests ui ON ui.UserId = p_UserId
    JOIN LookupValues  lv ON ui.InterestLkpId = lv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND lv.ValueCode = o.Category
    GROUP BY o.OrgId, vv.ValueCode, cv.ValueName
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

-- ── Campaign_ListPublicTrending ───────────────────────────────
CREATE PROCEDURE Campaign_ListPublicTrending(IN p_PageSize INT)
BEGIN
    SELECT
        dc.CampaignId,
        dc.CampaignName,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        dc.RaisedAmount,
        dc.TargetAmount,
        dc.DonorCount,
        ROUND(IF(dc.TargetAmount > 0, dc.RaisedAmount / dc.TargetAmount * 100, 0), 2) AS ProgressPct,
        dc.EndDate,
        dc.BannerUrl,
        dc.IsEmergency
    FROM DonationCampaigns dc
    JOIN Organisations o ON dc.OrgId = o.OrgId
    WHERE dc.IsActive = 1 AND dc.IsDeleted = 0 AND o.IsDeleted = 0
    ORDER BY dc.IsEmergency DESC, dc.DonorCount DESC, dc.RaisedAmount DESC
    LIMIT p_PageSize;
END //

-- ── Org_GetDonationDashboard ─────────────────────────────────
CREATE PROCEDURE Org_GetDonationDashboard(IN p_OrgId INT)
BEGIN
    SELECT
        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'), 0) AS TotalRaisedAllTime,

        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND YEAR(dt.CreatedAt) = YEAR(NOW()) AND MONTH(dt.CreatedAt) = MONTH(NOW())), 0) AS ThisMonthRaised,

        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND YEAR(dt.CreatedAt)  = YEAR(DATE_SUB(NOW(), INTERVAL 1 MONTH))
                  AND MONTH(dt.CreatedAt) = MONTH(DATE_SUB(NOW(), INTERVAL 1 MONTH))), 0) AS LastMonthRaised,

        IFNULL((SELECT SUM(dt.Amount) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND DATE(dt.CreatedAt) = CURDATE()), 0) AS TodayRaised,

        IFNULL((SELECT COUNT(*) FROM DonationTransactions dt
                 JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
                  AND DATE(dt.CreatedAt) = CURDATE()), 0) AS TodayTransactionCount,

        IFNULL((SELECT SUM(rd.Amount) FROM RecurringDonations rd
                 JOIN DonationCampaigns dc ON rd.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND rd.IsActive = 1), 0) AS RecurringMonthlyAmount,

        IFNULL((SELECT COUNT(DISTINCT rd.UserId) FROM RecurringDonations rd
                 JOIN DonationCampaigns dc ON rd.CampaignId = dc.CampaignId
                WHERE dc.OrgId = p_OrgId AND rd.IsActive = 1), 0) AS ActiveRecurringDonors,

        IFNULL((SELECT COUNT(*) FROM DonationCampaigns WHERE OrgId = p_OrgId AND IsDeleted = 0), 0) AS TotalCampaigns,
        IFNULL((SELECT COUNT(*) FROM DonationCampaigns WHERE OrgId = p_OrgId AND IsDeleted = 0 AND IsActive = 1), 0) AS ActiveCampaigns;
END //

-- ── Org_GetDonors ────────────────────────────────────────────
CREATE PROCEDURE Org_GetDonors(
    IN p_OrgId      INT,
    IN p_Tab        VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        u.UserId,
        IF(dt_agg.IsAnonymous = 1, NULL, CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,''))) AS FullName,
        IF(dt_agg.IsAnonymous = 1, NULL, u.Email)    AS Email,
        IF(dt_agg.IsAnonymous = 1, NULL, u.Mobile)   AS Phone,
        dt_agg.TotalDonated,
        dt_agg.DonationCount,
        dt_agg.LastDonatedAt,
        dt_agg.IsAnonymous,
        IF(rd_agg.ActiveCount > 0, 1, 0) AS IsRecurring
    FROM (
        SELECT dt.UserId,
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
    LEFT JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
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

    SELECT COUNT(DISTINCT dt.UserId) AS TotalCount
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    WHERE dc.OrgId = p_OrgId AND dt.StatusCode = 'SUCCESS'
      AND (p_Tab != 'RECURRING' OR dt.UserId IN (
            SELECT rd.UserId FROM RecurringDonations rd
            JOIN DonationCampaigns dc2 ON rd.CampaignId = dc2.CampaignId
            WHERE dc2.OrgId = p_OrgId AND rd.IsActive = 1));
END //

-- ── Org_GetTransactions ──────────────────────────────────────
CREATE PROCEDURE Org_GetTransactions(
    IN p_OrgId      INT,
    IN p_StatusCode VARCHAR(30),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        dt.TransactionId,
        dt.ReadableId,
        IF(dt.IsAnonymous = 1, NULL, CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,''))) AS DonorName,
        dt.Amount,
        dt.NetAmount,
        dc.CampaignName,
        dt.StatusCode,
        lv.ValueName AS StatusName,
        dt.PaymentMethod,
        dt.CreatedAt,
        dt.IsAnonymous
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    LEFT JOIN LookupValues lv ON dt.StatusLkpId = lv.LookupValueId
    LEFT JOIN UserProfiles up ON up.UserId = dt.UserId AND up.IsDeleted = 0
    WHERE dc.OrgId = p_OrgId
      AND (p_StatusCode IS NULL OR dt.StatusCode = p_StatusCode)
    ORDER BY dt.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM DonationTransactions dt
    JOIN DonationCampaigns dc ON dt.CampaignId = dc.CampaignId
    WHERE dc.OrgId = p_OrgId
      AND (p_StatusCode IS NULL OR dt.StatusCode = p_StatusCode);
END //

-- ── Org_GetVolunteerProfile (admin view — includes ReliabilityPct) ──
CREATE PROCEDURE Org_GetVolunteerProfile(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.City, up.Occupation, up.ProfilePhoto,
        IFNULL((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT pa.ProjectId) FROM ProjectAttendance pa
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId) FROM ProjectAttendance pa
                JOIN Projects p ON pa.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS OrgCount,
        ROUND(IFNULL(
            (SELECT attended / total * 100 FROM (
                SELECT SUM(CASE WHEN AttendanceStatus IN ('ATTENDED','EXCUSED') THEN 1 ELSE 0 END) AS attended,
                       COUNT(*) AS total
                FROM ProjectAttendance WHERE UserId = p_UserId
            ) r WHERE total > 0), 100), 2) AS ReliabilityPct,
        IFNULL((SELECT AVG(usr.RatingValue) FROM UserSkillRatings usr
                JOIN ProjectSkills ps2 ON usr.ProjectSkillId = ps2.ProjectSkillId
                JOIN Projects p2       ON ps2.ProjectId = p2.ProjectId
                WHERE usr.RatedUserId = p_UserId AND p2.OrgId = p_OrgId), 0) AS AvgRating,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance
                WHERE UserId = p_UserId AND AttendanceStatus = 'NO_SHOW'), 0) AS NoShowCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance
                WHERE UserId = p_UserId AND AttendanceStatus = 'EXCUSED'), 0) AS ExcusedCount,
        lv_role.ValueCode   AS RoleCode,
        lv_role.ValueName   AS RoleName,
        lv_status.ValueCode AS StatusCode,
        lv_status.ValueName AS StatusName,
        om.CreatedAt        AS JoinedAt
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om          ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role   ON lv_role.LookupValueId = om.RoleLkpId
    LEFT JOIN LookupValues lv_status ON lv_status.LookupValueId = om.StatusLkpId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- ── Org_GetMemberImpact ──────────────────────────────────────
CREATE PROCEDURE Org_GetMemberImpact(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.Occupation, up.City,
        lv_role.ValueName AS RoleName,
        up.ImpactScore,
        ROUND(IFNULL(
            (SELECT attended / total * 100 FROM (
                SELECT SUM(CASE WHEN AttendanceStatus IN ('ATTENDED','EXCUSED') THEN 1 ELSE 0 END) AS attended,
                       COUNT(*) AS total
                FROM ProjectAttendance WHERE UserId = p_UserId
            ) r WHERE total > 0), 100), 2) AS ReliabilityPct,
        IFNULL((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT pa.ProjectId) FROM ProjectAttendance pa
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId) FROM ProjectAttendance pa
                JOIN Projects p ON pa.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendanceStatus = 'ATTENDED'), 0) AS OrgCount,
        IFNULL((SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0), 0) AS BadgeCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance
                WHERE UserId = p_UserId AND AttendanceStatus = 'NO_SHOW'), 0) AS NoShowCount
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om        ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role ON lv_role.LookupValueId = om.RoleLkpId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

-- ── Org_UpdateMemberRole ─────────────────────────────────────
-- Updated: accepts p_RoleCode (ValueCode string) instead of p_RoleLkpId (int)
-- SP resolves to LkpId internally — consistent with Org_AddMember pattern
CREATE PROCEDURE Org_UpdateMemberRole(
    IN p_OrgId     INT,
    IN p_MemberId  INT,
    IN p_RoleCode  VARCHAR(50),
    IN p_UpdatedBy INT
)
BEGIN
    DECLARE v_RoleLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_RoleLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = p_RoleCode
    LIMIT  1;

    IF v_RoleLkpId = 0 THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown role: ', p_RoleCode) AS Message;
    ELSE
        UPDATE OrgMembers
        SET RoleLkpId = v_RoleLkpId,
            UpdatedAt = NOW(),
            UpdatedBy = p_UpdatedBy
        WHERE OrgMemberId = p_MemberId
          AND OrgId       = p_OrgId
          AND IsDeleted   = 0;

        IF ROW_COUNT() = 0 THEN
            SELECT 0 AS IsSuccess, 'Member not found or already deleted.' AS Message, NULL AS UserId;
        ELSE
            SELECT 1 AS IsSuccess, 'Member role updated.' AS Message,
                   (SELECT UserId FROM OrgMembers WHERE OrgMemberId = p_MemberId LIMIT 1) AS UserId;
        END IF;
    END IF;
END //

-- ── Attendance_ExcuseNoShow ───────────────────────────────────
CREATE PROCEDURE Attendance_ExcuseNoShow(
    IN p_AttendanceId INT,
    IN p_ExcusedBy    INT
)
BEGIN
    DECLARE v_UserId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectId INT UNSIGNED DEFAULT NULL;

    SELECT pa.UserId, ps.ProjectId
    INTO   v_UserId, v_ProjectId
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.AttendanceId = p_AttendanceId
    LIMIT  1;

    UPDATE ProjectAttendance pa
    SET pa.AttendanceStatus = 'EXCUSED',
        pa.IsNoShowExcused  = 1,
        pa.UpdatedAt        = NOW()
    WHERE pa.AttendanceId      = p_AttendanceId
      AND pa.AttendanceStatus  = 'NO_SHOW';

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or already not a no-show.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show excused. Reliability score will not be affected.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //

DELIMITER ;

-- ── Attendance_ConfirmNoShow ─────────────────────────────────────
DELIMITER //
DROP PROCEDURE IF EXISTS Attendance_ConfirmNoShow //
CREATE PROCEDURE Attendance_ConfirmNoShow(
    IN p_AttendanceId INT,
    IN p_ConfirmedBy  INT
)
BEGIN
    DECLARE v_UserId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectId INT UNSIGNED DEFAULT NULL;

    SELECT pa.UserId, ps.ProjectId
    INTO   v_UserId, v_ProjectId
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE  pa.AttendanceId     = p_AttendanceId
    LIMIT  1;

    UPDATE ProjectAttendance pa
    SET pa.NoShowReason = 'ADMIN_CONFIRMED',
        pa.UpdatedAt   = NOW()
    WHERE pa.AttendanceId     = p_AttendanceId
      AND pa.AttendanceStatus = 'NO_SHOW'
      AND pa.IsNoShowExcused  = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or already excused/confirmed.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show confirmed. Reliability score will be affected.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //
DELIMITER ;

-- ── SCHEMA VERSION SEED ─────────────────────────────────────────
INSERT INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v4.1', 'v4.1 complete setup: 47 tables, 45 LookupTypes (added INTEREST_TYPE), 113 stored procedures. Added VolunteerExp to UserProfiles, EmergencyContact cols to UserSafetyPreferences, InterestLkpId FK on UserInterests, ContactPerson/AvgRating/RatingCount/Latitude/Longitude to Organisations. 10 SPs updated, 15 new SPs added.', 'System');

COMMIT;

-- ════════════════════════════════════════════════════════════════
-- v4.2 UPGRADE BLOCK
-- Date: 2026-07-04
-- Changes:
--   Tables:  +3 (CommunityPostLikes, CommunityPostComments, CommunityCommentLikes)
--   Altered: CommunityPosts (+LikeCount, +CommentCount, +AcknowledgeCount)
--            SosIncidents (fix: UserId not VictimUserId, +IsDeleted, +CancelledAt)
--   SPs:     +5 new, 4 replaced (Community_GetFeed, _CreatePost, _CreatePoll, _Vote)
-- ════════════════════════════════════════════════════════════════

-- ── NOTE: CommunityPosts columns (LikeCount, CommentCount, AcknowledgeCount) ─
-- Already included in CREATE TABLE above. No ALTER needed.

-- ── NOTE: SosIncidents columns (IsDeleted, CancelledAt) ──────────────────────
-- Already included in CREATE TABLE above. No ALTER needed.

-- ── NEW TABLE: CommunityPostLikes ────────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityPostLikes (
    CommunityPostLikeId INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    CommunityPostId     INT UNSIGNED      NOT NULL,
    UserId              INT UNSIGNED      NOT NULL,
    CreatedAt           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityPostLikeId),
    UNIQUE KEY uq_cpl_post_user (CommunityPostId, UserId),
    KEY idx_cpl_post (CommunityPostId),
    KEY idx_cpl_user (UserId),
    CONSTRAINT fk_cpl_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId) ON DELETE CASCADE,
    CONSTRAINT fk_cpl_user FOREIGN KEY (UserId) REFERENCES Users(UserId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── NEW TABLE: CommunityPostComments ────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityPostComments (
    CommunityCommentId INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    CommunityPostId    INT UNSIGNED      NOT NULL,
    UserId             INT UNSIGNED      NOT NULL,
    Content            TEXT              NOT NULL,
    LikeCount          INT UNSIGNED      NOT NULL DEFAULT 0,
    IsDeleted          TINYINT(1)        NOT NULL DEFAULT 0,
    CreatedAt          DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt          DATETIME          NULL     ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityCommentId),
    KEY idx_cpc_post (CommunityPostId),
    KEY idx_cpc_user (UserId),
    CONSTRAINT fk_cpc_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId) ON DELETE CASCADE,
    CONSTRAINT fk_cpc_user FOREIGN KEY (UserId) REFERENCES Users(UserId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── NEW TABLE: CommunityCommentLikes ────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityCommentLikes (
    CommunityCommentLikeId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    CommunityCommentId     INT UNSIGNED  NOT NULL,
    UserId                 INT UNSIGNED  NOT NULL,
    CreatedAt              DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityCommentLikeId),
    UNIQUE KEY uq_ccl_comment_user (CommunityCommentId, UserId),
    KEY idx_ccl_comment (CommunityCommentId),
    KEY idx_ccl_user    (UserId),
    CONSTRAINT fk_ccl_comment FOREIGN KEY (CommunityCommentId) REFERENCES CommunityPostComments(CommunityCommentId) ON DELETE CASCADE,
    CONSTRAINT fk_ccl_user    FOREIGN KEY (UserId) REFERENCES Users(UserId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER //

-- ── REPLACED SP: Community_GetFeed ──────────────────────────────
-- v4.2: Added p_UserId to compute IsLiked/IsLikedByMe per viewer.
--        Added LikeCount, CommentCount, AcknowledgeCount, IsAcknowledged.
DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId,
        cp.OrgId,
        cp.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS AuthorName,
        up.ProfilePhoto,
        lv_role.ValueName AS RoleName,
        cp.Title,
        cp.Content,
        lv_type.ValueCode  AS PostType,
        lv_type.ValueCode  AS PostTypeLkpCode,
        lv_type.ValueName  AS PostTypeName,
        lv_aud.ValueCode   AS AudienceCode,
        cp.LikeCount,
        cp.CommentCount,
        cp.AcknowledgeCount,
        CASE WHEN cpl.CommunityPostLikeId IS NOT NULL THEN 1 ELSE 0 END AS IsLiked,
        CASE WHEN cpl.CommunityPostLikeId IS NOT NULL THEN 1 ELSE 0 END AS IsLikedByMe,
        CASE WHEN ack.AcknowledgeId IS NOT NULL THEN 1 ELSE 0 END       AS IsAcknowledged,
        CASE WHEN ack.AcknowledgeId IS NOT NULL THEN 1 ELSE 0 END       AS IsAcknowledgedByMe,
        cp.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR, cp.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR, cp.CreatedAt, NOW()), 'h ago')
            ELSE CONCAT(TIMESTAMPDIFF(DAY, cp.CreatedAt, NOW()), 'd ago')
        END AS TimeAgo
    FROM CommunityPosts cp
    JOIN UserProfiles up ON up.UserId = cp.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om      ON om.OrgId = cp.OrgId AND om.UserId = cp.UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role ON lv_role.LookupValueId = om.RoleLkpId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = cp.PostTypeLkpId
    LEFT JOIN LookupValues lv_aud  ON lv_aud.LookupValueId  = cp.AudienceLkpId
    LEFT JOIN CommunityPostLikes cpl
           ON cpl.CommunityPostId = cp.CommunityPostId AND cpl.UserId = p_UserId
    LEFT JOIN CommunityPostAcknowledgements ack
           ON ack.CommunityPostId = cp.CommunityPostId AND ack.UserId = p_UserId
    WHERE cp.IsDeleted = 0
      AND (p_OrgId IS NULL OR cp.OrgId = p_OrgId)
    ORDER BY cp.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM CommunityPosts cp
    WHERE cp.IsDeleted = 0
      AND (p_OrgId IS NULL OR cp.OrgId = p_OrgId);
END //

-- ── REPLACED SP: Community_CreatePost ───────────────────────────
-- v4.3: Fixed audience TypeCode POST_VISIBILITY → AUDIENCE_TYPE; added CreatedBy.
-- Updated: enforces CanCommunityPost from OrgMembers (Permission Enforcement patch)
-- v4.8: Added p_ResourceFileUrl for RESOURCE post type file uploads
-- v4.8: Added p_IsPinned (ANNOUNCEMENT), p_VolunteersNeeded (VOL_REQUEST),
--        p_EventRef (multipurpose: whatChanged for EVENT_UPDATE, dateTime text for
--        VOL_REQUEST, assignee name for TASK) → stored in EventRef column
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId           INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_Title            VARCHAR(300),
    IN p_Content          TEXT,
    IN p_PostTypeLkpId    INT UNSIGNED,
    IN p_AudienceLkpId    INT UNSIGNED,
    IN p_ResourceFileUrl  VARCHAR(500),
    IN p_IsPinned         TINYINT(1),
    IN p_VolunteersNeeded INT UNSIGNED,
    IN p_EventRef         VARCHAR(200)
)
BEGIN
    DECLARE v_ApprovedLkpId        INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost     TINYINT(1)  DEFAULT 0;
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT om.CanCommunityPost INTO v_CanCommunityPost
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanCommunityPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to post in this community.' AS Message,
               NULL AS CommunityPostId;
    ELSE
        IF p_AudienceLkpId IS NULL OR p_AudienceLkpId = 0 THEN
            SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
            FROM   LookupValues lv
            JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS'
            LIMIT  1;
            SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
        END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId,
             IsPinned, VolunteersNeeded, EventRef, ResourceFileUrl, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId,
             COALESCE(p_IsPinned, 0), p_VolunteersNeeded, p_EventRef, p_ResourceFileUrl, p_UserId);

        SELECT 1                    AS IsSuccess,
               'Post created.'      AS Message,
               LAST_INSERT_ID()     AS CommunityPostId,
               (SELECT lv.ValueCode FROM LookupValues lv
                WHERE lv.LookupValueId = p_AudienceLkpId LIMIT 1) AS AudienceCode;
    END IF;
END //

-- ── REPLACED SP: Community_CreatePoll ───────────────────────────
-- v4.3: Fixed TypeCode COMMUNITY_POST_TYPE → POST_TYPE_COMMUNITY; AUDIENCE_TYPE fix;
--       added p_IsMultiChoice; JSON_TABLE for options; PollIsMultiChoice in INSERT.
-- Updated: enforces CanCommunityPost from OrgMembers (Permission Enforcement patch)
-- v5.1: Added p_AudienceLkpId — polls now respect ADMINS_ONLY / VOLUNTEERS audience.
--       Returns AudienceCode so DAL can scope notification fan-out correctly.
DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT,
    IN p_IsMultiChoice  TINYINT(1),
    IN p_AudienceLkpId  INT UNSIGNED   -- NULL/0 = default to ALL_MEMBERS
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceCode     VARCHAR(50)  DEFAULT 'ALL_MEMBERS';

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT om.CanCommunityPost INTO v_CanCommunityPost
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanCommunityPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to create polls in this community.' AS Message,
               NULL AS PollId,
               NULL AS AudienceCode;
    ELSE
        SELECT lv.LookupValueId INTO v_PollTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

        -- Use caller-supplied audience if it resolves to a valid AUDIENCE_TYPE entry;
        -- otherwise fall back to ALL_MEMBERS.
        IF p_AudienceLkpId IS NOT NULL AND p_AudienceLkpId > 0 THEN
            SELECT lv.LookupValueId, lv.ValueCode
            INTO   v_AudienceLkpId, v_AudienceCode
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.LookupValueId = p_AudienceLkpId LIMIT 1;
        END IF;

        -- If nothing was resolved (NULL/0 input OR supplied ID not found), default to ALL_MEMBERS
        IF v_AudienceLkpId = 0 THEN
            SELECT lv.LookupValueId, lv.ValueCode
            INTO   v_AudienceLkpId, v_AudienceCode
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;
        END IF;

        IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
        IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, PollIsMultiChoice, CreatedBy)
        VALUES (
            p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
            v_AudienceLkpId,
            CASE WHEN p_ExpiresInHours > 0
                 THEN DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR)
                 ELSE NULL END,
            COALESCE(p_IsMultiChoice, 0),
            p_UserId
        );

        SET @PollId = LAST_INSERT_ID();

        INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
        SELECT @PollId, jt.opt, jt.rn
        FROM JSON_TABLE(p_OptionsJson, '$[*]' COLUMNS (
            rn   FOR ORDINALITY,
            opt  VARCHAR(200) PATH '$'
        )) AS jt
        WHERE TRIM(jt.opt) != '';

        SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId, v_AudienceCode AS AudienceCode;
    END IF;
END //

-- ── REPLACED SP: Community_Vote ─────────────────────────────────
-- v4.2: Fixed from 2-param to 3-param; checks expiry + duplicate.
DROP PROCEDURE IF EXISTS Community_Vote //
CREATE PROCEDURE Community_Vote(
    IN p_PollId        INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_PollOptionId  INT UNSIGNED
)
BEGIN
    DECLARE v_ExpiredAt DATETIME DEFAULT NULL;
    DECLARE v_AlreadyVoted INT DEFAULT 0;

    SELECT PollEndsAt INTO v_ExpiredAt
    FROM PollOptions WHERE PollOptionId = p_PollOptionId LIMIT 1;

    IF v_ExpiredAt IS NOT NULL AND v_ExpiredAt < NOW() THEN
        SELECT 0 AS IsSuccess, 'This poll has expired.' AS Message;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyVoted
        FROM PollVotes
        WHERE UserId = p_UserId
          AND PollOptionId IN (SELECT PollOptionId FROM PollOptions WHERE CommunityPostId = p_PollId);

        IF v_AlreadyVoted > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already voted on this poll.' AS Message;
        ELSE
            INSERT INTO PollVotes (PollOptionId, UserId, VotedAt) VALUES (p_PollOptionId, p_UserId, NOW());
            UPDATE PollOptions SET VoteCount = VoteCount + 1 WHERE PollOptionId = p_PollOptionId;
            SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
        END IF;
    END IF;
END //

-- ── NEW SP: Community_LikePost ───────────────────────────────────
-- Updated: returns PostAuthorUserId + ActorName for notification dispatch
CREATE PROCEDURE Community_LikePost(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists
    FROM CommunityPostLikes
    WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        DELETE FROM CommunityPostLikes
        WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;
        UPDATE CommunityPosts
        SET LikeCount = GREATEST(0, LikeCount - 1)
        WHERE CommunityPostId = p_CommunityPostId;
    ELSE
        INSERT INTO CommunityPostLikes (CommunityPostId, UserId, CreatedAt)
        VALUES (p_CommunityPostId, p_UserId, NOW());
        UPDATE CommunityPosts
        SET LikeCount = LikeCount + 1
        WHERE CommunityPostId = p_CommunityPostId;
    END IF;

    SELECT
        CASE WHEN v_Exists > 0 THEN 0 ELSE 1 END AS IsLiked,
        cp.LikeCount,
        cp.UserId AS PostAuthorUserId,
        CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM CommunityPosts cp
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE cp.CommunityPostId = p_CommunityPostId;
END //

-- ── NEW SP: Community_AddComment ─────────────────────────────────
-- Updated: returns PostAuthorUserId + ActorName for notification dispatch
CREATE PROCEDURE Community_AddComment(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT
)
BEGIN
    INSERT INTO CommunityPostComments (CommunityPostId, UserId, Content, CreatedAt)
    VALUES (p_CommunityPostId, p_UserId, p_Content, NOW());

    UPDATE CommunityPosts
    SET CommentCount = CommentCount + 1
    WHERE CommunityPostId = p_CommunityPostId;

    SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommunityCommentId,
           cp.UserId AS PostAuthorUserId,
           CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM   CommunityPosts cp
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE  cp.CommunityPostId = p_CommunityPostId
    LIMIT  1;
END //

-- ── NEW SP: Community_GetComments ────────────────────────────────
CREATE PROCEDURE Community_GetComments(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED
)
BEGIN
    SELECT
        c.CommunityCommentId,
        c.CommunityPostId,
        c.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS AuthorName,
        up.ProfilePhoto,
        c.Content,
        c.LikeCount,
        CASE WHEN cl.CommunityCommentLikeId IS NOT NULL THEN 1 ELSE 0 END AS IsLiked,
        CASE WHEN cl.CommunityCommentLikeId IS NOT NULL THEN 1 ELSE 0 END AS IsLikedByMe,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, c.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, c.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR, c.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR, c.CreatedAt, NOW()), 'h ago')
            ELSE CONCAT(TIMESTAMPDIFF(DAY, c.CreatedAt, NOW()), 'd ago')
        END AS TimeAgo,
        c.CreatedAt
    FROM CommunityPostComments c
    JOIN UserProfiles up ON up.UserId = c.UserId AND up.IsDeleted = 0
    LEFT JOIN CommunityCommentLikes cl
           ON cl.CommunityCommentId = c.CommunityCommentId AND cl.UserId = p_UserId
    WHERE c.CommunityPostId = p_CommunityPostId
      AND c.IsDeleted = 0
    ORDER BY c.CreatedAt ASC;
END //

-- ── NEW SP: Community_LikeComment ────────────────────────────────
CREATE PROCEDURE Community_LikeComment(
    IN p_CommunityCommentId INT UNSIGNED,
    IN p_UserId             INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists
    FROM CommunityCommentLikes
    WHERE CommunityCommentId = p_CommunityCommentId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        DELETE FROM CommunityCommentLikes
        WHERE CommunityCommentId = p_CommunityCommentId AND UserId = p_UserId;
        UPDATE CommunityPostComments
        SET LikeCount = GREATEST(0, LikeCount - 1)
        WHERE CommunityCommentId = p_CommunityCommentId;
    ELSE
        INSERT INTO CommunityCommentLikes (CommunityCommentId, UserId, CreatedAt)
        VALUES (p_CommunityCommentId, p_UserId, NOW());
        UPDATE CommunityPostComments
        SET LikeCount = LikeCount + 1
        WHERE CommunityCommentId = p_CommunityCommentId;
    END IF;

    SELECT
        CASE WHEN v_Exists > 0 THEN 0 ELSE 1 END AS IsLiked,
        LikeCount
    FROM CommunityPostComments WHERE CommunityCommentId = p_CommunityCommentId;
END //

-- ── NEW SP: Sos_GetMyActive ──────────────────────────────────────
DROP PROCEDURE IF EXISTS Sos_GetMyActive //
CREATE PROCEDURE Sos_GetMyActive(
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_ActiveLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE'
    LIMIT 1;

    -- Result set 1: victim's own active incident
    SELECT
        si.SosIncidentId,
        si.OrgId,
        o.OrgName,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CreatedAt,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName
    FROM SosIncidents si
    LEFT JOIN Organisations o   ON si.OrgId          = o.OrgId
    LEFT JOIN LookupValues atv  ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT JOIN LookupValues sv   ON si.StatusLkpId    = sv.LookupValueId
    WHERE si.UserId      = p_UserId
      AND si.StatusLkpId = v_ActiveLkpId
      AND si.IsDeleted   = 0
    ORDER BY si.CreatedAt DESC
    LIMIT 1;

    -- Result set 2: responders for that incident
    SELECT
        sr.SosResponderId,
        sr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS ResponderName,
        up.ProfilePhoto,
        rv.ValueCode  AS ApprovalStatus,
        rv.ValueName  AS ApprovalStatusName,
        sr.RespondedAt,
        sr.CanViewLocation
    FROM SosResponders sr
    JOIN SosIncidents si2 ON sr.SosIncidentId = si2.SosIncidentId
    JOIN UserProfiles up  ON sr.UserId        = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE si2.UserId      = p_UserId
      AND si2.StatusLkpId = v_ActiveLkpId
      AND si2.IsDeleted   = 0;
END //

DELIMITER ;

-- ── v4.2 SchemaVersions entry ────────────────────────────────────
INSERT INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v4.2', 'v4.2 upgrade: +3 tables (CommunityPostLikes, CommunityPostComments, CommunityCommentLikes), +3 columns on CommunityPosts (LikeCount, CommentCount, AcknowledgeCount), +2 columns on SosIncidents (IsDeleted, CancelledAt), +5 new SPs (Community_LikePost, _AddComment, _GetComments, _LikeComment, Sos_GetMyActive), 4 SPs replaced (Community_GetFeed, _CreatePost, _CreatePoll, _Vote). Total: 50 tables, 118 SPs.', 'System');

COMMIT;


-- ============================================================
-- v4.3 CHANGES (applied on top of v4.2)
-- Effective: 2026-07-06
-- Summary: Project SPs rebuilt to match DAL params; Project_List
--   adds ScheduleType, LocationName, Address columns; Community_GetFeed
--   adds PollOptionsJson/RoleName/TimeAgo; Sos_GetById made robust;
--   new SPs Sos_GetOrgAlerts + Sos_DeclineResponder; ORG_TYPE seed.
-- ============================================================

DELIMITER //

-- ── Project_Create: rebuilt to match C# DAL params ──────────
DROP PROCEDURE IF EXISTS Project_Create //
CREATE PROCEDURE Project_Create(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgId             INT UNSIGNED,
    IN p_Title             VARCHAR(200),
    IN p_Description       TEXT,
    IN p_Category          VARCHAR(100),
    IN p_ProjectTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId     INT UNSIGNED,
    IN p_StatusLkpId       INT UNSIGNED,
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_MinAge            INT UNSIGNED,
    IN p_MaxAge            INT UNSIGNED,
    IN p_IsPublic          TINYINT(1),
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_ScheduleType      VARCHAR(20),
    IN p_RecurrenceDays    VARCHAR(100),
    IN p_StartTime         VARCHAR(10),
    IN p_EndTime           VARCHAR(10),
    IN p_DurationMinutes   INT UNSIGNED,
    IN p_LocationTypeLkpId INT UNSIGNED,
    IN p_LocationTypeCode  VARCHAR(20),
    IN p_LocationName      VARCHAR(200),
    IN p_Address           VARCHAR(500),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_GenderRestriction VARCHAR(20),
    IN p_RequiresApproval  TINYINT(1),
    IN p_CoverImageUrl     VARCHAR(255),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_IsDraft           TINYINT(1),
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_ProjectTypeLkpId   INT UNSIGNED    DEFAULT NULL;
    DECLARE v_LocationTypeLkpId  INT UNSIGNED    DEFAULT NULL;
    DECLARE v_JoinTypeLkpId      INT UNSIGNED    DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED    DEFAULT NULL;

    -- Settings-based validation variables
    DECLARE v_Error              VARCHAR(500)    DEFAULT NULL;
    DECLARE v_OtMaxHours         INT             DEFAULT 12;
    DECLARE v_RecurMaxDays       INT             DEFAULT 90;
    DECLARE v_RecurMinDays       INT             DEFAULT 7;
    DECLARE v_FlexMaxDays        INT             DEFAULT 60;
    DECLARE v_FlexMinDays        INT             DEFAULT 3;
    DECLARE v_FlexMaxDailyHrs    DECIMAL(4,2)    DEFAULT 8;
    DECLARE v_FlexMinSessHrs     DECIMAL(4,2)    DEFAULT 1;
    DECLARE v_FlexMinAttendPct   DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_RecurMinAttendPct  DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_SessionDurHours    DECIMAL(6,2)    DEFAULT NULL;
    DECLARE v_SpanDays           INT             DEFAULT NULL;

    -- Load settings (fall back to declared defaults if setting row missing)
    SELECT CAST(SettingValue AS SIGNED)          INTO v_OtMaxHours        FROM Settings WHERE SettingKey = 'OT_MAX_DURATION_HOURS'       AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMaxDays       FROM Settings WHERE SettingKey = 'RECURRING_MAX_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMinDays       FROM Settings WHERE SettingKey = 'RECURRING_MIN_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMaxDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMinDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMaxDailyHrs    FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DAILY_HOURS'     AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMinSessHrs     FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_SESSION_HOURS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_FlexMinAttendPct   FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_ATTEND_PCT'      AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_RecurMinAttendPct  FROM Settings WHERE SettingKey = 'RECURRING_MIN_ATTEND_PCT'     AND IsDeleted = 0 LIMIT 1;

    -- ── Validation ────────────────────────────────────────────────────────────
    -- ONE_TIME: session duration must not exceed OT_MAX_DURATION_HOURS
    IF v_Error IS NULL AND p_ScheduleType = 'ONE_TIME'
       AND p_StartTime IS NOT NULL AND p_EndTime IS NOT NULL THEN
        SET v_SessionDurHours = (
            TIME_TO_SEC(CAST(p_EndTime AS TIME)) - TIME_TO_SEC(CAST(p_StartTime AS TIME))
        ) / 3600.0;
        IF v_SessionDurHours <= 0 THEN
            SET v_Error = 'Session end time must be after start time.';
        ELSEIF v_SessionDurHours > v_OtMaxHours THEN
            SET v_Error = CONCAT('Session duration cannot exceed ', v_OtMaxHours,
                                 ' hours for a ONE_TIME project. Please adjust start and end times.');
        END IF;
    END IF;

    -- RECURRING: date span must be within RECURRING_MIN/MAX_DURATION_DAYS
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_RecurMinDays THEN
            SET v_Error = CONCAT('RECURRING projects must span at least ', v_RecurMinDays, ' days.');
        ELSEIF v_SpanDays > v_RecurMaxDays THEN
            SET v_Error = CONCAT('RECURRING projects cannot span more than ', v_RecurMaxDays, ' days.');
        END IF;
    END IF;

    -- FLEXIBLE: date span must be within FLEXIBLE_MIN/MAX_DURATION_DAYS
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_FlexMinDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects must span at least ', v_FlexMinDays, ' days.');
        ELSEIF v_SpanDays > v_FlexMaxDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects cannot span more than ', v_FlexMaxDays, ' days.');
        END IF;
    END IF;

    -- FLEXIBLE: MaxDailyHours must be >= system floor (project can override upward only)
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MaxDailyHours IS NOT NULL THEN
        IF p_MaxDailyHours < v_FlexMaxDailyHrs THEN
            SET v_Error = CONCAT('Max daily hours cannot be less than the platform minimum of ',
                                 v_FlexMaxDailyHrs, ' hours.');
        END IF;
    END IF;

    -- FLEXIBLE: MinSessionHours must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinSessionHours IS NOT NULL THEN
        IF p_MinSessionHours < v_FlexMinSessHrs THEN
            SET v_Error = CONCAT('Minimum session hours cannot be less than the platform minimum of ',
                                 v_FlexMinSessHrs, ' hour(s).');
        END IF;
    END IF;

    -- FLEXIBLE: MinAttendPct must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_FlexMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_FlexMinAttendPct, '% for FLEXIBLE projects.');
        END IF;
    END IF;

    -- RECURRING: MinAttendPct must be >= system floor
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_RecurMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_RecurMinAttendPct, '% for RECURRING projects.');
        END IF;
    END IF;

    -- ORG PERMISSION: RECURRING projects require Super Admin grant
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' THEN
        IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND CanCreateRecurring = 1 AND IsDeleted = 0) THEN
            SET v_Error = 'Your organisation does not have permission to create RECURRING projects. Please contact support to upgrade your plan.';
        END IF;
    END IF;

    -- ORG PERMISSION: FLEXIBLE projects require Super Admin grant
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' THEN
        IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND CanCreateFlexible = 1 AND IsDeleted = 0) THEN
            SET v_Error = 'Your organisation does not have permission to create FLEXIBLE projects. Please contact support to upgrade your plan.';
        END IF;
    END IF;

    -- ORG CAP: MaxVolunteers cannot exceed org-level limit set by Super Admin
    IF v_Error IS NULL AND p_MaxVolunteers IS NOT NULL THEN
        IF p_MaxVolunteers > (SELECT OrgMaxVolunteers FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1) THEN
            SET v_Error = CONCAT('Max volunteers cannot exceed your organisation''s limit. Please contact support to increase the limit.');
        END IF;
    END IF;

    -- Return validation error if any check failed
    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS ProjectId;

    -- Duplicate check 1: same org + same title (case-insensitive, trimmed)
    ELSEIF EXISTS (
        SELECT 1 FROM Projects
        WHERE OrgId                    = p_OrgId
          AND LOWER(TRIM(ProjectName)) = LOWER(TRIM(p_Title))
          AND IsDeleted                = 0
    ) THEN
        SELECT 0    AS IsSuccess,
               'A project with this title already exists in your organisation. Please use a different name.' AS Message,
               NULL AS ProjectId;

    -- Duplicate check 2: same org + same category + same date range + same session times
    ELSEIF p_Category IS NOT NULL AND p_StartDate IS NOT NULL
        AND p_StartTime IS NOT NULL   AND p_EndTime IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM Projects
            WHERE OrgId                   = p_OrgId
              AND IsDeleted               = 0
              AND LOWER(TRIM(Category))   = LOWER(TRIM(p_Category))
              AND SessionStartTime        = p_StartTime
              AND SessionEndTime          = p_EndTime
              AND (
                  (p_ScheduleType = 'ONE_TIME'
                        AND OneTimeDate  = p_StartDate)
               OR (p_ScheduleType = 'RECURRING'
                        AND RecurStart  = p_StartDate
                        AND RecurEnd    = p_EndDate)
               OR (p_ScheduleType = 'FLEXIBLE'
                        AND FlexFromDate = p_StartDate
                        AND FlexToDate   = p_EndDate)
              )
        )
    THEN
        SELECT 0    AS IsSuccess,
               'A project in this category is already scheduled for the same date and time. Please choose a different schedule.' AS Message,
               NULL AS ProjectId;

    ELSE

        -- Resolve ProjectTypeLkpId from ScheduleType string if not supplied directly
        IF p_ProjectTypeLkpId IS NOT NULL THEN
            SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
        ELSE
            SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = COALESCE(p_ScheduleType, 'ONE_TIME')
            LIMIT 1;
        END IF;

        -- Resolve LocationTypeLkpId
        IF p_LocationTypeLkpId IS NOT NULL THEN
            SET v_LocationTypeLkpId = p_LocationTypeLkpId;
        ELSEIF p_LocationTypeCode IS NOT NULL THEN
            SELECT lv.LookupValueId INTO v_LocationTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode
            LIMIT 1;
        END IF;
        IF v_LocationTypeLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_LocationTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = 'IN_PERSON'
            LIMIT 1;
        END IF;

        -- Resolve JoinTypeLkpId
        IF p_JoinTypeLkpId IS NOT NULL THEN
            SET v_JoinTypeLkpId = p_JoinTypeLkpId;
        ELSE
            SELECT lv.LookupValueId INTO v_JoinTypeLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
              AND lv.ValueCode = IF(COALESCE(p_RequiresApproval, 0) = 1, 'APPROVE_REQ', 'OPEN_SIGNUP')
            LIMIT 1;
        END IF;

        -- Resolve StatusLkpId
        IF p_StatusLkpId IS NOT NULL THEN
            SET v_StatusLkpId = p_StatusLkpId;
        ELSEIF COALESCE(p_IsDraft, 0) = 1 THEN
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'DRAFT' LIMIT 1;
        ELSE
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;
        END IF;

        INSERT INTO Projects (
            OrgId, ProjectName, Category, Description,
            ProjectTypeLkpId,
            OneTimeDate, RecurStart, RecurEnd, RecurDays,
            FlexFromDate, FlexToDate,
            MinHoursRequired,
            SessionStartTime, SessionEndTime,
            LocationTypeLkpId, AddressLine, Landmark, City, State,
            Latitude, Longitude, GoogleMapsUrl,
            MaxVolunteers, JoinTypeLkpId, IsPublic,
            AgeRestriction, IdVerRequired, MinReliability,
            StatusLkpId, MinAttendPct, MaxDailyHours, MinSessionHours, CreatedBy
        ) VALUES (
            p_OrgId,
            p_Title,
            p_Category,
            p_Description,
            v_ProjectTypeLkpId,
            IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, NULL),
            IF(p_ScheduleType = 'RECURRING', p_StartDate, NULL),
            IF(p_ScheduleType = 'RECURRING', p_EndDate,   NULL),
            IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, NULL),
            IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, NULL),
            IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   NULL),
            IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL),
            p_StartTime, p_EndTime,
            v_LocationTypeLkpId,
            p_Address,
            p_LocationName,
            p_City, p_State,
            p_Latitude, p_Longitude, p_GoogleMapsUrl,
            p_MaxVolunteers,
            v_JoinTypeLkpId,
            COALESCE(p_IsPublic, 1),
            IF(COALESCE(p_MinAge, 0) >= 18, 1, 0),
            0,
            0.00,
            v_StatusLkpId,
            p_MinAttendPct, p_MaxDailyHours, p_MinSessionHours,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;

    END IF;
END //

-- ── Project_Update: rebuilt to match C# DAL params ──────────
DROP PROCEDURE IF EXISTS Project_Update //
CREATE PROCEDURE Project_Update(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Title             VARCHAR(200),
    IN p_Description       TEXT,
    IN p_Category          VARCHAR(100),
    IN p_ProjectTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId     INT UNSIGNED,
    IN p_StatusLkpId       INT UNSIGNED,
    IN p_MaxVolunteers     INT UNSIGNED,
    IN p_MinAge            INT UNSIGNED,
    IN p_MaxAge            INT UNSIGNED,
    IN p_IsPublic          TINYINT(1),
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_ScheduleType      VARCHAR(20),
    IN p_RecurrenceDays    VARCHAR(100),
    IN p_StartTime         VARCHAR(10),
    IN p_EndTime           VARCHAR(10),
    IN p_DurationMinutes   INT UNSIGNED,
    IN p_LocationTypeLkpId INT UNSIGNED,
    IN p_LocationTypeCode  VARCHAR(20),
    IN p_LocationName      VARCHAR(200),
    IN p_Address           VARCHAR(500),
    IN p_Latitude          DECIMAL(10,7),
    IN p_Longitude         DECIMAL(10,7),
    IN p_GoogleMapsUrl     VARCHAR(500),
    IN p_GenderRestriction VARCHAR(20),
    IN p_RequiresApproval  TINYINT(1),
    IN p_CoverImageUrl     VARCHAR(255),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_IsDraft           TINYINT(1),
    IN p_MinAttendPct      DECIMAL(5,2),
    IN p_MaxDailyHours     DECIMAL(4,2),
    IN p_MinSessionHours   DECIMAL(4,2)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId  INT UNSIGNED    DEFAULT NULL;
    DECLARE v_JoinTypeLkpId      INT UNSIGNED    DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED    DEFAULT NULL;

    -- Settings-based validation variables
    DECLARE v_Error              VARCHAR(500)    DEFAULT NULL;
    DECLARE v_OtMaxHours         INT             DEFAULT 12;
    DECLARE v_RecurMaxDays       INT             DEFAULT 90;
    DECLARE v_RecurMinDays       INT             DEFAULT 7;
    DECLARE v_FlexMaxDays        INT             DEFAULT 60;
    DECLARE v_FlexMinDays        INT             DEFAULT 3;
    DECLARE v_FlexMaxDailyHrs    DECIMAL(4,2)    DEFAULT 8;
    DECLARE v_FlexMinSessHrs     DECIMAL(4,2)    DEFAULT 1;
    DECLARE v_FlexMinAttendPct   DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_RecurMinAttendPct  DECIMAL(5,2)    DEFAULT 70;
    DECLARE v_SessionDurHours    DECIMAL(6,2)    DEFAULT NULL;
    DECLARE v_SpanDays           INT             DEFAULT NULL;

    -- Load settings
    SELECT CAST(SettingValue AS SIGNED)          INTO v_OtMaxHours        FROM Settings WHERE SettingKey = 'OT_MAX_DURATION_HOURS'       AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMaxDays       FROM Settings WHERE SettingKey = 'RECURRING_MAX_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_RecurMinDays       FROM Settings WHERE SettingKey = 'RECURRING_MIN_DURATION_DAYS'  AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMaxDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS SIGNED)          INTO v_FlexMinDays        FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_DURATION_DAYS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMaxDailyHrs    FROM Settings WHERE SettingKey = 'FLEXIBLE_MAX_DAILY_HOURS'     AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(4,2))    INTO v_FlexMinSessHrs     FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_SESSION_HOURS'   AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_FlexMinAttendPct   FROM Settings WHERE SettingKey = 'FLEXIBLE_MIN_ATTEND_PCT'      AND IsDeleted = 0 LIMIT 1;
    SELECT CAST(SettingValue AS DECIMAL(5,2))    INTO v_RecurMinAttendPct  FROM Settings WHERE SettingKey = 'RECURRING_MIN_ATTEND_PCT'     AND IsDeleted = 0 LIMIT 1;

    -- ── Validation (only when relevant fields are being changed) ──────────────
    IF v_Error IS NULL AND p_ScheduleType = 'ONE_TIME'
       AND p_StartTime IS NOT NULL AND p_EndTime IS NOT NULL THEN
        SET v_SessionDurHours = (
            TIME_TO_SEC(CAST(p_EndTime AS TIME)) - TIME_TO_SEC(CAST(p_StartTime AS TIME))
        ) / 3600.0;
        IF v_SessionDurHours <= 0 THEN
            SET v_Error = 'Session end time must be after start time.';
        ELSEIF v_SessionDurHours > v_OtMaxHours THEN
            SET v_Error = CONCAT('Session duration cannot exceed ', v_OtMaxHours,
                                 ' hours for a ONE_TIME project. Please adjust start and end times.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_RecurMinDays THEN
            SET v_Error = CONCAT('RECURRING projects must span at least ', v_RecurMinDays, ' days.');
        ELSEIF v_SpanDays > v_RecurMaxDays THEN
            SET v_Error = CONCAT('RECURRING projects cannot span more than ', v_RecurMaxDays, ' days.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE'
       AND p_StartDate IS NOT NULL AND p_EndDate IS NOT NULL THEN
        SET v_SpanDays = DATEDIFF(p_EndDate, p_StartDate);
        IF v_SpanDays < v_FlexMinDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects must span at least ', v_FlexMinDays, ' days.');
        ELSEIF v_SpanDays > v_FlexMaxDays THEN
            SET v_Error = CONCAT('FLEXIBLE projects cannot span more than ', v_FlexMaxDays, ' days.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MaxDailyHours IS NOT NULL THEN
        IF p_MaxDailyHours < v_FlexMaxDailyHrs THEN
            SET v_Error = CONCAT('Max daily hours cannot be less than the platform minimum of ',
                                 v_FlexMaxDailyHrs, ' hours.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinSessionHours IS NOT NULL THEN
        IF p_MinSessionHours < v_FlexMinSessHrs THEN
            SET v_Error = CONCAT('Minimum session hours cannot be less than the platform minimum of ',
                                 v_FlexMinSessHrs, ' hour(s).');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_FlexMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_FlexMinAttendPct, '% for FLEXIBLE projects.');
        END IF;
    END IF;

    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' AND p_MinAttendPct IS NOT NULL THEN
        IF p_MinAttendPct < v_RecurMinAttendPct THEN
            SET v_Error = CONCAT('Minimum attendance % cannot be below the platform minimum of ',
                                 v_RecurMinAttendPct, '% for RECURRING projects.');
        END IF;
    END IF;

    -- ORG PERMISSION: RECURRING projects require Super Admin grant
    IF v_Error IS NULL AND p_ScheduleType = 'RECURRING' THEN
        IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND CanCreateRecurring = 1 AND IsDeleted = 0) THEN
            SET v_Error = 'Your organisation does not have permission to create RECURRING projects. Please contact support to upgrade your plan.';
        END IF;
    END IF;

    -- ORG PERMISSION: FLEXIBLE projects require Super Admin grant
    IF v_Error IS NULL AND p_ScheduleType = 'FLEXIBLE' THEN
        IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND CanCreateFlexible = 1 AND IsDeleted = 0) THEN
            SET v_Error = 'Your organisation does not have permission to create FLEXIBLE projects. Please contact support to upgrade your plan.';
        END IF;
    END IF;

    -- ORG CAP: MaxVolunteers cannot exceed org-level limit set by Super Admin
    IF v_Error IS NULL AND p_MaxVolunteers IS NOT NULL THEN
        IF p_MaxVolunteers > (SELECT OrgMaxVolunteers FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1) THEN
            SET v_Error = CONCAT('Max volunteers cannot exceed your organisation''s limit. Please contact support to increase the limit.');
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE

    IF p_ProjectTypeLkpId IS NOT NULL THEN
        SET v_ProjectTypeLkpId = p_ProjectTypeLkpId;
    ELSEIF p_ScheduleType IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_ProjectTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_ScheduleType LIMIT 1;
    END IF;

    IF p_LocationTypeLkpId IS NOT NULL THEN
        SET v_LocationTypeLkpId = p_LocationTypeLkpId;
    ELSEIF p_LocationTypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocationTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'LOCATION_TYPE' AND lv.ValueCode = p_LocationTypeCode LIMIT 1;
    END IF;

    IF p_JoinTypeLkpId IS NOT NULL THEN
        SET v_JoinTypeLkpId = p_JoinTypeLkpId;
    ELSEIF p_RequiresApproval IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_JoinTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'
          AND lv.ValueCode = IF(p_RequiresApproval = 1, 'APPROVE_REQ', 'OPEN_SIGNUP') LIMIT 1;
    END IF;

    IF p_StatusLkpId IS NOT NULL THEN
        SET v_StatusLkpId = p_StatusLkpId;
    ELSEIF p_IsDraft IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS'
          AND lv.ValueCode = IF(p_IsDraft = 1, 'DRAFT', 'UPCOMING') LIMIT 1;
    END IF;

    UPDATE Projects SET
        ProjectName       = COALESCE(p_Title,             ProjectName),
        Category          = COALESCE(p_Category,          Category),
        Description       = COALESCE(p_Description,       Description),
        ProjectTypeLkpId  = COALESCE(v_ProjectTypeLkpId,  ProjectTypeLkpId),
        OneTimeDate       = IF(p_ScheduleType = 'ONE_TIME',  p_StartDate, OneTimeDate),
        RecurStart        = IF(p_ScheduleType = 'RECURRING', p_StartDate, RecurStart),
        RecurEnd          = IF(p_ScheduleType = 'RECURRING', p_EndDate,   RecurEnd),
        RecurDays         = IF(p_ScheduleType = 'RECURRING', p_RecurrenceDays, RecurDays),
        FlexFromDate      = IF(p_ScheduleType = 'FLEXIBLE',  p_StartDate, FlexFromDate),
        FlexToDate        = IF(p_ScheduleType = 'FLEXIBLE',  p_EndDate,   FlexToDate),
        MinHoursRequired  = COALESCE(IF(p_DurationMinutes IS NOT NULL, GREATEST(1, ROUND(p_DurationMinutes / 60)), NULL), MinHoursRequired),
        SessionStartTime  = COALESCE(p_StartTime,         SessionStartTime),
        SessionEndTime    = COALESCE(p_EndTime,           SessionEndTime),
        LocationTypeLkpId = COALESCE(v_LocationTypeLkpId, LocationTypeLkpId),
        AddressLine       = COALESCE(p_Address,           AddressLine),
        Landmark          = COALESCE(p_LocationName,      Landmark),
        City              = COALESCE(p_City,              City),
        State             = COALESCE(p_State,             State),
        Latitude          = COALESCE(p_Latitude,          Latitude),
        Longitude         = COALESCE(p_Longitude,         Longitude),
        GoogleMapsUrl     = COALESCE(p_GoogleMapsUrl,     GoogleMapsUrl),
        MaxVolunteers     = COALESCE(p_MaxVolunteers,     MaxVolunteers),
        JoinTypeLkpId     = COALESCE(v_JoinTypeLkpId,     JoinTypeLkpId),
        IsPublic          = COALESCE(p_IsPublic,          IsPublic),
        AgeRestriction    = IF(p_MinAge IS NOT NULL, IF(p_MinAge >= 18, 1, 0), AgeRestriction),
        StatusLkpId       = COALESCE(v_StatusLkpId,       StatusLkpId),
        MinAttendPct      = COALESCE(p_MinAttendPct,      MinAttendPct),
        MaxDailyHours     = COALESCE(p_MaxDailyHours,     MaxDailyHours),
        MinSessionHours   = COALESCE(p_MinSessionHours,   MinSessionHours),
        UpdatedBy         = p_UserId,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;

    END IF; -- v_Error IS NOT NULL check
END //

-- ── Project_List: v4.3 — adds ScheduleType, LocationName, Address,
--   ApprovedCount; admin org sees all projects (not just IsPublic=1)
DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_StatusLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId   INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode
        LIMIT 1;
    END IF;

    IF p_TypeCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_TypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode
        LIMIT 1;
    END IF;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        p.ProjectName,
        p.Category,
        ptv.ValueCode   AS ScheduleType,         -- ONE_TIME | RECURRING | FLEXIBLE (derived from ProjectTypeLkpId)
        ptv.ValueCode   AS ProjectTypeCode,
        ptv.ValueName   AS ProjectType,
        ltv.ValueCode   AS LocationTypeCode,
        ltv.ValueName   AS LocationType,
        p.Landmark      AS LocationName,          -- actual column is Landmark
        p.AddressLine   AS Address,               -- actual column is AddressLine
        sv.ValueCode    AS StatusCode,
        sv.ValueName    AS Status,
        p.City,
        p.State,
        p.MaxVolunteers,
        p.IsPublic,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.MinHoursRequired,
        p.CancelReason,
        p.CancelledAt,
        p.ImpactSummary,
        p.BeneficiaryCount,
        (SELECT COUNT(*) FROM ProjectApplications pa
         JOIN LookupValues alv ON pa.StatusLkpId = alv.LookupValueId
         WHERE pa.ProjectId = p.ProjectId
           AND alv.ValueCode = 'APPROVED'
           AND pa.IsDeleted  = 0
        ) AS ApprovedCount,
        p.CreatedAt
    FROM Projects p
    JOIN Organisations o        ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues ptv  ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv  ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv   ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.IsDeleted = 0
      -- Admin querying their own org sees ALL projects (public + private)
      -- Public browsing (no orgId) sees only IsPublic=1
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId            = p_OrgId)
      AND (p_Category    IS NULL OR p.Category         = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Projects p
    WHERE p.IsDeleted = 0
      AND (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND (p_OrgId       IS NULL OR p.OrgId            = p_OrgId)
      AND (p_Category    IS NULL OR p.Category         = p_Category)
      AND (p_City        IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //

-- ── Sos_GetById: v4.3 — robust LEFT JOINs, AlertTypeName + StatusName
DROP PROCEDURE IF EXISTS Sos_GetById //
CREATE PROCEDURE Sos_GetById(
    IN p_SosIncidentId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED      -- kept for future auth checks
)
BEGIN
    -- Result set 1: incident details
    SELECT
        si.SosIncidentId,
        si.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS UserName,
        up.ProfilePhoto,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CancelReason,
        si.ResolvedAt,
        si.CancelledAt,
        si.CreatedAt,
        si.OrgId,
        o.OrgName
    FROM  SosIncidents si
    LEFT  JOIN UserProfiles  up  ON si.UserId         = up.UserId AND up.IsDeleted = 0
    LEFT  JOIN Organisations o   ON si.OrgId          = o.OrgId
    LEFT  JOIN LookupValues  atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT  JOIN LookupValues  sv  ON si.StatusLkpId    = sv.LookupValueId
    WHERE  si.SosIncidentId = p_SosIncidentId
      AND  si.IsDeleted     = 0;

    -- Result set 2: responders list
    SELECT
        sr.SosResponderId,
        sr.UserId,
        CONCAT(COALESCE(up2.FirstName,''), ' ', COALESCE(up2.LastName,'')) AS ResponderName,
        up2.ProfilePhoto,
        rv.ValueCode   AS ApprovalStatus,
        rv.ValueName   AS ApprovalStatusName,
        sr.RespondedAt,
        sr.CanViewLocation
    FROM  SosResponders  sr
    LEFT  JOIN UserProfiles  up2 ON sr.UserId              = up2.UserId AND up2.IsDeleted = 0
    LEFT  JOIN LookupValues  rv  ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE  sr.SosIncidentId = p_SosIncidentId
    ORDER  BY sr.RespondedAt ASC;
END //

-- ── Community_GetFeed: v4.3 — adds PollOptionsJson, RoleName, TimeAgo
DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId,
        cp.Title,
        cp.Content,
        ptv.ValueCode  AS PostType,
        ptv.ValueCode  AS PostTypeLkpCode,
        ptv.ValueName  AS PostTypeName,
        av.ValueCode   AS AudienceCode,
        cp.IsPinned,
        cp.AcknowledgeCount,
        cp.LikeCount,
        cp.CommentCount,
        cp.AssignedToUserId,
        CONCAT(aup.FirstName, ' ', aup.LastName) AS AssignedToName,
        cp.DueDate,
        tsv.ValueCode  AS TaskStatus,
        cp.PollEndsAt,
        cp.PollIsMultiChoice,
        cp.VolunteersNeeded,
        cp.ResourceFileUrl,
        cp.EventRef,
        cp.CreatedAt,
        cp.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledged,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLiked,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLikedByMe,
        rv.ValueName AS RoleName,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()), 'd ago')
            ELSE DATE_FORMAT(cp.CreatedAt, '%d %b')
        END AS TimeAgo,
        (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'pollOptionId', po.PollOptionId,
                    'optionText',   po.OptionText,
                    'voteCount',    po.VoteCount,
                    'isVoted',      IF(pv.PollVoteId IS NOT NULL, 1, 0)
                )
            )
            FROM   PollOptions po
            LEFT   JOIN PollVotes pv
                       ON po.PollOptionId = pv.PollOptionId
                      AND pv.UserId       = p_UserId
            WHERE  po.CommunityPostId = cp.CommunityPostId
        ) AS PollOptionsJson

    FROM   CommunityPosts cp
    JOIN   UserProfiles up   ON cp.UserId           = up.UserId  AND up.IsDeleted  = 0
    LEFT   JOIN UserProfiles aup
                             ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT   JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT   JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT   JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT   JOIN CommunityPostAcknowledgements cpa
                             ON cp.CommunityPostId = cpa.CommunityPostId
                            AND cpa.UserId         = p_UserId
    LEFT   JOIN CommunityPostLikes cpl
                             ON cp.CommunityPostId = cpl.CommunityPostId
                            AND cpl.UserId         = p_UserId
    LEFT   JOIN OrgMembers om ON om.OrgId    = cp.OrgId
                             AND om.UserId   = cp.UserId
                             AND om.IsDeleted = 0
    LEFT   JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId

    WHERE  cp.OrgId    = p_OrgId
      AND  cp.IsDeleted = 0
      -- Audience enforcement: ALL_MEMBERS = any approved member;
      -- ADMINS_ONLY = FOUNDER or ADMIN role only;
      -- VOLUNTEERS = any approved member; NULL/unknown = treat as ALL_MEMBERS.
      AND (
          av.ValueCode IS NULL OR av.ValueCode IN ('ALL_MEMBERS', 'VOLUNTEERS')
          OR (av.ValueCode = 'ADMINS_ONLY'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_a
                  JOIN LookupValues lv_ms ON om_a.StatusLkpId = lv_ms.LookupValueId
                  JOIN LookupValues lv_mr ON om_a.RoleLkpId   = lv_mr.LookupValueId
                  WHERE om_a.OrgId     = cp.OrgId
                    AND om_a.UserId    = p_UserId
                    AND om_a.IsDeleted = 0
                    AND lv_ms.ValueCode = 'APPROVED'
                    AND lv_mr.ValueCode IN ('FOUNDER', 'ADMIN')
              ))
      )
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts cp2
    LEFT   JOIN LookupValues av2 ON av2.LookupValueId = cp2.AudienceLkpId
    WHERE  cp2.OrgId     = p_OrgId
      AND  cp2.IsDeleted = 0
      AND (
          av2.ValueCode IS NULL OR av2.ValueCode IN ('ALL_MEMBERS', 'VOLUNTEERS')
          OR (av2.ValueCode = 'ADMINS_ONLY'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_a
                  JOIN LookupValues lv_ms ON om_a.StatusLkpId = lv_ms.LookupValueId
                  JOIN LookupValues lv_mr ON om_a.RoleLkpId   = lv_mr.LookupValueId
                  WHERE om_a.OrgId     = cp2.OrgId
                    AND om_a.UserId    = p_UserId
                    AND om_a.IsDeleted = 0
                    AND lv_ms.ValueCode = 'APPROVED'
                    AND lv_mr.ValueCode IN ('FOUNDER', 'ADMIN')
              ))
      );
END //

-- ── NEW SP: Sos_GetOrgAlerts (v4.3)
--   Returns all SOS incidents for an org with per-user MyApprovalStatus
DROP PROCEDURE IF EXISTS Sos_GetOrgAlerts //
CREATE PROCEDURE Sos_GetOrgAlerts(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED,
    IN p_Limit  INT UNSIGNED
)
BEGIN
    DECLARE v_ActiveLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE'
    LIMIT  1;

    SELECT
        si.SosIncidentId,
        si.OrgId,
        si.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS UserName,
        up.ProfilePhoto,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName,
        CASE WHEN si.StatusLkpId = v_ActiveLkpId THEN 1 ELSE 0 END AS IsActive,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CancelReason,
        si.ResolvedAt,
        si.CancelledAt,
        si.CreatedAt,
        arv.ValueCode  AS MyApprovalStatus
    FROM   SosIncidents si
    LEFT   JOIN UserProfiles up  ON si.UserId         = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT   JOIN LookupValues sv  ON si.StatusLkpId    = sv.LookupValueId
    LEFT   JOIN SosResponders sr ON sr.SosIncidentId  = si.SosIncidentId
                                 AND sr.UserId         = p_UserId
    LEFT   JOIN LookupValues arv ON sr.ApprovalStatusLkpId = arv.LookupValueId
    WHERE  si.OrgId     = p_OrgId
      AND  si.IsDeleted = 0
    ORDER  BY si.CreatedAt DESC
    LIMIT  p_Limit;
END //

-- ── NEW SP: Sos_DeclineResponder (v4.3)
--   Victim declines a pending responder request
DROP PROCEDURE IF EXISTS Sos_DeclineResponder //
CREATE PROCEDURE Sos_DeclineResponder(
    IN p_SosIncidentId  INT UNSIGNED,
    IN p_SosResponderId INT UNSIGNED,
    IN p_DeclinedBy     INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_RejectedLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OwnerUserId   INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId
    INTO   v_RejectedLkpId
    FROM   LookupValues  lv
    JOIN   LookupTypes   lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode   = 'RESPONDER_STATUS'
      AND  lv.ValueCode  = 'REJECTED'
    LIMIT 1;

    IF v_RejectedLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'REJECTED status lookup not configured.' AS Message;
        LEAVE main_block;
    END IF;

    SELECT UserId INTO v_OwnerUserId
    FROM   SosIncidents
    WHERE  SosIncidentId = p_SosIncidentId
      AND  IsDeleted     = 0
    LIMIT 1;

    IF v_OwnerUserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'SOS incident not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_OwnerUserId <> p_DeclinedBy THEN
        SELECT 0 AS IsSuccess, 'Only the SOS victim can decline responders.' AS Message;
        LEAVE main_block;
    END IF;

    UPDATE SosResponders
    SET    ApprovalStatusLkpId = v_RejectedLkpId
    WHERE  SosResponderId = p_SosResponderId
      AND  SosIncidentId  = p_SosIncidentId;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Responder record not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Responder declined.' AS Message;
    END IF;
END //

DELIMITER ;

-- ── v4.3 Seed: ORG_TYPE lookup values ─────────────────────────
-- Adds 6 new legal entity types (INSERT IGNORE = idempotent)
-- Existing: TRUST (1), SOCIETY (2), SECTION_8 (3)
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1
FROM LookupTypes lt
JOIN (
    SELECT 'NGO'                     AS ValueCode, 'NGO'                      AS ValueName, 4  AS OrderNo UNION ALL
    SELECT 'FOUNDATION',                           'Foundation',                              5           UNION ALL
    SELECT 'CHARITABLE_INSTITUTION',               'Charitable Institution',                  6           UNION ALL
    SELECT 'RELIGIOUS_TRUST',                      'Religious Trust',                         7           UNION ALL
    SELECT 'CSR_FOUNDATION',                       'CSR Foundation',                          8           UNION ALL
    SELECT 'EDUCATIONAL_TRUST',                    'Educational Trust',                        9
) v ON 1=1
WHERE lt.TypeCode = 'ORG_TYPE';

-- ── v4.3 SchemaVersions entry ────────────────────────────────────
INSERT INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v4.3', 'v4.3 upgrade: Project_Create/Update rebuilt to match DAL params; Project_List adds ScheduleType/LocationName/Address/ApprovedCount, admin visibility fix; Sos_GetById made robust (LEFT JOINs, AlertTypeName, StatusName); Community_GetFeed adds PollOptionsJson/RoleName/TimeAgo; 2 new SPs (Sos_GetOrgAlerts with MyApprovalStatus, Sos_DeclineResponder); 6 new ORG_TYPE lookup values. Total: 50 tables, 120 SPs.', 'System');

COMMIT;

-- ── VERIFICATION QUERIES ─────────────────────────────────────────
SELECT 'TABLES' AS Check_Type, COUNT(*) AS Count FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'ngoconnect' AND TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'STORED_PROCEDURES', COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'ngoconnect' AND ROUTINE_TYPE = 'PROCEDURE'
UNION ALL
SELECT 'LOOKUP_TYPES', COUNT(*) FROM LookupTypes
UNION ALL
SELECT 'LOOKUP_VALUES', COUNT(*) FROM LookupValues
UNION ALL
SELECT 'SETTINGS', COUNT(*) FROM Settings
UNION ALL
SELECT 'SCHEMA_VERSION', Version FROM (SELECT Version FROM SchemaVersions ORDER BY VersionId DESC LIMIT 1) sv;

-- Expected: TABLES=50, STORED_PROCEDURES=120, LOOKUP_TYPES=45, LOOKUP_VALUES=174+, SETTINGS=21, SCHEMA_VERSION=v4.3

-- ── END OF NGOConnect_Complete_Setup_v4.3.sql ────────────────────


-- ============================================================
-- NGOConnect v4.4 ADDITIONS
-- Applied on top of v4.3 base schema.
-- All statements use DROP IF EXISTS / INSERT IGNORE / ON DUPLICATE KEY
-- patterns — safe to run on a fresh install (SPs created here override
-- the v4.3 versions created above) or incrementally on an existing db.
--
-- Sources: patch files dated 2026-07-07 through 2026-07-10
-- Patches included:
--   NGOConnect_Patch_Distance.sql
--   NGOConnect_Patch_ImpactSPs.sql
--   NGOConnect_Patch_ColumnFix.sql
--   NGOConnect_Patch_ReportPost.sql
--   NGOConnect_Patch_UserDocuments.sql
--   NGOConnect_Patch_AdminPostsSP.sql
--   NGOConnect_Patch_DashboardProjectApps.sql
--   NGOConnect_Patch_OrgGetProfile_MemberStatus.sql
--   NGOConnect_Patch_VolunteerSPs.sql
--   NGOConnect_Patch_VolunteerProfileDetails.sql
--   NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql
--   NGOConnect_Patch_PostFeed_VideoSupport.sql
--   NGOConnect_Patch_UserGetMyOrgs_Final.sql
-- ============================================================

USE ngoconnect;

-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 1: Settings Seeds (INSERT IGNORE — safe to re-run)
-- ────────────────────────────────────────────────────────────────────────────

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
('PROJECT', 'QR_EXPIRY_MINUTES', '60', 'NUMBER',
    'QR code validity window in minutes after generation. Volunteers must scan within this time.', 0),
('PROJECT', 'QR_BUFFER_MINUTES', '15', 'NUMBER',
    'Minutes BEFORE session start that the admin can generate a QR. Allows early arrivals to scan.', 0);

-- v5.0 — AES-256 key for URL share token encryption (hides raw numeric IDs in public URLs)
-- IMPORTANT: Replace the placeholder hex below with a securely generated 32-byte key:
--   dotnet: Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)).ToLower()
--   bash:   openssl rand -hex 32
-- Never reuse this key across environments. Store the Railway env value separately.
INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
('SECURITY', 'URL_SHARE_SECRET_KEY',
 'REPLACE_WITH_OPENSSL_RAND_HEX_32_OUTPUT',
 'STRING',
 'AES-256-GCM key (64-char hex) used to encrypt/decrypt share URL tokens. Never expose publicly.',
 0);


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 2: LookupValues Updates
-- ────────────────────────────────────────────────────────────────────────────

-- DOCUMENT_TYPE_USER: replace India-specific types with universal categories
SET @DocTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' LIMIT 1);

-- Soft-delete India-specific types (preserves FK integrity, hides from UI)
UPDATE LookupValues
SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = 1
WHERE  LookupTypeId = @DocTypeId
  AND  ValueCode IN ('AADHAAR', 'PAN', 'VOTER_ID')
  AND  IsDeleted = 0;

-- Upsert universal types
INSERT INTO LookupValues
    (LookupTypeId, ValueCode, ValueName, Description, IsDefault, IsSystemValue, OrderNo, CreatedBy)
VALUES
    (@DocTypeId, 'PHOTO_ID',    'Government Photo ID',  'Any govt-issued photo ID — national card, passport or driver licence',   1, 1, 1, 1),
    (@DocTypeId, 'ADDR_PROOF',  'Address Proof',        'Utility bill, bank statement, or government letter showing your address', 0, 1, 2, 1),
    (@DocTypeId, 'PASSPORT',    'Passport',             'International travel document',                                          0, 1, 3, 1),
    (@DocTypeId, 'DRIVING_LIC', 'Driving License',      'Government-issued driving licence',                                      0, 1, 4, 1),
    (@DocTypeId, 'OTHER',       'Other Document',       'Any other supporting document',                                          0, 1, 5, 1)
ON DUPLICATE KEY UPDATE
    ValueName   = VALUES(ValueName),
    Description = VALUES(Description),
    IsDefault   = VALUES(IsDefault),
    IsDeleted   = 0,
    DeletedAt   = NULL,
    OrderNo     = VALUES(OrderNo);


-- ────────────────────────────────────────────────────────────────────────────
-- SECTION 3: Updated Stored Procedures
-- ────────────────────────────────────────────────────────────────────────────

DELIMITER //


-- ── 3.02 User_GetImpact ─────────────────────────────────────────────────────
-- Full rebuild: ImpactScore inline, rank name, anchored on Users table.
-- FIXED: uses AttendStatusLkpId (FK) not AttendanceStatus (VARCHAR which doesn't exist)
--        anchored on Users (not UserProfiles) — always returns a row
-- FIXED: v_ProjCompleted now counts APPROVED applications on COMPLETED/EXPIRED projects
--        (previously required explicit ProjectAttendance rows marked ATTENDED, which were
--         never created when admin completed a project without recording individual attendance)
-- (Source: NGOConnect_Patch_ImpactSPs_Fix.sql)
DROP PROCEDURE IF EXISTS User_GetImpact //
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalHours        DECIMAL(8,2)  DEFAULT 0;
    DECLARE v_ProjCompleted     INT           DEFAULT 0;
    DECLARE v_NgosJoined        INT           DEFAULT 0;
    DECLARE v_CertCount         INT           DEFAULT 0;
    DECLARE v_BadgeCount        INT           DEFAULT 0;
    DECLARE v_SkillCount        INT           DEFAULT 0;
    DECLARE v_NoShows           INT           DEFAULT 0;
    DECLARE v_Withdrawals       INT           DEFAULT 0;
    DECLARE v_ImpactScore       INT           DEFAULT 0;
    DECLARE v_Attended          INT           DEFAULT 0;
    DECLARE v_TotalSessions     INT           DEFAULT 0;
    DECLARE v_ReliabilityPct    DECIMAL(5,2)  DEFAULT 0;
    DECLARE v_ProjApplied       INT           DEFAULT 0;
    DECLARE v_PendingApps       INT           DEFAULT 0;
    DECLARE v_ApprovedApps      INT           DEFAULT 0;
    DECLARE v_RankNumber        INT           DEFAULT 1;
    DECLARE v_TotalRanked       INT           DEFAULT 0;
    DECLARE v_AttStatusAttended INT UNSIGNED  DEFAULT 0;
    DECLARE v_AttStatusNoShow   INT UNSIGNED  DEFAULT 0;

    SELECT LookupValueId INTO v_AttStatusAttended
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_AttStatusNoShow
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    -- Sum stored HoursLogged (accurate per-project totals, includes recurring multiplier)
    SELECT ROUND(COALESCE(SUM(pa.HoursLogged), 0), 1)
    INTO   v_TotalHours
    FROM   ProjectAttendance pa
    WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;

    -- Count projects where user had an APPROVED application AND project is COMPLETED/EXPIRED.
    -- This is more reliable than requiring explicit ProjectAttendance rows (which are only
    -- created when admin manually marks attendance per session — often skipped for completed projects).
    SELECT COUNT(DISTINCT pa.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectApplications pa
    JOIN   Projects        p   ON pa.ProjectId   = p.ProjectId
    JOIN   LookupValues    apv ON pa.StatusLkpId = apv.LookupValueId
    JOIN   LookupValues    prv ON p.StatusLkpId  = prv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
      AND  apv.ValueCode NOT IN ('REJECTED', 'WITHDRAWN')
      AND  prv.ValueCode IN ('COMPLETED', 'EXPIRED');

    SELECT COUNT(*) INTO v_NgosJoined
    FROM   OrgMembers   om JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
    WHERE  om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    SELECT COUNT(*) INTO v_CertCount FROM VolunteerCertificates WHERE UserId = p_UserId;
    SELECT COUNT(*) INTO v_BadgeCount FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;
    SELECT COUNT(*) INTO v_SkillCount FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_NoShows FROM ProjectAttendance
    WHERE  UserId = p_UserId AND AttendStatusLkpId = v_AttStatusNoShow AND IsNoShowExcused = 0;

    SELECT COUNT(*) INTO v_Withdrawals
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

    SET v_ImpactScore = GREATEST(0, ROUND(
        (v_TotalHours * 10 + v_ProjCompleted * 50 + v_NgosJoined * 30
         + v_CertCount * 25 + v_BadgeCount * 15 + v_SkillCount * 5)
        - (v_NoShows * 20 + v_Withdrawals * 15)
    ));

    -- Write computed score back so User_GetProfile (and any caller reading the
    -- stored column) always sees an up-to-date value.
    UPDATE UserProfiles
    SET    ImpactScore = v_ImpactScore
    WHERE  UserId = p_UserId AND IsDeleted = 0;

    SELECT
        SUM(CASE WHEN AttendStatusLkpId = v_AttStatusAttended THEN 1 ELSE 0 END),
        SUM(CASE WHEN AttendStatusLkpId IN (v_AttStatusAttended, v_AttStatusNoShow) THEN 1 ELSE 0 END)
    INTO v_Attended, v_TotalSessions
    FROM ProjectAttendance WHERE UserId = p_UserId;

    IF COALESCE(v_TotalSessions, 0) > 0 THEN
        SET v_ReliabilityPct = ROUND(COALESCE(v_Attended, 0) * 100.0 / v_TotalSessions, 1);
    END IF;

    SELECT COUNT(*) INTO v_ProjApplied FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_PendingApps
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'PENDING';

    SELECT COUNT(*) INTO v_ApprovedApps
    FROM   ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';

    SELECT COUNT(*) + 1 INTO v_RankNumber
    FROM   UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId
    WHERE  up2.ImpactScore > v_ImpactScore
      AND  u2.IsDeleted = 0 AND up2.IsDeleted = 0;

    -- Count ALL active volunteers (including those with 0 score) so the
    -- denominator matches the ranking universe. Without this, a user with
    -- score 0 sees "#1 of 0" because the old filter (ImpactScore > 0) excluded
    -- everyone who hasn't earned points yet.
    SELECT COUNT(*) INTO v_TotalRanked
    FROM   UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId
    WHERE  u2.IsDeleted = 0 AND up2.IsDeleted = 0;

    SELECT
        v_ImpactScore    AS ImpactScore,
        v_ReliabilityPct AS ReliabilityPct,
        v_ProjCompleted  AS ProjectsCompleted,
        v_TotalHours     AS TotalHours,
        v_BadgeCount     AS BadgeCount,
        v_SkillCount     AS SkillCount,
        v_ProjApplied    AS ProjectsApplied,
        v_CertCount      AS CertificateCount,
        COALESCE(up.CreatedAt, u.CreatedAt) AS MemberSince,
        v_NgosJoined     AS NgosJoined,
        v_PendingApps    AS PendingApplications,
        v_ApprovedApps   AS ApprovedApplications,
        v_RankNumber     AS RankNumber,
        v_TotalRanked    AS TotalRanked,
        CASE
            WHEN v_ImpactScore >= 20000 THEN 'Elite'
            WHEN v_ImpactScore >= 10000 THEN 'Diamond'
            WHEN v_ImpactScore >= 5000  THEN 'Platinum'
            WHEN v_ImpactScore >= 2500  THEN 'Gold'
            WHEN v_ImpactScore >= 1500  THEN 'Committed Volunteer'
            WHEN v_ImpactScore >= 500   THEN 'Active Volunteer'
            WHEN v_ImpactScore >= 100   THEN 'Helper'
            ELSE                             'Newcomer'
        END              AS RankName,
        up.FirstName,
        up.LastName,
        up.ProfilePhoto,
        up.Bio
    FROM  Users u
    LEFT  JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //


-- ── 3.03 User_GetImpactSummary ──────────────────────────────────────────────
-- Single SP replaces 3 separate calls (User_GetImpact + User_GetBadges +
-- Application_GetByUser) on the ImpactScreen. Server-side LIMIT prevents
-- unbounded data fetch as a user accumulates hundreds of applications.
-- 7 result sets: Applied / Upcoming / Completed / Cancelled tabs (LIMIT each),
-- Badges (LIMIT), Counts row, Impact stats row.
-- (Source: NGOConnect_Patch_ImpactSummary.sql)
DROP PROCEDURE IF EXISTS User_GetImpactSummary //
CREATE PROCEDURE User_GetImpactSummary(
    IN p_UserId     INT UNSIGNED,
    IN p_AppLimit   INT,
    IN p_BadgeLimit INT
)
BEGIN
    DECLARE v_PendingLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_RejectedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_WithdrawnLkpId  INT UNSIGNED DEFAULT 0;
    DECLARE v_UpcomingProjId  INT UNSIGNED DEFAULT 0;
    DECLARE v_ActiveProjId    INT UNSIGNED DEFAULT 0;
    DECLARE v_ClosingProjId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CompletedProjId INT UNSIGNED DEFAULT 0;
    DECLARE v_ExpiredProjId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CancelledProjId INT UNSIGNED DEFAULT 0;
    DECLARE v_AttendedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CheckedInLkpId  INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_PendingLkpId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'   LIMIT 1;
    SELECT LookupValueId INTO v_ApprovedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'  LIMIT 1;
    SELECT LookupValueId INTO v_RejectedLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'REJECTED'  LIMIT 1;
    SELECT LookupValueId INTO v_WithdrawnLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN' LIMIT 1;
    SELECT LookupValueId INTO v_UpcomingProjId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING'   LIMIT 1;
    SELECT LookupValueId INTO v_ActiveProjId    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'     LIMIT 1;
    SELECT LookupValueId INTO v_ClosingProjId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING'    LIMIT 1;
    SELECT LookupValueId INTO v_CompletedProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED'  LIMIT 1;
    SELECT LookupValueId INTO v_ExpiredProjId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'EXPIRED'    LIMIT 1;
    SELECT LookupValueId INTO v_CancelledProjId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED'  LIMIT 1;
    SELECT LookupValueId INTO v_AttendedLkpId   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'   LIMIT 1;
    SELECT LookupValueId INTO v_CheckedInLkpId  FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    -- RS0: Applied — PENDING
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_PendingLkpId
    ORDER BY pa.CreatedAt DESC LIMIT p_AppLimit;

    -- RS1: Upcoming — APPROVED + project UPCOMING/ACTIVE/CLOSING (volunteer still in-progress)
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn,
        -- RECURRING: sessions this volunteer attended
        (SELECT COUNT(*) FROM ProjectAttendance ata2 JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId
         WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId AND ata2.AttendStatusLkpId = v_AttendedLkpId
        ) AS MyAttendedSessions,
        -- RECURRING: sessions eligible from approval date
        (SELECT COUNT(*) FROM ProjectSessions ps3
         WHERE ps3.ProjectId = p.ProjectId AND ps3.SessionDate >= DATE(pa.StatusUpdatedAt) AND ps3.IsDeleted = 0
        ) AS MyEligibleSessions,
        -- FLEXIBLE: hours logged
        COALESCE((SELECT SUM(ata4.HoursLogged) FROM ProjectAttendance ata4 JOIN ProjectSessions pss4 ON ata4.SessionId = pss4.SessionId
         WHERE pss4.ProjectId = p.ProjectId AND ata4.UserId = p_UserId AND ata4.AttendStatusLkpId = v_AttendedLkpId
        ), 0) AS MyHoursLogged,
        -- FLEXIBLE: required hours
        ROUND(DATEDIFF(p.FlexToDate, p.FlexFromDate) * (TIMESTAMPDIFF(MINUTE, p.SessionStartTime, p.SessionEndTime) / 60.0) * COALESCE(p.MinAttendPct, 70) / 100.0, 2) AS MyRequiredHours,
        p.MinAttendPct,
        -- FLEXIBLE: active check-in record
        (SELECT ata5.AttendanceId FROM ProjectAttendance ata5 JOIN ProjectSessions pss5 ON ata5.SessionId = pss5.SessionId
         WHERE pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId AND ata5.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata5.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInId,
        -- Certificate (if already issued)
        (SELECT vc.CertCode FROM VolunteerCertificates vc
         WHERE vc.ProjectId = p.ProjectId AND vc.UserId = p_UserId AND vc.IsDeleted = 0 LIMIT 1
        ) AS MyCertCode
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId = v_ApprovedLkpId
      AND p.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId, v_ClosingProjId)
    ORDER BY p.RecurStart ASC LIMIT p_AppLimit;

    -- RS2: Completed — not REJECTED/WITHDRAWN + project COMPLETED
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn,
        -- Total hours logged by this volunteer across all sessions of this project
        COALESCE((
            SELECT SUM(ata2.HoursLogged)
            FROM ProjectAttendance ata2
            JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId
            WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId
        ), 0) AS HoursLogged,
        -- Whether a certificate has been issued for this volunteer on this completed project
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc WHERE vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0), 1, 0) AS HasCertificate
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId)
      AND p.StatusLkpId IN (v_CompletedProjId, v_ExpiredProjId)
    ORDER BY pa.StatusUpdatedAt DESC LIMIT p_AppLimit;

    -- RS3: Cancelled — REJECTED/WITHDRAWN OR project EXPIRED/CANCELLED
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        appSv.ValueCode AS StatusCode, appSv.ValueName AS Status,
        pa.CreatedAt, pa.StatusUpdatedAt,
        ptv.ValueCode AS ScheduleTypeCode, ptv.ValueName AS ScheduleTypeName,
        p.RecurStart, p.RecurEnd, p.RecurDays, p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.Landmark AS LocationName, p.City,
        p.Category AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode, projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(SELECT 1 FROM ProjectAttendance ata JOIN ProjectSessions pss ON ata.SessionId = pss.SessionId WHERE pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId), 1, 0) AS IsCheckedIn,
        -- Distinguish admin-remove from self-withdraw: StatusUpdatedBy is set to admin when removed
        IF(pa.StatusUpdatedBy IS NOT NULL AND pa.StatusUpdatedBy != p_UserId, 1, 0) AS WasRemovedByAdmin
    FROM ProjectApplications pa
    JOIN Projects p ON pa.ProjectId = p.ProjectId
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId     = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId) OR p.StatusLkpId = v_CancelledProjId)
    ORDER BY pa.CreatedAt DESC LIMIT p_AppLimit;

    -- RS4: Badges — latest N
    SELECT ub.UserBadgeId, ub.BadgeLkpId, lv.ValueName AS BadgeName, lv.ValueCode AS BadgeCode,
           o.OrgName, p.ProjectName, ub.CreatedAt AS AwardedAt
    FROM   UserBadges ub
    JOIN   LookupValues lv   ON ub.BadgeLkpId      = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId       = p.ProjectId
    WHERE  ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC LIMIT p_BadgeLimit;

    -- RS5: Counts
    SELECT
        (SELECT COUNT(*) FROM ProjectApplications pa WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_PendingLkpId) AS TotalApplied,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId = v_ApprovedLkpId AND p2.StatusLkpId IN (v_UpcomingProjId, v_ActiveProjId)) AS TotalUpcoming,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND pa.StatusLkpId NOT IN (v_RejectedLkpId, v_WithdrawnLkpId) AND p2.StatusLkpId IN (v_CompletedProjId, v_ExpiredProjId)) AS TotalCompleted,
        (SELECT COUNT(*) FROM ProjectApplications pa JOIN Projects p2 ON pa.ProjectId = p2.ProjectId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND (pa.StatusLkpId IN (v_RejectedLkpId, v_WithdrawnLkpId) OR p2.StatusLkpId = v_CancelledProjId)) AS TotalCancelled,
        (SELECT COUNT(*) FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0) AS TotalBadges;

    -- RS6: Impact stats (same logic as User_GetImpact)
    BEGIN
        DECLARE v_TotalHours        DECIMAL(8,2)  DEFAULT 0;
        DECLARE v_ProjCompleted     INT           DEFAULT 0;
        DECLARE v_NgosJoined        INT           DEFAULT 0;
        DECLARE v_CertCount         INT           DEFAULT 0;
        DECLARE v_BadgeCount        INT           DEFAULT 0;
        DECLARE v_SkillCount        INT           DEFAULT 0;
        DECLARE v_NoShows           INT           DEFAULT 0;
        DECLARE v_Withdrawals       INT           DEFAULT 0;
        DECLARE v_ImpactScore       INT           DEFAULT 0;
        DECLARE v_Attended          INT           DEFAULT 0;
        DECLARE v_TotalSessions     INT           DEFAULT 0;
        DECLARE v_ReliabilityPct    DECIMAL(5,2)  DEFAULT 0;
        DECLARE v_ProjApplied       INT           DEFAULT 0;
        DECLARE v_PendingApps       INT           DEFAULT 0;
        DECLARE v_ApprovedApps      INT           DEFAULT 0;
        DECLARE v_RankNumber        INT           DEFAULT 1;
        DECLARE v_TotalRanked       INT           DEFAULT 0;
        DECLARE v_AttStatusAttended INT UNSIGNED  DEFAULT 0;
        DECLARE v_AttStatusNoShow   INT UNSIGNED  DEFAULT 0;

        SELECT LookupValueId INTO v_AttStatusAttended FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;
        SELECT LookupValueId INTO v_AttStatusNoShow   FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW'   LIMIT 1;

        -- Use SUM(HoursLogged) — reflects accurate per-project totals
        SELECT ROUND(COALESCE(SUM(pa.HoursLogged), 0), 1)
        INTO   v_TotalHours
        FROM   ProjectAttendance pa
        WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;

        SELECT COUNT(DISTINCT pa.ProjectId) INTO v_ProjCompleted
        FROM ProjectApplications pa JOIN Projects p ON pa.ProjectId = p.ProjectId
        JOIN LookupValues apv ON pa.StatusLkpId = apv.LookupValueId
        JOIN LookupValues prv ON p.StatusLkpId  = prv.LookupValueId
        WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0
          AND apv.ValueCode NOT IN ('REJECTED', 'WITHDRAWN')
          AND prv.ValueCode IN ('COMPLETED', 'EXPIRED');

        SELECT COUNT(*) INTO v_NgosJoined FROM OrgMembers om JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId WHERE om.UserId = p_UserId AND om.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';
        SELECT COUNT(*) INTO v_CertCount  FROM VolunteerCertificates WHERE UserId = p_UserId;
        SELECT COUNT(*) INTO v_BadgeCount FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_SkillCount FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_NoShows    FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_AttStatusNoShow AND IsNoShowExcused = 0;
        SELECT COUNT(*) INTO v_Withdrawals FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode IN ('REJECTED', 'WITHDRAWN');

        SET v_ImpactScore = GREATEST(0, ROUND(
            (v_TotalHours * 10 + v_ProjCompleted * 50 + v_NgosJoined * 30 + v_CertCount * 25 + v_BadgeCount * 15 + v_SkillCount * 5)
            - (v_NoShows * 20 + v_Withdrawals * 15)
        ));

        UPDATE UserProfiles SET ImpactScore = v_ImpactScore WHERE UserId = p_UserId AND IsDeleted = 0;

        SELECT
            SUM(CASE WHEN AttendStatusLkpId = v_AttStatusAttended THEN 1 ELSE 0 END),
            SUM(CASE WHEN AttendStatusLkpId IN (v_AttStatusAttended, v_AttStatusNoShow) THEN 1 ELSE 0 END)
        INTO v_Attended, v_TotalSessions FROM ProjectAttendance WHERE UserId = p_UserId;

        IF COALESCE(v_TotalSessions, 0) > 0 THEN
            SET v_ReliabilityPct = ROUND(COALESCE(v_Attended, 0) * 100.0 / v_TotalSessions, 1);
        END IF;

        SELECT COUNT(*) INTO v_ProjApplied  FROM ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
        SELECT COUNT(*) INTO v_PendingApps  FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'PENDING';
        SELECT COUNT(*) INTO v_ApprovedApps FROM ProjectApplications pa JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId WHERE pa.UserId = p_UserId AND pa.IsDeleted = 0 AND lv.ValueCode = 'APPROVED';
        SELECT COUNT(*) + 1 INTO v_RankNumber FROM UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId WHERE up2.ImpactScore > v_ImpactScore AND u2.IsDeleted = 0 AND up2.IsDeleted = 0;
        SELECT COUNT(*) INTO v_TotalRanked FROM UserProfiles up2 JOIN Users u2 ON up2.UserId = u2.UserId WHERE u2.IsDeleted = 0 AND up2.IsDeleted = 0;

        SELECT
            v_ImpactScore AS ImpactScore, v_ReliabilityPct AS ReliabilityPct,
            v_ProjCompleted AS ProjectsCompleted, v_TotalHours AS TotalHours,
            v_BadgeCount AS BadgeCount, v_SkillCount AS SkillCount,
            v_ProjApplied AS ProjectsApplied, v_CertCount AS CertificateCount,
            COALESCE(up.CreatedAt, u.CreatedAt) AS MemberSince,
            v_NgosJoined AS NgosJoined, v_PendingApps AS PendingApplications,
            v_ApprovedApps AS ApprovedApplications, v_RankNumber AS RankNumber,
            v_TotalRanked AS TotalRanked,
            CASE WHEN v_ImpactScore >= 20000 THEN 'Elite'
                 WHEN v_ImpactScore >= 10000 THEN 'Diamond'
                 WHEN v_ImpactScore >= 5000  THEN 'Platinum'
                 WHEN v_ImpactScore >= 2500  THEN 'Gold'
                 WHEN v_ImpactScore >= 1500  THEN 'Committed Volunteer'
                 WHEN v_ImpactScore >= 500   THEN 'Active Volunteer'
                 WHEN v_ImpactScore >= 100   THEN 'Helper'
                 ELSE                             'Newcomer'
            END AS RankName,
            up.FirstName, up.LastName, up.ProfilePhoto, up.Bio
        FROM  Users u
        LEFT  JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
    END;
END //


-- ── 3.04 Application_GetByUser ──────────────────────────────────────────────
-- Full rebuild: now paged (p_PageNumber + p_PageSize); adds schedule + status fields
-- (Source: NGOConnect_Patch_ImpactSPs.sql)
DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        appSv.ValueCode  AS StatusCode,
        appSv.ValueName  AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        ptv.ValueCode    AS ScheduleTypeCode,
        ptv.ValueName    AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.OneTimeDate,
        p.FlexFromDate,
        p.FlexToDate,
        p.Landmark       AS LocationName,
        p.City,
        p.Category       AS CategoryName,
        projSv.ValueCode AS ProjectStatusCode,
        projSv.ValueName AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        IF(EXISTS(
            SELECT 1 FROM ProjectAttendance ata
            JOIN   ProjectSessions pss ON ata.SessionId = pss.SessionId
            WHERE  pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId
        ), 1, 0) AS IsCheckedIn,
        COALESCE((
            SELECT SUM(ata2.HoursLogged)
            FROM ProjectAttendance ata2
            JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId
            WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId
        ), 0) AS HoursLogged,
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc WHERE vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0), 1, 0) AS HasCertificate
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId   = p.ProjectId
    JOIN   Organisations o     ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId        = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId         = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId    = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId       = jtv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //


-- ── 3.04 Application_Apply ─────────────────────────────────────────────────
-- Updated: p_Note → p_Motivation; added p_RequestedSessions
-- Updated: re-apply after REJECTED — UPDATE existing row to PENDING instead of INSERT
--          (plain INSERT crashed with duplicate key on (ProjectId, UserId, IsDeleted=0))
-- (Source: NGOConnect_Patch_ImpactSPs.sql)
DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_PendingLkpId   INT UNSIGNED;
    DECLARE v_ExistingId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExistingStatus VARCHAR(50)  DEFAULT NULL;
    DECLARE v_AgeRestriction TINYINT(1)   DEFAULT 0;
    DECLARE v_IsPublic       TINYINT(1)   DEFAULT 1;
    DECLARE v_OrgId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_UserDob        DATE         DEFAULT NULL;
    DECLARE v_UserAge        INT          DEFAULT NULL;
    DECLARE v_MembershipOk   TINYINT(1)   DEFAULT 1;
    DECLARE v_ApplicantName  VARCHAR(200) DEFAULT NULL;

    -- Resolve PENDING lookup id
    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- Read project attributes in one query
    SELECT p.AgeRestriction, p.IsPublic, p.OrgId
    INTO   v_AgeRestriction, v_IsPublic, v_OrgId
    FROM   Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    -- ── IsPublic check — private projects require approved membership ─────────
    IF v_IsPublic = 0 THEN
        IF NOT EXISTS (
            SELECT 1 FROM OrgMembers om
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId
            WHERE om.OrgId = v_OrgId AND om.UserId = p_UserId
              AND om.IsDeleted = 0
              AND st.TypeCode = 'MEMBER_STATUS' AND sv.ValueCode = 'APPROVED'
        ) THEN
            SET v_MembershipOk = 0;
            SELECT 0 AS IsSuccess,
                   'This project is only available to organisation members.' AS Message,
                   NULL AS ApplicationId, NULL AS OrgId;
        END IF;
    END IF;

    -- ── Age restriction check ────────────────────────────────────────────────
    IF v_MembershipOk = 1 AND v_AgeRestriction = 1 THEN
        SELECT up.DateOfBirth INTO v_UserDob
        FROM   UserProfiles up WHERE up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        IF v_UserDob IS NULL THEN
            SELECT 0 AS IsSuccess,
                   'This project is for volunteers aged 18 and above. Please update your date of birth in your profile before applying.' AS Message,
                   NULL AS ApplicationId, NULL AS OrgId;
        ELSE
            SET v_UserAge = TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE());
            IF v_UserAge < 18 THEN
                SELECT 0 AS IsSuccess,
                       CONCAT('This project requires volunteers to be at least 18 years old. Your current age (', v_UserAge, ') does not meet the requirement.') AS Message,
                       NULL AS ApplicationId, NULL AS OrgId;
            END IF;
        END IF;
    END IF;

    -- Only proceed if both checks passed
    IF v_MembershipOk = 1
       AND (
           (v_AgeRestriction = 0)
           OR (v_AgeRestriction = 1 AND v_UserDob IS NOT NULL AND TIMESTAMPDIFF(YEAR, v_UserDob, CURDATE()) >= 18)
       )
    THEN

    -- Check for any existing non-deleted application for this user + project
    SELECT pa.ApplicationId, lv.ValueCode
    INTO   v_ExistingId, v_ExistingStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
    LIMIT  1;

    IF v_ExistingStatus IN ('PENDING', 'APPROVED') THEN
        -- Cannot re-apply while a live application exists
        SELECT 0 AS IsSuccess,
               CONCAT('You already have a ', v_ExistingStatus, ' application for this project.') AS Message,
               NULL AS ApplicationId,
               NULL AS OrgId;

    ELSEIF v_ExistingStatus = 'REJECTED' THEN
        -- Re-application: reset the rejected row to PENDING
        UPDATE ProjectApplications
        SET    StatusLkpId       = v_PendingLkpId,
               Motivation        = p_Motivation,
               RequestedSessions = p_RequestedSessions,
               RejectionReason   = NULL,
               StatusUpdatedAt   = NOW(),
               StatusUpdatedBy   = p_UserId,
               UpdatedBy         = p_UserId,
               UpdatedAt         = NOW()
        WHERE  ApplicationId = v_ExistingId;

        -- Resolve applicant name for notification body
        SELECT COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''), u.Mobile, u.Email)
        INTO   v_ApplicantName
        FROM   UserProfiles up JOIN Users u ON u.UserId = p_UserId
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        SELECT 1 AS IsSuccess, 'Application re-submitted successfully.' AS Message,
               v_ExistingId AS ApplicationId,
               v_OrgId AS OrgId,
               v_ApplicantName AS ApplicantName;

    ELSE
        -- No existing application — fresh INSERT
        INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
        VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

        -- Resolve applicant name for notification body
        SELECT COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''), u.Mobile, u.Email)
        INTO   v_ApplicantName
        FROM   UserProfiles up JOIN Users u ON u.UserId = p_UserId
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0 LIMIT 1;

        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
               LAST_INSERT_ID() AS ApplicationId,
               v_OrgId AS OrgId,
               v_ApplicantName AS ApplicantName;
    END IF;

    END IF; -- end checks gate
END //


-- ── 3.05 Project_List ───────────────────────────────────────────────────────
-- Updated: adds p_UserLat + p_UserLon optional; returns DistanceKm (Haversine)
-- Updated: public browse (p_OrgId IS NULL) restricted to ACTIVE + UPCOMING only
--          (replaces EXPIRED blacklist with positive whitelist — cleaner + hides
--           DRAFT, CANCELLED, COMPLETED from volunteer browse)
-- Updated: adds p_Keyword for name/description search
-- Updated: COUNT query now has same JOINs as main SELECT (was missing org JOIN)
-- Updated: adds p_UserId (nullable); returns ApplicationStatusCode so AllOpportunities
--          screen can show "Applied" state for projects already applied to
DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_Keyword    VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7),
    IN p_UserId     INT UNSIGNED
)
BEGIN
    DECLARE v_Offset             INT;
    DECLARE v_StatusLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_UpcomingLkpId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedOrgLkpId   INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    END IF;

    IF p_TypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_TypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode LIMIT 1;
    END IF;

    -- Resolve ACTIVE + UPCOMING LkpIds for public volunteer browse whitelist
    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    -- Resolve APPROVED org status — public browse must exclude suspended/inactive orgs
    SELECT lv.LookupValueId INTO v_ApprovedOrgLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl    AS OrgLogoUrl,
        p.ProjectName,
        p.Category,
        ptv.ValueCode    AS ScheduleType,
        ptv.ValueCode    AS ProjectTypeCode,
        ptv.ValueName    AS ProjectType,
        ltv.ValueCode    AS LocationTypeCode,
        ltv.ValueName    AS LocationType,
        p.Landmark       AS LocationName,
        p.AddressLine    AS Address,
        sv.ValueCode     AS StatusCode,
        sv.ValueName     AS Status,
        p.City,
        p.State,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.IsPublic,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.MinHoursRequired,
        p.CancelReason,
        p.CancelledAt,
        p.ImpactSummary,
        p.BeneficiaryCount,
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv ON pa2.StatusLkpId = alv.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv.ValueCode = 'APPROVED'
           AND pa2.IsDeleted = 0) AS ApprovedCount,
        -- ApplicationStatusCode: non-null only when p_UserId provided and user has applied
        CASE WHEN p_UserId IS NOT NULL AND p_UserId > 0 THEN
            (SELECT lv2.ValueCode FROM ProjectApplications pa3
             JOIN LookupValues lv2 ON pa3.StatusLkpId = lv2.LookupValueId
             WHERE pa3.ProjectId = p.ProjectId AND pa3.UserId = p_UserId AND pa3.IsDeleted = 0
             LIMIT 1)
        ELSE NULL END AS ApplicationStatusCode,
        p.CreatedAt,
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
            )), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o       ON p.OrgId             = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv   ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv    ON p.StatusLkpId       = sv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      AND  (p_Keyword     IS NULL
            OR p.ProjectName  LIKE CONCAT('%', p_Keyword, '%')
            OR p.Description  LIKE CONCAT('%', p_Keyword, '%')
            OR o.OrgName      LIKE CONCAT('%', p_Keyword, '%')
            OR p.City         LIKE CONCAT('%', p_Keyword, '%')
            OR p.State        LIKE CONCAT('%', p_Keyword, '%')
            OR p.Landmark     LIKE CONCAT('%', p_Keyword, '%')
            OR p.AddressLine  LIKE CONCAT('%', p_Keyword, '%'))
      -- Public volunteer browse: only ACTIVE + UPCOMING (admin with p_OrgId sees all)
      AND  (p_OrgId IS NOT NULL OR p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId))
      -- Public volunteer browse: only projects from APPROVED organisations
      AND  (p_OrgId IS NOT NULL OR o.StatusLkpId = v_ApprovedOrgLkpId)
    ORDER BY
        CASE WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL THEN
            CASE WHEN p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL THEN
                6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))))
            ELSE 999999 END
        ELSE NULL END ASC,
        p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- TotalCount — same JOINs and WHERE as main SELECT (was missing org JOIN before)
    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    JOIN   Organisations o       ON p.OrgId             = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues sv    ON p.StatusLkpId       = sv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
      AND  (p_Keyword     IS NULL
            OR p.ProjectName  LIKE CONCAT('%', p_Keyword, '%')
            OR p.Description  LIKE CONCAT('%', p_Keyword, '%')
            OR o.OrgName      LIKE CONCAT('%', p_Keyword, '%')
            OR p.City         LIKE CONCAT('%', p_Keyword, '%')
            OR p.State        LIKE CONCAT('%', p_Keyword, '%')
            OR p.Landmark     LIKE CONCAT('%', p_Keyword, '%')
            OR p.AddressLine  LIKE CONCAT('%', p_Keyword, '%'))
      AND  (p_OrgId IS NOT NULL OR p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId))
      AND  (p_OrgId IS NOT NULL OR o.StatusLkpId = v_ApprovedOrgLkpId);
END //


-- ── 3.06 Project_GetNearbyFeed ───────────────────────────────────────────────
-- Home-screen nearby feed: pure distance ordering (nearest to farthest).
-- Algorithm (sort key):
--   1. DistanceKm ASC  — nearest project first (NULL distance = no GPS, sorts last)
--   2. CreatedAt DESC  — tie-break by newest
-- Filters: ACTIVE or UPCOMING status, IsPublic=1, user has NOT already
-- applied (any status), DistanceKm ≤ 1000 km,
-- capacity not full (MaxVolunteers NULL or 0 = unlimited).
-- Projects with no GPS coordinates are excluded (WHERE Latitude IS NOT NULL).
DROP PROCEDURE IF EXISTS Project_GetNearbyFeed //
CREATE PROCEDURE Project_GetNearbyFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_UserLat    DECIMAL(10,7),   -- NULL = no GPS (distance skipped)
    IN p_UserLon    DECIMAL(10,7),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset        INT         DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ActiveLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_UpcomingLkpId INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'   LIMIT 1;

    SELECT LookupValueId INTO v_UpcomingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl           AS OrgLogoUrl,
        p.ProjectName,
        p.Description,
        p.Category          AS CategoryName,
        ptv.ValueCode       AS ProjectTypeCode,
        ptv.ValueName       AS ProjectType,
        -- ScheduleType / ScheduleTypeCode mirror ProjectType so mobile consumers
        -- (ApplyModal, AllOpportunitiesScreen) can read a consistent field name
        -- regardless of which SP sourced the project.
        ptv.ValueCode       AS ScheduleType,
        ptv.ValueCode       AS ScheduleTypeCode,
        ltv.ValueCode       AS LocationTypeCode,
        p.Landmark          AS LocationName,
        p.AddressLine       AS Address,
        p.City,
        p.State,
        sv.ValueCode        AS StatusCode,
        sv.ValueName        AS Status,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.CreatedAt,
        -- Approved volunteer count (for "X / Y spots" display)
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv2.ValueCode = 'APPROVED'
           AND pa2.IsDeleted  = 0
        ) AS ApprovedCount,
        -- Haversine distance (km); NULL only when user has no GPS.
        -- Project GPS is guaranteed non-null by WHERE clause below.
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 )), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o       ON o.OrgId               = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv      ON sv.LookupValueId       = p.StatusLkpId
    LEFT JOIN LookupValues ptv   ON ptv.LookupValueId      = p.ProjectTypeLkpId
    LEFT JOIN LookupValues ltv   ON ltv.LookupValueId      = p.LocationTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      -- Only projects with a map pin — no pin = not a nearby opportunity
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      -- Exclude projects the user has ever applied to (any status).
      -- Hidden until the project completes and is re-activated as a new cycle.
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      -- Distance guard: only within 1000 km when user GPS is available
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          )
      -- Exclude capacity-full projects (NULL or 0 = unlimited seats)
      AND (
            p.MaxVolunteers IS NULL
            OR p.MaxVolunteers = 0
            OR (SELECT COUNT(*) FROM ProjectApplications pa2
                JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
                WHERE pa2.ProjectId    = p.ProjectId
                  AND alv2.ValueCode   = 'APPROVED'
                  AND pa2.IsDeleted    = 0
               ) < p.MaxVolunteers
          )
    ORDER BY
        -- Nearest first; NULL distance (no GPS) sorts last
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN 6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 ))
            ELSE NULL
        END ASC,
        p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- TotalCount for pagination (same filters, no pagination)
    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    JOIN   Organisations o  ON o.OrgId = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv ON sv.LookupValueId = p.StatusLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          )
      AND (
            p.MaxVolunteers IS NULL
            OR p.MaxVolunteers = 0
            OR (SELECT COUNT(*) FROM ProjectApplications pa2
                JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
                WHERE pa2.ProjectId    = p.ProjectId
                  AND alv2.ValueCode   = 'APPROVED'
                  AND pa2.IsDeleted    = 0
               ) < p.MaxVolunteers
          );
END //


-- ── 3.06 Post_Report ────────────────────────────────────────────────────────
-- Updated: p_ReasonLkpId INT → p_ReasonCode VARCHAR(50); SP resolves LkpId internally
-- Prevents duplicate reports from same user on same post
-- (Source: NGOConnect_Patch_ReportPost.sql)
DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId     INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_ReasonCode VARCHAR(50),
    IN p_Details    TEXT
)
BEGIN
    DECLARE v_ReasonLkpId   INT UNSIGNED;
    DECLARE v_StatusLkpId   INT UNSIGNED;
    DECLARE v_AlreadyExists INT DEFAULT 0;
    DECLARE v_ReportCount   INT DEFAULT 0;
    DECLARE v_AuthorUserId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgId         INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ReasonLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'REPORT_REASON' AND lv.ValueCode = p_ReasonCode LIMIT 1;

    IF v_ReasonLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown reason code: ', p_ReasonCode) AS Message,
               NULL AS ReportCount, NULL AS PostAuthorUserId, NULL AS OrgId;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyExists
        FROM   PostReports
        WHERE  PostId = p_PostId AND ReportedByUserId = p_UserId;

        IF v_AlreadyExists > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message,
                   NULL AS ReportCount, NULL AS PostAuthorUserId, NULL AS OrgId;
        ELSE
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
            VALUES (p_PostId, p_UserId, v_ReasonLkpId, p_Details, v_StatusLkpId);

            -- Total reports on this post (including the one just inserted)
            SELECT COUNT(*) INTO v_ReportCount FROM PostReports WHERE PostId = p_PostId;

            -- Post author + org for notification fan-out
            SELECT UserId, OrgId INTO v_AuthorUserId, v_OrgId
            FROM   Posts WHERE PostId = p_PostId LIMIT 1;

            SELECT 1            AS IsSuccess,
                   'Post reported.' AS Message,
                   v_ReportCount   AS ReportCount,
                   v_AuthorUserId  AS PostAuthorUserId,
                   v_OrgId         AS OrgId;
        END IF;
    END IF;
END //


-- ── 3.07 User_UploadDocument ────────────────────────────────────────────────
-- Updated: upsert pattern — soft-deletes existing doc of same type first
-- (Source: NGOConnect_Patch_UserDocuments.sql)
DROP PROCEDURE IF EXISTS User_UploadDocument //
CREATE PROCEDURE User_UploadDocument(
    IN p_UserId            INT UNSIGNED,
    IN p_DocumentTypeLkpId INT UNSIGNED,
    IN p_FileUrl           VARCHAR(500),
    IN p_FileName          VARCHAR(255),
    IN p_FileSizeKb        INT UNSIGNED
)
BEGIN
    UPDATE UserDocuments
    SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId, UpdatedBy = p_UserId
    WHERE  UserId = p_UserId AND DocumentTypeLkpId = p_DocumentTypeLkpId AND IsDeleted = 0;

    INSERT INTO UserDocuments (UserId, DocumentTypeLkpId, FileUrl, FileName, FileSizeKb, CreatedBy, UpdatedBy)
    VALUES (p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb, p_UserId, p_UserId);

    -- v5.1: same RESUBMITTED flip as User_UpdateProfile — re-uploading a document
    -- after being flagged NEEDS_UPDATE signals the Super Admin should take another look.
    UPDATE Users u
    JOIN LookupValues lv ON u.ProfileVerificationLkpId = lv.LookupValueId
    SET u.ProfileVerificationLkpId = (
            SELECT lv2.LookupValueId FROM LookupValues lv2
            JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE lt2.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv2.ValueCode = 'RESUBMITTED'
            LIMIT 1
        ),
        u.UpdatedAt = NOW()
    WHERE u.UserId = p_UserId AND lv.ValueCode = 'NEEDS_UPDATE';

    SELECT 1 AS IsSuccess, 'Document saved.' AS Message, LAST_INSERT_ID() AS UserDocumentId;
END //


-- ── 3.08 User_GetDocuments ──────────────────────────────────────────────────
-- NEW SP
-- (Source: NGOConnect_Patch_UserDocuments.sql)
DROP PROCEDURE IF EXISTS User_GetDocuments //
CREATE PROCEDURE User_GetDocuments(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ud.UserDocumentId, ud.UserId, ud.DocumentTypeLkpId,
        lv.ValueCode AS DocTypeCode, lv.ValueName AS DocTypeName,
        ud.FileUrl, ud.FileName, ud.FileSizeKb, ud.IsVerified,
        ud.CreatedAt AS UploadedAt
    FROM UserDocuments ud
    JOIN LookupValues  lv ON ud.DocumentTypeLkpId = lv.LookupValueId
    WHERE ud.UserId = p_UserId AND ud.IsDeleted = 0
    ORDER BY lv.OrderNo ASC;
END //


-- ── 3.09 User_DeleteDocument ────────────────────────────────────────────────
-- NEW SP — soft-delete with user ownership check
-- (Source: NGOConnect_Patch_UserDocuments.sql)
DROP PROCEDURE IF EXISTS User_DeleteDocument //
CREATE PROCEDURE User_DeleteDocument(
    IN p_UserDocumentId INT UNSIGNED,
    IN p_UserId         INT UNSIGNED
)
BEGIN
    UPDATE UserDocuments
    SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId, UpdatedBy = p_UserId
    WHERE  UserDocumentId = p_UserDocumentId AND UserId = p_UserId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document removed.' AS Message;
    END IF;
END //


-- ── 3.10 Org_GetAdminPosts ──────────────────────────────────────────────────
-- NEW SP — org feed post list with report count + status for admin
-- (Source: NGOConnect_Patch_AdminPostsSP.sql)
DROP PROCEDURE IF EXISTS Org_GetAdminPosts //
CREATE PROCEDURE Org_GetAdminPosts(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_PendingReportLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingReportLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT
        p.PostId, p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        rv.ValueCode AS RoleCode, rv.ValueName AS RoleName,
        p.Content,
        p.LikeCount    AS LikesCount,
        p.CommentCount AS CommentsCount,
        p.IsPinned, p.CreatedAt,
        COALESCE((SELECT COUNT(*) FROM PostReports pr
                  WHERE pr.PostId = p.PostId
                    AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
        ), 0) AS ReportCount,
        CASE WHEN COALESCE((SELECT COUNT(*) FROM PostReports pr
                            WHERE pr.PostId = p.PostId
                              AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
        ), 0) > 0 THEN 'REPORTED' ELSE 'PUBLISHED' END AS StatusCode,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om    ON p.UserId = om.UserId AND om.OrgId = p_OrgId AND om.IsDeleted = 0
    LEFT JOIN LookupValues rv    ON om.RoleLkpId = rv.LookupValueId
    LEFT JOIN PostMedia     pm   ON pm.PostId = p.PostId
    LEFT JOIN LookupValues  lv_mt ON lv_mt.LookupValueId = pm.MediaTypeLkpId
    WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
    GROUP BY
        p.PostId, p.UserId, up.FirstName, up.LastName, up.ProfilePhoto,
        rv.ValueCode, rv.ValueName, p.Content, p.LikeCount, p.CommentCount,
        p.IsPinned, p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC;
END //


-- ── 3.11 Org_PinPost ────────────────────────────────────────────────────────
-- Toggle IsPinned on a CommunityPost (admin action from Admin Community tab).
-- Bug fix: was incorrectly querying the Posts (feed) table; corrected to CommunityPosts.
-- CommunityPosts has no PinnedAt/PinnedBy columns — only IsPinned + UpdatedBy/UpdatedAt.
DROP PROCEDURE IF EXISTS Org_PinPost //
CREATE PROCEDURE Org_PinPost(
    IN p_PostId   INT UNSIGNED,
    IN p_OrgId    INT UNSIGNED,
    IN p_PinnedBy INT UNSIGNED
)
BEGIN
    DECLARE v_Current TINYINT(1);
    SELECT IsPinned INTO v_Current FROM CommunityPosts
    WHERE CommunityPostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1;

    IF v_Current IS NULL THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        UPDATE CommunityPosts
        SET IsPinned  = NOT v_Current,
            UpdatedBy = p_PinnedBy
        WHERE CommunityPostId = p_PostId AND OrgId = p_OrgId;

        SELECT 1 AS IsSuccess,
               CASE WHEN NOT v_Current = 1 THEN 'Post pinned.' ELSE 'Post unpinned.' END AS Message;
    END IF;
END //


-- ── 3.12 Org_DeletePost ─────────────────────────────────────────────────────
-- NEW SP — soft-delete a feed post (admin action)
-- (Source: NGOConnect_Patch_AdminPostsSP.sql)
DROP PROCEDURE IF EXISTS Org_DeletePost //
CREATE PROCEDURE Org_DeletePost(
    IN p_PostId    INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_DeletedBy INT UNSIGNED
)
BEGIN
    UPDATE Posts
    SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_DeletedBy, UpdatedBy = p_DeletedBy
    WHERE PostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Post deleted.' AS Message;
    END IF;
END //


-- ── 3.13 Org_ModeratePost ───────────────────────────────────────────────────
-- NEW SP — KEEP / REMOVE action on a reported post
-- (Source: NGOConnect_Patch_AdminPostsSP.sql)
DROP PROCEDURE IF EXISTS Org_ModeratePost //
CREATE PROCEDURE Org_ModeratePost(
    IN p_PostId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,
    IN p_ReviewedBy INT UNSIGNED,
    IN p_Action     VARCHAR(10)    -- 'KEEP' or 'REMOVE'
)
BEGIN
    DECLARE v_ResolvedLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ResolvedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'RESOLVED' LIMIT 1;

    UPDATE PostReports
    SET StatusLkpId = v_ResolvedLkpId, ReviewedBy = p_ReviewedBy, ReviewedAt = NOW()
    WHERE PostId = p_PostId;

    IF p_Action = 'REMOVE' THEN
        UPDATE Posts
        SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_ReviewedBy, UpdatedBy = p_ReviewedBy
        WHERE PostId = p_PostId AND OrgId = p_OrgId;
    END IF;

    SELECT 1 AS IsSuccess,
           CASE WHEN p_Action = 'REMOVE' THEN 'Post removed.' ELSE 'Reports cleared.' END AS Message;
END //


-- ── 3.14 Org_GetDashboard ───────────────────────────────────────────────────
-- Full rebuild: correct schema refs + new PendingProjectApplications KPI
-- FIXED: ProjectAttendance has no ProjectId column (route via ProjectSessions)
--        ProjectAttendance has no AttendanceStatus column (use AttendStatusLkpId)
--        ProjectAttendance has no MarkedAt column (use CreatedAt)
-- (Source: NGOConnect_Patch_DashboardProjectApps.sql)
DROP PROCEDURE IF EXISTS Org_GetDashboard //
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedMemberStatusId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
        ) AS TotalMembers,

        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
           AND YEAR(JoinedAt) = YEAR(NOW()) AND MONTH(JoinedAt) = MONTH(NOW())
        ) AS NewMembersThisMonth,

        (SELECT COUNT(DISTINCT pa.UserId)
         FROM ProjectAttendance pa
         JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
         JOIN Projects           p ON ps.ProjectId = p.ProjectId
         JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
         JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId
           AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
           AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ) AS ActiveVolunteers,

        ROUND(CASE
            WHEN (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                  AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0) = 0 THEN 0
            ELSE (SELECT COUNT(DISTINCT pa.UserId)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW()))
                 * 100.0
                 / (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                    AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0)
        END, 1) AS ActiveRatePct,

        COALESCE((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        -- Counts ACTIVE + UPCOMING projects that have NOT expired.
        -- DB status is never auto-transitioned (Hangfire not yet wired), so projects
        -- remain UPCOMING/ACTIVE past their end date. We exclude expired projects using
        -- the same date fields that the mobile isProjectExpired() helper checks:
        --   ONE_TIME  → OneTimeDate < CURDATE()
        --   RECURRING → RecurEnd    < CURDATE()
        --   FLEXIBLE  → FlexToDate  < CURDATE()
        -- Projects with no end date set are treated as not expired.
        (SELECT COUNT(*) FROM Projects p
         JOIN LookupValues lv ON p.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
           AND lt.TypeCode = 'PROJECT_STATUS'
           AND lv.ValueCode IN ('ACTIVE', 'UPCOMING')
           AND NOT (
               (p.OneTimeDate IS NOT NULL AND p.OneTimeDate < CURDATE())
            OR (p.RecurEnd    IS NOT NULL AND p.RecurEnd    < CURDATE())
            OR (p.FlexToDate  IS NOT NULL AND p.FlexToDate  < CURDATE())
           )
        ) AS ActiveProjects,

        (SELECT COUNT(*)
         FROM OrgMembershipRequests mr
         JOIN LookupValues lv ON mr.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE mr.OrgId = p_OrgId AND mr.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingApplications,

        (SELECT COUNT(*)
         FROM ProjectApplications pa
         JOIN Projects    p  ON pa.ProjectId = p.ProjectId
         JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND pa.IsDeleted = 0
           AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingProjectApplications,

        (SELECT FollowerCount FROM Organisations WHERE OrgId = p_OrgId) AS FollowerCount;
END //


-- ── 3.15 Org_GetProfile ─────────────────────────────────────────────────────
-- Updated: added p_UserId param; returns MemberStatusCode (APPROVED/PENDING/NULL)
-- (Source: NGOConnect_Patch_OrgFollow.sql — adds FollowerCount + IsFollowing)
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
        ) AS MemberStatusCode,
        -- Total projects (excl. CANCELLED) — used for the "Projects" stat on the profile header
        (SELECT COUNT(*) FROM Projects p
             JOIN LookupValues sv4 ON p.StatusLkpId = sv4.LookupValueId
             WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
               AND sv4.ValueCode NOT IN ('CANCELLED')) AS TotalProjectCount,
        -- Total volunteer hours logged (ATTENDED only) across all org projects
        COALESCE((SELECT SUM(pa.HoursLogged)
             FROM ProjectAttendance pa
             JOIN ProjectSessions   ps ON pa.SessionId  = ps.SessionId
             JOIN Projects          pr ON ps.ProjectId  = pr.ProjectId
             JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
             JOIN LookupTypes       lt ON lv.LookupTypeId      = lt.LookupTypeId
             WHERE pr.OrgId = o.OrgId
               AND lt.TypeCode = 'ATTENDANCE_STATUS'
               AND lv.ValueCode = 'ATTENDED'
             ), 0) AS TotalVolunteerHours
    FROM Organisations o
    LEFT JOIN OrgDonationSettings ods ON ods.OrgId = o.OrgId
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category
                              AND cv.LookupTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1)
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //


-- ── 3.16 Org_GetMembers ─────────────────────────────────────────────────────
-- Fixed: removed p_PageNumber/p_PageSize (DAL passes only p_OrgId); column aliases match frontend
-- v4.8: added ProfileVerificationStatusCode for verified badge in admin volunteer screen
-- (Source: NGOConnect_Patch_VolunteerSPs.sql)
DROP PROCEDURE IF EXISTS Org_GetMembers //
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId                                     AS MemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)             AS FullName,
        u.Email,
        u.Mobile                                           AS Phone,
        up.ProfilePhoto,
        up.Occupation,
        rv.ValueCode                                       AS RoleCode,
        rv.ValueName                                       AS RoleName,
        sv.ValueCode                                       AS StatusCode,
        sv.ValueName                                       AS StatusName,
        om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay,
        CASE WHEN lsv.ValueCode = 'ALWAYS' OR lsv.ValueCode = 'DURING_SOS' THEN 1 ELSE 0 END AS LocationSharing,
        om.JoinedAt,
        u.IsActive,
        u.LastLoginAt                                      AS LastActiveAt,
        COALESCE(pv.ValueCode, 'PENDING')                  AS ProfileVerificationStatusCode
    FROM OrgMembers om
    JOIN Users        u  ON om.UserId = u.UserId  AND u.IsDeleted  = 0
    JOIN UserProfiles up ON om.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv  ON om.RoleLkpId               = rv.LookupValueId
    LEFT JOIN LookupValues sv  ON om.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues lsv ON om.LocationSharingLkpId    = lsv.LookupValueId
    LEFT JOIN LookupValues pv  ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt ASC;
END //


-- ── 3.17 Org_GetPendingMembers ──────────────────────────────────────────────
-- v4.7 FINAL: MembershipRequestId alias + IFNULL pagination defaults
-- v4.8: added ProfileVerificationStatusCode for verified badge in admin pending tab
DROP PROCEDURE IF EXISTS Org_GetPendingMembers //
CREATE PROCEDURE Org_GetPendingMembers(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_PageSize    INT;
    DECLARE v_PageNumber  INT;
    DECLARE v_PendingLkpId INT UNSIGNED;

    SET v_PageNumber = IFNULL(p_PageNumber, 1);
    SET v_PageSize   = IFNULL(p_PageSize,   100);
    SET v_Offset     = (v_PageNumber - 1) * v_PageSize;

    SELECT LookupValueId INTO v_PendingLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    SELECT
        mr.RequestId   AS MembershipRequestId,
        mr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        up.City,
        up.State,
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.WhyJoin,
        mr.CreatedAt AS RequestedAt,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode
    FROM OrgMembershipRequests mr
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    JOIN Users        u  ON mr.UserId = u.UserId  AND u.IsDeleted  = 0
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE mr.OrgId = p_OrgId
      AND mr.StatusLkpId = v_PendingLkpId
      AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC
    LIMIT v_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM OrgMembershipRequests
    WHERE OrgId = p_OrgId
      AND StatusLkpId = v_PendingLkpId
      AND IsDeleted = 0;
END //


-- ── 3.18 Org_Follow ─────────────────────────────────────────────────────────
-- (Source: NGOConnect_Patch_OrgFollow.sql)
DROP PROCEDURE IF EXISTS Org_Follow //
CREATE PROCEDURE Org_Follow(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsFollowing TINYINT DEFAULT 0;

    SELECT IFNULL(IsFollowing, 0) INTO v_IsFollowing
    FROM OrgFollowers
    WHERE OrgId = p_OrgId AND UserId = p_UserId;

    IF v_IsFollowing = 1 THEN
        SELECT 1 AS IsSuccess, 'Already following.' AS Message;
    ELSE
        INSERT INTO OrgFollowers (OrgId, UserId, IsFollowing, FollowedAt, UnfollowedAt)
        VALUES (p_OrgId, p_UserId, 1, NOW(), NULL)
        ON DUPLICATE KEY UPDATE
            IsFollowing  = 1,
            FollowedAt   = NOW(),
            UnfollowedAt = NULL;

        UPDATE Organisations
        SET FollowerCount = FollowerCount + 1
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Now following.' AS Message;
    END IF;
END //


-- ── 3.19 Org_Unfollow ───────────────────────────────────────────────────────
-- (Source: NGOConnect_Patch_OrgFollow.sql)
DROP PROCEDURE IF EXISTS Org_Unfollow //
CREATE PROCEDURE Org_Unfollow(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsFollowing TINYINT DEFAULT 0;

    SELECT IFNULL(IsFollowing, 0) INTO v_IsFollowing
    FROM OrgFollowers
    WHERE OrgId = p_OrgId AND UserId = p_UserId;

    IF v_IsFollowing = 0 THEN
        SELECT 1 AS IsSuccess, 'Not currently following.' AS Message;
    ELSE
        UPDATE OrgFollowers
        SET IsFollowing  = 0,
            UnfollowedAt = NOW()
        WHERE OrgId = p_OrgId AND UserId = p_UserId;

        UPDATE Organisations
        SET FollowerCount = GREATEST(FollowerCount - 1, 0)
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Unfollowed.' AS Message;
    END IF;
END //


-- ── 3.20 Org_GetFollowedByUser ──────────────────────────────────────────────
-- Returns orgs the user actively follows (IsFollowing=1) where they are NOT
-- already an approved member — those already show in the Linked section.
DROP PROCEDURE IF EXISTS Org_GetFollowedByUser //
CREATE PROCEDURE Org_GetFollowedByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        o.City,
        o.State,
        o.FollowerCount,
        IFNULL((
            SELECT COUNT(*) FROM OrgMembers om2
            JOIN  LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
            JOIN  LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE om2.OrgId    = o.OrgId
              AND om2.IsDeleted = 0
              AND lt2.TypeCode  = 'MEMBER_STATUS'
              AND lv2.ValueCode = 'APPROVED'
        ), 0) AS MemberCount,
        f.FollowedAt
    FROM OrgFollowers f
    JOIN Organisations o ON f.OrgId = o.OrgId AND o.IsDeleted = 0
    WHERE f.UserId      = p_UserId
      AND f.IsFollowing = 1
      -- Exclude orgs where the user is already an active member
      AND NOT EXISTS (
          SELECT 1 FROM OrgMembers om
          JOIN  LookupValues ms ON om.StatusLkpId  = ms.LookupValueId
          JOIN  LookupTypes  mt ON ms.LookupTypeId = mt.LookupTypeId
          WHERE om.OrgId    = o.OrgId
            AND om.UserId   = p_UserId
            AND om.IsDeleted = 0
            AND mt.TypeCode  = 'MEMBER_STATUS'
            AND ms.ValueCode = 'APPROVED'
      )
    ORDER BY f.FollowedAt DESC;
END //

-- ── 3.21 Org_GetVolunteerProfile ────────────────────────────────────────────
-- Updated: adds Bio, VolunteerExp, State, membership request fields
-- NOTE: The impact stats sub-queries in this SP reference pa.AttendanceStatus
-- (a column that does not exist) and pa.ProjectId (ProjectAttendance has no
-- ProjectId column). These sub-queries will return 0 / NULL but will not crash.
-- A future patch should update them to use AttendStatusLkpId and route
-- through ProjectSessions to get ProjectId.
-- (Source: NGOConnect_Patch_VolunteerProfileDetails.sql)
DROP PROCEDURE IF EXISTS Org_GetVolunteerProfile //
CREATE PROCEDURE Org_GetVolunteerProfile(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_ExcusedLkpId  INT UNSIGNED;
    DECLARE v_NoShowLkpId   INT UNSIGNED;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_ExcusedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'EXCUSED' LIMIT 1;

    SELECT LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.City, up.State, up.Occupation, up.ProfilePhoto, up.Bio, up.VolunteerExp,
        IFNULL((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT ps.ProjectId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                JOIN Projects p ON ps.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS OrgCount,
        ROUND(IFNULL((SELECT SUM(CASE WHEN pa.AttendStatusLkpId IN (v_AttendedLkpId, v_ExcusedLkpId) THEN 1 ELSE 0 END)
                            / COUNT(*) * 100
                      FROM ProjectAttendance pa
                      WHERE pa.UserId = p_UserId
                      HAVING COUNT(*) > 0), 100), 2) AS ReliabilityPct,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_NoShowLkpId), 0) AS NoShowCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance WHERE UserId = p_UserId AND AttendStatusLkpId = v_ExcusedLkpId), 0) AS ExcusedCount,
        IFNULL((SELECT COUNT(*) FROM PostReports pr JOIN Posts po ON pr.PostId = po.PostId WHERE po.UserId = p_UserId), 0) AS ComplaintCount,
        lv_role.ValueCode AS RoleCode, lv_role.ValueName AS RoleName,
        lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
        om.CreatedAt AS JoinedAt,
        mr.PrevNgoExperience, mr.VolunteerSkills, mr.AreasOfInterest, mr.WhyJoin,
        mr.CreatedAt AS RequestedAt,
        -- Badges awarded to this volunteer (any org/project) — comma-separated ValueCodes
        (SELECT GROUP_CONCAT(DISTINCT lv_b.ValueCode ORDER BY lv_b.ValueCode SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv_b ON ub.BadgeLkpId = lv_b.LookupValueId
         WHERE  ub.UserId = p_UserId AND ub.IsDeleted = 0) AS AwardedBadgeCodes
    FROM Users u
    JOIN  UserProfiles     up       ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om       ON om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role   ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT JOIN LookupValues lv_status ON lv_status.LookupValueId = om.StatusLkpId
    LEFT JOIN OrgMembershipRequests mr ON mr.RequestId = (
        SELECT RequestId FROM OrgMembershipRequests
        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0
        ORDER BY CreatedAt DESC LIMIT 1
    )
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //


-- ── 3.19 Project_GetSessionQr ───────────────────────────────────────────────
-- Full rebuild: QR time-window enforcement; reads settings from Settings table
-- (Source: NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql)
DROP PROCEDURE IF EXISTS Project_GetSessionQr //
CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_QrCode      VARCHAR(100);
    DECLARE v_ProjectId   INT UNSIGNED;
    DECLARE v_SessionDate DATE;
    DECLARE v_StartTime   TIME;
    DECLARE v_EndTime     TIME;
    DECLARE v_Expiry      INT DEFAULT 60;
    DECLARE v_Buffer      INT DEFAULT 15;
    DECLARE v_WindowStart DATETIME;
    DECLARE v_WindowEnd   DATETIME;
    DECLARE v_NowIST      DATETIME;   -- Railway server is UTC; session times are IST
    DECLARE v_RowsHit     INT DEFAULT 0;

    SELECT ProjectId, SessionDate, StartTime, EndTime
    INTO   v_ProjectId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0 LIMIT 1;

    IF v_SessionDate IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found or already deleted.' AS Message, NULL AS QrToken;
    ELSE
        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Expiry
        FROM Settings WHERE SettingKey = 'QR_EXPIRY_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Expiry IS NULL OR v_Expiry = 0 THEN SET v_Expiry = 60; END IF;

        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
        FROM Settings WHERE SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

        -- Session times are stored in IST (as entered by admin).
        -- Railway MySQL server runs UTC. Convert NOW() to IST for apples-to-apples comparison.
        -- QrExpiresAt is intentionally kept as UTC (DATE_ADD(NOW(),...)) because
        -- Project_CheckIn validates it with NOW() — both UTC, internally consistent.
        SET v_NowIST      = CONVERT_TZ(NOW(), '+00:00', '+05:30');
        SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
        SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

        IF v_NowIST < v_WindowStart THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('QR not yet available. Session starts at ', TIME_FORMAT(v_StartTime, '%h:%i %p'),
                          '. QR opens ', v_Buffer, ' min before start.') AS Message,
                   NULL AS QrToken;
        ELSEIF v_NowIST > v_WindowEnd THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('Session ended at ', TIME_FORMAT(v_EndTime, '%h:%i %p'), '. QR is no longer active.') AS Message,
                   NULL AS QrToken;
        ELSE
            SET v_QrCode = REPLACE(UUID(), '-', '');

            UPDATE ProjectSessions
            SET    QrCode = v_QrCode, QrExpiresAt = DATE_ADD(NOW(), INTERVAL v_Expiry MINUTE),
                   UpdatedBy = p_UserId, UpdatedAt = NOW()
            WHERE  SessionId = p_SessionId AND IsDeleted = 0;

            SET v_RowsHit = ROW_COUNT();

            IF v_RowsHit = 0 THEN
                SELECT 0 AS IsSuccess, 'Failed to stamp QR on session.' AS Message, NULL AS QrToken;
            ELSE
                SELECT 1 AS IsSuccess, 'QR generated.' AS Message, v_QrCode AS QrToken;
            END IF;
        END IF;
    END IF;
END //


-- ── 3.20 Application_GetByProject ──────────────────────────────────────────
-- Full rebuild: joins ProjectAttendance; attendance status overrides application status.
-- v5.0 ADD: AwardedBadgeCodes, HasCertificate columns
-- (Consolidated: QR patch + BadgeAward patch + CertificateIssuance patch)
DROP PROCEDURE IF EXISTS Application_GetByProject //
CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusCode VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_FilterLkpId INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_FilterLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        -- Also try ATTENDANCE_STATUS (ATTENDED, NO_SHOW)
        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId,
        pa.UserId,
        -- CONCAT returns NULL if either part is NULL (unfinished profile).
        -- CONCAT_WS skips NULLs; fall back to phone/email from Users table.
        COALESCE(NULLIF(CONCAT_WS(' ', up.FirstName, up.LastName), ''),
                 u.Mobile, u.Email)             AS ApplicantName,
        up.ProfilePhoto,
        up.City,
        up.Occupation                               AS Profession,
        pa.Motivation,
        pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode)  AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName)  AS Status,
        pa.StatusUpdatedAt,
        pa.CreatedAt,
        DATE_FORMAT(CONVERT_TZ(att.CheckInTime, '+00:00', '+05:30'), '%Y-%m-%dT%H:%i:%s') AS CheckedInAt,
        att.AttendanceId,
        att.HoursLogged,
        att.IsNoShowExcused                         AS IsExcused,
        att.QrScannedAt,
        att.AdminNote,
        ps.SessionDate,
        ps.StartTime   AS SessionStartTime,
        ps.EndTime     AS SessionEndTime,
        -- Badges already awarded to this volunteer on this project (comma-separated ValueCodes)
        (SELECT GROUP_CONCAT(lv2.ValueCode ORDER BY ub.CreatedAt SEPARATOR ',')
         FROM   UserBadges ub
         JOIN   LookupValues lv2 ON ub.BadgeLkpId = lv2.LookupValueId
         WHERE  ub.UserId     = pa.UserId
           AND  ub.ProjectId  = pa.ProjectId
           AND  ub.IsDeleted  = 0
        )                                           AS AwardedBadgeCodes,
        -- Whether a certificate has already been issued for this volunteer on this project
        IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc2
                  WHERE vc2.ProjectId = pa.ProjectId
                    AND vc2.UserId    = pa.UserId
                    AND vc2.IsDeleted = 0), 1, 0)   AS HasCertificate
    FROM   ProjectApplications pa
    JOIN   UserProfiles up   ON pa.UserId        = up.UserId AND up.IsDeleted = 0
    JOIN   Users u           ON u.UserId         = pa.UserId
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    -- Most-recent attendance record for this user on this project
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    LEFT JOIN LookupValues   attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps   ON ps.SessionId          = att.SessionId
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           )
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications pa
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId
        FROM   ProjectAttendance att2
        JOIN   ProjectSessions   ps2 ON att2.SessionId = ps2.SessionId
        WHERE  att2.UserId     = pa.UserId
          AND  ps2.ProjectId   = pa.ProjectId
          AND  ps2.IsDeleted   = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC
        LIMIT  1
    )
    WHERE  pa.ProjectId = p_ProjectId
      AND  pa.IsDeleted = 0
      AND  (
            v_FilterLkpId IS NULL
            OR pa.StatusLkpId        = v_FilterLkpId
            OR att.AttendStatusLkpId = v_FilterLkpId
           );
END //


-- ── 3.21 Project_ManualAttendance ───────────────────────────────────────────
-- v5.0 UPDATED: auto-creates a session from project schedule if none exists,
-- so admin can mark attendance on completed projects that never used QR.
-- v5.0 VALIDATION: rejects CANCELLED/EXPIRED projects; enforces QR_BUFFER_MINUTES
-- time window for ACTIVE/UPCOMING projects (same window as QR scan and SelfCheckIn);
-- COMPLETED projects have no time restriction (post-session admin cleanup).
DROP PROCEDURE IF EXISTS Project_ManualAttendance //
CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId             INT UNSIGNED;
    DECLARE v_ProjectId          INT UNSIGNED;
    DECLARE v_CurrentStatus      VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ProjectStatus      VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ScheduleTypeCode   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_SessionId          INT UNSIGNED;
    DECLARE v_AttendedLkpId      INT UNSIGNED;
    DECLARE v_SessionStatusLkpId INT UNSIGNED;
    DECLARE v_HoursLogged        DECIMAL(4,2);
    DECLARE v_SessionDate        DATE         DEFAULT NULL;
    DECLARE v_StartTime          TIME         DEFAULT NULL;
    DECLARE v_EndTime            TIME         DEFAULT NULL;
    DECLARE v_MaxVol             INT UNSIGNED DEFAULT 0;
    DECLARE v_OneTimeDate        DATE         DEFAULT NULL;
    DECLARE v_RecurStart         DATE         DEFAULT NULL;
    DECLARE v_RecurEnd           DATE         DEFAULT NULL;
    DECLARE v_RecurDays          VARCHAR(200) DEFAULT NULL;
    DECLARE v_FlexFromDate       DATE         DEFAULT NULL;
    DECLARE v_FlexToDate         DATE         DEFAULT NULL;
    DECLARE v_Buffer             INT          DEFAULT 15;
    DECLARE v_NowIST             DATETIME;
    DECLARE v_TodayIST           DATE;
    DECLARE v_WindowStart        DATETIME;
    DECLARE v_WindowEnd          DATETIME;
    DECLARE v_ValidationError    VARCHAR(300) DEFAULT NULL;

    -- Single join: application + project status + schedule fields
    SELECT pa.UserId, pa.ProjectId, appSv.ValueCode,
           projSv.ValueCode, ptv.ValueCode,
           p.SessionStartTime, p.SessionEndTime,
           p.OneTimeDate, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate,
           COALESCE(p.MaxVolunteers, 0)
    INTO   v_UserId, v_ProjectId, v_CurrentStatus,
           v_ProjectStatus, v_ScheduleTypeCode,
           v_StartTime, v_EndTime,
           v_OneTimeDate, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFromDate, v_FlexToDate,
           v_MaxVol
    FROM   ProjectApplications pa
    JOIN   Projects p            ON pa.ProjectId       = p.ProjectId
    JOIN   LookupValues appSv    ON pa.StatusLkpId     = appSv.LookupValueId
    JOIN   LookupValues projSv   ON p.StatusLkpId      = projSv.LookupValueId
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0 LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;
    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;
    ELSE
        -- ── Project-state & time-window validation ───────────────────────────
        IF v_ProjectStatus IN ('CANCELLED', 'EXPIRED') THEN
            SET v_ValidationError = CONCAT('Cannot mark attendance: project is ', v_ProjectStatus, '.');

        ELSEIF v_ProjectStatus IN ('ACTIVE', 'UPCOMING', 'CLOSING') THEN
            -- Resolve today's session date in IST
            SET v_NowIST   = CONVERT_TZ(NOW(), '+00:00', '+05:30');
            SET v_TodayIST = DATE(v_NowIST);

            IF v_ScheduleTypeCode = 'ONE_TIME' THEN
                IF v_TodayIST = v_OneTimeDate THEN
                    SET v_SessionDate = v_OneTimeDate;
                END IF;
            ELSEIF v_ScheduleTypeCode = 'RECURRING' THEN
                IF v_TodayIST BETWEEN v_RecurStart AND v_RecurEnd
                   AND FIND_IN_SET(LEFT(UPPER(DAYNAME(v_TodayIST)), 3),
                                   UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;
            ELSEIF v_ScheduleTypeCode = 'FLEXIBLE' THEN
                IF v_TodayIST BETWEEN v_FlexFromDate AND v_FlexToDate THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;
            END IF;

            IF v_SessionDate IS NULL THEN
                SET v_ValidationError = 'There is no scheduled session for today.';
            ELSE
                -- Read buffer from Settings (default 15 min, same as QR)
                SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
                FROM   Settings WHERE SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;
                IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

                SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
                SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

                IF v_NowIST < v_WindowStart THEN
                    SET v_ValidationError = CONCAT('Attendance window opens at ',
                        TIME_FORMAT(TIME(v_WindowStart), '%h:%i %p'),
                        '. Please try after the session begins.');
                ELSEIF v_NowIST > v_WindowEnd THEN
                    SET v_ValidationError = CONCAT('Session ended at ',
                        TIME_FORMAT(v_EndTime, '%h:%i %p'),
                        '. The attendance window is now closed.');
                END IF;
            END IF;
        END IF;
        -- COMPLETED projects: no time restriction — v_ValidationError stays NULL

        IF v_ValidationError IS NOT NULL THEN
            SELECT 0 AS IsSuccess, v_ValidationError AS Message;
        ELSE
            -- Find latest past session; auto-create from project schedule if none exists
            SELECT ps.SessionId,
                   ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
            INTO   v_SessionId, v_HoursLogged
            FROM   ProjectSessions ps
            WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
            ORDER BY ps.SessionDate DESC LIMIT 1;

            IF v_SessionId IS NULL THEN
                -- No session exists — create one from project schedule fields already fetched
                SET v_SessionDate = COALESCE(v_OneTimeDate, v_RecurStart, v_FlexFromDate, CURDATE());
                IF v_StartTime IS NULL THEN SET v_StartTime = '09:00:00'; END IF;
                IF v_EndTime   IS NULL THEN SET v_EndTime   = '17:00:00'; END IF;

                SELECT lv.LookupValueId INTO v_SessionStatusLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

                INSERT INTO ProjectSessions
                    (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
                VALUES
                    (v_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_MaxVol, v_SessionStatusLkpId, p_MarkedBy);

                SET v_SessionId   = LAST_INSERT_ID();
                SET v_HoursLogged = GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, v_StartTime, v_EndTime) / 60.0, 2), 0.5);
            END IF;

            SELECT lv.LookupValueId INTO v_AttendedLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

            INSERT INTO ProjectAttendance
                (SessionId, UserId, CheckInTime, HoursLogged, QrScannedAt,
                 AttendStatusLkpId, AdminNote, CreatedBy)
            VALUES
                (v_SessionId, v_UserId, NOW(), v_HoursLogged, NULL,
                 v_AttendedLkpId, 'Manually marked as attended by admin.', p_MarkedBy)
            ON DUPLICATE KEY UPDATE
                AttendStatusLkpId = v_AttendedLkpId,
                CheckInTime       = NOW(),
                HoursLogged       = v_HoursLogged,
                QrScannedAt       = NULL,
                AdminNote         = 'Manually marked as attended by admin.',
                UpdatedBy         = p_MarkedBy,
                UpdatedAt         = NOW();

            SELECT 1 AS IsSuccess, 'Volunteer marked as attended.' AS Message,
                   v_UserId AS UserId, v_ProjectId AS ProjectId;
        END IF;
    END IF;
END //


-- ── 3.22 Project_AddSession ─────────────────────────────────────────────────
-- Updated: duplicate guard prevents two sessions for same project+date
-- (Source: NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql)
DROP PROCEDURE IF EXISTS Project_AddSession //
CREATE PROCEDURE Project_AddSession(
    IN p_ProjectId     INT UNSIGNED,
    IN p_SessionDate   DATE,
    IN p_StartTime     TIME,
    IN p_EndTime       TIME,
    IN p_MaxVolunteers INT UNSIGNED,
    IN p_CreatedBy     INT UNSIGNED
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_ExistingId  INT UNSIGNED DEFAULT NULL;

    SELECT SessionId INTO v_ExistingId
    FROM ProjectSessions
    WHERE ProjectId = p_ProjectId AND SessionDate = p_SessionDate AND IsDeleted = 0 LIMIT 1;

    IF v_ExistingId IS NOT NULL THEN
        SELECT 0 AS IsSuccess, 'A session already exists for this date.' AS Message, v_ExistingId AS SessionId;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

        INSERT INTO ProjectSessions
            (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
        VALUES
            (p_ProjectId, p_SessionDate, p_StartTime, p_EndTime, p_MaxVolunteers, v_StatusLkpId, p_CreatedBy);

        SELECT 1 AS IsSuccess, 'Session added.' AS Message, LAST_INSERT_ID() AS SessionId;
    END IF;
END //


-- ── 3.23 Project_GetSessions ────────────────────────────────────────────────
-- Updated: DATE_FORMAT for SessionDate to prevent .NET DateTime timezone shift
-- (Source: NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql)
DROP PROCEDURE IF EXISTS Project_GetSessions //
CREATE PROCEDURE Project_GetSessions(
    IN p_ProjectId  INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        ps.SessionId,
        DATE_FORMAT(ps.SessionDate, '%Y-%m-%d') AS SessionDate,
        ps.StartTime, ps.EndTime, ps.MaxVolunteers,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        ps.QrCode, ps.QrExpiresAt
    FROM ProjectSessions ps
    LEFT JOIN LookupValues sv ON ps.SessionStatusLkpId = sv.LookupValueId
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER BY ps.SessionDate ASC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;
END //


-- ── 3.24 Post_GetFeed ───────────────────────────────────────────────────────
-- v4.7 FINAL: merged 4-param (p_UserId, p_OrgId, p_PageNumber, p_PageSize)
--             + IsFollowing per post + OrgId filter
-- Supersedes: NGOConnect_Patch_PostFeed_OrgFilter.sql + NGOConnect_Patch_OrgFollow.sql
DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,   -- NULL = all orgs | non-null = filter to one org
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,
        p.LikeCount,
        p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLiked,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1
                THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up          ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o       ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type  ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm           ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt    ON lv_mt.LookupValueId   = pm.MediaTypeLkpId
    LEFT JOIN LookupValues lv_vis   ON lv_vis.LookupValueId  = p.VisibilityLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      -- Visibility enforcement
      AND (
          lv_vis.ValueCode IS NULL OR lv_vis.ValueCode = 'PUBLIC'
          OR (lv_vis.ValueCode = 'ORG_MEMBERS'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_v
                  JOIN LookupValues lv_s ON om_v.StatusLkpId = lv_s.LookupValueId
                  WHERE om_v.OrgId = p.OrgId AND om_v.UserId = p_UserId
                    AND om_v.IsDeleted = 0 AND lv_s.ValueCode = 'APPROVED'
              ))
          OR (lv_vis.ValueCode = 'FOLLOWERS'
              AND EXISTS (
                  SELECT 1 FROM OrgFollowers of_v
                  WHERE of_v.OrgId = p.OrgId AND of_v.UserId = p_UserId AND of_v.IsFollowing = 1
              ))
      )
    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount, p.ViewCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,   lv_vis.ValueCode, p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    LEFT JOIN LookupValues lv_vis ON lv_vis.LookupValueId = p.VisibilityLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      AND (
          lv_vis.ValueCode IS NULL OR lv_vis.ValueCode = 'PUBLIC'
          OR (lv_vis.ValueCode = 'ORG_MEMBERS'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_v
                  JOIN LookupValues lv_s ON om_v.StatusLkpId = lv_s.LookupValueId
                  WHERE om_v.OrgId = p.OrgId AND om_v.UserId = p_UserId
                    AND om_v.IsDeleted = 0 AND lv_s.ValueCode = 'APPROVED'
              ))
          OR (lv_vis.ValueCode = 'FOLLOWERS'
              AND EXISTS (
                  SELECT 1 FROM OrgFollowers of_v
                  WHERE of_v.OrgId = p.OrgId AND of_v.UserId = p_UserId AND of_v.IsFollowing = 1
              ))
      );
END //


-- ── 3.25 Post_Create ────────────────────────────────────────────────────────
-- Updated: auto-detects VIDEO vs IMAGE from URL extension via REGEXP
-- Updated: enforces CanPost + MaxPostsPerDay from OrgMembers (Permission Enforcement patch)
-- (Source: NGOConnect_Patch_PostFeed_VideoSupport.sql + NGOConnect_Patch_PermissionEnforcement.sql)
DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanPost          TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay        INT         DEFAULT 10;
    DECLARE v_TodayCount       INT         DEFAULT 0;
    DECLARE v_ImageTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_VideoTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultTypeLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve APPROVED status LkpId
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Load member's posting permission
    SELECT om.CanPost, om.MaxPostsPerDay INTO v_CanPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanPost = 0 THEN
        SELECT 0 AS IsSuccess,
               'You do not have permission to post in this organisation.' AS Message,
               NULL AS PostId;
    ELSE
        -- Count today's posts for daily limit check
        SELECT COUNT(*) INTO v_TodayCount
        FROM   Posts
        WHERE  UserId = p_UserId AND OrgId = p_OrgId
          AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

        IF v_MaxPerDay > 0 AND v_TodayCount >= v_MaxPerDay THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('Daily post limit of ', v_MaxPerDay, ' reached.') AS Message,
                   NULL AS PostId;
        ELSE
            IF p_PostTypeLkpId IS NULL THEN
                SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
                SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
            END IF;

            INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
            VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

            SET @NewPostId = LAST_INSERT_ID();

            IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN
                SELECT lv.LookupValueId INTO v_ImageTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

                SELECT lv.LookupValueId INTO v_VideoTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'VIDEO' LIMIT 1;

                IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;
                IF v_VideoTypeLkpId = 0 THEN SET v_VideoTypeLkpId = v_ImageTypeLkpId; END IF;

                INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
                SELECT
                    @NewPostId,
                    TRIM(j.val),
                    CASE WHEN LOWER(TRIM(j.val)) REGEXP '\\.(mp4|mov|avi|mkv|webm|m4v|3gp|wmv)$'
                         THEN v_VideoTypeLkpId ELSE v_ImageTypeLkpId END,
                    j.rn
                FROM JSON_TABLE(
                    CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
                    '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')
                ) AS j
                WHERE TRIM(j.val) != '';
            END IF;

            SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
        END IF;
    END IF;
END //


-- ── Post_GetPermissions ──────────────────────────────────────────────────────
-- Returns one row: membership status + all posting permissions + today's post count.
-- Always returns exactly one row regardless of membership state (uses DECLARE defaults).
-- Used by mobile before opening Create Post / Comment / Community Post to enforce rules.
-- Updated: added CanComment + CanCommunityPost columns (Permission Enforcement patch)
DELIMITER //
DROP PROCEDURE IF EXISTS Post_GetPermissions //
CREATE PROCEDURE Post_GetPermissions(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember         TINYINT(1)  DEFAULT 0;
    DECLARE v_CanPost          TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment       TINYINT(1)  DEFAULT 1;  -- non-members can comment freely; only blocked when member has CanComment=0
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay        INT         DEFAULT 10;
    DECLARE v_TodayCount       INT         DEFAULT 0;

    -- Resolve APPROVED status lookup id
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Load member's permissions (only if APPROVED member)
    SELECT 1, om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay
    INTO   v_IsMember, v_CanPost, v_CanComment, v_CanCommunityPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    -- Count posts created today for this org
    SELECT COUNT(*) INTO v_TodayCount
    FROM   Posts
    WHERE  UserId = p_UserId AND OrgId = p_OrgId
      AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

    SELECT
        v_IsMember          AS IsMember,
        v_CanPost           AS CanPost,
        v_CanComment        AS CanComment,
        v_CanCommunityPost  AS CanCommunityPost,
        v_MaxPerDay         AS MaxPostsPerDay,
        v_TodayCount        AS TodayPostCount;
END //
DELIMITER ;

-- ── 3.26 User_GetMyOrgs ─────────────────────────────────────────────────────
-- Final patch: UNION of approved (OrgMembers) + pending (OrgMembershipRequests)
-- Returns MemberStatusCode and OrgStatusCode correctly for MyOrgsScreen filter
-- (Source: NGOConnect_Patch_UserGetMyOrgs_Final.sql)
DELIMITER //
DROP PROCEDURE IF EXISTS User_GetMyOrgs //
CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- Approved memberships (includes REJECTED orgs where founder must resubmit)
    SELECT
        o.OrgId, o.OrgName, o.LogoUrl,
        ot.ValueName AS OrgType, o.City, o.State,
        COALESCE(rv.ValueName, 'Member') AS Role,
        COALESCE(rv.ValueCode, 'MEMBER') AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        om.CreatedAt AS JoinedAt,
        sv.ValueCode AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode,
        (SELECT h.Reason FROM OrgStatusHistory h
         JOIN LookupValues hv ON h.NewStatusLkpId = hv.LookupValueId
         JOIN LookupTypes  ht ON hv.LookupTypeId  = ht.LookupTypeId
         WHERE h.OrgId = o.OrgId AND ht.TypeCode = 'ORG_STATUS' AND hv.ValueCode = 'REJECTED'
         ORDER BY h.CreatedAt DESC LIMIT 1
        ) AS RejectionReason,
        (SELECT h.CreatedAt FROM OrgStatusHistory h
         JOIN LookupValues hv ON h.NewStatusLkpId = hv.LookupValueId
         JOIN LookupTypes  ht ON hv.LookupTypeId  = ht.LookupTypeId
         WHERE h.OrgId = o.OrgId AND ht.TypeCode = 'ORG_STATUS' AND hv.ValueCode = 'SUSPENDED'
         ORDER BY h.CreatedAt DESC LIMIT 1
        ) AS SuspendedAt
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN LookupValues rv ON om.RoleLkpId   = rv.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE om.UserId = p_UserId AND om.IsDeleted = 0 AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- Pending join requests
    SELECT
        o.OrgId, o.OrgName, o.LogoUrl,
        ot.ValueName AS OrgType, o.City, o.State,
        'Member' AS Role, 'MEMBER' AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        mr.CreatedAt AS JoinedAt,
        'PENDING' AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode,
        NULL AS RejectionReason,
        NULL AS SuspendedAt
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId       = o.OrgId  AND o.IsDeleted = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId
    LEFT JOIN LookupValues os ON o.StatusLkpId  = os.LookupValueId
    LEFT JOIN LookupValues ot ON o.OrgTypeLkpId = ot.LookupValueId
    WHERE mr.UserId = p_UserId AND mr.IsDeleted = 0 AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;
END //


DELIMITER ;

-- ============================================================
-- END OF v4.5 ADDITIONS
-- NGOConnect v4.4 — 52 Tables, 132 Stored Procedures
-- ============================================================


-- ============================================================
-- v4.5 ADDITIONS — SUPER ADMIN MODULE
-- New tables + brand-new SPs only. Zero changes to any existing
-- table or SP — isolated so this module cannot regress
-- mobile/NGO-admin flows.
-- Source: NGOConnect_Patch_SuperAdminModule.sql
-- ============================================================

CREATE TABLE SuperAdminUsers (
    SuperAdminUserId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Username         VARCHAR(100)  NOT NULL,
    PasswordHash     VARCHAR(255)  NOT NULL,
    FullName         VARCHAR(150)  NOT NULL,
    Email            VARCHAR(150)  NULL,
    IsActive         TINYINT(1)    NOT NULL DEFAULT 1,
    LastLoginAt      DATETIME      NULL,
    CreatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SuperAdminUserId),
    UNIQUE KEY uq_superadmin_username (Username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgStatusHistory (
    OrgStatusHistoryId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId              INT UNSIGNED  NOT NULL,
    OldStatusLkpId     INT UNSIGNED  NULL,
    NewStatusLkpId     INT UNSIGNED  NOT NULL,
    Reason             TEXT          NULL,
    ChangedByType      VARCHAR(20)   NOT NULL COMMENT 'SUPER_ADMIN or FOUNDER',
    ChangedBy          INT UNSIGNED  NOT NULL COMMENT 'SuperAdminUserId or UserId depending on ChangedByType',
    CreatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (OrgStatusHistoryId),
    INDEX idx_orgstatushist_org (OrgId, CreatedAt DESC),
    CONSTRAINT fk_orgstatushist_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed one default Super Admin.
--   Username: gaurav.admin
--   Password: NgoConnect@2026   <-- CHANGE IMMEDIATELY AFTER FIRST LOGIN
INSERT INTO SuperAdminUsers (Username, PasswordHash, FullName, Email, IsActive)
VALUES ('gaurav.admin', '$2b$11$bL6esk4WXdAWUxFp7H56PeGqxyXoIQO0CgVyt98K.1rwSJEH3Es5S', 'Gaurav Shukla', 'gauravshukla1409@gmail.com', 1);

DELIMITER //

CREATE PROCEDURE SuperAdmin_GetByUsername(IN p_Username VARCHAR(100))
BEGIN
    SELECT SuperAdminUserId, Username, PasswordHash, FullName, Email, IsActive
    FROM SuperAdminUsers
    WHERE Username = p_Username
    LIMIT 1;
END //

CREATE PROCEDURE SuperAdmin_UpdateLastLogin(IN p_SuperAdminUserId INT UNSIGNED)
BEGIN
    UPDATE SuperAdminUsers SET LastLoginAt = NOW() WHERE SuperAdminUserId = p_SuperAdminUserId;
    SELECT 1 AS IsSuccess, 'Login recorded.' AS Message;
END //

CREATE PROCEDURE SuperAdmin_Org_GetList(
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.Category, o.City, o.State, o.LogoUrl,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode
    ORDER BY o.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.IsDeleted = 0 AND sv.ValueCode = p_StatusCode;
END //

CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.RegistrationDate, o.Category, o.ContactPerson,
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

CREATE PROCEDURE SuperAdmin_Org_GetDocuments(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT od.OrgDocumentId, od.DocumentTypeLkpId, dt.ValueName AS DocumentType,
           od.FileUrl, od.FileName, od.IsVerified, od.VerifiedAt, od.VerifiedBy,
           od.CreatedAt
    FROM OrgDocuments od
    LEFT JOIN LookupValues dt ON od.DocumentTypeLkpId = dt.LookupValueId
    WHERE od.OrgId = p_OrgId AND od.IsDeleted = 0
    ORDER BY od.CreatedAt ASC;
END //

CREATE PROCEDURE SuperAdmin_OrgDocument_Verify(
    IN p_OrgDocumentId  INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsVerified     TINYINT(1)
)
BEGIN
    UPDATE OrgDocuments
    SET IsVerified = p_IsVerified,
        VerifiedAt = NOW(),
        VerifiedBy = p_SuperAdminUserId
    WHERE OrgDocumentId = p_OrgDocumentId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document verification updated.' AS Message;
    END IF;
END //

-- v5.1 MODIFIED: +p_IsNonRegistered param; sets IsNonRegistered on Organisations on approval
-- v5.1 MODIFIED: +p_Remarks param; stored in OrgStatusHistory.Reason + included in notification body
CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 0 = registered, 1 = non-registered
    IN p_Remarks          VARCHAR(1000)  -- optional admin remarks shown to org admins
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW', 'RESUBMITTED') THEN
        -- v5.2: RESUBMITTED added — org resubmitted after a Request-Update on an
        -- already-approved org (see SuperAdmin_Org_RequestUpdate / Org_Resubmit).
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        -- Build history reason: combine non-registered flag + optional remarks
        SET v_Reason = IF(v_CurrentCode = 'RESUBMITTED',
                           'Re-approved after resubmission',
                           IF(p_IsNonRegistered = 1, 'Approved as non-registered organisation', 'Approved'));
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_Reason = CONCAT(v_Reason, '. ', TRIM(p_Remarks));
        END IF;

        -- Build notification body
        SET v_NotifBody = 'Congratulations — your organisation is now live on Ripple Hub.';
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_NotifBody = CONCAT(v_NotifBody, ' Note from admin: ', TRIM(p_Remarks));
        END IF;

        UPDATE Organisations
        SET StatusLkpId     = v_ApprovedId,
            IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, v_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved', v_NotifBody, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

-- v5.1 NEW: toggle IsNonRegistered on any org (including already-approved orgs) with optional remarks
CREATE PROCEDURE SuperAdmin_Org_SetNonRegistered(
    IN p_OrgId            INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 1 = non-registered, 0 = registered
    IN p_Remarks          VARCHAR(1000), -- optional admin remarks shown to org admins
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_RegNumber       VARCHAR(100);
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifTitle      VARCHAR(200);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT StatusLkpId, RegNumber INTO v_CurrentStatusId, v_RegNumber
    FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    -- v5.2: block flipping to Registered (IsNonRegistered=0) while RegNumber is
    -- blank — previously the SP let this through since it only ever toggled the
    -- flag, never checked the field it's supposed to represent.
    ELSEIF IFNULL(p_IsNonRegistered, 0) = 0 AND (v_RegNumber IS NULL OR TRIM(v_RegNumber) = '') THEN
        SELECT 0 AS IsSuccess, 'Cannot mark as registered — a Registration Number is required first. Add it via Edit Organisation, then try again.' AS Message;
    ELSE
        -- Build history reason
        SET v_Reason = IF(p_IsNonRegistered = 1, 'Marked as non-registered', 'Marked as registered');
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_Reason = CONCAT(v_Reason, '. ', TRIM(p_Remarks));
        END IF;

        -- Build notification
        SET v_NotifTitle = IF(p_IsNonRegistered = 1,
            'Organisation Marked as Non-Registered',
            'Organisation Registration Status Updated');
        SET v_NotifBody = IF(p_IsNonRegistered = 1,
            'Your organisation has been classified as non-registered by the platform admin.',
            'Your organisation registration status has been updated by the platform admin.');
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_NotifBody = CONCAT(v_NotifBody, ' Note from admin: ', TRIM(p_Remarks));
        END IF;

        UPDATE Organisations
        SET IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId AND IsDeleted = 0;

        -- Record in history (status unchanged — OldId = NewId = current status)
        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_CurrentStatusId, v_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        -- Notify founder
        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        SELECT om.UserId, 'ORG_STATUS_UPDATE', v_NotifTitle, v_NotifBody, p_OrgId, 'ORGANISATION'
        FROM OrgMembers om
        JOIN LookupValues lv ON om.RoleLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
          AND lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER'
        LIMIT 1;

        SELECT 1 AS IsSuccess,
               IF(p_IsNonRegistered = 1,
                  'Organisation marked as non-registered.',
                  'Organisation marked as registered.') AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reject(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_RejectedId      INT UNSIGNED;
    DECLARE v_CancelledId     INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    -- v5.2: rejection is now also allowed from APPROVED (previously blocked) so
    -- Super Admin can revoke an already-live org. When coming from APPROVED, the
    -- org's active/upcoming/draft projects are cascade-cancelled below — see
    -- DOCUMENTATION_GUIDELINES.md 2026-08-26 "Reject an approved org" entry.
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW', 'APPROVED', 'NEEDS_UPDATE', 'RESUBMITTED') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reject — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A rejection reason is required.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_RejectedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'REJECTED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_RejectedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        -- v5.2: cascade-cancel this org's live projects when it was previously
        -- APPROVED (a PENDING/UNDER_REVIEW/NEEDS_UPDATE/RESUBMITTED org cannot
        -- have had approved projects, since project creation is gated on
        -- ORG_STATUS = APPROVED).
        IF v_CurrentCode = 'APPROVED' THEN
            SELECT LookupValueId INTO v_CancelledId FROM LookupValues lv
                JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

            UPDATE Projects p
            JOIN LookupValues sv2 ON p.StatusLkpId = sv2.LookupValueId
            SET p.StatusLkpId  = v_CancelledId,
                p.CancelledAt  = NOW(),
                p.CancelledBy  = p_SuperAdminUserId,
                p.CancelReason = 'Organisation rejected by Super Admin'
            WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
              AND sv2.ValueCode IN ('DRAFT', 'ACTIVE', 'UPCOMING');
        END IF;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_RejectedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_REJECTED', 'Your NGO registration needs changes',
                    p_Reason, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation rejected.' AS Message;
    END IF;
END //

-- v5.2 NEW: soft version of Reject for an already-APPROVED org — asks the founder
-- to fix something without a full reject/re-review cycle. Org drops out of public
-- listings while NEEDS_UPDATE (StatusLkpId gates visibility for orgs), same as
-- REJECTED, but Org_Resubmit routes it to RESUBMITTED (not back through PENDING)
-- so Super Admin can re-approve directly via SuperAdmin_Org_Approve.
CREATE PROCEDURE SuperAdmin_Org_RequestUpdate(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_NeedsUpdateId   INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'APPROVED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot request update — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_NeedsUpdateId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'NEEDS_UPDATE' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_NeedsUpdateId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_NeedsUpdateId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_UPDATE_REQUIRED', 'Update required for your organisation',
                    p_Reason, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Update requested from organisation.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Suspend(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_SuspendedId     INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'APPROVED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot suspend — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_SuspendedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'SUSPENDED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_SuspendedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_SuspendedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation suspended.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reactivate(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'SUSPENDED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reactivate — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation reactivated.' AS Message;
    END IF;
END //

-- v5.1 MODIFIED: +p_RegistrationNo, +p_IsNonRegistered so founder can correct registration status on resubmit
CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId          INT UNSIGNED,
    IN p_UserId         INT UNSIGNED,
    IN p_OrgName        VARCHAR(200),
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
    IN p_Country        VARCHAR(100),
    IN p_RegistrationNo VARCHAR(100),
    IN p_IsNonRegistered  TINYINT(1),
    IN p_Is80GEligible    TINYINT(1),
    IN p_Is12AEligible    TINYINT(1),
    IN p_RegistrationDate DATE                                    -- NULL when IsNonRegistered = 1
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_TargetId        INT UNSIGNED;
    DECLARE v_TargetCode      VARCHAR(50);
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
    ELSEIF v_CurrentCode NOT IN ('REJECTED', 'NEEDS_UPDATE') THEN
        SELECT 0 AS IsSuccess, 'Only a rejected organisation, or one flagged as needing an update, can be resubmitted.' AS Message;
    ELSE
        -- v5.2: REJECTED goes back through full review (PENDING); NEEDS_UPDATE
        -- (raised via SuperAdmin_Org_RequestUpdate on an already-approved org)
        -- goes to RESUBMITTED so Super Admin can re-approve directly without
        -- re-running the full PENDING/UNDER_REVIEW review flow.
        SET v_TargetCode = IF(v_CurrentCode = 'NEEDS_UPDATE', 'RESUBMITTED', 'PENDING');

        SELECT LookupValueId INTO v_TargetId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = v_TargetCode LIMIT 1;

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
            StatusLkpId = v_TargetId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_TargetId,
                IF(v_CurrentCode = 'NEEDS_UPDATE', 'Resubmitted by founder after update request', 'Resubmitted by founder after rejection'),
                'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_GetList()
BEGIN
    SELECT lt.LookupTypeId, lt.TypeCode, lt.TypeName, lt.Description, lt.IsSystemType,
        (SELECT COUNT(*) FROM LookupValues lv WHERE lv.LookupTypeId = lt.LookupTypeId AND lv.IsDeleted = 0) AS ValueCount
    FROM LookupTypes lt
    WHERE lt.IsDeleted = 0
    ORDER BY lt.TypeName;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_GetByType(IN p_LookupTypeId INT UNSIGNED)
BEGIN
    SELECT LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, IsDeleted
    FROM LookupValues
    WHERE LookupTypeId = p_LookupTypeId
    ORDER BY OrderNo, ValueName;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Add(
    IN p_TypeCode         VARCHAR(50),
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupTypes WHERE TypeCode = p_TypeCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A lookup type with this code already exists.' AS Message, NULL AS LookupTypeId;
    ELSE
        INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
        VALUES (p_TypeCode, p_TypeName, p_Description, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup type created.' AS Message, LAST_INSERT_ID() AS LookupTypeId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Update(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    UPDATE LookupTypes
    SET TypeName = p_TypeName, Description = p_Description, UpdatedBy = p_SuperAdminUserId
    WHERE LookupTypeId = p_LookupTypeId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Lookup type not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Lookup type updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Add(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_ValueCode        VARCHAR(50),
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupValues
        WHERE LookupTypeId = p_LookupTypeId AND ValueCode = p_ValueCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A value with this code already exists for this type.' AS Message, NULL AS LookupValueId;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = p_LookupTypeId;
        END IF;

        INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, CreatedBy)
        VALUES (p_LookupTypeId, p_ValueCode, p_ValueName, p_Description, p_OrderNo, p_IsDefault, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup value created.' AS Message, LAST_INSERT_ID() AS LookupValueId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Update(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_LookupTypeId INT UNSIGNED;
    SELECT LookupTypeId INTO v_LookupTypeId FROM LookupValues WHERE LookupValueId = p_LookupValueId AND IsDeleted = 0;

    IF v_LookupTypeId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = v_LookupTypeId;
        END IF;

        UPDATE LookupValues
        SET ValueName = p_ValueName, Description = p_Description, OrderNo = p_OrderNo,
            IsDefault = p_IsDefault, UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, 'Lookup value updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_SetActive(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_IsActive         TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsSystemValue TINYINT(1);
    SELECT IsSystemValue INTO v_IsSystemValue FROM LookupValues WHERE LookupValueId = p_LookupValueId;

    IF v_IsSystemValue IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSEIF v_IsSystemValue = 1 AND p_IsActive = 0 THEN
        SELECT 0 AS IsSuccess, 'System values cannot be deactivated — they are referenced by platform logic.' AS Message;
    ELSE
        UPDATE LookupValues
        SET IsDeleted = IF(p_IsActive = 1, 0, 1),
            DeletedAt = IF(p_IsActive = 1, NULL, NOW()),
            DeletedBy = IF(p_IsActive = 1, NULL, p_SuperAdminUserId),
            UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, IF(p_IsActive = 1, 'Lookup value reactivated.', 'Lookup value deactivated.') AS Message;
    END IF;
END //


-- ── v4.6 NEW SPs ──────────────────────────────────────────────────────

CREATE PROCEDURE SuperAdmin_Org_GetStatusHistory(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        h.OrgStatusHistoryId,
        oldv.ValueCode AS OldStatus,  oldv.ValueName AS OldStatusName,
        newv.ValueCode AS NewStatus,  newv.ValueName AS NewStatusName,
        h.Reason, h.ChangedByType, h.ChangedBy, h.CreatedAt
    FROM OrgStatusHistory h
    LEFT JOIN LookupValues oldv ON h.OldStatusLkpId = oldv.LookupValueId
    JOIN  LookupValues newv ON h.NewStatusLkpId  = newv.LookupValueId
    WHERE h.OrgId = p_OrgId
    ORDER BY h.CreatedAt DESC;
END //

-- v4.7 FIX: LEFT JOIN so new users (no org) appear; HAVING shows only approved members or new users
CREATE PROCEDURE SuperAdmin_User_GetList(
    IN p_OrgIds     TEXT,
    IN p_Search     VARCHAR(150),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT CASE WHEN sv.ValueCode = 'APPROVED' THEN o.OrgName END
                     ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS Role,
        (SELECT sv2.ValueCode FROM OrgMembers om2
            JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS MembershipStatus,
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        COALESCE(
            MIN(CASE WHEN sv.ValueCode = 'APPROVED' THEN om.JoinedAt END),
            u.CreatedAt
        ) AS JoinedAt
    FROM Users u
    JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
        AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
    LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN Organisations  o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues  pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.IsDeleted = 0
      AND (p_Search IS NULL OR p_Search = ''
           OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
           OR u.Email  LIKE CONCAT('%', p_Search, '%')
           OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
    GROUP BY
        u.UserId, up.FirstName, up.LastName, u.Email, u.Mobile,
        up.ProfilePhoto, u.IsActive, pv.ValueCode, u.CreatedAt
    HAVING
        -- A user with zero org memberships always passes, regardless of which
        -- orgs are selected in the filter — there's no org to filter them by,
        -- and "cross-NGO oversight" should still surface brand-new registrants.
        -- (Previously this branch also required p_OrgIds to be NULL/empty, but
        -- the frontend's "all organisations" selection always sends a real,
        -- non-empty ID list, so that condition was never actually true in
        -- practice — zero-org members were silently excluded on every real page
        -- load.)
        COUNT(om.OrgMemberId) = 0
        OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ORDER BY JoinedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;


    SELECT COUNT(*) AS TotalCount FROM (
        SELECT u.UserId
        FROM Users u
        JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
        LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
        WHERE u.IsDeleted = 0
          AND (p_Search IS NULL OR p_Search = ''
               OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
               OR u.Email  LIKE CONCAT('%', p_Search, '%')
               OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
        GROUP BY u.UserId
        HAVING
            COUNT(om.OrgMemberId) = 0
            OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ) t;
END //

-- ============================================================
-- Missing SuperAdmin SPs (added v5.0-fix)
-- ============================================================

DROP PROCEDURE IF EXISTS SuperAdmin_Dashboard_GetKpis //
CREATE PROCEDURE SuperAdmin_Dashboard_GetKpis()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM Organisations WHERE IsDeleted = 0) AS TotalOrgs,
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'PENDING') AS PendingOrgs,
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS ApprovedOrgs,
        (SELECT COUNT(*) FROM Users WHERE IsDeleted = 0) AS TotalUsers,
        (SELECT COUNT(*) FROM Users WHERE IsDeleted = 0 AND IsActive = 1) AS ActiveUsers,
        (SELECT COUNT(*) FROM Users WHERE IsDeleted = 0 AND IsActive = 0) AS SuspendedUsers,
        (SELECT COUNT(*) FROM Users u
            JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
            WHERE u.IsDeleted = 0 AND pv.ValueCode = 'PENDING') AS PendingProfileVerifications,
        (SELECT COUNT(*) FROM DonationTransactions WHERE IsDeleted = 0) AS TotalDonations,
        (SELECT COALESCE(SUM(Amount), 0) FROM DonationTransactions
            WHERE IsDeleted = 0 AND StatusCode = 'COMPLETED') AS TotalDonationAmount,
        (SELECT COUNT(*) FROM Projects WHERE IsDeleted = 0) AS TotalProjects,
        (SELECT COUNT(*) FROM UserDocuments WHERE IsDeleted = 0 AND IsVerified = 0) AS PendingDocuments;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetRecent //
CREATE PROCEDURE SuperAdmin_Org_GetRecent(IN p_Limit INT)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.LogoUrl, o.City, o.State,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId   = sv.LookupValueId
    WHERE o.IsDeleted = 0
    ORDER BY o.CreatedAt DESC
    LIMIT p_Limit;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_VerifyProfile //
CREATE PROCEDURE SuperAdmin_Org_VerifyProfile(
    IN p_OrgId        INT UNSIGNED,
    IN p_StatusCode   VARCHAR(50),
    IN p_SuperAdminId INT UNSIGNED
)
BEGIN
    DECLARE v_OrgExists   TINYINT DEFAULT 0;
    DECLARE v_StatusId    INT UNSIGNED;
    DECLARE v_FounderUId  INT UNSIGNED;

    SELECT COUNT(*) INTO v_OrgExists FROM Organisations
    WHERE OrgId = p_OrgId AND IsDeleted = 0;

    IF v_OrgExists = 0 THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_StatusId
        FROM LookupValues lv
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv.ValueCode = p_StatusCode
        LIMIT 1;

        IF v_StatusId IS NULL THEN
            SELECT 0 AS IsSuccess, CONCAT('Unknown verification status: ', p_StatusCode) AS Message;
        ELSE
            UPDATE Organisations
            SET VerificationStatusLkpId = v_StatusId, UpdatedAt = NOW(), UpdatedBy = p_SuperAdminId
            WHERE OrgId = p_OrgId;

            -- Notify founder
            SELECT om.UserId INTO v_FounderUId
            FROM OrgMembers om
            JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
            JOIN LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
            WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
              AND rt.TypeCode = 'MEMBER_ROLE' AND rv.ValueCode = 'FOUNDER'
            LIMIT 1;

            IF v_FounderUId IS NOT NULL THEN
                INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
                VALUES (v_FounderUId,
                    IF(p_StatusCode = 'VERIFIED', 'ORG_PROFILE_VERIFIED', 'ORG_PROFILE_REJECTED'),
                    IF(p_StatusCode = 'VERIFIED', 'Organisation documents verified',
                        'Organisation documents need attention'),
                    IF(p_StatusCode = 'VERIFIED',
                        'Your organisation''s documents have been verified by the Super Admin.',
                        'Please review and resubmit your organisation documents.'),
                    p_OrgId, 'ORGANISATION');
            END IF;

            SELECT 1 AS IsSuccess, 'Organisation verification status updated.' AS Message;
        END IF;
    END IF;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_UserDocument_Verify //
CREATE PROCEDURE SuperAdmin_UserDocument_Verify(
    IN p_UserDocumentId   INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsVerified       TINYINT(1)
)
BEGIN
    DECLARE v_UserId     INT UNSIGNED;
    DECLARE v_DocExists  TINYINT DEFAULT 0;

    SELECT UserId INTO v_UserId FROM UserDocuments
    WHERE UserDocumentId = p_UserDocumentId AND IsDeleted = 0;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        UPDATE UserDocuments
        SET IsVerified = p_IsVerified,
            VerifiedAt = IF(p_IsVerified = 1, NOW(), NULL),
            VerifiedBy = IF(p_IsVerified = 1, p_SuperAdminUserId, NULL)
        WHERE UserDocumentId = p_UserDocumentId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (v_UserId,
            IF(p_IsVerified = 1, 'DOCUMENT_VERIFIED', 'DOCUMENT_REJECTED'),
            IF(p_IsVerified = 1, 'Document verified', 'Document rejected'),
            IF(p_IsVerified = 1, 'Your identity document has been verified.',
                'Your identity document was not accepted. Please resubmit.'),
            p_UserDocumentId, 'USER_DOCUMENT');

        SELECT 1 AS IsSuccess,
               IF(p_IsVerified = 1, 'Document verified.', 'Document rejected.') AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_User_GetDocuments //
CREATE PROCEDURE SuperAdmin_User_GetDocuments(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ud.UserDocumentId, ud.UserId,
        ud.DocumentTypeLkpId, dt.ValueName AS DocumentType,
        ud.FileUrl, ud.FileName, ud.FileSizeKb,
        ud.IsVerified, ud.VerifiedAt, ud.VerifiedBy,
        ud.IsDeleted, ud.CreatedAt
    FROM UserDocuments ud
    LEFT JOIN LookupValues dt ON ud.DocumentTypeLkpId = dt.LookupValueId
    WHERE ud.UserId = p_UserId AND ud.IsDeleted = 0
    ORDER BY ud.CreatedAt DESC;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_User_GetFullProfile //
CREATE PROCEDURE SuperAdmin_User_GetFullProfile(IN p_UserId INT UNSIGNED)
BEGIN
    -- Result Set 0: core profile
    SELECT
        u.UserId, u.Email, u.Mobile, u.IsActive, u.IsVerified,
        -- v5.5-fix: AccountStatus was never returned by this SP at all —
        -- MemberDrawer.jsx's "Account" StatusPill and its suspend/reactivate
        -- branch both read profile.accountStatus, which was always undefined
        -- (rendered as "—"). Same derivation already used by
        -- SuperAdmin_User_GetList for the members table — reusing it here.
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
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
        -- v5.5: AddressLine1/2, Pincode, GenderLkpId added — only the City/
        -- State/Country and resolved Gender NAME were returned before, which
        -- isn't enough to pre-fill a full edit form (address lines/pincode
        -- were missing entirely; GenderLkpId is needed to pre-select the
        -- dropdown, not just display the resolved name).
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
    -- v5.5-fix: UserSkills.SkillName is a plain VARCHAR (see CREATE TABLE
    -- UserSkills) — there is no SkillLkpId column and never was. The old
    -- JOIN LookupValues ON us.SkillLkpId = ... referenced a column that
    -- doesn't exist, breaking every call to this SP (Unknown column
    -- 'us.SkillLkpId' in 'on clause') — this was a pre-existing bug, not
    -- something introduced by the v5.5 profile-edit work; just surfaced by
    -- it since MemberDrawer now calls GetMemberProfile more often.
    SELECT us.SkillName AS SkillName, us.SkillName AS SkillCode
    FROM UserSkills us
    WHERE us.UserId = p_UserId AND us.IsDeleted = 0;

    -- Result Set 2: interests
    -- v5.5-fix: same class of bug as skills/badges above — UserInterests has
    -- no IsDeleted column at all (see CREATE TABLE UserInterests: UserId,
    -- InterestLkpId, CreatedAt only) -> "Unknown column 'ui.IsDeleted'".
    SELECT iv.ValueName, iv.ValueCode
    FROM UserInterests ui
    JOIN LookupValues iv ON ui.InterestLkpId = iv.LookupValueId
    WHERE ui.UserId = p_UserId;

    -- Result Set 3: badges
    -- v5.5-fix: same class of bug as the skills query above — UserBadges has
    -- no BadgeType/BadgeName/AwardedAt/OrgId columns (see CREATE TABLE
    -- UserBadges: BadgeLkpId, AwardedByOrgId, CreatedAt). Never actually
    -- executed successfully before (execution always stopped at the skills
    -- query first) — fixing both together rather than leaving this one to
    -- surface as a second round-trip bug report.
    SELECT lv.ValueName AS BadgeType, ub.AwardedBy, ub.CreatedAt AS AwardedAt,
           ub.AwardedByOrgId AS OrgId, o.OrgName
    FROM UserBadges ub
    LEFT JOIN LookupValues lv ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId AND o.IsDeleted = 0
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.CreatedAt DESC;

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

DROP PROCEDURE IF EXISTS SuperAdmin_User_RequestUpdate //
CREATE PROCEDURE SuperAdmin_User_RequestUpdate(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_Exists TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM Users
    WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'User not found.' AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required.' AS Message;
    ELSE
        -- Set profile to NEEDS_UPDATE (distinct from PENDING/not-yet-reviewed) so the
        -- app can show a dedicated "action required" banner with the admin's reason.
        UPDATE Users
        SET ProfileVerificationLkpId = (
            SELECT lv.LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv.ValueCode = 'NEEDS_UPDATE'
            LIMIT 1
        ),
        UpdatedAt = NOW()
        WHERE UserId = p_UserId;

        -- NotifType standardised to PROFILE_UPDATE_REQUIRED (matches mobile app's
        -- RootNavigator/NotificationsScreen deep-link switch — was previously
        -- PROFILE_UPDATE_REQUESTED, a string the app never handled, so tapping the
        -- notification did nothing). This is the single canonical write for this
        -- event; the C# DAL layer no longer inserts a duplicate row.
        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'PROFILE_UPDATE_REQUIRED', 'Profile update required',
                p_Reason, p_UserId, 'USER');

        SELECT 1 AS IsSuccess, 'Profile update requested.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_User_Suspend //
CREATE PROCEDURE SuperAdmin_User_Suspend(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_Exists TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM Users
    WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'User not found.' AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A suspension reason is required.' AS Message;
    ELSE
        UPDATE Users SET IsActive = 0, UpdatedAt = NOW()
        WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'ACCOUNT_SUSPENDED', 'Account suspended',
                p_Reason, p_UserId, 'USER');

        SELECT 1 AS IsSuccess, 'User account suspended.' AS Message;
    END IF;
END //

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

-- ============================================================
-- Feed SPs (from NGOConnect_Patch_PersonalizedFeed.sql)
-- Tables (PostSaves, FeedInteractions) + Posts columns already
-- defined above in the CREATE TABLE section.
-- ============================================================

DELIMITER //

-- ── Feed_GetPersonalized ──────────────────────────────────────────────────────
-- v5.1 changes:
--   • Added p_SeenExpiryDays — seen-post filter window (default 30 days)
--   • Seen filter: posts viewed within expiry window are excluded
--   • Emergency posts (IsEmergency=1) always bypass the seen filter
--   • MY_ORG / FOLLOWED_ORG: no longer time-limited (show all historical posts)
--   • TRENDING: extended from 7 → 30 days
--   • INTEREST:  extended from 14 → 45 days
--   • Added PINNED_EVERGREEN bucket — pinned/evergreen posts from user's NGOs (no time limit)
--   • Added DISCOVERY safety-net bucket — top public posts of all time (last resort)
DROP PROCEDURE IF EXISTS Feed_GetPersonalized //
CREATE PROCEDURE Feed_GetPersonalized(
    IN p_UserId          INT UNSIGNED,
    IN p_CursorPostId    INT UNSIGNED,
    IN p_CursorScore     DECIMAL(10,4),
    IN p_PageSize        INT,
    IN p_SeenExpiryDays  INT          -- how many days to remember a viewed post (default 30)
)
BEGIN
    DECLARE v_FetchSize   INT          DEFAULT p_PageSize * 3;
    DECLARE v_PublicLkpId INT UNSIGNED DEFAULT 0;

    -- Default seen expiry if caller passes NULL
    IF p_SeenExpiryDays IS NULL OR p_SeenExpiryDays <= 0 THEN
        SET p_SeenExpiryDays = 30;
    END IF;

    -- Resolve the 'PUBLIC' visibility LkpId once — used to pre-filter candidate
    -- sources (TRENDING / RECENT / INTEREST / DISCOVERY) so ORG_MEMBERS posts
    -- never enter the global-discovery buckets in the first place.
    SELECT lv.LookupValueId INTO v_PublicLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC'
    LIMIT  1;

    SELECT sf.* FROM (

        SELECT
            p.PostId,
            p.Content,
            p.IsPinned,
            p.IsEmergency,
            p.IsEvergreen,
            p.LikeCount,
            p.CommentCount,
            p.ShareCount,
            p.SaveCount,
            p.ViewCount,
            lv_type.ValueCode  AS PostTypeCode,
            lv_type.ValueName  AS PostType,
            p.UserId,
            CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
            up.ProfilePhoto,
            p.OrgId,
            o.OrgName,
            o.LogoUrl          AS OrgLogoUrl,
            cands.FeedSource,

            (SELECT COUNT(*) FROM PostLikes pl
             WHERE pl.PostId = p.PostId AND pl.UserId = p_UserId)  AS IsLiked,

            (SELECT COUNT(*) FROM PostSaves ps
             WHERE ps.PostId = p.PostId AND ps.UserId = p_UserId)  AS IsSaved,

            IFNULL((SELECT of2.IsFollowing FROM OrgFollowers of2
                    WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId LIMIT 1), 0) AS IsFollowing,

            GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
            GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,

            p.CreatedAt,
            CASE
                WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
                WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
                WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
                WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
                WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
                ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
            END AS TimeAgo,

            (
                CASE
                    WHEN EXISTS(
                        SELECT 1 FROM OrgMembers om
                        JOIN LookupValues lvm ON om.StatusLkpId = lvm.LookupValueId
                        WHERE om.OrgId = p.OrgId AND om.UserId = p_UserId
                          AND om.IsDeleted = 0 AND lvm.ValueCode = 'APPROVED'
                    ) THEN 50
                    WHEN EXISTS(
                        SELECT 1 FROM OrgFollowers of3
                        WHERE of3.OrgId = p.OrgId AND of3.UserId = p_UserId AND of3.IsFollowing = 1
                    ) THEN 30
                    ELSE 0
                END

                + CASE WHEN EXISTS(
                    SELECT 1 FROM UserInterests ui
                    JOIN LookupValues li ON ui.InterestLkpId = li.LookupValueId
                    WHERE ui.UserId = p_UserId
                      AND (
                          LOWER(li.ValueName) LIKE CONCAT('%', LOWER(COALESCE(lv_type.ValueName, '')), '%')
                       OR LOWER(COALESCE(lv_type.ValueName, '')) LIKE CONCAT('%', LOWER(li.ValueName), '%')
                       OR LOWER(COALESCE(p.Content, ''))         LIKE CONCAT('%', LOWER(li.ValueName), '%')
                      )
                ) THEN 30 ELSE 0 END

                + LEAST(20, (
                    SELECT COUNT(*) * 10
                    FROM UserSkills us
                    WHERE us.UserId = p_UserId AND us.IsDeleted = 0
                      AND LOWER(COALESCE(p.Content, '')) LIKE CONCAT('%', LOWER(us.SkillName), '%')
                ))

                + CASE
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 1   THEN 25
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 6   THEN 20
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 24  THEN 15
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 3   THEN 10
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 7   THEN 5
                    ELSE 2
                  END

                + LEAST(15, FLOOR(
                    (p.LikeCount * 0.5 + p.CommentCount * 1.0 + p.ShareCount * 2.0 + p.SaveCount * 1.5)
                    / 10.0
                  ))

                + CASE WHEN EXISTS(
                    SELECT 1 FROM Organisations o2
                    JOIN LookupValues lv_os ON o2.StatusLkpId = lv_os.LookupValueId
                    WHERE o2.OrgId = p.OrgId AND lv_os.ValueCode = 'APPROVED'
                ) THEN 10 ELSE 0 END

                + CASE WHEN LENGTH(COALESCE(p.Content, '')) > 100 THEN 5 ELSE 0 END
                + CASE WHEN EXISTS(
                    SELECT 1 FROM PostMedia pm2 WHERE pm2.PostId = p.PostId
                ) THEN 5 ELSE 0 END

                - LEAST(20, COALESCE(
                    (SELECT COUNT(*) * 5 FROM PostReports pr WHERE pr.PostId = p.PostId),
                    0
                  ))

                + CASE WHEN p.IsEmergency = 1 THEN 1000 ELSE 0 END

            ) AS FeedScore

        FROM Posts p

        JOIN (
            SELECT PostId, MIN(FeedSource) AS FeedSource
            FROM (
                -- MY_ORG: all posts from NGOs the user is an approved member of.
                -- No time limit — member posts are always highest priority.
                (SELECT p1.PostId, 'MY_ORG' AS FeedSource
                FROM Posts p1
                INNER JOIN OrgMembers om1
                       ON om1.OrgId = p1.OrgId AND om1.UserId = p_UserId AND om1.IsDeleted = 0
                INNER JOIN LookupValues lv1
                       ON lv1.LookupValueId = om1.StatusLkpId AND lv1.ValueCode = 'APPROVED'
                WHERE p1.IsDeleted = 0
                ORDER BY p1.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- FOLLOWED_ORG: posts from NGOs the user follows.
                -- No time limit — followed org posts should always surface.
                (SELECT p2.PostId, 'FOLLOWED_ORG' AS FeedSource
                FROM Posts p2
                INNER JOIN OrgFollowers of1
                       ON of1.OrgId = p2.OrgId AND of1.UserId = p_UserId AND of1.IsFollowing = 1
                WHERE p2.IsDeleted = 0
                ORDER BY p2.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- TRENDING: top public posts by engagement. Extended to 30 days.
                (SELECT p3.PostId, 'TRENDING' AS FeedSource
                FROM Posts p3
                WHERE p3.IsDeleted = 0
                  AND p3.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                  AND p3.VisibilityLkpId = v_PublicLkpId
                ORDER BY (p3.LikeCount * 1 + p3.CommentCount * 2 + p3.ShareCount * 3 + p3.SaveCount * 2) DESC
                LIMIT 100)

                UNION ALL

                -- EMERGENCY: always show active emergency posts regardless of seen status.
                -- The seen filter in the outer WHERE exempts IsEmergency=1 posts.
                (SELECT p4.PostId, 'EMERGENCY' AS FeedSource
                FROM Posts p4
                WHERE p4.IsDeleted = 0
                  AND p4.IsEmergency = 1
                  AND p4.CreatedAt >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
                ORDER BY p4.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- INTEREST: public posts matching user's interest tags. Extended to 45 days.
                (SELECT p5.PostId, 'INTEREST' AS FeedSource
                FROM Posts p5
                INNER JOIN LookupValues pt5 ON pt5.LookupValueId = p5.PostTypeLkpId
                WHERE p5.IsDeleted = 0
                  AND p5.CreatedAt >= DATE_SUB(NOW(), INTERVAL 45 DAY)
                  AND p5.VisibilityLkpId = v_PublicLkpId
                  AND EXISTS(
                      SELECT 1 FROM UserInterests ui5
                      JOIN LookupValues li5 ON ui5.InterestLkpId = li5.LookupValueId
                      WHERE ui5.UserId = p_UserId
                        AND (LOWER(li5.ValueName) LIKE CONCAT('%', LOWER(pt5.ValueName), '%')
                          OR LOWER(pt5.ValueName) LIKE CONCAT('%', LOWER(li5.ValueName), '%'))
                  )
                ORDER BY p5.CreatedAt DESC LIMIT 100)

                UNION ALL

                -- RECENT: latest public posts from anyone. Keeps feed fresh.
                (SELECT p6.PostId, 'RECENT' AS FeedSource
                FROM Posts p6
                WHERE p6.IsDeleted = 0
                  AND p6.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                  AND p6.VisibilityLkpId = v_PublicLkpId
                ORDER BY p6.CreatedAt DESC LIMIT 100)

                UNION ALL

                -- PINNED_EVERGREEN: pinned or evergreen posts from the user's own NGOs.
                -- No time limit — these are explicitly marked as always-relevant.
                (SELECT p7.PostId, 'PINNED_EVERGREEN' AS FeedSource
                FROM Posts p7
                INNER JOIN OrgMembers om7
                       ON om7.OrgId = p7.OrgId AND om7.UserId = p_UserId AND om7.IsDeleted = 0
                INNER JOIN LookupValues lv7
                       ON lv7.LookupValueId = om7.StatusLkpId AND lv7.ValueCode = 'APPROVED'
                WHERE p7.IsDeleted = 0
                  AND (p7.IsPinned = 1 OR p7.IsEvergreen = 1)
                ORDER BY p7.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- DISCOVERY: top public posts of all time by engagement score.
                -- Safety net — surfaces when all personalised buckets are exhausted.
                (SELECT p8.PostId, 'DISCOVERY' AS FeedSource
                FROM Posts p8
                WHERE p8.IsDeleted = 0
                  AND p8.VisibilityLkpId = v_PublicLkpId
                ORDER BY (p8.LikeCount * 1 + p8.CommentCount * 2 + p8.ShareCount * 3 + p8.SaveCount * 2) DESC
                LIMIT 100)

            ) all_sources
            GROUP BY PostId
        ) cands ON cands.PostId = p.PostId

        JOIN   UserProfiles up      ON up.UserId             = p.UserId AND up.IsDeleted = 0
        LEFT JOIN Organisations o   ON o.OrgId               = p.OrgId
        LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
        LEFT JOIN PostMedia pm      ON pm.PostId             = p.PostId
        LEFT JOIN LookupValues lv_mt ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
        LEFT JOIN LookupValues lv_vis ON lv_vis.LookupValueId = p.VisibilityLkpId

        WHERE p.IsDeleted = 0
          -- Visibility enforcement: PUBLIC = everyone; ORG_MEMBERS = approved members only;
          -- FOLLOWERS = org followers only; NULL/unknown = treat as PUBLIC.
          AND (
              lv_vis.ValueCode IS NULL OR lv_vis.ValueCode = 'PUBLIC'
              OR (lv_vis.ValueCode = 'ORG_MEMBERS'
                  AND EXISTS (
                      SELECT 1 FROM OrgMembers om_v
                      JOIN LookupValues lv_s ON om_v.StatusLkpId = lv_s.LookupValueId
                      WHERE om_v.OrgId = p.OrgId AND om_v.UserId = p_UserId
                        AND om_v.IsDeleted = 0 AND lv_s.ValueCode = 'APPROVED'
                  ))
              OR (lv_vis.ValueCode = 'FOLLOWERS'
                  AND EXISTS (
                      SELECT 1 FROM OrgFollowers of_v
                      WHERE of_v.OrgId = p.OrgId AND of_v.UserId = p_UserId AND of_v.IsFollowing = 1
                  ))
          )

        GROUP BY
            p.PostId,      p.Content,    p.IsPinned,   p.IsEmergency, p.IsEvergreen,
            p.LikeCount,   p.CommentCount, p.ShareCount, p.SaveCount, p.ViewCount,
            lv_type.ValueCode, lv_type.ValueName,
            p.UserId,      up.FirstName, up.LastName,  up.ProfilePhoto,
            p.OrgId,       o.OrgName,   o.LogoUrl,    cands.FeedSource,
            lv_vis.ValueCode,
            p.CreatedAt

    ) sf

    -- Cursor: newest-first chronological pagination.
    -- Seen filter: exclude posts the user already viewed within the expiry window.
    -- Exception: IsEmergency=1 posts always bypass the seen filter.
    WHERE (
        p_CursorScore IS NULL
        OR UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore
        OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)
    )
    AND (
        sf.IsEmergency = 1   -- emergency posts always show regardless of seen status
        OR NOT EXISTS (
            SELECT 1 FROM FeedInteractions fi
            WHERE fi.PostId          = sf.PostId
              AND fi.UserId          = p_UserId
              AND fi.InteractionType = 'VIEW'
              AND fi.CreatedAt       >= DATE_SUB(NOW(), INTERVAL p_SeenExpiryDays DAY)
        )
    )

    ORDER BY sf.CreatedAt DESC, sf.PostId DESC
    LIMIT  v_FetchSize;

END //

-- ── Post_Save ─────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_Save //
CREATE PROCEDURE Post_Save(
    IN p_UserId INT UNSIGNED,
    IN p_PostId INT UNSIGNED
)
BEGIN
    INSERT IGNORE INTO PostSaves (PostId, UserId) VALUES (p_PostId, p_UserId);
    IF ROW_COUNT() > 0 THEN
        UPDATE Posts SET SaveCount = SaveCount + 1 WHERE PostId = p_PostId;
        INSERT INTO FeedInteractions (UserId, PostId, InteractionType) VALUES (p_UserId, p_PostId, 'SAVE');
        SELECT 1 AS IsSuccess, 'Post saved.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Already saved.' AS Message;
    END IF;
END //

-- ── Post_BulkNotifyOrgMembers ─────────────────────────────────────────────────
-- Called fire-and-forget after Post_Create succeeds.
-- 1. Bulk-inserts one Notifications row per approved org member (excludes author).
-- 2. Returns (UserId, Token, Platform, Title, Body) for FCM multicast dispatch.
DROP PROCEDURE IF EXISTS Post_BulkNotifyOrgMembers //
CREATE PROCEDURE Post_BulkNotifyOrgMembers(
    IN p_PostId       INT UNSIGNED,
    IN p_OrgId        INT UNSIGNED,
    IN p_AuthorUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Title VARCHAR(200);
    DECLARE v_Body  VARCHAR(104);

    -- Build title "[AuthorName] posted in [OrgName]" and body (first 100 chars of content)
    SELECT CONCAT(TRIM(CONCAT(up.FirstName, ' ', COALESCE(up.LastName, ''))),
                  ' posted in ', o.OrgName),
           CONCAT(LEFT(p.Content, 100),
                  IF(CHAR_LENGTH(p.Content) > 100, '…', ''))
    INTO   v_Title, v_Body
    FROM   Posts         p
    JOIN   Organisations o  ON o.OrgId   = p.OrgId
    JOIN   UserProfiles  up ON up.UserId = p.UserId
    WHERE  p.PostId    = p_PostId
      AND  p.OrgId     = p_OrgId
      AND  p.IsDeleted = 0
    LIMIT  1;

    -- Guard: post or org not found — return empty result set, nothing to do
    IF v_Title IS NULL THEN
        SELECT NULL AS UserId, NULL AS Token, NULL AS Platform, NULL AS Title, NULL AS Body LIMIT 0;
    ELSE
        -- Bulk-insert one Notifications inbox row per approved org member (excluding author)
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType, CreatedAt)
        SELECT om.UserId, p_OrgId, 'NEW_FEED_POST', v_Title, v_Body, p_PostId, 'POST', NOW()
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.StatusLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId     = p_OrgId
          AND  lt.TypeCode  = 'MEMBER_STATUS'
          AND  lv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  om.UserId   != p_AuthorUserId;

        -- Return token rows for FCM multicast (only members with a registered device)
        SELECT om.UserId,
               dt.Token,
               dt.Platform,
               v_Title AS Title,
               v_Body  AS Body
        FROM   OrgMembers       om
        JOIN   LookupValues     lv ON lv.LookupValueId = om.StatusLkpId
        JOIN   LookupTypes      lt ON lt.LookupTypeId  = lv.LookupTypeId
        JOIN   UserDeviceTokens dt ON dt.UserId = om.UserId
        WHERE  om.OrgId     = p_OrgId
          AND  lt.TypeCode  = 'MEMBER_STATUS'
          AND  lv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  om.UserId   != p_AuthorUserId;
    END IF;
END //

-- ── Post_Unsave ───────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_Unsave //
CREATE PROCEDURE Post_Unsave(
    IN p_UserId INT UNSIGNED,
    IN p_PostId INT UNSIGNED
)
BEGIN
    DELETE FROM PostSaves WHERE PostId = p_PostId AND UserId = p_UserId;
    IF ROW_COUNT() > 0 THEN
        UPDATE Posts SET SaveCount = GREATEST(0, SaveCount - 1) WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Post unsaved.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Not saved.' AS Message;
    END IF;
END //

-- ── Post_GetByUser ────────────────────────────────────────────────────────────
-- Returns all posts created by the given user, newest first.
-- Columns match Post_GetSaved (minus SavedAt) so the same card renders.
DROP PROCEDURE IF EXISTS Post_GetByUser //
CREATE PROCEDURE Post_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        p.IsEmergency,
        p.IsEvergreen,
        p.LikeCount,
        p.CommentCount,
        p.ShareCount,
        p.SaveCount,
        p.ViewCount,
        lv_type.ValueCode  AS PostTypeCode,
        lv_type.ValueName  AS PostType,
        p.UserId,
        CONCAT(up.FirstName, ' ', COALESCE(up.LastName, '')) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        o.LogoUrl          AS OrgLogoUrl,
        (SELECT COUNT(*) FROM PostSaves ps2
         WHERE ps2.PostId = p.PostId AND ps2.UserId = p_UserId) AS IsSaved,
        1                  AS IsLiked,   -- own posts; not needed for display
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts         p
    JOIN   UserProfiles  up     ON up.UserId          = p.UserId
    LEFT JOIN Organisations o   ON o.OrgId            = p.OrgId  AND o.IsDeleted = 0
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm      ON pm.PostId          = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.UserId = p_UserId AND p.IsDeleted = 0
    GROUP BY
        p.PostId,  p.Content,     p.IsPinned,   p.IsEmergency, p.IsEvergreen,
        p.LikeCount, p.CommentCount, p.ShareCount, p.SaveCount, p.ViewCount,
        lv_type.ValueCode, lv_type.ValueName,
        p.UserId,  up.FirstName,  up.LastName,  up.ProfilePhoto,
        p.OrgId,   o.OrgName,     o.LogoUrl,
        p.CreatedAt
    ORDER BY p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.UserId = p_UserId AND p.IsDeleted = 0;
END //

-- ── Post_GetSaved ─────────────────────────────────────────────────────────────
-- Returns all posts saved by the given user, ordered most-recently-saved first.
-- Columns match Feed_GetPersonalized so the same PostCard renders both feeds.
DROP PROCEDURE IF EXISTS Post_GetSaved //
CREATE PROCEDURE Post_GetSaved(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        p.IsEmergency,
        p.IsEvergreen,
        p.LikeCount,
        p.CommentCount,
        p.ShareCount,
        p.SaveCount,
        p.ViewCount,
        lv_type.ValueCode  AS PostTypeCode,
        lv_type.ValueName  AS PostType,
        p.UserId,
        CONCAT(up.FirstName, ' ', COALESCE(up.LastName, '')) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        o.LogoUrl          AS OrgLogoUrl,
        1                  AS IsSaved,
        (SELECT COUNT(*) FROM PostLikes pl
         WHERE pl.PostId = p.PostId AND pl.UserId = p_UserId) AS IsLiked,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        ps.CreatedAt AS SavedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   PostSaves     ps
    JOIN   Posts         p      ON p.PostId          = ps.PostId AND p.IsDeleted = 0
    JOIN   UserProfiles  up     ON up.UserId          = p.UserId
    LEFT JOIN Organisations o   ON o.OrgId            = p.OrgId  AND o.IsDeleted = 0
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm      ON pm.PostId          = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  ps.UserId = p_UserId
    GROUP BY
        p.PostId,  p.Content,     p.IsPinned,   p.IsEmergency, p.IsEvergreen,
        p.LikeCount, p.CommentCount, p.ShareCount, p.SaveCount, p.ViewCount,
        lv_type.ValueCode, lv_type.ValueName,
        p.UserId,  up.FirstName,  up.LastName,  up.ProfilePhoto,
        p.OrgId,   o.OrgName,     o.LogoUrl,
        p.CreatedAt, ps.CreatedAt
    ORDER BY ps.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   PostSaves ps
    JOIN   Posts     p ON p.PostId = ps.PostId AND p.IsDeleted = 0
    WHERE  ps.UserId = p_UserId;
END //

-- ── Feed_TrackInteraction ─────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Feed_TrackInteraction //
CREATE PROCEDURE Feed_TrackInteraction(
    IN p_UserId          INT UNSIGNED,
    IN p_PostId          INT UNSIGNED,
    IN p_InteractionType VARCHAR(30),
    IN p_DurationMs      INT UNSIGNED
)
BEGIN
    INSERT INTO FeedInteractions (UserId, PostId, InteractionType, DurationMs)
    VALUES (p_UserId, p_PostId, p_InteractionType, p_DurationMs);
    SELECT 1 AS IsSuccess, 'Tracked.' AS Message;
END //

-- ── Feed_BulkMarkViewed ────────────────────────────────────────────────────────
-- Records VIEW interactions and increments Posts.ViewCount (unique per user/post).
-- Called by the mobile app when flushing its seen-post buffer.
-- Uses a temp table to identify truly NEW views so ViewCount is never double-counted.
-- Uses JSON_TABLE (MySQL 8.0+) to unpack the array — one SP call for up to ~50 postIds.
DROP PROCEDURE IF EXISTS Feed_BulkMarkViewed //
CREATE PROCEDURE Feed_BulkMarkViewed(
    IN p_UserId  INT UNSIGNED,
    IN p_PostIds JSON          -- e.g. [1, 2, 3, 4, 5]
)
BEGIN
    -- Collect postIds the user has NOT yet viewed (first-time views only)
    DROP TEMPORARY TABLE IF EXISTS _tmp_new_views;
    CREATE TEMPORARY TABLE _tmp_new_views (PostId INT UNSIGNED NOT NULL PRIMARY KEY);

    INSERT INTO _tmp_new_views (PostId)
    SELECT DISTINCT jt.PostId
    FROM   JSON_TABLE(p_PostIds, '$[*]' COLUMNS (PostId INT PATH '$')) AS jt
    WHERE  EXISTS  (SELECT 1 FROM Posts            WHERE PostId = jt.PostId AND IsDeleted = 0)
    AND    NOT EXISTS (
               SELECT 1 FROM FeedInteractions
               WHERE  UserId = p_UserId AND PostId = jt.PostId AND InteractionType = 'VIEW'
           );

    -- Persist the new VIEW rows
    INSERT INTO FeedInteractions (UserId, PostId, InteractionType)
    SELECT p_UserId, PostId, 'VIEW' FROM _tmp_new_views;

    -- Increment the denormalized counter only for genuinely new views
    UPDATE Posts
    SET    ViewCount = ViewCount + 1
    WHERE  PostId IN (SELECT PostId FROM _tmp_new_views);

    DROP TEMPORARY TABLE IF EXISTS _tmp_new_views;

    SELECT 1 AS IsSuccess, 'Marked.' AS Message;
END //

DELIMITER ;

-- ============================================================
-- v5.0: ORG MEMBER INVITATION STORED PROCEDURES
-- ============================================================
DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Send
-- Sends an org member invitation via Phone or Email.
-- Pre-checks: permission, duplicate member, duplicate invite,
-- existing platform user.
-- Returns: IsSuccess, Message, InvitationId, ExistingUserFound,
--          ExistingUserId, ExistingUserName, ExistingUserPhoto,
--          ExistingUserCity, ExistingUserOrgCount, InviteToken,
--          InviteLink (base URL only — app appends token)
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Send //
CREATE PROCEDURE Org_Invite_Send(
    IN p_OrgId            INT UNSIGNED,
    IN p_InvitedByUserId  INT UNSIGNED,
    IN p_InviteTypeCode   VARCHAR(20),    -- 'PHONE' or 'EMAIL'
    IN p_InviteValue      VARCHAR(255),   -- normalised phone or email
    IN p_CountryCode      VARCHAR(6),     -- for PHONE; NULL for EMAIL
    IN p_InviteToken      VARCHAR(128),   -- generated by C# layer
    IN p_TokenExpiry      DATETIME,
    IN p_InviteBaseUrl    VARCHAR(500)    -- from SettingsCache INVITE_BASE_URL
)
main_block: BEGIN
    DECLARE v_InviteTypeLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_InviterRoleCode    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_ExistingUserId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_IsMember           TINYINT(1)   DEFAULT 0;
    DECLARE v_PendingInviteId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_NewInvitationId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ExistingUserName   VARCHAR(161) DEFAULT NULL;
    DECLARE v_ExistingUserPhoto  VARCHAR(500) DEFAULT NULL;
    DECLARE v_ExistingUserCity   VARCHAR(100) DEFAULT NULL;
    DECLARE v_ExistingUserOrgCt  INT UNSIGNED DEFAULT 0;
    DECLARE v_OrgName            VARCHAR(200) DEFAULT NULL;
    DECLARE v_NotifTypeLkpId     INT UNSIGNED DEFAULT NULL;

    -- 1. Verify inviter has FOUNDER or ADMIN role in this org
    SELECT lv.ValueCode INTO v_InviterRoleCode
    FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = p_OrgId AND om.UserId = p_InvitedByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_InviterRoleCode IS NULL OR v_InviterRoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to invite members.' AS Message,
               NULL AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- Guard against self-invite
    IF p_InviteTypeCode = 'PHONE' THEN
        SELECT UserId INTO v_ExistingUserId FROM Users
        WHERE Mobile = p_InviteValue AND IsDeleted = 0 LIMIT 1;
    ELSE
        SELECT UserId INTO v_ExistingUserId FROM Users
        WHERE Email = LOWER(p_InviteValue) AND IsDeleted = 0 LIMIT 1;
    END IF;

    IF v_ExistingUserId = p_InvitedByUserId THEN
        SELECT 0 AS IsSuccess, 'You cannot invite yourself.' AS Message,
               NULL AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- 2. If existing user found, check if already a member
    IF v_ExistingUserId IS NOT NULL THEN
        SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
        WHERE OrgId = p_OrgId AND UserId = v_ExistingUserId AND IsDeleted = 0;

        IF v_IsMember > 0 THEN
            SELECT 0 AS IsSuccess, 'This user is already a member of your organisation.' AS Message,
                   NULL AS InvitationId, 1 AS ExistingUserFound, v_ExistingUserId AS ExistingUserId,
                   NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
                   0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
            LEAVE main_block;
        END IF;
    END IF;

    -- 3. Check for an active (PENDING) invitation for same org + contact
    SELECT OrgInvitationId INTO v_PendingInviteId
    FROM OrgInvitations
    WHERE OrgId = p_OrgId
      AND InviteValue = p_InviteValue
      AND IsDeleted = 0
      AND TokenExpiry > NOW()
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                         JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                         WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING')
    LIMIT 1;

    IF v_PendingInviteId IS NOT NULL THEN
        SELECT 0 AS IsSuccess, 'An active invitation already exists for this contact. Use Resend Invitation to refresh it.' AS Message,
               v_PendingInviteId AS InvitationId, 0 AS ExistingUserFound, NULL AS ExistingUserId,
               NULL AS ExistingUserName, NULL AS ExistingUserPhoto, NULL AS ExistingUserCity,
               0 AS ExistingUserOrgCount, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    -- 4. Get LookupValueIds
    SELECT LookupValueId INTO v_InviteTypeLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_TYPE' AND lv.ValueCode = p_InviteTypeCode LIMIT 1;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    -- 5. Insert the invitation
    INSERT INTO OrgInvitations (
        OrgId, InvitedByUserId, InviteTypeLkpId, InviteValue, CountryCode,
        InvitedUserId, InviteToken, TokenExpiry, StatusLkpId, SentAt
    ) VALUES (
        p_OrgId, p_InvitedByUserId, v_InviteTypeLkpId, p_InviteValue, p_CountryCode,
        v_ExistingUserId, p_InviteToken, p_TokenExpiry, v_StatusLkpId, NOW()
    );

    SET v_NewInvitationId = LAST_INSERT_ID();

    -- 6. If existing user found, create in-app notification
    IF v_ExistingUserId IS NOT NULL THEN
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = p_OrgId LIMIT 1;

        SELECT LookupValueId INTO v_NotifTypeLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'NOTIFICATION_TYPE' AND lv.ValueCode = 'ORG_INVITE' LIMIT 1;

        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_ExistingUserId, p_OrgId,
            'ORG_INVITE',
            CONCAT(v_OrgName, ' invited you to join their organisation'),
            CONCAT('You have been invited to join ', v_OrgName, '. Tap to view the organisation and accept the invitation.'),
            v_NewInvitationId, 'ORG_INVITATION'
        );

        -- Fetch existing user profile for display
        SELECT CONCAT(up.FirstName, ' ', up.LastName), up.ProfilePhoto, up.City
        INTO v_ExistingUserName, v_ExistingUserPhoto, v_ExistingUserCity
        FROM UserProfiles up WHERE up.UserId = v_ExistingUserId LIMIT 1;

        SELECT COUNT(*) INTO v_ExistingUserOrgCt FROM OrgMembers
        WHERE UserId = v_ExistingUserId AND IsDeleted = 0;
    END IF;

    -- 7. Return result
    SELECT 1 AS IsSuccess,
           IF(v_ExistingUserId IS NOT NULL,
              'Invitation sent. The user has been notified in-app.',
              'Invitation created. Send the link via SMS or Email.') AS Message,
           v_NewInvitationId AS InvitationId,
           IF(v_ExistingUserId IS NOT NULL, 1, 0) AS ExistingUserFound,
           v_ExistingUserId       AS ExistingUserId,
           v_ExistingUserName     AS ExistingUserName,
           v_ExistingUserPhoto    AS ExistingUserPhoto,
           v_ExistingUserCity     AS ExistingUserCity,
           v_ExistingUserOrgCt    AS ExistingUserOrgCount,
           p_InviteToken          AS InviteToken,
           CONCAT(p_InviteBaseUrl, p_InviteToken) AS InviteLink;

END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_VerifyToken
-- Called by deep link handler (before/after login).
-- Returns full invitation context + org info + status.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_VerifyToken //
CREATE PROCEDURE Org_Invite_VerifyToken(
    IN p_Token VARCHAR(128)
)
main_block: BEGIN
    DECLARE v_StatusCode  VARCHAR(20)  DEFAULT NULL;
    DECLARE v_IsSingleUse TINYINT(1)   DEFAULT 1;

    SELECT lv.ValueCode INTO v_StatusCode
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.InviteToken = p_Token AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_StatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'INVALID_TOKEN'  AS ErrorCode, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode = 'CANCELLED' THEN
        SELECT 0 AS IsSuccess, 'INVITE_CANCELLED' AS ErrorCode, 'This invitation has been cancelled.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode = 'ACCEPTED' THEN
        SELECT 0 AS IsSuccess, 'INVITE_USED' AS ErrorCode, 'This invitation has already been accepted.' AS Message;
        LEAVE main_block;
    END IF;

    -- Auto-expire check
    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE InviteToken = p_Token AND TokenExpiry < NOW()
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                         JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                         WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING')
      AND IsDeleted = 0;

    SELECT
        1                       AS IsSuccess,
        NULL                    AS ErrorCode,
        'Valid invitation.'     AS Message,
        oi.OrgInvitationId,
        oi.OrgId,
        o.OrgName,
        o.LogoUrl               AS OrgLogo,
        o.City                  AS OrgCity,
        o.About                 AS OrgAbout,
        lv_status.ValueCode     AS StatusCode,
        lv_type.ValueCode       AS InviteType,
        oi.InviteValue,
        oi.CountryCode,
        oi.InvitedUserId,
        oi.TokenExpiry,
        CONCAT(up.FirstName, ' ', up.LastName) AS InvitedByName,
        up.ProfilePhoto         AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN Organisations o         ON o.OrgId = oi.OrgId
    JOIN LookupValues lv_status  ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN LookupValues lv_type    ON lv_type.LookupValueId   = oi.InviteTypeLkpId
    JOIN UserProfiles up         ON up.UserId = oi.InvitedByUserId
    WHERE oi.InviteToken = p_Token AND oi.IsDeleted = 0
    LIMIT 1;

    -- Mark as OPENED (idempotent)
    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'OPENED'),
        OpenedAt    = IFNULL(OpenedAt, NOW())
    WHERE InviteToken = p_Token
      AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                         JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                         WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING')
      AND IsDeleted = 0;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Accept
-- Consumes the invitation: creates a membership request
-- (or directly joins if org has auto-approval).
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Accept //
CREATE PROCEDURE Org_Invite_Accept(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId             INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode        VARCHAR(20)  DEFAULT NULL;
    DECLARE v_IsMember          TINYINT(1)   DEFAULT 0;
    DECLARE v_AcceptedLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_MemberRoleLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedMemLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName           VARCHAR(200) DEFAULT NULL;
    DECLARE v_InviteeName       VARCHAR(200) DEFAULT NULL;
    DECLARE v_AdminUserId       INT UNSIGNED DEFAULT NULL;
    DECLARE v_AdminDone         TINYINT(1)   DEFAULT 0;

    DECLARE admin_cur CURSOR FOR
        SELECT DISTINCT om.UserId
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = v_OrgId
          AND  lt.TypeCode = 'MEMBER_ROLE'
          AND  lv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_AdminDone = 1;

    -- Validate invitation
    SELECT oi.OrgId, lv.ValueCode
    INTO   v_OrgId, v_StatusCode
    FROM   OrgInvitations oi
    JOIN   LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE  oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT  1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message, NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess,
               CASE v_StatusCode
                   WHEN 'ACCEPTED'  THEN 'This invitation has already been accepted.'
                   WHEN 'CANCELLED' THEN 'This invitation has been cancelled.'
                   WHEN 'EXPIRED'   THEN 'This invitation has expired.'
                   ELSE 'Invitation is no longer valid.'
               END AS Message,
               NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    IF NOW() > (SELECT TokenExpiry FROM OrgInvitations WHERE OrgInvitationId = p_InvitationId) THEN
        SELECT 0 AS IsSuccess, 'This invitation has expired.' AS Message, NULL AS JoinType, NULL AS OrgId, NULL AS OrgName;
        LEAVE main_block;
    END IF;

    -- Already a member?
    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = v_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsMember > 0 THEN
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;
        SELECT 1 AS IsSuccess, CONCAT('You are already a member of ', v_OrgName, '.') AS Message,
               'ALREADY_MEMBER' AS JoinType, v_OrgId AS OrgId, v_OrgName AS OrgName;
        LEAVE main_block;
    END IF;

    -- Lookup IDs
    SELECT LookupValueId INTO v_AcceptedLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'ACCEPTED' LIMIT 1;

    SELECT LookupValueId INTO v_MemberRoleLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'MEMBER' LIMIT 1;

    SELECT LookupValueId INTO v_ApprovedMemLkpId FROM LookupValues lv
    JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Mark invitation as ACCEPTED
    UPDATE OrgInvitations
    SET    StatusLkpId  = v_AcceptedLkpId,
           AcceptedAt   = NOW(),
           InvitedUserId = p_UserId
    WHERE  OrgInvitationId = p_InvitationId;

    -- Direct join: invitation = admin approval, no separate review needed
    INSERT INTO OrgMembers
        (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
    VALUES
        (v_OrgId, p_UserId, v_MemberRoleLkpId, v_ApprovedMemLkpId, NOW(), p_UserId)
    ON DUPLICATE KEY UPDATE
        StatusLkpId     = v_ApprovedMemLkpId,
        JoinedAt        = NOW(),
        IsDeleted       = 0,
        DeletedAt       = NULL,
        DeletedBy       = NULL;

    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;

    -- Get invitee display name
    SELECT CONCAT(up.FirstName, ' ', up.LastName) INTO v_InviteeName
    FROM   UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    -- Notify each FOUNDER/ADMIN (they can see the new member immediately)
    SET v_AdminDone = 0;
    OPEN admin_cur;
    admin_loop: LOOP
        FETCH admin_cur INTO v_AdminUserId;
        IF v_AdminDone = 1 THEN LEAVE admin_loop; END IF;
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_AdminUserId, v_OrgId,
            'INVITE_ACCEPTED',
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' joined ', v_OrgName),
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' accepted your invitation and has joined ',
                   v_OrgName, ' as a member.'),
            v_OrgId, 'ORG'
        );
    END LOOP;
    CLOSE admin_cur;

    SELECT 1 AS IsSuccess,
           CONCAT('Welcome to ', v_OrgName, '! You are now a member.') AS Message,
           'DIRECT_JOINED' AS JoinType,
           v_OrgId   AS OrgId,
           v_OrgName AS OrgName;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Cancel
-- Admin cancels a pending/opened invitation.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Cancel //
CREATE PROCEDURE Org_Invite_Cancel(
    IN p_InvitationId      INT UNSIGNED,
    IN p_CancelledByUserId INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId       INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusCode  VARCHAR(20)  DEFAULT NULL;
    DECLARE v_RoleCode    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_CancelledId INT UNSIGNED DEFAULT NULL;

    SELECT oi.OrgId, lv.ValueCode INTO v_OrgId, v_StatusCode
    FROM OrgInvitations oi
    JOIN LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    -- Permission check
    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = v_OrgId AND om.UserId = p_CancelledByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to cancel invitations.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess, 'Only pending or opened invitations can be cancelled.' AS Message;
        LEAVE main_block;
    END IF;

    UPDATE OrgInvitations
    SET StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                       JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                       WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'CANCELLED'),
        CancelledAt = NOW(),
        DeletedBy   = p_CancelledByUserId
    WHERE OrgInvitationId = p_InvitationId;

    SELECT 1 AS IsSuccess, 'Invitation cancelled.' AS Message;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Decline
-- Called by the INVITEE to decline a pending invitation.
-- Permission: verified by matching InviteValue to the user's phone/email.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Decline //
CREATE PROCEDURE Org_Invite_Decline(
    IN p_InvitationId INT UNSIGNED,
    IN p_UserId       INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_OrgId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_InviteValue  VARCHAR(150) DEFAULT NULL;
    DECLARE v_StatusCode   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Mobile       VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email        VARCHAR(150) DEFAULT NULL;
    DECLARE v_CancelledId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName      VARCHAR(200) DEFAULT NULL;
    DECLARE v_InviteeName  VARCHAR(200) DEFAULT NULL;
    DECLARE v_AdminUserId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_AdminDone    TINYINT(1)   DEFAULT 0;

    DECLARE admin_cur CURSOR FOR
        SELECT DISTINCT om.UserId
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId = v_OrgId
          AND  lt.TypeCode = 'MEMBER_ROLE'
          AND  lv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_AdminDone = 1;

    -- Fetch invitation + current status + org
    SELECT oi.OrgId, oi.InviteValue, lv.ValueCode
    INTO   v_OrgId, v_InviteValue, v_StatusCode
    FROM   OrgInvitations oi
    JOIN   LookupValues lv ON lv.LookupValueId = oi.StatusLkpId
    WHERE  oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT  1;

    IF v_StatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message;
        LEAVE main_block;
    END IF;

    IF v_StatusCode NOT IN ('PENDING','OPENED') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('This invitation is already ', LOWER(v_StatusCode), '.') AS Message;
        LEAVE main_block;
    END IF;

    -- Verify caller is the invitee by matching phone / email
    SELECT u.Mobile, u.Email
    INTO   v_Mobile, v_Email
    FROM   Users u
    WHERE  u.UserId = p_UserId AND u.IsDeleted = 0
    LIMIT  1;

    IF v_InviteValue != v_Mobile AND v_InviteValue != LOWER(IFNULL(v_Email,'')) THEN
        SELECT 0 AS IsSuccess, 'You are not the recipient of this invitation.' AS Message;
        LEAVE main_block;
    END IF;

    -- Get CANCELLED lookup value
    SELECT lv.LookupValueId INTO v_CancelledId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'CANCELLED'
    LIMIT  1;

    UPDATE OrgInvitations
    SET    StatusLkpId = v_CancelledId,
           CancelledAt = NOW(),
           UpdatedAt   = NOW()
    WHERE  OrgInvitationId = p_InvitationId;

    -- Get org name and invitee name for notification
    SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = v_OrgId LIMIT 1;

    SELECT CONCAT(up.FirstName, ' ', up.LastName) INTO v_InviteeName
    FROM UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

    -- Notify each FOUNDER/ADMIN of the org
    SET v_AdminDone = 0;
    OPEN admin_cur;
    admin_loop: LOOP
        FETCH admin_cur INTO v_AdminUserId;
        IF v_AdminDone = 1 THEN LEAVE admin_loop; END IF;
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType)
        VALUES (
            v_AdminUserId, v_OrgId,
            'INVITE_DECLINED',
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' declined your invitation'),
            CONCAT(IFNULL(v_InviteeName, 'A user'), ' has declined the invitation to join ',
                   v_OrgName, '.'),
            v_OrgId, 'ORG'
        );
    END LOOP;
    CLOSE admin_cur;

    SELECT 1 AS IsSuccess, 'Invitation declined.' AS Message, v_OrgId AS OrgId;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_Resend
-- Resets the invitation: new token + new expiry + status PENDING.
-- App layer re-sends SMS/Email with the new link.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_Resend //
CREATE PROCEDURE Org_Invite_Resend(
    IN p_InvitationId      INT UNSIGNED,
    IN p_RequestedByUserId INT UNSIGNED,
    IN p_NewToken          VARCHAR(128),
    IN p_NewExpiry         DATETIME,
    IN p_InviteBaseUrl     VARCHAR(500)
)
main_block: BEGIN
    DECLARE v_OrgId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_RoleCode   VARCHAR(50)  DEFAULT NULL;
    DECLARE v_InviteValue VARCHAR(255) DEFAULT NULL;
    DECLARE v_InviteTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_CountryCode VARCHAR(6)  DEFAULT NULL;
    DECLARE v_InvitedUserId INT UNSIGNED DEFAULT NULL;

    SELECT oi.OrgId, oi.InviteValue, oi.InviteTypeLkpId, oi.CountryCode, oi.InvitedUserId
    INTO v_OrgId, v_InviteValue, v_InviteTypeLkpId, v_CountryCode, v_InvitedUserId
    FROM OrgInvitations oi
    WHERE oi.OrgInvitationId = p_InvitationId AND oi.IsDeleted = 0
    LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invitation not found.' AS Message, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = v_OrgId AND om.UserId = p_RequestedByUserId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        SELECT 0 AS IsSuccess, 'You do not have permission to resend invitations.' AS Message, NULL AS InviteToken, NULL AS InviteLink;
        LEAVE main_block;
    END IF;

    UPDATE OrgInvitations
    SET InviteToken  = p_NewToken,
        TokenExpiry  = p_NewExpiry,
        StatusLkpId  = (SELECT LookupValueId FROM LookupValues lv
                        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                        WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'PENDING'),
        SentAt       = NOW(),
        OpenedAt     = NULL
    WHERE OrgInvitationId = p_InvitationId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Invitation refreshed.' AS Message,
           p_NewToken AS InviteToken,
           CONCAT(p_InviteBaseUrl, p_NewToken) AS InviteLink,
           v_InviteValue   AS InviteValue,
           v_CountryCode   AS CountryCode,
           v_InvitedUserId AS InvitedUserId;
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_List
-- Paginated list of invitations for an org (admin view).
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_List //
CREATE PROCEDURE Org_Invite_List(
    IN p_OrgId        INT UNSIGNED,
    IN p_RequestorId  INT UNSIGNED,
    IN p_StatusCode   VARCHAR(20),    -- NULL = all
    IN p_PageNumber   INT UNSIGNED,
    IN p_PageSize     INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_RoleCode VARCHAR(50) DEFAULT NULL;
    DECLARE v_Offset   INT UNSIGNED;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = p_OrgId AND om.UserId = p_RequestorId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        -- Return two empty result sets so ExecuteDynamicPagedListAsync
        -- does not throw (it expects data rows + TotalCount)
        SELECT NULL AS OrgInvitationId WHERE FALSE;
        SELECT 0 AS TotalCount;
        LEAVE main_block;
    END IF;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    -- Auto-expire any lapsed PENDING invitations for this org before listing
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.OrgId = p_OrgId AND oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                            JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                            WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING');

    SELECT
        oi.OrgInvitationId,
        lv_type.ValueCode       AS InviteType,
        oi.InviteValue,
        oi.CountryCode,
        lv_status.ValueCode     AS StatusCode,
        lv_status.ValueName     AS StatusName,
        oi.SentAt,
        oi.TokenExpiry,
        oi.OpenedAt,
        oi.AcceptedAt,
        oi.CancelledAt,
        oi.DeliveryStatus,
        -- Invited user info (NULL if not on platform)
        oi.InvitedUserId,
        up_inv.FirstName        AS InviteeName,
        up_inv.LastName         AS InviteeLastName,
        up_inv.ProfilePhoto     AS InviteePhoto,
        -- Inviter info
        up_by.FirstName         AS InvitedByName,
        up_by.ProfilePhoto      AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = oi.InviteTypeLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up_by     ON up_by.UserId = oi.InvitedByUserId
    LEFT JOIN UserProfiles up_inv ON up_inv.UserId = oi.InvitedUserId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode)
    ORDER BY oi.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- TotalCount
    SELECT COUNT(*) AS TotalCount
    FROM OrgInvitations oi
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode);
END //

-- ─────────────────────────────────────────────────────────────
-- Org_Invite_GetPendingForUser
-- Called after login/register to auto-consume a pending invite
-- that matches the user's phone or email.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_GetPendingForUser //
CREATE PROCEDURE Org_Invite_GetPendingForUser(
    IN p_UserId  INT UNSIGNED
)
main_block: BEGIN
    -- Get the user's phone and email for matching
    DECLARE v_Mobile VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email  VARCHAR(150) DEFAULT NULL;

    SELECT Mobile, Email INTO v_Mobile, v_Email
    FROM Users WHERE UserId = p_UserId AND IsDeleted = 0 LIMIT 1;

    -- Auto-expire lapsed tokens first
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND (
          oi.InvitedUserId = p_UserId
          OR oi.InviteValue = v_Mobile
          OR oi.InviteValue = LOWER(IFNULL(v_Email,''))
      )
      AND oi.StatusLkpId IN (
          SELECT LookupValueId FROM LookupValues lv2
          JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
          WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode IN ('PENDING','OPENED')
      );

    SELECT
        oi.OrgInvitationId,
        oi.OrgId,
        o.OrgName,
        o.LogoUrl               AS OrgLogo,
        o.City                  AS OrgCity,
        oi.InviteToken,
        lv_status.ValueCode     AS StatusCode,
        oi.TokenExpiry,
        CONCAT(up.FirstName, ' ', up.LastName) AS InvitedByName,
        up.ProfilePhoto         AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN Organisations o         ON o.OrgId = oi.OrgId
    JOIN LookupValues lv_status  ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up         ON up.UserId = oi.InvitedByUserId
    WHERE oi.IsDeleted = 0
      AND lv_status.ValueCode IN ('PENDING','OPENED')
      AND oi.TokenExpiry > NOW()
      AND (
          oi.InvitedUserId = p_UserId                          -- direct match for existing users
          OR oi.InviteValue = v_Mobile                         -- phone match
          OR oi.InviteValue = LOWER(IFNULL(v_Email,''))        -- email match
      )
    ORDER BY oi.CreatedAt DESC
    LIMIT 5;
END //

DELIMITER ;


-- ════════════════════════════════════════════════════════════════
-- Applications — Volunteer withdraw own application
-- Rule: blocked within 24 hours of project start (ONE_TIME / RECURRING)
-- ════════════════════════════════════════════════════════════════

DROP PROCEDURE IF EXISTS Application_Withdraw;

DELIMITER //
CREATE PROCEDURE Application_Withdraw(
    IN p_ApplicationId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED
)
BEGIN
    DECLARE v_ProjectId      INT UNSIGNED;
    DECLARE v_StatusCode     VARCHAR(50);
    DECLARE v_RecurStart     DATE;
    DECLARE v_SessionStart   TIME;
    DECLARE v_SchType        VARCHAR(50);
    DECLARE v_WithdrawnLkpId INT UNSIGNED;

    -- Fetch application + linked project schedule info
    SELECT
        pa.ProjectId,
        lv_app.ValueCode        AS StatusCode,
        p.RecurStart,
        p.SessionStartTime,
        lv_sched.ValueCode      AS SchedType
    INTO v_ProjectId, v_StatusCode, v_RecurStart, v_SessionStart, v_SchType
    FROM ProjectApplications pa
    JOIN LookupValues lv_app   ON lv_app.LookupValueId  = pa.StatusLkpId
    JOIN Projects p            ON p.ProjectId            = pa.ProjectId
    JOIN LookupValues lv_sched ON lv_sched.LookupValueId = p.ProjectTypeLkpId
    WHERE pa.ApplicationId = p_ApplicationId
      AND pa.UserId        = p_UserId
      AND pa.IsDeleted     = 0
    LIMIT 1;

    -- Application not found or doesn't belong to user
    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;

    -- Already withdrawn, rejected, or completed
    ELSEIF v_StatusCode NOT IN ('PENDING', 'APPROVED') THEN
        SELECT 0 AS IsSuccess, 'This application cannot be withdrawn.' AS Message;

    -- APPROVED: enforce 24-hour gate for fixed-schedule projects
    -- PENDING: always allow (admin has not reviewed yet)
    ELSEIF v_StatusCode = 'APPROVED'
       AND v_SchType IN ('ONE_TIME', 'RECURRING') AND v_RecurStart IS NOT NULL
       AND TIMESTAMPDIFF(HOUR, NOW(),
             CASE WHEN v_SessionStart IS NOT NULL
                  THEN TIMESTAMP(v_RecurStart, v_SessionStart)
                  ELSE TIMESTAMP(v_RecurStart, '00:00:00')
             END) < 24 THEN
        SELECT 0 AS IsSuccess,
               'You cannot withdraw within 24 hours of the project start.' AS Message;

    ELSE
        SELECT lv2.LookupValueId INTO v_WithdrawnLkpId
        FROM LookupValues lv2
        JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
        WHERE lt2.TypeCode = 'APPLICATION_STATUS' AND lv2.ValueCode = 'WITHDRAWN'
        LIMIT 1;

        UPDATE ProjectApplications
        SET    StatusLkpId = v_WithdrawnLkpId,
               UpdatedAt   = NOW(),
               UpdatedBy   = p_UserId
        WHERE  ApplicationId = p_ApplicationId
          AND  UserId        = p_UserId;

        SELECT 1 AS IsSuccess, 'Your application has been withdrawn.' AS Message;
    END IF;
END //
DELIMITER ;


-- ════════════════════════════════════════════════════════════════
-- Support — Phase 1: Log contact submission to AuditLogs
-- ════════════════════════════════════════════════════════════════

DROP PROCEDURE IF EXISTS Support_LogContact;

DELIMITER //
CREATE PROCEDURE Support_LogContact(
    IN p_UserId         INT UNSIGNED,
    IN p_CategoryCode   VARCHAR(50),
    IN p_Subject        VARCHAR(255),
    IN p_Description    TEXT,
    IN p_ContactEmail   VARCHAR(150),
    IN p_ContactName    VARCHAR(100),
    IN p_IpAddress      VARCHAR(45),
    IN p_AttachmentUrl  VARCHAR(2048)
)
BEGIN
    INSERT INTO AuditLogs (
        UserId,
        Action,
        EntityName,
        EntityId,
        NewValue,
        IpAddress,
        CreatedAt
    )
    VALUES (
        p_UserId,
        'SUPPORT_CONTACT',
        'SupportContact',
        NULL,
        JSON_OBJECT(
            'category',      p_CategoryCode,
            'subject',       p_Subject,
            'description',   p_Description,
            'contactEmail',  p_ContactEmail,
            'contactName',   p_ContactName,
            'attachmentUrl', p_AttachmentUrl
        ),
        p_IpAddress,
        NOW()
    );

    SELECT 1 AS IsSuccess, 'Your message has been sent. We\'ll get back to you shortly.' AS Message;
END //

DELIMITER ;


-- ════════════════════════════════════════════════════════════════
-- v5.0 NEW: Marketing & Communication Center — Phase 0 + Phase 1
-- Push + Email only. SMS blocked at three layers on purpose (Settings
-- toggle, CampaignChannel_Save guard, dispatcher check) until Fast2SMS
-- DLT registration completes. See MarketingCommunicationCenter_BRD_v1.0.docx.
-- ════════════════════════════════════════════════════════════════

-- ── Phase 0: User Communication Preferences ──────────────────────

DROP PROCEDURE IF EXISTS UserCommunicationPreference_Get;

DELIMITER //
CREATE PROCEDURE UserCommunicationPreference_Get(IN p_UserId INT UNSIGNED)
BEGIN
    -- No row yet = user is opted in to everything (defaults below), so a brand
    -- new user is reachable without needing a preferences row created up front.
    SELECT base.UserId AS UserId,
           COALESCE(ucp.ReceivePushNotifications, 1)      AS ReceivePushNotifications,
           COALESCE(ucp.ReceivePromotionalEmails, 1)      AS ReceivePromotionalEmails,
           COALESCE(ucp.ReceivePromotionalSms, 1)         AS ReceivePromotionalSms,
           COALESCE(ucp.ReceiveNgoUpdates, 1)             AS ReceiveNgoUpdates,
           COALESCE(ucp.ReceiveDonationAlerts, 1)          AS ReceiveDonationAlerts,
           COALESCE(ucp.ReceiveVolunteerOpportunities, 1) AS ReceiveVolunteerOpportunities
    FROM (SELECT p_UserId AS UserId) base
    LEFT JOIN UserCommunicationPreferences ucp ON ucp.UserId = base.UserId;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS UserCommunicationPreference_Update;

DELIMITER //
CREATE PROCEDURE UserCommunicationPreference_Update(
    IN p_UserId                        INT UNSIGNED,
    IN p_ReceivePushNotifications      TINYINT(1),
    IN p_ReceivePromotionalEmails      TINYINT(1),
    IN p_ReceivePromotionalSms         TINYINT(1),
    IN p_ReceiveNgoUpdates             TINYINT(1),
    IN p_ReceiveDonationAlerts         TINYINT(1),
    IN p_ReceiveVolunteerOpportunities TINYINT(1)
)
BEGIN
    INSERT INTO UserCommunicationPreferences (
        UserId, ReceivePushNotifications, ReceivePromotionalEmails, ReceivePromotionalSms,
        ReceiveNgoUpdates, ReceiveDonationAlerts, ReceiveVolunteerOpportunities, UpdatedAt
    ) VALUES (
        p_UserId,
        COALESCE(p_ReceivePushNotifications, 1), COALESCE(p_ReceivePromotionalEmails, 1), COALESCE(p_ReceivePromotionalSms, 1),
        COALESCE(p_ReceiveNgoUpdates, 1), COALESCE(p_ReceiveDonationAlerts, 1), COALESCE(p_ReceiveVolunteerOpportunities, 1),
        NOW()
    )
    ON DUPLICATE KEY UPDATE
        ReceivePushNotifications      = COALESCE(p_ReceivePushNotifications, ReceivePushNotifications),
        ReceivePromotionalEmails      = COALESCE(p_ReceivePromotionalEmails, ReceivePromotionalEmails),
        ReceivePromotionalSms         = COALESCE(p_ReceivePromotionalSms, ReceivePromotionalSms),
        ReceiveNgoUpdates             = COALESCE(p_ReceiveNgoUpdates, ReceiveNgoUpdates),
        ReceiveDonationAlerts         = COALESCE(p_ReceiveDonationAlerts, ReceiveDonationAlerts),
        ReceiveVolunteerOpportunities = COALESCE(p_ReceiveVolunteerOpportunities, ReceiveVolunteerOpportunities),
        UpdatedAt = NOW();

    SELECT 1 AS IsSuccess, 'Preferences updated.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Campaign CRUD ────────────────────────────────────────

DROP PROCEDURE IF EXISTS Campaign_Create;

DELIMITER //
CREATE PROCEDURE Campaign_Create(
    IN p_CampaignName     VARCHAR(200),
    IN p_InternalNotes    VARCHAR(1000),
    IN p_CampaignTypeCode VARCHAR(50),
    IN p_PriorityCode     VARCHAR(50),
    IN p_CreatedBy        INT UNSIGNED
)
BEGIN
    DECLARE v_TypeLkpId        INT UNSIGNED;
    DECLARE v_PriorityLkpId    INT UNSIGNED;
    DECLARE v_DraftStatusLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_TypeLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE' AND lv.ValueCode = p_CampaignTypeCode LIMIT 1;
    SELECT LookupValueId INTO v_PriorityLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY' AND lv.ValueCode = p_PriorityCode LIMIT 1;
    SELECT LookupValueId INTO v_DraftStatusLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS' AND lv.ValueCode = 'DRAFT' LIMIT 1;

    IF v_TypeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown campaign type: ', p_CampaignTypeCode) AS Message, NULL AS CampaignId;
    ELSEIF v_PriorityLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown priority: ', p_PriorityCode) AS Message, NULL AS CampaignId;
    ELSE
        INSERT INTO Campaigns (CampaignName, InternalNotes, CampaignTypeLkpId, PriorityLkpId, StatusLkpId, CreatedBy)
        VALUES (p_CampaignName, p_InternalNotes, v_TypeLkpId, v_PriorityLkpId, v_DraftStatusLkpId, p_CreatedBy);

        SELECT 1 AS IsSuccess, 'Campaign created.' AS Message, LAST_INSERT_ID() AS CampaignId;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_Update;

DELIMITER //
CREATE PROCEDURE Campaign_Update(
    IN p_CampaignId       INT UNSIGNED,
    IN p_CampaignName     VARCHAR(200),
    IN p_InternalNotes    VARCHAR(1000),
    IN p_CampaignTypeCode VARCHAR(50),
    IN p_PriorityCode     VARCHAR(50),
    IN p_ScheduleType     VARCHAR(20),
    IN p_ScheduledAt      DATETIME,
    IN p_TimezoneName     VARCHAR(60),
    IN p_UpdatedBy        INT UNSIGNED
)
BEGIN
    DECLARE v_TypeLkpId     INT UNSIGNED;
    DECLARE v_PriorityLkpId INT UNSIGNED;
    DECLARE v_CurrentStatusCode VARCHAR(50);

    SELECT lv.ValueCode INTO v_CurrentStatusCode
    FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;

    IF v_CurrentStatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Campaign not found.' AS Message;
    ELSEIF v_CurrentStatusCode NOT IN ('DRAFT', 'SCHEDULED') THEN
        SELECT 0 AS IsSuccess, 'Only Draft or Scheduled campaigns can be edited.' AS Message;
    ELSE
        IF p_CampaignTypeCode IS NOT NULL THEN
            SELECT LookupValueId INTO v_TypeLkpId FROM LookupValues lv
                JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'MKTG_CAMPAIGN_TYPE' AND lv.ValueCode = p_CampaignTypeCode LIMIT 1;
        END IF;
        IF p_PriorityCode IS NOT NULL THEN
            SELECT LookupValueId INTO v_PriorityLkpId FROM LookupValues lv
                JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'MKTG_CAMPAIGN_PRIORITY' AND lv.ValueCode = p_PriorityCode LIMIT 1;
        END IF;

        UPDATE Campaigns SET
            CampaignName      = COALESCE(p_CampaignName, CampaignName),
            InternalNotes     = COALESCE(p_InternalNotes, InternalNotes),
            CampaignTypeLkpId = COALESCE(v_TypeLkpId, CampaignTypeLkpId),
            PriorityLkpId     = COALESCE(v_PriorityLkpId, PriorityLkpId),
            ScheduleType      = COALESCE(p_ScheduleType, ScheduleType),
            ScheduledAt       = COALESCE(p_ScheduledAt, ScheduledAt),
            TimezoneName      = COALESCE(p_TimezoneName, TimezoneName),
            UpdatedBy         = p_UpdatedBy,
            UpdatedAt         = NOW()
        WHERE CampaignId = p_CampaignId;

        SELECT 1 AS IsSuccess, 'Campaign updated.' AS Message;
    END IF;
END //
DELIMITER ;

-- Generic status transition — used by the /cancel endpoint and internally by
-- the Hangfire dispatch job (Running/Completed/Failed). Terminal states
-- (Completed/Cancelled/Failed) can never transition again.
DROP PROCEDURE IF EXISTS Campaign_SetStatus;

DELIMITER //
CREATE PROCEDURE Campaign_SetStatus(
    IN p_CampaignId    INT UNSIGNED,
    IN p_NewStatusCode VARCHAR(50),
    IN p_HangfireJobId VARCHAR(100),
    IN p_UpdatedBy     INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusCode VARCHAR(50);
    DECLARE v_NewStatusLkpId    INT UNSIGNED;

    SELECT lv.ValueCode INTO v_CurrentStatusCode
    FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;

    IF v_CurrentStatusCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Campaign not found.' AS Message;
    ELSEIF v_CurrentStatusCode IN ('COMPLETED', 'CANCELLED', 'FAILED') THEN
        SELECT 0 AS IsSuccess, CONCAT('Campaign is already ', v_CurrentStatusCode, ' and cannot change state.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_NewStatusLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE lt.TypeCode = 'MKTG_CAMPAIGN_STATUS' AND lv.ValueCode = p_NewStatusCode LIMIT 1;

        IF v_NewStatusLkpId IS NULL THEN
            SELECT 0 AS IsSuccess, CONCAT('Unknown status: ', p_NewStatusCode) AS Message;
        ELSE
            UPDATE Campaigns SET
                StatusLkpId   = v_NewStatusLkpId,
                HangfireJobId = COALESCE(p_HangfireJobId, HangfireJobId),
                UpdatedBy     = p_UpdatedBy,
                UpdatedAt     = NOW()
            WHERE CampaignId = p_CampaignId;

            SELECT 1 AS IsSuccess, CONCAT('Campaign status set to ', p_NewStatusCode, '.') AS Message;
        END IF;
    END IF;
END //
DELIMITER ;


-- ── Phase 1: Channels (Push + Email only — SMS/WhatsApp guarded here too) ──

DROP PROCEDURE IF EXISTS CampaignChannel_Save;

DELIMITER //
CREATE PROCEDURE CampaignChannel_Save(
    IN p_CampaignId      INT UNSIGNED,
    IN p_ChannelCode     VARCHAR(20),
    IN p_PushTitle       VARCHAR(200),
    IN p_PushBody        VARCHAR(500),
    IN p_PushImageUrl    VARCHAR(500),
    IN p_PushDeepLink    VARCHAR(500),
    IN p_PushActionLabel VARCHAR(50),
    IN p_EmailSubject    VARCHAR(255),
    IN p_EmailHtmlBody   MEDIUMTEXT
)
BEGIN
    DECLARE v_ChannelLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_ChannelLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode LIMIT 1;

    IF v_ChannelLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown channel: ', p_ChannelCode) AS Message;
    ELSEIF p_ChannelCode IN ('SMS', 'WHATSAPP') THEN
        -- Phase 1 scope guard — see Settings.COMMUNICATION.CAMPAIGN_SMS_ENABLED
        SELECT 0 AS IsSuccess, CONCAT(p_ChannelCode, ' channel is not yet enabled for campaigns.') AS Message;
    ELSE
        INSERT INTO CampaignChannels (
            CampaignId, ChannelLkpId, PushTitle, PushBody, PushImageUrl, PushDeepLink, PushActionLabel,
            EmailSubject, EmailHtmlBody
        ) VALUES (
            p_CampaignId, v_ChannelLkpId, p_PushTitle, p_PushBody, p_PushImageUrl, p_PushDeepLink, p_PushActionLabel,
            p_EmailSubject, p_EmailHtmlBody
        )
        ON DUPLICATE KEY UPDATE
            PushTitle       = VALUES(PushTitle),
            PushBody        = VALUES(PushBody),
            PushImageUrl    = VALUES(PushImageUrl),
            PushDeepLink    = VALUES(PushDeepLink),
            PushActionLabel = VALUES(PushActionLabel),
            EmailSubject    = VALUES(EmailSubject),
            EmailHtmlBody   = VALUES(EmailHtmlBody),
            UpdatedAt       = NOW();

        SELECT 1 AS IsSuccess, 'Channel saved.' AS Message;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignChannel_Delete;

DELIMITER //
CREATE PROCEDURE CampaignChannel_Delete(IN p_CampaignId INT UNSIGNED, IN p_ChannelCode VARCHAR(20))
BEGIN
    DELETE cc FROM CampaignChannels cc
    JOIN LookupValues lv ON lv.LookupValueId = cc.ChannelLkpId
    JOIN LookupTypes lt  ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE cc.CampaignId = p_CampaignId AND lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode;

    SELECT 1 AS IsSuccess, 'Channel removed.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Audience Rule (single rule per campaign — see BRD Phase 2 for the
--    composable, reusable Segment Builder) ─────────────────────────────────

DROP PROCEDURE IF EXISTS CampaignAudienceRule_Save;

DELIMITER //
CREATE PROCEDURE CampaignAudienceRule_Save(
    IN p_CampaignId    INT UNSIGNED,
    IN p_RuleType      VARCHAR(30),
    IN p_RuleValueJson JSON
)
BEGIN
    IF p_RuleType NOT IN ('ALL', 'ACTIVE', 'INACTIVE', 'NEW', 'BY_ORG', 'BY_ROLE') THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown audience rule type: ', p_RuleType) AS Message;
    ELSE
        DELETE FROM CampaignAudienceRules WHERE CampaignId = p_CampaignId;
        INSERT INTO CampaignAudienceRules (CampaignId, RuleType, RuleValueJson)
        VALUES (p_CampaignId, p_RuleType, p_RuleValueJson);

        SELECT 1 AS IsSuccess, 'Audience rule saved.' AS Message;
    END IF;
END //
DELIMITER ;

-- Estimates (and caches onto Campaigns.EstimatedRecipients) the recipient count
-- for the campaign's current audience rule. Called on-demand from the wizard
-- (step transitions), not per keystroke — a live COUNT() here is a deliberate,
-- documented simplification of the BRD's fuller pre-aggregated-cache proposal;
-- revisit if usage patterns make this a real hot path.
-- 'BY_ROLE' roleCodes accepts FOUNDER / ADMIN / MODERATOR / MEMBER (MEMBER_ROLE
-- lookup codes) plus the virtual code DONOR (resolved via DonationTransactions,
-- which is not an OrgMembers role at all).
DROP PROCEDURE IF EXISTS Campaign_EstimateAudience;

DELIMITER //
CREATE PROCEDURE Campaign_EstimateAudience(IN p_CampaignId INT UNSIGNED)
BEGIN
    DECLARE v_RuleType VARCHAR(30);
    DECLARE v_RuleJson JSON;
    DECLARE v_Count     INT UNSIGNED DEFAULT 0;

    SELECT RuleType, RuleValueJson INTO v_RuleType, v_RuleJson
    FROM CampaignAudienceRules
    WHERE CampaignId = p_CampaignId
    ORDER BY CampaignAudienceRuleId DESC
    LIMIT 1;

    IF v_RuleType = 'ALL' THEN
        SELECT COUNT(*) INTO v_Count FROM Users WHERE IsDeleted = 0 AND IsActive = 1;

    ELSEIF v_RuleType = 'ACTIVE' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND LastLoginAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'INACTIVE' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND (LastLoginAt IS NULL OR LastLoginAt < DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '30') AS UNSIGNED) DAY));

    ELSEIF v_RuleType = 'NEW' THEN
        SELECT COUNT(*) INTO v_Count FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND CreatedAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'BY_ORG' THEN
        SELECT COUNT(DISTINCT om.UserId) INTO v_Count
        FROM OrgMembers om
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.orgIds', CAST(om.OrgId AS JSON));

    ELSEIF v_RuleType = 'BY_ROLE' THEN
        SELECT COUNT(DISTINCT combined.UserId) INTO v_Count
        FROM (
            SELECT om.UserId
            FROM OrgMembers om
            JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
            JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
            WHERE om.IsDeleted = 0
              AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE(lv.ValueCode))
            UNION
            SELECT dt.DonorUserId
            FROM DonationTransactions dt
            JOIN Users u ON u.UserId = dt.DonorUserId AND u.IsDeleted = 0 AND u.IsActive = 1
            WHERE dt.DonorUserId IS NOT NULL
              AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE('DONOR'))
        ) combined;
    END IF;

    UPDATE Campaigns SET EstimatedRecipients = v_Count WHERE CampaignId = p_CampaignId;

    SELECT p_CampaignId AS CampaignId, v_Count AS EstimatedRecipients, v_RuleType AS RuleType;
END //
DELIMITER ;

-- Resolves the campaign's audience rule into concrete CampaignRecipients rows,
-- fanned out across every selected channel, skipping opted-out users and users
-- with no valid delivery address for that channel. Safe to call more than once
-- (INSERT IGNORE on the CampaignId+UserId+ChannelLkpId unique key).
DROP PROCEDURE IF EXISTS Campaign_ResolveRecipients;

DELIMITER //
CREATE PROCEDURE Campaign_ResolveRecipients(IN p_CampaignId INT UNSIGNED)
BEGIN
    DECLARE v_RuleType VARCHAR(30);
    DECLARE v_RuleJson JSON;

    SELECT RuleType, RuleValueJson INTO v_RuleType, v_RuleJson
    FROM CampaignAudienceRules
    WHERE CampaignId = p_CampaignId
    ORDER BY CampaignAudienceRuleId DESC
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_campaign_audience;
    CREATE TEMPORARY TABLE tmp_campaign_audience (UserId INT UNSIGNED PRIMARY KEY);

    IF v_RuleType = 'ALL' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users WHERE IsDeleted = 0 AND IsActive = 1;

    ELSEIF v_RuleType = 'ACTIVE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND LastLoginAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'INACTIVE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND (LastLoginAt IS NULL OR LastLoginAt < DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '30') AS UNSIGNED) DAY));

    ELSEIF v_RuleType = 'NEW' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT UserId FROM Users
        WHERE IsDeleted = 0 AND IsActive = 1
          AND CreatedAt >= DATE_SUB(NOW(), INTERVAL CAST(COALESCE(v_RuleJson->>'$.days', '7') AS UNSIGNED) DAY);

    ELSEIF v_RuleType = 'BY_ORG' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT om.UserId
        FROM OrgMembers om
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.orgIds', CAST(om.OrgId AS JSON));

    ELSEIF v_RuleType = 'BY_ROLE' THEN
        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT om.UserId
        FROM OrgMembers om
        JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
        JOIN Users u ON u.UserId = om.UserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE om.IsDeleted = 0
          AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE(lv.ValueCode));

        INSERT IGNORE INTO tmp_campaign_audience (UserId)
        SELECT DISTINCT dt.DonorUserId
        FROM DonationTransactions dt
        JOIN Users u ON u.UserId = dt.DonorUserId AND u.IsDeleted = 0 AND u.IsActive = 1
        WHERE dt.DonorUserId IS NOT NULL
          AND JSON_CONTAINS(v_RuleJson->'$.roleCodes', JSON_QUOTE('DONOR'));
    END IF;

    INSERT IGNORE INTO CampaignRecipients (CampaignId, UserId, ChannelLkpId, QueueStatus)
    SELECT p_CampaignId, a.UserId, cc.ChannelLkpId,
        CASE
            WHEN lv_ch.ValueCode = 'PUSH'  AND COALESCE(pref.ReceivePushNotifications, 1) = 0 THEN 'SKIPPED_OPTOUT'
            WHEN lv_ch.ValueCode = 'EMAIL' AND COALESCE(pref.ReceivePromotionalEmails, 1) = 0 THEN 'SKIPPED_OPTOUT'
            WHEN lv_ch.ValueCode = 'PUSH'  AND NOT EXISTS (SELECT 1 FROM UserDeviceTokens dt WHERE dt.UserId = a.UserId) THEN 'SKIPPED_NO_ADDRESS'
            WHEN lv_ch.ValueCode = 'EMAIL' AND u.Email IS NULL THEN 'SKIPPED_NO_ADDRESS'
            ELSE 'QUEUED'
        END
    FROM tmp_campaign_audience a
    JOIN Users u ON u.UserId = a.UserId
    JOIN CampaignChannels cc ON cc.CampaignId = p_CampaignId
    JOIN LookupValues lv_ch  ON lv_ch.LookupValueId = cc.ChannelLkpId
    LEFT JOIN UserCommunicationPreferences pref ON pref.UserId = a.UserId;

    DROP TEMPORARY TABLE IF EXISTS tmp_campaign_audience;

    SELECT 1 AS IsSuccess, 'Recipients resolved.' AS Message,
           (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = p_CampaignId) AS TotalRecipients,
           (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = p_CampaignId AND QueueStatus = 'QUEUED') AS QueuedRecipients;
END //
DELIMITER ;


-- ── Phase 1: Dispatch support (called by the Hangfire background job) ─────

DROP PROCEDURE IF EXISTS Campaign_GetQueuedRecipients;

DELIMITER //
CREATE PROCEDURE Campaign_GetQueuedRecipients(
    IN p_CampaignId  INT UNSIGNED,
    IN p_ChannelCode VARCHAR(20),
    IN p_BatchSize   INT
)
BEGIN
    SELECT cr.CampaignRecipientId, cr.UserId, u.Email,
           cc.PushTitle, cc.PushBody, cc.PushImageUrl, cc.PushDeepLink, cc.PushActionLabel,
           cc.EmailSubject, cc.EmailHtmlBody
    FROM CampaignRecipients cr
    JOIN LookupValues lv      ON lv.LookupValueId = cr.ChannelLkpId
    JOIN Users u              ON u.UserId = cr.UserId
    JOIN CampaignChannels cc  ON cc.CampaignId = cr.CampaignId AND cc.ChannelLkpId = cr.ChannelLkpId
    WHERE cr.CampaignId = p_CampaignId
      AND lv.ValueCode = p_ChannelCode
      AND cr.QueueStatus = 'QUEUED'
    ORDER BY cr.CampaignRecipientId
    LIMIT p_BatchSize;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignRecipient_MarkStatus;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_MarkStatus(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_StatusCode          VARCHAR(20),
    IN p_ProviderMessageId   VARCHAR(255),
    IN p_FailReason          VARCHAR(500)
)
BEGIN
    UPDATE CampaignRecipients SET
        QueueStatus       = p_StatusCode,
        ProviderMessageId = COALESCE(p_ProviderMessageId, ProviderMessageId),
        FailReason        = COALESCE(p_FailReason, FailReason),
        SentAt            = CASE WHEN p_StatusCode = 'SENT'      THEN NOW() ELSE SentAt      END,
        DeliveredAt       = CASE WHEN p_StatusCode = 'DELIVERED' THEN NOW() ELSE DeliveredAt END,
        RetryCount        = CASE WHEN p_StatusCode = 'FAILED'    THEN RetryCount + 1 ELSE RetryCount END
    WHERE CampaignRecipientId = p_CampaignRecipientId;

    SELECT 1 AS IsSuccess, 'Recipient status updated.' AS Message;
END //
DELIMITER ;

-- Real delivery acknowledgment from the mobile device itself — called by the app
-- immediately when it actually renders/displays a campaign push (not by the
-- dispatch worker). This is what makes "Delivered" mean "the device actually
-- got it" instead of "Firebase's Admin SDK accepted the send request", which is
-- all CampaignRecipient_MarkStatus's 'SENT' status has ever meant. Ownership-
-- checked (p_UserId must match the row's UserId) so one user can never ack
-- another user's recipient row. Always reports success regardless of whether a
-- row actually matched — this is a best-effort beacon from an untrusted client,
-- deliberately not leaking whether a given CampaignRecipientId exists or belongs
-- to someone else. Won't downgrade a terminal FAILED/SKIPPED_* row.
DROP PROCEDURE IF EXISTS CampaignRecipient_AckDelivered;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_AckDelivered(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_UserId              INT UNSIGNED
)
BEGIN
    UPDATE CampaignRecipients
    SET QueueStatus = 'DELIVERED', DeliveredAt = NOW()
    WHERE CampaignRecipientId = p_CampaignRecipientId
      AND UserId = p_UserId
      AND QueueStatus IN ('SENT', 'QUEUED', 'PROCESSING');

    SELECT 1 AS IsSuccess, 'Acknowledged.' AS Message;
END //
DELIMITER ;

-- Hook for future open/click tracking (pixel + redirect endpoints are a small
-- follow-up, not wired in Phase 1 — see MarketingCommunicationCenter_BRD_v1.0.docx
-- Section 8, "Rich HTML Editor" is Phase 2 scope, tracking pixel belongs with it).
DROP PROCEDURE IF EXISTS CampaignRecipient_MarkEngagement;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_MarkEngagement(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_EngagementType      VARCHAR(20) -- OPENED | CLICKED
)
BEGIN
    UPDATE CampaignRecipients SET
        OpenedAt  = CASE WHEN p_EngagementType = 'OPENED'  AND OpenedAt  IS NULL THEN NOW() ELSE OpenedAt  END,
        ClickedAt = CASE WHEN p_EngagementType = 'CLICKED' AND ClickedAt IS NULL THEN NOW() ELSE ClickedAt END
    WHERE CampaignRecipientId = p_CampaignRecipientId;

    SELECT 1 AS IsSuccess, 'Engagement recorded.' AS Message;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignQueueJob_Create;

DELIMITER //
CREATE PROCEDURE CampaignQueueJob_Create(
    IN p_CampaignId   INT UNSIGNED,
    IN p_BatchNumber  INT UNSIGNED,
    IN p_ChannelCode  VARCHAR(20),
    IN p_BatchSize    INT UNSIGNED
)
BEGIN
    DECLARE v_ChannelLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_ChannelLkpId FROM LookupValues lv
        JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE lt.TypeCode = 'MKTG_CAMPAIGN_CHANNEL' AND lv.ValueCode = p_ChannelCode LIMIT 1;

    INSERT INTO CampaignQueueJobs (CampaignId, BatchNumber, ChannelLkpId, BatchSize, Status, StartedAt)
    VALUES (p_CampaignId, p_BatchNumber, v_ChannelLkpId, p_BatchSize, 'PROCESSING', NOW());

    SELECT 1 AS IsSuccess, 'Queue job created.' AS Message, LAST_INSERT_ID() AS CampaignQueueJobId;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CampaignQueueJob_MarkStatus;

DELIMITER //
CREATE PROCEDURE CampaignQueueJob_MarkStatus(
    IN p_CampaignQueueJobId BIGINT UNSIGNED,
    IN p_Status             VARCHAR(20),
    IN p_ErrorMessage       VARCHAR(1000)
)
BEGIN
    UPDATE CampaignQueueJobs SET
        Status       = p_Status,
        ErrorMessage = COALESCE(p_ErrorMessage, ErrorMessage),
        RetryCount   = CASE WHEN p_Status = 'FAILED' THEN RetryCount + 1 ELSE RetryCount END,
        CompletedAt  = CASE WHEN p_Status IN ('COMPLETED', 'FAILED') THEN NOW() ELSE CompletedAt END
    WHERE CampaignQueueJobId = p_CampaignQueueJobId;

    SELECT 1 AS IsSuccess, 'Queue job status updated.' AS Message;
END //
DELIMITER ;


-- ── Phase 1: Lists, detail, dashboard ─────────────────────────────

DROP PROCEDURE IF EXISTS Campaign_GetList;

DELIMITER //
CREATE PROCEDURE Campaign_GetList(
    IN p_StatusCode VARCHAR(50),
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT c.CampaignId, c.CampaignName, c.ScheduleType, c.ScheduledAt, c.EstimatedRecipients,
           lv_type.ValueCode   AS CampaignTypeCode, lv_type.ValueName AS CampaignTypeName,
           lv_pri.ValueCode    AS PriorityCode,
           lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
           c.CreatedAt, c.CreatedBy,
           CONCAT(up.FirstName, ' ', up.LastName) AS CreatedByName,
           (SELECT GROUP_CONCAT(lv_ch.ValueCode) FROM CampaignChannels cc
              JOIN LookupValues lv_ch ON lv_ch.LookupValueId = cc.ChannelLkpId
              WHERE cc.CampaignId = c.CampaignId) AS Channels,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId) AS TotalRecipients,
           -- SentCount = accepted by FCM (not proof of arrival); DeliveredCount = real
           -- device-confirmed delivery via CampaignRecipient_AckDelivered. Keep both —
           -- SentCount was the old (misleadingly-labeled) "DeliveredCount" meaning.
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus IN ('SENT','DELIVERED')) AS SentCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus = 'DELIVERED') AS DeliveredCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.OpenedAt IS NOT NULL) AS OpenedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.ClickedAt IS NOT NULL) AS ClickedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus = 'FAILED') AS FailedCount
    FROM Campaigns c
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = c.CampaignTypeLkpId
    JOIN LookupValues lv_pri    ON lv_pri.LookupValueId    = c.PriorityLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    LEFT JOIN UserProfiles up ON up.UserId = c.CreatedBy
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'))
    ORDER BY c.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Campaigns c
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'));
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_GetById;

DELIMITER //
CREATE PROCEDURE Campaign_GetById(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT c.CampaignId, c.CampaignName, c.InternalNotes,
           lv_type.ValueCode   AS CampaignTypeCode,
           lv_pri.ValueCode    AS PriorityCode,
           lv_status.ValueCode AS StatusCode,
           c.ScheduleType, c.ScheduledAt, c.TimezoneName, c.EstimatedRecipients,
           c.CreatedAt, c.CreatedBy, c.UpdatedAt,
           (SELECT RuleType FROM CampaignAudienceRules WHERE CampaignId = c.CampaignId ORDER BY CampaignAudienceRuleId DESC LIMIT 1) AS AudienceRuleType,
           (SELECT RuleValueJson FROM CampaignAudienceRules WHERE CampaignId = c.CampaignId ORDER BY CampaignAudienceRuleId DESC LIMIT 1) AS AudienceRuleValueJson,
           (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                'channelCode',     lv_ch.ValueCode,
                'pushTitle',       cc.PushTitle,
                'pushBody',        cc.PushBody,
                'pushImageUrl',    cc.PushImageUrl,
                'pushDeepLink',    cc.PushDeepLink,
                'pushActionLabel', cc.PushActionLabel,
                'emailSubject',    cc.EmailSubject,
                'emailHtmlBody',   cc.EmailHtmlBody
            ))
            FROM CampaignChannels cc
            JOIN LookupValues lv_ch ON lv_ch.LookupValueId = cc.ChannelLkpId
            WHERE cc.CampaignId = c.CampaignId) AS ChannelsJson
    FROM Campaigns c
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = c.CampaignTypeLkpId
    JOIN LookupValues lv_pri    ON lv_pri.LookupValueId    = c.PriorityLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Campaign_GetHistoryDetail;

DELIMITER //
CREATE PROCEDURE Campaign_GetHistoryDetail(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        c.CampaignId, c.CampaignName,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId) AS TotalRecipients,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus IN ('SENT','DELIVERED')) AS SentCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus = 'DELIVERED') AS DeliveredCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND OpenedAt IS NOT NULL) AS OpenedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND ClickedAt IS NOT NULL) AS ClickedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus = 'FAILED') AS FailedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus LIKE 'SKIPPED%') AS SkippedCount
    FROM Campaigns c
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;
END //
DELIMITER ;

-- Per-recipient drill-down for a completed (or any) campaign — phone/email/name
-- + individual delivery status per row. Paged (Col<T>/DynamicRow 2-result-set
-- convention: rows, then TotalCount). Super Admin only, via CampaignController.
DROP PROCEDURE IF EXISTS Campaign_GetRecipientList;

DELIMITER //
CREATE PROCEDURE Campaign_GetRecipientList(
    IN p_CampaignId INT UNSIGNED,
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT cr.CampaignRecipientId, cr.UserId,
           CONCAT(up.FirstName, ' ', up.LastName) AS UserName,
           u.Email, u.Mobile,
           lv_ch.ValueCode AS ChannelCode,
           cr.QueueStatus, cr.FailReason, cr.RetryCount,
           cr.QueuedAt, cr.SentAt, cr.DeliveredAt, cr.OpenedAt, cr.ClickedAt
    FROM CampaignRecipients cr
    JOIN Users u              ON u.UserId = cr.UserId
    LEFT JOIN UserProfiles up ON up.UserId = cr.UserId
    JOIN LookupValues lv_ch   ON lv_ch.LookupValueId = cr.ChannelLkpId
    WHERE cr.CampaignId = p_CampaignId
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR cr.QueueStatus = p_StatusCode)
    ORDER BY cr.CampaignRecipientId
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM CampaignRecipients cr
    WHERE cr.CampaignId = p_CampaignId
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR cr.QueueStatus = p_StatusCode);
END //
DELIMITER ;

-- Lightweight contact lookup for the /test-send preview action — deliberately
-- does not touch CampaignRecipients (test sends must never pollute real metrics).
DROP PROCEDURE IF EXISTS User_GetContactsByIds;

DELIMITER //
CREATE PROCEDURE User_GetContactsByIds(IN p_UserIdsCsv VARCHAR(2000))
BEGIN
    SELECT UserId, Email FROM Users
    WHERE IsDeleted = 0 AND FIND_IN_SET(UserId, p_UserIdsCsv) > 0;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS Communication_GetDashboardStats;

DELIMITER //
CREATE PROCEDURE Communication_GetDashboardStats()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'PUSH'  AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalPushSent,
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'EMAIL' AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalEmailSent,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus = 'FAILED') AS TotalFailed,
        -- TotalSent = FCM/SES accepted the send request (not proof of arrival).
        -- TotalDelivered = real device-confirmed delivery via CampaignRecipient_AckDelivered
        -- (mobile calls this the moment it actually renders a push). These used to be
        -- the same number under the "TotalDelivered" name — that was misleading.
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus IN ('SENT','DELIVERED')) AS TotalSent,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus = 'DELIVERED') AS TotalDelivered,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus NOT LIKE 'SKIPPED%') AS TotalAttempted,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE OpenedAt IS NOT NULL) AS TotalOpened,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE ClickedAt IS NOT NULL) AS TotalClicked,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'RUNNING'   AND c.IsDeleted = 0) AS ActiveCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'SCHEDULED' AND c.IsDeleted = 0) AS ScheduledCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'DRAFT'     AND c.IsDeleted = 0) AS DraftCampaigns;
END //
DELIMITER ;


-- ── 3.27 Project_SelfCheckIn ─────────────────────────────────────────────────
-- v5.0 NEW: Self-attendance for OPEN_SIGNUP projects.
-- Volunteer marks their own attendance without QR scan.
-- Same time-window enforcement as QR scan (QR_BUFFER_MINUTES before start → session end).
-- Finds or auto-creates a ProjectSessions row for today's date.
DELIMITER //
DROP PROCEDURE IF EXISTS Project_SelfCheckIn //
CREATE PROCEDURE Project_SelfCheckIn(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_ScheduleTypeCode VARCHAR(20)  DEFAULT NULL;
    DECLARE v_JoinTypeCode     VARCHAR(20)  DEFAULT NULL;
    DECLARE v_StartTime        TIME         DEFAULT NULL;
    DECLARE v_EndTime          TIME         DEFAULT NULL;
    DECLARE v_OneTimeDate      DATE         DEFAULT NULL;
    DECLARE v_RecurStart       DATE         DEFAULT NULL;
    DECLARE v_RecurEnd         DATE         DEFAULT NULL;
    DECLARE v_RecurDays        VARCHAR(200) DEFAULT NULL;
    DECLARE v_FlexFromDate     DATE         DEFAULT NULL;
    DECLARE v_FlexToDate       DATE         DEFAULT NULL;
    DECLARE v_HasApproval      INT          DEFAULT 0;
    DECLARE v_IsCheckedIn      INT          DEFAULT 0;
    DECLARE v_Buffer           INT          DEFAULT 15;
    DECLARE v_NowIST           DATETIME;
    DECLARE v_TodayIST         DATE;
    DECLARE v_SessionDate      DATE         DEFAULT NULL;
    DECLARE v_WindowStart      DATETIME;
    DECLARE v_WindowEnd        DATETIME;
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_AttendedLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId      INT UNSIGNED DEFAULT NULL;

    -- Fetch project schedule + join type
    SELECT ptv.ValueCode, jtv.ValueCode,
           p.SessionStartTime, p.SessionEndTime,
           p.OneTimeDate, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate
    INTO   v_ScheduleTypeCode, v_JoinTypeCode,
           v_StartTime, v_EndTime,
           v_OneTimeDate, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFromDate, v_FlexToDate
    FROM   Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId    = jtv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0
    LIMIT  1;

    IF v_ScheduleTypeCode IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message, NULL AS SessionId;

    ELSEIF v_JoinTypeCode != 'OPEN_SIGNUP' THEN
        SELECT 0 AS IsSuccess, 'This project requires a QR scan for attendance.' AS Message, NULL AS SessionId;

    ELSE
        -- Verify APPROVED application
        SELECT COUNT(*) INTO v_HasApproval
        FROM   ProjectApplications pa
        JOIN   LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        WHERE  pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId
          AND  lv.ValueCode = 'APPROVED' AND pa.IsDeleted = 0;

        IF v_HasApproval = 0 THEN
            SELECT 0 AS IsSuccess, 'You are not registered for this project.' AS Message, NULL AS SessionId;

        ELSE
            SET v_NowIST   = CONVERT_TZ(NOW(), '+00:00', '+05:30');
            SET v_TodayIST = DATE(v_NowIST);

            -- Determine effective session date for today
            IF v_ScheduleTypeCode = 'ONE_TIME' THEN
                SET v_SessionDate = v_OneTimeDate;

            ELSEIF v_ScheduleTypeCode = 'RECURRING' THEN
                IF v_TodayIST BETWEEN v_RecurStart AND v_RecurEnd
                   AND FIND_IN_SET(LEFT(UPPER(DAYNAME(v_TodayIST)), 3),
                                   UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;

            ELSEIF v_ScheduleTypeCode = 'FLEXIBLE' THEN
                IF v_TodayIST BETWEEN v_FlexFromDate AND v_FlexToDate THEN
                    SET v_SessionDate = v_TodayIST;
                END IF;
            END IF;

            IF v_SessionDate IS NULL THEN
                SELECT 0 AS IsSuccess,
                       'There is no scheduled session for today.' AS Message,
                       NULL AS SessionId;

            ELSE
                -- Read buffer from Settings (default 15 min, same as QR)
                SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
                FROM   Settings
                WHERE  SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0
                LIMIT  1;
                IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

                -- Time window: [sessionStart - buffer, sessionEnd] in IST
                SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
                SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

                IF v_NowIST < v_WindowStart THEN
                    SELECT 0 AS IsSuccess,
                           CONCAT('Check-in opens at ',
                                  TIME_FORMAT(TIME(v_WindowStart), '%h:%i %p'),
                                  '. Please return when the session is about to start.') AS Message,
                           NULL AS SessionId;

                ELSEIF v_NowIST > v_WindowEnd THEN
                    SELECT 0 AS IsSuccess,
                           CONCAT('Session ended at ',
                                  TIME_FORMAT(v_EndTime, '%h:%i %p'),
                                  '. Check-in is no longer available.') AS Message,
                           NULL AS SessionId;

                ELSE
                    -- Find or create session row for today
                    SELECT SessionId INTO v_SessionId
                    FROM   ProjectSessions
                    WHERE  ProjectId = p_ProjectId AND SessionDate = v_SessionDate AND IsDeleted = 0
                    LIMIT  1;

                    IF v_SessionId IS NULL THEN
                        SELECT LookupValueId INTO v_StatusLkpId
                        FROM   LookupValues lv
                        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                        WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING'
                        LIMIT  1;

                        INSERT INTO ProjectSessions
                               (ProjectId, SessionDate, StartTime, EndTime, SessionStatusLkpId, CreatedBy)
                        VALUES (p_ProjectId, v_SessionDate, v_StartTime, v_EndTime, v_StatusLkpId, p_UserId);
                        SET v_SessionId = LAST_INSERT_ID();
                    END IF;

                    -- Already checked in?
                    SELECT COUNT(*) INTO v_IsCheckedIn
                    FROM   ProjectAttendance
                    WHERE  SessionId = v_SessionId AND UserId = p_UserId;

                    IF v_IsCheckedIn > 0 THEN
                        SELECT 0 AS IsSuccess,
                               'You have already marked your attendance for this session.' AS Message,
                               v_SessionId AS SessionId;

                    ELSE
                        SELECT LookupValueId INTO v_AttendedLkpId
                        FROM   LookupValues lv
                        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                        WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                        LIMIT  1;

                        INSERT INTO ProjectAttendance
                               (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
                        VALUES (v_SessionId, p_UserId, NOW(), v_AttendedLkpId, p_UserId);

                        SELECT 1 AS IsSuccess,
                               'Attendance marked successfully! Thank you for being there.' AS Message,
                               v_SessionId AS SessionId;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;
END //

DELIMITER ;


-- ============================================================
-- v5.1 ADDITIONS — NGO REVIEWS MODULE
-- New tables + LookupTypes + SPs only.
-- AvgRating / RatingCount on Organisations already existed —
-- now wired to OrgReview_Add / OrgReview_Delete.
-- ============================================================

-- ── New LookupTypes ─────────────────────────────────────────
INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('REVIEWER_TYPE',    'Reviewer Type',    'Type of reviewer leaving an NGO review',     1, 1),
('REVIEW_MEDIA_TYPE','Review Media Type','Media type attached to an NGO review',        1, 1),
('REVIEW_SORT',      'Review Sort',      'Sort order options for NGO review listing',   1, 1);

-- REVIEWER_TYPE values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'VOLUNTEER', 'Volunteer', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE' UNION ALL
SELECT LookupTypeId, 'DONOR',     'Donor',     2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE' UNION ALL
SELECT LookupTypeId, 'GENERAL',   'General',   3, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE';

-- REVIEW_MEDIA_TYPE values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'IMAGE', 'Image', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_MEDIA_TYPE' UNION ALL
SELECT LookupTypeId, 'VIDEO', 'Video', 2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_MEDIA_TYPE';

-- REVIEW_SORT values
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'RECENT',  'Most Recent',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'HELPFUL', 'Most Helpful',  2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'HIGHEST', 'Highest Rating',3, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'LOWEST',  'Lowest Rating', 4, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT';

-- ── New Tables ───────────────────────────────────────────────

CREATE TABLE OrgReviews (
    ReviewId            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId               INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    OverallRating       TINYINT         NOT NULL CHECK (OverallRating BETWEEN 1 AND 5),
    ReviewText          TEXT            NOT NULL,
    ReviewerTypeLkpId   INT UNSIGNED    NOT NULL,
    HelpfulCount        INT UNSIGNED    NOT NULL DEFAULT 0,
    NotHelpfulCount     INT UNSIGNED    NOT NULL DEFAULT 0,
    IsApproved          TINYINT(1)      NOT NULL DEFAULT 1  COMMENT 'Set 0 to hold for moderation',
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (ReviewId),
    UNIQUE  KEY uq_org_user_review   (OrgId, UserId),
    KEY     idx_orgreview_orgid      (OrgId),
    KEY     idx_orgreview_userid     (UserId),
    KEY     idx_orgreview_approved   (OrgId, IsApproved, IsDeleted),
    CONSTRAINT fk_orgreview_org  FOREIGN KEY (OrgId)             REFERENCES Organisations (OrgId),
    CONSTRAINT fk_orgreview_user FOREIGN KEY (UserId)            REFERENCES Users         (UserId),
    CONSTRAINT fk_orgreview_type FOREIGN KEY (ReviewerTypeLkpId) REFERENCES LookupValues  (LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgReviewMedia (
    MediaId             INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    MediaUrl            VARCHAR(500)    NOT NULL,
    MediaTypeLkpId      INT UNSIGNED    NOT NULL,
    OrderNo             TINYINT UNSIGNED NOT NULL DEFAULT 1,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (MediaId),
    KEY idx_reviewmedia_reviewid (ReviewId),
    CONSTRAINT fk_reviewmedia_review FOREIGN KEY (ReviewId)      REFERENCES OrgReviews  (ReviewId),
    CONSTRAINT fk_reviewmedia_type   FOREIGN KEY (MediaTypeLkpId) REFERENCES LookupValues (LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgReviewResponses (
    ResponseId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    OrgId               INT UNSIGNED    NOT NULL,
    RespondedByUserId   INT UNSIGNED    NOT NULL,
    ResponseText        TEXT            NOT NULL,
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (ResponseId),
    UNIQUE KEY uq_review_response (ReviewId),
    KEY idx_reviewresponse_orgid (OrgId),
    CONSTRAINT fk_reviewresp_review FOREIGN KEY (ReviewId)          REFERENCES OrgReviews   (ReviewId),
    CONSTRAINT fk_reviewresp_org    FOREIGN KEY (OrgId)             REFERENCES Organisations(OrgId),
    CONSTRAINT fk_reviewresp_user   FOREIGN KEY (RespondedByUserId) REFERENCES Users        (UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgReviewHelpful (
    HelpfulId           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    IsHelpful           TINYINT(1)      NOT NULL COMMENT '1=helpful, 0=not helpful',
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (HelpfulId),
    UNIQUE KEY uq_review_user_helpful (ReviewId, UserId),
    KEY idx_reviewhelpful_reviewid (ReviewId),
    CONSTRAINT fk_reviewhelpful_review FOREIGN KEY (ReviewId) REFERENCES OrgReviews (ReviewId),
    CONSTRAINT fk_reviewhelpful_user   FOREIGN KEY (UserId)   REFERENCES Users       (UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── Stored Procedures — NGO Reviews ─────────────────────────

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_Add
-- Inserts a review + media rows, then recalculates AvgRating
-- and RatingCount on Organisations.
-- p_MediaUrls  : JSON array of {url, type} objects  e.g. [{"url":"…","type":"IMAGE"}]
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_Add //
CREATE PROCEDURE OrgReview_Add(
    IN p_UserId           INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_OverallRating    TINYINT,
    IN p_ReviewText       TEXT,
    IN p_ReviewerType     VARCHAR(50),
    IN p_MediaUrls        JSON
)
BEGIN
    DECLARE v_ReviewId          INT UNSIGNED DEFAULT 0;
    DECLARE v_ReviewerTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_MediaTypeLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_MediaTypeCode     VARCHAR(50);
    DECLARE v_MediaUrl          VARCHAR(500);
    DECLARE v_Idx               INT DEFAULT 0;
    DECLARE v_MediaCount        INT DEFAULT 0;
    DECLARE v_AuthorName        VARCHAR(200) DEFAULT '';
    DECLARE v_OrgName           VARCHAR(200) DEFAULT '';

    -- Validate rating range
    IF p_OverallRating < 1 OR p_OverallRating > 5 THEN
        SELECT 0 AS IsSuccess, 'Rating must be between 1 and 5.' AS Message, NULL AS ReviewId;
    ELSE
        -- Resolve ReviewerType lookup
        SELECT lv.LookupValueId INTO v_ReviewerTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'REVIEWER_TYPE' AND lv.ValueCode = p_ReviewerType
        LIMIT 1;

        IF v_ReviewerTypeLkpId IS NULL THEN
            SET v_ReviewerTypeLkpId = (SELECT lv.LookupValueId FROM LookupValues lv
                                       JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                                       WHERE lt.TypeCode = 'REVIEWER_TYPE' AND lv.IsDefault = 1 LIMIT 1);
        END IF;

        -- Insert review (duplicate = user already reviewed this NGO)
        INSERT INTO OrgReviews (OrgId, UserId, OverallRating, ReviewText, ReviewerTypeLkpId)
        VALUES (p_OrgId, p_UserId, p_OverallRating, p_ReviewText, v_ReviewerTypeLkpId)
        ON DUPLICATE KEY UPDATE ReviewId = ReviewId; -- no-op on conflict so we can detect it

        IF ROW_COUNT() = 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reviewed this NGO.' AS Message, NULL AS ReviewId;
        ELSE
            SET v_ReviewId = LAST_INSERT_ID();

            -- Insert media rows
            IF p_MediaUrls IS NOT NULL AND JSON_LENGTH(p_MediaUrls) > 0 THEN
                SET v_MediaCount = JSON_LENGTH(p_MediaUrls);
                WHILE v_Idx < v_MediaCount DO
                    SET v_MediaUrl      = JSON_UNQUOTE(JSON_EXTRACT(p_MediaUrls, CONCAT('$[', v_Idx, '].url')));
                    SET v_MediaTypeCode = JSON_UNQUOTE(JSON_EXTRACT(p_MediaUrls, CONCAT('$[', v_Idx, '].type')));

                    SELECT lv.LookupValueId INTO v_MediaTypeLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'REVIEW_MEDIA_TYPE' AND lv.ValueCode = v_MediaTypeCode
                    LIMIT 1;

                    IF v_MediaTypeLkpId IS NOT NULL THEN
                        INSERT INTO OrgReviewMedia (ReviewId, MediaUrl, MediaTypeLkpId, OrderNo)
                        VALUES (v_ReviewId, v_MediaUrl, v_MediaTypeLkpId, v_Idx + 1);
                    END IF;

                    SET v_Idx = v_Idx + 1;
                END WHILE;
            END IF;

            -- Recalculate AvgRating + RatingCount on Organisations
            UPDATE Organisations
            SET    AvgRating   = (SELECT ROUND(AVG(OverallRating), 2) FROM OrgReviews WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0),
                   RatingCount = (SELECT COUNT(*)                      FROM OrgReviews WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0)
            WHERE  OrgId = p_OrgId;

            -- Fetch author name + org name for notification fan-out in DAL
            SELECT TRIM(CONCAT(IFNULL(up.FirstName,''), ' ', IFNULL(up.LastName,'')))
            INTO   v_AuthorName
            FROM   UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

            SELECT o.OrgName INTO v_OrgName FROM Organisations o WHERE o.OrgId = p_OrgId LIMIT 1;

            SELECT 1 AS IsSuccess, 'Review submitted successfully.' AS Message,
                   v_ReviewId    AS ReviewId,
                   p_UserId      AS ReviewerUserId,
                   v_AuthorName  AS AuthorName,
                   v_OrgName     AS OrgName;
        END IF;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_GetList
-- Returns paged reviews for an NGO with author info, media,
-- NGO response, and current user's helpful vote.
-- p_Sort: RECENT | HELPFUL | HIGHEST | LOWEST
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_GetList //
CREATE PROCEDURE OrgReview_GetList(
    IN p_OrgId        INT UNSIGNED,
    IN p_CurrentUserId INT UNSIGNED,
    IN p_Sort         VARCHAR(20),
    IN p_PageNumber   INT UNSIGNED,
    IN p_PageSize     INT UNSIGNED
)
BEGIN
    DECLARE v_Offset INT DEFAULT 0;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_Sort NOT IN ('RECENT','HELPFUL','HIGHEST','LOWEST') THEN
        SET p_Sort = 'RECENT';
    END IF;

    SELECT
        r.ReviewId,
        r.OverallRating,
        r.ReviewText,
        r.HelpfulCount,
        r.NotHelpfulCount,
        r.CreatedAt,
        -- Author
        u.UserId,
        COALESCE(CONCAT(up.FirstName, ' ', up.LastName), u.Mobile, 'Anonymous') AS AuthorName,
        up.ProfilePhoto                         AS AuthorAvatar,
        lv.ValueCode                            AS ReviewerType,
        -- Has the current user voted on this review?
        (SELECT IsHelpful FROM OrgReviewHelpful
         WHERE ReviewId = r.ReviewId AND UserId = p_CurrentUserId LIMIT 1) AS CurrentUserVote,
        -- Is the current user the review author?
        IF(r.UserId = p_CurrentUserId, 1, 0)                                           AS IsOwnReview,
        -- CanDelete = own review AND submitted within the last 30 days
        IF(r.UserId = p_CurrentUserId AND DATEDIFF(NOW(), r.CreatedAt) <= 30, 1, 0)   AS CanDelete,
        -- NGO response (if any)
        resp.ResponseText,
        resp.CreatedAt                          AS ResponseCreatedAt,
        -- Media JSON array (derived table avoids correlated subquery + ORDER BY issue in MySQL 8)
        media_agg.MediaItems
    FROM  OrgReviews r
    JOIN  Users u                              ON r.UserId    = u.UserId
    LEFT JOIN UserProfiles up                  ON u.UserId    = up.UserId
    JOIN  LookupValues lv                      ON r.ReviewerTypeLkpId = lv.LookupValueId
    LEFT JOIN OrgReviewResponses resp          ON r.ReviewId  = resp.ReviewId AND resp.IsDeleted = 0
    LEFT JOIN (
        SELECT
            m.ReviewId,
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'mediaId',   m.MediaId,
                    'mediaUrl',  m.MediaUrl,
                    'mediaType', IFNULL(mt.ValueCode, 'IMAGE'),
                    'orderNo',   m.OrderNo
                )
            ) AS MediaItems
        FROM  (SELECT * FROM OrgReviewMedia ORDER BY ReviewId, OrderNo) m
        LEFT JOIN LookupValues mt ON m.MediaTypeLkpId = mt.LookupValueId
        GROUP BY m.ReviewId
    ) media_agg ON media_agg.ReviewId = r.ReviewId
    WHERE r.OrgId      = p_OrgId
      AND r.IsApproved = 1
      AND r.IsDeleted  = 0
    ORDER BY
        -- Own review always pinned first so the user immediately sees their own review
        (r.UserId = p_CurrentUserId)             DESC,
        CASE WHEN p_Sort = 'RECENT'  THEN r.CreatedAt     END DESC,
        CASE WHEN p_Sort = 'HELPFUL' THEN r.HelpfulCount  END DESC,
        CASE WHEN p_Sort = 'HIGHEST' THEN r.OverallRating END DESC,
        CASE WHEN p_Sort = 'LOWEST'  THEN r.OverallRating END ASC,
        r.ReviewId DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- TotalCount (second result set for paging)
    SELECT COUNT(*) AS TotalCount
    FROM   OrgReviews
    WHERE  OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_GetAggregate
-- Returns avg, count, and per-star histogram percentages.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_GetAggregate //
CREATE PROCEDURE OrgReview_GetAggregate(
    IN p_OrgId INT UNSIGNED
)
BEGIN
    SELECT
        ROUND(AVG(OverallRating), 1)                                           AS AvgRating,
        COUNT(*)                                                               AS TotalReviews,
        ROUND(SUM(OverallRating = 5) / COUNT(*) * 100, 0)                     AS Star5Pct,
        ROUND(SUM(OverallRating = 4) / COUNT(*) * 100, 0)                     AS Star4Pct,
        ROUND(SUM(OverallRating = 3) / COUNT(*) * 100, 0)                     AS Star3Pct,
        ROUND(SUM(OverallRating = 2) / COUNT(*) * 100, 0)                     AS Star2Pct,
        ROUND(SUM(OverallRating = 1) / COUNT(*) * 100, 0)                     AS Star1Pct
    FROM  OrgReviews
    WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_MarkHelpful
-- Upserts a helpful vote; updates denormalized counts on review.
-- p_IsHelpful: 1 = helpful, 0 = not helpful
-- Passing the same value again REMOVES the vote (toggle).
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_MarkHelpful //
CREATE PROCEDURE OrgReview_MarkHelpful(
    IN p_UserId    INT UNSIGNED,
    IN p_ReviewId  INT UNSIGNED,
    IN p_IsHelpful TINYINT
)
BEGIN
    DECLARE v_ExistingVote  TINYINT     DEFAULT NULL;
    DECLARE v_HelpfulId     INT UNSIGNED DEFAULT NULL;

    SELECT HelpfulId, IsHelpful INTO v_HelpfulId, v_ExistingVote
    FROM   OrgReviewHelpful
    WHERE  ReviewId = p_ReviewId AND UserId = p_UserId
    LIMIT  1;

    IF v_HelpfulId IS NULL THEN
        -- First vote
        INSERT INTO OrgReviewHelpful (ReviewId, UserId, IsHelpful) VALUES (p_ReviewId, p_UserId, p_IsHelpful);
    ELSEIF v_ExistingVote = p_IsHelpful THEN
        -- Same vote again → remove (toggle off)
        DELETE FROM OrgReviewHelpful WHERE HelpfulId = v_HelpfulId;
    ELSE
        -- Switching vote
        UPDATE OrgReviewHelpful SET IsHelpful = p_IsHelpful WHERE HelpfulId = v_HelpfulId;
    END IF;

    -- Recalculate denormalized counts
    UPDATE OrgReviews
    SET    HelpfulCount    = (SELECT COUNT(*) FROM OrgReviewHelpful WHERE ReviewId = p_ReviewId AND IsHelpful = 1),
           NotHelpfulCount = (SELECT COUNT(*) FROM OrgReviewHelpful WHERE ReviewId = p_ReviewId AND IsHelpful = 0)
    WHERE  ReviewId = p_ReviewId;

    SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_Delete
-- Soft-deletes a review (owner only); recalculates org rating.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_Delete //
CREATE PROCEDURE OrgReview_Delete(
    IN p_UserId    INT UNSIGNED,
    IN p_ReviewId  INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_ReviewerUserId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OverallRating  TINYINT      DEFAULT 0;
    DECLARE v_AuthorName     VARCHAR(200) DEFAULT '';
    DECLARE v_OrgName        VARCHAR(200) DEFAULT '';
    DECLARE v_DaysOld        INT          DEFAULT 0;

    SELECT OrgId, UserId, OverallRating, DATEDIFF(NOW(), CreatedAt)
    INTO   v_OrgId, v_ReviewerUserId, v_OverallRating, v_DaysOld
    FROM   OrgReviews
    WHERE  ReviewId = p_ReviewId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Review not found or you are not the author.' AS Message,
               NULL AS ReviewerUserId, NULL AS AuthorName, NULL AS OverallRating, NULL AS OrgName, NULL AS OrgId;
    ELSEIF v_DaysOld > 30 THEN
        SELECT 0 AS IsSuccess, 'Reviews can only be deleted within 30 days of posting.' AS Message,
               NULL AS ReviewerUserId, NULL AS AuthorName, NULL AS OverallRating, NULL AS OrgName, NULL AS OrgId;
    ELSE
        -- Fetch author name + org name for notification
        SELECT TRIM(CONCAT(IFNULL(up.FirstName,''), ' ', IFNULL(up.LastName,'')))
        INTO   v_AuthorName
        FROM   UserProfiles up WHERE up.UserId = v_ReviewerUserId LIMIT 1;

        SELECT o.OrgName INTO v_OrgName FROM Organisations o WHERE o.OrgId = v_OrgId LIMIT 1;

        UPDATE OrgReviews SET IsDeleted = 1 WHERE ReviewId = p_ReviewId;

        -- Recalculate org aggregate
        UPDATE Organisations
        SET    AvgRating   = IFNULL((SELECT ROUND(AVG(OverallRating),2) FROM OrgReviews WHERE OrgId = v_OrgId AND IsApproved=1 AND IsDeleted=0), 0.00),
               RatingCount = (SELECT COUNT(*) FROM OrgReviews WHERE OrgId = v_OrgId AND IsApproved=1 AND IsDeleted=0)
        WHERE  OrgId = v_OrgId;

        SELECT 1 AS IsSuccess, 'Review deleted.' AS Message,
               v_ReviewerUserId AS ReviewerUserId,
               v_AuthorName     AS AuthorName,
               v_OverallRating  AS OverallRating,
               v_OrgName        AS OrgName,
               v_OrgId          AS OrgId;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_AddResponse
-- NGO admin adds or updates the official response to a review.
-- Only admins of the org (OrgMembers.Role = ADMIN) may respond.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_AddResponse //
CREATE PROCEDURE OrgReview_AddResponse(
    IN p_AdminUserId   INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_ReviewId      INT UNSIGNED,
    IN p_ResponseText  TEXT
)
BEGIN
    DECLARE v_IsAdmin        TINYINT      DEFAULT 0;
    DECLARE v_ReviewOrg      INT UNSIGNED DEFAULT NULL;
    DECLARE v_ReviewerUserId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName        VARCHAR(200) DEFAULT '';

    -- Verify admin membership
    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON om.RoleLkpId = lv.LookupValueId
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  om.UserId   = p_AdminUserId
      AND  om.OrgId    = p_OrgId
      AND  lt.TypeCode = 'ORG_ROLE'
      AND  lv.ValueCode IN ('ADMIN','SUPER_ADMIN')
      AND  om.IsActive = 1;

    -- Verify review belongs to this org; capture reviewer UserId for notification
    SELECT OrgId, UserId INTO v_ReviewOrg, v_ReviewerUserId
    FROM   OrgReviews WHERE ReviewId = p_ReviewId AND IsDeleted = 0 LIMIT 1;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Only NGO admins can respond to reviews.' AS Message,
               NULL AS ReviewerUserId, NULL AS OrgName;
    ELSEIF v_ReviewOrg IS NULL OR v_ReviewOrg != p_OrgId THEN
        SELECT 0 AS IsSuccess, 'Review not found for this NGO.' AS Message,
               NULL AS ReviewerUserId, NULL AS OrgName;
    ELSE
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = p_OrgId LIMIT 1;

        INSERT INTO OrgReviewResponses (ReviewId, OrgId, RespondedByUserId, ResponseText)
        VALUES (p_ReviewId, p_OrgId, p_AdminUserId, p_ResponseText)
        ON DUPLICATE KEY UPDATE
            ResponseText      = VALUES(ResponseText),
            RespondedByUserId = VALUES(RespondedByUserId),
            IsDeleted         = 0,
            UpdatedAt         = NOW();

        SELECT 1 AS IsSuccess, 'Response posted successfully.' AS Message,
               v_ReviewerUserId AS ReviewerUserId,
               v_OrgName        AS OrgName;
    END IF;
END //

-- ─────────────────────────────────────────────────────────────
-- OrgReview_Report
-- Records a review report. Reuses existing flag mechanism.
-- Simple table-less approach: increments a ReportCount column
-- (we add ReportCount on OrgReviews via ALTER in the patch).
-- For MVP this SP just returns success; moderation is manual.
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS OrgReview_Report //
CREATE PROCEDURE OrgReview_Report(
    IN p_UserId   INT UNSIGNED,
    IN p_ReviewId INT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM OrgReviews WHERE ReviewId = p_ReviewId AND IsDeleted = 0) THEN
        SELECT 0 AS IsSuccess, 'Review not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Review reported. Our team will review it shortly.' AS Message;
    END IF;
END //

DELIMITER ;

-- SchemaVersions record
INSERT INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1', 'v5.1: NGO Reviews module — 3 new LookupTypes (REVIEWER_TYPE, REVIEW_MEDIA_TYPE, REVIEW_SORT), 14 new LookupValues, 4 new tables (OrgReviews, OrgReviewMedia, OrgReviewResponses, OrgReviewHelpful), 7 new SPs. AvgRating/RatingCount on Organisations now wired to review aggregates.', 'System');

-- ============================================================
-- END OF v5.1 ADDITIONS
-- ============================================================

-- ============================================================
-- v5.1 ADDITIONS: RECURRING + FLEXIBLE Project Flow
-- ============================================================

-- ── Lookup Seeds ─────────────────────────────────────────────

INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType)
VALUES ('SESSION_OPT_OUT_TYPE', 'Session Opt-Out Type',
        'Reason a volunteer was removed from a specific session', 1);

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'CLOSING', 'Closing', 6, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'PROJECT_STATUS';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKED_IN', 'Checked In', 4, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKOUT_MISSED', 'Checkout Missed', 5, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'SELF', 'Self Opt-Out', 1, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'ADMIN_EXCUSED', 'Admin Excused', 2, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'ADMIN_REMOVED', 'Admin Removed', 3, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE';

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'PROJECT_COMPLETE', 'Project Completed', 8, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'BADGE_TYPE';

-- ATTENDANCE_STATUS: volunteer withdrew from a specific session (opt-out). No penalty.
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'WITHDRAWN', 'Withdrawn', 6, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

-- NOTIFICATION_TYPE: sent to checked-in FLEXIBLE volunteers 15 min before session end
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKOUT_REMINDER', 'Checkout Reminder', 85, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

-- NOTIFICATION_TYPE: sent to all approved participants when admin cancels a session
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, 'SESSION_CANCELLED', 'Session Cancelled', 86, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

-- ── Settings Seeds ────────────────────────────────────────────

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
-- ── PROJECT_VALIDATION ─────────────────────────────────────────
('PROJECT',  'OT_MAX_DURATION_HOURS',         '12',          'NUMBER',  'Max hours a ONE_TIME project session can span',                               1),
('PROJECT',  'RECURRING_MAX_DURATION_DAYS',   '90',          'NUMBER',  'Max calendar days a RECURRING project can span',                              1),
('PROJECT',  'RECURRING_MIN_DURATION_DAYS',   '7',           'NUMBER',  'Min calendar days a RECURRING project must span',                             1),
('PROJECT',  'FLEXIBLE_MAX_DURATION_DAYS',    '60',          'NUMBER',  'Max calendar days a FLEXIBLE project can span',                               1),
('PROJECT',  'FLEXIBLE_MIN_DURATION_DAYS',    '3',           'NUMBER',  'Min calendar days a FLEXIBLE project must span',                              1),
-- ── ATTENDANCE ────────────────────────────────────────────────
('PROJECT',  'FLEXIBLE_MAX_DAILY_HOURS',      '8',           'NUMBER',  'Default max hours a volunteer can log per day on FLEXIBLE projects. Project can override upward.',                                           1),
('PROJECT',  'FLEXIBLE_MIN_SESSION_HOURS',    '1',           'NUMBER',  'Default minimum check-in duration (hours) for a FLEXIBLE session to count toward attendance. Project can override.',                        1),
('PROJECT',  'FLEXIBLE_MIN_ATTEND_PCT',       '70',          'NUMBER',  'Default min attendance % (hours-based) for certificate eligibility on FLEXIBLE projects. Project can override upward.',                     1),
('PROJECT',  'RECURRING_MIN_ATTEND_PCT',      '70',          'NUMBER',  'Default min attendance % (session-based) for certificate eligibility on RECURRING projects. Project can override upward.',                  1),
('PROJECT',  'CHECKIN_BUFFER_MINUTES',        '15',          'NUMBER',  'Minutes before SessionStartTime that check-in window opens. Applies to both RECURRING and FLEXIBLE.',                                       0),
('PROJECT',  'AUTO_CHECKOUT_GRACE_MINUTES',   '30',          'NUMBER',  'Minutes after SessionEndTime before Hangfire auto-marks CHECKED_IN records as CHECKOUT_MISSED.',                                            0),
-- ── (legacy keys — kept for backward compat with existing SPs; will be removed when SPs are updated) ──
('PROJECT',  'FLEX_CHECKIN_OPEN_MINUTES',     '15',          'NUMBER',  'LEGACY: use CHECKIN_BUFFER_MINUTES. Minutes before session start that FLEXIBLE check-in opens.',                                           0),
('PROJECT',  'FLEX_CHECKOUT_BUFFER_MINUTES',  '30',          'NUMBER',  'LEGACY: use AUTO_CHECKOUT_GRACE_MINUTES. Minutes after session end before CHECKOUT_MISSED is applied.',                                     0),
('PROJECT',  'RECURRING_NOSHOW_GRACE_MINUTES','30',          'NUMBER',  'Minutes after RECURRING session end before marking absent volunteers NO_SHOW.',                                                              0),
('PROJECT',  'AUTO_ACTIVATE_LEAD_DAYS',       '0',           'NUMBER',  'Days before start date to auto-activate (0 = same day).',                                                                                   0),
('PROJECT',  'CLOSING_TRIGGER_OFFSET_DAYS',   '0',           'NUMBER',  'LEGACY: use CLOSING_SAME_DAY. Days after project end date to auto-transition to CLOSING.',                                                  0),
('PROJECT',  'SKILL_RATING_WINDOW_DAYS',      '7',           'NUMBER',  'LEGACY: use SESSION_SKILL_RATING_EDIT_DAYS. Days after CLOSING that session skill ratings can be submitted.',                               0),
-- ── CERTIFICATE ───────────────────────────────────────────────
('PROJECT',  'CERT_ISSUE_WINDOW_DAYS',        '14',          'NUMBER',  'Days after project end that admin can manually issue certificates.',                                                                         0),
('PROJECT',  'CERT_AUTO_CLOSE_DAYS',          '21',          'NUMBER',  'Days after CLOSING starts before Hangfire auto-transitions project to COMPLETED (safety net).',                                             0),
-- ── MILESTONE_NOTIFICATION ────────────────────────────────────
('PROJECT',  'MILESTONE_1_PCT',               '25',          'NUMBER',  'First milestone push-notification threshold (% attendance). Sends once per volunteer per project.',                                         0),
('PROJECT',  'MILESTONE_2_PCT',               '50',          'NUMBER',  'Second milestone push-notification threshold (% attendance).',                                                                              0),
('PROJECT',  'MILESTONE_3_PCT',               '75',          'NUMBER',  'Third milestone push-notification threshold (% attendance).',                                                                               0),
('PROJECT',  'MILESTONE_25_ENABLED',          'true',        'BOOLEAN', 'LEGACY: use MILESTONE_1_PCT. Push notification at 25% attendance milestone.',                                                              0),
('PROJECT',  'MILESTONE_50_ENABLED',          'true',        'BOOLEAN', 'LEGACY: use MILESTONE_2_PCT. Push notification at 50% attendance milestone.',                                                              0),
('PROJECT',  'MILESTONE_75_ENABLED',          'true',        'BOOLEAN', 'LEGACY: use MILESTONE_3_PCT. Push notification at 75% attendance milestone.',                                                              0),
-- ── SKILL_RATING ──────────────────────────────────────────────
('PROJECT',  'SESSION_SKILL_RATING_EDIT_DAYS','7',           'NUMBER',  'Days after a session date that admin can edit its per-session skill ratings.',                                                              0),
('PROJECT',  'FINAL_SKILL_RATING_EDIT_DAYS',  '14',          'NUMBER',  'Days after CLOSING starts that admin can still enter/edit final skill ratings before Finalize.',                                            0),
-- ── LIFECYCLE ─────────────────────────────────────────────────
('PROJECT',  'RECURRING_SESSION_GEN_DAYS',    '7',           'NUMBER',  'Days ahead Hangfire pre-generates sessions for RECURRING projects (rolling window).',                                                       0),
('PROJECT',  'PROJECT_REOPEN_ALLOWED',        '1',           'BOOLEAN', 'Whether FLEXIBLE projects can be reopened from CANCELLED state (1=allowed, 0=blocked).',                                                   0),
('PROJECT',  'CLOSING_SAME_DAY',              '1',           'BOOLEAN', 'Auto-move project to CLOSING on the project end date itself (1=yes, 0=next day).',                                                         0),
-- ── PUBLIC: mobile UI defaults ────────────────────────────────
('PROJECT',  'DEFAULT_MIN_ATTEND_PCT',        '70',          'NUMBER',  'Mobile UI floor: min % a volunteer must attend (RECURRING/FLEXIBLE). Admin can raise per-project but not lower below this.',               1),
('PROJECT',  'DEFAULT_MAX_DAILY_HOURS',       '8',           'NUMBER',  'Mobile UI floor: max hours per day on FLEXIBLE projects. Admin can raise per-project but not lower below this.',                           1),
-- ── HANGFIRE_CRON ─────────────────────────────────────────────
('HANGFIRE', 'CRON_GENERATE_SESSIONS',        '0 0 * * *',   'STRING',  'Cron: GenerateSessionsJob — daily midnight UTC',                                                                                            0),
('HANGFIRE', 'CRON_AUTO_ACTIVATE',            '0 * * * *',   'STRING',  'Cron: AutoActivateProjectsJob — hourly',                                                                                                    0),
('HANGFIRE', 'CRON_AUTO_COMPLETE_SESSIONS',   '30 * * * *',  'STRING',  'Cron: AutoCompleteSessionsJob — hourly at :30',                                                                                             0),
('HANGFIRE', 'CRON_AUTO_CHECKOUT',            '*/15 * * * *','STRING',  'Cron: AutoCheckoutMissedJob — every 15 min',                                                                                                0),
('HANGFIRE', 'CRON_CHECKOUT_REMINDER',        '*/5 * * * *', 'STRING',  'Cron: CheckoutReminderJob — every 5 min',                                                                                                  0),
('HANGFIRE', 'CRON_AUTO_CLOSING',             '0 1 * * *',   'STRING',  'Cron: TransitionToClosingJob — daily 1:00 AM UTC',                                                                                         0),
('HANGFIRE', 'CRON_MARK_NOSHOW',              '0 2 * * *',   'STRING',  'Cron: MarkNoShowJob — daily 2:00 AM UTC (RECURRING only)',                                                                                  0),
('HANGFIRE', 'CRON_MILESTONE_CHECK',          '0 3 * * *',   'STRING',  'Cron: MilestoneCheckJob — daily 3:00 AM UTC',                                                                                              0),
('HANGFIRE', 'CRON_AUTO_FINALIZE_CLOSING',    '0 4 * * *',   'STRING',  'Cron: AutoFinalizeStaleClosingJob — daily 4:00 AM UTC (safety net)',                                                                        0),
-- ── (legacy cron keys — used by existing C# Program.cs; kept until Hangfire wiring is updated) ──
('HANGFIRE', 'AUTO_ACTIVATE_CRON',            '0 1 * * *',   'STRING',  'LEGACY: use CRON_AUTO_ACTIVATE. AutoActivateProjectsJob cron.',                                                                            0),
('HANGFIRE', 'MARK_NOSHOW_CRON',              '*/30 * * * *','STRING',  'LEGACY: use CRON_MARK_NOSHOW. MarkNoShowJob cron.',                                                                                         0),
('HANGFIRE', 'AUTO_CHECKOUT_MISSED_CRON',     '*/30 * * * *','STRING',  'LEGACY: use CRON_AUTO_CHECKOUT. AutoCheckoutMissedJob cron.',                                                                              0),
('HANGFIRE', 'TRANSITION_CLOSING_CRON',       '0 2 * * *',   'STRING',  'LEGACY: use CRON_AUTO_CLOSING. TransitionToClosingJob cron.',                                                                              0);

-- ── New Stored Procedures ─────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Project_CreateInitialSessions //
CREATE PROCEDURE Project_CreateInitialSessions(IN p_ProjectId INT UNSIGNED, IN p_CreatedBy INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode     VARCHAR(20);
    DECLARE v_RecurStart   DATE;
    DECLARE v_RecurEnd     DATE;
    DECLARE v_RecurDays    VARCHAR(100);
    DECLARE v_FlexFrom     DATE;
    DECLARE v_FlexTo       DATE;
    DECLARE v_StartTime    TIME;
    DECLARE v_EndTime      TIME;
    DECLARE v_MaxVol       INT UNSIGNED;
    DECLARE v_CurrDate     DATE;
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_Count        INT DEFAULT 0;
    DECLARE v_DayAbbr      VARCHAR(3);

    SELECT ptv.ValueCode, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate, p.SessionStartTime, p.SessionEndTime, p.MaxVolunteers
    INTO   v_TypeCode, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFrom, v_FlexTo, v_StartTime, v_EndTime, v_MaxVol
    FROM   Projects p
    JOIN   LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    IF EXISTS (SELECT 1 FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0 LIMIT 1) THEN
        SELECT 1 AS IsSuccess, 'Sessions already generated.' AS Message, 0 AS SessionCount;
    ELSEIF v_TypeCode = 'RECURRING' AND v_RecurStart IS NOT NULL AND v_RecurEnd IS NOT NULL THEN
        SET v_CurrDate = v_RecurStart;
        WHILE v_CurrDate <= v_RecurEnd DO
            SET v_DayAbbr = LEFT(UPPER(DAYNAME(v_CurrDate)), 3);
            IF FIND_IN_SET(v_DayAbbr, UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
                INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, QrCode, SessionStatusLkpId, CreatedBy)
                VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, UUID(), v_UpcomingLkpId, p_CreatedBy);
                SET v_Count = v_Count + 1;
            END IF;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' recurring sessions.') AS Message, v_Count AS SessionCount;
    ELSEIF v_TypeCode = 'FLEXIBLE' AND v_FlexFrom IS NOT NULL AND v_FlexTo IS NOT NULL THEN
        SET v_CurrDate = v_FlexFrom;
        WHILE v_CurrDate <= v_FlexTo DO
            INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
            VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, v_UpcomingLkpId, p_CreatedBy);
            SET v_Count = v_Count + 1;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' flexible sessions.') AS Message, v_Count AS SessionCount;
    ELSE
        SELECT 0 AS IsSuccess, 'Project type does not support session generation or missing schedule data.' AS Message, 0 AS SessionCount;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_FlexCheckIn //
CREATE PROCEDURE Project_FlexCheckIn(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode         VARCHAR(20);
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionStart     TIME;
    DECLARE v_SessionEnd       TIME;
    DECLARE v_OpenMins         INT DEFAULT 15;
    DECLARE v_CheckedInLkpId   INT UNSIGNED;
    DECLARE v_InProgressLkpId  INT UNSIGNED;
    DECLARE v_IsApproved       INT DEFAULT 0;
    DECLARE v_AlreadyIn        INT DEFAULT 0;
    DECLARE v_StatusCode       VARCHAR(20);

    SELECT ptv.ValueCode, sv.ValueCode
    INTO   v_TypeCode, v_StatusCode
    FROM   Projects p
    JOIN   LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    JOIN   LookupValues sv  ON p.StatusLkpId      = sv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    IF v_TypeCode != 'FLEXIBLE' THEN
        SELECT 0 AS IsSuccess, 'Self check-in is only available for FLEXIBLE projects.' AS Message, NULL AS SessionId;
    ELSEIF v_StatusCode != 'ACTIVE' THEN
        SELECT 0 AS IsSuccess, 'Project is not currently active.' AS Message, NULL AS SessionId;
    ELSE
        SELECT COUNT(*) INTO v_IsApproved
        FROM ProjectApplications pa
        JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
          AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED';

        IF v_IsApproved = 0 THEN
            SELECT 0 AS IsSuccess, 'You are not an approved volunteer for this project.' AS Message, NULL AS SessionId;
        ELSE
            SELECT COALESCE(CAST(SettingValue AS UNSIGNED), 15) INTO v_OpenMins
            FROM Settings WHERE SettingKey = 'FLEX_CHECKIN_OPEN_MINUTES' AND IsDeleted = 0 LIMIT 1;

            SELECT ps.SessionId, ps.StartTime, ps.EndTime
            INTO   v_SessionId, v_SessionStart, v_SessionEnd
            FROM   ProjectSessions ps
            WHERE  ps.ProjectId = p_ProjectId AND ps.SessionDate = CURDATE() AND ps.IsDeleted = 0
            LIMIT 1;

            IF v_SessionId IS NULL THEN
                SELECT 0 AS IsSuccess, 'No session is scheduled for today.' AS Message, NULL AS SessionId;
            ELSEIF CURTIME() < SUBTIME(v_SessionStart, SEC_TO_TIME(v_OpenMins * 60)) THEN
                SELECT 0 AS IsSuccess,
                       CONCAT('Check-in opens at ', TIME_FORMAT(SUBTIME(v_SessionStart, SEC_TO_TIME(v_OpenMins * 60)), '%h:%i %p'), '.') AS Message,
                       NULL AS SessionId;
            ELSEIF CURTIME() > v_SessionEnd THEN
                SELECT 0 AS IsSuccess, 'Today''s session has ended. Check-in is closed.' AS Message, NULL AS SessionId;
            ELSE
                SELECT COUNT(*) INTO v_AlreadyIn
                FROM ProjectAttendance WHERE SessionId = v_SessionId AND UserId = p_UserId;

                IF v_AlreadyIn > 0 THEN
                    SELECT 0 AS IsSuccess, 'You have already checked in for today''s session.' AS Message, v_SessionId AS SessionId;
                ELSE
                    SELECT lv.LookupValueId INTO v_CheckedInLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

                    SELECT lv.LookupValueId INTO v_InProgressLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'IN_PROGRESS' LIMIT 1;

                    INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
                    VALUES (v_SessionId, p_UserId, NOW(), v_CheckedInLkpId, p_UserId);

                    UPDATE ProjectSessions SET SessionStatusLkpId = v_InProgressLkpId
                    WHERE SessionId = v_SessionId;

                    SELECT 1 AS IsSuccess, 'Checked in successfully.' AS Message, v_SessionId AS SessionId;
                END IF;
            END IF;
        END IF;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_FlexCheckOut //
CREATE PROCEDURE Project_FlexCheckOut(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode         VARCHAR(20);
    DECLARE v_SessionId        INT UNSIGNED DEFAULT NULL;
    DECLARE v_SessionEnd       TIME;
    DECLARE v_BufferMins       INT DEFAULT 30;
    DECLARE v_CheckedInLkpId   INT UNSIGNED;
    DECLARE v_AttendedLkpId    INT UNSIGNED;
    DECLARE v_AttendId         INT UNSIGNED DEFAULT NULL;
    DECLARE v_CheckInTime      DATETIME;
    DECLARE v_HoursLogged      DECIMAL(6,2) DEFAULT 0;
    DECLARE v_MaxDailyHours    DECIMAL(4,2) DEFAULT NULL;

    SELECT ptv.ValueCode, p.MaxDailyHours INTO v_TypeCode, v_MaxDailyHours
    FROM Projects p JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    IF v_TypeCode != 'FLEXIBLE' THEN
        SELECT 0 AS IsSuccess, 'Check-out is only available for FLEXIBLE projects.' AS Message, 0 AS HoursLogged;
    ELSE
        SELECT COALESCE(CAST(SettingValue AS UNSIGNED), 30) INTO v_BufferMins
        FROM Settings WHERE SettingKey = 'FLEX_CHECKOUT_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;

        SELECT ps.SessionId, ps.EndTime INTO v_SessionId, v_SessionEnd
        FROM ProjectSessions ps
        WHERE ps.ProjectId = p_ProjectId AND ps.SessionDate = CURDATE() AND ps.IsDeleted = 0
        LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No session found for today.' AS Message, 0 AS HoursLogged;
        ELSEIF ADDTIME(v_SessionEnd, SEC_TO_TIME(v_BufferMins * 60)) < CURTIME() THEN
            SELECT 0 AS IsSuccess, 'Check-out window has closed.' AS Message, 0 AS HoursLogged;
        ELSE
            SELECT lv.LookupValueId INTO v_CheckedInLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

            SELECT pa.AttendanceId, pa.CheckInTime INTO v_AttendId, v_CheckInTime
            FROM ProjectAttendance pa
            WHERE pa.SessionId = v_SessionId AND pa.UserId = p_UserId
              AND pa.AttendStatusLkpId = v_CheckedInLkpId
            LIMIT 1;

            IF v_AttendId IS NULL THEN
                SELECT 0 AS IsSuccess, 'No active check-in found. Please check in first.' AS Message, 0 AS HoursLogged;
            ELSE
                SELECT lv.LookupValueId INTO v_AttendedLkpId
                FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

                SET v_HoursLogged = ROUND(TIMESTAMPDIFF(MINUTE, v_CheckInTime, NOW()) / 60.0, 2);
                IF v_MaxDailyHours IS NOT NULL AND v_HoursLogged > v_MaxDailyHours THEN
                    SET v_HoursLogged = v_MaxDailyHours;
                END IF;

                UPDATE ProjectAttendance
                SET CheckOutTime = NOW(), HoursLogged = v_HoursLogged,
                    AttendStatusLkpId = v_AttendedLkpId, UpdatedAt = NOW()
                WHERE AttendanceId = v_AttendId;

                SELECT 1 AS IsSuccess, 'Checked out successfully.' AS Message, v_HoursLogged AS HoursLogged;
            END IF;
        END IF;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_TransitionToClosing //
CREATE PROCEDURE Project_TransitionToClosing()
BEGIN
    DECLARE v_ActiveLkpId  INT UNSIGNED;
    DECLARE v_ClosingLkpId INT UNSIGNED;
    DECLARE v_OffsetDays   INT DEFAULT 0;
    DECLARE v_Count        INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 0) INTO v_OffsetDays
    FROM Settings WHERE SettingKey = 'CLOSING_TRIGGER_OFFSET_DAYS' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    UPDATE Projects p JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET p.StatusLkpId = v_ClosingLkpId, p.UpdatedAt = NOW()
    WHERE p.StatusLkpId = v_ActiveLkpId AND p.IsDeleted = 0
      AND ptv.ValueCode = 'RECURRING' AND p.RecurEnd IS NOT NULL
      AND DATE_ADD(p.RecurEnd, INTERVAL v_OffsetDays DAY) < CURDATE();
    SET v_Count = v_Count + ROW_COUNT();

    UPDATE Projects p JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET p.StatusLkpId = v_ClosingLkpId, p.UpdatedAt = NOW()
    WHERE p.StatusLkpId = v_ActiveLkpId AND p.IsDeleted = 0
      AND ptv.ValueCode = 'FLEXIBLE' AND p.FlexToDate IS NOT NULL
      AND DATE_ADD(p.FlexToDate, INTERVAL v_OffsetDays DAY) < CURDATE();
    SET v_Count = v_Count + ROW_COUNT();

    SELECT 1 AS IsSuccess, CONCAT('Transitioned ', v_Count, ' project(s) to CLOSING.') AS Message, v_Count AS TransCount;
END //

DROP PROCEDURE IF EXISTS Project_FinalizeClosing //
CREATE PROCEDURE Project_FinalizeClosing(
    IN p_ProjectId       INT UNSIGNED,
    IN p_CompletedBy     INT UNSIGNED,
    IN p_ImpactSummary   TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId               INT UNSIGNED;
    DECLARE v_CompletedLkpId      INT UNSIGNED;
    DECLARE v_CompletedSessionLkpId INT UNSIGNED;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
    ELSE
        INSERT INTO UserSkillRatings (UserId, OrgId, ProjectId, SkillId, Rating, RatedBy, Notes)
        SELECT ssr.UserId, v_OrgId, p_ProjectId, ssr.SkillId, ROUND(AVG(ssr.Rating), 2), ssr.RatedBy, NULL
        FROM UserSessionSkillRatings ssr
        JOIN ProjectSessions ps ON ssr.SessionId = ps.SessionId
        WHERE ps.ProjectId = p_ProjectId
        GROUP BY ssr.UserId, ssr.SkillId, ssr.RatedBy
        ON DUPLICATE KEY UPDATE Rating = ROUND(VALUES(Rating), 2), UpdatedAt = NOW();

        SELECT lv.LookupValueId INTO v_CompletedSessionLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

        UPDATE ProjectSessions SET SessionStatusLkpId = v_CompletedSessionLkpId, UpdatedAt = NOW()
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT lv.LookupValueId INTO v_CompletedLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

        UPDATE Projects SET
            StatusLkpId = v_CompletedLkpId, CompletedAt = NOW(), CompletedBy = p_CompletedBy,
            ImpactSummary = COALESCE(p_ImpactSummary, ImpactSummary),
            BeneficiaryCount = COALESCE(p_BeneficiaryCount, BeneficiaryCount),
            UpdatedAt = NOW()
        WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Project finalized and marked as COMPLETED.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_AutoActivate //
CREATE PROCEDURE Project_AutoActivate()
BEGIN
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_ActiveLkpId   INT UNSIGNED;
    DECLARE v_LeadDays      INT DEFAULT 0;
    DECLARE v_Count         INT DEFAULT 0;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_Done          INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 0) INTO v_LeadDays
    FROM Settings WHERE SettingKey = 'AUTO_ACTIVATE_LEAD_DAYS' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    BEGIN
        DECLARE proj_cursor CURSOR FOR
            SELECT p.ProjectId FROM Projects p
            JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
            WHERE p.StatusLkpId = v_UpcomingLkpId AND p.IsDeleted = 0
              AND ptv.ValueCode IN ('RECURRING', 'FLEXIBLE')
              AND (
                  (ptv.ValueCode = 'RECURRING' AND p.RecurStart IS NOT NULL
                   AND DATE_SUB(p.RecurStart,  INTERVAL v_LeadDays DAY) <= CURDATE())
               OR (ptv.ValueCode = 'FLEXIBLE'  AND p.FlexFromDate IS NOT NULL
                   AND DATE_SUB(p.FlexFromDate, INTERVAL v_LeadDays DAY) <= CURDATE())
              );
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN proj_cursor;
        read_loop: LOOP
            FETCH proj_cursor INTO v_ProjectId;
            IF v_Done THEN LEAVE read_loop; END IF;
            UPDATE Projects SET StatusLkpId = v_ActiveLkpId, UpdatedAt = NOW()
            WHERE ProjectId = v_ProjectId AND IsDeleted = 0;
            CALL Project_CreateInitialSessions(v_ProjectId, 1);
            SET v_Count = v_Count + 1;
        END LOOP;
        CLOSE proj_cursor;
    END;

    SELECT 1 AS IsSuccess, CONCAT('Activated ', v_Count, ' project(s).') AS Message, v_Count AS ActivatedCount;
END //

DROP PROCEDURE IF EXISTS Project_MarkNoShows //
CREATE PROCEDURE Project_MarkNoShows()
BEGIN
    DECLARE v_NoShowLkpId INT UNSIGNED;
    DECLARE v_GraceMins   INT DEFAULT 30;
    DECLARE v_Count       INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 30) INTO v_GraceMins
    FROM Settings WHERE SettingKey = 'RECURRING_NOSHOW_GRACE_MINUTES' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, HoursLogged, AttendStatusLkpId, CreatedBy)
    SELECT ps.SessionId, appr.UserId, NOW(), 0, v_NoShowLkpId, 1
    FROM ProjectSessions ps
    JOIN Projects p ON ps.ProjectId = p.ProjectId
    JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    JOIN (
        SELECT pa.ProjectId, pa.UserId FROM ProjectApplications pa
        JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE pa.IsDeleted = 0 AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'
    ) appr ON appr.ProjectId = ps.ProjectId
    WHERE ptv.ValueCode = 'RECURRING' AND ps.IsDeleted = 0
      AND ps.SessionDate = CURDATE()
      AND ADDTIME(ps.EndTime, SEC_TO_TIME(v_GraceMins * 60)) < CURTIME()
      AND NOT EXISTS (SELECT 1 FROM ProjectAttendance pa2
                      WHERE pa2.SessionId = ps.SessionId AND pa2.UserId = appr.UserId)
      AND NOT EXISTS (SELECT 1 FROM VolunteerSessionOptOuts oo
                      WHERE oo.SessionId = ps.SessionId AND oo.UserId = appr.UserId)
    ON DUPLICATE KEY UPDATE UpdatedAt = NOW();

    SET v_Count = ROW_COUNT();
    SELECT 1 AS IsSuccess, CONCAT('Marked ', v_Count, ' volunteer(s) as NO_SHOW.') AS Message, v_Count AS NoShowCount;
END //

DROP PROCEDURE IF EXISTS Project_AutoCheckoutMissed //
CREATE PROCEDURE Project_AutoCheckoutMissed()
BEGIN
    DECLARE v_CheckedInLkpId      INT UNSIGNED;
    DECLARE v_CheckoutMissedLkpId INT UNSIGNED;
    DECLARE v_BufferMins          INT DEFAULT 30;
    DECLARE v_Count               INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 30) INTO v_BufferMins
    FROM Settings WHERE SettingKey = 'FLEX_CHECKOUT_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckoutMissedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKOUT_MISSED' LIMIT 1;

    UPDATE ProjectAttendance pa
    JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
    JOIN Projects p ON ps.ProjectId = p.ProjectId
    JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    SET pa.CheckOutTime = ADDTIME(ps.EndTime, SEC_TO_TIME(v_BufferMins * 60)),
        pa.HoursLogged = 0, pa.AttendStatusLkpId = v_CheckoutMissedLkpId, pa.UpdatedAt = NOW()
    WHERE ptv.ValueCode = 'FLEXIBLE' AND pa.AttendStatusLkpId = v_CheckedInLkpId
      AND ps.SessionDate = CURDATE()
      AND ADDTIME(ps.EndTime, SEC_TO_TIME(v_BufferMins * 60)) < CURTIME();

    SET v_Count = ROW_COUNT();
    SELECT 1 AS IsSuccess, CONCAT('Marked ', v_Count, ' volunteer(s) as CHECKOUT_MISSED.') AS Message, v_Count AS Count;
END //

DROP PROCEDURE IF EXISTS Project_GetVolunteerEligibility //
CREATE PROCEDURE Project_GetVolunteerEligibility(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalSessions  INT DEFAULT 0;
    DECLARE v_EligSessions   INT DEFAULT 0;
    DECLARE v_AttendedCount  INT DEFAULT 0;
    DECLARE v_HoursLogged    DECIMAL(6,2) DEFAULT 0;
    DECLARE v_MinAttendPct   DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_ApprovalDate   DATETIME DEFAULT NULL;
    DECLARE v_AttendPct      DECIMAL(5,2) DEFAULT 0;
    DECLARE v_IsEligible     TINYINT(1) DEFAULT 0;
    DECLARE v_AttendedLkpId  INT UNSIGNED;

    SELECT p.MinAttendPct INTO v_MinAttendPct
    FROM Projects p WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    SELECT pa.StatusUpdatedAt INTO v_ApprovalDate
    FROM ProjectApplications pa
    JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE pa.ProjectId = p_ProjectId AND pa.UserId = p_UserId AND pa.IsDeleted = 0
      AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_EligSessions
    FROM ProjectSessions ps
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
      AND (v_ApprovalDate IS NULL OR ps.SessionDate >= DATE(v_ApprovalDate));

    SELECT COUNT(*), COALESCE(SUM(pa.HoursLogged), 0)
    INTO v_AttendedCount, v_HoursLogged
    FROM ProjectAttendance pa
    JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND pa.AttendStatusLkpId = v_AttendedLkpId;

    IF v_EligSessions > 0 THEN
        SET v_AttendPct = ROUND((v_AttendedCount / v_EligSessions) * 100, 2);
    END IF;

    SET v_IsEligible = IF(v_MinAttendPct IS NULL OR v_AttendPct >= v_MinAttendPct, 1, 0);

    SELECT v_TotalSessions AS TotalSessions, v_EligSessions AS EligibleSessions,
           v_AttendedCount AS AttendedCount, v_HoursLogged AS TotalHoursLogged,
           v_AttendPct AS AttendancePct, v_MinAttendPct AS MinAttendPct,
           v_IsEligible AS IsEligibleForCert;
END //

DROP PROCEDURE IF EXISTS Project_GetMySessionList //
CREATE PROCEDURE Project_GetMySessionList(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ps.SessionId,
        DATE_FORMAT(ps.SessionDate, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(ps.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(ps.EndTime,   '%H:%i') AS EndTime,
        ssv.ValueCode AS SessionStatus,
        ssv.ValueName AS SessionStatusName,
        pa.CheckInTime, pa.CheckOutTime, pa.HoursLogged,
        asv.ValueCode AS AttendanceStatus,
        asv.ValueName AS AttendanceStatusName,
        pa.IsNoShowExcused, pa.AdminNote,
        oo.OptOutId,
        oov.ValueCode AS OptOutType,
        oov.ValueName AS OptOutTypeName,
        oo.Reason AS OptOutReason,
        (SELECT COUNT(*) FROM UserSessionSkillRatings ssr
         WHERE ssr.SessionId = ps.SessionId AND ssr.UserId = p_UserId) AS RatingCount
    FROM ProjectSessions ps
    LEFT JOIN ProjectAttendance       pa  ON pa.SessionId = ps.SessionId AND pa.UserId = p_UserId
    LEFT JOIN VolunteerSessionOptOuts oo  ON oo.SessionId = ps.SessionId AND oo.UserId = p_UserId
    LEFT JOIN LookupValues            ssv ON ps.SessionStatusLkpId = ssv.LookupValueId
    LEFT JOIN LookupValues            asv ON pa.AttendStatusLkpId  = asv.LookupValueId
    LEFT JOIN LookupValues            oov ON oo.OptOutTypeLkpId    = oov.LookupValueId
    WHERE ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER BY ps.SessionDate ASC, ps.StartTime ASC;
END //

DROP PROCEDURE IF EXISTS Session_Cancel //
CREATE PROCEDURE Session_Cancel(
    IN p_SessionId   INT UNSIGNED,
    IN p_CancelledBy INT UNSIGNED,
    IN p_Reason      TEXT
)
BEGIN
    DECLARE v_CancelledLkpId INT UNSIGNED;
    DECLARE v_Exists         INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_CancelledLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

        UPDATE ProjectSessions
        SET SessionStatusLkpId = v_CancelledLkpId, UpdatedBy = p_CancelledBy, UpdatedAt = NOW()
        WHERE SessionId = p_SessionId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Session cancelled successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Session_OptOut //
CREATE PROCEDURE Session_OptOut(
    IN p_SessionId  INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_OptOutType VARCHAR(20),
    IN p_Reason     TEXT,
    IN p_CreatedBy  INT UNSIGNED
)
BEGIN
    DECLARE v_OptOutTypeLkpId INT UNSIGNED;
    DECLARE v_ProjectId       INT UNSIGNED;

    SELECT ps.ProjectId INTO v_ProjectId
    FROM ProjectSessions ps WHERE ps.SessionId = p_SessionId AND ps.IsDeleted = 0;

    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_OptOutTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'SESSION_OPT_OUT_TYPE'
          AND lv.ValueCode = COALESCE(p_OptOutType, 'SELF') LIMIT 1;

        INSERT INTO VolunteerSessionOptOuts (SessionId, UserId, ProjectId, OptOutTypeLkpId, Reason, CreatedBy)
        VALUES (p_SessionId, p_UserId, v_ProjectId, v_OptOutTypeLkpId, p_Reason, p_CreatedBy)
        ON DUPLICATE KEY UPDATE OptOutTypeLkpId = v_OptOutTypeLkpId, Reason = p_Reason;

        SELECT 1 AS IsSuccess, 'Opt-out recorded successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Certificate_IssueBulk //
CREATE PROCEDURE Certificate_IssueBulk(
    IN p_ProjectId INT UNSIGNED,
    IN p_IssuedBy  INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED
)
BEGIN
    DECLARE v_UserId       INT UNSIGNED;
    DECLARE v_IssuedCount  INT DEFAULT 0;
    DECLARE v_SkippedCount INT DEFAULT 0;
    DECLARE v_MinAttendPct DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_TotalSessions INT DEFAULT 0;
    DECLARE v_AttendedCount INT DEFAULT 0;
    DECLARE v_AttendPct     DECIMAL(5,2) DEFAULT 0;
    DECLARE v_TotalHours    DECIMAL(6,2) DEFAULT 0;
    DECLARE v_CertCode      VARCHAR(20);
    DECLARE v_Done          INT DEFAULT 0;
    DECLARE v_AttendedLkpId INT UNSIGNED;

    SELECT MinAttendPct INTO v_MinAttendPct FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    BEGIN
        DECLARE vol_cursor CURSOR FOR
            SELECT pa.UserId FROM ProjectApplications pa
            JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
            JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
              AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED';
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN vol_cursor;
        read_loop: LOOP
            FETCH vol_cursor INTO v_UserId;
            IF v_Done THEN LEAVE read_loop; END IF;

            IF EXISTS (SELECT 1 FROM VolunteerCertificates
                       WHERE ProjectId = p_ProjectId AND UserId = v_UserId AND IsDeleted = 0) THEN
                SET v_SkippedCount = v_SkippedCount + 1;
            ELSE
                SELECT COUNT(*), COALESCE(SUM(pa2.HoursLogged), 0)
                INTO v_AttendedCount, v_TotalHours
                FROM ProjectAttendance pa2
                JOIN ProjectSessions   ps2 ON pa2.SessionId = ps2.SessionId
                WHERE ps2.ProjectId = p_ProjectId AND pa2.UserId = v_UserId
                  AND pa2.AttendStatusLkpId = v_AttendedLkpId;

                SET v_AttendPct = IF(v_TotalSessions > 0,
                    ROUND((v_AttendedCount / v_TotalSessions) * 100, 2), 0);

                IF v_MinAttendPct IS NULL OR v_AttendPct >= v_MinAttendPct THEN
                    -- Self-healing: ensure the current-year row exists (handles year rollover)
                    INSERT IGNORE INTO IdSequences (SequenceName, CurrentYear, LastValue)
                    VALUES ('CERT', YEAR(NOW()), 0);

                    UPDATE IdSequences SET LastValue = LastValue + 1
                    WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

                    SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
                    FROM IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

                    INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
                    VALUES (v_CertCode, p_ProjectId, v_UserId, p_OrgId, v_TotalHours, p_IssuedBy);

                    SET v_IssuedCount = v_IssuedCount + 1;
                ELSE
                    SET v_SkippedCount = v_SkippedCount + 1;
                END IF;
            END IF;
        END LOOP;
        CLOSE vol_cursor;
    END;

    SELECT 1 AS IsSuccess,
           CONCAT('Issued ', v_IssuedCount, ' certificate(s). Skipped ', v_SkippedCount, '.') AS Message,
           v_IssuedCount AS IssuedCount, v_SkippedCount AS SkippedCount;
END //

DROP PROCEDURE IF EXISTS UserSessionSkillRating_AddUpdate //
CREATE PROCEDURE UserSessionSkillRating_AddUpdate(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_SkillId   INT UNSIGNED,
    IN p_Rating    DECIMAL(3,2),
    IN p_RatedBy   INT UNSIGNED,
    IN p_Notes     TEXT
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;

    SELECT ProjectId INTO v_ProjectId FROM ProjectSessions
    WHERE SessionId = p_SessionId AND IsDeleted = 0;

    IF v_ProjectId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found.' AS Message;
    ELSE
        INSERT INTO UserSessionSkillRatings (SessionId, UserId, ProjectId, SkillId, Rating, RatedBy, Notes)
        VALUES (p_SessionId, p_UserId, v_ProjectId, p_SkillId, p_Rating, p_RatedBy, p_Notes)
        ON DUPLICATE KEY UPDATE Rating = p_Rating, Notes = p_Notes, RatedBy = p_RatedBy, UpdatedAt = NOW();

        SELECT 1 AS IsSuccess, 'Session skill rating saved.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_CheckMilestoneNotification //
CREATE PROCEDURE Project_CheckMilestoneNotification(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalSessions INT DEFAULT 0;
    DECLARE v_AttendedCount INT DEFAULT 0;
    DECLARE v_AttendPct     DECIMAL(5,2) DEFAULT 0;
    DECLARE v_Milestone     INT DEFAULT 0;
    DECLARE v_AttendedLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT COUNT(*) INTO v_TotalSessions
    FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_AttendedCount
    FROM ProjectAttendance pa
    JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND pa.AttendStatusLkpId = v_AttendedLkpId;

    IF v_TotalSessions > 0 THEN
        SET v_AttendPct = ROUND((v_AttendedCount / v_TotalSessions) * 100, 2);
    END IF;

    SET v_Milestone = CASE
        WHEN v_AttendPct >= 75 THEN 75
        WHEN v_AttendPct >= 50 THEN 50
        WHEN v_AttendPct >= 25 THEN 25
        ELSE 0
    END;

    SELECT v_TotalSessions AS TotalSessions, v_AttendedCount AS AttendedCount,
           v_AttendPct AS AttendancePct, v_Milestone AS MilestoneReached;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1-rf', 'v5.1 RECURRING+FLEXIBLE: 3 new Projects columns, 2 new tables, 7 new lookups, 15 settings, 2 updated SPs (Project_GetById, Certificate_Issue), 15 new SPs, 4 Hangfire jobs.', 'System');

-- ============================================================
-- END OF v5.1 RECURRING + FLEXIBLE ADDITIONS
-- ============================================================

-- ============================================================
-- v5.1-rf PATCH 2: Missing LookupValues, SP updates, new SPs
-- ============================================================

-- Missing NOTIFICATION_TYPE LookupValues (PROJECT_CLOSING, MILESTONE_25/50/75)
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue)
SELECT lt.LookupTypeId, vals.code, vals.name, vals.ord, 1
FROM LookupTypes lt
JOIN (
    SELECT 'NOTIFICATION_TYPE' AS tc, 'PROJECT_CLOSING' AS code, 'Project Closing'          AS name, 81 AS ord UNION ALL
    SELECT 'NOTIFICATION_TYPE',        'MILESTONE_25',             'Attendance Milestone 25%',           82       UNION ALL
    SELECT 'NOTIFICATION_TYPE',        'MILESTONE_50',             'Attendance Milestone 50%',           83       UNION ALL
    SELECT 'NOTIFICATION_TYPE',        'MILESTONE_75',             'Attendance Milestone 75%',           84
) vals ON lt.TypeCode = vals.tc;

DELIMITER //

-- ── Updated: UserBadge_Award — add p_SessionId param ────────────────────────
DROP PROCEDURE IF EXISTS UserBadge_Award //
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId    INT UNSIGNED,
    IN p_BadgeCode VARCHAR(50),
    IN p_AwardedBy INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_ProjectId INT UNSIGNED,
    IN p_SessionId INT UNSIGNED
)
BEGIN
    DECLARE v_BadgeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_BadgeName  VARCHAR(100) DEFAULT 'Badge';
    DECLARE v_Exists     INT          DEFAULT 0;
    DECLARE v_BadgeId    INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_BadgeLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'BADGE_TYPE' AND lv.ValueCode = p_BadgeCode LIMIT 1;

    IF v_BadgeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Unknown badge code: ', p_BadgeCode) AS Message,
               NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
    ELSE
        SELECT COUNT(*) INTO v_Exists
        FROM   UserBadges
        WHERE  UserId     = p_UserId
          AND  BadgeLkpId = v_BadgeLkpId
          AND  (p_ProjectId IS NULL OR ProjectId = p_ProjectId)
          AND  IsDeleted   = 0;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess,
                   'This badge has already been awarded to this volunteer.' AS Message,
                   NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
        ELSE
            SELECT ValueName INTO v_BadgeName
            FROM   LookupValues WHERE LookupValueId = v_BadgeLkpId LIMIT 1;

            INSERT INTO UserBadges (UserId, BadgeLkpId, AwardedBy, OrgId, ProjectId)
            VALUES (p_UserId, v_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId);

            SET v_BadgeId = LAST_INSERT_ID();

            SELECT 1 AS IsSuccess, CONCAT(v_BadgeName, ' badge awarded.') AS Message,
                   v_BadgeId AS BadgeId, v_BadgeName AS BadgeName, p_UserId AS UserId;
        END IF;
    END IF;
END //

-- ── Updated: Project_GetSkillRatings — p_SessionId switches between final/session ratings ──
DROP PROCEDURE IF EXISTS Project_GetSkillRatings //
CREATE PROCEDURE Project_GetSkillRatings(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_SessionId INT UNSIGNED
)
BEGIN
    IF p_SessionId IS NOT NULL THEN
        -- Per-session ratings from UserSessionSkillRatings
        SELECT
            ps.ProjectSkillId,
            ps.SkillName,
            COALESCE(ssr.Rating, 0) AS Rating,
            ssr.Notes
        FROM  ProjectSkills ps
        LEFT JOIN UserSessionSkillRatings ssr
              ON  ssr.SkillId    = ps.ProjectSkillId
              AND ssr.UserId     = p_UserId
              AND ssr.ProjectId  = p_ProjectId
              AND ssr.SessionId  = p_SessionId
        WHERE ps.ProjectId = p_ProjectId
        ORDER BY ps.SkillName;
    ELSE
        -- Final project ratings from UserSkillRatings
        SELECT
            ps.ProjectSkillId,
            ps.SkillName,
            COALESCE(usr.Rating, 0) AS Rating,
            usr.Notes
        FROM  ProjectSkills ps
        LEFT JOIN UserSkillRatings usr
              ON  usr.SkillId   = ps.ProjectSkillId
              AND usr.UserId    = p_UserId
              AND usr.ProjectId = p_ProjectId
        WHERE ps.ProjectId = p_ProjectId
        ORDER BY ps.SkillName;
    END IF;
END //

-- ── New: Project_ReopenFromCancelled (FLEXIBLE projects only) ───────────────
DROP PROCEDURE IF EXISTS Project_ReopenFromCancelled //
CREATE PROCEDURE Project_ReopenFromCancelled(
    IN p_ProjectId   INT UNSIGNED,
    IN p_AdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusCode VARCHAR(50) DEFAULT NULL;
    DECLARE v_ScheduleTypeCode  VARCHAR(50) DEFAULT NULL;
    DECLARE v_AllowedSetting    VARCHAR(10) DEFAULT '1';
    DECLARE v_ActiveLkpId       INT UNSIGNED DEFAULT NULL;

    SELECT SettingValue INTO v_AllowedSetting
    FROM Settings WHERE SettingKey = 'PROJECT_REOPEN_ALLOWED' AND IsDeleted = 0 LIMIT 1;

    IF v_AllowedSetting IN ('false', '0') THEN
        SELECT 0 AS IsSuccess, 'Project reopening is disabled by platform settings.' AS Message;
    ELSE
        SELECT projSv.ValueCode, ptv.ValueCode
        INTO   v_CurrentStatusCode, v_ScheduleTypeCode
        FROM   Projects p
        JOIN   LookupValues projSv ON p.StatusLkpId       = projSv.LookupValueId
        LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
        WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

        IF v_CurrentStatusCode IS NULL THEN
            SELECT 0 AS IsSuccess, 'Project not found.' AS Message;
        ELSEIF v_ScheduleTypeCode != 'FLEXIBLE' THEN
            SELECT 0 AS IsSuccess, 'Only FLEXIBLE projects can be reopened.' AS Message;
        ELSEIF v_CurrentStatusCode != 'CANCELLED' THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('Project cannot be reopened: current status is ', v_CurrentStatusCode, '.') AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_ActiveLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

            UPDATE Projects
            SET    StatusLkpId  = v_ActiveLkpId,
                   CancelledAt  = NULL,
                   CancelledBy  = NULL,
                   CancelReason = NULL,
                   UpdatedAt    = NOW()
            WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;

            SELECT 1 AS IsSuccess, 'Project reopened successfully.' AS Message,
                   p_ProjectId AS ProjectId;
        END IF;
    END IF;
END //

-- ── Updated: Application_GetByUser — add progress fields (MyAttendedSessions, MyHoursLogged, etc.) ──
DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset         INT;
    DECLARE v_AttendedLkpId  INT UNSIGNED;
    DECLARE v_CheckedInLkpId INT UNSIGNED;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT lv.LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        pa.UserId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl              AS OrgLogoUrl,
        appSv.ValueCode        AS StatusCode,
        appSv.ValueName        AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        ptv.ValueCode          AS ScheduleTypeCode,
        ptv.ValueName          AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.OneTimeDate,
        p.FlexFromDate,
        p.FlexToDate,
        p.Landmark             AS LocationName,
        p.City,
        p.Category             AS CategoryName,
        projSv.ValueCode       AS ProjectStatusCode,
        projSv.ValueName       AS ProjectStatus,
        IF(jtv.ValueCode = 'APPROVE_REQ', 1, 0) AS RequiresApproval,
        -- RECURRING: sessions this volunteer attended
        (SELECT COUNT(*)
         FROM   ProjectAttendance ata
         JOIN   ProjectSessions   pss ON ata.SessionId = pss.SessionId
         WHERE  pss.ProjectId = p.ProjectId AND ata.UserId = p_UserId
           AND  ata.AttendStatusLkpId = v_AttendedLkpId
        ) AS MyAttendedSessions,
        -- RECURRING: sessions eligible (from approval date onward)
        (SELECT COUNT(*)
         FROM   ProjectSessions ps2
         WHERE  ps2.ProjectId  = p.ProjectId
           AND  ps2.SessionDate >= DATE(pa.StatusUpdatedAt)
           AND  ps2.IsDeleted   = 0
        ) AS MyEligibleSessions,
        -- FLEXIBLE: hours logged
        COALESCE((
            SELECT SUM(ata2.HoursLogged)
            FROM   ProjectAttendance ata2
            JOIN   ProjectSessions   pss2 ON ata2.SessionId = pss2.SessionId
            WHERE  pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId
              AND  ata2.AttendStatusLkpId = v_AttendedLkpId
        ), 0) AS MyHoursLogged,
        -- FLEXIBLE: required hours (available window × session hours per day × MinAttendPct %)
        ROUND(
            DATEDIFF(p.FlexToDate, p.FlexFromDate) *
            (TIMESTAMPDIFF(MINUTE, p.SessionStartTime, p.SessionEndTime) / 60.0) *
            COALESCE(p.MinAttendPct, 70) / 100.0
        , 2) AS MyRequiredHours,
        p.MinAttendPct,
        p.MaxDailyHours,
        -- FLEXIBLE: active (open) check-in record
        (SELECT ata3.AttendanceId
         FROM   ProjectAttendance ata3
         JOIN   ProjectSessions   pss3 ON ata3.SessionId = pss3.SessionId
         WHERE  pss3.ProjectId = p.ProjectId AND ata3.UserId = p_UserId
           AND  ata3.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata3.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInId,
        (SELECT ata3.CheckInTime
         FROM   ProjectAttendance ata3
         JOIN   ProjectSessions   pss3 ON ata3.SessionId = pss3.SessionId
         WHERE  pss3.ProjectId = p.ProjectId AND ata3.UserId = p_UserId
           AND  ata3.AttendStatusLkpId = v_CheckedInLkpId
         ORDER BY ata3.CreatedAt DESC LIMIT 1
        ) AS ActiveCheckInTime,
        -- Certificate (if issued)
        (SELECT vc.CertCode
         FROM   VolunteerCertificates vc
         WHERE  vc.ProjectId = p.ProjectId AND vc.UserId = p_UserId AND vc.IsDeleted = 0
         LIMIT  1
        ) AS MyCertCode,
        IF(EXISTS(
            SELECT 1 FROM VolunteerCertificates vc
            WHERE  vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0
        ), 1, 0) AS HasCertificate,
        -- Any attendance record exists (for QR/checkin indicator)
        IF(EXISTS(
            SELECT 1 FROM ProjectAttendance ata4
            JOIN   ProjectSessions pss4 ON ata4.SessionId = pss4.SessionId
            WHERE  pss4.ProjectId = p.ProjectId AND ata4.UserId = p_UserId
        ), 1, 0) AS IsCheckedIn,
        -- Most recent attendance status for this user on this project (ATTENDED | NO_SHOW | null)
        (SELECT lv_att.ValueCode
         FROM   ProjectAttendance ata5
         JOIN   ProjectSessions   pss5 ON ata5.SessionId = pss5.SessionId
         JOIN   LookupValues      lv_att ON ata5.AttendStatusLkpId = lv_att.LookupValueId
         WHERE  pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId
         ORDER BY pss5.SessionDate DESC, ata5.CreatedAt DESC
         LIMIT  1
        )                                               AS AttendanceStatusCode,
        -- Whether the most recent no-show was excused
        (SELECT ata5.IsNoShowExcused
         FROM   ProjectAttendance ata5
         JOIN   ProjectSessions   pss5 ON ata5.SessionId = pss5.SessionId
         WHERE  pss5.ProjectId = p.ProjectId AND ata5.UserId = p_UserId
         ORDER BY pss5.SessionDate DESC, ata5.CreatedAt DESC
         LIMIT  1
        )                                               AS AttendanceIsExcused,
        -- Distinguish admin-remove from self-withdraw
        IF(pa.StatusUpdatedBy IS NOT NULL AND pa.StatusUpdatedBy != pa.UserId, 1, 0) AS WasRemovedByAdmin
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId        = p.ProjectId
    JOIN   Organisations o     ON p.OrgId             = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId      = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId       = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues jtv    ON p.JoinTypeLkpId     = jtv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1-rf-p2', 'v5.1 patch2: Added NOTIFICATION_TYPE lookups (PROJECT_CLOSING/MILESTONE_25/50/75); Updated UserBadge_Award (p_SessionId), Project_GetSkillRatings (p_SessionId + session ratings), Project_ManualAttendance (CLOSING status); New Project_ReopenFromCancelled SP; Updated Application_GetByUser (progress fields: MyAttendedSessions, MyEligibleSessions, MyHoursLogged, MyRequiredHours, ActiveCheckInId, ActiveCheckInTime, MyCertCode).', 'System');

-- ============================================================
-- END OF v5.1-rf PATCH 2
-- ============================================================

-- ============================================================
-- ORG PROJECT PERMISSIONS (subscription/plan gate)
-- CanCreateRecurring + CanCreateFlexible per organisation.
-- Super Admin grants/revokes via SuperAdmin_UpdateOrgProjectPermissions.
-- Project_Create + Project_Update enforce the flags SP-side.
-- ============================================================

DELIMITER //
DROP PROCEDURE IF EXISTS SuperAdmin_UpdateOrgProjectPermissions //
CREATE PROCEDURE SuperAdmin_UpdateOrgProjectPermissions(
    IN p_OrgId              INT UNSIGNED,
    IN p_CanCreateRecurring TINYINT(1),
    IN p_CanCreateFlexible  TINYINT(1),
    IN p_OrgMaxVolunteers   INT UNSIGNED,
    IN p_UpdatedBy          INT UNSIGNED
)
BEGIN
    DECLARE v_Error VARCHAR(500) DEFAULT NULL;
    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SET v_Error = 'Organisation not found.';
    END IF;
    IF v_Error IS NULL AND p_OrgMaxVolunteers IS NOT NULL AND p_OrgMaxVolunteers = 0 THEN
        SET v_Error = 'Max volunteers per project must be at least 1.';
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE
        UPDATE Organisations
        SET CanCreateRecurring = COALESCE(p_CanCreateRecurring, CanCreateRecurring),
            CanCreateFlexible  = COALESCE(p_CanCreateFlexible,  CanCreateFlexible),
            OrgMaxVolunteers   = COALESCE(p_OrgMaxVolunteers,   OrgMaxVolunteers),
            UpdatedAt          = NOW(),
            UpdatedBy          = p_UpdatedBy
        WHERE OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Organisation limits updated successfully.' AS Message;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1-org-perms', 'Org project permissions: CanCreateRecurring + CanCreateFlexible columns on Organisations; permission checks in Project_Create + Project_Update SPs; Org_GetProfile returns flags; SuperAdmin_UpdateOrgProjectPermissions SP added.', 'System');

-- ============================================================
-- PUBLIC GLOBAL STATS (Website "Global exploration" section)
-- No-auth, read-only, zero input parameters (nothing to inject/tamper).
-- Raw counts only — never returns row-level org/user data, so there is
-- no PII or enumerable-ID surface here at all.
-- Real counts are blended with a display floor (Settings, PLATFORM group)
-- so the section always looks credible even on a freshly-seeded DB, and
-- automatically starts showing real numbers once actual data overtakes
-- the floor — no code change needed when that day comes (Core Mandate:
-- Change-Adoptable). "Raised" is intentionally NOT DB-driven yet (per
-- product decision 2026-08-17) — it is a static Settings value until
-- donation totals are wired up for public display.
-- ============================================================

DELIMITER //
DROP PROCEDURE IF EXISTS Public_GetGlobalStats //
CREATE PROCEDURE Public_GetGlobalStats()
BEGIN
    SELECT
        (SELECT COUNT(DISTINCT o.Country) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS TotalCountries,
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS TotalOrgs,
        (SELECT COUNT(DISTINCT u.UserId) FROM Users u
            JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND sv.ValueCode = 'APPROVED') AS TotalVolunteers;
END //

DELIMITER ;

-- Display floors — GREATEST(actual DB count, floor) is applied in PublicStatsDal,
-- not in the SP itself, so Super Admin can retune these via the Settings table
-- with zero redeploy (Core Mandate: Change-Adoptable). IsPublic = 0 — these are
-- blended server-side; the raw floor values are never exposed directly, only the
-- final blended numbers via /api/v1/public/global-stats.
INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('PLATFORM', 'GLOBAL_STATS_MIN_COUNTRIES',  '1',        'NUMBER', 'Website Global exploration section — floor shown for Countries until real count exceeds it.',    0),
('PLATFORM', 'GLOBAL_STATS_MIN_ORGS',       '50',       'NUMBER', 'Website Global exploration section — floor shown for Organisations until real count exceeds it.', 0),
('PLATFORM', 'GLOBAL_STATS_MIN_VOLUNTEERS', '4000',     'NUMBER', 'Website Global exploration section — floor shown for Volunteers until real count exceeds it.',    0),
('PLATFORM', 'GLOBAL_STATS_RAISED_DISPLAY', '1000000',  'NUMBER', 'Website Global exploration section — static "Raised" display value. Not DB-driven (2026-08-17 product decision).', 0),
('PLATFORM', 'GLOBAL_STATS_CACHE_MINUTES',  '10',       'NUMBER', 'How long /api/v1/public/global-stats caches its DB query result in memory before re-querying.', 0);

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.2-public-global-stats', 'Public_GetGlobalStats SP + GLOBAL_STATS_* Settings for the website Global exploration section.', 'System');

-- ============================================================
-- SUPER ADMIN — PROACTIVE MEMBER + ORGANISATION ONBOARDING
-- Super Admin creates a User + UserProfile + (new or existing)
-- Organisation + OrgMembers association in ONE atomic operation,
-- before the person has ever logged into the app. First login via
-- the existing OTP flow (Auth_VerifyOTP) matches on Mobile/Email
-- against the row created here — no extra "claim" step needed,
-- the pre-created OrgMembers row is already there waiting.
--
-- Explicit START TRANSACTION / ROLLBACK handler — the FIRST such
-- multi-table atomic SP in this codebase. Necessary here because a
-- partial failure (e.g. Org insert succeeds, OrgMembers insert
-- fails) must never leave an orphaned User or Organisation row —
-- explicit product requirement (BRD Section 13).
-- ============================================================

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

        -- 1. Users — IsVerified = 0: this person has not completed OTP yet.
        --    Auth_VerifyOTP flips it to 1 on their actual first login, same as
        --    every self-registered user.
        INSERT INTO Users (Mobile, Email, CountryCode, IsVerified, IsActive, CreatedBy)
        VALUES (
            NULLIF(p_Mobile, ''), NULLIF(p_Email, ''),
            IFNULL(NULLIF(p_CountryCode, ''), '+91'), 0, 1, p_SuperAdminUserId
        );
        SET v_UserId = LAST_INSERT_ID();

        -- 2. UserProfiles
        INSERT INTO UserProfiles (
            UserId, FirstName, LastName, DateOfBirth, GenderLkpId, ProfilePhoto,
            AddressLine1, AddressLine2, City, State, Pincode, Country, CreatedBy
        ) VALUES (
            v_UserId, IFNULL(p_FirstName, ''), IFNULL(p_LastName, ''), p_DateOfBirth, p_GenderLkpId, p_ProfilePhoto,
            p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, IFNULL(NULLIF(p_Country, ''), 'India'),
            p_SuperAdminUserId
        );

        -- 3. Organisation — new row, or reuse the selected existing one
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
                -- Super Admin is creating this directly (already vetted externally) —
                -- auto-Approved/Verified, skips the normal self-service review queue.
                v_OrgStatusLkpId, v_VerifiedStatusLkpId, v_UserId
            );
            SET v_OrgId = LAST_INSERT_ID();
        ELSE
            SET v_OrgId = p_ExistingOrgId;
        END IF;

        -- 4. OrgMembers — pre-approved association; this is what's already
        --    waiting for the user the moment they complete OTP on first login.
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

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.3-superadmin-member-onboarding', 'SuperAdmin_CreateMemberWithOrg — proactive Super Admin onboarding: creates User+UserProfile+Organisation(optional)+OrgMembers atomically.', 'System');

-- ============================================================
-- SUPER ADMIN — EDIT ORGANISATION / MEMBER PROFILE VALUES
-- Post-creation correction flow: fix a typo'd org name, wrong
-- contact email, wrong address, etc. after Create Member/Org.
-- Full-profile overwrite (same style as the create SP), not
-- per-field PATCH — matches Core Mandate "Change-Adoptable".
--
-- SuperAdmin_User_UpdateProfile enforces server-side (not just
-- trusting the caller/UI) that Email/Mobile can only change while
-- Users.IsVerified = 0 (member has never actually logged in yet).
-- Once verified, those two columns are silently left untouched
-- even if new values are passed — self-service change-email/
-- change-mobile (User_SendContactOtp/VerifyContactOtp) is the
-- only path once a login identity is live. Confirmed with product
-- 2026-08-23 — see DOCUMENTATION_GUIDELINES.md pending log.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_UpdateProfile //
CREATE PROCEDURE SuperAdmin_Org_UpdateProfile(
    IN p_OrgId           INT UNSIGNED,
    IN p_OrgName         VARCHAR(200),
    IN p_OrgTypeLkpId    INT UNSIGNED,
    IN p_RegNumber       VARCHAR(100),
    IN p_RegistrationDate DATE,          -- v5.1: date org was officially registered with govt (nullable)
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
            RegistrationDate = p_RegistrationDate,
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
VALUES ('v5.5-superadmin-profile-edit', 'SuperAdmin_Org_UpdateProfile + SuperAdmin_User_UpdateProfile — post-creation field correction for Super Admin onboarded orgs/members. Email/Mobile edit locked once Users.IsVerified = 1. Also extends SuperAdmin_Org_GetDetail (+OrgTypeLkpId) and SuperAdmin_User_GetFullProfile (+CountryCode/AddressLine1/AddressLine2/Pincode/GenderLkpId/AccountStatus) so the edit forms and Account status pill can be pre-filled, and fixes three pre-existing column-name bugs in SuperAdmin_User_GetFullProfile (skills: UserSkills.SkillLkpId does not exist; interests: UserInterests.IsDeleted does not exist; badges: UserBadges.BadgeType/BadgeName/AwardedAt/OrgId do not exist) that broke every call to it.', 'System');

-- ============================================================
-- RICH PUBLIC ORGANISATION PROFILE (Super Admin onboarding Phase 3)
-- Replaces the thin Org_GetPublicPreview for the /organisation/{token} public
-- page. Reviews/ratings and projects reuse EXISTING SPs unchanged
-- (OrgReview_GetList, OrgReview_GetAggregate, Project_List with
-- p_UserId=0) — this SP only covers the org info block itself.
--
-- ProfileState gate — mirrors the CERT_REVOKED/NOT_FOUND pattern
-- already used by CertificateController for public tokens:
--   'NOT_FOUND'   — OrgId doesn't exist or is soft-deleted
--   'UNAVAILABLE' — org exists but is not APPROVED (PENDING/REJECTED/
--                   SUSPENDED/UNDER_REVIEW) — link may have been
--                   shared before a status change; only OrgId+OrgName
--                   returned so the page can show a neutral message,
--                   nothing else.
--   'ACTIVE'      — full public profile.
-- Deliberately excludes: internal audit columns (CreatedBy/UpdatedBy/
-- DeletedBy/StatusUpdatedBy — raw IDs, not public info), the
-- CanCreateRecurring/CanCreateFlexible/OrgMaxVolunteers plan-gate
-- columns (internal platform business logic, not org profile info),
-- and all OrgDonationSettings banking/PAN/KYC/Razorpay fields (only
-- IsDonationEnabled/Is80GEligible/Is12AEligible are public-safe).
-- ============================================================

DROP PROCEDURE IF EXISTS Org_GetPublicProfile //
CREATE PROCEDURE Org_GetPublicProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_StatusCode VARCHAR(20) DEFAULT NULL;
    DECLARE v_IsDeleted  TINYINT(1)  DEFAULT 1;

    SELECT sv.ValueCode, o.IsDeleted INTO v_StatusCode, v_IsDeleted
    FROM Organisations o
    LEFT JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId
    LIMIT 1;

    IF v_StatusCode IS NULL OR v_IsDeleted = 1 THEN
        SELECT 'NOT_FOUND' AS ProfileState, NULL AS OrgId, NULL AS OrgName;

    ELSEIF v_StatusCode != 'APPROVED' THEN
        SELECT 'UNAVAILABLE' AS ProfileState, o.OrgId, o.OrgName
        FROM Organisations o WHERE o.OrgId = p_OrgId;

    ELSE
        SELECT
            'ACTIVE' AS ProfileState,
            o.OrgId, o.OrgName, o.ContactPerson, o.RegNumber,
            tv.ValueName AS OrgType,
            COALESCE(cv.ValueName, o.Category) AS Category,
            o.LogoUrl, o.About, o.Mission, o.Vision,
            o.ContactEmail, o.ContactPhone, o.Website,
            o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
            o.Latitude, o.Longitude,
            COALESCE(ods.Is80GEligible, o.Is80GEligible, 0) AS Is80GEligible,
            COALESCE(ods.Is12AEligible, o.Is12AEligible, 0) AS Is12AEligible,
            COALESCE(ods.IsDonationEnabled, 0)              AS IsDonationEnabled,
            o.AvgRating, o.RatingCount, o.FollowerCount,
            COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
            o.CreatedAt AS OnPlatformSince,
            (SELECT COUNT(*) FROM OrgMembers om
                 JOIN LookupValues lv ON om.StatusLkpId = lv.LookupValueId
                 JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                 WHERE om.OrgId = o.OrgId AND om.IsDeleted = 0
                   AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED') AS MemberCount,
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv2 ON p.StatusLkpId = sv2.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv2.ValueCode IN ('UPCOMING', 'ACTIVE')) AS ActiveProjectCount,
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv3 ON p.StatusLkpId = sv3.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv3.ValueCode = 'COMPLETED') AS CompletedProjectCount,
            (SELECT COUNT(*) FROM Projects p
                 JOIN LookupValues sv4 ON p.StatusLkpId = sv4.LookupValueId
                 WHERE p.OrgId = o.OrgId AND p.IsDeleted = 0
                   AND sv4.ValueCode NOT IN ('CANCELLED')) AS TotalProjectCount,
            COALESCE((SELECT SUM(pa.HoursLogged)
                 FROM ProjectAttendance pa
                 JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                 JOIN Projects          pr ON ps.ProjectId = pr.ProjectId
                 JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                 JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                 WHERE pr.OrgId = o.OrgId
                   AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalVolunteerHours
        FROM Organisations o
        LEFT JOIN OrgDonationSettings ods ON ods.OrgId = o.OrgId
        LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
        LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
        LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category
                                  AND cv.LookupTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' LIMIT 1)
        WHERE o.OrgId = p_OrgId;
    END IF;
END //

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.4-org-public-profile', 'Org_GetPublicProfile — rich public organisation profile (about/mission/stats/verification) for the /organisation/{token} page. Reviews and projects reuse existing OrgReview_GetList/OrgReview_GetAggregate/Project_List unchanged.', 'System');

-- ============================================================
-- ADMIN REMOVE VOLUNTEER
-- Admin can remove an APPROVED volunteer from any project type.
-- Effect: Application → WITHDRAWN, CurrentVolunteers decremented (slot freed).
-- ============================================================

DELIMITER //
DROP PROCEDURE IF EXISTS Project_AdminRemoveVolunteer //
CREATE PROCEDURE Project_AdminRemoveVolunteer(
    IN p_ProjectId   INT UNSIGNED,
    IN p_UserId      INT UNSIGNED,
    IN p_RemovedBy   INT UNSIGNED
)
BEGIN
    DECLARE v_Error           VARCHAR(500) DEFAULT NULL;
    DECLARE v_WithdrawnLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_ApprovedLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectStatus   VARCHAR(20)  DEFAULT NULL;
    DECLARE v_AppId           INT UNSIGNED DEFAULT NULL;

    -- Resolve lookup IDs
    SELECT lv.LookupValueId INTO v_WithdrawnLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'WITHDRAWN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Validate project exists + not in a terminal state
    SELECT sv.ValueCode INTO v_ProjectStatus
    FROM   Projects p
    JOIN   LookupValues sv ON p.StatusLkpId = sv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0 LIMIT 1;

    IF v_ProjectStatus IS NULL THEN
        SET v_Error = 'Project not found.';
    END IF;

    IF v_Error IS NULL AND v_ProjectStatus IN ('COMPLETED', 'CANCELLED', 'EXPIRED') THEN
        SET v_Error = 'Cannot remove a volunteer from a project that is already completed, cancelled, or expired.';
    END IF;

    -- Validate the volunteer has an APPROVED application
    IF v_Error IS NULL THEN
        SELECT ApplicationId INTO v_AppId
        FROM   ProjectApplications
        WHERE  ProjectId    = p_ProjectId
          AND  UserId       = p_UserId
          AND  StatusLkpId  = v_ApprovedLkpId
          AND  IsDeleted    = 0
        LIMIT  1;

        IF v_AppId IS NULL THEN
            SET v_Error = 'No approved application found for this volunteer on this project.';
        END IF;
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message;
    ELSE
        -- Mark application as WITHDRAWN
        UPDATE ProjectApplications
        SET    StatusLkpId    = v_WithdrawnLkpId,
               StatusUpdatedAt = NOW(),
               StatusUpdatedBy = p_RemovedBy,
               UpdatedAt       = NOW(),
               UpdatedBy       = p_RemovedBy
        WHERE  ApplicationId = v_AppId;

        -- Decrement CurrentVolunteers (floor at 0)
        UPDATE Projects
        SET    CurrentVolunteers = GREATEST(0, CurrentVolunteers - 1),
               UpdatedAt         = NOW(),
               UpdatedBy         = p_RemovedBy
        WHERE  ProjectId = p_ProjectId;

        SELECT 1 AS IsSuccess, 'Volunteer removed from project. Slot has been freed.' AS Message;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1-admin-remove-vol', 'Admin remove volunteer: Project_AdminRemoveVolunteer SP — sets application WITHDRAWN, frees slot (CurrentVolunteers--). Works for all schedule types.', 'System');

-- ============================================================
-- Missing SPs detected by DAL audit (added v5.0-fix2)
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Donation_GetCampaignById //
CREATE PROCEDURE Donation_GetCampaignById(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        dc.CampaignId, dc.OrgId, o.OrgName, o.LogoUrl,
        dc.CampaignName, dc.Description,
        dc.TargetAmount, dc.RaisedAmount, dc.DonorCount,
        dc.StartDate, dc.EndDate, dc.BannerUrl,
        tv.ValueCode AS CampaignTypeCode, tv.ValueName AS CampaignType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        vv.ValueCode AS VisibilityCode,
        o.Is80GEligible, o.Is12AEligible,
        dc.CreatedAt
    FROM DonationCampaigns dc
    JOIN  Organisations  o  ON dc.OrgId              = o.OrgId
    LEFT JOIN LookupValues tv ON dc.CampaignTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON dc.StatusLkpId        = sv.LookupValueId
    LEFT JOIN LookupValues vv ON dc.VisibilityLkpId    = vv.LookupValueId
    WHERE dc.CampaignId = p_CampaignId AND dc.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Donation_GetReceipt //
CREATE PROCEDURE Donation_GetReceipt(
    IN p_DonationId INT UNSIGNED,
    IN p_UserId     INT UNSIGNED
)
BEGIN
    SELECT
        dt.TransactionId, dt.DonationId, dt.DonationAmount,
        dt.OrgId, o.OrgName, o.Is80GEligible, o.Is12AEligible,
        dc.CampaignId, dc.CampaignName,
        COALESCE(dt.DonorName,
            CONCAT(up.FirstName, ' ', up.LastName)) AS DonorName,
        COALESCE(dt.DonorEmail, u.Email)     AS DonorEmail,
        COALESCE(dt.DonorMobile, u.Mobile)   AS DonorMobile,
        pmt.ValueName AS PaymentMethod,
        dr.ReceiptNumber, dr.ReceiptUrl, dr.FiscalYear, dr.IssuedAt,
        dt.CreatedAt AS DonatedAt
    FROM DonationTransactions dt
    JOIN  Organisations     o   ON dt.OrgId         = o.OrgId
    LEFT JOIN DonationCampaigns dc  ON dt.CampaignId    = dc.CampaignId
    LEFT JOIN Users             u   ON dt.DonorUserId   = u.UserId
    LEFT JOIN UserProfiles      up  ON dt.DonorUserId   = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues      pmt ON dt.PayMethodLkpId = pmt.LookupValueId
    LEFT JOIN DonationReceipts  dr  ON dt.TransactionId  = dr.TransactionId
    WHERE dt.TransactionId = p_DonationId
      AND dt.IsDeleted = 0
      AND (p_UserId IS NULL OR p_UserId = 0 OR dt.DonorUserId = p_UserId);
END //

DROP PROCEDURE IF EXISTS Donation_SetupRecurring //
CREATE PROCEDURE Donation_SetupRecurring(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_CampaignId     INT UNSIGNED,
    IN p_Amount         DECIMAL(12,2),
    IN p_FrequencyLkpId INT UNSIGNED,
    IN p_StartDate      DATE
)
BEGIN
    DECLARE v_ActiveStatusId INT UNSIGNED;
    DECLARE v_NewId          INT UNSIGNED;

    -- Guard: org must exist
    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message, NULL AS RecurringDonId;
    ELSEIF p_Amount <= 0 THEN
        SELECT 0 AS IsSuccess, 'Amount must be greater than zero.' AS Message, NULL AS RecurringDonId;
    ELSE
        SELECT lv.LookupValueId INTO v_ActiveStatusId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

        INSERT INTO RecurringDonations
            (DonorUserId, OrgId, CampaignId, Amount, FrequencyLkpId, StatusLkpId, StartDate, NextChargeDate)
        VALUES
            (p_UserId, p_OrgId, p_CampaignId, p_Amount, p_FrequencyLkpId, v_ActiveStatusId, p_StartDate, p_StartDate);

        SET v_NewId = LAST_INSERT_ID();
        SELECT 1 AS IsSuccess, 'Recurring donation set up.' AS Message, v_NewId AS RecurringDonId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Donation_CancelRecurring //
CREATE PROCEDURE Donation_CancelRecurring(
    IN p_RecurringDonId INT UNSIGNED,
    IN p_UserId         INT UNSIGNED
)
BEGIN
    DECLARE v_Exists      TINYINT DEFAULT 0;
    DECLARE v_CancelledId INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM RecurringDonations
    WHERE RecurringDonId = p_RecurringDonId AND DonorUserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'Recurring donation not found.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_CancelledId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

        UPDATE RecurringDonations
        SET StatusLkpId = v_CancelledId, CancelledAt = NOW(), UpdatedAt = NOW()
        WHERE RecurringDonId = p_RecurringDonId AND DonorUserId = p_UserId;

        SELECT 1 AS IsSuccess, 'Recurring donation cancelled.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS User_SendContactOtp //
CREATE PROCEDURE User_SendContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(20),
    IN p_Value     VARCHAR(150),
    IN p_OtpCode   VARCHAR(10),
    IN p_IpAddress VARCHAR(45)
)
BEGIN
    DECLARE v_PurposeLkpId  INT UNSIGNED;
    DECLARE v_RecentCount   INT DEFAULT 0;
    DECLARE v_ExpiryMins    INT DEFAULT 10;
    DECLARE v_AlreadyUsed   INT DEFAULT 0;

    -- Map type to OTP purpose (ADD_PHONE / ADD_EMAIL are the seeded values for this flow)
    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE'
      AND lv.ValueCode = IF(UPPER(p_Type) = 'EMAIL', 'ADD_EMAIL', 'ADD_PHONE')
    LIMIT 1;

    IF v_PurposeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid contact type.' AS Message;
    ELSE
        -- Uniqueness check: phone/email must not already belong to another account
        IF UPPER(p_Type) = 'EMAIL' THEN
            SELECT COUNT(*) INTO v_AlreadyUsed
            FROM Users
            WHERE Email = p_Value AND UserId != p_UserId AND IsDeleted = 0;
        ELSE
            SELECT COUNT(*) INTO v_AlreadyUsed
            FROM Users
            WHERE Mobile = p_Value AND UserId != p_UserId AND IsDeleted = 0;
        END IF;

        IF v_AlreadyUsed > 0 THEN
            SELECT 0 AS IsSuccess,
                   CONCAT(IF(UPPER(p_Type) = 'EMAIL', 'This email address', 'This phone number'),
                          ' is already linked to another account.') AS Message;
        ELSE
            -- Rate limit: max 3 per 10 min
            SELECT COUNT(*) INTO v_RecentCount
            FROM OtpTokens
            WHERE Recipient    = p_Value
              AND PurposeLkpId = v_PurposeLkpId
              AND CreatedAt   >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
              AND IsUsed       = 0;

            IF v_RecentCount >= 3 THEN
                SELECT 0 AS IsSuccess, 'Too many OTP requests. Please wait before trying again.' AS Message;
            ELSE
                -- Invalidate previous OTPs for this recipient + purpose
                UPDATE OtpTokens SET IsUsed = 1
                WHERE Recipient = p_Value AND PurposeLkpId = v_PurposeLkpId AND IsUsed = 0;

                INSERT INTO OtpTokens (UserId, Recipient, OtpCode, PurposeLkpId, IpAddress, ExpiresAt)
                VALUES (p_UserId, p_Value, p_OtpCode, v_PurposeLkpId, p_IpAddress,
                        DATE_ADD(NOW(), INTERVAL v_ExpiryMins MINUTE));

                SELECT 1 AS IsSuccess, 'OTP sent.' AS Message;
            END IF;
        END IF;
    END IF;
END //

DROP PROCEDURE IF EXISTS User_VerifyContactOtp //
CREATE PROCEDURE User_VerifyContactOtp(
    IN p_UserId    INT UNSIGNED,
    IN p_Type      VARCHAR(20),
    IN p_Value     VARCHAR(150),
    IN p_OtpCode   VARCHAR(10),
    IN p_IpAddress VARCHAR(45)
)
BEGIN
    DECLARE v_PurposeLkpId INT UNSIGNED;
    DECLARE v_OtpTokenId   INT UNSIGNED;
    DECLARE v_Attempts     TINYINT DEFAULT 0;
    DECLARE v_IsExpired    TINYINT DEFAULT 0;

    -- Map type to OTP purpose (must match what User_SendContactOtp used)
    SELECT lv.LookupValueId INTO v_PurposeLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'OTP_PURPOSE'
      AND lv.ValueCode = IF(UPPER(p_Type) = 'EMAIL', 'ADD_EMAIL', 'ADD_PHONE')
    LIMIT 1;

    IF v_PurposeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid contact type.' AS Message;
    ELSE
        SELECT OtpTokenId, AttemptCount,
               IF(ExpiresAt < NOW(), 1, 0)
        INTO v_OtpTokenId, v_Attempts, v_IsExpired
        FROM OtpTokens
        WHERE Recipient    = p_Value
          AND PurposeLkpId = v_PurposeLkpId
          AND IsUsed       = 0
        ORDER BY CreatedAt DESC LIMIT 1;

        IF v_OtpTokenId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No OTP found. Please request a new one.' AS Message;
        ELSEIF v_IsExpired = 1 THEN
            UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;
            SELECT 0 AS IsSuccess, 'OTP has expired. Please request a new one.' AS Message;
        ELSEIF v_Attempts >= 3 THEN
            SELECT 0 AS IsSuccess, 'Too many incorrect attempts. Please request a new OTP.' AS Message;
        ELSE
            -- Verify code
            IF NOT EXISTS (
                SELECT 1 FROM OtpTokens WHERE OtpTokenId = v_OtpTokenId AND OtpCode = p_OtpCode
            ) THEN
                UPDATE OtpTokens SET AttemptCount = AttemptCount + 1 WHERE OtpTokenId = v_OtpTokenId;
                SELECT 0 AS IsSuccess, 'Invalid OTP.' AS Message;
            ELSE
                -- Mark used and update user contact
                UPDATE OtpTokens SET IsUsed = 1 WHERE OtpTokenId = v_OtpTokenId;

                IF UPPER(p_Type) = 'EMAIL' THEN
                    UPDATE Users SET Email = p_Value, IsVerified = 1, UpdatedAt = NOW()
                    WHERE UserId = p_UserId;
                ELSE
                    UPDATE Users SET Mobile = p_Value, IsVerified = 1, UpdatedAt = NOW()
                    WHERE UserId = p_UserId;
                END IF;

                SELECT 1 AS IsSuccess, CONCAT(IF(UPPER(p_Type) = 'EMAIL', 'Email', 'Mobile'), ' updated successfully.') AS Message;
            END IF;
        END IF;
    END IF;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.0-missing-sps-fix2', '6 SPs detected missing by DAL audit: Donation_GetCampaignById, Donation_GetReceipt, Donation_SetupRecurring, Donation_CancelRecurring, User_SendContactOtp, User_VerifyContactOtp.', 'System');

-- ── v5.1 Hangfire Job SPs ─────────────────────────────────────────────────────
-- NOTE: Project_CreateInitialSessions (renamed from Project_GenerateSessions)
-- handles per-project session seeding at creation. The 5 SPs below are for
-- background Hangfire jobs only.

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GenerateSessions //
CREATE PROCEDURE Project_GenerateSessions(IN p_DaysAhead INT)
BEGIN
    DECLARE v_RecurringTypeId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_UpcomingLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ScheduledLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_Done             TINYINT(1)   DEFAULT 0;
    DECLARE v_ProjectId        INT UNSIGNED;
    DECLARE v_TypeCode         VARCHAR(50);
    DECLARE v_RecurDays        VARCHAR(50);
    DECLARE v_StartDate        DATE;
    DECLARE v_EndDate          DATE;
    DECLARE v_StartTime        TIME;
    DECLARE v_EndTime          TIME;
    DECLARE v_CheckDate        DATE;
    DECLARE v_DayName          VARCHAR(10);
    DECLARE v_MaxDate          DATE;

    SELECT lv.LookupValueId INTO v_RecurringTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'RECURRING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ScheduledLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'SCHEDULED' LIMIT 1;

    SET v_MaxDate = DATE_ADD(CURDATE(), INTERVAL p_DaysAhead DAY);

    BEGIN
        DECLARE cur CURSOR FOR
            SELECT p.ProjectId, sv.ValueCode, p.RecurDays,
                   COALESCE(p.RecurStart, CURDATE()) AS StartDate,
                   COALESCE(p.RecurEnd,   v_MaxDate) AS EndDate,
                   p.SessionStartTime, p.SessionEndTime
            FROM   Projects p
            JOIN   LookupValues sv ON p.ProjectTypeLkpId = sv.LookupValueId
            WHERE  p.IsDeleted = 0
              AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
              AND  p.ProjectTypeLkpId IN (v_RecurringTypeId, v_FlexibleTypeId);

        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN cur;
        project_loop: LOOP
            FETCH cur INTO v_ProjectId, v_TypeCode, v_RecurDays,
                           v_StartDate, v_EndDate, v_StartTime, v_EndTime;
            IF v_Done THEN LEAVE project_loop; END IF;

            SET v_CheckDate = GREATEST(v_StartDate, CURDATE());
            WHILE v_CheckDate <= LEAST(v_MaxDate, v_EndDate) DO
                SET v_DayName = UPPER(DAYNAME(v_CheckDate));
                IF v_TypeCode = 'FLEXIBLE'
                   OR (v_TypeCode = 'RECURRING' AND FIND_IN_SET(v_DayName, UPPER(REPLACE(v_RecurDays, ' ', ''))) > 0)
                THEN
                    IF NOT EXISTS (
                        SELECT 1 FROM ProjectSessions ps
                        WHERE ps.ProjectId = v_ProjectId AND ps.SessionDate = v_CheckDate AND ps.IsDeleted = 0
                    ) THEN
                        INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, StatusLkpId, CreatedBy)
                        VALUES (v_ProjectId, v_CheckDate, v_StartTime, v_EndTime, v_ScheduledLkpId, 0);
                    END IF;
                END IF;
                SET v_CheckDate = DATE_ADD(v_CheckDate, INTERVAL 1 DAY);
            END WHILE;
        END LOOP;
        CLOSE cur;
    END;

    SELECT 1 AS IsSuccess, 'Sessions generated.' AS Message;
END //


DROP PROCEDURE IF EXISTS Project_AutoCompleteSessions //
CREATE PROCEDURE Project_AutoCompleteSessions()
BEGIN
    DECLARE v_ScheduledLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ScheduledLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'SCHEDULED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CompletedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE ProjectSessions ps
    SET    ps.SessionStatusLkpId = v_CompletedLkpId, ps.UpdatedAt = NOW()
    WHERE  ps.IsDeleted          = 0
      AND  ps.SessionStatusLkpId IN (v_ScheduledLkpId, v_ActiveLkpId)
      AND  CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00') < NOW();

    SELECT 1 AS IsSuccess, CONCAT('Auto-completed ', ROW_COUNT(), ' sessions.') AS Message;
END //


DROP PROCEDURE IF EXISTS Project_GetCheckoutReminderTargets //
CREATE PROCEDURE Project_GetCheckoutReminderTargets(IN p_MinutesBefore INT)
BEGIN
    DECLARE v_CheckedInLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT att.UserId, p.ProjectId, p.ProjectName, ud.Token AS FcmToken,
           TIME_FORMAT(ps.EndTime, '%H:%i') AS EndTime
    FROM   ProjectAttendance att
    JOIN   ProjectSessions      ps ON ps.SessionId = att.SessionId AND ps.IsDeleted = 0
    JOIN   Projects             p  ON p.ProjectId  = ps.ProjectId  AND p.IsDeleted  = 0
    JOIN   Users                u  ON u.UserId     = att.UserId
    LEFT JOIN UserDeviceTokens  ud ON ud.UserId     = att.UserId
    WHERE  att.AttendStatusLkpId = v_CheckedInLkpId
      AND  att.CheckOutTime      IS NULL
      AND  p.ProjectTypeLkpId    = v_FlexibleTypeId
      AND  ps.SessionDate        = CURDATE()
      AND  TIMESTAMPDIFF(MINUTE, NOW(),
               CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00'))
           BETWEEN (p_MinutesBefore - 1) AND (p_MinutesBefore + 1);
END //


DROP PROCEDURE IF EXISTS Project_CheckMilestoneNotifications //
CREATE PROCEDURE Project_CheckMilestoneNotifications()
BEGIN
    DECLARE v_RecurringTypeId INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ClosingLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_NotifLkpId      INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_RecurringTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'RECURRING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_NotifLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'NOTIF_TYPE' AND lv.ValueCode = 'MILESTONE_REACHED' LIMIT 1;

    INSERT INTO Notifications (UserId, Title, Body, NotifTypeLkpId, RefId, RefType, CreatedAt)
    SELECT pa.UserId,
           'Milestone Reached! 🎉' AS Title,
           CONCAT('You''ve reached ', m.milestone, '% progress on "', p.ProjectName, '"!') AS Body,
           v_NotifLkpId, p.ProjectId, 'PROJECT', NOW()
    FROM ProjectApplications pa
    JOIN Projects p ON p.ProjectId = pa.ProjectId AND p.IsDeleted = 0
    JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    JOIN (SELECT 25 AS milestone UNION ALL SELECT 50 UNION ALL SELECT 75) m
    WHERE pa.IsDeleted = 0
      AND appSv.ValueCode = 'APPROVED'
      AND p.ProjectTypeLkpId IN (v_RecurringTypeId, v_FlexibleTypeId)
      AND p.StatusLkpId IN (v_ActiveLkpId, v_ClosingLkpId)
      AND (
          (p.ProjectTypeLkpId = v_RecurringTypeId AND p.MinAttendPct IS NOT NULL
           AND (SELECT COUNT(*) FROM ProjectAttendance att2
                JOIN ProjectSessions ps2 ON att2.SessionId = ps2.SessionId
                JOIN LookupValues av ON att2.AttendStatusLkpId = av.LookupValueId
                WHERE att2.UserId = pa.UserId AND ps2.ProjectId = p.ProjectId
                  AND att2.IsDeleted = 0 AND av.ValueCode = 'ATTENDED') * 100.0 /
           NULLIF((SELECT COUNT(*) FROM ProjectSessions ps3
                   WHERE ps3.ProjectId = p.ProjectId AND ps3.IsDeleted = 0), 0) >= m.milestone)
          OR
          (p.ProjectTypeLkpId = v_FlexibleTypeId AND p.MinSessionHours IS NOT NULL
           AND (SELECT COALESCE(SUM(att3.HoursLogged), 0)
                FROM ProjectAttendance att3
                JOIN ProjectSessions ps4 ON att3.SessionId = ps4.SessionId
                WHERE att3.UserId = pa.UserId AND ps4.ProjectId = p.ProjectId
                  AND att3.IsDeleted = 0) * 100.0 /
           NULLIF(p.MinSessionHours, 0) >= m.milestone)
      )
      AND NOT EXISTS (
          SELECT 1 FROM Notifications n2
          WHERE n2.UserId = pa.UserId AND n2.RefId = p.ProjectId
            AND n2.NotifTypeLkpId = v_NotifLkpId
            AND n2.Body LIKE CONCAT('%', m.milestone, '%')
      );

    SELECT 1 AS IsSuccess, CONCAT('Milestone notifications inserted: ', ROW_COUNT()) AS Message;
END //


DROP PROCEDURE IF EXISTS Project_AutoFinalizeStaleClosing //
CREATE PROCEDURE Project_AutoFinalizeStaleClosing(IN p_DaysThreshold INT)
BEGIN
    DECLARE v_ClosingLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CompletedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE Projects p
    SET    p.StatusLkpId   = v_CompletedLkpId, p.UpdatedAt = NOW(), p.UpdatedBy = 0,
           p.ImpactSummary = COALESCE(p.ImpactSummary, 'Auto-finalized by system.')
    WHERE  p.IsDeleted     = 0
      AND  p.StatusLkpId   = v_ClosingLkpId
      AND  p.StatusUpdatedAt IS NOT NULL
      AND  DATEDIFF(NOW(), p.StatusUpdatedAt) >= p_DaysThreshold;

    SELECT 1 AS IsSuccess,
           CONCAT('Auto-finalized ', ROW_COUNT(), ' stale CLOSING projects.') AS Message;
END //

DELIMITER ;

INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1-hangfire-job-sps', '5 Hangfire background job SPs: Project_GenerateSessions (daily rolling), Project_AutoCompleteSessions, Project_GetCheckoutReminderTargets, Project_CheckMilestoneNotifications, Project_AutoFinalizeStaleClosing. Also renamed per-project init SP to Project_CreateInitialSessions.', 'System');

-- ─────────────────────────────────────────────────────────────────────────────
-- Account Deletion: User_RequestAccountDeletion, User_ReviveAccount,
--                   Auth_VerifyOTP (updated), Auth_CreateFreshAccount,
--                   Org_TransferFoundership
-- See patch_account_deletion.sql for full change history.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS User_RequestAccountDeletion //
CREATE PROCEDURE User_RequestAccountDeletion(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_BlockOrgId    INT UNSIGNED DEFAULT 0;
    DECLARE v_BlockOrgName  VARCHAR(200) DEFAULT NULL;
    DECLARE v_BlockLogoUrl  VARCHAR(500) DEFAULT NULL;
    DECLARE v_TotalMembers  INT          DEFAULT 0;
    DECLARE v_AdminCount    INT          DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    SELECT
        o.OrgId,
        o.OrgName,
        COALESCE(o.LogoUrl, '')                                                AS LogoUrl,
        (SELECT COUNT(*)
         FROM   OrgMembers om2
         WHERE  om2.OrgId     = o.OrgId
           AND  om2.IsDeleted = 0)                                             AS TotalMembers,
        (SELECT COUNT(*)
         FROM   OrgMembers om3
         JOIN   LookupValues rv3 ON om3.RoleLkpId    = rv3.LookupValueId
         JOIN   LookupTypes  rt3 ON rv3.LookupTypeId = rt3.LookupTypeId
         WHERE  om3.OrgId     = o.OrgId
           AND  om3.UserId   != p_UserId
           AND  om3.IsDeleted = 0
           AND  rt3.TypeCode  = 'MEMBER_ROLE'
           AND  rv3.ValueCode IN ('ADMIN','FOUNDER'))                          AS AvailableAdminCount
    INTO v_BlockOrgId, v_BlockOrgName, v_BlockLogoUrl, v_TotalMembers, v_AdminCount
    FROM   OrgMembers om
    JOIN   LookupValues rv ON om.RoleLkpId    = rv.LookupValueId
    JOIN   LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
    JOIN   Organisations o  ON om.OrgId       = o.OrgId
    JOIN   LookupValues sv  ON o.StatusLkpId  = sv.LookupValueId
    WHERE  om.UserId    = p_UserId
      AND  om.IsDeleted = 0
      AND  rt.TypeCode  = 'MEMBER_ROLE'
      AND  rv.ValueCode = 'FOUNDER'
      AND  o.IsDeleted  = 0
      AND  sv.ValueCode = 'APPROVED'
      AND  NOT EXISTS (
               SELECT 1
               FROM   OrgMembers om_f
               JOIN   LookupValues rv_f ON om_f.RoleLkpId    = rv_f.LookupValueId
               JOIN   LookupTypes  rt_f ON rv_f.LookupTypeId = rt_f.LookupTypeId
               WHERE  om_f.OrgId    = om.OrgId
                 AND  om_f.UserId  != p_UserId
                 AND  om_f.IsDeleted = 0
                 AND  rt_f.TypeCode  = 'MEMBER_ROLE'
                 AND  rv_f.ValueCode = 'FOUNDER'
           )
      AND  (SELECT COUNT(*) FROM OrgMembers om2
            WHERE om2.OrgId = om.OrgId AND om2.IsDeleted = 0) > 1
    ORDER BY o.OrgId
    LIMIT 1;

    IF v_BlockOrgId > 0 THEN
        SELECT 0               AS IsSuccess,
               CONCAT('You are the only Founder of "', v_BlockOrgName,
                      '". Please transfer ownership before deleting your account.') AS Message,
               'SOLE_FOUNDER' AS ErrorCode,
               v_BlockOrgId   AS OrgId,
               v_BlockOrgName AS OrgName,
               v_BlockLogoUrl AS OrgLogoUrl,
               v_TotalMembers AS TotalMembers,
               v_AdminCount   AS AvailableAdminCount;
    ELSE
        UPDATE Organisations o
        JOIN   OrgMembers   om ON om.OrgId    = o.OrgId
                               AND om.UserId  = p_UserId
                               AND om.IsDeleted = 0
        JOIN   LookupValues rv ON om.RoleLkpId    = rv.LookupValueId
        JOIN   LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
        JOIN   LookupValues sv ON o.StatusLkpId   = sv.LookupValueId
        SET    o.StatusLkpId = (
                   SELECT lv.LookupValueId
                   FROM   LookupValues lv
                   JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                   WHERE  lt.TypeCode  = 'ORG_STATUS'
                     AND  lv.ValueCode = 'ARCHIVED'
                   LIMIT 1
               ),
               o.UpdatedAt = NOW()
        WHERE  o.IsDeleted  = 0
          AND  rt.TypeCode  = 'MEMBER_ROLE'
          AND  rv.ValueCode = 'FOUNDER'
          AND  sv.ValueCode = 'APPROVED'
          AND  (SELECT COUNT(*) FROM OrgMembers om_c
                WHERE om_c.OrgId = om.OrgId AND om_c.IsDeleted = 0) = 1
          AND  NOT EXISTS (
                   SELECT 1
                   FROM   OrgMembers om_f
                   JOIN   LookupValues rv_f ON om_f.RoleLkpId    = rv_f.LookupValueId
                   JOIN   LookupTypes  rt_f ON rv_f.LookupTypeId = rt_f.LookupTypeId
                   WHERE  om_f.OrgId    = om.OrgId
                     AND  om_f.UserId  != p_UserId
                     AND  om_f.IsDeleted = 0
                     AND  rt_f.TypeCode  = 'MEMBER_ROLE'
                     AND  rv_f.ValueCode = 'FOUNDER'
               );

        UPDATE Users
        SET    IsDeleted           = 1,
               DeletedAt           = NOW(),
               DeletedBy           = p_UserId,
               ScheduledDeletionAt = DATE_ADD(NOW(), INTERVAL 30 DAY)
        WHERE  UserId    = p_UserId
          AND  IsDeleted = 0;

        UPDATE OrgMembers
        SET    IsDeleted = 1,
               DeletedAt = NOW(),
               DeletedBy = p_UserId
        WHERE  UserId    = p_UserId
          AND  IsDeleted = 0;

        UPDATE RefreshTokens
        SET    IsRevoked = 1,
               RevokedAt = NOW()
        WHERE  UserId    = p_UserId
          AND  IsRevoked = 0;

        SELECT 1 AS IsSuccess,
               'Your account has been scheduled for deletion. You have 30 days to sign back in and recover it.' AS Message,
               NULL AS ErrorCode;
    END IF;
END //

DROP PROCEDURE IF EXISTS User_ReviveAccount //
CREATE PROCEDURE User_ReviveAccount(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ScheduledDeletionAt DATETIME DEFAULT NULL;

    SELECT ScheduledDeletionAt INTO v_ScheduledDeletionAt
    FROM   Users
    WHERE  UserId = p_UserId AND IsDeleted = 1
    LIMIT  1;

    IF v_ScheduledDeletionAt IS NULL THEN
        SELECT 0 AS IsSuccess, 'Account not found or not scheduled for deletion.' AS Message;
    ELSEIF v_ScheduledDeletionAt <= NOW() THEN
        SELECT 0 AS IsSuccess, 'The 30-day recovery window has passed. This account has been permanently deleted.' AS Message;
    ELSE
        UPDATE Users
        SET    IsDeleted           = 0,
               DeletedAt           = NULL,
               DeletedBy           = NULL,
               ScheduledDeletionAt = NULL,
               IsVerified          = 1,
               UpdatedAt           = NOW()
        WHERE  UserId = p_UserId;

        SELECT 1 AS IsSuccess, 'Welcome back! Your account has been fully restored.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Auth_CreateFreshAccount //
CREATE PROCEDURE Auth_CreateFreshAccount(IN p_OldUserId INT UNSIGNED)
BEGIN
    DECLARE v_Mobile      VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email       VARCHAR(150) DEFAULT NULL;
    DECLARE v_CountryCode VARCHAR(6)   DEFAULT '+91';
    DECLARE v_NewUserId   INT UNSIGNED DEFAULT 0;

    SELECT Mobile, Email, CountryCode
    INTO   v_Mobile, v_Email, v_CountryCode
    FROM   Users
    WHERE  UserId    = p_OldUserId
      AND  IsDeleted = 1
    LIMIT  1;

    IF v_Mobile IS NULL AND v_Email IS NULL THEN
        SELECT 0 AS IsSuccess,
               'Original account not found or is not in a deleted state.' AS Message,
               NULL AS UserId;
    ELSE
        INSERT INTO Users (Mobile, Email, CountryCode, IsVerified, IsActive)
        VALUES (v_Mobile, v_Email, v_CountryCode, 1, 1);
        SET v_NewUserId = LAST_INSERT_ID();
        INSERT INTO UserProfiles (UserId, FirstName, LastName) VALUES (v_NewUserId, '', '');
        SELECT 1 AS IsSuccess, 'Fresh account created. Welcome!' AS Message, v_NewUserId AS UserId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_TransferFoundership //
CREATE PROCEDURE Org_TransferFoundership(
    IN p_OrgId            INT UNSIGNED,
    IN p_CurrentFounderId INT UNSIGNED,
    IN p_NewFounderId     INT UNSIGNED
)
BEGIN
    DECLARE v_IsCurrentFounder INT UNSIGNED DEFAULT 0;
    DECLARE v_NewMemberExists  INT UNSIGNED DEFAULT 0;
    DECLARE v_FounderLkpId     INT UNSIGNED DEFAULT 0;
    DECLARE v_AdminLkpId       INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsCurrentFounder
    FROM   OrgMembers om
    JOIN   LookupValues rv ON om.RoleLkpId    = rv.LookupValueId
    JOIN   LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
    WHERE  om.OrgId    = p_OrgId
      AND  om.UserId   = p_CurrentFounderId
      AND  om.IsDeleted = 0
      AND  rt.TypeCode  = 'MEMBER_ROLE'
      AND  rv.ValueCode = 'FOUNDER';

    IF v_IsCurrentFounder = 0 THEN
        SELECT 0 AS IsSuccess, 'You are not the Founder of this organisation.' AS Message, 'NOT_FOUNDER' AS ErrorCode;
    ELSE
        SELECT COUNT(*) INTO v_NewMemberExists
        FROM   OrgMembers
        WHERE  OrgId    = p_OrgId
          AND  UserId   = p_NewFounderId
          AND  UserId  != p_CurrentFounderId
          AND  IsDeleted = 0;

        IF v_NewMemberExists = 0 THEN
            SELECT 0 AS IsSuccess, 'Selected member is not an active member of this organisation.' AS Message, 'INVALID_MEMBER' AS ErrorCode;
        ELSE
            SELECT LookupValueId INTO v_FounderLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1;

            SELECT LookupValueId INTO v_AdminLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'ADMIN' LIMIT 1;

            UPDATE OrgMembers SET RoleLkpId = v_FounderLkpId, UpdatedAt = NOW()
            WHERE  OrgId = p_OrgId AND UserId = p_NewFounderId AND IsDeleted = 0;

            UPDATE OrgMembers SET RoleLkpId = v_AdminLkpId, UpdatedAt = NOW()
            WHERE  OrgId = p_OrgId AND UserId = p_CurrentFounderId AND IsDeleted = 0;

            SELECT 1 AS IsSuccess, 'Ownership transferred successfully.' AS Message, NULL AS ErrorCode;
        END IF;
    END IF;
END //

DELIMITER ;

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
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (UserId),
    UNIQUE KEY uq_users_mobile (Mobile, IsDeleted),
    UNIQUE KEY uq_users_email  (Email, IsDeleted),
    INDEX idx_users_isactive   (IsActive, IsDeleted)
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
    SkillRatingId  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserSkillId    INT UNSIGNED  NOT NULL,
    RatedByUserId  INT UNSIGNED  NOT NULL,
    SessionId      INT UNSIGNED  NULL,
    Rating         TINYINT       NOT NULL,
    RatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (SkillRatingId),
    UNIQUE KEY uq_rating_skill_rater (UserSkillId, RatedByUserId, SessionId),
    CONSTRAINT fk_skillrating_skill FOREIGN KEY (UserSkillId)   REFERENCES UserSkills(UserSkillId),
    CONSTRAINT fk_skillrating_rater FOREIGN KEY (RatedByUserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE UserBadges (
    UserBadgeId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED  NOT NULL,
    BadgeType       VARCHAR(50)   NOT NULL,
    AwardedByUserId INT UNSIGNED  NOT NULL,
    OrgId           INT UNSIGNED  NULL,
    AwardedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted       TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (UserBadgeId),
    INDEX idx_badge_user (UserId, IsDeleted),
    CONSTRAINT fk_badge_user      FOREIGN KEY (UserId)          REFERENCES Users(UserId),
    CONSTRAINT fk_badge_awardedby FOREIGN KEY (AwardedByUserId) REFERENCES Users(UserId)
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
    RegNumber       VARCHAR(100)    NOT NULL,
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
    HoursLogged       DECIMAL(4,2)  NULL,
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

CREATE TABLE VolunteerCertificates (
    CertificateId  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    ProjectId      INT UNSIGNED  NOT NULL,
    UserId         INT UNSIGNED  NOT NULL,
    CertificateUrl VARCHAR(500)  NOT NULL,
    IssuedAt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IssuedBy       INT UNSIGNED  NULL,
    PRIMARY KEY (CertificateId),
    UNIQUE KEY uq_cert_project_user (ProjectId, UserId),
    INDEX idx_cert_user (UserId),
    CONSTRAINT fk_cert_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_cert_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
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
('ORG_VERIFICATION_STATUS',     'Org Verification Status',     'Super Admin legal document verification state for an organisation', 1, 1);
-- ^ #44 is LOCATION_SHARING, #45 is PROFILE_VERIFICATION_STATUS, #46 is ORG_VERIFICATION_STATUS — added v4.8

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
SELECT LookupTypeId, 'SENIOR', 'Senior Citizens', 10, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY';

-- ORG_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING', 'Pending', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'UNDER_REVIEW', 'Under Review', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'SUSPENDED', 'Suspended', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS';

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
SELECT LookupTypeId, 'DONATION_RCVD', 'Donation Received', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'POST_LIKED', 'Post Liked', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'BADGE_AWARDED', 'Badge Awarded', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'CERT_ISSUED', 'Certificate Issued', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE' UNION ALL
SELECT LookupTypeId, 'MEM_REQ_REVIEWED', 'Membership Reviewed', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'NOTIFICATION_TYPE';

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
    SELECT 'REJECTED',       'Rejected',                4
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

-- FK: Users.ProfileVerificationLkpId → LookupValues (v4.6 NEW)
ALTER TABLE Users ADD CONSTRAINT fk_users_profileverification
    FOREIGN KEY (ProfileVerificationLkpId) REFERENCES LookupValues(LookupValueId);

-- FK: Organisations.VerificationStatusLkpId → LookupValues (v4.8 NEW)
ALTER TABLE Organisations ADD CONSTRAINT fk_orgs_verificationstatus
    FOREIGN KEY (VerificationStatusLkpId) REFERENCES LookupValues(LookupValueId);

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
('PLATFORM',   'APP_NAME',             'NGO Connect',            'STRING',  'Platform display name',                  1),
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
('SMS',        'SMS_TEMPLATE_OTP',     'Your OTP is {otp}',      'STRING',  'OTP SMS template',                       0);

INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue) VALUES
('DON', YEAR(CURDATE()), 0),
('WDR', YEAR(CURDATE()), 0),
('REC', YEAR(CURDATE()), 0);

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
                    THEN 'Registration successful. Welcome to NGO Connect!'
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

CREATE PROCEDURE Settings_GetPublic()
BEGIN
    SELECT SettingKey, SettingValue, DataType FROM Settings WHERE IsPublic = 1 AND IsDeleted = 0 ORDER BY SettingGroup, SettingKey;
END //

CREATE PROCEDURE Settings_GetByGroup(IN p_Group VARCHAR(50))
BEGIN
    SELECT SettingKey, SettingValue, DataType, Description, IsPublic FROM Settings WHERE SettingGroup = p_Group AND IsDeleted = 0;
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

-- v4.0 MODIFIED: +LogoUrl, AddressLine1/2, Pincode, Mission, Vision
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

-- v4.0 MODIFIED: returns AddressLine1/2, Pincode
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
        o.AvgRating, o.RatingCount,
        o.Latitude, o.Longitude,
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
    DECLARE v_Offset     INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Result set 1: page
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
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

CREATE PROCEDURE Org_RemoveMember(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_RemovedBy INT UNSIGNED)
BEGIN
    UPDATE OrgMembers SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_RemovedBy
    WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Member removed.' AS Message;
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
        SELECT COUNT(*) INTO v_Exists FROM OrgMembershipRequests
        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;
        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess, 'Request already submitted.' AS Message, NULL AS RequestId;
        ELSE
            SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO OrgMembershipRequests
                (OrgId, UserId, PrevNgoExperience, VolunteerSkills, AreasOfInterest, WhyJoin, StatusLkpId)
            VALUES
                (p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin, v_StatusLkpId);
            SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message, LAST_INSERT_ID() AS RequestId;

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
CREATE PROCEDURE Org_UpdateMemberPermissions(
    IN p_OrgMemberId         INT UNSIGNED,
    IN p_OrgId               INT UNSIGNED,
    IN p_UpdatedBy           INT UNSIGNED,
    IN p_CanPost             TINYINT(1),
    IN p_CanComment          TINYINT(1),
    IN p_CanCommunityPost    TINYINT(1),
    IN p_MaxPostsPerDay      TINYINT,
    IN p_LocationSharingLkpId INT UNSIGNED
)
BEGIN
    UPDATE OrgMembers SET
        CanPost              = COALESCE(p_CanPost, CanPost),
        CanComment           = COALESCE(p_CanComment, CanComment),
        CanCommunityPost     = COALESCE(p_CanCommunityPost, CanCommunityPost),
        MaxPostsPerDay       = COALESCE(p_MaxPostsPerDay, MaxPostsPerDay),
        LocationSharingLkpId = COALESCE(p_LocationSharingLkpId, LocationSharingLkpId),
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

-- v4.0 MODIFIED: returns all 17 schedule/location/restriction fields
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        p.RecurStart, p.RecurEnd, p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        p.OneTimeDate, p.FlexFromDate, p.FlexToDate,
        p.MinHoursRequired,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedVolunteers,
        (SELECT StatusLkpId FROM ProjectApplications WHERE ProjectId = p.ProjectId AND UserId = p_UserId AND IsDeleted = 0 LIMIT 1) AS MyApplicationStatusId
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
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

-- v4.0 NEW: Mark a project as completed with impact summary
CREATE PROCEDURE Project_Complete(
    IN p_ProjectId       INT UNSIGNED,
    IN p_CompletedBy     INT UNSIGNED,
    IN p_ImpactSummary   TEXT,
    IN p_BeneficiaryCount INT UNSIGNED
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE Projects SET StatusLkpId = v_StatusLkpId, CompletedAt = NOW(), CompletedBy = p_CompletedBy,
        ImpactSummary = p_ImpactSummary, BeneficiaryCount = p_BeneficiaryCount, UpdatedAt = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Project marked as completed.' AS Message;
END //

-- ── APPLICATION SPs ─────────────────────────────────────────────

CREATE PROCEDURE Application_Apply(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Motivation TEXT, IN p_RequestedSessions VARCHAR(200))
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    DECLARE v_StatusLkpId INT UNSIGNED;
    SELECT COUNT(*) INTO v_Exists FROM ProjectApplications WHERE ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0;
    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'Already applied to this project.' AS Message, NULL AS ApplicationId;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;
        INSERT INTO ProjectApplications (ProjectId, UserId, Motivation, RequestedSessions, StatusLkpId, CreatedBy)
        VALUES (p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions, v_StatusLkpId, p_UserId);
        SELECT 1 AS IsSuccess, 'Application submitted.' AS Message, LAST_INSERT_ID() AS ApplicationId;
    END IF;
END //

CREATE PROCEDURE Application_GetByProject(IN p_ProjectId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_PageNumber INT, IN p_PageSize INT)
BEGIN
    DECLARE v_Offset INT; DECLARE v_StatusLkpId INT UNSIGNED DEFAULT NULL;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;
    IF p_StatusCode IS NOT NULL THEN
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    END IF;
    SELECT pa.ApplicationId, pa.UserId, CONCAT(up.FirstName,' ',up.LastName) AS ApplicantName,
           up.ProfilePhoto, up.City, pa.Motivation, pa.RequestedSessions,
           sv.ValueCode AS StatusCode, sv.ValueName AS Status, pa.CreatedAt
    FROM ProjectApplications pa
    JOIN UserProfiles up ON pa.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND (v_StatusLkpId IS NULL OR pa.StatusLkpId = v_StatusLkpId)
    ORDER BY pa.CreatedAt DESC LIMIT p_PageSize OFFSET v_Offset;
    SELECT COUNT(*) AS TotalCount FROM ProjectApplications pa
    WHERE pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND (v_StatusLkpId IS NULL OR pa.StatusLkpId = v_StatusLkpId);
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
        p.LikeCount, p.CommentCount,
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
        p.LikeCount, p.CommentCount, p.IsPinned, p.CreatedAt, p.UpdatedAt,
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
    SELECT 1 AS IsSuccess, 'Post liked.' AS Message;
END //

CREATE PROCEDURE Post_Unlike(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DELETE FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId;
    UPDATE Posts SET LikeCount = (SELECT COUNT(*) FROM PostLikes WHERE PostId = p_PostId) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post unliked.' AS Message;
END //

-- Updated: enforces CanComment from OrgMembers for org-scoped posts (Permission Enforcement patch)
CREATE PROCEDURE Post_AddComment(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Content TEXT, IN p_ParentCommentId INT UNSIGNED)
BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember      TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment    TINYINT(1)  DEFAULT 1;  -- default allow (no OrgId = public post)

    -- Look up the post's OrgId
    SELECT OrgId INTO v_OrgId
    FROM   Posts WHERE PostId = p_PostId AND IsDeleted = 0 LIMIT 1;

    -- Enforce CanComment only for org-scoped posts
    IF v_OrgId > 0 THEN
        SELECT lv.LookupValueId INTO v_ApprovedLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        SELECT 1, om.CanComment INTO v_IsMember, v_CanComment
        FROM   OrgMembers om
        WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
          AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
        LIMIT 1;

        -- Non-members cannot comment on org posts
        IF v_IsMember = 0 THEN SET v_CanComment = 0; END IF;
    END IF;

    IF v_CanComment = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to comment in this organisation.' AS Message,
               NULL AS CommentId;
    ELSE
        INSERT INTO PostComments (PostId, UserId, ParentCommentId, Content)
        VALUES (p_PostId, p_UserId, p_ParentCommentId, p_Content);
        UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId;
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
           si.CancelReason, si.ResolvedAt, si.CreatedAt,
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
    SELECT vc.CertificateId, vc.ProjectId, p.ProjectName AS ProjectTitle,
           vc.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
           vc.CertificateUrl, vc.IssuedAt, vc.TotalHours
    FROM VolunteerCertificates vc
    JOIN Projects p ON vc.ProjectId = p.ProjectId
    JOIN Organisations o ON vc.OrgId = o.OrgId
    WHERE vc.UserId = p_UserId AND vc.IsDeleted = 0
    ORDER BY vc.IssuedAt DESC;
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

-- v4.0 NEW: Award a badge to a volunteer
CREATE PROCEDURE UserBadge_Award(IN p_UserId INT UNSIGNED, IN p_BadgeLkpId INT UNSIGNED, IN p_AwardedBy INT UNSIGNED, IN p_OrgId INT UNSIGNED, IN p_ProjectId INT UNSIGNED)
BEGIN
    INSERT INTO UserBadges (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
    VALUES (p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());
    SELECT 1 AS IsSuccess, 'Badge awarded successfully.' AS Message, LAST_INSERT_ID() AS BadgeId;
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
           n.RefId, n.RefType, n.IsRead, n.ReadAt, n.CreatedAt
    FROM   Notifications n
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
    IN p_RefType   VARCHAR(50)
)
BEGIN
    INSERT INTO Notifications (UserId, Title, Body, NotifType, RefId, RefType, IsSent)
    VALUES (p_UserId, p_Title, p_Body, p_NotifType, p_RefId, p_RefType, 0);

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
        ub.AwardedAt
    FROM UserBadges ub
    JOIN LookupValues lv  ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId = p.ProjectId
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;
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
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT
        o.OrgId, o.OrgName, o.Category, o.LogoUrl, o.City, o.State,
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
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND lv.ValueCode = o.Category
    GROUP BY o.OrgId, vv.ValueCode
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
    IN p_OrgId        INT,
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
    JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
    JOIN Projects p         ON ps.ProjectId = p.ProjectId
    SET pa.AttendanceStatus = 'EXCUSED',
        pa.UpdatedAt        = NOW()
    WHERE pa.AttendanceId = p_AttendanceId
      AND pa.AttendanceStatus = 'NO_SHOW'
      AND p.OrgId = p_OrgId;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or not a no-show in this org.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show excused. Reliability score will adjust.' AS Message,
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
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Title          VARCHAR(300),
    IN p_Content        TEXT,
    IN p_PostTypeLkpId  INT UNSIGNED,
    IN p_AudienceLkpId  INT UNSIGNED
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
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_UserId);

        SELECT 1                    AS IsSuccess,
               'Post created.'      AS Message,
               LAST_INSERT_ID()     AS CommunityPostId;
    END IF;
END //

-- ── REPLACED SP: Community_CreatePoll ───────────────────────────
-- v4.3: Fixed TypeCode COMMUNITY_POST_TYPE → POST_TYPE_COMMUNITY; AUDIENCE_TYPE fix;
--       added p_IsMultiChoice; JSON_TABLE for options; PollIsMultiChoice in INSERT.
-- Updated: enforces CanCommunityPost from OrgMembers (Permission Enforcement patch)
DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT,
    IN p_IsMultiChoice  TINYINT(1)
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;

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
               NULL AS PollId;
    ELSE
        SELECT lv.LookupValueId INTO v_PollTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

        SELECT lv.LookupValueId INTO v_AudienceLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;

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

        SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId;
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
        LikeCount
    FROM CommunityPosts WHERE CommunityPostId = p_CommunityPostId;
END //

-- ── NEW SP: Community_AddComment ─────────────────────────────────
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

    SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommunityCommentId;
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
    IN p_IsDraft           TINYINT(1)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

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
        StatusLkpId, CreatedBy
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
        p_UserId
    );

    SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
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
    IN p_IsDraft           TINYINT(1)
)
BEGIN
    DECLARE v_ProjectTypeLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_LocationTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_JoinTypeLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_StatusLkpId       INT UNSIGNED DEFAULT NULL;

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
        UpdatedBy         = p_UserId,
        UpdatedAt         = NOW()
    WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Project updated successfully.' AS Message;
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
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts
    WHERE  OrgId      = p_OrgId
      AND  IsDeleted  = 0;
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

-- ── 3.01 User_GetBadges ─────────────────────────────────────────────────────
-- FIXED: UserBadges has BadgeType VARCHAR(50), not BadgeLkpId FK
--        UserBadges has no ProjectId column
-- (Source: NGOConnect_Patch_ColumnFix.sql)
DROP PROCEDURE IF EXISTS User_GetBadges //
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        0            AS BadgeLkpId,   -- no FK column; 0 satisfies DAL Col<int>
        ub.BadgeType AS BadgeName,
        ub.BadgeType AS BadgeCode,
        o.OrgName,
        NULL         AS ProjectName,  -- no ProjectId in UserBadges table
        ub.AwardedAt
    FROM  UserBadges ub
    LEFT  JOIN Organisations o ON ub.OrgId = o.OrgId
    WHERE ub.UserId    = p_UserId
      AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;
END //


-- ── 3.02 User_GetImpact ─────────────────────────────────────────────────────
-- Full rebuild: ImpactScore inline, rank name, anchored on Users table.
-- FIXED: uses AttendStatusLkpId (FK) not AttendanceStatus (VARCHAR which doesn't exist)
--        anchored on Users (not UserProfiles) — always returns a row
-- (Source: NGOConnect_Patch_ColumnFix.sql — supersedes NGOConnect_Patch_ImpactSPs.sql)
DROP PROCEDURE IF EXISTS User_GetImpact //
CREATE PROCEDURE User_GetImpact(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_TotalMinutes      DECIMAL(12,2) DEFAULT 0;
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

    SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)), 0)
    INTO   v_TotalMinutes
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttStatusAttended;
    SET v_TotalHours = ROUND(v_TotalMinutes / 60.0, 1);

    SELECT COUNT(DISTINCT ps.ProjectId)
    INTO   v_ProjCompleted
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId  = ps.SessionId
    JOIN   Projects        p  ON ps.ProjectId  = p.ProjectId
    JOIN   LookupValues    lv ON p.StatusLkpId = lv.LookupValueId
    WHERE  pa.UserId = p_UserId
      AND  pa.AttendStatusLkpId = v_AttStatusAttended
      AND  lv.ValueCode IN ('COMPLETED', 'EXPIRED');

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


-- ── 3.03 Application_GetByUser ──────────────────────────────────────────────
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
        projSv.ValueCode AS ProjectStatusCode,
        projSv.ValueName AS ProjectStatus
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId   = p.ProjectId
    JOIN   Organisations o     ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId        = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId         = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId    = ptv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications WHERE UserId = p_UserId AND IsDeleted = 0;
END //


-- ── 3.04 Application_Apply ─────────────────────────────────────────────────
-- Updated: p_Note → p_Motivation; added p_RequestedSessions
-- (Source: NGOConnect_Patch_ImpactSPs.sql)
DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId         INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_Motivation        TEXT,
    IN p_RequestedSessions TEXT
)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    INSERT INTO ProjectApplications (ProjectId, UserId, StatusLkpId, Motivation, RequestedSessions, CreatedBy)
    VALUES (p_ProjectId, p_UserId, v_PendingLkpId, p_Motivation, p_RequestedSessions, p_UserId);

    SELECT 1 AS IsSuccess, 'Application submitted.' AS Message,
           LAST_INSERT_ID() AS ApplicationId,
           (SELECT OrgId FROM Projects WHERE ProjectId = p_ProjectId) AS OrgId;
END //


-- ── 3.05 Project_List ───────────────────────────────────────────────────────
-- Updated: adds p_UserLat + p_UserLon optional; returns DistanceKm (Haversine)
-- (Source: NGOConnect_Patch_Distance.sql)
DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7)
)
BEGIN
    DECLARE v_Offset       INT;
    DECLARE v_StatusLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId    INT UNSIGNED DEFAULT NULL;

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
      AND  (p_Category   IS NULL OR p.Category          = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
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

    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId             = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category          = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId      = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //


-- ── 3.06 Project_GetNearbyFeed ───────────────────────────────────────────────
-- Personalised home-screen feed: distance-banded + relevance-scored.
-- Algorithm (sort key):
--   1. FLOOR(DistanceKm / 10) ASC  — 10 km bands (0-9km, 10-19km, …)
--   2. RelevanceScore DESC          — within band, most relevant first
--   3. DistanceKm ASC               — exact distance tie-break
--   4. CreatedAt DESC               — newest tie-break
-- RelevanceScore breakdown:
--   +5  approved member of the project's NGO
--   +3  actively following the project's NGO
--   +2  per matching skill (UserSkills ↔ ProjectSkills), capped at 3 = max +6
--   +3  any UserInterest name matches the project's Category (partial LIKE)
-- Filters: ACTIVE or UPCOMING status, IsPublic=1, user has NOT already
-- applied with PENDING or APPROVED status, DistanceKm ≤ 1000 km.
-- Projects with no GPS coordinates rank last (pseudo-distance 999999).
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
        END AS DistanceKm,
        -- Personalisation relevance score
        (
            -- +5: user is an approved member of this NGO (strongest signal)
            CASE WHEN EXISTS(
                SELECT 1 FROM OrgMembers om
                JOIN LookupValues lvm ON om.StatusLkpId = lvm.LookupValueId
                WHERE om.OrgId     = p.OrgId
                  AND om.UserId    = p_UserId
                  AND om.IsDeleted = 0
                  AND lvm.ValueCode = 'APPROVED'
            ) THEN 5 ELSE 0 END
            -- +3: user is actively following this NGO
            + CASE WHEN EXISTS(
                SELECT 1 FROM OrgFollowers of2
                WHERE of2.OrgId      = p.OrgId
                  AND of2.UserId     = p_UserId
                  AND of2.IsFollowing = 1
            ) THEN 3 ELSE 0 END
            -- +2 per skill match (case-insensitive), capped at 3 matches
            + LEAST(
                (SELECT COUNT(*)
                 FROM ProjectSkills ps
                 JOIN UserSkills us
                   ON LOWER(TRIM(ps.SkillName)) = LOWER(TRIM(us.SkillName))
                 WHERE ps.ProjectId = p.ProjectId
                   AND us.UserId    = p_UserId
                   AND us.IsDeleted = 0)
              , 3) * 2
            -- +3: any user interest name matches the project category (partial)
            + CASE WHEN EXISTS(
                SELECT 1 FROM UserInterests ui
                JOIN LookupValues lvi ON ui.InterestLkpId = lvi.LookupValueId
                WHERE ui.UserId = p_UserId
                  AND (LOWER(lvi.ValueName) LIKE CONCAT('%', LOWER(p.Category), '%')
                    OR LOWER(p.Category)    LIKE CONCAT('%', LOWER(lvi.ValueName), '%'))
            ) THEN 3 ELSE 0 END
        ) AS RelevanceScore
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
    ORDER BY
        -- Band (10 km slices); when user has no GPS all share band 0 → sort by relevance
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN FLOOR(6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 )) / 10)
            ELSE 0
        END ASC,
        -- Within each band: most relevant first
        RelevanceScore DESC,
        -- Same relevance: nearest first
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
    DECLARE v_ReasonLkpId  INT UNSIGNED;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_AlreadyExists INT DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ReasonLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'REPORT_REASON' AND lv.ValueCode = p_ReasonCode LIMIT 1;

    IF v_ReasonLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown reason code: ', p_ReasonCode) AS Message;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyExists
        FROM   PostReports
        WHERE  PostId = p_PostId AND ReportedByUserId = p_UserId;

        IF v_AlreadyExists > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
            VALUES (p_PostId, p_UserId, v_ReasonLkpId, p_Details, v_StatusLkpId);

            SELECT 1 AS IsSuccess, 'Post reported.' AS Message;
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
        ), 0) > 0 THEN 'REPORTED' ELSE 'PUBLISHED' END AS StatusCode
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om ON p.UserId = om.UserId AND om.OrgId = p_OrgId AND om.IsDeleted = 0
    LEFT JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
    WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC;
END //


-- ── 3.11 Org_PinPost ────────────────────────────────────────────────────────
-- NEW SP — toggle IsPinned on a feed post (admin action)
-- (Source: NGOConnect_Patch_AdminPostsSP.sql)
DROP PROCEDURE IF EXISTS Org_PinPost //
CREATE PROCEDURE Org_PinPost(
    IN p_PostId   INT UNSIGNED,
    IN p_OrgId    INT UNSIGNED,
    IN p_PinnedBy INT UNSIGNED
)
BEGIN
    DECLARE v_Current TINYINT(1);
    SELECT IsPinned INTO v_Current FROM Posts
    WHERE PostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1;

    IF v_Current IS NULL THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        UPDATE Posts
        SET IsPinned  = NOT v_Current,
            PinnedAt  = CASE WHEN NOT v_Current = 1 THEN NOW() ELSE NULL END,
            PinnedBy  = CASE WHEN NOT v_Current = 1 THEN p_PinnedBy ELSE NULL END,
            UpdatedBy = p_PinnedBy
        WHERE PostId = p_PostId AND OrgId = p_OrgId;

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
    DECLARE v_ActiveProjectStatusId  INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveProjectStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

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

        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveProjectStatusId AND IsDeleted = 0
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
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        sv.ValueCode AS OrgStatusCode,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.AvgRating, o.RatingCount, o.Latitude, o.Longitude, o.CreatedAt,
        o.FollowerCount,
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
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId         = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId          = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
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
        CASE WHEN lsv.ValueCode IS NOT NULL AND lsv.ValueCode != 'DISABLED' THEN 1 ELSE 0 END AS LocationSharing,
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


-- ── 3.20 Org_GetVolunteerProfile ────────────────────────────────────────────
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
        mr.CreatedAt AS RequestedAt
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

        SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
        SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

        IF NOW() < v_WindowStart THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('QR not yet available. Session starts at ', TIME_FORMAT(v_StartTime, '%h:%i %p'),
                          '. QR opens ', v_Buffer, ' min before start.') AS Message,
                   NULL AS QrToken;
        ELSEIF NOW() > v_WindowEnd THEN
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
-- Full rebuild: joins ProjectAttendance; attendance status overrides application status
-- (Source: NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql)
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

        IF v_FilterLkpId IS NULL THEN
            SELECT lv.LookupValueId INTO v_FilterLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
        END IF;
    END IF;

    SELECT
        pa.ApplicationId, pa.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS ApplicantName,
        up.ProfilePhoto, up.City,
        up.Occupation                          AS Profession,
        pa.Motivation, pa.RequestedSessions,
        COALESCE(attSv.ValueCode, appSv.ValueCode) AS StatusCode,
        COALESCE(attSv.ValueName, appSv.ValueName) AS Status,
        pa.StatusUpdatedAt, pa.CreatedAt,
        att.CheckInTime  AS CheckedInAt,
        att.HoursLogged,
        att.IsNoShowExcused AS IsExcused,
        att.QrScannedAt, att.AdminNote,
        ps.SessionDate, ps.StartTime AS SessionStartTime, ps.EndTime AS SessionEndTime
    FROM   ProjectApplications pa
    JOIN   UserProfiles up ON pa.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId FROM ProjectAttendance att2
        JOIN ProjectSessions ps2 ON att2.SessionId = ps2.SessionId
        WHERE att2.UserId = pa.UserId AND ps2.ProjectId = pa.ProjectId AND ps2.IsDeleted = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC LIMIT 1
    )
    LEFT JOIN LookupValues attSv ON att.AttendStatusLkpId = attSv.LookupValueId
    LEFT JOIN ProjectSessions ps ON ps.SessionId = att.SessionId
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (v_FilterLkpId IS NULL OR pa.StatusLkpId = v_FilterLkpId OR att.AttendStatusLkpId = v_FilterLkpId)
    ORDER BY pa.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications pa
    LEFT JOIN ProjectAttendance att ON att.AttendanceId = (
        SELECT att2.AttendanceId FROM ProjectAttendance att2
        JOIN ProjectSessions ps2 ON att2.SessionId = ps2.SessionId
        WHERE att2.UserId = pa.UserId AND ps2.ProjectId = pa.ProjectId AND ps2.IsDeleted = 0
        ORDER BY ps2.SessionDate DESC, att2.CreatedAt DESC LIMIT 1
    )
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (v_FilterLkpId IS NULL OR pa.StatusLkpId = v_FilterLkpId OR att.AttendStatusLkpId = v_FilterLkpId);
END //


-- ── 3.21 Project_ManualAttendance ───────────────────────────────────────────
-- NEW SP — admin marks volunteer ATTENDED for latest past session
-- QrScannedAt=NULL distinguishes from QR scan
-- (Source: NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql)
DROP PROCEDURE IF EXISTS Project_ManualAttendance //
CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId        INT UNSIGNED;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_CurrentStatus VARCHAR(50);
    DECLARE v_SessionId     INT UNSIGNED;
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_HoursLogged   DECIMAL(4,2);

    SELECT pa.UserId, pa.ProjectId, sv.ValueCode
    INTO   v_UserId, v_ProjectId, v_CurrentStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0 LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;
    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;
    ELSE
        SELECT ps.SessionId,
               ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
        INTO   v_SessionId, v_HoursLogged
        FROM   ProjectSessions ps
        WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
        ORDER BY ps.SessionDate DESC LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No past session found for this project.' AS Message;
        ELSE
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
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,   p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId);
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
    DECLARE v_CanComment       TINYINT(1)  DEFAULT 0;
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
DROP PROCEDURE IF EXISTS User_GetMyOrgs //
CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- Approved memberships
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
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
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
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
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
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.City, o.State, o.LogoUrl,
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
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
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

CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved',
                    'Congratulations — your organisation is now live on NGO Connect.', p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
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
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
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

CREATE PROCEDURE Org_Resubmit(
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
            StatusLkpId = v_PendingId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

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

CREATE PROCEDURE SuperAdmin_User_GetFullProfile(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        u.UserId, CONCAT(up.FirstName,' ',up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT o.OrgName ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.Jo
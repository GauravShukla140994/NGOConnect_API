-- ============================================================
-- NGO CONNECT — COMPLETE SETUP (SINGLE RUN FILE)
-- Version: 3.0  |  MySQL 8.0+  |  utf8mb4
-- Run this once to fully reset and rebuild the NGOConnect DB.
--
-- WHAT THIS DOES:
--   1. Drops and recreates the NGOConnect database (clean slate)
--   2. Creates all 42+ tables with corrected DDL
--   3. Inserts all seed data (LookupTypes, LookupValues, Settings)
--   4. Inserts dummy test data (users, org, project, posts, etc.)
--   5. Creates all Stored Procedures (Auth, User, All Modules)
--
-- Run in MySQL Workbench:
--   File → Open → Select this file → Execute (Ctrl+Shift+Enter)
-- ============================================================

-- ============================================================
-- STEP 1: DROP AND RECREATE DATABASE
-- ============================================================

DROP DATABASE IF EXISTS NGOConnect;
CREATE DATABASE NGOConnect
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE NGOConnect;

SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
-- STEP 2: ALL TABLES (Corrected DDL)
-- ============================================================

-- ── GROUP 1: AUTH ─────────────────────────────────────────────

CREATE TABLE Users (
    UserId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    Mobile          VARCHAR(20)     NULL,
    Email           VARCHAR(150)    NULL,
    PasswordHash    VARCHAR(255)    NULL,
    CountryCode     VARCHAR(6)      NOT NULL DEFAULT '+91',
    IsVerified      TINYINT(1)      NOT NULL DEFAULT 0,
    IsActive        TINYINT(1)      NOT NULL DEFAULT 1,
    LastLoginAt     DATETIME        NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (UserId),
    UNIQUE KEY uq_users_mobile   (Mobile, IsDeleted),
    UNIQUE KEY uq_users_email    (Email, IsDeleted),
    INDEX idx_users_isactive     (IsActive, IsDeleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    INDEX idx_otp_recipient_purpose (Recipient, PurposeLkpId, IsUsed),   -- FIXED: Purpose → PurposeLkpId
    INDEX idx_otp_expiry            (ExpiresAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    INDEX idx_rt_userid   (UserId),
    INDEX idx_rt_token    (Token(100)),
    INDEX idx_rt_expiry   (ExpiresAt),
    CONSTRAINT fk_rt_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 2: PROFILES ──────────────────────────────────────────

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
    EducationLkpId  INT UNSIGNED    NULL,
    FieldOfStudy    VARCHAR(150)    NULL,
    WorkExpLkpId    INT UNSIGNED    NULL,
    AddressLine1    VARCHAR(200)    NULL,
    AddressLine2    VARCHAR(200)    NULL,
    City            VARCHAR(100)    NULL,
    State           VARCHAR(100)    NULL,
    Pincode         VARCHAR(20)     NULL,
    Country         VARCHAR(100)    NULL DEFAULT 'India',
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
    INDEX idx_profile_city     (City, IsDeleted),
    INDEX idx_profile_impact   (ImpactScore DESC),
    CONSTRAINT fk_profile_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserDocuments (
    UserDocumentId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    DocumentTypeLkpId INT UNSIGNED  NOT NULL,
    FileUrl         VARCHAR(500)    NOT NULL,
    FileName        VARCHAR(255)    NOT NULL,
    FileSizeKb      INT UNSIGNED    NULL,
    IsVerified      TINYINT(1)      NOT NULL DEFAULT 0,
    VerifiedAt      DATETIME        NULL,
    VerifiedBy      INT UNSIGNED    NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (UserDocumentId),
    INDEX idx_udoc_user     (UserId, IsDeleted),
    INDEX idx_udoc_type     (DocumentTypeLkpId),                         -- FIXED: DocumentType → DocumentTypeLkpId
    CONSTRAINT fk_udoc_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserSkills (
    UserSkillId     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    SkillName       VARCHAR(100)    NOT NULL,
    AvgRating       DECIMAL(3,2)    NOT NULL DEFAULT 0.00,
    RatingCount     INT UNSIGNED    NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (UserSkillId),
    UNIQUE KEY uq_skill_user_name (UserId, SkillName, IsDeleted),
    INDEX idx_skill_name          (SkillName),
    CONSTRAINT fk_skill_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserSkillRatings (
    SkillRatingId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserSkillId     INT UNSIGNED    NOT NULL,
    RatedByUserId   INT UNSIGNED    NOT NULL,
    SessionId       INT UNSIGNED    NULL,
    Rating          TINYINT         NOT NULL,
    RatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (SkillRatingId),
    UNIQUE KEY uq_rating_skill_rater (UserSkillId, RatedByUserId, SessionId),
    CONSTRAINT fk_skillrating_skill FOREIGN KEY (UserSkillId)    REFERENCES UserSkills(UserSkillId),
    CONSTRAINT fk_skillrating_rater FOREIGN KEY (RatedByUserId)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserBadges (
    UserBadgeId     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    BadgeType       VARCHAR(50)     NOT NULL,
    AwardedByUserId INT UNSIGNED    NOT NULL,
    OrgId           INT UNSIGNED    NULL,
    AwardedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (UserBadgeId),
    INDEX idx_badge_user (UserId, IsDeleted),
    CONSTRAINT fk_badge_user      FOREIGN KEY (UserId)          REFERENCES Users(UserId),
    CONSTRAINT fk_badge_awardedby FOREIGN KEY (AwardedByUserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserInterests (
    UserInterestId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    InterestName    VARCHAR(100)    NOT NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (UserInterestId),
    INDEX idx_interest_user (UserId),
    CONSTRAINT fk_interest_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE UserSafetyPreferences (
    UserSafetyPrefId     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    UserId               INT UNSIGNED  NOT NULL,
    EmergVisibilityLkpId INT UNSIGNED  NOT NULL,
    AutoShareDurLkpId    INT UNSIGNED  NOT NULL,
    AllowLocDuringSos    TINYINT(1)    NOT NULL DEFAULT 1,
    AllowLocDuringProj   TINYINT(1)    NOT NULL DEFAULT 1,
    CreatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (UserSafetyPrefId),
    UNIQUE KEY uq_safepref_user (UserId),
    CONSTRAINT fk_safepref_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 3: ORGANISATIONS ──────────────────────────────────────

CREATE TABLE Organisations (
    OrgId           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgName         VARCHAR(200)    NOT NULL,
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
    PRIMARY KEY (OrgId),
    UNIQUE KEY uq_org_regnumber (RegNumber, IsDeleted),
    INDEX idx_org_status        (StatusLkpId, IsDeleted),                -- FIXED: Status → StatusLkpId
    INDEX idx_org_city          (City, IsDeleted),
    INDEX idx_org_category      (Category, IsDeleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE OrgDocuments (
    OrgDocumentId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId           INT UNSIGNED    NOT NULL,
    DocumentTypeLkpId INT UNSIGNED  NOT NULL,
    FileUrl         VARCHAR(500)    NOT NULL,
    FileName        VARCHAR(255)    NOT NULL,
    IsVerified      TINYINT(1)      NOT NULL DEFAULT 0,
    VerifiedAt      DATETIME        NULL,
    VerifiedBy      INT UNSIGNED    NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (OrgDocumentId),
    INDEX idx_orgdoc_org (OrgId, IsDeleted),
    CONSTRAINT fk_orgdoc_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE OrgMembers (
    OrgMemberId     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId           INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    RoleLkpId       INT UNSIGNED    NOT NULL,
    StatusLkpId     INT UNSIGNED    NOT NULL,
    StatusUpdatedAt DATETIME        NULL,
    StatusUpdatedBy INT UNSIGNED    NULL,
    CanPost         TINYINT(1)      NOT NULL DEFAULT 1,
    CanComment      TINYINT(1)      NOT NULL DEFAULT 1,
    CanCommunityPost TINYINT(1)     NOT NULL DEFAULT 1,
    MaxPostsPerDay  TINYINT         NOT NULL DEFAULT 10,
    JoinedAt        DATETIME        NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (OrgMemberId),
    UNIQUE KEY uq_orgmember_org_user (OrgId, UserId, IsDeleted),
    INDEX idx_orgmember_userid       (UserId, IsDeleted),
    INDEX idx_orgmember_status       (StatusLkpId),                      -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_orgmember_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orgmember_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE OrgDonationSettings (
    OrgDonSettingId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId            INT UNSIGNED    NOT NULL,
    IsDonationEnabled TINYINT(1)     NOT NULL DEFAULT 0,
    PlatformFeePct   DECIMAL(5,2)    NOT NULL DEFAULT 1.00,
    BankAccNumber    VARCHAR(50)     NULL,
    BankIfsc         VARCHAR(20)     NULL,
    BankName         VARCHAR(100)    NULL,
    AccountHolderName VARCHAR(150)   NULL,
    Pan              VARCHAR(20)     NULL,
    Is80GEligible    TINYINT(1)      NOT NULL DEFAULT 0,
    Is12AEligible    TINYINT(1)      NOT NULL DEFAULT 0,
    RazorpayAccountId VARCHAR(100)   NULL,
    KycStatusLkpId   INT UNSIGNED    NOT NULL,
    KycVerifiedAt    DATETIME        NULL,
    KycVerifiedBy    INT UNSIGNED    NULL,
    CreatedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy        INT UNSIGNED    NULL,
    PRIMARY KEY (OrgDonSettingId),
    UNIQUE KEY uq_orgdon_org (OrgId),
    CONSTRAINT fk_orgdon_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 4: PROJECTS ──────────────────────────────────────────

CREATE TABLE Projects (
    ProjectId        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId            INT UNSIGNED    NOT NULL,
    ProjectName      VARCHAR(200)    NOT NULL,
    Category         VARCHAR(100)    NOT NULL,
    Description      TEXT            NULL,
    ProjectTypeLkpId INT UNSIGNED    NOT NULL,
    ScheduleTypeLkpId INT UNSIGNED   NULL,
    RecurStart       DATE            NULL,
    RecurEnd         DATE            NULL,
    RecurDays        VARCHAR(20)     NULL,
    SessionStartTime TIME            NULL,
    SessionEndTime   TIME            NULL,
    OneTimeDate      DATE            NULL,
    FlexFromDate     DATE            NULL,
    FlexToDate       DATE            NULL,
    MinHoursRequired INT UNSIGNED    NULL,
    LocationTypeLkpId INT UNSIGNED   NOT NULL,
    AddressLine      VARCHAR(300)    NULL,
    Landmark         VARCHAR(200)    NULL,
    City             VARCHAR(100)    NULL,
    State            VARCHAR(100)    NULL,
    Latitude         DECIMAL(10,7)   NULL,
    Longitude        DECIMAL(10,7)   NULL,
    GoogleMapsUrl    VARCHAR(500)    NULL,
    MaxVolunteers    INT UNSIGNED    NULL,
    JoinTypeLkpId    INT UNSIGNED    NOT NULL,
    IsPublic         TINYINT(1)      NOT NULL DEFAULT 1,
    AgeRestriction   TINYINT(1)      NOT NULL DEFAULT 0,
    IdVerRequired    TINYINT(1)      NOT NULL DEFAULT 0,
    MinReliability   DECIMAL(5,2)    NOT NULL DEFAULT 0,
    StatusLkpId      INT UNSIGNED    NOT NULL,
    CancelledAt      DATETIME        NULL,
    CancelledBy      INT UNSIGNED    NULL,
    CancelReason     TEXT            NULL,
    CompletedAt      DATETIME        NULL,
    CompletedBy      INT UNSIGNED    NULL,
    ImpactSummary    TEXT            NULL,
    BeneficiaryCount INT UNSIGNED    NULL,
    IsDeleted        TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt        DATETIME        NULL,
    DeletedBy        INT UNSIGNED    NULL,
    CreatedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy        INT UNSIGNED    NOT NULL,
    UpdatedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy        INT UNSIGNED    NULL,
    PRIMARY KEY (ProjectId),
    INDEX idx_project_org       (OrgId, IsDeleted),
    INDEX idx_project_status    (StatusLkpId, IsDeleted),                -- FIXED: Status → StatusLkpId
    INDEX idx_project_city      (City, IsDeleted),
    INDEX idx_project_type      (ProjectTypeLkpId),                      -- FIXED: ProjectType → ProjectTypeLkpId
    CONSTRAINT fk_project_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ProjectSkills (
    ProjectSkillId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ProjectId       INT UNSIGNED    NOT NULL,
    SkillName       VARCHAR(100)    NOT NULL,
    PRIMARY KEY (ProjectSkillId),
    INDEX idx_projskill_project (ProjectId),
    CONSTRAINT fk_projskill_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ProjectSessions (
    SessionId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ProjectId          INT UNSIGNED    NOT NULL,
    SessionDate        DATE            NOT NULL,
    StartTime          TIME            NOT NULL,
    EndTime            TIME            NOT NULL,
    MaxVolunteers      INT UNSIGNED    NULL,
    QrCode             VARCHAR(100)    NULL,
    QrExpiresAt        DATETIME        NULL,
    SessionStatusLkpId INT UNSIGNED    NOT NULL,
    IsDeleted          TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy          INT UNSIGNED    NULL,
    UpdatedAt          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy          INT UNSIGNED    NULL,
    PRIMARY KEY (SessionId),
    UNIQUE KEY uq_session_qr      (QrCode),
    INDEX idx_session_project     (ProjectId, IsDeleted),
    INDEX idx_session_date        (SessionDate),
    CONSTRAINT fk_session_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ProjectApplications (
    ApplicationId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ProjectId       INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    Motivation      TEXT            NULL,
    RequestedSessions VARCHAR(200)  NULL,
    StatusLkpId     INT UNSIGNED    NOT NULL,
    StatusUpdatedAt DATETIME        NULL,
    StatusUpdatedBy INT UNSIGNED    NULL,
    RejectionReason TEXT            NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (ApplicationId),
    UNIQUE KEY uq_application_proj_user (ProjectId, UserId, IsDeleted),
    INDEX idx_app_user     (UserId, IsDeleted),
    INDEX idx_app_status   (StatusLkpId),                               -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_app_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_app_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ProjectAttendance (
    AttendanceId      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    SessionId         INT UNSIGNED    NOT NULL,
    UserId            INT UNSIGNED    NOT NULL,
    CheckInTime       DATETIME        NOT NULL,
    CheckOutTime      DATETIME        NULL,
    HoursLogged       DECIMAL(4,2)    NULL,
    QrScannedAt       DATETIME        NULL,
    AttendStatusLkpId INT UNSIGNED    NOT NULL,
    NoShowReason      TEXT            NULL,
    IsNoShowExcused   TINYINT(1)      NOT NULL DEFAULT 0,
    AdminNote         TEXT            NULL,
    CreatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED    NULL,
    UpdatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED    NULL,
    PRIMARY KEY (AttendanceId),
    UNIQUE KEY uq_attendance_session_user (SessionId, UserId),
    INDEX idx_attend_user     (UserId),
    CONSTRAINT fk_attend_session FOREIGN KEY (SessionId) REFERENCES ProjectSessions(SessionId),
    CONSTRAINT fk_attend_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE VolunteerCertificates (
    CertificateId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ProjectId       INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    CertificateUrl  VARCHAR(500)    NOT NULL,
    IssuedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IssuedBy        INT UNSIGNED    NULL,
    PRIMARY KEY (CertificateId),
    UNIQUE KEY uq_cert_project_user (ProjectId, UserId),
    INDEX idx_cert_user (UserId),
    CONSTRAINT fk_cert_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_cert_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 5: CONTENT & COMMUNITY ───────────────────────────────

CREATE TABLE Posts (
    PostId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId           INT UNSIGNED    NULL,
    UserId          INT UNSIGNED    NOT NULL,
    PostTypeLkpId   INT UNSIGNED    NOT NULL,
    Content         TEXT            NOT NULL,
    VisibilityLkpId INT UNSIGNED    NOT NULL,
    IsPinned        TINYINT(1)      NOT NULL DEFAULT 0,
    PinnedAt        DATETIME        NULL,
    PinnedBy        INT UNSIGNED    NULL,
    LikeCount       INT UNSIGNED    NOT NULL DEFAULT 0,
    CommentCount    INT UNSIGNED    NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy       INT UNSIGNED    NULL,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy       INT UNSIGNED    NULL,
    PRIMARY KEY (PostId),
    INDEX idx_post_org     (OrgId, IsDeleted),
    INDEX idx_post_user    (UserId, IsDeleted),
    INDEX idx_post_created (CreatedAt DESC),
    INDEX idx_post_pinned  (IsPinned, OrgId),
    CONSTRAINT fk_post_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_post_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PostMedia (
    PostMediaId    INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    PostId         INT UNSIGNED    NOT NULL,
    FileUrl        VARCHAR(500)    NOT NULL,
    MediaTypeLkpId INT UNSIGNED    NOT NULL,
    SortOrder      TINYINT         NOT NULL DEFAULT 1,
    CreatedAt      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostMediaId),
    INDEX idx_postmedia_post (PostId),
    CONSTRAINT fk_postmedia_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PostLikes (
    PostLikeId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    PostId      INT UNSIGNED    NOT NULL,
    UserId      INT UNSIGNED    NOT NULL,
    CreatedAt   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostLikeId),
    UNIQUE KEY uq_postlike_post_user (PostId, UserId),
    INDEX idx_postlike_user          (UserId),
    CONSTRAINT fk_postlike_post FOREIGN KEY (PostId) REFERENCES Posts(PostId),
    CONSTRAINT fk_postlike_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PostComments (
    CommentId       INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    PostId          INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    ParentCommentId INT UNSIGNED    NULL,
    Content         TEXT            NOT NULL,
    LikeCount       INT UNSIGNED    NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt       DATETIME        NULL,
    DeletedBy       INT UNSIGNED    NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CommentId),
    INDEX idx_comment_post   (PostId, IsDeleted),
    INDEX idx_comment_user   (UserId),
    INDEX idx_comment_parent (ParentCommentId),
    CONSTRAINT fk_comment_post   FOREIGN KEY (PostId)          REFERENCES Posts(PostId),
    CONSTRAINT fk_comment_user   FOREIGN KEY (UserId)          REFERENCES Users(UserId),
    CONSTRAINT fk_comment_parent FOREIGN KEY (ParentCommentId) REFERENCES PostComments(CommentId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PostReports (
    PostReportId     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    PostId           INT UNSIGNED    NOT NULL,
    ReportedByUserId INT UNSIGNED    NOT NULL,
    ReasonLkpId      INT UNSIGNED    NOT NULL,
    Details          TEXT            NULL,
    StatusLkpId      INT UNSIGNED    NOT NULL,
    ReviewedBy       INT UNSIGNED    NULL,
    ReviewedAt       DATETIME        NULL,
    CreatedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostReportId),
    INDEX idx_report_post   (PostId),
    INDEX idx_report_status (StatusLkpId),                              -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_report_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE CommunityPosts (
    CommunityPostId     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId               INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    PostTypeLkpId       INT UNSIGNED    NOT NULL,
    Title               VARCHAR(300)    NOT NULL,
    Content             TEXT            NULL,
    AudienceLkpId       INT UNSIGNED    NOT NULL,
    IsPinned            TINYINT(1)      NOT NULL DEFAULT 0,
    BestAnswerCommentId INT UNSIGNED    NULL,
    AssignedToUserId    INT UNSIGNED    NULL,
    DueDate             DATETIME        NULL,
    TaskStatusLkpId     INT UNSIGNED    NULL,
    PollEndsAt          DATETIME        NULL,
    PollIsMultiChoice   TINYINT(1)      NULL,
    EventRef            VARCHAR(200)    NULL,
    VolunteersNeeded    INT UNSIGNED    NULL,
    ResourceFileUrl     VARCHAR(500)    NULL,
    AcknowledgeCount    INT UNSIGNED    NOT NULL DEFAULT 0,
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt           DATETIME        NULL,
    DeletedBy           INT UNSIGNED    NULL,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy           INT UNSIGNED    NULL,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy           INT UNSIGNED    NULL,
    PRIMARY KEY (CommunityPostId),
    INDEX idx_commpost_org     (OrgId, IsDeleted),
    INDEX idx_commpost_user    (UserId, IsDeleted),
    INDEX idx_commpost_type    (PostTypeLkpId),                         -- FIXED: PostType → PostTypeLkpId
    INDEX idx_commpost_created (CreatedAt DESC),
    CONSTRAINT fk_commpost_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_commpost_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PollOptions (
    PollOptionId    INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    CommunityPostId INT UNSIGNED    NOT NULL,
    OptionText      VARCHAR(200)    NOT NULL,
    VoteCount       INT UNSIGNED    NOT NULL DEFAULT 0,
    SortOrder       TINYINT         NOT NULL DEFAULT 1,
    PRIMARY KEY (PollOptionId),
    INDEX idx_polloption_post (CommunityPostId),
    CONSTRAINT fk_polloption_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PollVotes (
    PollVoteId      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    PollOptionId    INT UNSIGNED    NOT NULL,
    CommunityPostId INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    VotedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PollVoteId),
    UNIQUE KEY uq_pollvote_user_post (UserId, CommunityPostId),
    CONSTRAINT fk_pollvote_option FOREIGN KEY (PollOptionId) REFERENCES PollOptions(PollOptionId),
    CONSTRAINT fk_pollvote_user   FOREIGN KEY (UserId)       REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Notifications (
    NotificationId  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    NotifType       VARCHAR(50)     NOT NULL,
    Title           VARCHAR(200)    NOT NULL,
    Body            TEXT            NOT NULL,
    RefId           INT UNSIGNED    NULL,
    RefType         VARCHAR(50)     NULL,
    IsRead          TINYINT(1)      NOT NULL DEFAULT 0,
    ReadAt          DATETIME        NULL,
    IsSent          TINYINT(1)      NOT NULL DEFAULT 0,
    SentAt          DATETIME        NULL,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (NotificationId),
    INDEX idx_notif_user    (UserId, IsRead),
    INDEX idx_notif_created (CreatedAt DESC),
    CONSTRAINT fk_notif_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 6: SAFETY / SOS ──────────────────────────────────────

CREATE TABLE SosIncidents (
    SosIncidentId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    OrgId           INT UNSIGNED    NULL,
    AlertTypeLkpId  INT UNSIGNED    NOT NULL,
    Description     TEXT            NULL,
    ApproxLocation  VARCHAR(300)    NULL,
    Latitude        DECIMAL(10,7)   NULL,
    Longitude       DECIMAL(10,7)   NULL,
    StatusLkpId     INT UNSIGNED    NOT NULL,
    ResolvedAt      DATETIME        NULL,
    ResolvedByLkpId INT UNSIGNED    NULL,
    CancelReason    TEXT            NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SosIncidentId),
    INDEX idx_sos_user   (UserId),
    INDEX idx_sos_org    (OrgId),
    INDEX idx_sos_status (StatusLkpId),                                 -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_sos_user FOREIGN KEY (UserId) REFERENCES Users(UserId),
    CONSTRAINT fk_sos_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE SosResponders (
    SosResponderId      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    SosIncidentId       INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    RespondedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ApprovalStatusLkpId INT UNSIGNED    NOT NULL,
    ApprovedAt          DATETIME        NULL,
    ApprovedBy          INT UNSIGNED    NULL,
    CanViewLocation     TINYINT(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (SosResponderId),
    UNIQUE KEY uq_sosresponder_inc_user (SosIncidentId, UserId),
    CONSTRAINT fk_sosresponder_incident FOREIGN KEY (SosIncidentId) REFERENCES SosIncidents(SosIncidentId),
    CONSTRAINT fk_sosresponder_user     FOREIGN KEY (UserId)        REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE SosLocationLogs (
    SosLocationLogId BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    SosIncidentId   INT UNSIGNED    NOT NULL,
    UserId          INT UNSIGNED    NOT NULL,
    Latitude        DECIMAL(10,7)   NOT NULL,
    Longitude       DECIMAL(10,7)   NOT NULL,
    Accuracy        DECIMAL(8,2)    NULL,
    LoggedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (SosLocationLogId),
    INDEX idx_sosloc_incident (SosIncidentId),
    INDEX idx_sosloc_logged   (LoggedAt DESC),
    CONSTRAINT fk_sosloc_incident FOREIGN KEY (SosIncidentId) REFERENCES SosIncidents(SosIncidentId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 7: DONATIONS ─────────────────────────────────────────

CREATE TABLE DonationCampaigns (
    CampaignId        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId             INT UNSIGNED    NOT NULL,
    CreatedByUserId   INT UNSIGNED    NOT NULL,
    CampaignName      VARCHAR(200)    NOT NULL,
    Description       TEXT            NULL,
    CampaignTypeLkpId INT UNSIGNED    NOT NULL,
    TargetAmount      DECIMAL(12,2)   NOT NULL,
    RaisedAmount      DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    DonorCount        INT UNSIGNED    NOT NULL DEFAULT 0,
    StartDate         DATE            NOT NULL,
    EndDate           DATE            NULL,
    BannerUrl         VARCHAR(500)    NULL,
    ProjectId         INT UNSIGNED    NULL,
    VisibilityLkpId   INT UNSIGNED    NOT NULL,
    StatusLkpId       INT UNSIGNED    NOT NULL,
    IsDeleted         TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt         DATETIME        NULL,
    DeletedBy         INT UNSIGNED    NULL,
    CreatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy         INT UNSIGNED    NULL,
    UpdatedAt         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy         INT UNSIGNED    NULL,
    PRIMARY KEY (CampaignId),
    INDEX idx_campaign_org    (OrgId, IsDeleted),
    INDEX idx_campaign_status (StatusLkpId, IsDeleted),                 -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_campaign_org     FOREIGN KEY (OrgId)     REFERENCES Organisations(OrgId),
    CONSTRAINT fk_campaign_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE DonationTransactions (
    TransactionId   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    DonationId      VARCHAR(30)     NOT NULL,
    CampaignId      INT UNSIGNED    NULL,
    OrgId           INT UNSIGNED    NOT NULL,
    DonorUserId     INT UNSIGNED    NULL,
    DonorName       VARCHAR(150)    NULL,
    DonorEmail      VARCHAR(150)    NULL,
    DonorMobile     VARCHAR(20)     NULL,
    DonorPan        VARCHAR(20)     NULL,
    DonationAmount  DECIMAL(12,2)   NOT NULL,
    PlatformFeePct  DECIMAL(5,2)    NOT NULL,
    PlatformFeeAmt  DECIMAL(10,2)   NOT NULL,
    OrgReceivesAmt  DECIMAL(12,2)   NOT NULL,
    DonTypeLkpId    INT UNSIGNED    NOT NULL,
    PayMethodLkpId  INT UNSIGNED    NOT NULL,
    VisibilityLkpId INT UNSIGNED    NOT NULL,
    PayStatusLkpId  INT UNSIGNED    NOT NULL,
    GatewayOrderId  VARCHAR(100)    NULL,
    GatewayPaymentId VARCHAR(100)   NULL,
    GatewayResponse TEXT            NULL,
    FailureReason   TEXT            NULL,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (TransactionId),
    UNIQUE KEY uq_donation_donationid (DonationId),
    INDEX idx_donation_org      (OrgId),
    INDEX idx_donation_user     (DonorUserId),
    INDEX idx_donation_campaign (CampaignId),
    INDEX idx_donation_status   (PayStatusLkpId),                       -- FIXED: PaymentStatus → PayStatusLkpId
    INDEX idx_donation_created  (CreatedAt DESC),
    CONSTRAINT fk_donation_org      FOREIGN KEY (OrgId)       REFERENCES Organisations(OrgId),
    CONSTRAINT fk_donation_campaign FOREIGN KEY (CampaignId)  REFERENCES DonationCampaigns(CampaignId),
    CONSTRAINT fk_donation_user     FOREIGN KEY (DonorUserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE RecurringDonations (
    RecurringDonId  INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    DonorUserId     INT UNSIGNED    NOT NULL,
    OrgId           INT UNSIGNED    NOT NULL,
    CampaignId      INT UNSIGNED    NULL,
    Amount          DECIMAL(12,2)   NOT NULL,
    FrequencyLkpId  INT UNSIGNED    NOT NULL,
    StatusLkpId     INT UNSIGNED    NOT NULL,
    StartDate       DATE            NOT NULL,
    NextChargeDate  DATE            NOT NULL,
    PausedAt        DATETIME        NULL,
    CancelledAt     DATETIME        NULL,
    GatewaySubId    VARCHAR(100)    NULL,
    SuccessCount    INT UNSIGNED    NOT NULL DEFAULT 0,
    FailureCount    INT UNSIGNED    NOT NULL DEFAULT 0,
    IsDeleted       TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (RecurringDonId),
    INDEX idx_recdon_user       (DonorUserId, IsDeleted),
    INDEX idx_recdon_org        (OrgId),
    INDEX idx_recdon_nextcharge (NextChargeDate, StatusLkpId),          -- FIXED: Status → StatusLkpId
    CONSTRAINT fk_recdon_user     FOREIGN KEY (DonorUserId) REFERENCES Users(UserId),
    CONSTRAINT fk_recdon_org      FOREIGN KEY (OrgId)       REFERENCES Organisations(OrgId),
    CONSTRAINT fk_recdon_campaign FOREIGN KEY (CampaignId)  REFERENCES DonationCampaigns(CampaignId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE DonationReceipts (
    ReceiptId       INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    TransactionId   INT UNSIGNED    NOT NULL,
    ReceiptNumber   VARCHAR(50)     NOT NULL,
    ReceiptUrl      VARCHAR(500)    NOT NULL,
    FiscalYear      VARCHAR(10)     NOT NULL,
    IssuedAt        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ReceiptId),
    UNIQUE KEY uq_receipt_transaction (TransactionId),
    INDEX idx_receipt_fiscal (FiscalYear),
    CONSTRAINT fk_receipt_transaction FOREIGN KEY (TransactionId) REFERENCES DonationTransactions(TransactionId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE WithdrawalRequests (
    WithdrawalId        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    WithdrawalRef       VARCHAR(30)     NOT NULL,
    OrgId               INT UNSIGNED    NOT NULL,
    RequestedByUserId   INT UNSIGNED    NOT NULL,
    Amount              DECIMAL(12,2)   NOT NULL,
    Purpose             TEXT            NOT NULL,
    StatusLkpId         INT UNSIGNED    NOT NULL,
    ReviewedBy          INT UNSIGNED    NULL,
    ReviewedAt          DATETIME        NULL,
    RejectionReason     TEXT            NULL,
    TransferredAt       DATETIME        NULL,
    BankRef             VARCHAR(100)    NULL,
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy           INT UNSIGNED    NULL,
    PRIMARY KEY (WithdrawalId),
    UNIQUE KEY uq_withdrawal_ref  (WithdrawalRef),
    INDEX idx_withdrawal_org      (OrgId),
    INDEX idx_withdrawal_status   (StatusLkpId),
    CONSTRAINT fk_withdrawal_org  FOREIGN KEY (OrgId)              REFERENCES Organisations(OrgId),
    CONSTRAINT fk_withdrawal_user FOREIGN KEY (RequestedByUserId)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PaymentGatewayLogs (
    GatewayLogId    INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    TransactionId   INT UNSIGNED    NULL,
    EventType       VARCHAR(100)    NOT NULL,
    GatewayRef      VARCHAR(200)    NULL,
    Payload         MEDIUMTEXT      NOT NULL,
    ProcessedAt     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsProcessed     TINYINT(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (GatewayLogId),
    INDEX idx_gwlog_transaction (TransactionId),
    INDEX idx_gwlog_event       (EventType),
    INDEX idx_gwlog_processed   (IsProcessed)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 8: AUDIT LOG ─────────────────────────────────────────

CREATE TABLE AuditLogs (
    AuditLogId  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId      INT UNSIGNED    NULL,
    Action      VARCHAR(100)    NOT NULL,
    EntityName  VARCHAR(100)    NOT NULL,
    EntityId    INT UNSIGNED    NULL,
    OldValue    MEDIUMTEXT      NULL,
    NewValue    MEDIUMTEXT      NULL,
    IpAddress   VARCHAR(45)     NULL,
    UserAgent   VARCHAR(300)    NULL,
    CreatedAt   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (AuditLogId),
    INDEX idx_audit_entity  (EntityName, EntityId),
    INDEX idx_audit_user    (UserId),
    INDEX idx_audit_created (CreatedAt DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 9: SEQUENCES ─────────────────────────────────────────

CREATE TABLE IdSequences (
    SequenceName VARCHAR(50)  NOT NULL,
    CurrentYear  YEAR         NOT NULL,
    LastValue    INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (SequenceName, CurrentYear)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 10: LOOKUP ───────────────────────────────────────────

CREATE TABLE LookupTypes (
    LookupTypeId INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    TypeCode     VARCHAR(50)     NOT NULL,
    TypeName     VARCHAR(100)    NOT NULL,
    Description  VARCHAR(300)    NULL,
    IsSystemType TINYINT(1)      NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt    DATETIME        NULL,
    DeletedBy    INT UNSIGNED    NULL,
    CreatedAt    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy    INT UNSIGNED    NULL,
    UpdatedAt    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy    INT UNSIGNED    NULL,
    PRIMARY KEY (LookupTypeId),
    UNIQUE KEY uq_lookuptype_code (TypeCode, IsDeleted)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE LookupValues (
    LookupValueId INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    LookupTypeId  INT UNSIGNED    NOT NULL,
    ValueCode     VARCHAR(50)     NOT NULL,
    ValueName     VARCHAR(100)    NOT NULL,
    Description   VARCHAR(300)    NULL,
    OrderNo       SMALLINT        NOT NULL DEFAULT 0,
    IsDefault     TINYINT(1)      NOT NULL DEFAULT 0,
    IsSystemValue TINYINT(1)      NOT NULL DEFAULT 0,
    IsDeleted     TINYINT(1)      NOT NULL DEFAULT 0,
    DeletedAt     DATETIME        NULL,
    DeletedBy     INT UNSIGNED    NULL,
    CreatedAt     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CreatedBy     INT UNSIGNED    NULL,
    UpdatedAt     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UpdatedBy     INT UNSIGNED    NULL,
    PRIMARY KEY (LookupValueId),
    UNIQUE KEY uq_lookupval_type_code (LookupTypeId, ValueCode, IsDeleted),
    INDEX idx_lookupval_type          (LookupTypeId, IsDeleted, OrderNo),
    CONSTRAINT fk_lookupval_type FOREIGN KEY (LookupTypeId) REFERENCES LookupTypes(LookupTypeId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── GROUP 11: SETTINGS ─────────────────────────────────────────

CREATE TABLE Settings (
    SettingId    INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    SettingGroup VARCHAR(50)     NOT NULL,
    SettingKey   VARCHAR(100)    NOT NULL,
    SettingValue TEXT            NOT NULL,
    DataType     VARCHAR(20)     NOT NULL DEFAULT 'STRING',
    Description  VARCHAR(500)    NULL,
    IsPublic     TINYINT(1)      NOT NULL DEFAULT 0,
    IsDeleted    TINYINT(1)      NOT NULL DEFAULT 0,
    UpdatedAt    DATETIME        NULL,
    UpdatedBy    INT UNSIGNED    NULL,
    PRIMARY KEY (SettingId),
    UNIQUE KEY uq_settings_key (SettingKey, IsDeleted),
    INDEX idx_settings_group  (SettingGroup),
    INDEX idx_settings_public (IsPublic)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- STEP 3: SEED DATA — LookupTypes
-- ============================================================

INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('GENDER',              'Gender',                    'User gender options',                         1, 1),
('ORG_TYPE',            'Organisation Type',         'Legal structure of NGO',                      1, 1),
('ORG_CATEGORY',        'Organisation Category',     'Primary cause area of NGO',                   1, 1),
('ORG_STATUS',          'Organisation Status',       'Verification status of NGO on platform',      1, 1),
('MEMBER_ROLE',         'Member Role',               'Role of a user within an organisation',       1, 1),
('MEMBER_STATUS',       'Member Status',             'Status of membership application',            1, 1),
('DOCUMENT_TYPE_USER',  'User Document Type',        'Acceptable identity/address proof for users', 1, 1),
('DOCUMENT_TYPE_ORG',   'Org Document Type',         'Acceptable documents for NGO verification',   1, 1),
('EDUCATION',           'Education Level',           'Highest qualification of a volunteer',        1, 1),
('WORK_EXPERIENCE',     'Work Experience',           'Years of work experience brackets',           1, 1),
('PROJECT_TYPE',        'Project Type',              'Schedule type of a volunteer project',        1, 1),
('PROJECT_STATUS',      'Project Status',            'Current state of a project',                  1, 1),
('PROJECT_JOIN_TYPE',   'Project Join Type',         'How volunteers can join a project',           1, 1),
('APPLICATION_STATUS',  'Application Status',        'Status of a volunteer project application',   1, 1),
('ATTENDANCE_STATUS',   'Attendance Status',         'Volunteer attendance outcome for a session',  1, 1),
('POST_TYPE_FEED',      'Feed Post Type',            'Type of post on the public feed',             1, 1),
('POST_TYPE_COMMUNITY', 'Community Post Type',       'Type of post in an org community',            1, 1),
('POST_VISIBILITY',     'Post Visibility',           'Who can see a feed post',                     1, 1),
('REPORT_REASON',       'Report Reason',             'Reason for reporting a post',                 1, 1),
('SOS_ALERT_TYPE',      'SOS Alert Type',            'Type of emergency alert',                     1, 1),
('SOS_STATUS',          'SOS Status',                'Current state of an SOS incident',            1, 1),
('RESPONDER_STATUS',    'Responder Approval Status', 'Admin approval status of an SOS responder',   1, 1),
('PAYMENT_METHOD',      'Payment Method',            'Payment options for donation',                1, 1),
('DONATION_TYPE',       'Donation Type',             'One-time vs recurring donation',              1, 1),
('DONATION_STATUS',     'Donation Status',           'Payment processing status',                   1, 1),
('CAMPAIGN_TYPE',       'Campaign Type',             'Fundraising campaign category',               1, 1),
('CAMPAIGN_STATUS',     'Campaign Status',           'Current state of a donation campaign',        1, 1),
('RECURRING_FREQUENCY', 'Recurring Frequency',       'How often a recurring donation is charged',   1, 1),
('RECURRING_STATUS',    'Recurring Donation Status', 'Status of a recurring donation',              1, 1),
('WITHDRAWAL_STATUS',   'Withdrawal Status',         'State of an NGO withdrawal request',          1, 1),
('OTP_PURPOSE',         'OTP Purpose',               'Why an OTP was sent',                         1, 1),
('NOTIFICATION_TYPE',   'Notification Type',         'Category of in-app notification',             1, 1),
('LOCATION_TYPE',       'Location Type',             'Whether project is in-person or remote',      1, 1),
('EMERGENCY_VISIBILITY','Emergency Visibility',      'Who can see SOS alerts for a user',           1, 1),
('AUTO_SHARE_DURATION', 'Auto Share Duration',       'How long to share live location during SOS',  1, 1),
('BADGE_TYPE',          'Badge Type',                'Volunteer achievement badge categories',      1, 1),
('KYC_STATUS',          'KYC Status',                'KYC verification state for NGO donations',    1, 1),
('SCHEDULE_TYPE',       'Schedule Type',             'Recurring project schedule pattern',          1, 1),
('SESSION_STATUS',      'Session Status',            'State of a single project session',           1, 1),
('TASK_STATUS',         'Task Status',               'Status of a community task post',             1, 1),
('MEDIA_TYPE',          'Media Type',                'Type of media file attached to a post',       1, 1),  -- ADDED (was missing)
('SOS_RESOLVED_BY',     'SOS Resolved By',           'Who resolved the SOS incident',               1, 1);  -- ADDED (was missing)


-- ============================================================
-- STEP 4: SEED DATA — LookupValues
-- ============================================================

-- GENDER
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'MALE',   'Male',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER' UNION ALL
SELECT LookupTypeId, 'FEMALE', 'Female', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER' UNION ALL
SELECT LookupTypeId, 'OTHER',  'Other',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'GENDER';

-- ORG_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'TRUST',     'Trust',             1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE' UNION ALL
SELECT LookupTypeId, 'SOCIETY',   'Society',           2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE' UNION ALL
SELECT LookupTypeId, 'SECTION_8', 'Section 8 Company', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_TYPE';

-- ORG_CATEGORY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EDUCATION',      'Education',         1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'ENVIRONMENT',    'Environment',       2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'HEALTHCARE',     'Healthcare',        3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'ANIMAL_WELFARE', 'Animal Welfare',    4, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'WOMEN_EMP',      'Women Empowerment', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'COMMUNITY',      'Community Service', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'DISASTER',       'Disaster Relief',   7, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'RURAL_DEV',      'Rural Development', 8, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'CHILD_WELFARE',  'Child Welfare',     9, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY' UNION ALL
SELECT LookupTypeId, 'SENIOR',         'Senior Citizens',  10, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_CATEGORY';

-- ORG_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',      'Pending',      1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'UNDER_REVIEW', 'Under Review', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED',     'Approved',     3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED',     'Rejected',     4, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS' UNION ALL
SELECT LookupTypeId, 'SUSPENDED',    'Suspended',    5, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS';

-- MEMBER_ROLE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'FOUNDER',   'Founder',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'ADMIN',     'Admin',     2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'MODERATOR', 'Moderator', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE' UNION ALL
SELECT LookupTypeId, 'MEMBER',    'Member',    4, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_ROLE';

-- MEMBER_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',   'Pending',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED',  'Approved',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED',  'Rejected',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS' UNION ALL
SELECT LookupTypeId, 'SUSPENDED', 'Suspended', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEMBER_STATUS';

-- DOCUMENT_TYPE_USER
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'AADHAAR',     'Aadhaar Card',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'PAN',         'PAN Card',        2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'PASSPORT',    'Passport',        3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'VOTER_ID',    'Voter ID',        4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'DRIVING_LIC', 'Driving Licence', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'ADDR_PROOF',  'Address Proof',   6, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' UNION ALL
SELECT LookupTypeId, 'OTHER',       'Other',           7, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER';

-- DOCUMENT_TYPE_ORG
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'REG_CERT',  'Registration Certificate', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'ORG_PAN',   'PAN Card',                 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'DOC_80G',   '80G Certificate',          3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'DOC_12A',   '12A Certificate',          4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'BANK_STMT', 'Bank Statement',           5, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG' UNION ALL
SELECT LookupTypeId, 'OTHER',     'Other',                    6, 1, 1 FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_ORG';

-- EDUCATION
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'HIGH_SCHOOL', 'High School',       1, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'DIPLOMA',     'Diploma',           2, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'BACHELOR',    "Bachelor's Degree", 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'MASTER',      "Master's Degree",   4, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION' UNION ALL
SELECT LookupTypeId, 'PHD',         'PhD',               5, 1, 1 FROM LookupTypes WHERE TypeCode = 'EDUCATION';

-- WORK_EXPERIENCE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'EXP_0_2',  '0-2 years',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_3_5',  '3-5 years',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_5_10', '5-10 years', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE' UNION ALL
SELECT LookupTypeId, 'EXP_10P',  '10+ years',  4, 1, 1 FROM LookupTypes WHERE TypeCode = 'WORK_EXPERIENCE';

-- PROJECT_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ONE_TIME',  'One-time',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE' UNION ALL
SELECT LookupTypeId, 'FLEXIBLE',  'Flexible',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_TYPE';

-- PROJECT_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DRAFT',     'Draft',     1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'ACTIVE',    'Active',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'UPCOMING',  'Upcoming',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED', 'Completed', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_STATUS';

-- PROJECT_JOIN_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'APPROVE_REQ', 'Apply and get approved', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE' UNION ALL
SELECT LookupTypeId, 'SLOT_PICK',   'Pick session slots',     2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE' UNION ALL
SELECT LookupTypeId, 'OPEN_SIGNUP', 'Open signup',            3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PROJECT_JOIN_TYPE';

-- APPLICATION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',   'Pending',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED',  'Approved',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED',  'Rejected',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS' UNION ALL
SELECT LookupTypeId, 'WITHDRAWN', 'Withdrawn', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'APPLICATION_STATUS';

-- ATTENDANCE_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ATTENDED', 'Attended', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS' UNION ALL
SELECT LookupTypeId, 'NO_SHOW',  'No Show',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS' UNION ALL
SELECT LookupTypeId, 'EXCUSED',  'Excused',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'ATTENDANCE_STATUS';

-- POST_TYPE_FEED
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'GENERAL',      'General Post',          1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'ANNOUNCEMENT', 'Announcement',          2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'EVENT',        'Event Promotion',       3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'VOL_REQUEST',  'Volunteer Requirement', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'FUNDRAISING',  'Fundraising',           5, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'SUCCESS',      'Success Story',         6, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'ACHIEVEMENT',  'Achievement',           7, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED' UNION ALL
SELECT LookupTypeId, 'PHOTO_VIDEO',  'Photo / Video',         8, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_FEED';

-- POST_TYPE_COMMUNITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DISCUSSION',   'Discussion',        1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'QUESTION',     'Question',          2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'POLL',         'Poll',              3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'ANNOUNCEMENT', 'Announcement',      4, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'EVENT_UPDATE', 'Event Update',      5, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'VOL_REQUEST',  'Volunteer Request', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'TASK',         'Task',              7, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY' UNION ALL
SELECT LookupTypeId, 'RESOURCE',     'Resource / File',   8, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_TYPE_COMMUNITY';

-- POST_VISIBILITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PUBLIC',      'Public',                1, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ORG_MEMBERS', 'Organisation Members',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'FOLLOWERS',   'Followers',             3, 1, 1 FROM LookupTypes WHERE TypeCode = 'POST_VISIBILITY';

-- REPORT_REASON
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SPAM',         'Spam or misleading', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'HATE',         'Hate speech',        2, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'INAPPROPRIATE','Inappropriate',      3, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'SCAM',         'Scam / Fraud',       4, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON' UNION ALL
SELECT LookupTypeId, 'OTHER',        'Other',              5, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_REASON';

-- SOS_ALERT_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SOS',          'SOS Alert',         1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'HELP_REQUEST', 'Help Request',      2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'MISSING_VOL',  'Missing Volunteer', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE' UNION ALL
SELECT LookupTypeId, 'SAFE_ARRIVAL', 'Safe Arrival',      4, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_ALERT_TYPE';

-- SOS_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ACTIVE',    'Active',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS' UNION ALL
SELECT LookupTypeId, 'RESOLVED',  'Resolved',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_STATUS';

-- RESPONDER_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',  'Pending',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED', 'Approved', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS' UNION ALL
SELECT LookupTypeId, 'DECLINED', 'Declined', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RESPONDER_STATUS';

-- PAYMENT_METHOD
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'UPI',         'UPI',                 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'CARD',        'Credit / Debit Card', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'NET_BANKING', 'Net Banking',         3, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD' UNION ALL
SELECT LookupTypeId, 'WALLET',      'Wallet',              4, 1, 1 FROM LookupTypes WHERE TypeCode = 'PAYMENT_METHOD';

-- DONATION_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ONE_TIME',  'One-time',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_TYPE';

-- DONATION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',  'Pending',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'SUCCESS',  'Success',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'FAILED',   'Failed',   3, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS' UNION ALL
SELECT LookupTypeId, 'REFUNDED', 'Refunded', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'DONATION_STATUS';

-- CAMPAIGN_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'GENERAL',   'General Campaign', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'PROJECT',   'Project-Based',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'EMERGENCY', 'Emergency',        3, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE' UNION ALL
SELECT LookupTypeId, 'RECURRING', 'Recurring Fund',   4, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_TYPE';

-- CAMPAIGN_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'DRAFT',     'Draft',     1, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'ACTIVE',    'Active',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'PAUSED',    'Paused',    3, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED', 'Completed', 4, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'CAMPAIGN_STATUS';

-- RECURRING_FREQUENCY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'WEEKLY',    'Weekly',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'MONTHLY',   'Monthly',   2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'QUARTERLY', 'Quarterly', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY' UNION ALL
SELECT LookupTypeId, 'YEARLY',    'Yearly',    4, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_FREQUENCY';

-- RECURRING_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ACTIVE',    'Active',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS' UNION ALL
SELECT LookupTypeId, 'PAUSED',    'Paused',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED', 'Cancelled', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'RECURRING_STATUS';

-- WITHDRAWAL_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',      'Pending',      1, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'UNDER_REVIEW', 'Under Review', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'APPROVED',     'Approved',     3, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'TRANSFERRED',  'Transferred',  4, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED',     'Rejected',     5, 1, 1 FROM LookupTypes WHERE TypeCode = 'WITHDRAWAL_STATUS';

-- OTP_PURPOSE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'LOGIN',           'Login',           1, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'REGISTER',        'Register',        2, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'FORGOT_PASSWORD', 'Forgot Password', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE' UNION ALL
SELECT LookupTypeId, 'CHANGE_EMAIL',    'Change Email',    4, 1, 1 FROM LookupTypes WHERE TypeCode = 'OTP_PURPOSE';

-- LOCATION_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'IN_PERSON', 'In-person', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE' UNION ALL
SELECT LookupTypeId, 'REMOTE',    'Remote',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE' UNION ALL
SELECT LookupTypeId, 'HYBRID',    'Hybrid',    3, 1, 1 FROM LookupTypes WHERE TypeCode = 'LOCATION_TYPE';

-- EMERGENCY_VISIBILITY
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ADMIN_ONLY',  'Only Organisation Admin',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ADMIN_MODS',  'Admin + Moderators',       2, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY' UNION ALL
SELECT LookupTypeId, 'ALL_MEMBERS', 'All Organisation Members',  3, 1, 1 FROM LookupTypes WHERE TypeCode = 'EMERGENCY_VISIBILITY';

-- AUTO_SHARE_DURATION
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'MIN_30',        '30 Minutes',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_1',        '1 Hour',       2, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_2',        '2 Hours',      3, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'HOUR_4',        '4 Hours',      4, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION' UNION ALL
SELECT LookupTypeId, 'UNTIL_STOPPED', 'Until Stopped', 5, 1, 1 FROM LookupTypes WHERE TypeCode = 'AUTO_SHARE_DURATION';

-- BADGE_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'STAR_VOL',    'Volunteer Star', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'TEAM_PLAYER', 'Team Player',    2, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'GO_GETTER',   'Go-getter',      3, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'TOP_PERFORM', 'Top Performer',  4, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'CHAMPION',    'Champion',       5, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'GREEN_WARRIOR','Green Warrior',  6, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE' UNION ALL
SELECT LookupTypeId, 'NGO_HERO',    'NGO Hero',       7, 1, 1 FROM LookupTypes WHERE TypeCode = 'BADGE_TYPE';

-- KYC_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'PENDING',  'Pending',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS' UNION ALL
SELECT LookupTypeId, 'VERIFIED', 'Verified', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS' UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected', 3, 1, 1 FROM LookupTypes WHERE TypeCode = 'KYC_STATUS';

-- SCHEDULE_TYPE
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'WEEKLY_DAYS',  'Weekly - specific days',   1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE' UNION ALL
SELECT LookupTypeId, 'MONTHLY_DATE', 'Monthly - specific dates',  2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE' UNION ALL
SELECT LookupTypeId, 'WEEKDAYS',     'Weekdays only (Mon-Fri)',    3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SCHEDULE_TYPE';

-- SESSION_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'UPCOMING',    'Upcoming',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'IN_PROGRESS', 'In Progress', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'COMPLETED',   'Completed',   3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS' UNION ALL
SELECT LookupTypeId, 'CANCELLED',   'Cancelled',   4, 1, 1 FROM LookupTypes WHERE TypeCode = 'SESSION_STATUS';

-- TASK_STATUS
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'OPEN',        'Open',        1, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS' UNION ALL
SELECT LookupTypeId, 'IN_PROGRESS', 'In Progress', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS' UNION ALL
SELECT LookupTypeId, 'DONE',        'Done',        3, 1, 1 FROM LookupTypes WHERE TypeCode = 'TASK_STATUS';

-- MEDIA_TYPE  (was missing in original LookupTypes INSERT — added above)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'IMAGE', 'Image', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEDIA_TYPE' UNION ALL
SELECT LookupTypeId, 'VIDEO', 'Video', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'MEDIA_TYPE';

-- SOS_RESOLVED_BY  (was missing in original LookupTypes INSERT — added above)
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'SELF',  'Resolved by user',  1, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY' UNION ALL
SELECT LookupTypeId, 'ADMIN', 'Resolved by admin', 2, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY' UNION ALL
SELECT LookupTypeId, 'AUTO',  'Auto-resolved',     3, 1, 1 FROM LookupTypes WHERE TypeCode = 'SOS_RESOLVED_BY';


-- ============================================================
-- STEP 5: SEED DATA — IdSequences
-- ============================================================

INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue) VALUES
('DON', YEAR(CURDATE()), 0),
('WDR', YEAR(CURDATE()), 0),
('REC', YEAR(CURDATE()), 0);


-- ============================================================
-- STEP 6: SEED DATA — Settings
-- ============================================================

INSERT INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('OTP',        'OTP_EXPIRY_MINUTES',   '10',                     'NUMBER',  'OTP expiry in minutes',                 0),
('OTP',        'OTP_MAX_ATTEMPTS',     '3',                      'NUMBER',  'Max OTP verification attempts',         0),
('OTP',        'OTP_RATE_LIMIT',       '3',                      'NUMBER',  'Max OTPs per 10 minutes per recipient', 0),
('AUTH',       'JWT_EXPIRY_MINUTES',   '15',                     'NUMBER',  'JWT access token expiry in minutes',    0),
('AUTH',       'REFRESH_EXPIRY_DAYS',  '30',                     'NUMBER',  'Refresh token expiry in days',          0),
('AUTH',       'MAX_SESSIONS',         '5',                      'NUMBER',  'Max concurrent sessions per user',      0),
('PAGINATION', 'DEFAULT_PAGE_SIZE',    '20',                     'NUMBER',  'Default page size for list APIs',       1),
('PAGINATION', 'MAX_PAGE_SIZE',        '100',                    'NUMBER',  'Maximum allowed page size',             1),
('PLATFORM',   'APP_NAME',             'NGO Connect',            'STRING',  'Platform display name',                 1),
('PLATFORM',   'SUPPORT_EMAIL',        'support@ngoconnect.app', 'STRING',  'Support email address',                 1),
('FEATURE',    'SOS_ENABLED',          'true',                   'BOOLEAN', 'Toggle SOS feature on/off',             0),
('FEATURE',    'DONATIONS_ENABLED',    'true',                   'BOOLEAN', 'Toggle donations feature on/off',       0),
('DONATION',   'MIN_DONATION_AMOUNT',  '10',                     'NUMBER',  'Minimum donation amount in INR',        1),
('DONATION',   'RAZORPAY_KEY_ID',      'rzp_test_xxxx',          'STRING',  'Razorpay Key ID (public)',              1),
('UPLOAD',     'MAX_FILE_SIZE_MB',     '10',                     'NUMBER',  'Maximum file upload size in MB',        1);


-- ============================================================
-- STEP 7: DUMMY / TEST DATA
-- ============================================================

-- Test User 1 (Admin / Founder)
INSERT INTO Users (Mobile, CountryCode, IsVerified, IsActive)
VALUES ('9876543210', '+91', 1, 1);
SET @user1 = LAST_INSERT_ID();

INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, Occupation, City, State, Country)
VALUES (@user1, 'Gaurav', 'Shukla', 'Platform founder and admin user.', 'Software Developer', 'Pune', 'Maharashtra', 'India');

-- Test User 2 (Volunteer)
INSERT INTO Users (Mobile, CountryCode, IsVerified, IsActive)
VALUES ('9876500001', '+91', 1, 1);
SET @user2 = LAST_INSERT_ID();

INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, Occupation, City, State, Country)
VALUES (@user2, 'Priya', 'Sharma', 'Passionate volunteer focused on education.', 'Teacher', 'Mumbai', 'Maharashtra', 'India');

-- Test User 3 (Donor)
INSERT INTO Users (Email, CountryCode, IsVerified, IsActive)
VALUES ('donor@test.com', '+91', 1, 1);
SET @user3 = LAST_INSERT_ID();

INSERT INTO UserProfiles (UserId, FirstName, LastName, Bio, Occupation, City, State, Country)
VALUES (@user3, 'Rahul', 'Mehta', 'Corporate professional who supports NGO causes.', 'Manager', 'Delhi', 'Delhi', 'India');

-- Test Organisation
INSERT INTO Organisations (
    OrgName, RegNumber, OrgTypeLkpId, Category,
    About, ContactEmail, ContactPhone, City, State, Country,
    StatusLkpId, CreatedBy
)
SELECT
    'GreenFuture Foundation',
    'MH/NGO/2024/001',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='ORG_TYPE' AND lv.ValueCode='TRUST'),
    'Environment',
    'Working towards a greener and sustainable future for India.',
    'info@greenfuture.org',
    '9800000001',
    'Pune', 'Maharashtra', 'India',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='ORG_STATUS' AND lv.ValueCode='APPROVED'),
    @user1;
SET @org1 = LAST_INSERT_ID();

-- Add User1 as FOUNDER of Org1
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
SELECT @org1, @user1,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE' AND lv.ValueCode='FOUNDER'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='MEMBER_STATUS' AND lv.ValueCode='APPROVED'),
    NOW(), @user1;

-- Add User2 as MEMBER of Org1
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
SELECT @org1, @user2,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE' AND lv.ValueCode='MEMBER'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='MEMBER_STATUS' AND lv.ValueCode='APPROVED'),
    NOW(), @user1;

-- Org Donation Settings
INSERT INTO OrgDonationSettings (OrgId, IsDonationEnabled, KycStatusLkpId)
SELECT @org1, 1,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='KYC_STATUS' AND lv.ValueCode='VERIFIED');

-- Test Project
INSERT INTO Projects (
    OrgId, ProjectName, Category, Description,
    ProjectTypeLkpId, LocationTypeLkpId, JoinTypeLkpId, StatusLkpId,
    City, State, MaxVolunteers, IsPublic, CreatedBy
)
SELECT
    @org1,
    'Tree Plantation Drive 2026',
    'Environment',
    'Mass tree plantation event across Pune suburbs. Join us to plant 10,000 trees!',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='PROJECT_TYPE' AND lv.ValueCode='ONE_TIME'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='LOCATION_TYPE' AND lv.ValueCode='IN_PERSON'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='PROJECT_JOIN_TYPE' AND lv.ValueCode='APPROVE_REQ'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='PROJECT_STATUS' AND lv.ValueCode='ACTIVE'),
    'Pune', 'Maharashtra', 100, 1, @user1;
SET @proj1 = LAST_INSERT_ID();

-- Test Session for Project
INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, QrCode, SessionStatusLkpId, CreatedBy)
SELECT
    @proj1,
    DATE_ADD(CURDATE(), INTERVAL 7 DAY),
    '08:00:00',
    '13:00:00',
    50,
    UUID(),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='SESSION_STATUS' AND lv.ValueCode='UPCOMING'),
    @user1;
SET @session1 = LAST_INSERT_ID();

-- Project Application (User2 applies)
INSERT INTO ProjectApplications (ProjectId, UserId, Motivation, StatusLkpId, CreatedBy)
SELECT
    @proj1, @user2,
    'I am passionate about the environment and want to contribute to greening our city.',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='PENDING'),
    @user2;

-- Test Post (Feed)
INSERT INTO Posts (OrgId, UserId, PostTypeLkpId, Content, VisibilityLkpId, CreatedBy)
SELECT
    @org1, @user1,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='POST_TYPE_FEED' AND lv.ValueCode='ANNOUNCEMENT'),
    'Exciting news! GreenFuture Foundation is organizing a massive tree plantation drive on July 4th, 2026. Register now to join us in making Pune greener!',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='POST_VISIBILITY' AND lv.ValueCode='PUBLIC'),
    @user1;
SET @post1 = LAST_INSERT_ID();

-- Test Donation Campaign
INSERT INTO DonationCampaigns (
    OrgId, CreatedByUserId, CampaignName, Description,
    CampaignTypeLkpId, TargetAmount, StartDate,
    VisibilityLkpId, StatusLkpId, CreatedBy
)
SELECT
    @org1, @user1,
    'Plant 10,000 Trees Campaign 2026',
    'Help us raise funds to plant 10,000 trees across Maharashtra. Every donation plants a tree!',
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='CAMPAIGN_TYPE' AND lv.ValueCode='PROJECT'),
    500000.00,
    CURDATE(),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='POST_VISIBILITY' AND lv.ValueCode='PUBLIC'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='CAMPAIGN_STATUS' AND lv.ValueCode='ACTIVE'),
    @user1;
SET @campaign1 = LAST_INSERT_ID();

-- Sample Donation Transaction (completed)
INSERT INTO DonationTransactions (
    DonationId, CampaignId, OrgId, DonorUserId,
    DonorName, DonorEmail, DonorMobile,
    DonationAmount, PlatformFeePct, PlatformFeeAmt, OrgReceivesAmt,
    DonTypeLkpId, PayMethodLkpId, VisibilityLkpId, PayStatusLkpId,
    GatewayOrderId, GatewayPaymentId
)
SELECT
    'DON-2026-000001',
    @campaign1, @org1, @user3,
    'Rahul Mehta', 'donor@test.com', '9876500099',
    5000.00, 1.00, 50.00, 4950.00,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='DONATION_TYPE' AND lv.ValueCode='ONE_TIME'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='PAYMENT_METHOD' AND lv.ValueCode='UPI'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='POST_VISIBILITY' AND lv.ValueCode='PUBLIC'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId=lv.LookupTypeId WHERE lt.TypeCode='DONATION_STATUS' AND lv.ValueCode='SUCCESS'),
    'order_test_001', 'pay_test_001';

-- Update campaign raised amount
UPDATE DonationCampaigns SET RaisedAmount = 5000.00, DonorCount = 1 WHERE CampaignId = @campaign1;

-- Update IdSequence for DON
INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue)
VALUES ('DON', YEAR(CURDATE()), 1)
ON DUPLICATE KEY UPDATE LastValue = 1;

-- User Skills (test data)
INSERT INTO UserSkills (UserId, SkillName, AvgRating, RatingCount) VALUES
(@user2, 'Teaching', 4.50, 6),
(@user2, 'Community Outreach', 4.20, 3),
(@user1, 'Project Management', 4.80, 10);

-- Test Notification
INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType, IsRead)
VALUES
(@user2, 'NEW_APPLICATION', 'Application Received', 'Your application for Tree Plantation Drive 2026 has been received.', @proj1, 'Project', 0),
(@user1, 'NEW_APPLICATION', 'New Application', 'Priya Sharma applied for Tree Plantation Drive 2026.', @proj1, 'Project', 0);


-- ============================================================
-- STEP 8: STORED PROCEDURES
-- ============================================================

-- =============================================================================
-- NGO Connect — Stored Procedures: Auth Module
-- Run AFTER 01_Tables_Auth_User.sql
-- SPs: Auth_SendOTP, Auth_VerifyOTP, Auth_SaveRefreshToken,
--      Auth_GetRefreshToken, Auth_RevokeRefreshToken, Auth_RevokeRefreshTokenById
-- =============================================================================

DELIMITER //

-- ── Auth_SendOTP ──────────────────────────────────────────────────────────────
-- Called by: AuthDal.SendOtpAsync
-- Params: Recipient (mobile/email), CountryCode, OtpCode (6-digit from C#),
--         PurposeLkpId, IpAddress, ExpiryMinutes
-- Returns: IsSuccess INT, Message VARCHAR
-- Rate limit: max 3 OTPs per 10 min per Recipient+Purpose
-- DB Column note: OtpTokens has no CountryCode column (it lives on Users).
--                 CountryCode is accepted as param but NOT stored in OtpTokens.
-- -----------------------------------------------------------------------------
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

        -- Insert new OTP
        -- Note: OtpTokens table columns are: Recipient, OtpCode, PurposeLkpId, IpAddress, ExpiresAt
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


-- ── Auth_VerifyOTP ────────────────────────────────────────────────────────────
-- Called by: AuthDal.VerifyOtpAsync
-- Params: Recipient, OtpCode (user-entered), PurposeLkpId, IpAddress
-- Returns: IsSuccess INT, Message VARCHAR, UserId INT, IsNewUser TINYINT
-- Logic: validates OTP → creates user if new → returns UserId
-- DB Column notes:
--   Users table uses column name: Mobile (not MobileNumber)
--   Users table has NO RoleLkpId column — roles live in OrgMembers
--   UserProfiles.FirstName and LastName are NOT NULL — inserted as empty string
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS Auth_VerifyOTP //
CREATE PROCEDURE Auth_VerifyOTP(
    IN p_Recipient     VARCHAR(255),
    IN p_OtpCode       VARCHAR(6),
    IN p_PurposeLkpId  INT UNSIGNED,
    IN p_IpAddress     VARCHAR(45)
)
BEGIN
    DECLARE v_OtpTokenId     INT UNSIGNED DEFAULT 0;
    DECLARE v_StoredOtp      VARCHAR(6)   DEFAULT '';
    DECLARE v_AttemptCount   TINYINT      DEFAULT 0;
    DECLARE v_ExpiresAt      DATETIME;
    DECLARE v_OtpCountryCode VARCHAR(5)   DEFAULT '+91';
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

        -- Check if user already exists (DB column is "Mobile", not "MobileNumber")
        SELECT UserId INTO v_UserId
        FROM   Users
        WHERE  Mobile    = p_Recipient
          AND  IsDeleted = 0
        LIMIT  1;

        IF v_UserId = 0 THEN
            -- Attempt email match (recipient may be an email address)
            SELECT UserId INTO v_UserId
            FROM   Users
            WHERE  Email     = p_Recipient
              AND  IsDeleted = 0
            LIMIT  1;
        END IF;

        IF v_UserId = 0 THEN
            -- ── NEW USER ── Create user row
            -- Detect whether recipient looks like email or mobile
            IF p_Recipient LIKE '%@%' THEN
                INSERT INTO Users (Email, CountryCode, IsVerified)
                VALUES (p_Recipient, '+91', 1);
            ELSE
                INSERT INTO Users (Mobile, CountryCode, IsVerified)
                VALUES (p_Recipient, '+91', 1);
            END IF;

            SET v_UserId    = LAST_INSERT_ID();
            SET v_IsNewUser = 1;

            -- Create empty profile row — FirstName/LastName are NOT NULL in DB,
            -- using empty string placeholders until user fills in their profile
            INSERT INTO UserProfiles (UserId, FirstName, LastName)
            VALUES (v_UserId, '', '');

        ELSE
            -- ── EXISTING USER ── ensure verified flag is set
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


-- ── Auth_SaveRefreshToken ─────────────────────────────────────────────────────
-- Called by: AuthDal (after VerifyOTP and RefreshToken)
-- Params: UserId, Token (SHA-256 hashed), DeviceInfo, IpAddress, ExpiresAt
-- Logic: Enforce max 5 concurrent sessions — drops oldest beyond limit
-- Returns: no result set (called via ExecuteNonQueryAsync)
-- -----------------------------------------------------------------------------
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


-- ── Auth_GetRefreshToken ──────────────────────────────────────────────────────
-- Called by: AuthDal.RefreshTokenAsync
-- Params: Token (SHA-256 hashed)
-- Returns: IsSuccess, Message, UserId, Recipient, RefreshTokenId
-- DB note: Users.Mobile (not MobileNumber)
-- -----------------------------------------------------------------------------
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
               COALESCE(u.Email, u.Mobile)        AS Recipient,   -- Mobile (not MobileNumber)
               v_TokenId                          AS RefreshTokenId
        FROM   Users u
        WHERE  u.UserId = v_UserId;
    END IF;
END //


-- ── Auth_RevokeRefreshToken ───────────────────────────────────────────────────
-- Called by: AuthDal.RevokeTokenAsync (logout)
-- Params: Token (SHA-256 hashed)
-- Returns: IsSuccess INT, Message VARCHAR
-- -----------------------------------------------------------------------------
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


-- ── Auth_RevokeRefreshTokenById ───────────────────────────────────────────────
-- Called by: AuthDal.RevokeRefreshTokenByIdAsync (during token rotation)
-- Params: RefreshTokenId
-- Returns: no result set (called via ExecuteNonQueryAsync)
-- ------------------- =============================================================================
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
-- Called by: UserDal.R-- ============================================================
-- NGO Connect — All New Module Stored Procedures
-- File: 04_SP_All_New_Modules.sql  |  v2.1 — DB-Aligned
-- Covers: Settings, Organisations, Projects, Applications,
--         Posts/Feed, Community/Polls, Donations, SOS, Notifications
-- Run after: NGOConnect_DB_Complete_Setup.sql
-- ============================================================
--
-- DB COLUMN CORRECTIONS vs v2.0 (key changes):
--   Users.Mobile            (not MobileNumber)
--   UserProfiles.Bio        (not About), ProfilePhoto (not ProfilePhotoUrl)
--   UserSkills              text-based (SkillName), no LkpId FKs
--   Organisations.RegNumber (not RegistrationNo), OrgTypeLkpId (not OrgTypeId)
--   Organisations.ContactEmail/ContactPhone (not Email/Phone)
--   Organisations.StatusLkpId INT FK (not IsVerified BOOL)
--   OrgMembers.RoleLkpId + StatusLkpId INT FK (not Role VARCHAR)
--   Projects.ProjectName    (not Title)
--   Projects.StatusLkpId/ProjectTypeLkpId/LocationTypeLkpId/JoinTypeLkpId INT FK
--   ProjectSessions: SessionDate DATE + StartTime TIME + EndTime TIME (no Title/Location)
--   ProjectSessions.SessionStatusLkpId INT FK, QrCode UUID-based
--   ProjectApplications.Motivation (not Note), StatusLkpId INT FK
--   Posts.PostTypeLkpId + VisibilityLkpId INT FK (not PostType VARCHAR)
--   PostMedia.FileUrl + MediaTypeLkpId INT FK (not MediaUrl)
--   PostReports.ReasonLkpId + StatusLkpId INT FK, ReportedByUserId (not UserId)
--   CommunityPosts.Title (NOT NULL), PostTypeLkpId, AudienceLkpId INT FK (no Tags)
--   CommunityPosts.PollEndsAt (not ExpiresAt), no IsPoll column
--   DonationCampaigns.CampaignName (not Title), TargetAmount (not GoalAmount)
--   DonationCampaigns.CampaignTypeLkpId + StatusLkpId + VisibilityLkpId INT FK
--   DonationTransactions: DonationId (not DonationRef), DonorUserId (not UserId)
--   DonationTransactions.DonationAmount, GatewayOrderId, PayStatusLkpId INT FK
--   RecurringDonations.RecurringDonId PK, DonorUserId, FrequencyLkpId+StatusLkpId INT FK
--   RecurringDonations.NextChargeDate DATE (not NextRunAt DATETIME)
--   IdSequences: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
--   SosIncidents.SosIncidentId PK, AlertTypeLkpId + StatusLkpId INT FK (not SosId/SosType/Status)
--   SosResponders.SosIncidentId (not SosId), ApprovalStatusLkpId INT FK
--   SosLocationLogs.SosIncidentId (not SosId)
--   Notifications: RefId (not EntityId), no IsDeleted column
-- ============================================================

-- ============================================================
-- CREATE TABLES NOT IN NGOConnect_DB_Complete_Setup.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS Settings (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS UserDeviceTokens (
    DeviceTokenId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId        INT UNSIGNED NOT NULL,
    Token         VARCHAR(512) NOT NULL,
    Platform      VARCHAR(20)  NOT NULL DEFAULT 'ANDROID',  -- ANDROID / IOS / WEB
    CreatedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt     DATETIME     NULL,
    PRIMARY KEY (DeviceTokenId),
    UNIQUE KEY uq_device_user_platform (UserId, Platform),
    INDEX idx_device_user (UserId),
    CONSTRAINT fk_devicetoken_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================
-- SEED: Settings
-- ============================================================

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('OTP',        'OTP_EXPIRY_MINUTES',   '10',                      'NUMBER',  'OTP expiry in minutes',                 0),
('OTP',        'OTP_MAX_ATTEMPTS',     '3',                       'NUMBER',  'Max OTP verification attempts',         0),
('OTP',        'OTP_RATE_LIMIT',       '3',                       'NUMBER',  'Max OTPs per 10 minutes per recipient', 0),
('AUTH',       'JWT_EXPIRY_MINUTES',   '15',                      'NUMBER',  'JWT access token expiry in minutes',    0),
('AUTH',       'REFRESH_EXPIRY_DAYS',  '30',                      'NUMBER',  'Refresh token expiry in days',          0),
('AUTH',       'MAX_SESSIONS',         '5',                       'NUMBER',  'Max concurrent sessions per user',      0),
('PAGINATION', 'DEFAULT_PAGE_SIZE',    '20',                      'NUMBER',  'Default page size for list APIs',       1),
('PAGINATION', 'MAX_PAGE_SIZE',        '100',                     'NUMBER',  'Maximum allowed page size',             1),
('PLATFORM',   'APP_NAME',             'NGO Connect',             'STRING',  'Platform display name',                 1),
('PLATFORM',   'SUPPORT_EMAIL',        'support@ngoconnect.app',  'STRING',  'Support email address',                 1),
('FEATURE',    'SOS_ENABLED',          'true',                    'BOOLEAN', 'Toggle SOS feature on/off',             0),
('FEATURE',    'DONATIONS_ENABLED',    'true',                    'BOOLEAN', 'Toggle donations feature on/off',       0),
('DONATION',   'MIN_DONATION_AMOUNT',  '10',                      'NUMBER',  'Minimum donation amount in INR',        1),
('DONATION',   'RAZORPAY_KEY_ID',      'rzp_test_xxxx',           'STRING',  'Razorpay Key ID (public)',              1),
('UPLOAD',     'MAX_FILE_SIZE_MB',     '10',                      'NUMBER',  'Maximum file upload size in MB',        1);


DELIMITER //

-- ============================================================
-- SETTINGS MODULE
-- ============================================================

DROP PROCEDURE IF EXISTS Settings_GetPublic //
CREATE PROCEDURE Settings_GetPublic()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description
    FROM   Settings
    WHERE  IsPublic = 1 AND IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_GetByGroup //
CREATE PROCEDURE Settings_GetByGroup(IN p_SettingGroup VARCHAR(50))
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  SettingGroup = p_SettingGroup AND IsDeleted = 0
    ORDER  BY SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_GetAll //
CREATE PROCEDURE Settings_GetAll()
BEGIN
    SELECT SettingId, SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic
    FROM   Settings
    WHERE  IsDeleted = 0
    ORDER  BY SettingGroup, SettingKey;
END //

DROP PROCEDURE IF EXISTS Settings_Update //
CREATE PROCEDURE Settings_Update(
    IN p_SettingKey   VARCHAR(100),
    IN p_SettingValue TEXT,
    IN p_UpdatedBy    INT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Settings WHERE SettingKey = p_SettingKey AND IsDeleted = 0) THEN
        SELECT 0 AS IsSuccess, 'Setting key not found.' AS Message;
    ELSE
        UPDATE Settings
        SET    SettingValue = p_SettingValue,
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UpdatedBy
        WHERE  SettingKey   = p_SettingKey AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Setting updated successfully.' AS Message;
    END IF;
END //


-- ============================================================
-- ORGANISATIONS MODULE
-- DB notes: RegNumber (not RegistrationNo), OrgTypeLkpId (not OrgTypeId),
--           ContactEmail (not Email), ContactPhone (not Phone),
--           StatusLkpId INT FK (not IsVerified BOOL)
--           OrgMembers: RoleLkpId + StatusLkpId INT FK (not Role VARCHAR)
-- ============================================================

DROP PROCEDURE IF EXISTS Org_Register //
CREATE PROCEDURE Org_Register(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgName        VARCHAR(200),
    IN p_RegistrationNo VARCHAR(100),    -- API param; maps to DB column: RegNumber
    IN p_Category       VARCHAR(100),
    IN p_About          TEXT,
    IN p_Website        VARCHAR(255),
    IN p_Phone          VARCHAR(20),     -- API param; maps to DB column: ContactPhone
    IN p_Email          VARCHAR(150),    -- API param; maps to DB column: ContactEmail
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Country        VARCHAR(100),
    IN p_OrgTypeLkpId   INT UNSIGNED    -- was p_OrgTypeId
)
BEGIN
    DECLARE v_PendingStatusId INT UNSIGNED DEFAULT 0;
    DECLARE v_FounderRoleId   INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedMemStatus INT UNSIGNED DEFAULT 0;
    DECLARE v_Duplicate       INT DEFAULT 0;

    -- Check duplicate registration number
    IF p_RegistrationNo IS NOT NULL THEN
        SELECT COUNT(*) INTO v_Duplicate FROM Organisations
        WHERE  RegNumber = p_RegistrationNo AND IsDeleted = 0;
    END IF;

    IF v_Duplicate > 0 THEN
        SELECT 0 AS IsSuccess, 'Organisation with this registration number already exists.' AS Message, NULL AS OrgId;
    ELSE
        -- Resolve status LkpIds from LookupValues
        SELECT lv.LookupValueId INTO v_PendingStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        SELECT lv.LookupValueId INTO v_FounderRoleId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1;

        SELECT lv.LookupValueId INTO v_ApprovedMemStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        -- Fallback to 1 if seed not present
        IF v_PendingStatusId = 0 THEN SET v_PendingStatusId = 1; END IF;
        IF v_FounderRoleId   = 0 THEN SET v_FounderRoleId   = 1; END IF;
        IF v_ApprovedMemStatus = 0 THEN SET v_ApprovedMemStatus = 1; END IF;

        INSERT INTO Organisations (
            OrgName, RegNumber, OrgTypeLkpId, Category,
            About, Website, ContactPhone, ContactEmail,
            City, State, Country, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgName, p_RegistrationNo, p_OrgTypeLkpId, COALESCE(p_Category, 'Community Service'),
            p_About, p_Website, p_Phone, p_Email,
            p_City, p_State, COALESCE(p_Country, 'India'), v_PendingStatusId, p_UserId
        );

        SET @NewOrgId = LAST_INSERT_ID();

        -- Add registering user as FOUNDER with APPROVED status
        INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
        VALUES (@NewOrgId, p_UserId, v_FounderRoleId, v_ApprovedMemStatus, NOW(), p_UserId);

        -- Initialise org donation settings row
        INSERT INTO OrgDonationSettings (OrgId, KycStatusLkpId)
        SELECT @NewOrgId,
               (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE lt.TypeCode = 'KYC_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1);

        SELECT 1 AS IsSuccess, 'Organisation registered successfully. Pending verification.' AS Message, @NewOrgId AS OrgId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category,
        o.About, o.Mission, o.Vision,
        o.Website, o.ContactPhone, o.ContactEmail,
        o.City, o.State, o.Country, o.LogoUrl,
        lv_type.ValueName   AS OrgType,
        lv_status.ValueName AS OrgStatus,
        o.CreatedAt,
        (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = o.OrgId AND IsDeleted = 0) AS MemberCount
    FROM   Organisations o
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = o.OrgTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = o.StatusLkpId
    WHERE  o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Org_Update //
CREATE PROCEDURE Org_Update(
    IN p_OrgId   INT UNSIGNED,
    IN p_UserId  INT UNSIGNED,
    IN p_About   TEXT,
    IN p_Website VARCHAR(255),
    IN p_Phone   VARCHAR(20),
    IN p_City    VARCHAR(100),
    IN p_State   VARCHAR(100),
    IN p_Country VARCHAR(100)
)
BEGIN
    DECLARE v_IsAdmin INT DEFAULT 0;

    -- Check caller has ADMIN or FOUNDER role in this org (with APPROVED member status)
    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can update.' AS Message;
    ELSE
        UPDATE Organisations
        SET    About        = COALESCE(p_About,   About),
               Website      = COALESCE(p_Website, Website),
               ContactPhone = COALESCE(p_Phone,   ContactPhone),
               City         = COALESCE(p_City,    City),
               State        = COALESCE(p_State,   State),
               Country      = COALESCE(p_Country, Country),
               UpdatedAt    = NOW(),
               UpdatedBy    = p_UserId
        WHERE  OrgId = p_OrgId AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Organisation updated successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT o.OrgId, o.OrgName, o.Category, o.City, o.State, o.LogoUrl,
           lv_type.ValueName   AS OrgType,
           lv_status.ValueName AS OrgStatus,
           (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = o.OrgId AND IsDeleted = 0) AS MemberCount
    FROM   Organisations o
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = o.OrgTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = o.StatusLkpId
    WHERE  o.IsDeleted = 0
      AND  (p_Search IS NULL
            OR o.OrgName   LIKE CONCAT('%', p_Search, '%')
            OR o.City      LIKE CONCAT('%', p_Search, '%')
            OR o.Category  LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY o.OrgName
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Organisations o
    WHERE  o.IsDeleted = 0
      AND  (p_Search IS NULL
            OR o.OrgName  LIKE CONCAT('%', p_Search, '%')
            OR o.City     LIKE CONCAT('%', p_Search, '%')
            OR o.Category LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Org_GetMembers //
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,                          -- was AvatarUrl
        lv_role.ValueName   AS RoleCode,
        lv_status.ValueName AS StatusCode,
        om.JoinedAt
    FROM   OrgMembers om
    JOIN   UserProfiles up ON up.UserId = om.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues lv_role   ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = om.StatusLkpId
    WHERE  om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER  BY om.JoinedAt;
END //

DROP PROCEDURE IF EXISTS Org_AddMember //
CREATE PROCEDURE Org_AddMember(
    IN p_OrgId         INT UNSIGNED,
    IN p_RequestedBy   INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_RoleLkpId     INT UNSIGNED    -- was p_Role VARCHAR
)
BEGIN
    DECLARE v_IsAdmin        INT DEFAULT 0;
    DECLARE v_Exists         INT DEFAULT 0;
    DECLARE v_ApprovedStatus INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RequestedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    SELECT COUNT(*) INTO v_Exists
    FROM   OrgMembers WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can add members.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'User is already a member of this organisation.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_ApprovedStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        IF v_ApprovedStatus = 0 THEN SET v_ApprovedStatus = 1; END IF;

        INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, JoinedAt, CreatedBy)
        VALUES (p_OrgId, p_UserId, p_RoleLkpId, v_ApprovedStatus, NOW(), p_RequestedBy);

        SELECT 1 AS IsSuccess, 'Member added successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Org_RemoveMember //
CREATE PROCEDURE Org_RemoveMember(
    IN p_OrgId        INT UNSIGNED,
    IN p_RequestedBy  INT UNSIGNED,
    IN p_OrgMemberId  INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin INT DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_RequestedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/founder can remove members.' AS Message;
    ELSE
        UPDATE OrgMembers
        SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_RequestedBy
        WHERE  OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Member removed successfully.' AS Message;
    END IF;
END //


-- ============================================================
-- PROJECTS + SESSIONS MODULE
-- DB notes: ProjectName (not Title), StatusLkpId/ProjectTypeLkpId/
--           LocationTypeLkpId/JoinTypeLkpId INT FK
--           ProjectSessions: SessionDate DATE, StartTime TIME, EndTime TIME
--           No Title/Location columns on ProjectSessions
--           SessionStatusLkpId INT FK required
-- ============================================================

DROP PROCEDURE IF EXISTS Project_Create //
CREATE PROCEDURE Project_Create(
    IN p_UserId             INT UNSIGNED,
    IN p_OrgId              INT UNSIGNED,
    IN p_Title              VARCHAR(200),   -- API param; maps to DB column: ProjectName
    IN p_Category           VARCHAR(100),
    IN p_Description        TEXT,
    IN p_City               VARCHAR(100),
    IN p_State              VARCHAR(100),
    IN p_ProjectTypeLkpId   INT UNSIGNED,
    IN p_LocationTypeLkpId  INT UNSIGNED,
    IN p_JoinTypeLkpId      INT UNSIGNED,
    IN p_MaxVolunteers      INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin       INT DEFAULT 0;
    DECLARE v_DraftStatusId INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied. Only org admin/moderator can create projects.' AS Message, NULL AS ProjectId;
    ELSE
        SELECT lv.LookupValueId INTO v_DraftStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

        IF v_DraftStatusId = 0 THEN SET v_DraftStatusId = 1; END IF;

        INSERT INTO Projects (
            OrgId, ProjectName, Category, Description,
            City, State,
            ProjectTypeLkpId, LocationTypeLkpId, JoinTypeLkpId,
            MaxVolunteers, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgId,
            p_Title,                    -- inserted into ProjectName
            COALESCE(p_Category, 'Community Service'),
            p_Description,
            p_City, p_State,
            p_ProjectTypeLkpId, p_LocationTypeLkpId, p_JoinTypeLkpId,
            p_MaxVolunteers,
            v_DraftStatusId,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Project created successfully.' AS Message, LAST_INSERT_ID() AS ProjectId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_GetById //
CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName,
        p.ProjectName,                  -- not Title
        p.Category, p.Description,
        p.City, p.State,
        lv_type.ValueName   AS ProjectType,
        lv_loc.ValueName    AS LocationType,
        lv_join.ValueName   AS JoinType,
        lv_status.ValueName AS Status,
        p.MaxVolunteers,
        p.IsPublic,
        p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS AppliedCount
    FROM   Projects p
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = p.ProjectTypeLkpId
    LEFT   JOIN LookupValues lv_loc    ON lv_loc.LookupValueId    = p.LocationTypeLkpId
    LEFT   JOIN LookupValues lv_join   ON lv_join.LookupValueId   = p.JoinTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = p.StatusLkpId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Project_Update //
CREATE PROCEDURE Project_Update(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_Title        VARCHAR(200),
    IN p_Description  TEXT,
    IN p_City         VARCHAR(100),
    IN p_State        VARCHAR(100),
    IN p_MaxVolunteers INT UNSIGNED,
    IN p_StatusLkpId  INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId   INT UNSIGNED;
    DECLARE v_IsAdmin INT DEFAULT 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message;
    ELSE
        UPDATE Projects
        SET    ProjectName    = COALESCE(p_Title,         ProjectName),
               Description    = COALESCE(p_Description,   Description),
               City           = COALESCE(p_City,          City),
               State          = COALESCE(p_State,         State),
               MaxVolunteers  = COALESCE(p_MaxVolunteers, MaxVolunteers),
               StatusLkpId    = COALESCE(p_StatusLkpId,   StatusLkpId),
               UpdatedAt      = NOW(),
               UpdatedBy      = p_UserId
        WHERE  ProjectId = p_ProjectId AND IsDeleted = 0;
        SELECT 1 AS IsSuccess, 'Project updated.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.ProjectId, p.OrgId, o.OrgName,
        p.ProjectName, p.Category, p.City, p.State,
        lv_status.ValueName AS Status,
        p.MaxVolunteers,
        p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId AND IsDeleted = 0) AS AppliedCount
    FROM   Projects p
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = p.StatusLkpId
    WHERE  p.IsDeleted = 0 AND p.IsPublic = 1
      AND  (p_OrgId  IS NULL OR p.OrgId = p_OrgId)
      AND  (p_Search IS NULL
            OR p.ProjectName LIKE CONCAT('%', p_Search, '%')
            OR p.City        LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Projects p
    WHERE  p.IsDeleted = 0 AND p.IsPublic = 1
      AND  (p_OrgId  IS NULL OR p.OrgId = p_OrgId)
      AND  (p_Search IS NULL
            OR p.ProjectName LIKE CONCAT('%', p_Search, '%')
            OR p.City        LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Project_AddSession //
CREATE PROCEDURE Project_AddSession(
    IN p_ProjectId    INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_SessionDate  DATE,
    IN p_StartTime    VARCHAR(5),   -- "HH:mm" from CreateSessionRequest.StartTime
    IN p_EndTime      VARCHAR(5),   -- "HH:mm" from CreateSessionRequest.EndTime
    IN p_MaxVolunteers INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId          INT UNSIGNED;
    DECLARE v_IsAdmin        INT DEFAULT 0;
    DECLARE v_UpcomingStatus INT UNSIGNED DEFAULT 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = p_ProjectId AND IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message, NULL AS SessionId;
    ELSE
        SELECT lv.LookupValueId INTO v_UpcomingStatus
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

        IF v_UpcomingStatus = 0 THEN SET v_UpcomingStatus = 1; END IF;

        SET @QrCode = UUID();   -- UUID as session QR (not SHA256 hash)

        -- DB columns: SessionDate DATE, StartTime TIME, EndTime TIME, QrCode, QrExpiresAt, SessionStatusLkpId
        INSERT INTO ProjectSessions (
            ProjectId, SessionDate, StartTime, EndTime,
            MaxVolunteers, QrCode, QrExpiresAt, SessionStatusLkpId, CreatedBy
        )
        VALUES (
            p_ProjectId,
            p_SessionDate,
            STR_TO_DATE(p_StartTime, '%H:%i'),
            STR_TO_DATE(p_EndTime,   '%H:%i'),
            p_MaxVolunteers,
            @QrCode,
            DATE_ADD(CONCAT(p_SessionDate, ' ', p_EndTime), INTERVAL 30 MINUTE),
            v_UpcomingStatus,
            p_UserId
        );

        SELECT 1 AS IsSuccess, 'Session added successfully.' AS Message, LAST_INSERT_ID() AS SessionId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_GetSessions //
CREATE PROCEDURE Project_GetSessions(IN p_ProjectId INT UNSIGNED)
BEGIN
    SELECT
        ps.SessionId, ps.ProjectId,
        ps.SessionDate, ps.StartTime, ps.EndTime,
        ps.MaxVolunteers, ps.QrCode, ps.QrExpiresAt,
        lv_status.ValueName AS SessionStatus,
        (SELECT COUNT(*) FROM ProjectAttendance WHERE SessionId = ps.SessionId) AS AttendeeCount
    FROM   ProjectSessions ps
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = ps.SessionStatusLkpId
    WHERE  ps.ProjectId = p_ProjectId AND ps.IsDeleted = 0
    ORDER  BY ps.SessionDate, ps.StartTime;
END //

DROP PROCEDURE IF EXISTS Project_GetSessionQr //
CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;
    DECLARE v_OrgId     INT UNSIGNED;
    DECLARE v_IsAdmin   INT DEFAULT 0;

    SELECT ProjectId INTO v_ProjectId FROM ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0;
    SELECT OrgId     INTO v_OrgId     FROM Projects WHERE ProjectId = v_ProjectId;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT NULL AS SessionId, NULL AS QrCode, NULL AS SessionDate;
    ELSE
        SELECT ps.SessionId, ps.QrCode, ps.QrExpiresAt,
               ps.SessionDate, ps.StartTime, ps.EndTime
        FROM   ProjectSessions ps
        WHERE  ps.SessionId = p_SessionId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Project_CheckIn //
CREATE PROCEDURE Project_CheckIn(
    IN p_UserId  INT UNSIGNED,
    IN p_QrToken VARCHAR(100)   -- matches QrCode UUID in ProjectSessions
)
BEGIN
    DECLARE v_SessionId      INT UNSIGNED;
    DECLARE v_QrExpiresAt    DATETIME;
    DECLARE v_AlreadyIn      INT DEFAULT 0;
    DECLARE v_AttendStatusId INT UNSIGNED DEFAULT 0;

    -- Find session by QR token
    SELECT SessionId, QrExpiresAt
    INTO   v_SessionId, v_QrExpiresAt
    FROM   ProjectSessions
    WHERE  QrCode = p_QrToken AND IsDeleted = 0
    LIMIT  1;

    IF v_SessionId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid QR code.' AS Message;
    ELSEIF NOW() > v_QrExpiresAt THEN
        SELECT 0 AS IsSuccess, 'QR code has expired.' AS Message;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyIn
        FROM   ProjectAttendance WHERE SessionId = v_SessionId AND UserId = p_UserId;

        IF v_AlreadyIn > 0 THEN
            SELECT 0 AS IsSuccess, 'Already checked in for this session.' AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_AttendStatusId
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

            IF v_AttendStatusId = 0 THEN SET v_AttendStatusId = 1; END IF;

            INSERT INTO ProjectAttendance (
                SessionId, UserId, CheckInTime, QrScannedAt, AttendStatusLkpId
            )
            VALUES (v_SessionId, p_UserId, NOW(), NOW(), v_AttendStatusId);

            SELECT 1 AS IsSuccess, 'Check-in successful.' AS Message;
        END IF;
    END IF;
END //


-- ============================================================
-- APPLICATIONS MODULE
-- DB notes: Motivation (not Note), StatusLkpId INT FK (not Status VARCHAR)
--           No AppliedAt column (use CreatedAt default)
-- ============================================================

DROP PROCEDURE IF EXISTS Application_Apply //
CREATE PROCEDURE Application_Apply(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_Note      TEXT          -- API param "Note"; maps to DB column: Motivation
)
BEGIN
    DECLARE v_IsActive  INT DEFAULT 0;
    DECLARE v_Exists    INT DEFAULT 0;
    DECLARE v_PendingId INT UNSIGNED DEFAULT 0;

    -- Check project is ACTIVE via StatusLkpId
    SELECT COUNT(*) INTO v_IsActive
    FROM   Projects p
    JOIN   LookupValues lv ON lv.LookupValueId = p.StatusLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  p.ProjectId = p_ProjectId AND lt.TypeCode = 'PROJECT_STATUS'
      AND  lv.ValueCode = 'ACTIVE' AND p.IsDeleted = 0;

    SELECT COUNT(*) INTO v_Exists
    FROM   ProjectApplications
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsActive = 0 THEN
        SELECT 0 AS IsSuccess, 'Project is not accepting applications.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already applied to this project.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingId = 0 THEN SET v_PendingId = 1; END IF;

        INSERT INTO ProjectApplications (ProjectId, UserId, Motivation, StatusLkpId)
        VALUES (p_ProjectId, p_UserId, p_Note, v_PendingId);

        SELECT 1 AS IsSuccess, 'Application submitted successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Application_GetByProject //
CREATE PROCEDURE Application_GetByProject(
    IN p_ProjectId  INT UNSIGNED,
    IN p_StatusLkpId INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName AS ProjectTitle,
        pa.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        lv_status.ValueName AS Status,
        pa.Motivation,              -- was Note
        pa.CreatedAt AS AppliedAt,
        pa.StatusUpdatedAt AS ReviewedAt
    FROM   ProjectApplications pa
    JOIN   Projects p ON p.ProjectId = pa.ProjectId
    JOIN   UserProfiles up ON up.UserId = pa.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = pa.StatusLkpId
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (p_StatusLkpId IS NULL OR pa.StatusLkpId = p_StatusLkpId)
    ORDER  BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM ProjectApplications pa
    WHERE  pa.ProjectId = p_ProjectId AND pa.IsDeleted = 0
      AND  (p_StatusLkpId IS NULL OR pa.StatusLkpId = p_StatusLkpId);
END //

DROP PROCEDURE IF EXISTS Application_Review //
CREATE PROCEDURE Application_Review(
    IN p_ApplicationId INT UNSIGNED,
    IN p_ReviewedBy    INT UNSIGNED,
    IN p_StatusLkpId   INT UNSIGNED,  -- was p_Status VARCHAR
    IN p_Note          TEXT
)
BEGIN
    DECLARE v_ProjectId INT UNSIGNED;
    DECLARE v_OrgId     INT UNSIGNED;
    DECLARE v_IsAdmin   INT DEFAULT 0;

    SELECT ProjectId INTO v_ProjectId
    FROM   ProjectApplications WHERE ApplicationId = p_ApplicationId AND IsDeleted = 0;

    SELECT OrgId INTO v_OrgId FROM Projects WHERE ProjectId = v_ProjectId;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = v_OrgId AND om.UserId = p_ReviewedBy
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER','MODERATOR')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message;
    ELSE
        UPDATE ProjectApplications
        SET    StatusLkpId      = p_StatusLkpId,
               RejectionReason  = CASE WHEN p_Note IS NOT NULL THEN p_Note ELSE RejectionReason END,
               StatusUpdatedBy  = p_ReviewedBy,
               StatusUpdatedAt  = NOW()
        WHERE  ApplicationId = p_ApplicationId;

        SELECT 1 AS IsSuccess, 'Application reviewed.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        pa.ApplicationId, pa.ProjectId, p.ProjectName AS ProjectTitle,
        o.OrgName, lv_status.ValueName AS Status,
        pa.Motivation, pa.CreatedAt AS AppliedAt,
        pa.StatusUpdatedAt AS ReviewedAt,
        p.City, p.State
    FROM   ProjectApplications pa
    JOIN   Projects p ON p.ProjectId = pa.ProjectId
    JOIN   Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = pa.StatusLkpId
    WHERE  pa.UserId = p_UserId AND pa.IsDeleted = 0
    ORDER  BY pa.CreatedAt DESC;
END //


-- ============================================================
-- POSTS / FEED MODULE
-- DB notes: PostTypeLkpId + VisibilityLkpId INT FK (not PostType VARCHAR)
--           PostMedia.FileUrl + MediaTypeLkpId INT FK (not MediaUrl)
--           PostReports.ReasonLkpId + StatusLkpId INT FK, ReportedByUserId (not UserId)
-- ============================================================

DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,
    IN p_PostTypeLkpId   INT UNSIGNED,  -- was p_PostType VARCHAR
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_DefaultTypeLkpId       INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultVisibilityLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_ImageTypeLkpId         INT UNSIGNED DEFAULT 0;

    -- Resolve defaults from LookupValues
    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
        SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
    END IF;

    IF p_VisibilityLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultVisibilityLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;
        SET p_VisibilityLkpId = COALESCE(v_DefaultVisibilityLkpId, 1);
    END IF;

    INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
    VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

    SET @NewPostId = LAST_INSERT_ID();

    -- Store media URLs (mapped to PostMedia.FileUrl + default IMAGE type)
    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN
        SELECT lv.LookupValueId INTO v_ImageTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

        IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;

        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT @NewPostId, TRIM(j.val), v_ImageTypeLkpId, j.rn
        FROM JSON_TABLE(CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
                        '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')) AS j
        WHERE TRIM(j.val) != '';
    END IF;

    SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
END //

DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId, p.Content, lv_type.ValueName AS PostType,
        p.LikeCount, p.CommentCount, p.CreatedAt,
        p.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId, o.OrgName,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe
    FROM   Posts p
    JOIN   UserProfiles up ON up.UserId = p.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    WHERE  p.IsDeleted = 0
    ORDER  BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Posts WHERE IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_GetById //
CREATE PROCEDURE Post_GetById(
    IN p_PostId INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        p.PostId, p.Content, lv_type.ValueName AS PostType,
        p.LikeCount, p.CommentCount, p.CreatedAt,
        p.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId, o.OrgName,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe
    FROM   Posts p
    JOIN   UserProfiles up ON up.UserId = p.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = p.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    WHERE  p.PostId = p_PostId AND p.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_Like //
CREATE PROCEDURE Post_Like(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    IF EXISTS (SELECT 1 FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId) THEN
        SELECT 0 AS IsSuccess, 'Already liked this post.' AS Message;
    ELSE
        INSERT INTO PostLikes (PostId, UserId) VALUES (p_PostId, p_UserId);
        UPDATE Posts SET LikeCount = LikeCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Post liked.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Post_Unlike //
CREATE PROCEDURE Post_Unlike(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DELETE FROM PostLikes WHERE PostId = p_PostId AND UserId = p_UserId;
    UPDATE Posts SET LikeCount = GREATEST(LikeCount - 1, 0) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post unliked.' AS Message;
END //

DROP PROCEDURE IF EXISTS Post_AddComment //
CREATE PROCEDURE Post_AddComment(
    IN p_PostId          INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_ParentCommentId INT UNSIGNED
)
BEGIN
    INSERT INTO PostComments (PostId, UserId, Content, ParentCommentId)
    VALUES (p_PostId, p_UserId, p_Content, p_ParentCommentId);

    UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;

    SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId;
END //

DROP PROCEDURE IF EXISTS Post_GetComments //
CREATE PROCEDURE Post_GetComments(
    IN p_PostId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        pc.CommentId, pc.ParentCommentId, pc.Content, pc.CreatedAt,
        pc.UserId, CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto
    FROM   PostComments pc
    JOIN   UserProfiles up ON up.UserId = pc.UserId AND up.IsDeleted = 0
    WHERE  pc.PostId = p_PostId AND pc.IsDeleted = 0
    ORDER  BY pc.CreatedAt
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM PostComments WHERE PostId = p_PostId AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId       INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_ReasonLkpId  INT UNSIGNED,  -- was p_Reason TEXT
    IN p_Details      TEXT
)
BEGIN
    DECLARE v_Exists         INT DEFAULT 0;
    DECLARE v_PendingStatusId INT UNSIGNED DEFAULT 0;

    -- PostReports uses ReportedByUserId (not UserId)
    SELECT COUNT(*) INTO v_Exists
    FROM   PostReports WHERE PostId = p_PostId AND ReportedByUserId = p_UserId;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingStatusId = 0 THEN SET v_PendingStatusId = 1; END IF;

        INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
        VALUES (p_PostId, p_UserId, p_ReasonLkpId, p_Details, v_PendingStatusId);

        SELECT 1 AS IsSuccess, 'Post reported. Our team will review it.' AS Message;
    END IF;
END //


-- ============================================================
-- COMMUNITY / POLLS MODULE
-- DB notes: CommunityPosts.Title NOT NULL, PostTypeLkpId + AudienceLkpId INT FK
--           No Tags column, no IsPoll column, no ExpiresAt column
--           PollEndsAt DATETIME for poll expiry
-- ============================================================

DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId        INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_Title         VARCHAR(300),   -- NOT NULL in DB
    IN p_Content       TEXT,
    IN p_PostTypeLkpId INT UNSIGNED,
    IN p_AudienceLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    IF p_AudienceLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'ORG_MEMBERS' LIMIT 1;
        SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
    END IF;

    INSERT INTO CommunityPosts (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, CreatedBy)
    VALUES (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_UserId);

    SELECT 1 AS IsSuccess, 'Community post created.' AS Message, LAST_INSERT_ID() AS CommunityPostId;
END //

DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId, cp.Title, cp.Content,
        lv_type.ValueName AS PostType, cp.CreatedAt,
        cp.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName,
        up.ProfilePhoto,
        cp.OrgId, o.OrgName,
        cp.AcknowledgeCount
    FROM   CommunityPosts cp
    JOIN   UserProfiles up ON up.UserId = cp.UserId AND up.IsDeleted = 0
    LEFT   JOIN Organisations o ON o.OrgId = cp.OrgId
    LEFT   JOIN LookupValues lv_type ON lv_type.LookupValueId = cp.PostTypeLkpId
    WHERE  cp.IsDeleted = 0
      AND  (p_OrgId IS NULL OR cp.OrgId = p_OrgId)
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM CommunityPosts WHERE IsDeleted = 0
      AND  (p_OrgId IS NULL OR OrgId = p_OrgId);
END //

DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT
)
BEGIN
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_PollTypeLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

    SELECT lv.LookupValueId INTO v_AudienceLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'ORG_MEMBERS' LIMIT 1;

    IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
    IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

    -- Title stores the poll question; PollEndsAt computed from ExpiresInHours
    INSERT INTO CommunityPosts (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, CreatedBy)
    VALUES (
        p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
        v_AudienceLkpId,
        DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR),
        p_UserId
    );

    SET @PollId = LAST_INSERT_ID();

    INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
    SELECT @PollId, jt.opt, jt.rn
    FROM JSON_TABLE(p_OptionsJson, '$[*]' COLUMNS (
        rn   FOR ORDINALITY,
        opt  VARCHAR(200) PATH '$'
    )) AS jt;

    SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId;
END //

DROP PROCEDURE IF EXISTS Community_Vote //
CREATE PROCEDURE Community_Vote(
    IN p_PollId       INT UNSIGNED,   -- CommunityPostId
    IN p_UserId       INT UNSIGNED,
    IN p_PollOptionId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists   INT DEFAULT 0;
    DECLARE v_Expired  INT DEFAULT 0;

    -- Check poll not expired (PollEndsAt, not ExpiresAt)
    SELECT COUNT(*) INTO v_Expired FROM CommunityPosts
    WHERE  CommunityPostId = p_PollId AND PollEndsAt IS NOT NULL AND PollEndsAt < NOW();

    SELECT COUNT(*) INTO v_Exists FROM PollVotes
    WHERE  CommunityPostId = p_PollId AND UserId = p_UserId;

    IF v_Expired > 0 THEN
        SELECT 0 AS IsSuccess, 'This poll has expired.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already voted on this poll.' AS Message;
    ELSE
        INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId)
        VALUES (p_PollOptionId, p_PollId, p_UserId);

        UPDATE PollOptions SET VoteCount = VoteCount + 1 WHERE PollOptionId = p_PollOptionId;

        SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
    END IF;
END //


-- ============================================================
-- DONATIONS + RAZORPAY MODULE
-- DB notes: CampaignName (not Title), TargetAmount (not GoalAmount)
--           DonationTransactions: DonationId (not DonationRef), DonorUserId (not UserId)
--           DonationAmount (not Amount), GatewayOrderId (not RazorpayOrderId)
--           PayStatusLkpId INT FK (not Status VARCHAR)
--           IdSequences: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
--           RecurringDonations: RecurringDonId PK, DonorUserId, FrequencyLkpId + StatusLkpId INT FK
--           NextChargeDate DATE (not NextRunAt DATETIME), StartDate required
-- ============================================================

DROP PROCEDURE IF EXISTS Donation_CreateCampaign //
CREATE PROCEDURE Donation_CreateCampaign(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgId             INT UNSIGNED,
    IN p_Title             VARCHAR(200),    -- API param; maps to DB column: CampaignName
    IN p_Description       TEXT,
    IN p_GoalAmount        DECIMAL(12,2),   -- API param; maps to DB column: TargetAmount
    IN p_StartDate         DATE,
    IN p_EndDate           DATE,
    IN p_BannerUrl         VARCHAR(500),
    IN p_CampaignTypeLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_IsAdmin         INT DEFAULT 0;
    DECLARE v_ActiveStatusId  INT UNSIGNED DEFAULT 0;
    DECLARE v_PublicVisId     INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode IN ('ADMIN','FOUNDER')
      AND  om.IsDeleted = 0;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Access denied.' AS Message, NULL AS CampaignId;
    ELSE
        SELECT lv.LookupValueId INTO v_ActiveStatusId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'CAMPAIGN_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

        SELECT lv.LookupValueId INTO v_PublicVisId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;

        IF v_ActiveStatusId = 0 THEN SET v_ActiveStatusId = 1; END IF;
        IF v_PublicVisId    = 0 THEN SET v_PublicVisId    = 1; END IF;

        INSERT INTO DonationCampaigns (
            OrgId, CreatedByUserId, CampaignName, Description,
            CampaignTypeLkpId, TargetAmount, RaisedAmount,
            StartDate, EndDate, BannerUrl,
            VisibilityLkpId, StatusLkpId, CreatedBy
        )
        VALUES (
            p_OrgId, p_UserId, p_Title, p_Description,
            p_CampaignTypeLkpId, p_GoalAmount, 0.00,
            p_StartDate, p_EndDate, p_BannerUrl,
            v_PublicVisId, v_ActiveStatusId, p_UserId
        );

        SELECT 1 AS IsSuccess, 'Campaign created.' AS Message, LAST_INSERT_ID() AS CampaignId;
    END IF;
END //

DROP PROCEDURE IF EXISTS Donation_GetCampaigns //
CREATE PROCEDURE Donation_GetCampaigns(
    IN p_OrgId      INT UNSIGNED,
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        dc.CampaignId, dc.OrgId, o.OrgName,
        dc.CampaignName AS Title,       -- aliased to Title for API consistency
        dc.TargetAmount AS GoalAmount,  -- aliased to GoalAmount for API consistency
        dc.RaisedAmount, dc.DonorCount,
        dc.StartDate, dc.EndDate, dc.BannerUrl,
        lv_status.ValueName AS Status,
        ROUND((dc.RaisedAmount / NULLIF(dc.TargetAmount, 0)) * 100, 1) AS ProgressPct
    FROM   DonationCampaigns dc
    JOIN   Organisations o ON o.OrgId = dc.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dc.StatusLkpId
    WHERE  dc.IsDeleted = 0
      AND  (p_OrgId  IS NULL OR dc.OrgId = p_OrgId)
      AND  (p_Search IS NULL OR dc.CampaignName LIKE CONCAT('%', p_Search, '%'))
    ORDER  BY dc.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationCampaigns dc
    WHERE  dc.IsDeleted = 0
      AND  (p_OrgId  IS NULL OR dc.OrgId = p_OrgId)
      AND  (p_Search IS NULL OR dc.CampaignName LIKE CONCAT('%', p_Search, '%'));
END //

DROP PROCEDURE IF EXISTS Donation_GetCampaignById //
CREATE PROCEDURE Donation_GetCampaignById(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        dc.CampaignId, dc.OrgId, o.OrgName,
        dc.CampaignName AS Title,
        dc.Description,
        dc.TargetAmount AS GoalAmount,
        dc.RaisedAmount, dc.DonorCount,
        dc.StartDate, dc.EndDate, dc.BannerUrl,
        lv_status.ValueName AS Status,
        ROUND((dc.RaisedAmount / NULLIF(dc.TargetAmount, 0)) * 100, 1) AS ProgressPct
    FROM   DonationCampaigns dc
    JOIN   Organisations o ON o.OrgId = dc.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dc.StatusLkpId
    WHERE  dc.CampaignId = p_CampaignId AND dc.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Donation_Initiate //
CREATE PROCEDURE Donation_Initiate(
    IN p_UserId        INT UNSIGNED,
    IN p_CampaignId    INT UNSIGNED,
    IN p_Amount        DECIMAL(10,2),
    IN p_Note          TEXT,
    IN p_IsAnonymous   TINYINT(1),
    IN p_PayMethodLkpId INT UNSIGNED  -- LkpId for UPI/CARD/etc (TypeCode='PAYMENT_METHOD')
)
BEGIN
    DECLARE v_Year        VARCHAR(4);
    DECLARE v_SeqNo       INT UNSIGNED;
    DECLARE v_DonationId  VARCHAR(30);
    DECLARE v_GatewayOrderId VARCHAR(100);
    DECLARE v_OrgId       INT UNSIGNED;
    DECLARE v_PlatformPct DECIMAL(5,2) DEFAULT 1.00;
    DECLARE v_PlatformAmt DECIMAL(10,2);
    DECLARE v_OrgAmt      DECIMAL(12,2);
    DECLARE v_PendingPayStatus INT UNSIGNED DEFAULT 0;
    DECLARE v_OneTimeDonType   INT UNSIGNED DEFAULT 0;
    DECLARE v_PublicVisId      INT UNSIGNED DEFAULT 0;

    SET v_Year = YEAR(NOW());

    -- Generate readable donation ID: DON-2026-000001
    -- IdSequences uses: SequenceName, CurrentYear, LastValue (not SeqKey, LastVal)
    INSERT INTO IdSequences (SequenceName, CurrentYear, LastValue)
    VALUES ('DON', v_Year, 1)
    ON DUPLICATE KEY UPDATE LastValue = LastValue + 1;

    SELECT LastValue INTO v_SeqNo
    FROM   IdSequences WHERE SequenceName = 'DON' AND CurrentYear = v_Year;

    SET v_DonationId     = CONCAT('DON-', v_Year, '-', LPAD(v_SeqNo, 6, '0'));
    SET v_GatewayOrderId = CONCAT('order_', UNIX_TIMESTAMP(), '_', p_UserId);

    -- Get OrgId and platform fee from campaign
    SELECT dc.OrgId, COALESCE(ods.PlatformFeePct, 1.00)
    INTO   v_OrgId, v_PlatformPct
    FROM   DonationCampaigns dc
    LEFT   JOIN OrgDonationSettings ods ON ods.OrgId = dc.OrgId
    WHERE  dc.CampaignId = p_CampaignId LIMIT 1;

    SET v_PlatformAmt = ROUND(p_Amount * v_PlatformPct / 100, 2);
    SET v_OrgAmt      = p_Amount - v_PlatformAmt;

    -- Resolve required LkpIds
    SELECT lv.LookupValueId INTO v_PendingPayStatus
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'DONATION_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_OneTimeDonType
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'DONATION_TYPE' AND lv.ValueCode = 'ONE_TIME' LIMIT 1;

    SELECT lv.LookupValueId INTO v_PublicVisId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC' LIMIT 1;

    IF v_PendingPayStatus = 0 THEN SET v_PendingPayStatus = 1; END IF;
    IF v_OneTimeDonType   = 0 THEN SET v_OneTimeDonType   = 1; END IF;
    IF v_PublicVisId      = 0 THEN SET v_PublicVisId      = 1; END IF;

    INSERT INTO DonationTransactions (
        DonationId, CampaignId, OrgId, DonorUserId,
        DonationAmount, PlatformFeePct, PlatformFeeAmt, OrgReceivesAmt,
        DonTypeLkpId, PayMethodLkpId, VisibilityLkpId, PayStatusLkpId,
        GatewayOrderId
    )
    VALUES (
        v_DonationId, p_CampaignId, v_OrgId,
        CASE WHEN p_IsAnonymous = 1 THEN NULL ELSE p_UserId END,
        p_Amount, v_PlatformPct, v_PlatformAmt, v_OrgAmt,
        v_OneTimeDonType, p_PayMethodLkpId, v_PublicVisId, v_PendingPayStatus,
        v_GatewayOrderId
    );

    SELECT v_DonationId     AS DonationRef,
           v_GatewayOrderId AS RazorpayOrderId,
           p_Amount          AS Amount,
           LAST_INSERT_ID()  AS TransactionId;
END //

DROP PROCEDURE IF EXISTS Donation_VerifyPayment //
CREATE PROCEDURE Donation_VerifyPayment(
    IN p_UserId             INT UNSIGNED,
    IN p_DonationRef        VARCHAR(30),    -- API param; maps to DB column: DonationId
    IN p_RazorpayOrderId    VARCHAR(100),
    IN p_RazorpayPaymentId  VARCHAR(100),
    IN p_RazorpaySignature  VARCHAR(256)
)
BEGIN
    DECLARE v_TxnId      INT UNSIGNED;
    DECLARE v_Amount     DECIMAL(12,2);
    DECLARE v_CampaignId INT UNSIGNED;
    DECLARE v_SuccessId  INT UNSIGNED DEFAULT 0;

    -- DonationId is the readable reference (DON-2026-000001)
    SELECT TransactionId, DonationAmount, CampaignId
    INTO   v_TxnId, v_Amount, v_CampaignId
    FROM   DonationTransactions
    WHERE  DonationId = p_DonationRef
      AND  (DonorUserId = p_UserId OR DonorUserId IS NULL)
    LIMIT  1;

    IF v_TxnId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Donation transaction not found.' AS Message;
    ELSE
        -- NOTE: HMAC-SHA256 Razorpay signature verification must happen in C# BEFORE calling this SP
        SELECT lv.LookupValueId INTO v_SuccessId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'DONATION_STATUS' AND lv.ValueCode = 'SUCCESS' LIMIT 1;

        IF v_SuccessId = 0 THEN SET v_SuccessId = 1; END IF;

        UPDATE DonationTransactions
        SET    PayStatusLkpId  = v_SuccessId,
               GatewayPaymentId = p_RazorpayPaymentId,
               GatewayResponse  = p_RazorpaySignature
        WHERE  TransactionId = v_TxnId;

        -- Update campaign raised amount + donor count (denormalized)
        UPDATE DonationCampaigns
        SET    RaisedAmount = RaisedAmount + v_Amount,
               DonorCount  = DonorCount + 1
        WHERE  CampaignId = v_CampaignId;

        SELECT 1 AS IsSuccess, 'Payment verified. Thank you for your donation!' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS Donation_GetTransactions //
CREATE PROCEDURE Donation_GetTransactions(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        dt.TransactionId,
        dt.DonationId AS DonationRef,
        dt.DonationAmount AS Amount,
        lv_status.ValueName AS Status,
        dt.CreatedAt,
        dc.CampaignName AS CampaignTitle,
        o.OrgName
    FROM   DonationTransactions dt
    LEFT   JOIN DonationCampaigns dc ON dc.CampaignId = dt.CampaignId
    LEFT   JOIN Organisations o ON o.OrgId = dt.OrgId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId = dt.PayStatusLkpId
    WHERE  dt.DonorUserId = p_UserId AND dt.IsDeleted = 0
    ORDER  BY dt.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM DonationTransactions WHERE DonorUserId = p_UserId AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Donation_GetReceipt //
CREATE PROCEDURE Donation_GetReceipt(
    IN p_DonationId VARCHAR(30),
    IN p_UserId     INT UNSIGNED
)
BEGIN
    SELECT
        dr.ReceiptId,
        dr.ReceiptNumber,
        dr.ReceiptUrl,
        dr.FiscalYear,
        dr.IssuedAt,
        dt.DonationId,
        dt.DonationAmount AS Amount,
        dt.DonorName,
        dt.DonorEmail,
        o.OrgName,
        dc.CampaignName AS CampaignTitle
    FROM   DonationReceipts dr
    JOIN   DonationTransactions dt ON dt.TransactionId = dr.TransactionId
    JOIN   Organisations o         ON o.OrgId          = dt.OrgId
    LEFT   JOIN DonationCampaigns dc ON dc.CampaignId  = dt.CampaignId
    WHERE  dt.DonationId   = p_DonationId
      AND  dt.DonorUserId  = p_UserId;
END //


DROP PROCEDURE IF EXISTS Donation_SetupRecurring //
CREATE PROCEDURE Donation_SetupRecurring(
    IN p_UserId        INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_CampaignId    INT UNSIGNED,
    IN p_Amount        DECIMAL(12,2),
    IN p_FrequencyLkpId INT UNSIGNED,
    IN p_StartDate     DATE
)
BEGIN
    DECLARE v_ActiveStatusId INT UNSIGNED DEFAULT 0;
    DECLARE v_NextCharge     DATE;

    -- Resolve ACTIVE status for recurring donation
    SELECT lv.LookupValueId INTO v_ActiveStatusId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    IF v_ActiveStatusId = 0 THEN SET v_ActiveStatusId = 1; END IF;

    -- Compute NextChargeDate based on frequency
    SET v_NextCharge = p_StartDate;

    INSERT INTO RecurringDonations (
        DonorUserId, OrgId, CampaignId, Amount,
        FrequencyLkpId, StatusLkpId, StartDate, NextChargeDate
    )
    VALUES (
        p_UserId, p_OrgId, p_CampaignId, p_Amount,
        p_FrequencyLkpId, v_ActiveStatusId, p_StartDate, v_NextCharge
    );

    SELECT 1 AS IsSuccess, 'Recurring donation set up successfully.' AS Message, LAST_INSERT_ID() AS RecurringDonId;
END //


DROP PROCEDURE IF EXISTS Donation_CancelRecurring //
CREATE PROCEDURE Donation_CancelRecurring(
    IN p_RecurringDonId INT UNSIGNED,
    IN p_UserId         INT UNSIGNED
)
BEGIN
    DECLARE v_CancelledId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_CancelledId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'RECURRING_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

    IF v_CancelledId = 0 THEN SET v_CancelledId = 1; END IF;

    UPDATE RecurringDonations
    SET    StatusLkpId = v_CancelledId,
           CancelledAt = NOW(),
           IsDeleted   = 1,
           UpdatedAt   = NOW()
    WHERE  RecurringDonId = p_RecurringDonId
      AND  DonorUserId    = p_UserId
      AND  IsDeleted      = 0;

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'Recurring donation cancelled successfully.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Recurring donation not found or already cancelled.' AS Message;
    END IF;
END //


-- ============================================================
-- SOS MODULE
-- DB notes: SosIncidentId PK (not SosId), AlertTypeLkpId + StatusLkpId INT FK,
--           SosResponders.ApprovalStatusLkpId, SosLocationLogs.SosIncidentId
-- ============================================================

DROP PROCEDURE IF EXISTS Sos_Trigger //
CREATE PROCEDURE Sos_Trigger(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_AlertTypeLkpId INT UNSIGNED,
    IN p_Description    TEXT,
    IN p_ApproxLocation VARCHAR(300),
    IN p_Latitude       DECIMAL(10,7),
    IN p_Longitude      DECIMAL(10,7)
)
BEGIN
    DECLARE v_ActiveStatusId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveStatusId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    IF v_ActiveStatusId = 0 THEN SET v_ActiveStatusId = 1; END IF;

    INSERT INTO SosIncidents (
        UserId, OrgId, AlertTypeLkpId, Description,
        ApproxLocation, Latitude, Longitude, StatusLkpId
    )
    VALUES (
        p_UserId, p_OrgId, p_AlertTypeLkpId, p_Description,
        p_ApproxLocation, p_Latitude, p_Longitude, v_ActiveStatusId
    );

    SELECT 1 AS IsSuccess, 'SOS alert triggered. Help is on the way!' AS Message, LAST_INSERT_ID() AS SosIncidentId;
END //


DROP PROCEDURE IF EXISTS Sos_Respond //
CREATE PROCEDURE Sos_Respond(
    IN p_SosIncidentId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED
)
BEGIN
    DECLARE v_Exists     INT DEFAULT 0;
    DECLARE v_PendingId  INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists
    FROM   SosResponders
    WHERE  SosIncidentId = p_SosIncidentId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already responded to this incident.' AS Message;
    ELSE
        SELECT lv.LookupValueId INTO v_PendingId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        IF v_PendingId = 0 THEN SET v_PendingId = 1; END IF;

        INSERT INTO SosResponders (SosIncidentId, UserId, ApprovalStatusLkpId)
        VALUES (p_SosIncidentId, p_UserId, v_PendingId);

        SELECT 1 AS IsSuccess, 'Response recorded. Awaiting approval from incident admin.' AS Message;
    END IF;
END //


DROP PROCEDURE IF EXISTS Sos_UpdateLocation //
CREATE PROCEDURE Sos_UpdateLocation(
    IN p_SosIncidentId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_Latitude      DECIMAL(10,7),
    IN p_Longitude     DECIMAL(10,7),
    IN p_Accuracy      DECIMAL(8,2)
)
BEGIN
    INSERT INTO SosLocationLogs (SosIncidentId, UserId, Latitude, Longitude, Accuracy)
    VALUES (p_SosIncidentId, p_UserId, p_Latitude, p_Longitude, p_Accuracy);

    SELECT 1 AS IsSuccess, 'Location updated.' AS Message;
END //


DROP PROCEDURE IF EXISTS Sos_GetActive //
CREATE PROCEDURE Sos_GetActive(
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        si.SosIncidentId,
        si.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VictimName,
        lv_type.ValueName   AS AlertType,
        lv_status.ValueName AS Status,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.Description,
        si.CreatedAt,
        (SELECT COUNT(*) FROM SosResponders WHERE SosIncidentId = si.SosIncidentId) AS ResponderCount
    FROM   SosIncidents si
    JOIN   UserProfiles up ON up.UserId = si.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues lv_type   ON lv_type.LookupValueId   = si.AlertTypeLkpId
    LEFT   JOIN LookupValues lv_status ON lv_status.LookupValueId  = si.StatusLkpId
    WHERE  si.IsDeleted = 0
      AND  lv_status.ValueCode = 'ACTIVE'
    ORDER  BY si.CreatedAt DESC;
END //


DROP PROCEDURE IF EXISTS Sos_Resolve //
CREATE PROCEDURE Sos_Resolve(
    IN p_SosIncidentId  INT UNSIGNED,
    IN p_UserId         INT UNSIGNED,
    IN p_ResolvedByLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ResolvedId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ResolvedId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'RESOLVED' LIMIT 1;

    IF v_ResolvedId = 0 THEN SET v_ResolvedId = 1; END IF;

    UPDATE SosIncidents
    SET    StatusLkpId     = v_ResolvedId,
           ResolvedAt      = NOW(),
           ResolvedByLkpId = p_ResolvedByLkpId,
           UpdatedAt       = NOW()
    WHERE  SosIncidentId = p_SosIncidentId
      AND  IsDeleted     = 0;

    IF ROW_COUNT() > 0 THEN
        SELECT 1 AS IsSuccess, 'SOS incident marked as resolved.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Incident not found or already closed.' AS Message;
    END IF;
END //


-- ============================================================
-- NOTIFICATIONS MODULE
-- DB notes: No IsDeleted column, RefId (not EntityId)
-- ============================================================

DROP PROCEDURE IF EXISTS Notification_GetList //
CREATE PROCEDURE Notification_GetList(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        NotificationId,
        NotifType,
        Title,
        Body,
        RefId,
        RefType,
        IsRead,
        ReadAt,
        CreatedAt
    FROM   Notifications
    WHERE  UserId = p_UserId           -- no IsDeleted column on Notifications
    ORDER  BY CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Notifications WHERE UserId = p_UserId;
END //


DROP PROCEDURE IF EXISTS Notification_MarkRead //
CREATE PROCEDURE Notification_MarkRead(
    IN p_UserId         INT UNSIGNED,
    IN p_NotificationId BIGINT UNSIGNED  -- NULL = mark all
)
BEGIN
    IF p_NotificationId IS NULL THEN
        UPDATE Notifications
        SET    IsRead = 1, ReadAt = NOW()
        WHERE  UserId = p_UserId AND IsRead = 0;

        SELECT 1 AS IsSuccess, 'All notifications marked as read.' AS Message;
    ELSE
        UPDATE Notifications
        SET    IsRead = 1, ReadAt = NOW()
        WHERE  NotificationId = p_NotificationId
          AND  UserId         = p_UserId
          AND  IsRead         = 0;

        IF ROW_COUNT() > 0 THEN
            SELECT 1 AS IsSuccess, 'Notification marked as read.' AS Message;
        ELSE
            SELECT 0 AS IsSuccess, 'Notification not found or already read.' AS Message;
        END IF;
    END IF;
END //


-- ============================================================
-- LOOKUP MODULE
-- ============================================================

DROP PROCEDURE IF EXISTS Lookup_GetAllTypes //
CREATE PROCEDURE Lookup_GetAllTypes()
BEGIN
    SELECT LookupTypeId, TypeCode, TypeName, Description
    FROM   LookupTypes
    WHERE  IsDeleted = 0
    ORDER  BY TypeName;
END //


DROP PROCEDURE IF EXISTS Lookup_GetValuesByType //
CREATE PROCEDURE Lookup_GetValuesByType(IN p_TypeCode VARCHAR(50))
BEGIN
    SELECT lv.LookupValueId, lv.ValueCode, lv.ValueName, lv.Description, lv.OrderNo, lv.IsDefault
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode   = p_TypeCode
      AND  lv.IsDeleted  = 0
      AND  lt.IsDeleted  = 0
    ORDER  BY lv.OrderNo, lv.ValueName;
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

-- ============================================================
-- END OF SETUP
-- ============================================================
-- To verify run: SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='NGOConnect';
-- Should return 42+ tables.
-- SELECT COUNT(*) FROM LookupTypes;   -- Should return 42
-- SELECT COUNT(*) FROM LookupValues;  -- Should return 169+
-- SELECT COUNT(*) FROM Settings;      -- Should return 15
-- ============================================================

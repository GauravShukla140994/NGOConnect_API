# NGOConnect Database Documentation v5.0

**Database:** MySQL 8.0+  
**Version:** 5.0  
**Tables:** 62  
**Stored Procedures:** 204  
**Generated:** 2026-08-05  


**v5.0 Additions — Full Platform Release (absorbs all patches applied to Railway staging through 2026-08-05):**

- **OrgInvitations table** — NEW. Member invitation system (phone/email). Token-based, 30-day expiry. Maintained by 8 new `Org_Invite_*` SPs.
- **UserCommunicationPreferences table** — NEW. Per-user marketing opt-in/out flags (push, email, SMS). Maintained by `UserCommunicationPreference_Get/Update` SPs.
- **Campaigns table** — NEW. Marketing & Communication Center campaigns. MKTG_CAMPAIGN_TYPE/STATUS/PRIORITY lookups (MKTG_-prefixed to avoid collision with donation module).
- **CampaignChannels table** — NEW. Per-campaign channels (PUSH/EMAIL/SMS) with image/deeplink/actionlabel payload fields.
- **CampaignAudienceRules table** — NEW. One audience rule per campaign (Phase 1); composable segments planned for Phase 2.
- **CampaignRecipients table** — NEW. BIGINT PK. Per-recipient send/delivery/engagement tracking. `QueueStatus` values: PENDING/SENT/DELIVERED/FAILED/SKIPPED.
- **CampaignQueueJobs table** — NEW. BIGINT PK. Hangfire job tracking per campaign dispatch run.
- **UserBadges table** — SCHEMA REBUILT. Columns `BadgeType VARCHAR/AwardedByUserId` replaced with `BadgeLkpId INT UNSIGNED FK→LookupValues`, `AwardedBy INT UNSIGNED FK→Users NULL`, `AwardedByOrgId INT UNSIGNED FK→Organisations NULL`, `ProjectId INT UNSIGNED FK→Projects NULL`, `CreatedAt DATETIME`. Old `AwardedAt` removed.
- **VolunteerCertificates table** — SCHEMA REBUILT. Added `CertCode VARCHAR(20) UNIQUE` (CERT-YYYY-NNNNNN format), `OrgId INT UNSIGNED FK→Organisations`, `TotalHours DECIMAL(6,2)`, `IsDeleted TINYINT(1)`. `CertificateUrl` now nullable.
- **UserSkillRatings table** — SCHEMA REBUILT. Columns replaced: old `UserSkillId/RatedByUserId/SessionId/RatedAt` → new `(SkillRatingId, UserId, OrgId, ProjectId, SkillId FK→ProjectSkills, Rating DECIMAL(3,2), RatedBy, Notes, CreatedAt, UpdatedAt)`. UNIQUE KEY `(UserId, ProjectId, SkillId)` for upsert.
- **IdSequences** — new row `('CERT', YEAR(CURDATE()), 0)` seeded for certificate readable IDs.
- **Users table** — 2 new indexes: `idx_users_lastlogin (LastLoginAt)`, `idx_users_createdat (CreatedAt)` for campaign audience segment queries.
- **New LookupTypes:** `INVITE_TYPE` (PHONE, EMAIL), `INVITE_STATUS` (PENDING, OPENED, ACCEPTED, CANCELLED, EXPIRED), `MKTG_CAMPAIGN_TYPE`, `MKTG_CAMPAIGN_PRIORITY`, `MKTG_CAMPAIGN_STATUS`, `MKTG_CAMPAIGN_CHANNEL`.
- **New Settings groups:** `INVITE` (INVITE_BASE_URL, INVITE_TOKEN_EXPIRY_DAYS), `COMMUNICATION` (CAMPAIGN_BATCH_SIZE, CAMPAIGN_RETRY_MAX_ATTEMPTS, CAMPAIGN_RETRY_BACKOFF_MINUTES, CAMPAIGN_SMS_ENABLED, HANGFIRE_DASHBOARD_KEY), `SECURITY` (URL_SHARE_SECRET_KEY).
- **41 new SPs** and 20+ updated SPs — see SP table below.

---

**v4.9 Additions — FCM Notifications, Verification Badges, Tax Eligibility, Community All Post Types, Permission Enforcement, SuperAdmin Enhancements (2026-07-18):**

See v4.9 documentation for full details. Key additions: `UserDeviceTokens` table, Organisations tax eligibility columns, Notifications column renames, CommunityPosts new columns, 6 new Notification_GetTokens* SPs, SuperAdmin_Org_VerifyProfile, Community permission gates, Application_Review/Org_ReviewMembership/Sos_ApproveResponder FCM result columns.

---

## Architecture Principles

- **SP naming:** `{Module}_{Action}` — `Auth_SendOTP`, `Org_Register`, `Project_Create`
- **Parameter prefix:** `p_` — `p_UserId`, `p_OrgId`, `p_PageNumber`
- **WRITE SPs always return:** `IsSuccess INT`, `Message VARCHAR`, `[EntityId]`
- **READ SPs return:** direct SELECT rows; paged SPs add second result set `SELECT COUNT(*) AS TotalCount`
- **Soft delete:** all master tables have `IsDeleted TINYINT(1)`, `DeletedAt`, `DeletedBy`
- **LookupValues:** all category columns use `INT UNSIGNED FK → LookupValues` not enums
- **30/70 rule:** 30% typed C# models, 70% DynamicRow for display queries

---

## Tables (62 Total)

### Group 1 — Auth (4 tables)

#### Users
| Column | Type | Notes |
|---|---|---|
| UserId | INT UNSIGNED PK AUTO_INCREMENT | |
| Mobile | VARCHAR(20) UNIQUE NOT NULL | |
| Email | VARCHAR(255) UNIQUE NULL | |
| CountryCode | VARCHAR(5) DEFAULT '+91' | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| IsActive | TINYINT(1) DEFAULT 1 | |
| ProfileVerificationLkpId | INT UNSIGNED NULL FK→LookupValues | Super Admin review state (PROFILE_VERIFICATION_STATUS) |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

**Indexes (v5.0 NEW):** `idx_users_lastlogin (LastLoginAt)`, `idx_users_createdat (CreatedAt)` — support campaign audience segment queries (Active/Inactive/New user segments).

#### OtpTokens
| Column | Type | Notes |
|---|---|---|
| OtpTokenId | INT UNSIGNED PK AUTO_INCREMENT | |
| Recipient | VARCHAR(255) NOT NULL | Mobile or email |
| OtpCode | VARCHAR(10) NOT NULL | Hashed |
| PurposeLkpId | INT UNSIGNED FK→LookupValues | |
| AttemptCount | TINYINT DEFAULT 0 | Max 3 |
| ExpiresAt | DATETIME NOT NULL | |
| IsUsed | TINYINT(1) DEFAULT 0 | |
| IpAddress | VARCHAR(45) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### RefreshTokens
| Column | Type | Notes |
|---|---|---|
| RefreshTokenId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| TokenHash | VARCHAR(500) NOT NULL | SHA-256 |
| DeviceInfo | VARCHAR(500) NULL | |
| IpAddress | VARCHAR(45) NULL | |
| ExpiresAt | DATETIME NOT NULL | 30 days |
| RevokedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### UserDeviceTokens
| Column | Type | Notes |
|---|---|---|
| DeviceTokenId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| Token | VARCHAR(512) NOT NULL | FCM registration token from mobile device |
| DeviceType | VARCHAR(20) NULL | `android` / `ios` |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, Token) | One token row per device per user |
| INDEX | idx_udt_user (UserId) | Fast token lookup for push notifications |

> **Lifecycle:** Tokens inserted/updated via `Notification_SaveDeviceToken` when user logs in. Auto-deleted by `Notification_DeleteStaleToken` when Firebase returns `Unregistered`.

---

### Group 2 — Profiles (7 tables)

#### UserProfiles
| Column | Type | Notes |
|---|---|---|
| UserProfileId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED UNIQUE FK→Users | |
| FirstName | VARCHAR(80) NULL | |
| LastName | VARCHAR(80) NULL | |
| Bio | TEXT NULL | |
| GenderLkpId | INT UNSIGNED FK→LookupValues NULL | |
| DateOfBirth | DATE NULL | |
| ProfilePhoto | VARCHAR(500) NULL | Azure/S3 Blob URL |
| Occupation | VARCHAR(150) NULL | |
| Organisation | VARCHAR(200) NULL | Employer/company name |
| VolunteerExp | TEXT NULL | Previous NGO/volunteer experience (free text) |
| EducationLkpId | INT UNSIGNED FK→LookupValues NULL | |
| FieldOfStudy | VARCHAR(150) NULL | |
| WorkExpLkpId | INT UNSIGNED FK→LookupValues NULL | |
| AddressLine1 | VARCHAR(200) NULL | |
| AddressLine2 | VARCHAR(200) NULL | |
| Pincode | VARCHAR(20) NULL | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| ImpactScore | INT DEFAULT 0 | Synced by `User_GetImpact` SP on each call |
| ReliabilityPct | DECIMAL(5,2) DEFAULT 0.00 | |
| IsProfileComplete | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

#### UserDocuments
| Column | Type | Notes |
|---|---|---|
| UserDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | LookupType: DOCUMENT_TYPE_USER |
| FileUrl | VARCHAR(500) NOT NULL | |
| FileName | VARCHAR(255) NOT NULL | |
| FileSizeKb | INT UNSIGNED NOT NULL | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | Soft delete — supports upsert pattern |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### UserSkills
| Column | Type | Notes |
|---|---|---|
| UserSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| SkillName | VARCHAR(100) NOT NULL | |
| AvgRating | DECIMAL(3,2) DEFAULT 0.00 | Denormalized |
| RatingCount | INT DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, SkillName) | |

#### UserSkillRatings *(v5.0 SCHEMA REBUILT)*
| Column | Type | Notes |
|---|---|---|
| SkillRatingId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | Volunteer being rated |
| OrgId | INT UNSIGNED FK→Organisations NULL | Org context |
| ProjectId | INT UNSIGNED FK→Projects NULL | Project context |
| SkillId | INT UNSIGNED FK→ProjectSkills | References `ProjectSkills.ProjectSkillId` |
| Rating | DECIMAL(3,2) NOT NULL | 1.00–5.00 |
| RatedBy | INT UNSIGNED FK→Users NULL | Admin who gave the rating |
| Notes | VARCHAR(500) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, ProjectId, SkillId) | ON DUPLICATE KEY UPDATE for upsert |

> **Old schema removed:** `RaterUserId`, `RatedUserId`, `UserSkillId INT FK→UserSkills`, `Review`, `Rating TINYINT`. The new schema ties ratings to `ProjectSkills` (per-project skills) rather than `UserSkills` (user's own skill list).

#### UserBadges *(v5.0 SCHEMA REBUILT)*
| Column | Type | Notes |
|---|---|---|
| UserBadgeId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| BadgeLkpId | INT UNSIGNED FK→LookupValues | BADGE_TYPE lookup — StarVol, TeamPlayer, TopPerform, etc. |
| AwardedBy | INT UNSIGNED FK→Users NULL | Admin user who awarded the badge |
| AwardedByOrgId | INT UNSIGNED FK→Organisations NULL | Org context |
| ProjectId | INT UNSIGNED FK→Projects NULL | Project context |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, BadgeLkpId) | INSERT IGNORE — one badge per type per user |

> **Old schema removed:** `BadgeType VARCHAR(50) NOT NULL`, `AwardedByUserId INT UNSIGNED NOT NULL`, `AwardedAt`. These caused SP crashes ("Unknown column 'ub.BadgeLkpId'") in `Application_GetByProject`, `UserBadge_Award`, and `User_GetBadges`. Apply `NGOConnect_Patch_UserBadges_SchemaFix.sql` to Railway **before** any other patch.

#### UserInterests
| Column | Type | Notes |
|---|---|---|
| UserInterestId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| InterestLkpId | INT UNSIGNED FK→LookupValues | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, InterestLkpId) | |

#### UserSafetyPreferences
| Column | Type | Notes |
|---|---|---|
| UserSafetyPrefId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED UNIQUE FK→Users | One row per user (UPSERT) |
| EmergVisibilityLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| AutoShareDurLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| AllowLocDuringSos | TINYINT(1) DEFAULT 1 | |
| AllowLocDuringProj | TINYINT(1) DEFAULT 1 | |
| EmergencyContactName | VARCHAR(100) NULL | |
| EmergencyContactPhone | VARCHAR(20) NULL | |
| EmergencyContactRelation | VARCHAR(50) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME ON UPDATE CURRENT_TIMESTAMP | |

#### UserCommunicationPreferences *(v5.0 NEW)*
| Column | Type | Notes |
|---|---|---|
| PrefId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED UNIQUE FK→Users | One row per user (UPSERT) |
| ReceivePushNotifications | TINYINT(1) DEFAULT 1 | |
| ReceivePromotionalEmails | TINYINT(1) DEFAULT 1 | |
| ReceivePromotionalSms | TINYINT(1) DEFAULT 1 | |
| ReceiveNgoUpdates | TINYINT(1) DEFAULT 1 | |
| ReceiveDonationAlerts | TINYINT(1) DEFAULT 1 | |
| ReceiveVolunteerOpportunities | TINYINT(1) DEFAULT 1 | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

---

### Group 3 — Organisations (6 tables)

#### Organisations
| Column | Type | Notes |
|---|---|---|
| OrgId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgName | VARCHAR(300) NOT NULL | |
| RegNumber | VARCHAR(100) UNIQUE NULL | |
| OrgTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| Category | VARCHAR(100) NULL | |
| ContactPerson | VARCHAR(100) NULL | |
| About | TEXT NULL | |
| Mission | TEXT NULL | |
| Vision | TEXT NULL | |
| LogoUrl | VARCHAR(500) NULL | |
| AddressLine1 | VARCHAR(300) NULL | |
| AddressLine2 | VARCHAR(300) NULL | |
| Pincode | VARCHAR(20) NULL | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| Website | VARCHAR(300) NULL | |
| ContactEmail | VARCHAR(255) NULL | |
| ContactPhone | VARCHAR(20) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | ORG_STATUS — PENDING/APPROVED/REJECTED/SUSPENDED |
| MemberCount | INT DEFAULT 0 | Denormalized |
| AvgRating | DECIMAL(3,2) NOT NULL DEFAULT 0.00 | |
| RatingCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| Latitude | DECIMAL(10,7) NULL | |
| Longitude | DECIMAL(10,7) NULL | |
| FollowerCount | INT UNSIGNED DEFAULT 0 | Denormalized — maintained by Org_Follow/Org_Unfollow |
| VerificationStatusLkpId | INT UNSIGNED NULL FK→LookupValues | ORG_VERIFICATION_STATUS — PENDING/VERIFIED/REJECTED. INDEX `idx_org_verification` |
| Is80GEligible | TINYINT(1) DEFAULT 0 | 80G tax exemption eligibility |
| Is12AEligible | TINYINT(1) DEFAULT 0 | 12A tax registration eligibility |
| RejectionReason | TEXT NULL | Latest rejection reason; cleared on APPROVED |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### OrgFollowers
| Column | Type | Notes |
|---|---|---|
| OrgFollowerId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| IsFollowing | TINYINT(1) DEFAULT 1 | 1 = following, 0 = soft-unfollowed |
| FollowedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UnfollowedAt | DATETIME NULL | |
| UNIQUE | (OrgId, UserId) | |

#### OrgDocuments
| Column | Type | Notes |
|---|---|---|
| OrgDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| UploadedBy | INT UNSIGNED FK→Users | |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | LookupType: DOC_TYPE_ORG |
| FileUrl | VARCHAR(500) NOT NULL | |
| FileName | VARCHAR(255) NOT NULL | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### OrgMembers
| Column | Type | Notes |
|---|---|---|
| OrgMemberId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| UserId | INT UNSIGNED FK→Users | |
| RoleLkpId | INT UNSIGNED FK→LookupValues | ADMIN/STAFF/MEMBER |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| AdminNotes | VARCHAR(500) NULL | |
| RequestMessage | TEXT NULL | |
| CanPost | TINYINT(1) DEFAULT 1 | |
| CanComment | TINYINT(1) DEFAULT 1 | |
| CanCommunityPost | TINYINT(1) DEFAULT 1 | |
| MaxPostsPerDay | TINYINT DEFAULT 10 | |
| LocationSharingLkpId | INT UNSIGNED FK→LookupValues NULL | |
| RequestedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| JoinedAt | DATETIME NULL | Set when approved |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (OrgId, UserId) | |

#### OrgDonationSettings
| Column | Type | Notes |
|---|---|---|
| OrgDonSettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED UNIQUE FK→Organisations | |
| RazorpayKeyId | VARCHAR(200) NULL | |
| RazorpayKeySecret | VARCHAR(200) NULL | Encrypted |
| WithdrawalEnabled | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

#### OrgInvitations *(v5.0 NEW)*
| Column | Type | Notes |
|---|---|---|
| OrgInvitationId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| InvitedByUserId | INT UNSIGNED FK→Users NOT NULL | Admin who sent the invite |
| InvitedUserId | INT UNSIGNED FK→Users NULL | Set when target is an existing platform user |
| InviteTypeCode | VARCHAR(20) NOT NULL | `PHONE` or `EMAIL` (INVITE_TYPE lookup) |
| InviteValue | VARCHAR(255) NOT NULL | Phone number or email address |
| CountryCode | VARCHAR(6) NULL | For phone invites |
| InviteToken | VARCHAR(43) UNIQUE NOT NULL | 32-byte RNG → URL-safe base64 (43 chars) |
| TokenExpiry | DATETIME NOT NULL | Default: 30 days from send (INVITE_TOKEN_EXPIRY_DAYS setting) |
| InviteBaseUrl | VARCHAR(500) NULL | Landing page base URL |
| StatusCode | VARCHAR(20) NOT NULL DEFAULT 'PENDING' | INVITE_STATUS — PENDING/OPENED/ACCEPTED/CANCELLED/EXPIRED |
| SentAt | DATETIME NULL | |
| OpenedAt | DATETIME NULL | Set by Org_Invite_VerifyToken |
| AcceptedAt | DATETIME NULL | Set by Org_Invite_Accept |
| CancelledAt | DATETIME NULL | Set by Org_Invite_Cancel or Org_Invite_Decline |
| DeliveryStatus | VARCHAR(30) NULL | SMS/Email delivery outcome |
| DeliveryError | TEXT NULL | Provider error detail |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

---

### Group 4 — Projects (6 tables)

#### Projects
| Column | Type | Notes |
|---|---|---|
| ProjectId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| ProjectName | VARCHAR(200) NOT NULL | ⚠️ Correct column name — some older code used `Title` |
| Description | TEXT NULL | |
| ProjectTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| JoinTypeLkpId | INT UNSIGNED FK→LookupValues NULL | OPEN/APPROVAL/INVITE |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | DRAFT/ACTIVE/COMPLETED/CANCELLED/EXPIRED |
| MaxVolunteers | INT NULL | NULL = unlimited |
| MinAge | TINYINT NULL | |
| MaxAge | TINYINT NULL | |
| IsPublic | TINYINT(1) DEFAULT 1 | Public volunteer browse requires IsPublic=1 |
| RecurStart | DATE NULL | ⚠️ Not `StartDate` |
| RecurEnd | DATE NULL | ⚠️ Not `EndDate` |
| ScheduleType | VARCHAR(20) NULL | ONE_TIME/RECURRING/ONGOING |
| RecurDays | VARCHAR(100) NULL | ⚠️ Not `RecurrenceDays` |
| SessionStartTime | TIME NULL | ⚠️ Not `StartTime` |
| SessionEndTime | TIME NULL | ⚠️ Not `EndTime` |
| DurationMinutes | INT NULL | |
| LocationTypeLkpId | INT UNSIGNED FK→LookupValues NULL | IN_PERSON/ONLINE/HYBRID |
| Landmark | VARCHAR(200) NULL | ⚠️ SP alias: `p.Landmark AS LocationName` |
| AddressLine | VARCHAR(500) NULL | ⚠️ SP alias: `p.AddressLine AS Address` |
| Latitude | DECIMAL(10,7) NULL | |
| Longitude | DECIMAL(10,7) NULL | |
| MeetingLink | VARCHAR(500) NULL | |
| GenderRestriction | VARCHAR(20) NULL | ANY/MALE/FEMALE |
| RequiresApproval | TINYINT(1) DEFAULT 0 | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| AppliedCount | INT DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

> ⚠️ **No `CoverImageUrl` column** on Projects table. No direct `ScheduleType` column — derive via JOIN on `ProjectTypeLkpId` → `LookupValues`.

#### ProjectSkills
| Column | Type | Notes |
|---|---|---|
| ProjectSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SkillName | VARCHAR(100) NOT NULL | |
| IsRequired | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

> **Index:** `idx_projskill_project (ProjectId, SkillName)` — covering index for skill-match subquery in `Project_GetNearbyFeed`.

#### ProjectSessions
| Column | Type | Notes |
|---|---|---|
| SessionId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SessionDate | DATE NOT NULL | Stored as IST date |
| StartTime | TIME NOT NULL | Stored as IST time |
| EndTime | TIME NOT NULL | Stored as IST time |
| MaxVolunteers | INT NULL | |
| QrCode | VARCHAR(500) NULL | UUID token |
| QrExpiresAt | DATETIME NULL | UTC |
| SessionStatusLkpId | INT UNSIGNED FK→LookupValues NULL | |
| AttendeeCount | INT DEFAULT 0 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| UpdatedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

> ⚠️ **Timezone:** Session times stored as IST. `Project_GetSessionQr` uses `CONVERT_TZ(NOW(), '+00:00', '+05:30')` to compare with stored times. `QrExpiresAt` is UTC — `Project_CheckIn` compares with `NOW()` (also UTC). Railway MySQL server runs UTC.

#### ProjectApplications
| Column | Type | Notes |
|---|---|---|
| ApplicationId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| UserId | INT UNSIGNED FK→Users | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED/WITHDRAWN |
| Motivation | TEXT NULL | Applicant's motivation (was `Note`) |
| RequestedSessions | TEXT NULL | Comma-separated session preferences |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| StatusUpdatedAt | DATETIME NULL | |
| AdminNotes | TEXT NULL | |
| AppliedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (ProjectId, UserId) | |

#### ProjectAttendance
| Column | Type | Notes |
|---|---|---|
| AttendanceId | INT UNSIGNED PK AUTO_INCREMENT | |
| SessionId | INT UNSIGNED FK→ProjectSessions | |
| UserId | INT UNSIGNED FK→Users | |
| CheckInTime | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| HoursLogged | DECIMAL(4,2) NULL | Computed from session EndTime − StartTime |
| AttendStatusLkpId | INT UNSIGNED FK→LookupValues | ATTENDED/NO_SHOW/EXCUSED |
| IsNoShowExcused | TINYINT(1) DEFAULT 0 | |
| QrScannedAt | DATETIME NULL | NULL = manually marked by admin |
| AdminNote | TEXT NULL | |
| CreatedBy | INT UNSIGNED NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| UpdatedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (SessionId, UserId) | ON DUPLICATE KEY UPDATE |

#### VolunteerCertificates *(v5.0 SCHEMA REBUILT)*
| Column | Type | Notes |
|---|---|---|
| CertificateId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| ProjectId | INT UNSIGNED FK→Projects | |
| OrgId | INT UNSIGNED FK→Organisations | **v5.0 NEW** |
| CertCode | VARCHAR(20) UNIQUE | **v5.0 NEW** CERT-YYYY-NNNNNN via IdSequences |
| CertificateUrl | VARCHAR(500) NULL | Azure/S3 Blob — nullable (future PDF upload) |
| IssuedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| TotalHours | DECIMAL(6,2) NULL | **v5.0 NEW** |
| IsDeleted | TINYINT(1) DEFAULT 0 | **v5.0 NEW** |
| UNIQUE | (UserId, ProjectId) | |

---

### Group 5 — Content (13 tables)

#### Posts
| Column | Type | Notes |
|---|---|---|
| PostId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| OrgId | INT UNSIGNED FK→Organisations NULL | |
| Content | TEXT NOT NULL | |
| PostTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| VisibilityLkpId | INT UNSIGNED FK→LookupValues NULL | |
| LikeCount | INT DEFAULT 0 | Denormalized |
| CommentCount | INT DEFAULT 0 | Denormalized |
| IsPinned | TINYINT(1) DEFAULT 0 | |
| IsEmergency | TINYINT(1) NOT NULL DEFAULT 0 | Emergency post — floats to top of personalised feed |
| IsEvergreen | TINYINT(1) NOT NULL DEFAULT 0 | Stays in feed candidate pool beyond 7-day window |
| ShareCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized |
| SaveCount | INT UNSIGNED NOT NULL DEFAULT 0 | Maintained by Post_Save / Post_Unsave |
| PinnedAt | DATETIME NULL | |
| PinnedBy | INT UNSIGNED FK→Users NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED NOT NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

**Indexes:** `idx_post_emergency (IsEmergency, CreatedAt)`

#### PostMedia
| Column | Type | Notes |
|---|---|---|
| PostMediaId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| FileUrl | VARCHAR(500) NOT NULL | Column name is `FileUrl` (not `MediaUrl`) |
| MediaTypeLkpId | INT UNSIGNED FK→LookupValues NULL | IMAGE or VIDEO |
| SortOrder | TINYINT DEFAULT 0 | |

#### PostLikes
| Column | Type | Notes |
|---|---|---|
| PostLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| UserId | INT UNSIGNED FK→Users | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PostId, UserId) | |

#### PostSaves
| Column | Type | Notes |
|---|---|---|
| PostSaveId | BIGINT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PostId, UserId) | |
| INDEX | idx_postsave_user (UserId) | |

#### FeedInteractions
| Column | Type | Notes |
|---|---|---|
| InteractionId | BIGINT UNSIGNED PK AUTO_INCREMENT | High-volume analytics |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| PostId | INT UNSIGNED FK→Posts NOT NULL | |
| InteractionType | VARCHAR(30) NOT NULL | IMPRESSION \| VIEW \| LIKE \| COMMENT \| SHARE \| SAVE \| VOLUNTEER_CLICK \| DONATION_CLICK \| NGO_VISIT \| HIDE \| REPORT |
| DurationMs | INT UNSIGNED NULL | VIEW interactions only |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| INDEX | idx_feedint_user (UserId, CreatedAt) | |
| INDEX | idx_feedint_post (PostId, InteractionType) | |

#### PostComments
| Column | Type | Notes |
|---|---|---|
| CommentId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| UserId | INT UNSIGNED FK→Users | |
| ParentCommentId | INT UNSIGNED FK→PostComments NULL | Threading |
| Content | TEXT NOT NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### PostReports
| Column | Type | Notes |
|---|---|---|
| PostReportId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| ReportedByUserId | INT UNSIGNED FK→Users | Column name is `ReportedByUserId` (not `ReportedBy`) |
| ReasonLkpId | INT UNSIGNED FK→LookupValues | |
| Details | TEXT NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NULL | PENDING/REVIEWED/DISMISSED/RESOLVED |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CommunityPosts
| Column | Type | Notes |
|---|---|---|
| CommunityPostId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| UserId | INT UNSIGNED FK→Users | |
| Title | VARCHAR(300) NOT NULL | |
| Content | TEXT NULL | |
| PostTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| AudienceLkpId | INT UNSIGNED FK→LookupValues NULL | |
| IsPinned | TINYINT(1) DEFAULT 0 | ANNOUNCEMENT type — pin to top |
| VolunteersNeeded | INT UNSIGNED NULL | VOL_REQUEST type — slot count |
| EventRef | VARCHAR(200) NULL | Multi-purpose: EVENT_UPDATE → whatChanged; VOL_REQUEST → date/time; TASK → assignee name |
| ResourceFileUrl | VARCHAR(500) NULL | RESOURCE type — uploaded file URL |
| PollIsMultiChoice | TINYINT(1) DEFAULT 0 | POLL type — multi-select flag |
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| CommentCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| AcknowledgeCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CommunityPostLikes
| Column | Type | Notes |
|---|---|---|
| CommunityPostLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (CommunityPostId, UserId) | Toggle via INSERT…ON DUPLICATE KEY DELETE |

#### CommunityPostComments
| Column | Type | Notes |
|---|---|---|
| CommunityCommentId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| Content | TEXT NOT NULL | Max 2000 chars |
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

#### CommunityCommentLikes
| Column | Type | Notes |
|---|---|---|
| CommunityCommentLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityCommentId | INT UNSIGNED FK→CommunityPostComments NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (CommunityCommentId, UserId) | |

#### PollOptions
| Column | Type | Notes |
|---|---|---|
| PollOptionId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts | |
| OptionText | VARCHAR(500) NOT NULL | |
| VoteCount | INT DEFAULT 0 | Denormalized |
| PollEndsAt | DATETIME NULL | |

#### PollVotes
| Column | Type | Notes |
|---|---|---|
| PollVoteId | INT UNSIGNED PK AUTO_INCREMENT | |
| PollOptionId | INT UNSIGNED FK→PollOptions | |
| UserId | INT UNSIGNED FK→Users | |
| VotedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PollOptionId, UserId) | |

#### Notifications
| Column | Type | Notes |
|---|---|---|
| NotificationId | BIGINT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| NotifType | VARCHAR(50) NULL | String type code — NEW_APPLICATION, MEMBERSHIP_APPROVED, etc. (was `TypeLkpId`) |
| Title | VARCHAR(200) NOT NULL | |
| Body | TEXT NULL | |
| RefType | VARCHAR(50) NULL | POST / PROJECT / SOS / DONATION (was `EntityType`) |
| RefId | INT UNSIGNED NULL | Related entity ID (was `EntityId`) |
| OrgId | INT UNSIGNED NULL FK→Organisations | Org context for notification |
| IsRead | TINYINT(1) DEFAULT 0 | |
| ReadAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

**Indexes:** `idx_notif_org (OrgId)`

---

### Group 6 — Safety / SOS (3 tables)

#### SosIncidents
| Column | Type | Notes |
|---|---|---|
| SosIncidentId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users NOT NULL | Victim (actual column name `UserId`, not `VictimUserId`) |
| OrgId | INT UNSIGNED FK→Organisations NULL | |
| AlertTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | ACTIVE/RESOLVED/CANCELLED |
| Description | TEXT NULL | |
| ApproxLocation | VARCHAR(300) NULL | |
| Latitude | DECIMAL(10,7) NULL | |
| Longitude | DECIMAL(10,7) NULL | |
| CancelReason | TEXT NULL | |
| ResolvedByLkpId | INT UNSIGNED FK→LookupValues NULL | |
| ResolvedAt | DATETIME NULL | |
| CancelledAt | DATETIME NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### SosResponders
| Column | Type | Notes |
|---|---|---|
| SosResponderId | INT UNSIGNED PK AUTO_INCREMENT | |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| CanViewLocation | TINYINT(1) DEFAULT 0 | |
| RespondedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (SosIncidentId, UserId) | |

#### SosLocationLogs
| Column | Type | Notes |
|---|---|---|
| SosLocationLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | Every 10s |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | |
| Latitude | DECIMAL(10,7) NOT NULL | |
| Longitude | DECIMAL(10,7) NOT NULL | |
| Accuracy | DECIMAL(8,2) NULL | |
| LoggedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 7 — Donations (6 tables)

#### DonationCampaigns
| Column | Type | Notes |
|---|---|---|
| CampaignId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CreatedBy | INT UNSIGNED FK→Users | |
| CampaignName | VARCHAR(200) NOT NULL | SP param: `p_Title` |
| Description | TEXT NULL | |
| CampaignTypeLkpId | INT UNSIGNED FK→LookupValues | CAMPAIGN_TYPE lookup (donation module) |
| TargetAmount | DECIMAL(12,2) NOT NULL | SP param: `p_GoalAmount` |
| RaisedAmount | DECIMAL(12,2) DEFAULT 0 | Denormalized |
| StartDate | DATE NOT NULL | |
| EndDate | DATE NULL | |
| BannerUrl | VARCHAR(500) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | DRAFT/ACTIVE/COMPLETED/SUSPENDED |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### DonationTransactions
| Column | Type | Notes |
|---|---|---|
| DonationId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationRef | VARCHAR(30) UNIQUE | DON-2026-000001 via IdSequences |
| UserId | INT UNSIGNED FK→Users | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| DonationAmount | DECIMAL(10,2) NOT NULL | Column name: `DonationAmount` (not `Amount`) |
| PayMethodLkpId | INT UNSIGNED FK→LookupValues | |
| PayStatusLkpId | INT UNSIGNED FK→LookupValues | Column name: `PayStatusLkpId` (not `StatusLkpId`) |
| RazorpayOrderId | VARCHAR(200) NULL | |
| RazorpayPaymentId | VARCHAR(200) NULL | |
| Note | TEXT NULL | |
| IsAnonymous | TINYINT(1) DEFAULT 0 | |
| PaidAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### RecurringDonations, DonationReceipts, WithdrawalRequests, PaymentGatewayLogs
*(schemas unchanged from v4.9 — see v4.9 documentation)*

---

### Group 8 — System (2 tables)

#### AuditLogs
| Column | Type | Notes |
|---|---|---|
| AuditLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED NULL | |
| Action | VARCHAR(100) NOT NULL | CREATE/UPDATE/DELETE/SUPPORT_CONTACT |
| EntityName | VARCHAR(100) NOT NULL | |
| EntityId | INT UNSIGNED NULL | |
| OldValue | JSON NULL | |
| NewValue | JSON NULL | |
| IpAddress | VARCHAR(45) NULL | |
| UserAgent | VARCHAR(500) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

> **v5.0:** `Support_LogContact` writes `Action=SUPPORT_CONTACT, EntityName=SupportContact` with the full contact JSON in `NewValue`.

#### IdSequences
| Column | Type | Notes |
|---|---|---|
| SequenceId | INT UNSIGNED PK AUTO_INCREMENT | |
| PrefixCode | VARCHAR(10) UNIQUE NOT NULL | DON, WDR, REC, **CERT** *(v5.0 NEW)* |
| CurrentYear | SMALLINT NOT NULL | |
| LastNumber | INT DEFAULT 0 | |
| Padding | TINYINT DEFAULT 6 | |

**Readable ID format:** `{PREFIX}-{YEAR}-{PADDED_NUMBER}`  
DON-2026-000001, WDR-2026-0001, REC-2026-0001, **CERT-2026-000001** *(v5.0 NEW)*

---

### Group 9 — Lookup (2 tables)

*(schemas unchanged from v4.9)*

---

### Group 10 — Settings (1 table)

*(schema unchanged from v4.9)*

**New Settings (v5.0):**

| SettingGroup | SettingKey | Default | Description |
|---|---|---|---|
| INVITE | INVITE_BASE_URL | (URL) | Invite landing page base URL |
| INVITE | INVITE_TOKEN_EXPIRY_DAYS | 30 | Invite token validity in days |
| COMMUNICATION | CAMPAIGN_BATCH_SIZE | 500 | FCM/email recipients per dispatch batch |
| COMMUNICATION | CAMPAIGN_RETRY_MAX_ATTEMPTS | 3 | Max dispatch retry attempts |
| COMMUNICATION | CAMPAIGN_RETRY_BACKOFF_MINUTES | 5 | Backoff between retries |
| COMMUNICATION | CAMPAIGN_SMS_ENABLED | false | SMS gate — keep false until DLT/TRAI registration |
| COMMUNICATION | HANGFIRE_DASHBOARD_KEY | (empty) | `/hangfire` access key — fails closed if unset |
| SECURITY | URL_SHARE_SECRET_KEY | (placeholder) | AES-256-GCM key for share URL encryption — replace with `openssl rand -hex 32` |

---

### Group 11 — Super Admin (2 tables)

*(SuperAdminUsers and OrgStatusHistory schemas unchanged from v4.9)*

---

### Group 12 — Marketing & Communication Center (6 tables) *(v5.0 NEW)*

#### Campaigns
| Column | Type | Notes |
|---|---|---|
| CampaignId | INT UNSIGNED PK AUTO_INCREMENT | Marketing campaigns (MKTG_ prefix — separate from donation DonationCampaigns) |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | Super Admin only |
| Title | VARCHAR(200) NOT NULL | |
| Description | TEXT NULL | |
| CampaignType | VARCHAR(50) NOT NULL | MKTG_CAMPAIGN_TYPE ValueCode |
| Priority | VARCHAR(20) DEFAULT 'NORMAL' | MKTG_CAMPAIGN_PRIORITY ValueCode |
| Status | VARCHAR(20) DEFAULT 'DRAFT' | MKTG_CAMPAIGN_STATUS ValueCode |
| ScheduledAt | DATETIME NULL | NULL = send immediately on activation |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

#### CampaignChannels
| Column | Type | Notes |
|---|---|---|
| ChannelId | INT UNSIGNED PK AUTO_INCREMENT | |
| CampaignId | INT UNSIGNED FK→Campaigns NOT NULL | |
| Channel | VARCHAR(20) NOT NULL | MKTG_CAMPAIGN_CHANNEL ValueCode — PUSH/EMAIL/SMS |
| Subject | VARCHAR(300) NULL | Email subject |
| Body | TEXT NULL | Email body / SMS text |
| PushTitle | VARCHAR(200) NULL | |
| PushBody | TEXT NULL | |
| PushImageUrl | VARCHAR(500) NULL | |
| PushDeepLink | VARCHAR(500) NULL | |
| PushActionLabel | VARCHAR(100) NULL | In-app CTA text shown on destination screen after notification tap |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CampaignAudienceRules
| Column | Type | Notes |
|---|---|---|
| RuleId | INT UNSIGNED PK AUTO_INCREMENT | |
| CampaignId | INT UNSIGNED UNIQUE FK→Campaigns NOT NULL | One rule per campaign (Phase 1) |
| RuleType | VARCHAR(50) NOT NULL | ALL_USERS / ACTIVE_LAST_N_DAYS / INACTIVE_N_DAYS / NEW_USERS / SPECIFIC_USERS / ORG_MEMBERS |
| RuleParams | JSON NULL | e.g. `{"days": 30}` or `{"userIds": [1,2,3]}` |
| EstimatedCount | INT UNSIGNED NULL | Set by Campaign_EstimateAudience |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CampaignRecipients
| Column | Type | Notes |
|---|---|---|
| RecipientId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — high-volume |
| CampaignId | INT UNSIGNED FK→Campaigns NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| Channel | VARCHAR(20) NOT NULL | |
| QueueStatus | VARCHAR(20) DEFAULT 'PENDING' | PENDING/SENT/DELIVERED/FAILED/SKIPPED |
| SentAt | DATETIME NULL | When Firebase/SES accepted the send |
| DeliveredAt | DATETIME NULL | Set by device-side ack via `CampaignRecipient_AckDelivered` |
| FailReason | TEXT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| INDEX | (CampaignId, QueueStatus) | Fast queue polling |

> **Delivery acknowledgment:** Mobile app calls `POST /campaign-recipients/{id}/delivered` the moment notifee renders a CAMPAIGN notification. `SentCount` (Firebase accepted) and `DeliveredCount` (device ack) are tracked separately — `SentCount` was previously mislabeled "Delivered".

#### CampaignQueueJobs
| Column | Type | Notes |
|---|---|---|
| JobId | BIGINT UNSIGNED PK AUTO_INCREMENT | |
| CampaignId | INT UNSIGNED FK→Campaigns NOT NULL | |
| HangfireJobId | VARCHAR(100) NULL | Hangfire job ID for tracking |
| Status | VARCHAR(20) DEFAULT 'PENDING' | PENDING/RUNNING/COMPLETED/FAILED |
| StartedAt | DATETIME NULL | |
| CompletedAt | DATETIME NULL | |
| TotalRecipients | INT UNSIGNED DEFAULT 0 | |
| SentCount | INT UNSIGNED DEFAULT 0 | |
| FailCount | INT UNSIGNED DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

## Stored Procedures (204 Total)

### Auth (6 SPs)
*(unchanged from v4.9)*

### User (20 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| User_GetProfile | p_UserId, p_RequestingUserId | GET | **v5.0 UPDATED** Returns full profile. Added subqueries: `TotalHours` (SUM from ProjectAttendance ATTENDED), `ProjectsCount` (COMPLETED/EXPIRED approved applications), `NgosJoined` (APPROVED OrgMembers count). These match `User_GetImpact` logic — profile screen stats now computed at read time, not stale stored values |
| User_GetPublicProfile | p_UserId | GET | Public-safe profile |
| User_UpdateProfile | 19 params | WRITE | All fields COALESCE (partial update safe) |
| User_UpdateSafetyPrefs | 8 params | WRITE | UPSERT on UserId |
| User_SaveInterests | p_UserId, p_InterestLkpIds (JSON) | WRITE | DELETE all + INSERT from JSON array |
| User_UploadDocument | 5 params | WRITE | Upsert: soft-deletes existing same-type doc before inserting |
| User_GetDocuments | p_UserId | LIST | All active user documents with DocTypeCode/DocTypeName |
| User_DeleteDocument | p_UserDocumentId, p_UserId | WRITE | Soft-delete with ownership check |
| User_GetSkills | p_UserId | LIST | UserSkills with AvgRating, RatingCount |
| User_AddSkill | p_UserId, p_SkillName | WRITE | Insert; 0 if duplicate |
| User_RemoveSkill | p_UserId, p_UserSkillId | WRITE | Soft-delete |
| User_GetSafetyPrefs | p_UserId | GET | Safety prefs + emergency contacts |
| User_GetInterests | p_UserId | LIST | User interests with lookup names |
| User_GetMyOrgs | p_UserId | LIST (Dynamic) | **v5.0 UPDATED** Added `SuspendedAt` subquery (first UNION; `NULL AS SuspendedAt` in second UNION for column parity). Previously added `RejectionReason`. Returns: OrgId, OrgName, LogoUrl, OrgType, City, State, Role, RoleCode, MemberStatusCode, OrgStatusCode, MemberCount, JoinedAt, RejectionReason, **SuspendedAt** |
| User_GetBadges | p_UserId | LIST | **v5.0 UPDATED** Returns `lv.ValueCode AS BadgeCode`, `lv.ValueName AS BadgeName` (JOIN LookupValues on BadgeLkpId), `OrgName` (via AwardedByOrgId FK), `ProjectName` (via ProjectId FK). Old version returning raw VARCHAR `BadgeType` was duplicate and removed |
| User_GetImpact | p_UserId | GET | **v5.0 UPDATED** `v_ProjCompleted` now counts via ProjectApplications APPROVED + project StatusLkpId IN (COMPLETED, EXPIRED) — no longer requires explicit ProjectAttendance rows (fixes "always 0" bug on Railway). Also syncs `UserProfiles.ImpactScore` via UPDATE after calculation |
| User_GetImpactSummary | p_UserId, p_AppLimit, p_BadgeLimit | READ (7 RS) | **v5.0 NEW** 7 result sets: RS0 Applied, RS1 Upcoming, RS2 Completed *(includes `HoursLogged`, `HasCertificate`)*,  RS3 Cancelled — each server-filtered by status and LIMIT p_AppLimit. RS4: latest p_BadgeLimit badges. RS5: TotalApplied/Upcoming/Completed/Cancelled/Badges counts. RS6: full impact stats (same logic as User_GetImpact) |
| User_SendContactOtp | p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress | WRITE | OTP to add new phone or email |
| User_VerifyContactOtp | p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress | WRITE | Verifies OTP and updates Users.Email or Users.Mobile |

### Lookup (4 SPs)
*(unchanged from v4.9)*

### Settings (4 SPs)
*(unchanged from v4.9)*

### Organisation (39 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| Org_Register | 21 params | WRITE | Includes Is80GEligible, Is12AEligible |
| Org_GetProfile | p_OrgId, p_UserId | GET | Returns Is80GEligible, Is12AEligible, VerificationStatusCode, FollowerCount, IsFollowing |
| Org_Update | 20 params | WRITE | COALESCE partial update; includes Is80GEligible/Is12AEligible |
| Org_GetDashboard | p_OrgId | GET | KPIs including FollowerCount, PendingProjectApplications |
| Org_List | 4 params | PAGED | Returns FollowerCount |
| Org_ListRecommended | p_UserId | LIST | Interest-matched orgs |
| Org_GetVolunteerProfile | p_OrgId, p_UserId | GET | Full volunteer profile for admin view |
| Org_GetMemberImpact | p_OrgId, p_UserId | GET | Member impact detail |
| Org_UpdateMemberRole | p_OrgId, p_MemberId, p_RoleCode, p_UpdatedBy | WRITE | `p_RoleCode VARCHAR(50)` (resolves LkpId internally). Returns `UserId` for FCM trigger |
| Org_GetMembers | p_OrgId | LIST | All members with role, status, permissions, ProfileVerificationStatusCode |
| Org_AddMember | p_OrgId, p_UserId, p_RoleLkpId, p_RequestedBy | WRITE | Direct admin add |
| Org_RemoveMember | p_OrgId, p_UserId, p_RemovedBy | WRITE | **v5.0 SECURITY FIX** Requester check: `p_RemovedBy` must be ADMIN or FOUNDER. Founder protection: target FOUNDER cannot be removed. Returns `IsSuccess=0` with "Access denied" / "Founder cannot be removed" |
| Org_RequestMembership | p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin | WRITE | **v5.0 FIXED** Re-join: duplicate-check now filters by PENDING only (old APPROVED/REJECTED rows no longer block re-join). UPDATE-first pattern replaces INSERT to avoid UNIQUE KEY collision on re-join |
| Org_Follow | p_OrgId, p_UserId | WRITE | Idempotent follow |
| Org_Unfollow | p_OrgId, p_UserId | WRITE | Soft-unfollow with FollowerCount decrement |
| Org_ReviewMembership | p_RequestId, p_StatusCode, p_AdminNotes, p_ReviewedBy | WRITE | APPROVED/REJECTED |
| Org_GetPendingMembers | p_OrgId, p_PageNumber, p_PageSize | LIST | Returns MembershipRequestId, ProfileVerificationStatusCode |
| Org_UpdateMemberPermissions | p_OrgId, p_MemberId, p_CanPost, p_CanComment, p_CanCommunityPost, p_MaxPostsPerDay, p_LocationSharingLkpId, p_UpdatedBy | WRITE | Granular member permissions |
| Org_UploadDocument | p_OrgId, p_UploadedBy, p_DocumentTypeLkpId, p_FileUrl, p_FileName | WRITE | |
| Org_GetDocuments | p_OrgId | LIST | Org documents with DocumentTypeCode, IsVerified |
| Org_GetAdminPosts | p_OrgId | LIST | All feed posts for org with ReportCount, StatusCode |
| Org_PinPost | p_PostId, p_OrgId, p_PinnedBy | WRITE | Toggle IsPinned |
| Org_DeletePost | p_PostId, p_OrgId, p_DeletedBy | WRITE | Soft-delete feed post |
| Org_ModeratePost | p_PostId, p_OrgId, p_ReviewedBy, p_Action | WRITE | KEEP / REMOVE reported post |
| Org_Resubmit | p_OrgId, p_UserId + 19 org fields | WRITE | Founder re-submit from REJECTED → PENDING |
| Org_CancelMembershipRequest | p_OrgId, p_UserId | WRITE | **v5.0 NEW** Soft-deletes PENDING OrgMembershipRequests row. Returns `IsSuccess=0` if no pending request found |
| **Org_Invite_Send** | p_OrgId, p_InvitedByUserId, p_InviteTypeCode, p_InviteValue, p_CountryCode, p_InviteToken, p_TokenExpiry, p_InviteBaseUrl | WRITE | **v5.0 NEW** Permission check + self-invite guard + duplicate check + INSERT into OrgInvitations. Returns IsSuccess, Message, InvitationId |
| **Org_Invite_VerifyToken** | p_Token | READ | **v5.0 NEW** Validates token, auto-expires lapsed tokens, marks OPENED, returns org + invite data |
| **Org_Invite_Accept** | p_InvitationId, p_UserId | WRITE | **v5.0 NEW** Direct join: inserts into OrgMembers with MEMBER role + APPROVED status (ON DUPLICATE KEY UPDATE for idempotency). Marks ACCEPTED. Notifies org admins (INVITE_ACCEPTED). Returns JoinType=DIRECT_JOINED |
| **Org_Invite_Cancel** | p_InvitationId, p_CancelledByUserId | WRITE | **v5.0 NEW** Admin cancels invite — marks CANCELLED |
| **Org_Invite_Decline** | p_InvitationId, p_UserId | WRITE | **v5.0 NEW** Invitee declines — verifies caller via Users.Mobile/Email match against InviteValue. Marks CANCELLED. Notifies org admins (INVITE_DECLINED). Distinct from Org_Invite_Cancel (admin-only) |
| **Org_Invite_Resend** | p_InvitationId, p_RequestedByUserId, p_NewToken, p_NewExpiry, p_InviteBaseUrl | WRITE | **v5.0 NEW** Refreshes token + expiry, resets to PENDING |
| **Org_Invite_List** | p_OrgId, p_RequestorId, p_StatusCode, p_PageNumber, p_PageSize | PAGED (Dynamic) | **v5.0 NEW** Paged invite list with invitee + inviter info. Auto-expires lapsed tokens on each call |
| **Org_Invite_GetPendingForUser** | p_UserId | LIST (Dynamic) | **v5.0 NEW** Matches by InvitedUserId = p_UserId OR phone/email string match. Returns pending invites for home screen banner |
| Campaign_ListPublicTrending | p_PageSize | LIST | Active donation campaigns ranked by IsEmergency → DonorCount → RaisedAmount |
| Org_GetDonationDashboard | p_OrgId | GET | 9 donation KPIs |
| Org_GetDonors | p_OrgId, p_Tab, p_PageNumber, p_PageSize | PAGED | Donor list; respects IsAnonymous |
| Org_GetTransactions | p_OrgId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | Transaction list |

### Project (17 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| Project_Create | 32 params | WRITE | Creates project + skills |
| Project_GetById | p_ProjectId, p_UserId | GET | **v5.0 UPDATED** Fixed two column alias bugs: (1) `ApprovedVolunteers` → `ApprovedCount` (matches mobile `approvedCount` field); (2) `MyApplicationStatusId` (raw LkpId integer) → `lv2.ValueCode AS ApplicationStatusCode` (string e.g. 'APPROVED'/'PENDING'). Date columns now returned as strings via `DATE_FORMAT(p.XXX, '%Y-%m-%d')` to prevent .NET DateTime serialisation timezone suffix |
| Project_Update | 32 params | WRITE | COALESCE partial update |
| Project_List | p_OrgId, p_Category, p_City, p_StatusCode, p_TypeCode, p_PageNumber, p_PageSize, p_UserLat, p_UserLon, p_Keyword | PAGED | **v5.0 UPDATED** 10 params. Added: `p_Keyword` (LIKE search on ProjectName, Description, OrgName, City, State, Landmark, AddressLine); public volunteer browse restricted to ACTIVE+UPCOMING only (whitelist); filters projects from non-APPROVED orgs out of public browse; TotalCount JOIN fixed; returns DistanceKm when coords provided |
| Project_AddSkill | p_ProjectId, p_SkillName, p_IsRequired | WRITE | |
| Project_AddSession | 6 params | WRITE | Duplicate guard per project+date |
| Project_GetSessions | p_ProjectId, p_PageNumber, p_PageSize | PAGED | SessionDate via DATE_FORMAT |
| Project_GetSessionQr | p_SessionId, p_UserId | GET | **v5.0 UPDATED** IST timezone fix: uses `CONVERT_TZ(NOW(), '+00:00', '+05:30')` for window comparisons. `QrExpiresAt` remains UTC for consistency with `Project_CheckIn` |
| Project_CheckIn | p_QrToken, p_UserId, p_SessionId | WRITE | |
| Project_Apply | p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions | WRITE | |
| Project_ReviewApplication | p_ApplicationId, p_StatusLkpId, p_RejectionReason, p_ReviewedBy | WRITE | |
| Project_Complete | p_ProjectId, p_OrgId, p_CompletedBy | WRITE | |
| Project_Cancel | p_ProjectId, p_UserId, p_CancelReason | WRITE | **v5.0 NEW** (was missing from all setup SQL files prior to v5.0; only existed in an outdated patch). Dynamically resolves CANCELLED LkpId. Guards: missing lookup, not-found project |
| Project_ManualAttendance | p_ApplicationId, p_MarkedBy | WRITE | **v5.0 UPDATED** Auto-creates a session if none exists (from Projects.OneTimeDate/RecurStart/FlexFromDate, SessionStartTime, SessionEndTime, MaxVolunteers). Enables retroactive attendance on completed projects where QR flow was never used |
| Project_GetNearbyFeed | p_UserId, p_UserLat, p_UserLon, p_PageNumber, p_PageSize | PAGED | **v5.0 UPDATED** Capacity-full exclusion (NULL-safe: `MaxVolunteers IS NULL OR MaxVolunteers = 0 OR approved_count < MaxVolunteers`). ORDER BY changed to pure distance (nearest first); RelevanceScore correlated subqueries removed |
| Project_GetApplications | p_ProjectId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | Alias for Application_GetByProject |
| **Project_GetSkillRatings** | p_ProjectId, p_UserId | LIST (Dynamic) | **v5.0 NEW** Returns all ProjectSkills for a project with the volunteer's existing rating (LEFT JOIN UserSkillRatings). Used by admin skill rating UI to pre-populate saved stars |

### Application (5 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| Application_Apply | p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions | WRITE | |
| Application_GetByProject | p_ProjectId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | **v5.0 UPDATED** Added `HasCertificate` (EXISTS subquery on VolunteerCertificates) and `AwardedBadgeCodes` (GROUP_CONCAT of BadgeLkpId ValueCodes awarded for this project). Also returns `CheckedInAt`, `HoursLogged`, `IsExcused`, `QrScannedAt`, `AdminNote`, `SessionDate`, `SessionStartTime`, `SessionEndTime` |
| Application_Review | p_ApplicationId, p_StatusLkpId, p_RejectionReason, p_ReviewedBy | WRITE | Returns ApplicantUserId, ProjectId for FCM |
| Application_GetByUser | p_UserId, p_PageNumber, p_PageSize | PAGED | **v5.0 UPDATED** Added `HoursLogged` (SUM from ProjectAttendance) and `HasCertificate` (EXISTS on VolunteerCertificates). Returns full schedule fields, ProjectStatusCode, ProjectStatus |
| **Application_Withdraw** | p_ApplicationId, p_UserId | WRITE | **v5.0 NEW** Validates PENDING status + ownership. For ONE_TIME/RECURRING: blocks if < 24h to start. FLEXIBLE: always allowed. Sets StatusLkpId → WITHDRAWN |

### Post / Feed (18 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| Post_Create | 6 params | WRITE | Permission gate (CanPost, MaxPostsPerDay). Auto-detects media type |
| Post_GetFeed | p_UserId, p_OrgId, p_PageNumber, p_PageSize | PAGED | Returns `IsLiked` (fixed from `IsLikedByMe`), IsFollowing, MediaUrls, MediaTypes, TimeAgo. Reported posts hidden from reporter |
| Post_GetPermissions | p_OrgId, p_UserId | GET | Returns IsMember, CanPost, MaxPostsPerDay, TodayPostCount, CanComment, CanCommunityPost |
| Post_GetById | p_PostId, p_UserId | GET | `IsLiked` alias fixed |
| Post_Delete | p_PostId, p_UserId | WRITE | Soft delete |
| Post_Pin | p_PostId, p_OrgId, p_PinnedBy | WRITE | Toggle IsPinned |
| Post_Like | p_PostId, p_UserId | WRITE | |
| Post_Unlike | p_PostId, p_UserId | WRITE | |
| Post_AddComment | p_PostId, p_UserId, p_Content, p_ParentCommentId | WRITE | CanComment permission gate |
| Post_GetComments | p_PostId, p_PageNumber, p_PageSize | PAGED | Nested comments |
| Post_Report | p_PostId, p_UserId, p_ReasonCode, p_Details | WRITE | p_ReasonCode VARCHAR(50); prevents duplicate reports |
| Post_Save | p_UserId, p_PostId | WRITE | Idempotent save; increments Posts.SaveCount |
| Post_Unsave | p_UserId, p_PostId | WRITE | Decrements Posts.SaveCount with GREATEST(n-1, 0) floor |
| **Post_GetSaved** | p_UserId, p_PageNumber, p_PageSize | PAGED (Dynamic) | **v5.0 NEW** Returns paginated saved posts ordered by ps.CreatedAt DESC (most recently saved first). Same columns as Feed_GetPersonalized plus `SavedAt`. Second result set: TotalCount |
| **Post_BulkNotifyOrgMembers** | p_PostId, p_OrgId, p_AuthorUserId | WRITE | **v5.0 NEW** Bulk-inserts Notifications rows for all approved org members (excluding author); NotifType=NEW_FEED_POST. Returns (UserId, Token, Platform, Title, Body) rows for FCM multicast dispatch. Title = "[AuthorName] posted in [OrgName]"; Body = first 100 chars |
| Feed_GetPersonalized | p_UserId, p_CursorPostId, p_CursorScore, p_PageSize | LIST (Dynamic) | **v5.0 UPDATED** ORDER BY changed to `CreatedAt DESC, PostId DESC` (was FeedScore DESC). Cursor now carries `UNIX_TIMESTAMP(CreatedAt)` of last seen post. FeedScore still computed and returned for analytics |
| Feed_TrackInteraction | p_UserId, p_PostId, p_InteractionType, p_DurationMs | WRITE | Fire-and-forget analytics insert |

### Community (9 SPs)
*(unchanged from v4.9)*

### SOS (12 SPs)
*(unchanged from v4.9)*

### Donation (14 SPs)
*(unchanged from v4.9)*

### Withdrawal (3 SPs)
*(unchanged from v4.9)*

### Certificate / Badge / Rating / Attendance (9 SPs)

| SP Name | Params | Type | Description |
|---|---|---|---|
| Certificate_GetByUser | p_UserId | LIST | **v5.0 UPDATED** References rebuilt VolunteerCertificates schema: `vc.CertCode`, `vc.OrgId`, `vc.TotalHours`, `vc.IsDeleted`. Fixed `p.ProjectName AS ProjectTitle` (was `p.Title`) |
| **Certificate_GetData** | p_CertCode | GET (Dynamic) | **v5.0 NEW** Full certificate data for verify page and app: volunteer, NGO, project, skills+ratings, impact score. AllowAnonymous endpoint |
| **Certificate_GetDataById** | p_CertificateId INT UNSIGNED | GET (Dynamic) | **v5.0 NEW** Same shape as Certificate_GetData but keyed by internal numeric CertificateId (for encrypted token verify flow — avoids exposing sequential CertCode in public URLs) |
| **Certificate_Issue** | p_ProjectId, p_UserId, p_OrgId, p_IssuedBy, p_TotalHours | WRITE | **v5.0 NEW** Generates CERT-YYYY-NNNNNN via IdSequences, inserts into VolunteerCertificates. Returns IsSuccess, Message, CertCode |
| User_GetBadges | p_UserId | LIST | **v5.0 UPDATED** Returns `lv.ValueCode AS BadgeCode`, `lv.ValueName AS BadgeName`, OrgName via AwardedByOrgId, ProjectName via ProjectId JOIN. Duplicate SP definition removed |
| UserBadge_Award | p_UserId, p_BadgeLkpId, p_AwardedBy, p_AwardedByOrgId, p_ProjectId | WRITE | **v5.0 UPDATED** Duplicate guard (same UserId + BadgeLkpId + ProjectId). Returns BadgeName (from LookupValues) + UserId for personalised FCM notification |
| SkillRating_AddOrUpdate | p_ApplicationId, p_ProjectSkillId, p_RatedUserId, p_Rating, p_OrgId, p_RatedBy, p_Notes | WRITE | **v5.0 UPDATED** Params match rebuilt UserSkillRatings schema. Upsert via UNIQUE KEY (UserId, ProjectId, SkillId) |
| Attendance_GetByProject | p_ProjectId, p_PageNumber, p_PageSize | PAGED | All attendance records for a project |
| Attendance_ExcuseNoShow | p_AttendanceId, p_ExcusedBy | WRITE | Returns UserId, ProjectId for FCM |

### Support (1 SP) *(v5.0 NEW)*

| SP Name | Params | Type | Description |
|---|---|---|---|
| **Support_LogContact** | p_UserId, p_CategoryCode, p_Subject, p_Description, p_ContactEmail, p_ContactName, p_AttachmentUrl, p_IpAddress | WRITE | Inserts into AuditLogs (Action=SUPPORT_CONTACT, EntityName=SupportContact, NewValue=JSON with all fields including attachmentUrl). Returns IsSuccess=1, Message='Your message has been sent…'. No new tables in Phase 1 |

### Notification (12 SPs)
*(unchanged from v4.9 — see v4.9 docs for full list)*

### Marketing & Communication Center (22 SPs) *(v5.0 NEW)*

| SP Name | Params | Type | Description |
|---|---|---|---|
| UserCommunicationPreference_Get | p_UserId | GET | Returns all 6 preference flags with defaults (all-enabled if no row yet) |
| UserCommunicationPreference_Update | p_UserId, 6 flag params | WRITE | UPSERT on UserId |
| Campaign_Create | p_CreatedBy, p_Title, p_Description, p_CampaignType, p_Priority, p_ScheduledAt | WRITE | Returns CampaignId |
| Campaign_Update | p_CampaignId, p_Title, p_Description, p_Priority, p_ScheduledAt | WRITE | DRAFT only — cannot edit ACTIVE/COMPLETED campaigns |
| Campaign_SetStatus | p_CampaignId, p_Status, p_UpdatedBy | WRITE | State machine transitions |
| CampaignChannel_Save | p_CampaignId, p_Channel, all payload fields | WRITE | Upsert per campaign+channel |
| CampaignChannel_Delete | p_CampaignId, p_Channel | WRITE | Remove channel |
| CampaignAudienceRule_Save | p_CampaignId, p_RuleType, p_RuleParams | WRITE | Upsert (one rule per campaign Phase 1) |
| Campaign_EstimateAudience | p_CampaignId | GET | Live COUNT for audience rule — sets EstimatedCount. Returns RecipientsCount |
| Campaign_ResolveRecipients | p_CampaignId | WRITE | Materialises audience into CampaignRecipients rows. Returns ResolvedCount |
| Campaign_GetQueuedRecipients | p_CampaignId, p_Channel, p_BatchSize | LIST | Returns PENDING recipients for dispatch: UserId, Email, Mobile, Token, PushTitle, PushBody, PushImageUrl, PushDeepLink, PushActionLabel, RecipientId |
| CampaignRecipient_MarkStatus | p_RecipientId, p_Status, p_FailReason | WRITE | Updates QueueStatus, SentAt |
| **CampaignRecipient_AckDelivered** | p_CampaignRecipientId, p_UserId | WRITE | **Device-side acknowledgment** — updates QueueStatus=DELIVERED + DeliveredAt. Ownership-checked but always reports IsSuccess=1 (best-effort beacon). Never downgrades FAILED/SKIPPED rows |
| CampaignRecipient_MarkEngagement | p_RecipientId, p_EngagementType | WRITE | Fire-and-forget engagement log (future open/click tracking) |
| CampaignQueueJob_Create | p_CampaignId, p_HangfireJobId | WRITE | Creates tracking row; returns JobId |
| CampaignQueueJob_MarkStatus | p_JobId, p_Status, p_SentCount, p_FailCount | WRITE | Updates job completion state |
| Campaign_GetList | p_CreatedBy, p_Status, p_PageNumber, p_PageSize | PAGED | Returns SentCount (Firebase accepted) + DeliveredCount (device ack) separately |
| Campaign_GetById | p_CampaignId | GET | Full campaign with channels, audience rule, estimated count |
| Campaign_GetHistoryDetail | p_CampaignId | GET | Delivery stats: SentCount, DeliveredCount split (honest metrics) |
| **Campaign_GetRecipientList** | p_CampaignId, p_Status, p_PageNumber, p_PageSize | PAGED | Per-recipient drill-down: name, email, mobile, channel, QueueStatus, SentAt, DeliveredAt, FailReason |
| Communication_GetDashboardStats | — | GET | Platform-wide campaign KPIs: TotalCampaigns, SentCount (accepted), DeliveredCount (ack-based) — split metrics |
| User_GetContactsByIds | p_UserIds (JSON array) | LIST | Returns UserId, Email, Mobile, FirstName, LastName for specific users — used by SPECIFIC_USERS audience rule |

### Super Admin (29 SPs)
*(unchanged from v4.9 — see v4.9 docs for full list)*

---

## LookupTypes (52 Types)

| TypeCode | Values / Notes |
|---|---|
| GENDER | Male, Female, Non-Binary, Prefer Not to Say |
| ORG_TYPE | Trust, Society, Section 8 Company, NGO, Foundation, Charitable Institution, Religious Trust, CSR Foundation, Educational Trust |
| ORG_STATUS | Pending Verification, Verified, Suspended, Rejected |
| USER_ROLE | Super Admin, NGO Admin, Volunteer, Donor, Beneficiary, Staff |
| ORG_MEMBER_ROLE | Admin, Staff, Member |
| MEMBER_APPROVAL | Pending, Approved, Rejected |
| LOCATION_SHARING | Always, During Activity, On Request, Never |
| PROJECT_TYPE | Education, Healthcare, Environment, Animal Welfare, Disaster Relief, Women Empowerment, Child Welfare, Elderly Care, Poverty Alleviation, Arts & Culture |
| PROJECT_STATUS | Draft, Active, Completed, Cancelled, Paused, Expired |
| JOIN_TYPE | Open, Requires Approval, Invite Only |
| LOCATION_TYPE | In-Person, Online, Hybrid |
| APPLICATION_STATUS | Pending, Approved, Rejected, Waitlisted, Withdrawn |
| ATTENDANCE_STATUS | Attended, No Show, Excused |
| SESSION_STATUS | Upcoming, Active, Completed, Cancelled |
| ATTENDANCE_METHOD | QR Scan, Manual, GPS |
| BADGE_TYPE | First Volunteer, 10 Hours, 50 Hours, 100 Hours, 500 Hours, Mentor, Top Donor, SOS Hero, Community Leader, Impact Champion |
| EDUCATION | Below 10th, 10th Pass, 12th Pass, Diploma, Graduate, Post Graduate, Doctorate |
| WORK_EXPERIENCE | Fresher, 1-2 Years, 3-5 Years, 6-10 Years, 10+ Years |
| INTEREST_TYPE | Education, Healthcare, Environment, Sports, Arts, Technology, Community, Animal Welfare |
| DOCUMENT_TYPE_USER | Photo ID (PHOTO_ID), Address Proof (ADDR_PROOF), Passport (PASSPORT), Driving License (DRIVING_LIC), Other (OTHER) |
| DOC_TYPE_ORG | Registration Certificate, 80G Certificate, 12A Certificate, FCRA Certificate, CSR Policy, Annual Report |
| POST_TYPE_FEED | Update, Announcement, Opportunity, Story, Article |
| POST_VISIBILITY | Public, Followers, Organisation Members, Private |
| POST_TYPE_COMMUNITY | Discussion, Question, Announcement, Resource, Event, Achievement |
| REPORT_REASON | Spam, Inappropriate Content, Misleading, Hate Speech, Harassment, Other |
| REPORT_STATUS | PENDING, REVIEWED, RESOLVED |
| MEDIA_TYPE | IMAGE, VIDEO, Document, Audio |
| SOS_ALERT_TYPE | SOS Emergency, Help Request, Missing Volunteer, Safe Arrival |
| SOS_STATUS | Active, Resolved, Cancelled |
| SOS_APPROVAL | Pending, Approved, Rejected |
| SOS_RESOLUTION | Self Resolved, Helped By Volunteer, Emergency Services, False Alarm |
| OTP_PURPOSE | LOGIN, MOBILE_CHANGE, EMAIL_CHANGE, PASSWORD_RESET, ADD_PHONE, ADD_EMAIL |
| CAMPAIGN_TYPE | General, Project Specific, Emergency, Recurring *(donation module — CAMPAIGN_TYPE)* |
| CAMPAIGN_STATUS | Draft, Active, Completed, Suspended, Archived *(donation module)* |
| PAYMENT_METHOD | UPI, Credit/Debit Card, Net Banking, Wallet, NEFT/RTGS |
| PAYMENT_STATUS | Pending, Completed, Failed, Refunded |
| RECURRING_FREQUENCY | Weekly, Monthly, Quarterly, Yearly |
| WITHDRAWAL_STATUS | Pending, Under Review, Approved, Rejected, Processed |
| NOTIFICATION_TYPE | Project Update, New Application, SOS Alert, Donation Received, Badge Earned, New Follower, Comment, Mention, System |
| RECEIPT_TYPE | 80G, General, CSR |
| CERTIFICATE_TYPE | Volunteer Completion, Skills Assessment, Training, Achievement |
| SETTING_DATA_TYPE | String, Number, Boolean, URL, JSON |
| BENEFICIARY_TYPE | Individual, Family, Community, Institution |
| LANGUAGE | English, Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, Gujarati |
| COUNTRY | India, USA, UK, Canada, Australia, UAE, Singapore, Germany |
| PROFILE_VERIFICATION_STATUS | PENDING (Not Reviewed), VERIFIED, NEEDS_UPDATE, REJECTED |
| ORG_VERIFICATION_STATUS | PENDING, VERIFIED, REJECTED |
| AUDIENCE_TYPE | ALL_MEMBERS, etc. |
| **INVITE_TYPE** | PHONE, EMAIL *(v5.0 NEW)* |
| **INVITE_STATUS** | PENDING, OPENED, ACCEPTED, CANCELLED, EXPIRED *(v5.0 NEW)* |
| **MKTG_CAMPAIGN_TYPE** | PROMOTIONAL, ENGAGEMENT, ANNOUNCEMENT, VOLUNTEER_DRIVE, FUNDRAISING *(v5.0 NEW — MKTG_ prefix avoids collision with donation CAMPAIGN_TYPE)* |
| **MKTG_CAMPAIGN_PRIORITY** | LOW, NORMAL, HIGH, URGENT *(v5.0 NEW)* |
| **MKTG_CAMPAIGN_STATUS** | DRAFT, SCHEDULED, RUNNING, COMPLETED, FAILED, CANCELLED *(v5.0 NEW)* |
| **MKTG_CAMPAIGN_CHANNEL** | PUSH, EMAIL, SMS, WHATSAPP *(v5.0 NEW — WhatsApp seeded as inert value, enabled in future phase)* |

---

## IdSequences — Readable IDs

| PrefixCode | Format | Example | Padding |
|---|---|---|---|
| DON | DON-{YYYY}-{NNNNNN} | DON-2026-000001 | 6 digits |
| WDR | WDR-{YYYY}-{NNNN} | WDR-2026-0001 | 4 digits |
| REC | REC-{YYYY}-{NNNN} | REC-2026-0001 | 4 digits |
| **CERT** | CERT-{YYYY}-{NNNNNN} | CERT-2026-000001 | 6 digits — *(v5.0 NEW)* |

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| BIGINT on AuditLogs, SosLocationLogs, Notifications, CampaignRecipients, CampaignQueueJobs | Volume overflow risk at scale |
| Soft delete on all master tables | Audit trail, dispute resolution, compliance |
| LookupTypes + LookupValues for all category columns | No redeploy on label/category changes |
| Settings table for all platform config | No redeploy on config changes |
| SettingsCache singleton | Zero DB calls for config reads |
| DynamicRow for display/dashboard/feed SPs | SP column change = zero C# change |
| DataReader for large/frequent lists | 2-5× faster, lower memory than DataSet |
| Denormalized counts (LikeCount, MemberCount) | No COUNT() on hot read paths |
| IsPublic flag on Settings | Secrets never exposed to frontend |
| SuperAdmin module fully isolated | Zero blast radius to mobile/NGO-admin SPs |
| OrgStatusHistory written by SP on every transition | Immutable audit trail for org lifecycle |
| MKTG_ prefix on campaign lookups | Avoids TypeCode collision with donation module's CAMPAIGN_TYPE/CAMPAIGN_STATUS |
| CampaignRecipient BIGINT PK | High-volume — could reach millions at scale |
| SentCount ≠ DeliveredCount | `SentCount` = Firebase accepted; `DeliveredCount` = device-side ack via POST /campaign-recipients/{id}/delivered. Previously mislabeled — now honestly split |
| Invite direct-join (no approval step) | Invitation IS the approval — inserts directly to OrgMembers with APPROVED status |
| Certificate verify via encrypted token, not raw CertCode | CertCode (CERT-YYYY-NNNNNN) is a sequential counter — enumerable. AES-256-GCM token (via IUrlTokenService) prevents walking the sequence to harvest volunteer data |
| Project_List approved-orgs filter | Public volunteer browse silently hides projects from SUSPENDED/PENDING/REJECTED orgs |
| NULL-safe MaxVolunteers capacity check | `MaxVolunteers IS NULL OR MaxVolunteers = 0 OR count < MaxVolunteers` — MySQL NULL comparison returns UNKNOWN, not FALSE |
| UserBadges schema rebuild | Old schema (BadgeType VARCHAR, AwardedByUserId NOT NULL) caused "Unknown column" crashes across multiple SPs. Rebuilt to FK→LookupValues pattern |
| UserSkillRatings schema rebuild | Old schema referenced UserSkills.UserSkillId; new schema references ProjectSkills.ProjectSkillId — skills are now rated per-project, not per user-skill globally |

---

*Database_Documentation_v5.0.md — 62 Tables, 52 LookupTypes, 204 Stored Procedures — Last updated 2026-08-05*

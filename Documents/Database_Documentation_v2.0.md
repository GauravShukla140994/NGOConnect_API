# NGO Connect — Database Documentation Register
**Version:** v2.0
**Date:** 24-Jun-2026
**Database:** MySQL 8.0+
**Charset:** utf8mb4 / utf8mb4_unicode_ci

---

## Version History

| Version | Date        | Change Description |
|---------|-------------|--------------------|
| v1.0    | 24-Jun-2026 | Initial — Auth + User groups (5 tables, 12 SPs) |
| v2.0    | 24-Jun-2026 | Added all new modules: Settings, Organisations, Projects, Applications, Posts/Feed, Community/Polls, Donations, SOS, Notifications (22 new tables, 52 new SPs; total: 27 tables, 64 SPs) |

---

## Table of Contents

1. [Database Design Principles](#1-database-design-principles)
2. [Tables — Group 1: Auth](#2-group-1-auth)
3. [Tables — Group 2: User Profiles](#3-group-2-user-profiles)
4. [Tables — Group 3: Settings](#4-group-3-settings)
5. [Tables — Group 4: Organisations](#5-group-4-organisations)
6. [Tables — Group 5: Projects](#6-group-5-projects)
7. [Tables — Group 6: Content / Feed](#7-group-6-content--feed)
8. [Tables — Group 7: Community / Polls](#8-group-7-community--polls)
9. [Tables — Group 8: Donations](#9-group-8-donations)
10. [Tables — Group 9: SOS / Safety](#10-group-9-sos--safety)
11. [Tables — Group 10: Notifications](#11-group-10-notifications)
12. [Stored Procedures — Auth Module](#12-stored-procedures--auth-module)
13. [Stored Procedures — User Module](#13-stored-procedures--user-module)
14. [Stored Procedures — Settings Module](#14-stored-procedures--settings-module)
15. [Stored Procedures — Organisation Module](#15-stored-procedures--organisation-module)
16. [Stored Procedures — Projects Module](#16-stored-procedures--projects-module)
17. [Stored Procedures — Applications Module](#17-stored-procedures--applications-module)
18. [Stored Procedures — Posts Module](#18-stored-procedures--posts-module)
19. [Stored Procedures — Community Module](#19-stored-procedures--community-module)
20. [Stored Procedures — Donations Module](#20-stored-procedures--donations-module)
21. [Stored Procedures — SOS Module](#21-stored-procedures--sos-module)
22. [Stored Procedures — Notifications Module](#22-stored-procedures--notifications-module)
23. [Relationships Diagram](#23-relationships-diagram)
24. [SP Summary Index](#24-sp-summary-index)
25. [Change Management Rules](#25-change-management-rules)

---

## 1. Database Design Principles

| Principle | Rule |
|-----------|------|
| **Primary Keys** | `INT UNSIGNED AUTO_INCREMENT` for standard tables. `BIGINT UNSIGNED` for high-volume append-only tables (AuditLogs, Notifications, SosLocationLogs). |
| **Soft Delete** | All master tables carry `IsDeleted TINYINT(1)`, `DeletedAt DATETIME`, `DeletedBy INT UNSIGNED`. Never hard-delete. |
| **Naming** | PascalCase for tables and columns. Prefix `p_` for SP parameters. SP naming: `{Module}_{Action}`. |
| **SP Returns — WRITE** | All WRITE SPs return: `IsSuccess INT, Message VARCHAR, [EntityId INT]`. |
| **SP Returns — LIST** | Paged list SPs return two result sets: data rows + `SELECT COUNT(*) AS TotalCount`. |
| **Charset** | `utf8mb4` on all tables — supports multilingual content and emoji. |
| **Indexes** | Every FK column and every filtered/sorted column must be indexed. |
| **Lookups** | All category columns use `INT UNSIGNED FK → LookupValues`. Never TINYINT enums. |
| **Timestamps** | `CreatedAt = DEFAULT CURRENT_TIMESTAMP`. `UpdatedAt` set by SP on every write. |
| **Readable IDs** | Donations use `DON-YYYY-000001` format via `IdSequences` table. |
| **Denormalized Counts** | `Posts.LikeCount`, `DonationCampaigns.RaisedAmount` maintained by SP — no COUNT() on hot read paths. |
| **Config** | All platform configuration in `Settings` table. Loaded into singleton `SettingsCache` at startup. Zero DB reads for config. |

---

## 2. Group 1: Auth

**Script File:** `Database/01_Tables_Auth_User.sql`

### 2.1 Users

Core authentication table. One row per registered user.

| Column       | Type         | Nullable | Default           | Description |
|--------------|--------------|----------|-------------------|-------------|
| UserId       | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| MobileNumber | VARCHAR(15)  | No       | —                 | Registered mobile |
| CountryCode  | VARCHAR(5)   | No       | `+91`             | Dialing code |
| Email        | VARCHAR(255) | Yes      | NULL              | Email (optional) |
| RoleLkpId    | INT UNSIGNED | No       | —                 | FK → LookupValues (USER_ROLE) |
| IsActive     | TINYINT(1)   | No       | 1                 | Account active flag |
| IsVerified   | TINYINT(1)   | No       | 0                 | Set to 1 after first OTP |
| IsDeleted    | TINYINT(1)   | No       | 0                 | Soft delete |
| DeletedAt    | DATETIME     | Yes      | NULL              | — |
| DeletedBy    | INT UNSIGNED | Yes      | NULL              | — |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP | — |
| UpdatedAt    | DATETIME     | Yes      | NULL              | Set by SP |

**Indexes:** `uq_mobile_country (MobileNumber, CountryCode)`, `uq_email (Email)`

---

### 2.2 OtpTokens

Stores OTP codes. Never deleted — kept for audit trail.

| Column       | Type         | Nullable | Default           | Description |
|--------------|--------------|----------|-------------------|-------------|
| OtpTokenId   | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| UserId       | INT UNSIGNED | Yes      | NULL              | NULL for unregistered users |
| Recipient    | VARCHAR(255) | No       | —                 | Mobile or email |
| CountryCode  | VARCHAR(5)   | No       | `+91`             | — |
| OtpCode      | VARCHAR(6)   | No       | —                 | 6-digit OTP |
| PurposeLkpId | INT UNSIGNED | No       | —                 | FK → LookupValues (OTP_PURPOSE) |
| AttemptCount | TINYINT      | No       | 0                 | Max 3 wrong attempts |
| IsUsed       | TINYINT(1)   | No       | 0                 | 1 = used/expired |
| IpAddress    | VARCHAR(45)  | Yes      | NULL              | IPv4/IPv6 |
| ExpiresAt    | DATETIME     | No       | —                 | now + 10 min |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP | — |

**Business Rules:** Max 3 OTPs per 10 min per Recipient+Purpose. Max 3 wrong attempts before lock.

---

### 2.3 RefreshTokens

Hashed refresh tokens for session management. Max 5 active sessions per user.

| Column         | Type         | Nullable | Default           | Description |
|----------------|--------------|----------|-------------------|-------------|
| RefreshTokenId | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| UserId         | INT UNSIGNED | No       | —                 | FK → Users |
| Token          | VARCHAR(512) | No       | —                 | SHA-256 hash — never plain text |
| DeviceInfo     | VARCHAR(500) | Yes      | NULL              | Device identifier |
| IpAddress      | VARCHAR(45)  | Yes      | NULL              | IP at creation |
| IsRevoked      | TINYINT(1)   | No       | 0                 | 1 = logged out |
| ExpiresAt      | DATETIME     | No       | —                 | now + 30 days |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP | — |

**Business Rules:** Token rotated on every use. Oldest session auto-revoked when > 5 active.

---

## 3. Group 2: User Profiles

**Script File:** `Database/01_Tables_Auth_User.sql`

### 3.1 UserProfiles

Extended profile per user. Created (empty) at first OTP verification.

| Column          | Type         | Nullable | Default | Description |
|-----------------|--------------|----------|---------|-------------|
| UserProfileId   | INT UNSIGNED | No       | AUTO_INCREMENT | PK |
| UserId          | INT UNSIGNED | No       | —       | FK → Users (UNIQUE) |
| FirstName       | VARCHAR(100) | Yes      | NULL    | — |
| LastName        | VARCHAR(100) | Yes      | NULL    | — |
| DisplayName     | VARCHAR(200) | Yes      | NULL    | Shown in UI |
| About           | TEXT         | Yes      | NULL    | Bio |
| GenderLkpId     | INT UNSIGNED | Yes      | NULL    | FK → LookupValues (GENDER) |
| DateOfBirth     | DATE         | Yes      | NULL    | — |
| ProfilePhotoUrl | VARCHAR(500) | Yes      | NULL    | Azure Blob URL |
| City            | VARCHAR(100) | Yes      | NULL    | — |
| State           | VARCHAR(100) | Yes      | NULL    | — |
| Country         | VARCHAR(100) | Yes      | `India` | — |
| LinkedInUrl     | VARCHAR(500) | Yes      | NULL    | — |
| WebsiteUrl      | VARCHAR(500) | Yes      | NULL    | — |
| CreatedAt       | DATETIME     | No       | CURRENT_TIMESTAMP | — |
| UpdatedAt       | DATETIME     | Yes      | NULL    | Set by SP |

---

### 3.2 UserSkills

Skills tagged to a user's profile. Upsert pattern — updates proficiency if skill re-added.

| Column           | Type         | Nullable | Description |
|------------------|--------------|----------|-------------|
| UserSkillId      | INT UNSIGNED | No       | PK |
| UserId           | INT UNSIGNED | No       | FK → Users |
| SkillLkpId       | INT UNSIGNED | No       | FK → LookupValues (SKILL) |
| ProficiencyLkpId | INT UNSIGNED | No       | FK → LookupValues (SKILL_PROFICIENCY) |
| CreatedAt        | DATETIME     | No       | — |

**Unique:** `(UserId, SkillLkpId)` — one proficiency per skill per user.

---

## 4. Group 3: Settings

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 4.1 Settings

All platform configuration. Loaded into `SettingsCache` singleton at startup. Zero DB reads for config after boot.

| Column       | Type         | Nullable | Default | Description |
|--------------|--------------|----------|---------|-------------|
| SettingId    | INT UNSIGNED | No       | AUTO_INCREMENT | PK |
| SettingGroup | VARCHAR(50)  | No       | —       | Category: OTP, AUTH, PAGINATION, FEATURE, DONATION, UPLOAD, PLATFORM |
| SettingKey   | VARCHAR(100) | No       | —       | Unique machine-readable key e.g. `OTP_EXPIRY_MINUTES` |
| SettingValue | TEXT         | No       | —       | The value |
| DataType     | VARCHAR(20)  | No       | STRING  | STRING, NUMBER, BOOLEAN, URL, JSON |
| Description  | VARCHAR(500) | Yes      | NULL    | Human-readable purpose |
| IsPublic     | TINYINT(1)   | No       | 0       | 1 = safe to expose via `/api/v1/settings/public`. 0 = server-side only |
| IsDeleted    | TINYINT(1)   | No       | 0       | Soft delete |
| UpdatedAt    | DATETIME     | Yes      | NULL    | Set by SP |
| UpdatedBy    | INT UNSIGNED | Yes      | NULL    | Admin UserId |

**Unique:** `SettingKey`

**Key Business Rule:** `IsPublic=0` settings (Razorpay secret, JWT key, etc.) are NEVER returned to any frontend API. Only `Settings_GetPublic` returns `IsPublic=1` rows.

**Seed Data (15 rows):**

| SettingGroup | SettingKey | Value | IsPublic |
|---|---|---|---|
| OTP | OTP_EXPIRY_MINUTES | 10 | 0 |
| OTP | OTP_MAX_ATTEMPTS | 3 | 0 |
| OTP | OTP_RATE_LIMIT | 3 | 0 |
| AUTH | JWT_EXPIRY_MINUTES | 15 | 0 |
| AUTH | REFRESH_EXPIRY_DAYS | 30 | 0 |
| AUTH | MAX_SESSIONS | 5 | 0 |
| PAGINATION | DEFAULT_PAGE_SIZE | 20 | 1 |
| PAGINATION | MAX_PAGE_SIZE | 100 | 1 |
| PLATFORM | APP_NAME | NGO Connect | 1 |
| PLATFORM | SUPPORT_EMAIL | support@ngoconnect.app | 1 |
| FEATURE | SOS_ENABLED | true | 0 |
| FEATURE | DONATIONS_ENABLED | true | 0 |
| DONATION | MIN_DONATION_AMOUNT | 10 | 1 |
| DONATION | RAZORPAY_KEY_ID | rzp_test_xxxx | 1 |
| UPLOAD | MAX_FILE_SIZE_MB | 10 | 1 |

---

## 5. Group 4: Organisations

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 5.1 Organisations

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| OrgId         | INT UNSIGNED | No       | PK AUTO_INCREMENT |
| OrgName       | VARCHAR(200) | No       | Display name |
| RegistrationNo| VARCHAR(100) | Yes      | Govt registration number (unique if provided) |
| About         | TEXT         | Yes      | Description |
| Website       | VARCHAR(255) | Yes      | — |
| Phone         | VARCHAR(20)  | Yes      | — |
| Email         | VARCHAR(150) | Yes      | — |
| City          | VARCHAR(100) | Yes      | — |
| State         | VARCHAR(100) | Yes      | — |
| Country       | VARCHAR(100) | No       | Default: India |
| LogoUrl       | VARCHAR(500) | Yes      | Azure Blob URL |
| OrgTypeId     | INT UNSIGNED | Yes      | FK → LookupValues (ORG_TYPE) |
| IsVerified    | TINYINT(1)   | No       | 0 — Set by admin after document verification |
| IsDeleted     | TINYINT(1)   | No       | 0 |
| DeletedAt     | DATETIME     | Yes      | — |
| DeletedBy     | INT UNSIGNED | Yes      | — |
| CreatedBy     | INT UNSIGNED | No       | UserId of registrant |
| CreatedAt     | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt     | DATETIME     | Yes      | — |
| UpdatedBy     | INT UNSIGNED | Yes      | — |

---

### 5.2 OrgMembers

Members of an organisation with their roles.

| Column      | Type         | Nullable | Description |
|-------------|--------------|----------|-------------|
| OrgMemberId | INT UNSIGNED | No       | PK |
| OrgId       | INT UNSIGNED | No       | FK → Organisations |
| UserId      | INT UNSIGNED | No       | FK → Users |
| Role        | VARCHAR(20)  | No       | ADMIN / STAFF / MEMBER |
| JoinedAt    | DATETIME     | No       | — |
| IsDeleted   | TINYINT(1)   | No       | 0 |
| DeletedAt   | DATETIME     | Yes      | — |
| DeletedBy   | INT UNSIGNED | Yes      | — |
| CreatedBy   | INT UNSIGNED | Yes      | Admin who added the member |

**Unique:** `(OrgId, UserId)` — one role per member per org.

**Business Rule:** Registering user is auto-added as `ADMIN`. Only ADMIN can add/remove members.

---

## 6. Group 5: Projects

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 6.1 Projects

Volunteer engagement projects created by organisations.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| ProjectId    | INT UNSIGNED | No       | PK |
| OrgId        | INT UNSIGNED | No       | FK → Organisations |
| Title        | VARCHAR(300) | No       | — |
| Description  | TEXT         | Yes      | — |
| City         | VARCHAR(100) | Yes      | — |
| State        | VARCHAR(100) | Yes      | — |
| Status       | VARCHAR(20)  | No       | OPEN / CLOSED / COMPLETED / CANCELLED |
| StartDate    | DATE         | No       | — |
| EndDate      | DATE         | Yes      | — |
| MaxVolunteers| INT          | No       | 0 = unlimited |
| IsDeleted    | TINYINT(1)   | No       | 0 |
| CreatedBy    | INT UNSIGNED | No       | — |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt    | DATETIME     | Yes      | — |
| UpdatedBy    | INT UNSIGNED | Yes      | — |

---

### 6.2 ProjectSessions

Scheduled attendance sessions within a project. Each session has a unique QR token.

| Column      | Type         | Nullable | Description |
|-------------|--------------|----------|-------------|
| SessionId   | INT UNSIGNED | No       | PK |
| ProjectId   | INT UNSIGNED | No       | FK → Projects |
| Title       | VARCHAR(200) | No       | — |
| SessionDate | DATETIME     | No       | — |
| Location    | VARCHAR(300) | Yes      | — |
| QrCode      | VARCHAR(512) | No       | SHA-256 token. Volunteer scans to check in. |
| IsActive    | TINYINT(1)   | No       | 1 = QR active. 0 = QR expired/closed. |
| IsDeleted   | TINYINT(1)   | No       | 0 |
| CreatedBy   | INT UNSIGNED | No       | — |
| CreatedAt   | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 6.3 ProjectApplications

Volunteer applications to projects.

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| ApplicationId | INT UNSIGNED | No       | PK |
| ProjectId     | INT UNSIGNED | No       | FK → Projects |
| UserId        | INT UNSIGNED | No       | FK → Users (applicant) |
| Status        | VARCHAR(20)  | No       | PENDING / APPROVED / REJECTED |
| Note          | TEXT         | Yes      | Applicant note / reviewer note |
| ReviewedBy    | INT UNSIGNED | Yes      | UserId of org staff who reviewed |
| ReviewedAt    | DATETIME     | Yes      | — |
| AppliedAt     | DATETIME     | No       | CURRENT_TIMESTAMP |
| IsDeleted     | TINYINT(1)   | No       | 0 |

**Unique:** `(ProjectId, UserId)` — one application per volunteer per project.

---

### 6.4 ProjectAttendance

QR scan check-in records per session.

| Column      | Type         | Nullable | Description |
|-------------|--------------|----------|-------------|
| AttendanceId| INT UNSIGNED | No       | PK |
| ProjectId   | INT UNSIGNED | No       | FK → Projects |
| SessionId   | INT UNSIGNED | No       | FK → ProjectSessions |
| UserId      | INT UNSIGNED | No       | FK → Users |
| CheckInAt   | DATETIME     | No       | — |

**Unique:** `(SessionId, UserId)` — one check-in per volunteer per session.

---

## 7. Group 6: Content / Feed

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 7.1 Posts

Main social feed posts.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| PostId       | INT UNSIGNED | No       | PK |
| UserId       | INT UNSIGNED | No       | FK → Users (author) |
| OrgId        | INT UNSIGNED | Yes      | FK → Organisations (if posted as org) |
| Content      | TEXT         | No       | Post body |
| PostType     | VARCHAR(20)  | No       | GENERAL / UPDATE / IMPACT / CAMPAIGN |
| LikeCount    | INT          | No       | 0 — Denormalized. Updated by SP on like/unlike. |
| CommentCount | INT          | No       | 0 — Denormalized. Updated by SP on add comment. |
| IsDeleted    | TINYINT(1)   | No       | 0 |
| DeletedAt    | DATETIME     | Yes      | — |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP |

**Index:** `(CreatedAt DESC)` — used in feed ORDER BY.

---

### 7.2 PostMedia

Media URLs attached to posts. One-to-many.

| Column     | Type         | Nullable | Description |
|------------|--------------|----------|-------------|
| PostMediaId| INT UNSIGNED | No       | PK |
| PostId     | INT UNSIGNED | No       | FK → Posts |
| MediaUrl   | VARCHAR(500) | No       | Azure Blob URL |
| CreatedAt  | DATETIME     | No       | — |

---

### 7.3 PostLikes

Tracks which users liked which posts.

| Column    | Type         | Nullable | Description |
|-----------|--------------|----------|-------------|
| PostLikeId| INT UNSIGNED | No       | PK |
| PostId    | INT UNSIGNED | No       | FK → Posts |
| UserId    | INT UNSIGNED | No       | FK → Users |
| CreatedAt | DATETIME     | No       | — |

**Unique:** `(PostId, UserId)` — one like per user per post.

---

### 7.4 PostComments

Comments on posts. Supports nested replies via `ParentCommentId`.

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| CommentId      | INT UNSIGNED | No       | PK |
| PostId         | INT UNSIGNED | No       | FK → Posts |
| UserId         | INT UNSIGNED | No       | FK → Users |
| ParentCommentId| INT UNSIGNED | Yes      | NULL = top-level. Set for replies. |
| Content        | TEXT         | No       | — |
| IsDeleted      | TINYINT(1)   | No       | 0 |
| DeletedAt      | DATETIME     | Yes      | — |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 7.5 PostReports

User reports on posts (for moderation).

| Column   | Type         | Nullable | Description |
|----------|--------------|----------|-------------|
| ReportId | INT UNSIGNED | No       | PK |
| PostId   | INT UNSIGNED | No       | FK → Posts |
| UserId   | INT UNSIGNED | No       | FK → Users (reporter) |
| Reason   | TEXT         | No       | Report reason |
| Status   | VARCHAR(20)  | No       | PENDING / REVIEWED / ACTIONED |
| CreatedAt| DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(PostId, UserId)` — one report per user per post.

---

## 8. Group 7: Community / Polls

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 8.1 CommunityPosts

Discussion board posts. Posts with `IsPoll=1` are linked to `PollOptions`.

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| CommunityPostId| INT UNSIGNED | No       | PK |
| UserId         | INT UNSIGNED | No       | FK → Users |
| OrgId          | INT UNSIGNED | Yes      | FK → Organisations |
| Content        | TEXT         | No       | Post body or poll question |
| Tags           | VARCHAR(500) | Yes      | Comma-separated topic tags |
| IsPoll         | TINYINT(1)   | No       | 0 = post, 1 = poll |
| ExpiresAt      | DATETIME     | Yes      | Poll expiry. NULL for regular posts. |
| IsDeleted      | TINYINT(1)   | No       | 0 |
| DeletedAt      | DATETIME     | Yes      | — |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 8.2 PollOptions

Options within a poll. `VoteCount` is denormalized — updated by `Community_Vote`.

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| PollOptionId   | INT UNSIGNED | No       | PK |
| CommunityPostId| INT UNSIGNED | No       | FK → CommunityPosts |
| OptionText     | VARCHAR(200) | No       | Display text |
| VoteCount      | INT          | No       | 0 — Denormalized |
| SortOrder      | INT          | No       | Display order |

---

### 8.3 PollVotes

Records which user voted on which option. Prevents double-voting at DB level.

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| PollVoteId     | INT UNSIGNED | No       | PK |
| CommunityPostId| INT UNSIGNED | No       | FK → CommunityPosts |
| PollOptionId   | INT UNSIGNED | No       | FK → PollOptions |
| UserId         | INT UNSIGNED | No       | FK → Users |
| VotedAt        | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(CommunityPostId, UserId)` — one vote per user per poll.

---

## 9. Group 8: Donations

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 9.1 DonationCampaigns

Fundraising campaigns created by organisations.

| Column       | Type          | Nullable | Description |
|--------------|---------------|----------|-------------|
| CampaignId   | INT UNSIGNED  | No       | PK |
| OrgId        | INT UNSIGNED  | No       | FK → Organisations |
| Title        | VARCHAR(300)  | No       | — |
| Description  | TEXT          | Yes      | — |
| GoalAmount   | DECIMAL(12,2) | No       | Target in INR |
| RaisedAmount | DECIMAL(12,2) | No       | 0 — Denormalized. Updated by `Donation_VerifyPayment`. |
| EndDate      | DATE          | No       | Campaign end date |
| BannerUrl    | VARCHAR(500)  | Yes      | Azure Blob URL |
| Status       | VARCHAR(20)   | No       | ACTIVE / COMPLETED / CLOSED |
| IsDeleted    | TINYINT(1)    | No       | 0 |
| CreatedBy    | INT UNSIGNED  | No       | — |
| CreatedAt    | DATETIME      | No       | CURRENT_TIMESTAMP |
| UpdatedAt    | DATETIME      | Yes      | — |

---

### 9.2 DonationTransactions

Individual donation payment records.

| Column              | Type          | Nullable | Description |
|---------------------|---------------|----------|-------------|
| TransactionId       | INT UNSIGNED  | No       | PK |
| UserId              | INT UNSIGNED  | No       | FK → Users |
| CampaignId          | INT UNSIGNED  | No       | FK → DonationCampaigns |
| Amount              | DECIMAL(10,2) | No       | In INR |
| DonationRef         | VARCHAR(20)   | No       | UNIQUE. Human-readable: `DON-2026-000001` |
| RazorpayOrderId     | VARCHAR(100)  | Yes      | Set at initiate |
| RazorpayPaymentId   | VARCHAR(100)  | Yes      | Set at verify |
| RazorpaySignature   | VARCHAR(256)  | Yes      | HMAC-SHA256 for verification |
| Status              | VARCHAR(20)   | No       | PENDING / COMPLETED / FAILED |
| IsAnonymous         | TINYINT(1)    | No       | 0 — Hides donor name in public leaderboards |
| Note                | TEXT          | Yes      | Donor message |
| CreatedAt           | DATETIME      | No       | CURRENT_TIMESTAMP |
| CompletedAt         | DATETIME      | Yes      | Set by `Donation_VerifyPayment` |

**Sequence Pattern:** `DON-YYYY-NNNNNN` generated via `IdSequences` table. No gaps, no duplicates.

---

### 9.3 RecurringDonations

Scheduled recurring donation setups. Processed by Hangfire background job.

| Column      | Type          | Nullable | Description |
|-------------|---------------|----------|-------------|
| RecurringId | INT UNSIGNED  | No       | PK |
| UserId      | INT UNSIGNED  | No       | FK → Users |
| CampaignId  | INT UNSIGNED  | No       | FK → DonationCampaigns |
| Amount      | DECIMAL(10,2) | No       | — |
| Frequency   | VARCHAR(20)   | No       | WEEKLY / MONTHLY / YEARLY |
| Status      | VARCHAR(20)   | No       | ACTIVE / PAUSED / CANCELLED |
| Note        | TEXT          | Yes      | — |
| NextRunAt   | DATETIME      | No       | Next scheduled charge date |
| CreatedAt   | DATETIME      | No       | CURRENT_TIMESTAMP |
| UpdatedAt   | DATETIME      | Yes      | — |

**Index:** `(Status, NextRunAt)` — used by Hangfire job to find due recurring donations.

---

### 9.4 IdSequences

Sequence counter table for human-readable IDs.

| Column | Type        | Description |
|--------|-------------|-------------|
| SeqKey | VARCHAR(20) | PK e.g. `DON-2026` |
| LastVal| INT UNSIGNED| Auto-incremented by SP using `ON DUPLICATE KEY UPDATE` |

---

## 10. Group 9: SOS / Safety

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 10.1 SosIncidents

Active and resolved SOS emergency events. Previous active SOS auto-resolved on new trigger.

| Column         | Type          | Nullable | Description |
|----------------|---------------|----------|-------------|
| SosId          | INT UNSIGNED  | No       | PK |
| UserId         | INT UNSIGNED  | No       | FK → Users (person in distress) |
| Latitude       | DECIMAL(10,7) | No       | — |
| Longitude      | DECIMAL(10,7) | No       | — |
| Description    | TEXT          | Yes      | — |
| SosType        | VARCHAR(20)   | No       | GENERAL / MEDICAL / FIRE / CRIME |
| Status         | VARCHAR(20)   | No       | ACTIVE / RESOLVED |
| ResolutionNote | TEXT          | Yes      | Set by user on resolve |
| TriggeredAt    | DATETIME      | No       | CURRENT_TIMESTAMP |
| ResolvedAt     | DATETIME      | Yes      | — |

---

### 10.2 SosResponders

Volunteers who respond to an SOS alert.

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| SosResponderId| INT UNSIGNED | No       | PK |
| SosId         | INT UNSIGNED | No       | FK → SosIncidents |
| UserId        | INT UNSIGNED | No       | FK → Users (responder) |
| Note          | TEXT         | Yes      | Responder message |
| RespondedAt   | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(SosId, UserId)` — one response per volunteer per SOS.

---

### 10.3 SosLocationLogs

**BIGINT PK** — High-frequency location updates during active SOS (every 10 seconds via SignalR). Used for live tracking.

| Column           | Type            | Nullable | Description |
|------------------|-----------------|----------|-------------|
| SosLocationLogId | BIGINT UNSIGNED | No       | PK |
| SosId            | INT UNSIGNED    | No       | FK → SosIncidents |
| UserId           | INT UNSIGNED    | No       | FK → Users |
| Latitude         | DECIMAL(10,7)   | No       | — |
| Longitude        | DECIMAL(10,7)   | No       | — |
| LoggedAt         | DATETIME        | No       | CURRENT_TIMESTAMP |

---

## 11. Group 10: Notifications

**Script File:** `Database/04_SP_All_New_Modules.sql`

### 11.1 Notifications

**BIGINT PK** — All in-app notifications. Volume: millions at scale.

| Column         | Type            | Nullable | Description |
|----------------|-----------------|----------|-------------|
| NotificationId | BIGINT UNSIGNED | No       | PK |
| UserId         | INT UNSIGNED    | No       | FK → Users (recipient) |
| Title          | VARCHAR(200)    | No       | Push notification title |
| Body           | TEXT            | No       | Full notification text |
| NotifType      | VARCHAR(50)     | No       | GENERAL / APPLICATION / DONATION / SOS / COMMUNITY |
| EntityId       | INT UNSIGNED    | Yes      | Related entity ID (ProjectId, PostId, etc.) |
| IsRead         | TINYINT(1)      | No       | 0 |
| IsDeleted      | TINYINT(1)      | No       | 0 |
| ReadAt         | DATETIME        | Yes      | — |
| CreatedAt      | DATETIME        | No       | CURRENT_TIMESTAMP |

**Index:** `(UserId, IsRead)` — used by `Notification_GetList` WHERE clause.

---

### 11.2 UserDeviceTokens

FCM push notification tokens per user per platform.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| DeviceTokenId| INT UNSIGNED | No       | PK |
| UserId       | INT UNSIGNED | No       | FK → Users |
| Token        | VARCHAR(512) | No       | Firebase FCM token |
| Platform     | VARCHAR(20)  | No       | ANDROID / IOS / WEB |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt    | DATETIME     | Yes      | Set by upsert |

**Unique:** `(UserId, Platform)` — one token per platform per user. Upsert pattern updates token on re-register.

---

## 12. Stored Procedures — Auth Module

**Script:** `Database/02_SP_Auth.sql`

| # | SP Name | Type | Tables | Called By |
|---|---------|------|--------|-----------|
| 1 | Auth_SendOTP | WRITE | OtpTokens | AuthDal.SendOtpAsync |
| 2 | Auth_VerifyOTP | WRITE | OtpTokens, Users, UserProfiles | AuthDal.VerifyOtpAsync |
| 3 | Auth_SaveRefreshToken | WRITE | RefreshTokens | AuthDal (internal) |
| 4 | Auth_GetRefreshToken | READ | RefreshTokens, Users | AuthDal.RefreshTokenAsync |
| 5 | Auth_RevokeRefreshToken | WRITE | RefreshTokens | AuthDal.RevokeTokenAsync |
| 6 | Auth_RevokeRefreshTokenById | WRITE | RefreshTokens | AuthDal (rotation) |

### Auth_SendOTP

**Purpose:** Generate and store OTP. Rate-limit enforced (max 3 per 10 min per Recipient+Purpose). Invalidates previous unused OTPs.

| Parameter | Type | Description |
|-----------|------|-------------|
| p_Recipient | VARCHAR(255) | Mobile or email |
| p_CountryCode | VARCHAR(5) | `+91` |
| p_OtpCode | VARCHAR(6) | Generated in C# |
| p_PurposeLkpId | INT UNSIGNED | OTP purpose |
| p_IpAddress | VARCHAR(45) | Requester IP |
| p_ExpiryMinutes | INT | Default: 10 |

**Returns:** `IsSuccess INT, Message VARCHAR`

---

### Auth_VerifyOTP

**Purpose:** Validate OTP. Creates user + profile on first login (IsNewUser=1). Tracks wrong attempts. Locks after 3 failures.

**Returns:** `IsSuccess INT, Message VARCHAR, UserId INT UNSIGNED, IsNewUser TINYINT`

---

### Auth_SaveRefreshToken

**Purpose:** Store hashed refresh token. Auto-revoke oldest when > 5 active sessions.

**Returns:** No result set.

---

### Auth_GetRefreshToken

**Purpose:** Validate token on rotation. Returns UserId + Recipient for JWT re-generation.

**Returns:** `IsSuccess INT, Message VARCHAR, UserId INT UNSIGNED, Recipient VARCHAR, RefreshTokenId INT UNSIGNED`

---

### Auth_RevokeRefreshToken

**Purpose:** Logout — revoke token by hash.

**Returns:** `IsSuccess INT, Message VARCHAR`

---

### Auth_RevokeRefreshTokenById

**Purpose:** Internal — revoke old token by PK during rotation.

**Returns:** No result set.

---

## 13. Stored Procedures — User Module

**Script:** `Database/03_SP_User.sql`

| # | SP Name | Type | Called By |
|---|---------|------|-----------|
| 7 | User_GetProfile | READ | UserDal.GetProfileAsync (ExecuteGetAsync → typed model) |
| 8 | User_GetPublicProfile | READ | UserDal.GetPublicProfileAsync (ExecuteDynamicGetAsync → DynamicRow) |
| 9 | User_UpdateProfile | WRITE | UserDal.UpdateProfileAsync |
| 10 | User_GetSkills | READ | UserDal.GetSkillsAsync (ExecuteReaderListAsync) |
| 11 | User_AddSkill | WRITE | UserDal.AddSkillAsync |
| 12 | User_RemoveSkill | WRITE | UserDal.RemoveSkillAsync |

All User SPs are fully documented in `Database_Documentation_v1.0.md` §3.7–§3.12. No changes in v2.0.

---

## 14. Stored Procedures — Settings Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | DAL Method | Returns |
|---|---------|------|------------|---------|
| 13 | Settings_GetPublic | LIST | ExecuteListAsync | All IsPublic=1 settings |
| 14 | Settings_GetByGroup | LIST | ExecuteListAsync | Settings filtered by SettingGroup |
| 15 | Settings_GetAll | LIST | ExecuteListAsync | All settings (admin only) |
| 16 | Settings_Update | WRITE | ExecuteWriteAsync | IsSuccess, Message |

### Settings_GetPublic
Returns all rows where `IsPublic=1 AND IsDeleted=0`, ordered by SettingGroup, SettingKey.
No parameters. Safe for unauthenticated frontend calls.

### Settings_GetByGroup
`p_SettingGroup VARCHAR(50)` — Returns all settings for a given group. Used internally by `SettingsCache`.

### Settings_GetAll
No parameters. Returns all non-deleted settings. Admin-only endpoint.

### Settings_Update
| Parameter | Type |
|-----------|------|
| p_SettingKey | VARCHAR(100) |
| p_SettingValue | TEXT |
| p_UpdatedBy | INT UNSIGNED |

Returns `IsSuccess, Message`. Called by admin endpoint; triggers `SettingsCache.RefreshAsync()`.

---

## 15. Stored Procedures — Organisation Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 17 | Org_Register | WRITE | Checks RegistrationNo duplicate. Auto-adds registrant as ADMIN in OrgMembers. |
| 18 | Org_GetProfile | READ (Dynamic) | Joins LookupValues for OrgType. Includes live MemberCount subquery. |
| 19 | Org_Update | WRITE | Checks caller is ADMIN/STAFF. COALESCE preserves existing values. |
| 20 | Org_List | PAGED (Dynamic) | Filterable by Search text. 2 result sets (data + TotalCount). |
| 21 | Org_GetMembers | READ (Reader) | Joins UserProfiles for FullName + AvatarUrl. |
| 22 | Org_AddMember | WRITE | Checks caller is ADMIN. Prevents duplicate membership. |
| 23 | Org_RemoveMember | WRITE | Soft-delete. Checks caller is ADMIN. |

### Org_Register Returns
`IsSuccess INT, Message VARCHAR, OrgId INT UNSIGNED`

### Org_List Parameters
`p_Search VARCHAR(200), p_PageNumber INT, p_PageSize INT`

### Org_AddMember Parameters
`p_OrgId INT UNSIGNED, p_RequestedBy INT UNSIGNED, p_UserId INT UNSIGNED, p_Role VARCHAR(20)`

---

## 16. Stored Procedures — Projects Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 24 | Project_Create | WRITE | Checks caller is org ADMIN/STAFF. |
| 25 | Project_GetById | READ (Dynamic) | Joins Organisations. Includes live AppliedCount. |
| 26 | Project_Update | WRITE | COALESCE PATCH semantics. Status can be updated. |
| 27 | Project_List | PAGED (Dynamic) | Filter by OrgId or Search. Only OPEN projects. |
| 28 | Project_AddSession | WRITE | Generates SHA-256 QR token. Checks org membership. |
| 29 | Project_GetSessions | LIST (Dynamic) | Returns sessions with live AttendeeCount. |
| 30 | Project_GetSessionQr | READ (Dynamic) | Returns QrCode only to ADMIN/STAFF. |
| 31 | Project_CheckIn | WRITE | Validates QR token. Prevents duplicate check-in. |

### Project_Create Returns
`IsSuccess, Message, ProjectId INT UNSIGNED`

### Project_CheckIn Parameters
`p_SessionId INT UNSIGNED, p_UserId INT UNSIGNED, p_QrToken VARCHAR(512)`

**QR Logic:** QrCode = `SHA2(CONCAT(ProjectId, SessionDate, RAND()), 256)`. Volunteer submits the token from their scanned QR. SP compares token directly.

---

## 17. Stored Procedures — Applications Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 32 | Application_Apply | WRITE | Checks project is OPEN. Prevents duplicate application. |
| 33 | Application_GetByProject | PAGED (Dynamic) | Filterable by Status (PENDING/APPROVED/REJECTED). |
| 34 | Application_Review | WRITE | Checks reviewer is org ADMIN/STAFF. |
| 35 | Application_GetByUser | LIST (Dynamic) | Returns all applications for a user with project details. |

### Application_Apply Parameters
`p_ProjectId INT UNSIGNED, p_UserId INT UNSIGNED, p_Note TEXT`

### Application_Review Parameters
`p_ApplicationId INT UNSIGNED, p_ReviewedBy INT UNSIGNED, p_Status VARCHAR(20), p_Note TEXT`

---

## 18. Stored Procedures — Posts Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 36 | Post_Create | WRITE | Parses MediaUrls (comma-separated) via JSON_TABLE into PostMedia. |
| 37 | Post_GetFeed | PAGED (Dynamic) | Includes IsLikedByMe per calling user. ORDER BY CreatedAt DESC. |
| 38 | Post_GetById | READ (Dynamic) | Single post with IsLikedByMe. Public. |
| 39 | Post_Like | WRITE | Unique constraint check + `LikeCount + 1`. |
| 40 | Post_Unlike | WRITE | DELETE from PostLikes + `LikeCount - 1` (GREATEST to prevent negative). |
| 41 | Post_AddComment | WRITE | Increments `CommentCount`. Supports nested (ParentCommentId). |
| 42 | Post_GetComments | PAGED (Dynamic) | Returns comments for a post. Public. |
| 43 | Post_Report | WRITE | Prevents duplicate reports per user per post. |

### Post_Create Parameters
`p_UserId INT UNSIGNED, p_OrgId INT UNSIGNED, p_Content TEXT, p_MediaUrls TEXT, p_PostType VARCHAR(20)`

MediaUrls is a comma-separated string: `"url1,url2,url3"` — parsed in SP via JSON_TABLE.

---

## 19. Stored Procedures — Community Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 44 | Community_CreatePost | WRITE | Tags stored as comma-separated string. |
| 45 | Community_GetFeed | PAGED (Dynamic) | Public. ORDER BY CreatedAt DESC. |
| 46 | Community_CreatePoll | WRITE | Options JSON array parsed via JSON_TABLE into PollOptions. |
| 47 | Community_Vote | WRITE | Checks poll not expired. Prevents double-vote. Increments VoteCount. |

### Community_CreatePoll Parameters
`p_UserId INT UNSIGNED, p_OrgId INT UNSIGNED, p_Question VARCHAR(500), p_OptionsJson JSON, p_ExpiresInHours INT`

**OptionsJson format:** `["Option A","Option B","Option C"]` — C# serializes `List<string>` to JSON before passing.

### Community_Vote Parameters
`p_PollId INT UNSIGNED, p_UserId INT UNSIGNED, p_PollOptionId INT UNSIGNED`

---

## 20. Stored Procedures — Donations Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 48 | Donation_CreateCampaign | WRITE | Checks org ADMIN/STAFF. Returns CampaignId. |
| 49 | Donation_GetCampaigns | PAGED (Dynamic) | Filter by OrgId or Search. ProgressPct calculated. |
| 50 | Donation_GetCampaignById | READ (Dynamic) | Includes DonorCount and ProgressPct. |
| 51 | Donation_Initiate | WRITE (Dynamic GET) | Generates DonationRef (DON-YYYY-NNNNNN) and mock RazorpayOrderId. Returns ref + order ID. |
| 52 | Donation_VerifyPayment | WRITE | Updates status to COMPLETED. Increments RaisedAmount. ⚠️ Signature verification must be done in C# before calling this SP. |
| 53 | Donation_GetTransactions | PAGED (Dynamic) | Donor's own transaction history. |
| 54 | Donation_GetReceipt | READ (Dynamic) | 80G receipt data. Status must be COMPLETED. |
| 55 | Donation_SetupRecurring | WRITE | Calculates NextRunAt from Frequency. |
| 56 | Donation_CancelRecurring | WRITE | Ownership check. Sets Status=CANCELLED. |

### Donation Payment Flow
1. Client calls `POST /donation/donate` → SP `Donation_Initiate` → returns `DonationRef + RazorpayOrderId`
2. Client pays via Razorpay SDK
3. Client calls `POST /donation/verify-payment` → C# layer verifies Razorpay HMAC-SHA256 signature → SP `Donation_VerifyPayment` → sets COMPLETED + updates RaisedAmount

### Donation_Initiate Returns
`DonationRef VARCHAR(20), RazorpayOrderId VARCHAR(100), Amount DECIMAL, TransactionId INT UNSIGNED`

---

## 21. Stored Procedures — SOS Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 57 | Sos_Trigger | WRITE | Auto-closes any existing ACTIVE SOS for user. Creates new. |
| 58 | Sos_Resolve | WRITE | Ownership check. Only triggering user can resolve. |
| 59 | Sos_Respond | WRITE | Prevents self-response. Prevents duplicate response. |
| 60 | Sos_UpdateLocation | WRITE | Inserts into SosLocationLogs (high-frequency) + updates SosIncidents current location. |

### Sos_Trigger Returns
`IsSuccess INT, Message VARCHAR, SosId INT UNSIGNED`

### Sos_UpdateLocation
Called every 10 seconds during active SOS via SignalR. Uses BIGINT PK table `SosLocationLogs` for volume safety.

---

## 22. Stored Procedures — Notifications Module

**Script:** `Database/04_SP_All_New_Modules.sql`

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 61 | Notification_GetList | PAGED (Dynamic) | User's notifications. Most recent first. |
| 62 | Notification_MarkRead | WRITE | Single notification. UserId ownership check. |
| 63 | Notification_MarkAllRead | WRITE | Bulk update. UserId scoped. |
| 64 | Notification_SaveDeviceToken | WRITE | `INSERT ... ON DUPLICATE KEY UPDATE` — upsert per (UserId, Platform). |

### Notification_SaveDeviceToken Parameters
`p_UserId INT UNSIGNED, p_Token VARCHAR(512), p_Platform VARCHAR(20)`

Platform values: `ANDROID`, `IOS`, `WEB`

---

## 23. Relationships Diagram

```
LookupTypes ──< LookupValues
                    │
                    ├── Users.RoleLkpId
                    ├── OtpTokens.PurposeLkpId
                    ├── UserProfiles.GenderLkpId
                    ├── UserSkills.SkillLkpId + ProficiencyLkpId
                    └── Organisations.OrgTypeId

Users ──1 UserProfiles          (UNIQUE FK)
Users ──< OtpTokens
Users ──< RefreshTokens
Users ──< UserSkills
Users ──< UserDeviceTokens
Users ──< Notifications         (BIGINT PK)

Organisations ──< OrgMembers ──> Users
Organisations ──< Projects ──< ProjectSessions
                           ──< ProjectApplications ──> Users
                           ──< ProjectAttendance   ──> Users + ProjectSessions

Users ──< Posts ──< PostMedia
               ──< PostLikes
               ──< PostComments
               ──< PostReports

Users ──< CommunityPosts ──< PollOptions ──< PollVotes ──> Users

Organisations ──< DonationCampaigns ──< DonationTransactions ──> Users
                                    ──< RecurringDonations    ──> Users

IdSequences — standalone sequence table (keyed by DON-YYYY)

Users ──< SosIncidents ──< SosResponders  ──> Users
                       ──< SosLocationLogs
```

---

## 24. SP Summary Index

| # | SP Name | Module | Script File |
|---|---------|--------|-------------|
| 1 | Auth_SendOTP | Auth | 02_SP_Auth.sql |
| 2 | Auth_VerifyOTP | Auth | 02_SP_Auth.sql |
| 3 | Auth_SaveRefreshToken | Auth | 02_SP_Auth.sql |
| 4 | Auth_GetRefreshToken | Auth | 02_SP_Auth.sql |
| 5 | Auth_RevokeRefreshToken | Auth | 02_SP_Auth.sql |
| 6 | Auth_RevokeRefreshTokenById | Auth | 02_SP_Auth.sql |
| 7 | User_GetProfile | User | 03_SP_User.sql |
| 8 | User_GetPublicProfile | User | 03_SP_User.sql |
| 9 | User_UpdateProfile | User | 03_SP_User.sql |
| 10 | User_GetSkills | User | 03_SP_User.sql |
| 11 | User_AddSkill | User | 03_SP_User.sql |
| 12 | User_RemoveSkill | User | 03_SP_User.sql |
| 13 | Settings_GetPublic | Settings | 04_SP_All_New_Modules.sql |
| 14 | Settings_GetByGroup | Settings | 04_SP_All_New_Modules.sql |
| 15 | Settings_GetAll | Settings | 04_SP_All_New_Modules.sql |
| 16 | Settings_Update | Settings | 04_SP_All_New_Modules.sql |
| 17 | Org_Register | Org | 04_SP_All_New_Modules.sql |
| 18 | Org_GetProfile | Org | 04_SP_All_New_Modules.sql |
| 19 | Org_Update | Org | 04_SP_All_New_Modules.sql |
| 20 | Org_List | Org | 04_SP_All_New_Modules.sql |
| 21 | Org_GetMembers | Org | 04_SP_All_New_Modules.sql |
| 22 | Org_AddMember | Org | 04_SP_All_New_Modules.sql |
| 23 | Org_RemoveMember | Org | 04_SP_All_New_Modules.sql |
| 24 | Project_Create | Projects | 04_SP_All_New_Modules.sql |
| 25 | Project_GetById | Projects | 04_SP_All_New_Modules.sql |
| 26 | Project_Update | Projects | 04_SP_All_New_Modules.sql |
| 27 | Project_List | Projects | 04_SP_All_New_Modules.sql |
| 28 | Project_AddSession | Projects | 04_SP_All_New_Modules.sql |
| 29 | Project_GetSessions | Projects | 04_SP_All_New_Modules.sql |
| 30 | Project_GetSessionQr | Projects | 04_SP_All_New_Modules.sql |
| 31 | Project_CheckIn | Projects | 04_SP_All_New_Modules.sql |
| 32 | Application_Apply | Applications | 04_SP_All_New_Modules.sql |
| 33 | Application_GetByProject | Applications | 04_SP_All_New_Modules.sql |
| 34 | Application_Review | Applications | 04_SP_All_New_Modules.sql |
| 35 | Application_GetByUser | Applications | 04_SP_All_New_Modules.sql |
| 36 | Post_Create | Posts | 04_SP_All_New_Modules.sql |
| 37 | Post_GetFeed | Posts | 04_SP_All_New_Modules.sql |
| 38 | Post_GetById | Posts | 04_SP_All_New_Modules.sql |
| 39 | Post_Like | Posts | 04_SP_All_New_Modules.sql |
| 40 | Post_Unlike | Posts | 04_SP_All_New_Modules.sql |
| 41 | Post_AddComment | Posts | 04_SP_All_New_Modules.sql |
| 42 | Post_GetComments | Posts | 04_SP_All_New_Modules.sql |
| 43 | Post_Report | Posts | 04_SP_All_New_Modules.sql |
| 44 | Community_CreatePost | Community | 04_SP_All_New_Modules.sql |
| 45 | Community_GetFeed | Community | 04_SP_All_New_Modules.sql |
| 46 | Community_CreatePoll | Community | 04_SP_All_New_Modules.sql |
| 47 | Community_Vote | Community | 04_SP_All_New_Modules.sql |
| 48 | Donation_CreateCampaign | Donations | 04_SP_All_New_Modules.sql |
| 49 | Donation_GetCampaigns | Donations | 04_SP_All_New_Modules.sql |
| 50 | Donation_GetCampaignById | Donations | 04_SP_All_New_Modules.sql |
| 51 | Donation_Initiate | Donations | 04_SP_All_New_Modules.sql |
| 52 | Donation_VerifyPayment | Donations | 04_SP_All_New_Modules.sql |
| 53 | Donation_GetTransactions | Donations | 04_SP_All_New_Modules.sql |
| 54 | Donation_GetReceipt | Donations | 04_SP_All_New_Modules.sql |
| 55 | Donation_SetupRecurring | Donations | 04_SP_All_New_Modules.sql |
| 56 | Donation_CancelRecurring | Donations | 04_SP_All_New_Modules.sql |
| 57 | Sos_Trigger | SOS | 04_SP_All_New_Modules.sql |
| 58 | Sos_Resolve | SOS | 04_SP_All_New_Modules.sql |
| 59 | Sos_Respond | SOS | 04_SP_All_New_Modules.sql |
| 60 | Sos_UpdateLocation | SOS | 04_SP_All_New_Modules.sql |
| 61 | Notification_GetList | Notifications | 04_SP_All_New_Modules.sql |
| 62 | Notification_MarkRead | Notifications | 04_SP_All_New_Modules.sql |
| 63 | Notification_MarkAllRead | Notifications | 04_SP_All_New_Modules.sql |
| 64 | Notification_SaveDeviceToken | Notifications | 04_SP_All_New_Modules.sql |

**Total: 64 Stored Procedures across 11 modules.**

---

## 25. Change Management Rules

### Before Any Change

1. Review this document for existing tables, columns, and SPs.
2. Verify: Does the table/column/SP already exist?
3. Assess impact on existing SPs, DALs, and APIs.
4. Prepare a Change Summary: existing structure → proposed change → impact → version increment.
5. **Wait for explicit confirmation before proceeding.**

### Mandatory Confirmation Required For

- Creating new tables
- Adding columns to existing tables
- Renaming columns or tables
- Modifying data types or lengths
- Deleting tables or columns
- Creating or modifying stored procedures
- Adding or removing indexes

### After Confirmation

1. Increment version number in this document header.
2. Add row to Version History table.
3. Generate and run the SQL script.
4. Update `API_Documentation_v{X}.docx` if API response shapes change.

### File Map

| File | Contains |
|------|----------|
| `Database/01_Tables_Auth_User.sql` | Users, OtpTokens, RefreshTokens, UserProfiles, UserSkills + seed data |
| `Database/02_SP_Auth.sql` | Auth SPs (#1–#6) |
| `Database/03_SP_User.sql` | User SPs (#7–#12) |
| `Database/04_SP_All_New_Modules.sql` | All new module tables (CREATE IF NOT EXISTS) + SPs (#13–#64) + seed Settings |

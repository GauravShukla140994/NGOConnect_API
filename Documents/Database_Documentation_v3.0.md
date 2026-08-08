# NGO Connect — Database Documentation Register
**Version:** v3.0
**Date:** 25-Jun-2026
**Database:** MySQL 8.0+
**Charset:** utf8mb4 / utf8mb4_unicode_ci
**Source of Truth:** `Documents/NGOConnect_Complete_Setup_250626.sql`

---

## Version History

| Version | Date        | Change Description |
|---------|-------------|--------------------|
| v1.0    | 24-Jun-2026 | Initial — Auth + User groups (5 tables, 12 SPs) |
| v2.0    | 24-Jun-2026 | Added all new modules: Settings, Organisations, Projects, Applications, Posts/Feed, Community/Polls, Donations, SOS, Notifications (22 new tables, 52 new SPs; total: 27 tables, 64 SPs) |
| v3.0    | 25-Jun-2026 | Full schema realignment with SQL source of truth. Major corrections: UserSkills is text-based (not FK), Organisations uses LkpId FKs throughout, Projects redesigned with type/location/join LkpIds, SosIncidents uses SosIncidentId PK + AlertTypeLkpId, DonationTransactions restructured, RecurringDonations uses RecurringDonId. Added 10+ missing tables. Total: 42 tables, 67 SPs. All Status/Type columns converted from VARCHAR to INT FK → LookupValues. |

---

## Table of Contents

1. [Database Design Principles](#1-database-design-principles)
2. [Tables — Group 1: Auth](#2-group-1-auth)
3. [Tables — Group 2: User Profiles](#3-group-2-user-profiles)
4. [Tables — Group 3: Organisations](#4-group-3-organisations)
5. [Tables — Group 4: Projects](#5-group-4-projects)
6. [Tables — Group 5: Content / Feed](#6-group-5-content--feed)
7. [Tables — Group 6: Community / Polls](#7-group-6-community--polls)
8. [Tables — Group 7: Donations](#8-group-7-donations)
9. [Tables — Group 8: SOS / Safety](#9-group-8-sos--safety)
10. [Tables — Group 9: Notifications + Device Tokens](#10-group-9-notifications--device-tokens)
11. [Tables — Group 10: Audit + Sequences](#11-group-10-audit--sequences)
12. [Tables — Group 11: Lookup + Settings](#12-group-11-lookup--settings)
13. [Stored Procedures — Auth Module](#13-stored-procedures--auth-module)
14. [Stored Procedures — User Module](#14-stored-procedures--user-module)
15. [Stored Procedures — Lookup Module](#15-stored-procedures--lookup-module)
16. [Stored Procedures — Settings Module](#16-stored-procedures--settings-module)
17. [Stored Procedures — Organisation Module](#17-stored-procedures--organisation-module)
18. [Stored Procedures — Projects Module](#18-stored-procedures--projects-module)
19. [Stored Procedures — Applications Module](#19-stored-procedures--applications-module)
20. [Stored Procedures — Posts Module](#20-stored-procedures--posts-module)
21. [Stored Procedures — Community Module](#21-stored-procedures--community-module)
22. [Stored Procedures — Donations Module](#22-stored-procedures--donations-module)
23. [Stored Procedures — SOS Module](#23-stored-procedures--sos-module)
24. [Stored Procedures — Notifications Module](#24-stored-procedures--notifications-module)
25. [LookupTypes Reference (42 Types)](#25-lookuptypes-reference-42-types)
26. [Relationships Diagram](#26-relationships-diagram)
27. [SP Summary Index](#27-sp-summary-index)
28. [Change Management Rules](#28-change-management-rules)

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
| **Lookups** | All category/status/type columns use `INT UNSIGNED FK → LookupValues`. Never VARCHAR enums. TypeCode pattern: `lt.TypeCode = 'ORG_STATUS'`, ValueCode: `lv.ValueCode = 'ACTIVE'`. |
| **Timestamps** | `CreatedAt = DEFAULT CURRENT_TIMESTAMP`. `UpdatedAt = DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`. |
| **Readable IDs** | Donations use `DON-YYYY-000001` format via `IdSequences` table. |
| **Denormalized Counts** | `Posts.LikeCount`, `DonationCampaigns.RaisedAmount`, `DonationCampaigns.DonorCount` maintained by SP — no COUNT() on hot read paths. |
| **Config** | All platform configuration in `Settings` table. Loaded into singleton `SettingsCache` at startup. Zero DB reads for config after boot. |

---

## 2. Group 1: Auth

### 2.1 Users

Core authentication table. One row per registered user.

| Column       | Type         | Nullable | Default           | Description |
|--------------|--------------|----------|-------------------|-------------|
| UserId       | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| Mobile       | VARCHAR(20)  | Yes      | NULL              | Registered mobile (**was MobileNumber in v2.0**) |
| Email        | VARCHAR(150) | Yes      | NULL              | Email (optional) |
| PasswordHash | VARCHAR(255) | Yes      | NULL              | BCrypt hash (future) |
| CountryCode  | VARCHAR(6)   | No       | `+91`             | Dialing code |
| IsVerified   | TINYINT(1)   | No       | 0                 | Set to 1 after first OTP |
| IsActive     | TINYINT(1)   | No       | 1                 | Account active flag |
| LastLoginAt  | DATETIME     | Yes      | NULL              | Last successful login |
| IsDeleted    | TINYINT(1)   | No       | 0                 | Soft delete |
| DeletedAt    | DATETIME     | Yes      | NULL              | — |
| DeletedBy    | INT UNSIGNED | Yes      | NULL              | — |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP | — |
| CreatedBy    | INT UNSIGNED | Yes      | NULL              | — |
| UpdatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE | — |
| UpdatedBy    | INT UNSIGNED | Yes      | NULL              | — |

**Indexes:** `uq_users_mobile (Mobile, IsDeleted)`, `uq_users_email (Email, IsDeleted)`, `idx_users_isactive`

> ⚠️ **v2.0 → v3.0:** Column renamed `MobileNumber` → `Mobile`. Removed `RoleLkpId` (no Role on Users table). Added `PasswordHash`, `LastLoginAt`, `CreatedBy`, `UpdatedBy`.

---

### 2.2 OtpTokens

| Column       | Type         | Nullable | Default           | Description |
|--------------|--------------|----------|-------------------|-------------|
| OtpTokenId   | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| UserId       | INT UNSIGNED | Yes      | NULL              | NULL for unregistered users |
| Recipient    | VARCHAR(150) | No       | —                 | Mobile or email |
| OtpCode      | VARCHAR(10)  | No       | —                 | 6-digit OTP |
| PurposeLkpId | INT UNSIGNED | No       | —                 | FK → LookupValues (OTP_PURPOSE) |
| ExpiresAt    | DATETIME     | No       | —                 | now + 10 min |
| AttemptCount | TINYINT      | No       | 0                 | Max 3 wrong attempts |
| IsUsed       | TINYINT(1)   | No       | 0                 | 1 = used/expired |
| IpAddress    | VARCHAR(45)  | Yes      | NULL              | IPv4/IPv6 |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP | — |

**Business Rules:** Max 3 OTPs per 10 min per Recipient+Purpose. Max 3 wrong attempts before lock.

---

### 2.3 RefreshTokens

| Column         | Type         | Nullable | Default           | Description |
|----------------|--------------|----------|-------------------|-------------|
| RefreshTokenId | INT UNSIGNED | No       | AUTO_INCREMENT    | Primary key |
| UserId         | INT UNSIGNED | No       | —                 | FK → Users |
| Token          | VARCHAR(500) | No       | —                 | SHA-256 hash |
| DeviceInfo     | VARCHAR(255) | Yes      | NULL              | Device identifier |
| IpAddress      | VARCHAR(45)  | Yes      | NULL              | IP at creation |
| ExpiresAt      | DATETIME     | No       | —                 | now + 30 days |
| IsRevoked      | TINYINT(1)   | No       | 0                 | 1 = logged out |
| RevokedAt      | DATETIME     | Yes      | NULL              | — |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP | — |

**Business Rules:** Token rotated on every use. Oldest session auto-revoked when > 5 active.

---

## 3. Group 2: User Profiles

### 3.1 UserProfiles

Extended profile per user.

| Column          | Type           | Nullable | Default | Description |
|-----------------|----------------|----------|---------|-------------|
| UserProfileId   | INT UNSIGNED   | No       | AUTO_INCREMENT | PK |
| UserId          | INT UNSIGNED   | No       | —       | FK → Users (UNIQUE) |
| FirstName       | VARCHAR(80)    | No       | —       | — |
| LastName        | VARCHAR(80)    | No       | —       | — |
| DateOfBirth     | DATE           | Yes      | NULL    | — |
| GenderLkpId     | INT UNSIGNED   | Yes      | NULL    | FK → LookupValues (GENDER) |
| Bio             | TEXT           | Yes      | NULL    | **was `About` in v2.0** |
| ProfilePhoto    | VARCHAR(500)   | Yes      | NULL    | Azure Blob URL. **was `ProfilePhotoUrl` in v2.0** |
| Occupation      | VARCHAR(150)   | Yes      | NULL    | **new in v3.0** |
| Organisation    | VARCHAR(150)   | Yes      | NULL    | Current employer text |
| EducationLkpId  | INT UNSIGNED   | Yes      | NULL    | FK → LookupValues (EDUCATION) |
| FieldOfStudy    | VARCHAR(150)   | Yes      | NULL    | — |
| WorkExpLkpId    | INT UNSIGNED   | Yes      | NULL    | FK → LookupValues (WORK_EXPERIENCE) |
| AddressLine1    | VARCHAR(200)   | Yes      | NULL    | — |
| AddressLine2    | VARCHAR(200)   | Yes      | NULL    | — |
| City            | VARCHAR(100)   | Yes      | NULL    | — |
| State           | VARCHAR(100)   | Yes      | NULL    | — |
| Pincode         | VARCHAR(20)    | Yes      | NULL    | — |
| Country         | VARCHAR(100)   | Yes      | `India` | — |
| ImpactScore     | INT UNSIGNED   | No       | 0       | Calculated badge score |
| ReliabilityPct  | DECIMAL(5,2)   | No       | 100.00  | Attendance reliability % |
| IsDeleted       | TINYINT(1)     | No       | 0       | — |
| CreatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP | — |
| UpdatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE | — |

> ⚠️ **v2.0 → v3.0:** `About` → `Bio`. `ProfilePhotoUrl` → `ProfilePhoto`. Removed `DisplayName`, `LinkedInUrl`, `WebsiteUrl`. Added `Occupation`, `Organisation`, `EducationLkpId`, `FieldOfStudy`, `WorkExpLkpId`, `AddressLine1`, `AddressLine2`, `Pincode`, `ImpactScore`, `ReliabilityPct`.

---

### 3.2 UserDocuments

Identity and address proof documents. *(New in v3.0 — not in v2.0)*

| Column            | Type         | Nullable | Description |
|-------------------|--------------|----------|-------------|
| UserDocumentId    | INT UNSIGNED | No       | PK |
| UserId            | INT UNSIGNED | No       | FK → Users |
| DocumentTypeLkpId | INT UNSIGNED | No       | FK → LookupValues (DOCUMENT_TYPE_USER) |
| FileUrl           | VARCHAR(500) | No       | Azure Blob URL |
| FileName          | VARCHAR(255) | No       | — |
| FileSizeKb        | INT UNSIGNED | Yes      | — |
| IsVerified        | TINYINT(1)   | No       | 0 |
| VerifiedAt        | DATETIME     | Yes      | — |
| VerifiedBy        | INT UNSIGNED | Yes      | Admin UserId |
| IsDeleted         | TINYINT(1)   | No       | 0 |
| CreatedAt         | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 3.3 UserSkills

Skills on a user's profile. **Text-based — NOT FK-based.**

| Column      | Type           | Nullable | Description |
|-------------|----------------|----------|-------------|
| UserSkillId | INT UNSIGNED   | No       | PK |
| UserId      | INT UNSIGNED   | No       | FK → Users |
| SkillName   | VARCHAR(100)   | No       | Free-text skill name |
| AvgRating   | DECIMAL(3,2)   | No       | 0.00 — Updated by peer ratings |
| RatingCount | INT UNSIGNED   | No       | 0 — Number of ratings received |
| IsDeleted   | TINYINT(1)     | No       | 0 |
| CreatedAt   | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt   | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

**Unique:** `(UserId, SkillName, IsDeleted)` — one entry per skill name per user.

> ⚠️ **v2.0 → v3.0:** Complete redesign. v2.0 had `SkillLkpId + ProficiencyLkpId` (FK-based). v3.0 uses `SkillName VARCHAR(100)` (text, free entry). Added `AvgRating`, `RatingCount` for peer rating system. Removed `ProficiencyLkpId` entirely.

---

### 3.4 UserSkillRatings

Peer ratings for volunteer skills after project sessions. *(New in v3.0)*

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| SkillRatingId | INT UNSIGNED | No       | PK |
| UserSkillId   | INT UNSIGNED | No       | FK → UserSkills |
| RatedByUserId | INT UNSIGNED | No       | FK → Users (rater) |
| SessionId     | INT UNSIGNED | Yes      | FK → ProjectSessions |
| Rating        | TINYINT      | No       | 1–5 |
| RatedAt       | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(UserSkillId, RatedByUserId, SessionId)` — one rating per rater per skill per session.

---

### 3.5 UserBadges

Achievement badges awarded to volunteers. *(New in v3.0)*

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| UserBadgeId    | INT UNSIGNED | No       | PK |
| UserId         | INT UNSIGNED | No       | FK → Users |
| BadgeType      | VARCHAR(50)  | No       | Badge category text |
| AwardedByUserId| INT UNSIGNED | No       | FK → Users |
| OrgId          | INT UNSIGNED | Yes      | FK → Organisations |
| AwardedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |
| IsDeleted      | TINYINT(1)   | No       | 0 |

---

### 3.6 UserInterests

Interest tags for volunteer matching. *(New in v3.0)*

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| UserInterestId| INT UNSIGNED | No       | PK |
| UserId        | INT UNSIGNED | No       | FK → Users |
| InterestName  | VARCHAR(100) | No       | Free-text interest |
| CreatedAt     | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 3.7 UserSafetyPreferences

Per-user SOS and location sharing preferences. *(New in v3.0)*

| Column               | Type         | Nullable | Description |
|----------------------|--------------|----------|-------------|
| UserSafetyPrefId     | INT UNSIGNED | No       | PK |
| UserId               | INT UNSIGNED | No       | FK → Users (UNIQUE) |
| EmergVisibilityLkpId | INT UNSIGNED | No       | FK → LookupValues (EMERGENCY_VISIBILITY) |
| AutoShareDurLkpId    | INT UNSIGNED | No       | FK → LookupValues (AUTO_SHARE_DURATION) |
| AllowLocDuringSos    | TINYINT(1)   | No       | 1 |
| AllowLocDuringProj   | TINYINT(1)   | No       | 1 |
| CreatedAt            | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt            | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

---

## 4. Group 3: Organisations

### 4.1 Organisations

| Column          | Type         | Nullable | Description |
|-----------------|--------------|----------|-------------|
| OrgId           | INT UNSIGNED | No       | PK |
| OrgName         | VARCHAR(200) | No       | Display name |
| OrgTypeLkpId    | INT UNSIGNED | No       | FK → LookupValues (ORG_TYPE). **was `OrgTypeId` in v2.0** |
| RegNumber       | VARCHAR(100) | No       | Govt registration number. **was `RegistrationNo` in v2.0** |
| Category        | VARCHAR(100) | No       | Primary cause area. **new in v3.0** |
| LogoUrl         | VARCHAR(500) | Yes      | Azure Blob URL |
| About           | TEXT         | Yes      | Description |
| Mission         | TEXT         | Yes      | Org mission statement. **new in v3.0** |
| Vision          | TEXT         | Yes      | Org vision statement. **new in v3.0** |
| ContactEmail    | VARCHAR(150) | Yes      | **was `Email` in v2.0** |
| ContactPhone    | VARCHAR(20)  | Yes      | **was `Phone` in v2.0** |
| Website         | VARCHAR(255) | Yes      | — |
| AddressLine1    | VARCHAR(200) | Yes      | — |
| AddressLine2    | VARCHAR(200) | Yes      | — |
| City            | VARCHAR(100) | Yes      | — |
| State           | VARCHAR(100) | Yes      | — |
| Pincode         | VARCHAR(20)  | Yes      | — |
| Country         | VARCHAR(100) | No       | Default: India |
| StatusLkpId     | INT UNSIGNED | No       | FK → LookupValues (ORG_STATUS). **was `IsVerified TINYINT` in v2.0** |
| StatusUpdatedAt | DATETIME     | Yes      | — |
| StatusUpdatedBy | INT UNSIGNED | Yes      | Admin UserId |
| IsDeleted       | TINYINT(1)   | No       | 0 |
| CreatedBy       | INT UNSIGNED | No       | UserId of registrant |
| CreatedAt       | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt       | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** `OrgTypeId` → `OrgTypeLkpId`. `RegistrationNo` → `RegNumber`. `Phone` → `ContactPhone`. `Email` → `ContactEmail`. `IsVerified TINYINT` → `StatusLkpId INT FK` (ORG_STATUS values: PENDING, VERIFIED, SUSPENDED). Added `Category`, `Mission`, `Vision`, `AddressLine1/2`, `Pincode`.

---

### 4.2 OrgDocuments

NGO verification documents. *(New in v3.0)*

| Column            | Type         | Nullable | Description |
|-------------------|--------------|----------|-------------|
| OrgDocumentId     | INT UNSIGNED | No       | PK |
| OrgId             | INT UNSIGNED | No       | FK → Organisations |
| DocumentTypeLkpId | INT UNSIGNED | No       | FK → LookupValues (DOCUMENT_TYPE_ORG) |
| FileUrl           | VARCHAR(500) | No       | Azure Blob URL |
| FileName          | VARCHAR(255) | No       | — |
| IsVerified        | TINYINT(1)   | No       | 0 |
| VerifiedAt        | DATETIME     | Yes      | — |
| VerifiedBy        | INT UNSIGNED | Yes      | Admin UserId |
| IsDeleted         | TINYINT(1)   | No       | 0 |
| CreatedAt         | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 4.3 OrgMembers

Members of an organisation with their roles.

| Column           | Type         | Nullable | Description |
|------------------|--------------|----------|-------------|
| OrgMemberId      | INT UNSIGNED | No       | PK |
| OrgId            | INT UNSIGNED | No       | FK → Organisations |
| UserId           | INT UNSIGNED | No       | FK → Users |
| RoleLkpId        | INT UNSIGNED | No       | FK → LookupValues (MEMBER_ROLE). **was `Role VARCHAR(20)` in v2.0** |
| StatusLkpId      | INT UNSIGNED | No       | FK → LookupValues (MEMBER_STATUS). **new in v3.0** |
| StatusUpdatedAt  | DATETIME     | Yes      | — |
| StatusUpdatedBy  | INT UNSIGNED | Yes      | — |
| CanPost          | TINYINT(1)   | No       | 1 |
| CanComment       | TINYINT(1)   | No       | 1 |
| CanCommunityPost | TINYINT(1)   | No       | 1 |
| MaxPostsPerDay   | TINYINT      | No       | 10 |
| JoinedAt         | DATETIME     | Yes      | NULL |
| IsDeleted        | TINYINT(1)   | No       | 0 |
| CreatedBy        | INT UNSIGNED | Yes      | Admin who added the member |
| CreatedAt        | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(OrgId, UserId, IsDeleted)`.

> ⚠️ **v2.0 → v3.0:** `Role VARCHAR(20)` → `RoleLkpId INT UNSIGNED FK`. Added `StatusLkpId`, `CanPost`, `CanComment`, `CanCommunityPost`, `MaxPostsPerDay`.

---

### 4.4 OrgDonationSettings

Donation and banking configuration per org. *(New in v3.0)*

| Column              | Type           | Nullable | Description |
|---------------------|----------------|----------|-------------|
| OrgDonSettingId     | INT UNSIGNED   | No       | PK |
| OrgId               | INT UNSIGNED   | No       | FK → Organisations (UNIQUE) |
| IsDonationEnabled   | TINYINT(1)     | No       | 0 |
| PlatformFeePct      | DECIMAL(5,2)   | No       | 1.00 |
| BankAccNumber       | VARCHAR(50)    | Yes      | Encrypted at rest |
| BankIfsc            | VARCHAR(20)    | Yes      | — |
| BankName            | VARCHAR(100)   | Yes      | — |
| AccountHolderName   | VARCHAR(150)   | Yes      | — |
| Pan                 | VARCHAR(20)    | Yes      | Encrypted at rest |
| Is80GEligible       | TINYINT(1)     | No       | 0 |
| Is12AEligible       | TINYINT(1)     | No       | 0 |
| RazorpayAccountId   | VARCHAR(100)   | Yes      | — |
| KycStatusLkpId      | INT UNSIGNED   | No       | FK → LookupValues (KYC_STATUS) |
| KycVerifiedAt       | DATETIME       | Yes      | — |
| KycVerifiedBy       | INT UNSIGNED   | Yes      | Admin UserId |
| CreatedAt           | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt           | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

---

## 5. Group 4: Projects

### 5.1 Projects

Volunteer engagement projects created by organisations.

| Column            | Type           | Nullable | Description |
|-------------------|----------------|----------|-------------|
| ProjectId         | INT UNSIGNED   | No       | PK |
| OrgId             | INT UNSIGNED   | No       | FK → Organisations |
| ProjectName       | VARCHAR(200)   | No       | **was `Title` in v2.0** |
| Category          | VARCHAR(100)   | No       | Cause category text. **new in v3.0** |
| Description       | TEXT           | Yes      | — |
| ProjectTypeLkpId  | INT UNSIGNED   | No       | FK → LookupValues (PROJECT_TYPE). **new in v3.0** |
| ScheduleTypeLkpId | INT UNSIGNED   | Yes      | FK → LookupValues (SCHEDULE_TYPE) |
| RecurStart        | DATE           | Yes      | For recurring projects |
| RecurEnd          | DATE           | Yes      | — |
| RecurDays         | VARCHAR(20)    | Yes      | e.g. `MON,WED,FRI` |
| SessionStartTime  | TIME           | Yes      | — |
| SessionEndTime    | TIME           | Yes      | — |
| OneTimeDate       | DATE           | Yes      | For one-off projects |
| FlexFromDate      | DATE           | Yes      | For flexible-schedule projects |
| FlexToDate        | DATE           | Yes      | — |
| MinHoursRequired  | INT UNSIGNED   | Yes      | Minimum volunteer hours |
| LocationTypeLkpId | INT UNSIGNED   | No       | FK → LookupValues (LOCATION_TYPE). **new in v3.0** |
| AddressLine       | VARCHAR(300)   | Yes      | Venue address |
| Landmark          | VARCHAR(200)   | Yes      | — |
| City              | VARCHAR(100)   | Yes      | — |
| State             | VARCHAR(100)   | Yes      | — |
| Latitude          | DECIMAL(10,7)  | Yes      | — |
| Longitude         | DECIMAL(10,7)  | Yes      | — |
| GoogleMapsUrl     | VARCHAR(500)   | Yes      | — |
| MaxVolunteers     | INT UNSIGNED   | Yes      | NULL = unlimited |
| JoinTypeLkpId     | INT UNSIGNED   | No       | FK → LookupValues (PROJECT_JOIN_TYPE). **new in v3.0** |
| IsPublic          | TINYINT(1)     | No       | 1 — Public = discoverable by all. **new in v3.0** |
| AgeRestriction    | TINYINT(1)     | No       | 0 |
| IdVerRequired     | TINYINT(1)     | No       | 0 |
| MinReliability    | DECIMAL(5,2)   | No       | 0 |
| StatusLkpId       | INT UNSIGNED   | No       | FK → LookupValues (PROJECT_STATUS). **was `Status VARCHAR` in v2.0** |
| IsDeleted         | TINYINT(1)     | No       | 0 |
| CreatedBy         | INT UNSIGNED   | No       | — |
| CreatedAt         | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt         | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** `Title` → `ProjectName`. `Status VARCHAR` → `StatusLkpId INT FK`. Removed `StartDate`, `EndDate` as simple columns (replaced by schedule type columns). Added `Category`, `ProjectTypeLkpId`, `LocationTypeLkpId`, `JoinTypeLkpId`, `IsPublic`, `AgeRestriction`, `IdVerRequired`, `MinReliability`.

---

### 5.2 ProjectSkills

Skills required for a project. *(New in v3.0)*

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| ProjectSkillId| INT UNSIGNED | No       | PK |
| ProjectId     | INT UNSIGNED | No       | FK → Projects |
| SkillName     | VARCHAR(100) | No       | Free-text skill name (mirrors UserSkills.SkillName) |

---

### 5.3 ProjectSessions

Scheduled attendance sessions within a project.

| Column            | Type         | Nullable | Description |
|-------------------|--------------|----------|-------------|
| SessionId         | INT UNSIGNED | No       | PK |
| ProjectId         | INT UNSIGNED | No       | FK → Projects |
| SessionDate       | DATE         | No       | Date of session. **new in v3.0** |
| StartTime         | TIME         | No       | Session start time. **new in v3.0** |
| EndTime           | TIME         | No       | Session end time. **new in v3.0** |
| MaxVolunteers     | INT UNSIGNED | Yes      | — |
| QrCode            | VARCHAR(100) | Yes      | UUID-based QR token for check-in |
| QrExpiresAt       | DATETIME     | Yes      | QR validity window. **new in v3.0** |
| SessionStatusLkpId| INT UNSIGNED | No       | FK → LookupValues (SESSION_STATUS). **was `IsActive TINYINT` in v2.0** |
| IsDeleted         | TINYINT(1)   | No       | 0 |
| CreatedAt         | DATETIME     | No       | CURRENT_TIMESTAMP |
| CreatedBy         | INT UNSIGNED | Yes      | — |
| UpdatedAt         | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** Removed `Title`, `Location`. Added `SessionDate`, `StartTime`, `EndTime`, `MaxVolunteers`, `QrExpiresAt`. `IsActive TINYINT` → `SessionStatusLkpId INT FK`.

---

### 5.4 ProjectApplications

Volunteer applications to projects.

| Column           | Type         | Nullable | Description |
|------------------|--------------|----------|-------------|
| ApplicationId    | INT UNSIGNED | No       | PK |
| ProjectId        | INT UNSIGNED | No       | FK → Projects |
| UserId           | INT UNSIGNED | No       | FK → Users (applicant) |
| Motivation       | TEXT         | Yes      | Applicant note. **was `Note` in v2.0** |
| RequestedSessions| VARCHAR(200) | Yes      | — |
| StatusLkpId      | INT UNSIGNED | No       | FK → LookupValues (APPLICATION_STATUS). **was `Status VARCHAR` in v2.0** |
| StatusUpdatedAt  | DATETIME     | Yes      | — |
| StatusUpdatedBy  | INT UNSIGNED | Yes      | Reviewer UserId |
| RejectionReason  | TEXT         | Yes      | Set on REJECTED status |
| IsDeleted        | TINYINT(1)   | No       | 0 |
| CreatedAt        | DATETIME     | No       | CURRENT_TIMESTAMP |

> ⚠️ **v2.0 → v3.0:** `Status VARCHAR` → `StatusLkpId INT FK`. `Note` → `Motivation`. Added `RejectionReason`, `RequestedSessions`.

---

### 5.5 ProjectAttendance

QR scan check-in records per session.

| Column            | Type           | Nullable | Description |
|-------------------|----------------|----------|-------------|
| AttendanceId      | INT UNSIGNED   | No       | PK |
| SessionId         | INT UNSIGNED   | No       | FK → ProjectSessions |
| UserId            | INT UNSIGNED   | No       | FK → Users |
| CheckInTime       | DATETIME       | No       | — |
| CheckOutTime      | DATETIME       | Yes      | — |
| HoursLogged       | DECIMAL(4,2)   | Yes      | Calculated on checkout |
| QrScannedAt       | DATETIME       | Yes      | When QR was scanned |
| AttendStatusLkpId | INT UNSIGNED   | No       | FK → LookupValues (ATTENDANCE_STATUS) |
| NoShowReason      | TEXT           | Yes      | — |
| IsNoShowExcused   | TINYINT(1)     | No       | 0 |
| AdminNote         | TEXT           | Yes      | — |
| CreatedAt         | DATETIME       | No       | CURRENT_TIMESTAMP |

**Unique:** `(SessionId, UserId)` — one check-in per volunteer per session.

---

### 5.6 VolunteerCertificates

Certificates issued to volunteers on project completion. *(New in v3.0)*

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| CertificateId | INT UNSIGNED | No       | PK |
| ProjectId     | INT UNSIGNED | No       | FK → Projects |
| UserId        | INT UNSIGNED | No       | FK → Users |
| CertificateUrl| VARCHAR(500) | No       | Azure Blob PDF URL |
| IssuedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |
| IssuedBy      | INT UNSIGNED | Yes      | Admin UserId |

**Unique:** `(ProjectId, UserId)`.

---

## 6. Group 5: Content / Feed

### 6.1 Posts

Main social feed posts.

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| PostId         | INT UNSIGNED | No       | PK |
| OrgId          | INT UNSIGNED | Yes      | FK → Organisations (if posted as org) |
| UserId         | INT UNSIGNED | No       | FK → Users (author) |
| PostTypeLkpId  | INT UNSIGNED | No       | FK → LookupValues (POST_TYPE_FEED). **was `PostType VARCHAR` in v2.0** |
| Content        | TEXT         | No       | Post body |
| VisibilityLkpId| INT UNSIGNED | No       | FK → LookupValues (POST_VISIBILITY). **new in v3.0** |
| IsPinned       | TINYINT(1)   | No       | 0 |
| PinnedAt       | DATETIME     | Yes      | — |
| PinnedBy       | INT UNSIGNED | Yes      | — |
| LikeCount      | INT UNSIGNED | No       | 0 — Denormalized |
| CommentCount   | INT UNSIGNED | No       | 0 — Denormalized |
| IsDeleted      | TINYINT(1)   | No       | 0 |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** `PostType VARCHAR` → `PostTypeLkpId INT FK`. Added `VisibilityLkpId`, `IsPinned`, `PinnedAt`, `PinnedBy`.

---

### 6.2 PostMedia

Media files attached to posts. One-to-many.

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| PostMediaId   | INT UNSIGNED | No       | PK |
| PostId        | INT UNSIGNED | No       | FK → Posts |
| FileUrl       | VARCHAR(500) | No       | Azure Blob URL. **was `MediaUrl` in v2.0** |
| MediaTypeLkpId| INT UNSIGNED | No       | FK → LookupValues (MEDIA_TYPE). **new in v3.0** |
| SortOrder     | TINYINT      | No       | 1 |
| CreatedAt     | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 6.3 PostLikes

| Column    | Type         | Nullable | Description |
|-----------|--------------|----------|-------------|
| PostLikeId| INT UNSIGNED | No       | PK |
| PostId    | INT UNSIGNED | No       | FK → Posts |
| UserId    | INT UNSIGNED | No       | FK → Users |
| CreatedAt | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(PostId, UserId)`.

---

### 6.4 PostComments

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| CommentId      | INT UNSIGNED | No       | PK |
| PostId         | INT UNSIGNED | No       | FK → Posts |
| UserId         | INT UNSIGNED | No       | FK → Users |
| ParentCommentId| INT UNSIGNED | Yes      | NULL = top-level. Set for replies. |
| Content        | TEXT         | No       | — |
| LikeCount      | INT UNSIGNED | No       | 0 |
| IsDeleted      | TINYINT(1)   | No       | 0 |
| CreatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt      | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

---

### 6.5 PostReports

User reports on posts (for moderation).

| Column          | Type         | Nullable | Description |
|-----------------|--------------|----------|-------------|
| PostReportId    | INT UNSIGNED | No       | PK |
| PostId          | INT UNSIGNED | No       | FK → Posts |
| ReportedByUserId| INT UNSIGNED | No       | FK → Users (reporter). **was `UserId` in v2.0** |
| ReasonLkpId     | INT UNSIGNED | No       | FK → LookupValues (REPORT_REASON). **was `Reason TEXT` in v2.0** |
| Details         | TEXT         | Yes      | Optional extra detail. **new in v3.0** |
| StatusLkpId     | INT UNSIGNED | No       | FK → LookupValues (ORG_STATUS for moderation). **was `Status VARCHAR` in v2.0** |
| ReviewedBy      | INT UNSIGNED | Yes      | Admin UserId |
| ReviewedAt      | DATETIME     | Yes      | — |
| CreatedAt       | DATETIME     | No       | CURRENT_TIMESTAMP |

> ⚠️ **v2.0 → v3.0:** `UserId` → `ReportedByUserId`. `Reason TEXT` → `ReasonLkpId INT FK`. Added `Details`, `StatusLkpId`, `ReviewedBy`, `ReviewedAt`.

---

## 7. Group 6: Community / Polls

### 7.1 CommunityPosts

Org community board posts. Supports multiple types: discussion, announcement, task, event, poll.

| Column              | Type         | Nullable | Description |
|---------------------|--------------|----------|-------------|
| CommunityPostId     | INT UNSIGNED | No       | PK |
| OrgId               | INT UNSIGNED | No       | FK → Organisations |
| UserId              | INT UNSIGNED | No       | FK → Users |
| PostTypeLkpId       | INT UNSIGNED | No       | FK → LookupValues (POST_TYPE_COMMUNITY). **new in v3.0** |
| Title               | VARCHAR(300) | No       | Post title or poll question. **new in v3.0** |
| Content             | TEXT         | Yes      | — |
| AudienceLkpId       | INT UNSIGNED | No       | FK → LookupValues (POST_VISIBILITY). **new in v3.0** |
| IsPinned            | TINYINT(1)   | No       | 0 |
| BestAnswerCommentId | INT UNSIGNED | Yes      | — |
| AssignedToUserId    | INT UNSIGNED | Yes      | For task-type posts |
| DueDate             | DATETIME     | Yes      | — |
| TaskStatusLkpId     | INT UNSIGNED | Yes      | FK → LookupValues (TASK_STATUS) |
| PollEndsAt          | DATETIME     | Yes      | Poll expiry. **was `ExpiresAt` in v2.0** |
| PollIsMultiChoice   | TINYINT(1)   | Yes      | — |
| ResourceFileUrl     | VARCHAR(500) | Yes      | — |
| AcknowledgeCount    | INT UNSIGNED | No       | 0 — Denormalized |
| IsDeleted           | TINYINT(1)   | No       | 0 |
| CreatedAt           | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt           | DATETIME     | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** Added `PostTypeLkpId`, `Title` (NOT NULL), `AudienceLkpId`, `IsPinned`, `AcknowledgeCount`. Removed `Tags VARCHAR(500)`, `IsPoll TINYINT`. `ExpiresAt` → `PollEndsAt`. `OrgId` now NOT NULL.

---

### 7.2 PollOptions

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| PollOptionId   | INT UNSIGNED | No       | PK |
| CommunityPostId| INT UNSIGNED | No       | FK → CommunityPosts |
| OptionText     | VARCHAR(200) | No       | Display text |
| VoteCount      | INT UNSIGNED | No       | 0 — Denormalized |
| SortOrder      | TINYINT      | No       | Display order |

---

### 7.3 PollVotes

| Column         | Type         | Nullable | Description |
|----------------|--------------|----------|-------------|
| PollVoteId     | INT UNSIGNED | No       | PK |
| PollOptionId   | INT UNSIGNED | No       | FK → PollOptions |
| CommunityPostId| INT UNSIGNED | No       | FK → CommunityPosts |
| UserId         | INT UNSIGNED | No       | FK → Users |
| VotedAt        | DATETIME     | No       | CURRENT_TIMESTAMP |

**Unique:** `(UserId, CommunityPostId)` — one vote per user per poll.

---

## 8. Group 7: Donations

### 8.1 DonationCampaigns

Fundraising campaigns created by organisations.

| Column            | Type           | Nullable | Description |
|-------------------|----------------|----------|-------------|
| CampaignId        | INT UNSIGNED   | No       | PK |
| OrgId             | INT UNSIGNED   | No       | FK → Organisations |
| CreatedByUserId   | INT UNSIGNED   | No       | FK → Users |
| CampaignName      | VARCHAR(200)   | No       | **was `Title` in v2.0** |
| Description       | TEXT           | Yes      | — |
| CampaignTypeLkpId | INT UNSIGNED   | No       | FK → LookupValues (CAMPAIGN_TYPE). **new in v3.0** |
| TargetAmount      | DECIMAL(12,2)  | No       | **was `GoalAmount` in v2.0** |
| RaisedAmount      | DECIMAL(12,2)  | No       | 0.00 — Denormalized |
| DonorCount        | INT UNSIGNED   | No       | 0 — Denormalized. **new in v3.0** |
| StartDate         | DATE           | No       | **new in v3.0** |
| EndDate           | DATE           | Yes      | — |
| BannerUrl         | VARCHAR(500)   | Yes      | — |
| ProjectId         | INT UNSIGNED   | Yes      | FK → Projects (optional link) |
| VisibilityLkpId   | INT UNSIGNED   | No       | FK → LookupValues (POST_VISIBILITY). **new in v3.0** |
| StatusLkpId       | INT UNSIGNED   | No       | FK → LookupValues (CAMPAIGN_STATUS). **was `Status VARCHAR` in v2.0** |
| IsDeleted         | TINYINT(1)     | No       | 0 |
| CreatedAt         | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt         | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** `Title` → `CampaignName`. `GoalAmount` → `TargetAmount`. `Status VARCHAR` → `StatusLkpId INT FK`. Added `CampaignTypeLkpId`, `StartDate` (required), `DonorCount`, `VisibilityLkpId`, `ProjectId`.

---

### 8.2 DonationTransactions

Individual donation payment records.

| Column           | Type           | Nullable | Description |
|------------------|----------------|----------|-------------|
| TransactionId    | INT UNSIGNED   | No       | PK |
| DonationId       | VARCHAR(30)    | No       | UNIQUE. Human-readable: `DON-2026-000001`. **was `DonationRef` in v2.0** |
| CampaignId       | INT UNSIGNED   | Yes      | FK → DonationCampaigns |
| OrgId            | INT UNSIGNED   | No       | FK → Organisations |
| DonorUserId      | INT UNSIGNED   | Yes      | FK → Users. NULL if anonymous. **was `UserId` in v2.0** |
| DonorName        | VARCHAR(150)   | Yes      | For anonymous/guest donors |
| DonorEmail       | VARCHAR(150)   | Yes      | — |
| DonorMobile      | VARCHAR(20)    | Yes      | — |
| DonorPan         | VARCHAR(20)    | Yes      | Encrypted at rest |
| DonationAmount   | DECIMAL(12,2)  | No       | In INR. **was `Amount` in v2.0** |
| PlatformFeePct   | DECIMAL(5,2)   | No       | % deducted as platform fee |
| PlatformFeeAmt   | DECIMAL(10,2)  | No       | Calculated fee amount |
| OrgReceivesAmt   | DECIMAL(12,2)  | No       | DonationAmount - PlatformFeeAmt |
| DonTypeLkpId     | INT UNSIGNED   | No       | FK → LookupValues (DONATION_TYPE) |
| PayMethodLkpId   | INT UNSIGNED   | No       | FK → LookupValues (PAYMENT_METHOD). **new in v3.0** |
| VisibilityLkpId  | INT UNSIGNED   | No       | FK → LookupValues (POST_VISIBILITY) |
| PayStatusLkpId   | INT UNSIGNED   | No       | FK → LookupValues (DONATION_STATUS). **was `Status VARCHAR` in v2.0** |
| GatewayOrderId   | VARCHAR(100)   | Yes      | Razorpay order ID. **was `RazorpayOrderId` in v2.0** |
| GatewayPaymentId | VARCHAR(100)   | Yes      | Razorpay payment ID |
| GatewayResponse  | TEXT           | Yes      | Raw gateway response |
| FailureReason    | TEXT           | Yes      | — |
| IsDeleted        | TINYINT(1)     | No       | 0 |
| CreatedAt        | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt        | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** `DonationRef` → `DonationId`. `UserId` → `DonorUserId`. `Amount` → `DonationAmount`. `Status VARCHAR` → `PayStatusLkpId INT FK`. `RazorpayOrderId` → `GatewayOrderId`. Added `PayMethodLkpId`, `DonTypeLkpId`, `VisibilityLkpId`, `PlatformFeePct/Amt`, `OrgReceivesAmt`, `OrgId`, `DonorName/Email/Mobile/Pan`.

---

### 8.3 RecurringDonations

Scheduled recurring donation setups. Processed by Hangfire background job.

| Column          | Type           | Nullable | Description |
|-----------------|----------------|----------|-------------|
| RecurringDonId  | INT UNSIGNED   | No       | PK. **was `RecurringId` in v2.0** |
| DonorUserId     | INT UNSIGNED   | No       | FK → Users. **was `UserId` in v2.0** |
| OrgId           | INT UNSIGNED   | No       | FK → Organisations. **new required field in v3.0** |
| CampaignId      | INT UNSIGNED   | Yes      | FK → DonationCampaigns (optional) |
| Amount          | DECIMAL(12,2)  | No       | — |
| FrequencyLkpId  | INT UNSIGNED   | No       | FK → LookupValues (RECURRING_FREQUENCY). **was `Frequency VARCHAR` in v2.0** |
| StatusLkpId     | INT UNSIGNED   | No       | FK → LookupValues (RECURRING_STATUS). **was `Status VARCHAR` in v2.0** |
| StartDate       | DATE           | No       | First charge date. **new in v3.0** |
| NextChargeDate  | DATE           | No       | Next scheduled charge. **was `NextRunAt DATETIME` in v2.0** |
| PausedAt        | DATETIME       | Yes      | — |
| CancelledAt     | DATETIME       | Yes      | — |
| GatewaySubId    | VARCHAR(100)   | Yes      | Razorpay subscription ID |
| SuccessCount    | INT UNSIGNED   | No       | 0 |
| FailureCount    | INT UNSIGNED   | No       | 0 |
| IsDeleted       | TINYINT(1)     | No       | 0 |
| CreatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

**Index:** `(NextChargeDate, StatusLkpId)` — used by Hangfire job to find due recurring donations.

> ⚠️ **v2.0 → v3.0:** PK renamed `RecurringId` → `RecurringDonId`. `UserId` → `DonorUserId`. `Frequency VARCHAR` → `FrequencyLkpId`. `Status VARCHAR` → `StatusLkpId`. `NextRunAt DATETIME` → `NextChargeDate DATE`. Added `OrgId` (required), `StartDate` (required). Removed `Note`.

---

### 8.4 DonationReceipts

80G tax receipts. *(New in v3.0)*

| Column        | Type         | Nullable | Description |
|---------------|--------------|----------|-------------|
| ReceiptId     | INT UNSIGNED | No       | PK |
| TransactionId | INT UNSIGNED | No       | FK → DonationTransactions (UNIQUE) |
| ReceiptNumber | VARCHAR(50)  | No       | — |
| ReceiptUrl    | VARCHAR(500) | No       | Azure Blob PDF URL |
| FiscalYear    | VARCHAR(10)  | No       | e.g. `2025-26` |
| IssuedAt      | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 8.5 WithdrawalRequests

NGO withdrawal requests from campaign funds. *(New in v3.0)*

| Column             | Type           | Nullable | Description |
|--------------------|----------------|----------|-------------|
| WithdrawalId       | INT UNSIGNED   | No       | PK |
| WithdrawalRef      | VARCHAR(30)    | No       | UNIQUE. e.g. `WDR-2026-0001` |
| OrgId              | INT UNSIGNED   | No       | FK → Organisations |
| RequestedByUserId  | INT UNSIGNED   | No       | FK → Users |
| Amount             | DECIMAL(12,2)  | No       | — |
| Purpose            | TEXT           | No       | — |
| StatusLkpId        | INT UNSIGNED   | No       | FK → LookupValues (WITHDRAWAL_STATUS) |
| ReviewedBy         | INT UNSIGNED   | Yes      | Admin UserId |
| ReviewedAt         | DATETIME       | Yes      | — |
| RejectionReason    | TEXT           | Yes      | — |
| TransferredAt      | DATETIME       | Yes      | — |
| BankRef            | VARCHAR(100)   | Yes      | Bank transfer reference |
| IsDeleted          | TINYINT(1)     | No       | 0 |
| CreatedAt          | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt          | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

---

### 8.6 PaymentGatewayLogs

Raw gateway webhook and callback logs. *(New in v3.0)*

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| GatewayLogId | INT UNSIGNED | No       | PK |
| TransactionId| INT UNSIGNED | Yes      | FK → DonationTransactions |
| EventType    | VARCHAR(100) | No       | e.g. `payment.captured` |
| GatewayRef   | VARCHAR(200) | Yes      | Gateway reference ID |
| Payload      | MEDIUMTEXT   | No       | Raw JSON payload |
| ProcessedAt  | DATETIME     | No       | CURRENT_TIMESTAMP |
| IsProcessed  | TINYINT(1)   | No       | 0 |

---

## 9. Group 8: SOS / Safety

### 9.1 SosIncidents

Active and resolved SOS emergency events.

| Column          | Type           | Nullable | Description |
|-----------------|----------------|----------|-------------|
| SosIncidentId   | INT UNSIGNED   | No       | PK. **was `SosId` in v2.0** |
| UserId          | INT UNSIGNED   | No       | FK → Users (person in distress) |
| OrgId           | INT UNSIGNED   | Yes      | FK → Organisations. **new in v3.0** |
| AlertTypeLkpId  | INT UNSIGNED   | No       | FK → LookupValues (SOS_ALERT_TYPE). **was `SosType VARCHAR` in v2.0** |
| Description     | TEXT           | Yes      | — |
| ApproxLocation  | VARCHAR(300)   | Yes      | Text description of location. **new in v3.0** |
| Latitude        | DECIMAL(10,7)  | Yes      | — |
| Longitude       | DECIMAL(10,7)  | Yes      | — |
| StatusLkpId     | INT UNSIGNED   | No       | FK → LookupValues (SOS_STATUS). **was `Status VARCHAR` in v2.0** |
| ResolvedAt      | DATETIME       | Yes      | — |
| ResolvedByLkpId | INT UNSIGNED   | Yes      | FK → LookupValues (SOS_RESOLVED_BY). **was `ResolutionNote TEXT` in v2.0** |
| CancelReason    | TEXT           | Yes      | — |
| IsDeleted       | TINYINT(1)     | No       | 0 |
| CreatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP |
| UpdatedAt       | DATETIME       | No       | CURRENT_TIMESTAMP ON UPDATE |

> ⚠️ **v2.0 → v3.0:** PK renamed `SosId` → `SosIncidentId`. `SosType VARCHAR` → `AlertTypeLkpId INT FK`. `Status VARCHAR` → `StatusLkpId INT FK`. `ResolutionNote TEXT` → `ResolvedByLkpId INT FK` (LookupType: SOS_RESOLVED_BY). Added `OrgId`, `ApproxLocation`, `CancelReason`. **All C# code, interfaces, and controllers use `sosIncidentId` naming.**

---

### 9.2 SosResponders

Volunteers who respond to an SOS alert.

| Column               | Type         | Nullable | Description |
|----------------------|--------------|----------|-------------|
| SosResponderId       | INT UNSIGNED | No       | PK |
| SosIncidentId        | INT UNSIGNED | No       | FK → SosIncidents. **was `SosId` in v2.0** |
| UserId               | INT UNSIGNED | No       | FK → Users (responder) |
| RespondedAt          | DATETIME     | No       | CURRENT_TIMESTAMP |
| ApprovalStatusLkpId  | INT UNSIGNED | No       | FK → LookupValues (RESPONDER_STATUS). **new in v3.0** |
| ApprovedAt           | DATETIME     | Yes      | — |
| ApprovedBy           | INT UNSIGNED | Yes      | — |
| CanViewLocation      | TINYINT(1)   | No       | 0 |

**Unique:** `(SosIncidentId, UserId)`.

> ⚠️ **v2.0 → v3.0:** `SosId` → `SosIncidentId`. Removed `Note`. Added `ApprovalStatusLkpId`, `ApprovedAt`, `ApprovedBy`, `CanViewLocation`.

---

### 9.3 SosLocationLogs

**BIGINT PK** — High-frequency location updates during active SOS (every 10 seconds via SignalR).

| Column           | Type            | Nullable | Description |
|------------------|-----------------|----------|-------------|
| SosLocationLogId | BIGINT UNSIGNED | No       | PK |
| SosIncidentId    | INT UNSIGNED    | No       | FK → SosIncidents. **was `SosId` in v2.0** |
| UserId           | INT UNSIGNED    | No       | FK → Users |
| Latitude         | DECIMAL(10,7)   | No       | — |
| Longitude        | DECIMAL(10,7)   | No       | — |
| Accuracy         | DECIMAL(8,2)    | Yes      | GPS accuracy in metres. **new in v3.0** |
| LoggedAt         | DATETIME        | No       | CURRENT_TIMESTAMP |

> ⚠️ **v2.0 → v3.0:** `SosId` → `SosIncidentId`. Added `Accuracy DECIMAL(8,2)`.

---

## 10. Group 9: Notifications + Device Tokens

### 10.1 Notifications

**BIGINT PK** — All in-app notifications.

| Column         | Type            | Nullable | Description |
|----------------|-----------------|----------|-------------|
| NotificationId | BIGINT UNSIGNED | No       | PK |
| UserId         | INT UNSIGNED    | No       | FK → Users (recipient) |
| NotifType      | VARCHAR(50)     | No       | GENERAL / APPLICATION / DONATION / SOS / COMMUNITY |
| Title          | VARCHAR(200)    | No       | Push notification title |
| Body           | TEXT            | No       | Full notification text |
| RefId          | INT UNSIGNED    | Yes      | Related entity ID. **was `EntityId` in v2.0** |
| RefType        | VARCHAR(50)     | Yes      | Entity type name. **new in v3.0** |
| IsRead         | TINYINT(1)      | No       | 0 |
| ReadAt         | DATETIME        | Yes      | — |
| IsSent         | TINYINT(1)      | No       | 0. **new in v3.0** |
| SentAt         | DATETIME        | Yes      | When FCM push was sent. **new in v3.0** |
| CreatedAt      | DATETIME        | No       | CURRENT_TIMESTAMP |

---

### 10.2 UserDeviceTokens

FCM push notification tokens per user per platform.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| DeviceTokenId| INT UNSIGNED | No       | PK |
| UserId       | INT UNSIGNED | No       | FK → Users |
| Token        | VARCHAR(512) | No       | Firebase FCM token |
| Platform     | VARCHAR(20)  | No       | ANDROID / IOS / WEB |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP |
| UpdatedAt    | DATETIME     | Yes      | Set by upsert |

**Unique:** `(UserId, Platform)` — upsert pattern.

---

## 11. Group 10: Audit + Sequences

### 11.1 AuditLogs

**BIGINT PK** — Every write operation produces one row.

| Column     | Type            | Nullable | Description |
|------------|-----------------|----------|-------------|
| AuditLogId | BIGINT UNSIGNED | No       | PK |
| UserId     | INT UNSIGNED    | Yes      | Actor |
| Action     | VARCHAR(100)    | No       | e.g. `PROJECT_CREATED` |
| EntityName | VARCHAR(100)    | No       | Table name |
| EntityId   | INT UNSIGNED    | Yes      | PK of affected row |
| OldValue   | MEDIUMTEXT      | Yes      | JSON before |
| NewValue   | MEDIUMTEXT      | Yes      | JSON after |
| IpAddress  | VARCHAR(45)     | Yes      | — |
| UserAgent  | VARCHAR(300)    | Yes      | — |
| CreatedAt  | DATETIME        | No       | CURRENT_TIMESTAMP |

---

### 11.2 IdSequences

Sequence counter for human-readable IDs.

| Column       | Type        | Description |
|--------------|-------------|-------------|
| SequenceName | VARCHAR(50) | PK part — e.g. `DON` |
| CurrentYear  | YEAR        | PK part — e.g. `2026` |
| LastValue    | INT UNSIGNED| Auto-incremented via `ON DUPLICATE KEY UPDATE` |

**Pattern:** `DON-2026-000001` = `CONCAT('DON-', Year, '-', LPAD(LastValue, 6, '0'))`

---

## 12. Group 11: Lookup + Settings

### 12.1 LookupTypes

Reference list categories. 42 types seeded.

| Column      | Type         | Nullable | Description |
|-------------|--------------|----------|-------------|
| LookupTypeId| INT UNSIGNED | No       | PK |
| TypeCode    | VARCHAR(50)  | No       | UNIQUE. Machine-readable e.g. `GENDER` |
| TypeName    | VARCHAR(100) | No       | Display name |
| Description | VARCHAR(300) | Yes      | — |
| IsSystemType| TINYINT(1)   | No       | 0 — If 1, admin cannot delete |
| IsDeleted   | TINYINT(1)   | No       | 0 |
| CreatedAt   | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 12.2 LookupValues

Individual options within a LookupType.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| LookupValueId| INT UNSIGNED | No       | PK — used as FK in all `*LkpId` columns |
| LookupTypeId | INT UNSIGNED | No       | FK → LookupTypes |
| ValueCode    | VARCHAR(50)  | No       | UNIQUE per type. Machine-readable e.g. `ACTIVE` |
| ValueName    | VARCHAR(100) | No       | Display name e.g. `Active` |
| Description  | VARCHAR(300) | Yes      | — |
| OrderNo      | SMALLINT     | No       | 0 — Dropdown display order |
| IsDefault    | TINYINT(1)   | No       | 0 — Pre-selected in UI |
| IsSystemValue| TINYINT(1)   | No       | 0 — Cannot be deleted by admin |
| IsDeleted    | TINYINT(1)   | No       | 0 |
| CreatedAt    | DATETIME     | No       | CURRENT_TIMESTAMP |

---

### 12.3 Settings

All platform configuration. Zero DB reads after startup.

| Column       | Type         | Nullable | Description |
|--------------|--------------|----------|-------------|
| SettingId    | INT UNSIGNED | No       | PK |
| SettingGroup | VARCHAR(50)  | No       | OTP, AUTH, PAGINATION, FEATURE, DONATION, UPLOAD, PLATFORM |
| SettingKey   | VARCHAR(100) | No       | UNIQUE. Machine-readable e.g. `OTP_EXPIRY_MINUTES` |
| SettingValue | TEXT         | No       | The value |
| DataType     | VARCHAR(20)  | No       | STRING, NUMBER, BOOLEAN, URL, JSON |
| Description  | VARCHAR(500) | Yes      | — |
| IsPublic     | TINYINT(1)   | No       | 0 — 1 = safe to expose via `/api/v1/settings/public`. **Secrets are NEVER IsPublic=1** |
| IsDeleted    | TINYINT(1)   | No       | 0 |
| UpdatedAt    | DATETIME     | Yes      | — |
| UpdatedBy    | INT UNSIGNED | Yes      | Admin UserId |

---

## 13. Stored Procedures — Auth Module

**Script:** included in `NGOConnect_Complete_Setup_250626.sql`

| # | SP Name | Type | Called By |
|---|---------|------|-----------|
| 1 | Auth_SendOTP | WRITE | AuthDal.SendOtpAsync |
| 2 | Auth_VerifyOTP | WRITE | AuthDal.VerifyOtpAsync |
| 3 | Auth_SaveRefreshToken | WRITE (internal) | AuthDal |
| 4 | Auth_GetRefreshToken | READ | AuthDal.RefreshTokenAsync |
| 5 | Auth_RevokeRefreshToken | WRITE | AuthDal.RevokeTokenAsync |
| 6 | Auth_RevokeRefreshTokenById | WRITE (internal) | AuthDal rotation |

### Auth_SendOTP Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_Recipient | VARCHAR(255) | Mobile or email |
| p_CountryCode | VARCHAR(5) | `+91` |
| p_OtpCode | VARCHAR(6) | Generated in C# |
| p_PurposeLkpId | INT UNSIGNED | OTP purpose LkpId |
| p_IpAddress | VARCHAR(45) | Requester IP |
| p_ExpiryMinutes | INT | Default: 10 |

**Returns:** `IsSuccess INT, Message VARCHAR`

### Auth_VerifyOTP Returns
`IsSuccess INT, Message VARCHAR, UserId INT UNSIGNED, IsNewUser TINYINT`

---

## 14. Stored Procedures — User Module

| # | SP Name | Type | Called By |
|---|---------|------|-----------|
| 7 | User_GetProfile | READ | UserDal.GetProfileAsync → ExecuteGetAsync → typed model |
| 8 | User_GetPublicProfile | READ (Dynamic) | UserDal.GetPublicProfileAsync → DynamicRow |
| 9 | User_UpdateProfile | WRITE | UserDal.UpdateProfileAsync |
| 10 | User_GetSkills | READ (Reader) | UserDal.GetSkillsAsync → ExecuteReaderListAsync |
| 11 | User_AddSkill | WRITE | UserDal.AddSkillAsync |
| 12 | User_RemoveSkill | WRITE | UserDal.RemoveSkillAsync |

### User_UpdateProfile Parameters *(v3.0 corrected)*

| Parameter | Type | Maps to DB Column |
|-----------|------|-------------------|
| p_UserId | INT UNSIGNED | UserId |
| p_FirstName | VARCHAR(80) | FirstName |
| p_LastName | VARCHAR(80) | LastName |
| p_About | TEXT | **Bio** (API param `About` → DB column `Bio`) |
| p_GenderLkpId | INT UNSIGNED | GenderLkpId |
| p_DateOfBirth | DATE | DateOfBirth |
| p_Occupation | VARCHAR(150) | Occupation |
| p_City | VARCHAR(100) | City |
| p_State | VARCHAR(100) | State |
| p_Country | VARCHAR(100) | Country |

**Returns:** `IsSuccess INT, Message VARCHAR`

### User_AddSkill Parameters *(v3.0 corrected — text-based)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | — |
| p_SkillName | VARCHAR(100) | Free-text skill name. **Replaces p_SkillLkpId + p_ProficiencyLkpId from v2.0** |

**Returns:** `IsSuccess INT, Message VARCHAR, UserSkillId INT UNSIGNED`

### User_GetSkills Returns
`UserSkillId, SkillName, AvgRating, RatingCount` — typed to `UserSkillModel`.

---

## 15. Stored Procedures — Lookup Module

| # | SP Name | Type | Called By |
|---|---------|------|-----------|
| 13 | Lookup_GetAllTypes | LIST | LookupDal.GetAllTypesAsync |
| 14 | Lookup_GetValuesByType | LIST | LookupDal.GetValuesByTypeCodeAsync |

> ⚠️ **v2.0 had no Lookup SPs.** Both are new in v3.0. SP name is `Lookup_GetValuesByType` — **NOT** `Lookup_GetValuesByTypeCode`. There is **no** `Lookup_GetValueByCode` SP — C# filters by ValueCode in memory after fetching all values for the type.

### Lookup_GetValuesByType Parameters

| Parameter | Type |
|-----------|------|
| p_TypeCode | VARCHAR(50) |

**Returns:** `LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault`

---

## 16. Stored Procedures — Settings Module

| # | SP Name | Type | Called By |
|---|---------|------|-----------|
| 15 | Settings_GetPublic | LIST | SettingsDal.GetPublicAsync → IsPublic=1 rows |
| 16 | Settings_GetByGroup | LIST | SettingsCache at startup |
| 17 | Settings_GetAll | LIST | Admin only |
| 18 | Settings_Update | WRITE | SettingsDal.UpdateAsync → refreshes cache |

### Settings_Update Parameters

| Parameter | Type |
|-----------|------|
| p_SettingKey | VARCHAR(100) |
| p_SettingValue | TEXT |
| p_UpdatedBy | INT UNSIGNED |

---

## 17. Stored Procedures — Organisation Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 19 | Org_Register | WRITE | Checks RegNumber duplicate. Auto-adds registrant as FOUNDER. Initialises OrgDonationSettings. |
| 20 | Org_GetProfile | READ (Dynamic) | Joins LookupValues for OrgType + OrgStatus. Live MemberCount. |
| 21 | Org_Update | WRITE | COALESCE PATCH. Only ADMIN/FOUNDER can update. |
| 22 | Org_List | PAGED (Dynamic) | Filter by Search. Returns OrgType + OrgStatus from LookupValues. |
| 23 | Org_GetMembers | READ (Reader) | Joins UserProfiles + LookupValues for RoleCode + StatusCode. |
| 24 | Org_AddMember | WRITE | Only ADMIN/FOUNDER can add. Prevents duplicate. |
| 25 | Org_RemoveMember | WRITE | Soft-delete. ADMIN/FOUNDER only. |

### Org_Register Parameters *(v3.0 corrected)*

| Parameter | Type | Maps to DB Column |
|-----------|------|-------------------|
| p_UserId | INT UNSIGNED | CreatedBy |
| p_OrgName | VARCHAR(200) | OrgName |
| p_RegistrationNo | VARCHAR(100) | **RegNumber** |
| p_Category | VARCHAR(100) | Category. **new in v3.0** |
| p_About | TEXT | About |
| p_Website | VARCHAR(255) | Website |
| p_Phone | VARCHAR(20) | **ContactPhone** |
| p_Email | VARCHAR(150) | **ContactEmail** |
| p_City | VARCHAR(100) | City |
| p_State | VARCHAR(100) | State |
| p_Country | VARCHAR(100) | Country |
| p_OrgTypeLkpId | INT UNSIGNED | OrgTypeLkpId. **was p_OrgTypeId in v2.0** |

**Returns:** `IsSuccess INT, Message VARCHAR, OrgId INT UNSIGNED`

### Org_AddMember Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_OrgId | INT UNSIGNED | — |
| p_RequestedBy | INT UNSIGNED | Caller UserId (must be ADMIN/FOUNDER) |
| p_UserId | INT UNSIGNED | User to add |
| p_RoleLkpId | INT UNSIGNED | Role LkpId from MEMBER_ROLE type. **was p_Role VARCHAR in v2.0** |

---

## 18. Stored Procedures — Projects Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 26 | Project_Create | WRITE | Caller must be org ADMIN/STAFF. No StartDate/EndDate params. |
| 27 | Project_GetById | READ (Dynamic) | Joins Org, LookupValues. Includes live AppliedCount. |
| 28 | Project_Update | WRITE | COALESCE PATCH. `p_StatusLkpId` not `p_Status`. |
| 29 | Project_List | PAGED (Dynamic) | Filter by OrgId or Search. |
| 30 | Project_AddSession | WRITE | Takes SessionDate, StartTime, EndTime. Generates QrCode UUID. |
| 31 | Project_GetSessions | LIST (Dynamic) | Returns sessions with AttendeeCount. |
| 32 | Project_GetSessionQr | READ (Dynamic) | Returns QrCode to ADMIN/STAFF only. |
| 33 | Project_CheckIn | WRITE | Validates QR token. No SessionId param — SP finds session by QrToken. |

### Project_CheckIn Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | Volunteer checking in |
| p_QrToken | VARCHAR(100) | QR code scanned from ProjectSessions.QrCode |

> ⚠️ **v2.0 had `p_SessionId` as a parameter.** v3.0 removed it — SP finds the session by matching `p_QrToken` against `ProjectSessions.QrCode`. This prevents session ID spoofing.

**Returns:** `IsSuccess INT, Message VARCHAR`

---

## 19. Stored Procedures — Applications Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 34 | Application_Apply | WRITE | p_Note maps to Motivation column. Checks project is ACTIVE. |
| 35 | Application_GetByProject | PAGED (Dynamic) | Filter by p_StatusLkpId (INT, not string). |
| 36 | Application_Review | WRITE | p_StatusLkpId (INT). Checks reviewer is ADMIN/STAFF. |
| 37 | Application_GetByUser | LIST (Dynamic) | All user's applications with project details. |

### Application_GetByProject Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_ProjectId | INT UNSIGNED | — |
| p_StatusLkpId | INT UNSIGNED | Filter value. NULL = all. **was p_Status VARCHAR in v2.0** |
| p_PageNumber | INT | — |
| p_PageSize | INT | — |

### Application_Review Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_ApplicationId | INT UNSIGNED | — |
| p_ReviewedBy | INT UNSIGNED | Reviewer UserId |
| p_StatusLkpId | INT UNSIGNED | New status LkpId. **was p_Status VARCHAR in v2.0** |
| p_Note | TEXT | Maps to RejectionReason column |

---

## 20. Stored Procedures — Posts Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 38 | Post_Create | WRITE | MediaUrls comma-separated → parsed via JSON_TABLE into PostMedia. |
| 39 | Post_GetFeed | PAGED (Dynamic) | Includes IsLikedByMe per caller. ORDER BY IsPinned DESC, CreatedAt DESC. |
| 40 | Post_GetById | READ (Dynamic) | Single post with IsLikedByMe. |
| 41 | Post_Like | WRITE | Unique check + LikeCount + 1. |
| 42 | Post_Unlike | WRITE | DELETE + GREATEST(LikeCount - 1, 0). |
| 43 | Post_AddComment | WRITE | Increments CommentCount. Supports nested replies. |
| 44 | Post_GetComments | PAGED (Dynamic) | Comments for a post. |
| 45 | Post_Report | WRITE | ReportedByUserId not UserId. Prevents duplicate reports. |

### Post_Create Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | — |
| p_OrgId | INT UNSIGNED | Optional — posting as org |
| p_Content | TEXT | Post body |
| p_MediaUrls | TEXT | Comma-separated Azure Blob URLs |
| p_PostTypeLkpId | INT UNSIGNED | FK → LookupValues (POST_TYPE_FEED). **was p_PostType VARCHAR in v2.0** |
| p_VisibilityLkpId | INT UNSIGNED | FK → LookupValues (POST_VISIBILITY). **new in v3.0** |

**Returns:** `IsSuccess INT, Message VARCHAR, PostId INT UNSIGNED`

### Post_Report Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_PostId | INT UNSIGNED | — |
| p_UserId | INT UNSIGNED | Reporter UserId |
| p_ReasonLkpId | INT UNSIGNED | FK → LookupValues (REPORT_REASON). **was p_Reason TEXT in v2.0** |
| p_Details | TEXT | Optional detail. **new in v3.0** |

---

## 21. Stored Procedures — Community Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 46 | Community_CreatePost | WRITE | Title is required (NOT NULL). AudienceLkpId defaults to ORG_MEMBERS. |
| 47 | Community_GetFeed | PAGED (Dynamic) | Filterable by OrgId. ORDER BY IsPinned DESC, CreatedAt DESC. |
| 48 | Community_CreatePoll | WRITE | Title = poll question. PollEndsAt computed. |
| 49 | Community_Vote | WRITE | Checks PollEndsAt not expired. Prevents double-vote. |

### Community_CreatePost Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | — |
| p_OrgId | INT UNSIGNED | Required — community is org-scoped |
| p_Title | VARCHAR(300) | **Required.** Maps to CommunityPosts.Title. **new in v3.0** |
| p_Content | TEXT | Optional |
| p_PostTypeLkpId | INT UNSIGNED | FK → LookupValues (POST_TYPE_COMMUNITY). **new in v3.0** |
| p_AudienceLkpId | INT UNSIGNED | FK → LookupValues (POST_VISIBILITY). **new in v3.0** |

> ⚠️ **v2.0 had `p_Content, p_Tags`.** v3.0 adds `p_Title` (required), `p_PostTypeLkpId`, `p_AudienceLkpId`. Removed `p_Tags` (no Tags column in DB).

### Community_GetFeed Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_OrgId | INT UNSIGNED | Filter by org. NULL = global community. **new in v3.0** |
| p_PageNumber | INT | — |
| p_PageSize | INT | — |

---

## 22. Stored Procedures — Donations Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 50 | Donation_CreateCampaign | WRITE | p_StartDate required. p_CampaignTypeLkpId required. |
| 51 | Donation_GetCampaigns | PAGED (Dynamic) | Filter by OrgId + Search. CampaignName aliased as Title. |
| 52 | Donation_GetCampaignById | READ (Dynamic) | Includes DonorCount + ProgressPct. |
| 53 | Donation_Initiate | WRITE | Generates DonationId (DON-YYYY-NNNNNN). Requires p_PayMethodLkpId. |
| 54 | Donation_VerifyPayment | WRITE | ⚠️ Razorpay HMAC-SHA256 must be verified in C# BEFORE calling this SP. |
| 55 | Donation_GetTransactions | PAGED (Dynamic) | Donor's own history. |
| 56 | Donation_GetReceipt | READ (Dynamic) | By DonationId VARCHAR (DON-2026-000001 string). |
| 57 | Donation_SetupRecurring | WRITE | p_OrgId required. p_FrequencyLkpId (not string). Returns RecurringDonId. |
| 58 | Donation_CancelRecurring | WRITE | p_RecurringDonId (not p_RecurringId). Ownership check. |

### Donation_CreateCampaign Parameters *(v3.0 corrected)*

| Parameter | Type | Maps to DB Column |
|-----------|------|-------------------|
| p_UserId | INT UNSIGNED | CreatedByUserId |
| p_OrgId | INT UNSIGNED | OrgId |
| p_Title | VARCHAR(200) | **CampaignName** |
| p_Description | TEXT | Description |
| p_GoalAmount | DECIMAL(12,2) | **TargetAmount** |
| p_StartDate | DATE | StartDate. **new in v3.0** |
| p_EndDate | DATE | EndDate |
| p_BannerUrl | VARCHAR(500) | BannerUrl |
| p_CampaignTypeLkpId | INT UNSIGNED | CampaignTypeLkpId. **new in v3.0** |

**Returns:** `IsSuccess INT, Message VARCHAR, CampaignId INT UNSIGNED`

### Donation_Initiate Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | — |
| p_CampaignId | INT UNSIGNED | — |
| p_Amount | DECIMAL(10,2) | — |
| p_Note | TEXT | Donor message |
| p_IsAnonymous | TINYINT(1) | Hides name from leaderboard |
| p_PayMethodLkpId | INT UNSIGNED | FK → LookupValues (PAYMENT_METHOD). **new in v3.0** |

**Returns:** `DonationRef VARCHAR, RazorpayOrderId VARCHAR, Amount DECIMAL, TransactionId INT UNSIGNED`

### Donation_GetReceipt Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_DonationId | VARCHAR(30) | Human-readable donation ID e.g. `DON-2026-000001` |
| p_UserId | INT UNSIGNED | Ownership check |

### Donation_SetupRecurring Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | DonorUserId |
| p_OrgId | INT UNSIGNED | **Required. new in v3.0** |
| p_CampaignId | INT UNSIGNED | Optional |
| p_Amount | DECIMAL(12,2) | — |
| p_FrequencyLkpId | INT UNSIGNED | FK → LookupValues (RECURRING_FREQUENCY). **was p_Frequency VARCHAR in v2.0** |
| p_StartDate | DATE | First charge date. **new in v3.0** |

**Returns:** `IsSuccess INT, Message VARCHAR, RecurringDonId INT UNSIGNED` (**was RecurringId in v2.0**)

### Donation_CancelRecurring Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_RecurringDonId | INT UNSIGNED | **was p_RecurringId in v2.0** |
| p_UserId | INT UNSIGNED | Ownership check |

---

## 23. Stored Procedures — SOS Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 59 | Sos_Trigger | WRITE | No p_SosType — uses p_AlertTypeLkpId. Returns SosIncidentId. |
| 60 | Sos_GetActive | READ (Dynamic) | Returns all ACTIVE incidents with responder count. **new in v3.0** |
| 61 | Sos_Respond | WRITE | No p_Note. Records responder with PENDING approval status. |
| 62 | Sos_UpdateLocation | WRITE | Inserts into SosLocationLogs. Includes p_Accuracy. |
| 63 | Sos_Resolve | WRITE | Uses p_ResolvedByLkpId not ResolutionNote. |

### Sos_Trigger Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | Person in distress |
| p_OrgId | INT UNSIGNED | Optional. NULL for personal SOS. **new in v3.0** |
| p_AlertTypeLkpId | INT UNSIGNED | FK → LookupValues (SOS_ALERT_TYPE). **was p_SosType VARCHAR in v2.0** |
| p_Description | TEXT | Optional |
| p_ApproxLocation | VARCHAR(300) | Optional text description. **new in v3.0** |
| p_Latitude | DECIMAL(10,7) | — |
| p_Longitude | DECIMAL(10,7) | — |

**Returns:** `IsSuccess INT, Message VARCHAR, SosIncidentId INT UNSIGNED` (**was SosId in v2.0**)

### Sos_GetActive Parameters *(new in v3.0)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | Caller (for future permission scoping) |

**Returns:** Dynamic list — SosIncidentId, VictimName, AlertType, Status, Latitude, Longitude, Description, ResponderCount

### Sos_Respond Parameters *(v3.0 corrected — no body)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_SosIncidentId | INT UNSIGNED | **was p_SosId in v2.0** |
| p_UserId | INT UNSIGNED | Responder |

> ⚠️ **No p_Note parameter.** Removed from both SP and C# model (`RespondSosRequest` class is empty).

### Sos_UpdateLocation Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_SosIncidentId | INT UNSIGNED | **was p_SosId in v2.0** |
| p_UserId | INT UNSIGNED | — |
| p_Latitude | DECIMAL(10,7) | — |
| p_Longitude | DECIMAL(10,7) | — |
| p_Accuracy | DECIMAL(8,2) | GPS accuracy in metres. **new in v3.0** |

### Sos_Resolve Parameters *(v3.0 corrected)*

| Parameter | Type | Description |
|-----------|------|-------------|
| p_SosIncidentId | INT UNSIGNED | **was p_SosId in v2.0** |
| p_UserId | INT UNSIGNED | Must be the incident creator |
| p_ResolvedByLkpId | INT UNSIGNED | FK → LookupValues (SOS_RESOLVED_BY). **was p_ResolutionNote TEXT in v2.0** |

---

## 24. Stored Procedures — Notifications Module

| # | SP Name | Type | Key Logic |
|---|---------|------|-----------|
| 64 | Notification_GetList | PAGED (Dynamic) | User's notifications. Most recent first. |
| 65 | Notification_MarkRead | WRITE | Single notification. UserId ownership check. |
| 66 | Notification_MarkAllRead | WRITE | Bulk update. UserId scoped. |
| 67 | Notification_SaveDeviceToken | WRITE | `INSERT ... ON DUPLICATE KEY UPDATE` — upsert per (UserId, Platform). |

### Notification_SaveDeviceToken Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_UserId | INT UNSIGNED | — |
| p_Token | VARCHAR(512) | Firebase FCM token |
| p_Platform | VARCHAR(20) | ANDROID / IOS / WEB |

---

## 25. LookupTypes Reference (42 Types)

| TypeCode | TypeName | Used By |
|----------|----------|---------|
| GENDER | Gender | UserProfiles.GenderLkpId |
| ORG_TYPE | Organisation Type | Organisations.OrgTypeLkpId |
| ORG_CATEGORY | Organisation Category | (reference) |
| ORG_STATUS | Organisation Status | Organisations.StatusLkpId |
| MEMBER_ROLE | Member Role | OrgMembers.RoleLkpId |
| MEMBER_STATUS | Member Status | OrgMembers.StatusLkpId |
| DOCUMENT_TYPE_USER | User Document Type | UserDocuments.DocumentTypeLkpId |
| DOCUMENT_TYPE_ORG | Org Document Type | OrgDocuments.DocumentTypeLkpId |
| EDUCATION | Education Level | UserProfiles.EducationLkpId |
| WORK_EXPERIENCE | Work Experience | UserProfiles.WorkExpLkpId |
| PROJECT_TYPE | Project Type | Projects.ProjectTypeLkpId |
| PROJECT_STATUS | Project Status | Projects.StatusLkpId |
| PROJECT_JOIN_TYPE | Project Join Type | Projects.JoinTypeLkpId |
| APPLICATION_STATUS | Application Status | ProjectApplications.StatusLkpId |
| ATTENDANCE_STATUS | Attendance Status | ProjectAttendance.AttendStatusLkpId |
| POST_TYPE_FEED | Feed Post Type | Posts.PostTypeLkpId |
| POST_TYPE_COMMUNITY | Community Post Type | CommunityPosts.PostTypeLkpId |
| POST_VISIBILITY | Post Visibility | Posts.VisibilityLkpId, CommunityPosts.AudienceLkpId, DonationCampaigns.VisibilityLkpId |
| REPORT_REASON | Report Reason | PostReports.ReasonLkpId |
| SOS_ALERT_TYPE | SOS Alert Type | SosIncidents.AlertTypeLkpId |
| SOS_STATUS | SOS Status | SosIncidents.StatusLkpId |
| RESPONDER_STATUS | Responder Approval Status | SosResponders.ApprovalStatusLkpId |
| PAYMENT_METHOD | Payment Method | DonationTransactions.PayMethodLkpId |
| DONATION_TYPE | Donation Type | DonationTransactions.DonTypeLkpId |
| DONATION_STATUS | Donation Status | DonationTransactions.PayStatusLkpId |
| CAMPAIGN_TYPE | Campaign Type | DonationCampaigns.CampaignTypeLkpId |
| CAMPAIGN_STATUS | Campaign Status | DonationCampaigns.StatusLkpId |
| RECURRING_FREQUENCY | Recurring Frequency | RecurringDonations.FrequencyLkpId |
| RECURRING_STATUS | Recurring Donation Status | RecurringDonations.StatusLkpId |
| WITHDRAWAL_STATUS | Withdrawal Status | WithdrawalRequests.StatusLkpId |
| OTP_PURPOSE | OTP Purpose | OtpTokens.PurposeLkpId |
| NOTIFICATION_TYPE | Notification Type | Notifications.NotifType (text, not FK yet) |
| LOCATION_TYPE | Location Type | Projects.LocationTypeLkpId |
| EMERGENCY_VISIBILITY | Emergency Visibility | UserSafetyPreferences.EmergVisibilityLkpId |
| AUTO_SHARE_DURATION | Auto Share Duration | UserSafetyPreferences.AutoShareDurLkpId |
| BADGE_TYPE | Badge Type | UserBadges.BadgeType (text, not FK yet) |
| KYC_STATUS | KYC Status | OrgDonationSettings.KycStatusLkpId |
| SCHEDULE_TYPE | Schedule Type | Projects.ScheduleTypeLkpId |
| SESSION_STATUS | Session Status | ProjectSessions.SessionStatusLkpId |
| TASK_STATUS | Task Status | CommunityPosts.TaskStatusLkpId |
| MEDIA_TYPE | Media Type | PostMedia.MediaTypeLkpId |
| SOS_RESOLVED_BY | SOS Resolved By | SosIncidents.ResolvedByLkpId |

---

## 26. Relationships Diagram

```
LookupTypes ──< LookupValues
                    │
                    ├── Users.* (no LkpId directly)
                    ├── OtpTokens.PurposeLkpId
                    ├── UserProfiles.GenderLkpId / EducationLkpId / WorkExpLkpId
                    ├── UserDocuments.DocumentTypeLkpId
                    ├── UserSafetyPreferences.EmergVisibilityLkpId / AutoShareDurLkpId
                    ├── Organisations.OrgTypeLkpId / StatusLkpId
                    ├── OrgMembers.RoleLkpId / StatusLkpId
                    ├── OrgDocuments.DocumentTypeLkpId
                    ├── OrgDonationSettings.KycStatusLkpId
                    ├── Projects.ProjectTypeLkpId / LocationTypeLkpId / JoinTypeLkpId / StatusLkpId / ScheduleTypeLkpId
                    ├── ProjectSessions.SessionStatusLkpId
                    ├── ProjectApplications.StatusLkpId
                    ├── ProjectAttendance.AttendStatusLkpId
                    ├── Posts.PostTypeLkpId / VisibilityLkpId
                    ├── PostMedia.MediaTypeLkpId
                    ├── PostReports.ReasonLkpId / StatusLkpId
                    ├── CommunityPosts.PostTypeLkpId / AudienceLkpId / TaskStatusLkpId
                    ├── DonationCampaigns.CampaignTypeLkpId / VisibilityLkpId / StatusLkpId
                    ├── DonationTransactions.PayMethodLkpId / DonTypeLkpId / VisibilityLkpId / PayStatusLkpId
                    ├── RecurringDonations.FrequencyLkpId / StatusLkpId
                    ├── WithdrawalRequests.StatusLkpId
                    ├── SosIncidents.AlertTypeLkpId / StatusLkpId / ResolvedByLkpId
                    └── SosResponders.ApprovalStatusLkpId

Users ──1 UserProfiles          (UNIQUE FK)
Users ──< UserDocuments
Users ──< UserSkills ──< UserSkillRatings
Users ──< UserBadges
Users ──< UserInterests
Users ──1 UserSafetyPreferences
Users ──< OtpTokens
Users ──< RefreshTokens
Users ──< UserDeviceTokens
Users ──< Notifications         (BIGINT PK)

Organisations ──1 OrgDonationSettings
Organisations ──< OrgDocuments
Organisations ──< OrgMembers ──> Users
Organisations ──< Projects
    Projects ──< ProjectSkills
    Projects ──< ProjectSessions
    Projects ──< ProjectApplications ──> Users
    Projects ──< ProjectAttendance   ──> Users + ProjectSessions
    Projects ──< VolunteerCertificates ──> Users

Users ──< Posts ──< PostMedia
               ──< PostLikes
               ──< PostComments
               ──< PostReports

Organisations ──< CommunityPosts ──< PollOptions ──< PollVotes ──> Users

Organisations ──< DonationCampaigns ──< DonationTransactions ──> Users
                                    ──< RecurringDonations    ──> Users
DonationTransactions ──< DonationReceipts

IdSequences — standalone (SequenceName + CurrentYear compound PK)

Users ──< SosIncidents ──< SosResponders (ApprovalStatus FK to LookupValues)
                       ──< SosLocationLogs (BIGINT PK)

AuditLogs — standalone append-only log (BIGINT PK)
PaymentGatewayLogs — standalone webhook log
WithdrawalRequests — Organisations + Users
```

---

## 27. SP Summary Index

| # | SP Name | Module |
|---|---------|--------|
| 1 | Auth_SendOTP | Auth |
| 2 | Auth_VerifyOTP | Auth |
| 3 | Auth_SaveRefreshToken | Auth |
| 4 | Auth_GetRefreshToken | Auth |
| 5 | Auth_RevokeRefreshToken | Auth |
| 6 | Auth_RevokeRefreshTokenById | Auth |
| 7 | User_GetProfile | User |
| 8 | User_GetPublicProfile | User |
| 9 | User_UpdateProfile | User |
| 10 | User_GetSkills | User |
| 11 | User_AddSkill | User |
| 12 | User_RemoveSkill | User |
| 13 | Lookup_GetAllTypes | Lookup |
| 14 | Lookup_GetValuesByType | Lookup |
| 15 | Settings_GetPublic | Settings |
| 16 | Settings_GetByGroup | Settings |
| 17 | Settings_GetAll | Settings |
| 18 | Settings_Update | Settings |
| 19 | Org_Register | Org |
| 20 | Org_GetProfile | Org |
| 21 | Org_Update | Org |
| 22 | Org_List | Org |
| 23 | Org_GetMembers | Org |
| 24 | Org_AddMember | Org |
| 25 | Org_RemoveMember | Org |
| 26 | Project_Create | Projects |
| 27 | Project_GetById | Projects |
| 28 | Project_Update | Projects |
| 29 | Project_List | Projects |
| 30 | Project_AddSession | Projects |
| 31 | Project_GetSessions | Projects |
| 32 | Project_GetSessionQr | Projects |
| 33 | Project_CheckIn | Projects |
| 34 | Application_Apply | Applications |
| 35 | Application_GetByProject | Applications |
| 36 | Application_Review | Applications |
| 37 | Application_GetByUser | Applications |
| 38 | Post_Create | Posts |
| 39 | Post_GetFeed | Posts |
| 40 | Post_GetById | Posts |
| 41 | Post_Like | Posts |
| 42 | Post_Unlike | Posts |
| 43 | Post_AddComment | Posts |
| 44 | Post_GetComments | Posts |
| 45 | Post_Report | Posts |
| 46 | Community_CreatePost | Community |
| 47 | Community_GetFeed | Community |
| 48 | Community_CreatePoll | Community |
| 49 | Community_Vote | Community |
| 50 | Donation_CreateCampaign | Donations |
| 51 | Donation_GetCampaigns | Donations |
| 52 | Donation_GetCampaignById | Donations |
| 53 | Donation_Initiate | Donations |
| 54 | Donation_VerifyPayment | Donations |
| 55 | Donation_GetTransactions | Donations |
| 56 | Donation_GetReceipt | Donations |
| 57 | Donation_SetupRecurring | Donations |
| 58 | Donation_CancelRecurring | Donations |
| 59 | Sos_Trigger | SOS |
| 60 | Sos_GetActive | SOS |
| 61 | Sos_Respond | SOS |
| 62 | Sos_UpdateLocation | SOS |
| 63 | Sos_Resolve | SOS |
| 64 | Notification_GetList | Notifications |
| 65 | Notification_MarkRead | Notifications |
| 66 | Notification_MarkAllRead | Notifications |
| 67 | Notification_SaveDeviceToken | Notifications |

**Total: 67 Stored Procedures across 12 modules.**

---

## 28. Change Management Rules

### ⚠️ Documentation-First Protocol (enforced from v3.0)

**Before any implementation (new feature, bug fix, SP change, model change):**
1. Read `Database_Documentation_v*.md` — understand current schema, SP params, column names.
2. Read `API_Documentation_v*.docx` — understand current endpoints and request/response shapes.
3. Read `NGOConnect_Postman_Collection_v*.json` — understand current request bodies.

**After any implementation:**
1. List exactly what changed (SP params, column names, DAL signatures, routes, request/response bodies).
2. Ask for confirmation before updating each document.
3. Update all three documents in the same session as the code change.

### Mandatory Confirmation Required For

- Creating new tables or columns
- Renaming or removing columns
- Modifying SP parameters (add, remove, rename, type change)
- Changing SP return values
- Adding or removing API endpoints
- Changing request/response model properties

### After Confirmation

1. Increment version number in document header.
2. Add row to Version History table.
3. Run/verify the SQL script.
4. Update `API_Documentation_v{X}.docx` and `Postman_Collection_v{X}.json`.

### File Map

| File | Contains |
|------|----------|
| `Documents/NGOConnect_Complete_Setup_250626.sql` | **Source of truth** — all 42 tables + 67 SPs + seed data in one file |
| `Documents/Database_Documentation_v3.0.md` | This file |
| `Documents/API_Documentation_v3.0.docx` | All API endpoints, request/response shapes |
| `Documents/NGOConnect_Postman_Collection_v3.0.json` | All 69 API requests, variables, test scripts |

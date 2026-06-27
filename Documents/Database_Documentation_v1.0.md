# NGO Connect — Database Documentation Register
**Version:** v1.0
**Date:** 24-Jun-2026
**Database:** MySQL 8.0+
**Charset:** utf8mb4 / utf8mb4_unicode_ci

---

## Version History

| Version | Date        | Change Description                                                   |
|---------|-------------|----------------------------------------------------------------------|
| v1.0    | 24-Jun-2026 | Initial creation — Auth + User groups (5 tables, 12 stored procedures) |

---

## Table of Contents

1. [Database Design Principles](#1-database-design-principles)
2. [Tables](#2-tables)
   - [2.1 Users](#21-users)
   - [2.2 OtpTokens](#22-otptokens)
   - [2.3 RefreshTokens](#23-refreshtokens)
   - [2.4 UserProfiles](#24-userprofiles)
   - [2.5 UserSkills](#25-userskills)
3. [Stored Procedures](#3-stored-procedures)
   - [Auth_SendOTP](#31-auth_sendotp)
   - [Auth_VerifyOTP](#32-auth_verifyotp)
   - [Auth_SaveRefreshToken](#33-auth_saverefreshtoken)
   - [Auth_GetRefreshToken](#34-auth_getrefreshtoken)
   - [Auth_RevokeRefreshToken](#35-auth_revokerefreshtoke)
   - [Auth_RevokeRefreshTokenById](#36-auth_revokerefreshtokenbyid)
   - [User_GetProfile](#37-user_getprofile)
   - [User_GetPublicProfile](#38-user_getpublicprofile)
   - [User_UpdateProfile](#39-user_updateprofile)
   - [User_GetSkills](#310-user_getskills)
   - [User_AddSkill](#311-user_addskill)
   - [User_RemoveSkill](#312-user_removeskill)
4. [Relationships Diagram](#4-relationships-diagram)
5. [Change Management Rules](#5-change-management-rules)

---

## 1. Database Design Principles

| Principle | Rule |
|-----------|------|
| **Primary Keys** | `INT UNSIGNED AUTO_INCREMENT` for standard tables. `BIGINT UNSIGNED` reserved for high-volume append-only tables (AuditLogs, Notifications, SosLocationLogs) |
| **Soft Delete** | All master tables have `IsDeleted`, `DeletedAt`, `DeletedBy`. Never hard-delete. |
| **Naming** | PascalCase for tables and columns. Prefix `p_` for SP parameters. |
| **SP Returns** | WRITE SPs always return `IsSuccess INT, Message VARCHAR`. |
| **Charset** | `utf8mb4` on all tables to support multilingual content and emoji. |
| **Indexes** | Every FK column and every filtered column must be indexed. |
| **Lookups** | All category columns use `INT UNSIGNED FK → LookupValues`. Never TINYINT enums. |
| **Timestamps** | `CreatedAt` = `DEFAULT CURRENT_TIMESTAMP`. `UpdatedAt` = updated by SP, not trigger. |

---

## 2. Tables

### 2.1 Users

**Purpose:** Core authentication table. One row per registered user. Created automatically on first successful OTP verification.

**Script File:** `Database/01_Tables_Auth_User.sql`

#### Columns

| Column       | Data Type      | Length | Nullable | Default           | Description                                    |
|--------------|----------------|--------|----------|-------------------|------------------------------------------------|
| UserId       | INT UNSIGNED   | —      | No       | AUTO_INCREMENT    | Primary key                                    |
| MobileNumber | VARCHAR        | 15     | No       | —                 | Registered mobile number                       |
| CountryCode  | VARCHAR        | 5      | No       | `+91`             | International dialing code                     |
| Email        | VARCHAR        | 255    | Yes      | NULL              | Email address (optional, can be added later)   |
| RoleLkpId    | INT UNSIGNED   | —      | No       | —                 | FK → LookupValues (TypeCode = `USER_ROLE`)     |
| IsActive     | TINYINT(1)     | —      | No       | 1                 | Soft-disable account without deleting          |
| IsVerified   | TINYINT(1)     | —      | No       | 0                 | Set to 1 after first OTP verification          |
| IsDeleted    | TINYINT(1)     | —      | No       | 0                 | Soft delete flag                               |
| DeletedAt    | DATETIME       | —      | Yes      | NULL              | Timestamp of soft deletion                     |
| DeletedBy    | INT UNSIGNED   | —      | Yes      | NULL              | UserId of admin who deleted this account       |
| CreatedAt    | DATETIME       | —      | No       | CURRENT_TIMESTAMP | Account creation timestamp (UTC)               |
| UpdatedAt    | DATETIME       | —      | Yes      | NULL              | Last update timestamp (UTC), set by SP         |

#### Indexes & Constraints

| Name              | Type        | Columns                  | Purpose                                  |
|-------------------|-------------|--------------------------|------------------------------------------|
| PRIMARY           | Primary Key | UserId                   | —                                        |
| uq_mobile_country | Unique      | MobileNumber, CountryCode| Prevent duplicate mobile registrations   |
| uq_email          | Unique      | Email                    | Prevent duplicate email registrations    |

#### Relationships

| FK Column  | References      | On Delete |
|------------|-----------------|-----------|
| RoleLkpId  | LookupValues.LookupValueId | Restrict |

---

### 2.2 OtpTokens

**Purpose:** Stores OTP codes for verification. Each Send OTP request creates one row. Rows are marked `IsUsed=1` after verification or expiry. Never deleted — kept for audit.

**Script File:** `Database/01_Tables_Auth_User.sql`

#### Columns

| Column       | Data Type    | Length | Nullable | Default           | Description                                          |
|--------------|--------------|--------|----------|-------------------|------------------------------------------------------|
| OtpTokenId   | INT UNSIGNED | —      | No       | AUTO_INCREMENT    | Primary key                                          |
| UserId       | INT UNSIGNED | —      | Yes      | NULL              | NULL for unregistered users (first-time OTP)         |
| Recipient    | VARCHAR      | 255    | No       | —                 | Mobile number or email address the OTP was sent to   |
| CountryCode  | VARCHAR      | 5      | No       | `+91`             | Country code captured at time of OTP request         |
| OtpCode      | VARCHAR      | 6      | No       | —                 | 6-digit OTP, plain text (generated in C# layer)      |
| PurposeLkpId | INT UNSIGNED | —      | No       | —                 | FK → LookupValues (TypeCode = `OTP_PURPOSE`)         |
| AttemptCount | TINYINT      | —      | No       | 0                 | Incremented on each wrong attempt. Max = 3.          |
| IsUsed       | TINYINT(1)   | —      | No       | 0                 | 1 = used/expired/invalidated                         |
| IpAddress    | VARCHAR      | 45     | Yes      | NULL              | Requester IP (supports IPv6 up to 45 chars)          |
| ExpiresAt    | DATETIME     | —      | No       | —                 | OTP expiry timestamp (UTC). Default: now + 10 min.   |
| CreatedAt    | DATETIME     | —      | No       | CURRENT_TIMESTAMP | OTP generation timestamp                             |

#### Indexes & Constraints

| Name                    | Type        | Columns               | Purpose                                        |
|-------------------------|-------------|-----------------------|------------------------------------------------|
| PRIMARY                 | Primary Key | OtpTokenId            | —                                              |
| idx_recipient_purpose   | Index       | Recipient, PurposeLkpId | Fast lookup for rate limiting and verification |
| idx_expires             | Index       | ExpiresAt             | For future cleanup jobs                        |

#### Business Rules

- Max 3 OTP requests per Recipient+Purpose per 10 minutes (enforced in `Auth_SendOTP`)
- Max 3 wrong attempts per OTP before lock (enforced in `Auth_VerifyOTP`)
- Previous unused OTPs are invalidated when a new one is generated

---

### 2.3 RefreshTokens

**Purpose:** Stores hashed refresh tokens for session management. Max 5 active sessions per user. Old sessions are auto-revoked when limit is exceeded. Tokens are SHA-256 hashed in C# before storage.

**Script File:** `Database/01_Tables_Auth_User.sql`

#### Columns

| Column         | Data Type    | Length | Nullable | Default           | Description                                          |
|----------------|--------------|--------|----------|-------------------|------------------------------------------------------|
| RefreshTokenId | INT UNSIGNED | —      | No       | AUTO_INCREMENT    | Primary key                                          |
| UserId         | INT UNSIGNED | —      | No       | —                 | FK → Users.UserId                                    |
| Token          | VARCHAR      | 512    | No       | —                 | SHA-256 hashed refresh token (never stored plain)    |
| DeviceInfo     | VARCHAR      | 500    | Yes      | NULL              | Optional device identifier (e.g., "iPhone 15 iOS 17")|
| IpAddress      | VARCHAR      | 45     | Yes      | NULL              | IP at time of token creation                         |
| IsRevoked      | TINYINT(1)   | —      | No       | 0                 | 1 = revoked/logged out. Never deleted.               |
| ExpiresAt      | DATETIME     | —      | No       | —                 | Token expiry (UTC). Default: now + 30 days.          |
| CreatedAt      | DATETIME     | —      | No       | CURRENT_TIMESTAMP | Token creation timestamp                             |

#### Indexes & Constraints

| Name              | Type        | Columns                      | Purpose                          |
|-------------------|-------------|------------------------------|----------------------------------|
| PRIMARY           | Primary Key | RefreshTokenId               | —                                |
| idx_token         | Index       | Token                        | Fast token lookup on every API call |
| idx_user_active   | Index       | UserId, IsRevoked, ExpiresAt | Count active sessions per user   |

#### Relationships

| FK Column | References     | On Delete |
|-----------|----------------|-----------|
| UserId    | Users.UserId   | Cascade   |

#### Business Rules

- Token rotation: old token revoked on every use, new token issued
- Max 5 concurrent sessions per user enforced in `Auth_SaveRefreshToken`

---

### 2.4 UserProfiles

**Purpose:** Extended profile information for each user. One row per user. Created automatically (empty) when user registers via OTP. Updated via `User_UpdateProfile`.

**Script File:** `Database/01_Tables_Auth_User.sql`

#### Columns

| Column         | Data Type    | Length | Nullable | Default           | Description                                        |
|----------------|--------------|--------|----------|-------------------|----------------------------------------------------|
| UserProfileId  | INT UNSIGNED | —      | No       | AUTO_INCREMENT    | Primary key                                        |
| UserId         | INT UNSIGNED | —      | No       | —                 | FK → Users.UserId (UNIQUE — one profile per user)  |
| FirstName      | VARCHAR      | 100    | Yes      | NULL              | First name                                         |
| LastName       | VARCHAR      | 100    | Yes      | NULL              | Last name                                          |
| DisplayName    | VARCHAR      | 200    | Yes      | NULL              | Preferred name. Shown in UI over firstName+lastName|
| About          | TEXT         | —      | Yes      | NULL              | Short bio. Max ~65,000 chars in TEXT type.         |
| GenderLkpId    | INT UNSIGNED | —      | Yes      | NULL              | FK → LookupValues (TypeCode = `GENDER`)            |
| DateOfBirth    | DATE         | —      | Yes      | NULL              | Date only, no time component                       |
| ProfilePhotoUrl| VARCHAR      | 500    | Yes      | NULL              | Azure Blob Storage URL for profile photo           |
| City           | VARCHAR      | 100    | Yes      | NULL              | City of residence                                  |
| State          | VARCHAR      | 100    | Yes      | NULL              | State                                              |
| Country        | VARCHAR      | 100    | Yes      | `India`           | Country of residence                               |
| LinkedInUrl    | VARCHAR      | 500    | Yes      | NULL              | LinkedIn profile URL                               |
| WebsiteUrl     | VARCHAR      | 500    | Yes      | NULL              | Personal or portfolio website                      |
| CreatedAt      | DATETIME     | —      | No       | CURRENT_TIMESTAMP | Profile creation timestamp                         |
| UpdatedAt      | DATETIME     | —      | Yes      | NULL              | Last update timestamp, set by SP                   |

#### Indexes & Constraints

| Name     | Type        | Columns | Purpose                              |
|----------|-------------|---------|--------------------------------------|
| PRIMARY  | Primary Key | UserProfileId | —                              |
| uq_user  | Unique      | UserId  | Enforce one profile per user         |

#### Relationships

| FK Column   | References          | On Delete |
|-------------|---------------------|-----------|
| UserId      | Users.UserId        | Cascade   |
| GenderLkpId | LookupValues.LookupValueId | Restrict |

---

### 2.5 UserSkills

**Purpose:** Skills tagged to a user's profile. Each row is one skill + proficiency level. Unique constraint prevents duplicate skill entries per user. Upsert pattern updates proficiency if skill re-added.

**Script File:** `Database/01_Tables_Auth_User.sql`

#### Columns

| Column          | Data Type    | Length | Nullable | Default           | Description                                      |
|-----------------|--------------|--------|----------|-------------------|--------------------------------------------------|
| UserSkillId     | INT UNSIGNED | —      | No       | AUTO_INCREMENT    | Primary key                                      |
| UserId          | INT UNSIGNED | —      | No       | —                 | FK → Users.UserId                                |
| SkillLkpId      | INT UNSIGNED | —      | No       | —                 | FK → LookupValues (TypeCode = `SKILL`)           |
| ProficiencyLkpId| INT UNSIGNED | —      | No       | —                 | FK → LookupValues (TypeCode = `SKILL_PROFICIENCY`) |
| CreatedAt       | DATETIME     | —      | No       | CURRENT_TIMESTAMP | When skill was added                             |

#### Indexes & Constraints

| Name           | Type        | Columns          | Purpose                                   |
|----------------|-------------|------------------|-------------------------------------------|
| PRIMARY        | Primary Key | UserSkillId      | —                                         |
| uq_user_skill  | Unique      | UserId, SkillLkpId | Prevent duplicate skills per user       |
| idx_user       | Index       | UserId           | Fast lookup of all skills for a user      |

#### Relationships

| FK Column        | References                  | On Delete |
|------------------|-----------------------------|-----------|
| UserId           | Users.UserId                | Cascade   |
| SkillLkpId       | LookupValues.LookupValueId  | Restrict  |
| ProficiencyLkpId | LookupValues.LookupValueId  | Restrict  |

---

## 3. Stored Procedures

**Naming Convention:** `{Module}_{Action}` — e.g., `Auth_SendOTP`, `User_GetProfile`
**Parameter Prefix:** `p_` — e.g., `p_UserId`, `p_OtpCode`
**Script Files:** `Database/02_SP_Auth.sql`, `Database/03_SP_User.sql`

---

### 3.1 Auth_SendOTP

| Field       | Value |
|-------------|-------|
| **Purpose** | Generate and store a new OTP for a recipient. Enforces rate limit (max 3 per 10 min). Invalidates previous unused OTPs for same recipient+purpose. |
| **Tables**  | OtpTokens |
| **Called By** | AuthDal.SendOtpAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter       | Type         | Description                              |
|-----------------|--------------|------------------------------------------|
| p_Recipient     | VARCHAR(255) | Mobile number or email address           |
| p_CountryCode   | VARCHAR(5)   | Country dialing code                     |
| p_OtpCode       | VARCHAR(6)   | 6-digit OTP generated in C# layer        |
| p_PurposeLkpId  | INT UNSIGNED | OTP purpose (Login / Register / etc.)    |
| p_IpAddress     | VARCHAR(45)  | Requester IP address                     |
| p_ExpiryMinutes | INT          | OTP validity window in minutes (default: 10) |

#### Output (Result Set)

| Column    | Type    | Description                       |
|-----------|---------|-----------------------------------|
| IsSuccess | INT     | 1 = OTP stored. 0 = rate limited. |
| Message   | VARCHAR | Human-readable status message     |

#### Sample Execution

```sql
CALL Auth_SendOTP('9876543210', '+91', '482910', 1, '192.168.1.1', 10);
-- Returns: IsSuccess=1, Message='OTP generated successfully.'
-- Rate limited: IsSuccess=0, Message='Too many OTP requests...'
```

---

### 3.2 Auth_VerifyOTP

| Field       | Value |
|-------------|-------|
| **Purpose** | Validate OTP code entered by user. Tracks attempt count. On success: creates user + profile if new, returns UserId and IsNewUser flag. |
| **Tables**  | OtpTokens (R+W), Users (R+W), UserProfiles (W), LookupValues (R) |
| **Called By** | AuthDal.VerifyOtpAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter      | Type         | Description                            |
|----------------|--------------|----------------------------------------|
| p_Recipient    | VARCHAR(255) | Mobile or email (must match Send OTP)  |
| p_OtpCode      | VARCHAR(6)   | OTP code entered by the user           |
| p_PurposeLkpId | INT UNSIGNED | Must match purpose used in Send OTP    |
| p_IpAddress    | VARCHAR(45)  | Requester IP                           |

#### Output (Result Set)

| Column    | Type      | Description                                          |
|-----------|-----------|------------------------------------------------------|
| IsSuccess | INT       | 1 = verified. 0 = failed.                            |
| Message   | VARCHAR   | Result message                                       |
| UserId    | INT UNSIGNED | User ID (0 on failure)                            |
| IsNewUser | TINYINT   | 1 = first-time registration. 0 = existing user.     |

#### Logic Flow

```
1. Fetch latest unused OTP for Recipient + PurposeLkpId
2. IF not found → return IsSuccess=0 (OTP_NOT_FOUND)
3. IF AttemptCount >= 3 → return IsSuccess=0 (MAX_ATTEMPTS)
4. IF NOW() > ExpiresAt → mark used, return IsSuccess=0 (EXPIRED)
5. IF OtpCode mismatch → increment AttemptCount, return IsSuccess=0 (WRONG_OTP)
6. Mark OTP as used
7. Check if user exists by MobileNumber
8. IF new user → INSERT Users + INSERT UserProfiles (empty)
9. IF existing → UPDATE IsVerified=1
10. Return IsSuccess=1, UserId, IsNewUser
```

#### Sample Execution

```sql
CALL Auth_VerifyOTP('9876543210', '482910', 1, '192.168.1.1');
-- New user: IsSuccess=1, UserId=101, IsNewUser=1
-- Existing: IsSuccess=1, UserId=101, IsNewUser=0
-- Wrong OTP: IsSuccess=0, UserId=0, IsNewUser=0
```

---

### 3.3 Auth_SaveRefreshToken

| Field       | Value |
|-------------|-------|
| **Purpose** | Store a new hashed refresh token. Enforces max 5 concurrent sessions per user by auto-revoking the oldest beyond 4. |
| **Tables**  | RefreshTokens |
| **Called By** | AuthDal (after VerifyOTP and RefreshToken) |
| **Returns** | No result set — called via ExecuteNonQueryAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter   | Type         | Description                                       |
|-------------|--------------|---------------------------------------------------|
| p_UserId    | INT UNSIGNED | User ID                                           |
| p_Token     | VARCHAR(512) | SHA-256 hashed refresh token                      |
| p_DeviceInfo| VARCHAR(500) | Optional device identifier                        |
| p_IpAddress | VARCHAR(45)  | IP at token creation                              |
| p_ExpiresAt | DATETIME     | Token expiry timestamp                            |

#### Sample Execution

```sql
CALL Auth_SaveRefreshToken(101, 'hashed_token_here', 'iPhone 15 iOS 17', '192.168.1.1', '2026-07-24 11:00:00');
```

---

### 3.4 Auth_GetRefreshToken

| Field       | Value |
|-------------|-------|
| **Purpose** | Validate a refresh token during token rotation. Returns UserId and Recipient for JWT re-generation. |
| **Tables**  | RefreshTokens (R), Users (R) |
| **Called By** | AuthDal.RefreshTokenAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter | Type         | Description              |
|-----------|--------------|--------------------------|
| p_Token   | VARCHAR(512) | SHA-256 hashed token     |

#### Output (Result Set)

| Column         | Type         | Description                              |
|----------------|--------------|------------------------------------------|
| IsSuccess      | INT          | 1 = valid. 0 = invalid/revoked/expired.  |
| Message        | VARCHAR      | Result message                           |
| UserId         | INT UNSIGNED | User ID (0 on failure)                   |
| Recipient      | VARCHAR      | Email or mobile — used to re-sign JWT    |
| RefreshTokenId | INT UNSIGNED | Token DB ID — used to revoke this token  |

#### Sample Execution

```sql
CALL Auth_GetRefreshToken('sha256_hashed_token');
-- Valid: IsSuccess=1, UserId=101, Recipient='9876543210', RefreshTokenId=55
-- Expired: IsSuccess=0, Message='Refresh token has expired. Please login again.'
```

---

### 3.5 Auth_RevokeRefreshToken

| Field       | Value |
|-------------|-------|
| **Purpose** | Revoke a refresh token by its hash value. Called on user logout. |
| **Tables**  | RefreshTokens |
| **Called By** | AuthDal.RevokeTokenAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter | Type         | Description              |
|-----------|--------------|--------------------------|
| p_Token   | VARCHAR(512) | SHA-256 hashed token     |

#### Output (Result Set)

| Column    | Type    | Description                              |
|-----------|---------|------------------------------------------|
| IsSuccess | INT     | 1 = revoked. 0 = not found.              |
| Message   | VARCHAR | Result message                           |

#### Sample Execution

```sql
CALL Auth_RevokeRefreshToken('sha256_hashed_token');
-- Found: IsSuccess=1, Message='Token revoked successfully.'
-- Not found: IsSuccess=0, Message='Token not found or already revoked.'
```

---

### 3.6 Auth_RevokeRefreshTokenById

| Field       | Value |
|-------------|-------|
| **Purpose** | Revoke a refresh token by its primary key. Used during token rotation to invalidate the old token immediately. |
| **Tables**  | RefreshTokens |
| **Called By** | AuthDal.RevokeRefreshTokenByIdAsync (internal — rotation step) |
| **Returns** | No result set — called via ExecuteNonQueryAsync |
| **Script**  | Database/02_SP_Auth.sql |

#### Input Parameters

| Parameter       | Type         | Description              |
|-----------------|--------------|--------------------------|
| p_RefreshTokenId| INT UNSIGNED | Primary key of the token |

#### Sample Execution

```sql
CALL Auth_RevokeRefreshTokenById(55);
```

---

### 3.7 User_GetProfile

| Field       | Value |
|-------------|-------|
| **Purpose** | Return full user profile including PII (mobile, email). Called ONLY for own-profile endpoint (authenticated). Maps to typed `UserProfileModel` in C#. |
| **Tables**  | Users (R), UserProfiles (R), LookupValues (R) |
| **Called By** | UserDal.GetProfileAsync via ExecuteGetAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter | Type         | Description  |
|-----------|--------------|--------------|
| p_UserId  | INT UNSIGNED | User ID      |

#### Output (Single Row)

| Column           | Type      | Description                              |
|------------------|-----------|------------------------------------------|
| UserId           | INT       | User ID                                  |
| MobileNumber     | VARCHAR   | Registered mobile                        |
| CountryCode      | VARCHAR   | Dialing code                             |
| Email            | VARCHAR   | Email (nullable)                         |
| FirstName        | VARCHAR   | First name (nullable)                    |
| LastName         | VARCHAR   | Last name (nullable)                     |
| DisplayName      | VARCHAR   | Display name (nullable)                  |
| About            | TEXT      | Bio (nullable)                           |
| GenderValueCode  | VARCHAR   | Gender value code e.g. MALE (nullable)   |
| DateOfBirth      | DATE      | Date of birth (nullable)                 |
| ProfilePhotoUrl  | VARCHAR   | Photo URL (nullable)                     |
| City             | VARCHAR   | City (nullable)                          |
| State            | VARCHAR   | State (nullable)                         |
| Country          | VARCHAR   | Country (nullable)                       |
| LinkedInUrl      | VARCHAR   | LinkedIn URL (nullable)                  |
| WebsiteUrl       | VARCHAR   | Website URL (nullable)                   |
| CreatedAt        | DATETIME  | Account creation date                    |
| UpdatedAt        | DATETIME  | Last update (nullable)                   |
| IsProfileComplete| TINYINT   | 1 = firstName AND lastName are filled    |

#### Sample Execution

```sql
CALL User_GetProfile(101);
```

---

### 3.8 User_GetPublicProfile

| Field       | Value |
|-------------|-------|
| **Purpose** | Return publicly visible profile fields. NO PII (no mobile, no email). Maps to DynamicRow in C# — SP can add new columns without code changes. |
| **Tables**  | Users (R), UserProfiles (R), LookupValues (R) |
| **Called By** | UserDal.GetPublicProfileAsync via ExecuteDynamicGetAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter | Type         | Description      |
|-----------|--------------|------------------|
| p_UserId  | INT UNSIGNED | Target user's ID |

#### Output (Single Dynamic Row)

| Column         | Type      | Description                                              |
|----------------|-----------|----------------------------------------------------------|
| UserId         | INT       | User ID                                                  |
| DisplayName    | VARCHAR   | COALESCE(DisplayName, FirstName + ' ' + LastName)        |
| FirstName      | VARCHAR   | First name (nullable)                                    |
| LastName       | VARCHAR   | Last name (nullable)                                     |
| About          | TEXT      | Bio (nullable)                                           |
| Gender         | VARCHAR   | Gender display name from LookupValues (nullable)         |
| ProfilePhotoUrl| VARCHAR   | Photo URL (nullable)                                     |
| City           | VARCHAR   | City (nullable)                                          |
| State          | VARCHAR   | State (nullable)                                         |
| Country        | VARCHAR   | Country (nullable)                                       |
| LinkedInUrl    | VARCHAR   | LinkedIn URL (nullable)                                  |
| WebsiteUrl     | VARCHAR   | Website URL (nullable)                                   |
| MemberSince    | DATETIME  | Account creation date                                    |

> DynamicRow: New columns added to this SP appear in API response automatically. Zero C# changes needed.

#### Sample Execution

```sql
CALL User_GetPublicProfile(101);
```

---

### 3.9 User_UpdateProfile

| Field       | Value |
|-------------|-------|
| **Purpose** | Upsert user profile. Inserts if no profile exists, updates if exists. COALESCE preserves existing values for NULL params (PATCH semantics). |
| **Tables**  | UserProfiles (W), Users (W) |
| **Called By** | UserDal.UpdateProfileAsync via ExecuteWriteAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter     | Type         | Nullable | Description                   |
|---------------|--------------|----------|-------------------------------|
| p_UserId      | INT UNSIGNED | No       | User ID                       |
| p_FirstName   | VARCHAR(100) | Yes      | Null = keep existing value    |
| p_LastName    | VARCHAR(100) | Yes      | Null = keep existing value    |
| p_DisplayName | VARCHAR(200) | Yes      | Null = keep existing value    |
| p_About       | TEXT         | Yes      | Null = keep existing value    |
| p_GenderLkpId | INT UNSIGNED | Yes      | Null = keep existing value    |
| p_DateOfBirth | DATE         | Yes      | Null = keep existing value    |
| p_City        | VARCHAR(100) | Yes      | Null = keep existing value    |
| p_State       | VARCHAR(100) | Yes      | Null = keep existing value    |
| p_Country     | VARCHAR(100) | Yes      | Null = keep existing value    |
| p_LinkedInUrl | VARCHAR(500) | Yes      | Null = keep existing value    |
| p_WebsiteUrl  | VARCHAR(500) | Yes      | Null = keep existing value    |

#### Output (Result Set)

| Column    | Type    | Description     |
|-----------|---------|-----------------|
| IsSuccess | INT     | Always 1        |
| Message   | VARCHAR | Success message |

#### Sample Execution

```sql
CALL User_UpdateProfile(101, 'Gaurav', 'Shukla', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 'India', NULL, NULL);
-- Only FirstName, LastName, City, State, Country updated. All NULL params keep existing DB values.
```

---

### 3.10 User_GetSkills

| Field       | Value |
|-------------|-------|
| **Purpose** | Return all skills for a user with lookup names joined. Called via DataReader in C# for speed — streamed, not buffered. |
| **Tables**  | UserSkills (R), LookupValues (R) — joined twice for skill name and proficiency name |
| **Called By** | UserDal.GetSkillsAsync via ExecuteReaderListAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter | Type         | Description  |
|-----------|--------------|--------------|
| p_UserId  | INT UNSIGNED | User ID      |

#### Output (Multiple Rows)

| Column          | Type    | Description                    |
|-----------------|---------|--------------------------------|
| UserSkillId     | INT     | Skill entry primary key        |
| SkillLkpId      | INT     | Skill LookupValueId            |
| SkillName       | VARCHAR | Skill display name             |
| ProficiencyLkpId| INT     | Proficiency LookupValueId      |
| ProficiencyName | VARCHAR | Proficiency display name       |

#### Sample Execution

```sql
CALL User_GetSkills(101);
-- Returns all skills for user 101, ordered alphabetically by SkillName
```

---

### 3.11 User_AddSkill

| Field       | Value |
|-------------|-------|
| **Purpose** | Add a skill to user profile (INSERT) or update proficiency if skill already exists (UPDATE). Upsert pattern — safe to call repeatedly. |
| **Tables**  | UserSkills (R+W) |
| **Called By** | UserDal.AddSkillAsync via ExecuteWriteAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter        | Type         | Description                                        |
|------------------|--------------|----------------------------------------------------|
| p_UserId         | INT UNSIGNED | User ID                                            |
| p_SkillLkpId     | INT UNSIGNED | Skill LookupValueId (TypeCode = SKILL)             |
| p_ProficiencyLkpId | INT UNSIGNED | Proficiency LookupValueId (TypeCode = SKILL_PROFICIENCY) |

#### Output (Result Set)

| Column    | Type    | Description                                           |
|-----------|---------|-------------------------------------------------------|
| IsSuccess | INT     | Always 1                                              |
| Message   | VARCHAR | 'Skill added successfully.' or 'Skill proficiency updated successfully.' |

#### Sample Execution

```sql
-- Add new skill
CALL User_AddSkill(101, 42, 88);
-- Returns: IsSuccess=1, Message='Skill added successfully.'

-- Update existing skill proficiency
CALL User_AddSkill(101, 42, 87);
-- Returns: IsSuccess=1, Message='Skill proficiency updated successfully.'
```

---

### 3.12 User_RemoveSkill

| Field       | Value |
|-------------|-------|
| **Purpose** | Remove a skill from user's profile. Ownership check (UserId) ensures users cannot delete other users' skills. |
| **Tables**  | UserSkills (W) |
| **Called By** | UserDal.RemoveSkillAsync via ExecuteWriteAsync |
| **Script**  | Database/03_SP_User.sql |

#### Input Parameters

| Parameter     | Type         | Description                            |
|---------------|--------------|----------------------------------------|
| p_UserId      | INT UNSIGNED | Must match skill owner — ownership check |
| p_UserSkillId | INT UNSIGNED | UserSkillId to delete                  |

#### Output (Result Set)

| Column    | Type    | Description                                          |
|-----------|---------|------------------------------------------------------|
| IsSuccess | INT     | 1 = deleted. 0 = not found or not owned.             |
| Message   | VARCHAR | 'Skill removed successfully.' or 'Skill not found or you do not own this skill.' |

#### Sample Execution

```sql
CALL User_RemoveSkill(101, 5);
-- Found and owned: IsSuccess=1, Message='Skill removed successfully.'
-- Not found/not owned: IsSuccess=0, Message='Skill not found or you do not own this skill.'
```

---

## 4. Relationships Diagram

```
LookupTypes ──< LookupValues
                    │
                    ├── Users.RoleLkpId
                    ├── OtpTokens.PurposeLkpId
                    ├── UserProfiles.GenderLkpId
                    ├── UserSkills.SkillLkpId
                    └── UserSkills.ProficiencyLkpId

Users ──< OtpTokens         (UserId, nullable — NULL for new users)
Users ──< RefreshTokens     (UserId)
Users ──1 UserProfiles      (UserId, UNIQUE — one profile per user)
Users ──< UserSkills        (UserId)
```

---

## 5. Change Management Rules

Before any database change, the following process **must** be followed:

### Before Making Any Change

1. Review this document for existing tables, columns, SPs.
2. Verify: Does the table/column/SP already exist?
3. Assess impact on existing SPs, DALs, and APIs.
4. Prepare a Change Summary with: existing structure, proposed change, impact analysis, version increment.
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

1. Update this documentation file with new version number.
2. Add a row to the Version History table.
3. Generate and run the SQL script.
4. Update `API_Documentation_v{X}.docx` if the change affects API response shapes.

---

*Next update: v1.1 — LookupTypes, LookupValues, Settings tables + Organisation module tables*

# NGOConnect Database Documentation v4.3

**Database:** MySQL 8.0+  
**Version:** 4.3  
**Tables:** 50  
**Stored Procedures:** 120  
**Generated:** 2026-07-06  

**Changes from v4.2 (v4.3):**

- **Project_Create / Project_Update** — Rebuilt to match C# DAL params: `p_UserId`, `p_Title`, `p_ScheduleType VARCHAR(20)`, `p_RecurrenceDays VARCHAR(100)`, `p_StartTime/EndTime VARCHAR(10)`, `p_DurationMinutes`, `p_LocationName`, `p_Address`, `p_IsDraft` (32 params). Removed old `p_ScheduleTypeLkpId`, `p_AddressLine`, `p_Landmark` naming.
- **Project_List** — Added `ScheduleType` (derived: `ptv.ValueCode`), `LocationName` (`p.Landmark`), `Address` (`p.AddressLine`), `ApprovedCount` (correlated subquery), `StatusCode`. Admin querying own org now sees all projects (not just `IsPublic=1`).
- **Sos_GetById** — Rebuilt: removed `JOIN Users` (caused 0-row returns); all JOINs now LEFT; added `AlertTypeName`, `StatusName` return columns; responders list includes `ProfilePhoto`, `ApprovalStatusName`.
- **Community_GetFeed** — Added `PollOptionsJson` (JSON_ARRAYAGG correlated subquery with `voteCount` + `isVoted`), `RoleName` (author's org role), `TimeAgo` (human-readable elapsed). DAL post-processes `PollOptionsJson` → `pollOptions` array.
- **Sos_GetOrgAlerts** — **NEW SP** — `p_OrgId, p_UserId, p_Limit`. Returns all incidents for org (active + resolved + cancelled) with `IsActive` flag and `MyApprovalStatus` (PENDING/APPROVED/REJECTED/NULL) per viewer.
- **Sos_DeclineResponder** — **NEW SP** — `p_SosIncidentId, p_SosResponderId, p_DeclinedBy`. Victim declines pending responder — sets `ApprovalStatusLkpId` to REJECTED. Validates caller is incident owner.
- **LookupValues (ORG_TYPE)** — Added 6 new values: NGO (4), FOUNDATION (5), CHARITABLE_INSTITUTION (6), RELIGIOUS_TRUST (7), CSR_FOUNDATION (8), EDUCATIONAL_TRUST (9).
- **DynamicRow.cs** — Added `public bool Remove(string key)` method for post-processing intermediate SP columns.
- **CommunityDal.GetFeedAsync** — Post-processes `PollOptionsJson` → typed `pollOptions` array with computed `votePct`; removes raw key before returning.

**Changes from v4.1 (v4.2):**

- **Community Likes & Comments** — 3 new tables: `CommunityPostLikes`, `CommunityPostComments`, `CommunityCommentLikes`
- **CommunityPosts** — Added `LikeCount INT UNSIGNED`, `CommentCount INT UNSIGNED`, `AcknowledgeCount INT UNSIGNED` denormalized count columns
- **Community SPs** — 4 new SPs (LikePost, AddComment, GetComments, LikeComment); 4 replaced SPs (GetFeed now passes `p_UserId` for `IsLiked`; CreatePost fixed to 6 params; CreatePoll fixed to 5 params; Vote fixed to 3 params)
- **SosIncidents** — Fixed: column is `UserId` (not `VictimUserId`); added `IsDeleted TINYINT(1)`, `CancelledAt DATETIME`
- **SOS SPs** — New: `Sos_GetMyActive(p_UserId)` returns 2 result sets (incident row + responders list)
- **Group 5 Content** — 9 → 12 tables

**Changes from v4.0 (v4.1):**

*Section 1–4 (v4.1 initial)*
- `UserProfiles`: Added `VolunteerExp TEXT NULL` column (previous NGO/volunteer experience)
- `UserSafetyPreferences`: Corrected column names to match actual DB schema; added `EmergencyContactName`, `EmergencyContactPhone`, `EmergencyContactRelation`
- `User_GetProfile` SP: Now returns `VolunteerExp`, `CountryCode`, `IsVerified`, `UpdatedAt`, `IsProfileComplete`, `GenderLkpId`, `EducationLkpId`, `WorkExpLkpId`
- `User_UpdateProfile` SP: Added `p_VolunteerExp` (now 19 params)
- `User_UpdateSafetyPrefs` SP: Added 3 emergency contact params (now 8 params)
- `Lookup_GetValueByCode` SP: Now returns `OrderNo`, `IsDefault` in addition to existing columns
- Auth SPs: Documented correctly from `02_SP_Auth.sql` source of truth
- `UserInterests` table: Redesigned — now uses `InterestLkpId INT FK→LookupValues` (was free-text); `User_SaveInterests` SP rewrites full list from JSON array
- Settings: Added 3 upload settings (`UPLOAD_MAX_SIZE_MB`, `UPLOAD_ALLOWED_TYPES`, `UPLOAD_BASE_URL`)

*Section 5 (v4.1 User GET SPs — new)*
- 5 new read SPs: `User_GetSafetyPrefs`, `User_GetInterests`, `User_GetMyOrgs`, `User_GetBadges`, `User_GetImpact`

*Section 6 (v4.1 Org module fixes)*
- `Organisations`: Added `ContactPerson VARCHAR(100) NULL` column
- `Org_Register` SP: Fixed `p_RegistrationNo` (was `p_RegistrationNumber`); added `p_Category`, `p_ContactPerson`, `p_About` params (now 19 params)
- `Org_Update` SP: Added `p_Category`, `p_ContactPerson`, `p_About`, `p_Country` params (now 18 params)
- `Org_GetProfile` SP: Now returns `OrgTypeLkpId`, `StatusLkpId`, `ContactPerson`, `Category` for edit form pre-fill
- `Org_GetDashboard` SP: New — returns 7 KPI fields for Admin Dashboard (s-admin screen)

*Section 7 (v4.1 Explore + Admin Donor/Volunteer SPs — new)*
- `Organisations`: Added `AvgRating DECIMAL(3,2)`, `RatingCount INT UNSIGNED`, `Latitude DECIMAL(10,7)`, `Longitude DECIMAL(10,7)`
- `Org_List` SP: Fixed — now filters by `p_Keyword` + `p_Category` (not `p_OrgTypeLkpId`); always returns APPROVED orgs only; returns `AvgRating`, `Latitude`, `Longitude`
- 10 new SPs: `Org_ListRecommended`, `Campaign_ListPublicTrending`, `Org_GetDonationDashboard`, `Org_GetDonors`, `Org_GetTransactions`, `Org_GetVolunteerProfile`, `Org_GetMemberImpact`, `Org_UpdateMemberRole`, `UserBadge_Award` (updated), `Attendance_ExcuseNoShow`

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

## Tables (47 Total)

### Group 1 — Auth (3 tables)

#### Users
| Column | Type | Notes |
|---|---|---|
| UserId | INT UNSIGNED PK AUTO_INCREMENT | |
| Mobile | VARCHAR(20) UNIQUE NOT NULL | |
| Email | VARCHAR(255) UNIQUE NULL | |
| CountryCode | VARCHAR(5) DEFAULT '+91' | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| IsActive | TINYINT(1) DEFAULT 1 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

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
| ProfilePhoto | VARCHAR(500) NULL | Azure Blob URL |
| Occupation | VARCHAR(150) NULL | |
| Organisation | VARCHAR(200) NULL | Employer/company name |
| VolunteerExp | TEXT NULL | **v4.1** Previous NGO/volunteer experience (free text) |
| EducationLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| FieldOfStudy | VARCHAR(150) NULL | v4.0 |
| WorkExpLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| AddressLine1 | VARCHAR(200) NULL | v4.0 |
| AddressLine2 | VARCHAR(200) NULL | v4.0 |
| Pincode | VARCHAR(20) NULL | v4.0 |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| ImpactScore | INT DEFAULT 0 | |
| ReliabilityPct | DECIMAL(5,2) DEFAULT 0.00 | |
| IsProfileComplete | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

#### UserDocuments
| Column | Type | Notes |
|---|---|---|
| UserDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | LookupType: DOC_TYPE_USER |
| FileUrl | VARCHAR(500) NOT NULL | Permanent URL from /media/upload |
| FileName | VARCHAR(255) NOT NULL | Stored filename (date_userId_guid.ext) |
| FileSizeKb | INT UNSIGNED NOT NULL | File size in KB |
| IsVerified | TINYINT(1) DEFAULT 0 | Admin-verified document |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | Same as UserId |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### UserSkills
| Column | Type | Notes |
|---|---|---|
| UserSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| SkillName | VARCHAR(100) NOT NULL | |
| AvgRating | DECIMAL(3,2) DEFAULT 0.00 | Denormalized |
| RatingCount | INT DEFAULT 0 | Denormalized |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, SkillName) | |

#### UserSkillRatings
| Column | Type | Notes |
|---|---|---|
| SkillRatingId | INT UNSIGNED PK AUTO_INCREMENT | |
| RaterUserId | INT UNSIGNED FK→Users | |
| RatedUserId | INT UNSIGNED FK→Users | |
| UserSkillId | INT UNSIGNED FK→UserSkills | |
| Rating | TINYINT NOT NULL | 1–5 |
| Review | VARCHAR(500) NULL | |
| ProjectId | INT UNSIGNED FK→Projects NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (RaterUserId, UserSkillId) | ON DUPLICATE KEY UPDATE |

#### UserBadges
| Column | Type | Notes |
|---|---|---|
| UserBadgeId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| BadgeLkpId | INT UNSIGNED FK→LookupValues | |
| AwardedBy | INT UNSIGNED FK→Users NULL | |
| ProjectId | INT UNSIGNED FK→Projects NULL | |
| AwardedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, BadgeLkpId) | INSERT IGNORE |

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
| EmergVisibilityLkpId | INT UNSIGNED FK→LookupValues NOT NULL | Who can see SOS alert (SOS_VISIBILITY lookup) |
| AutoShareDurLkpId | INT UNSIGNED FK→LookupValues NOT NULL | Auto-stop location sharing duration (SOS_SHARE_DUR lookup) |
| AllowLocDuringSos | TINYINT(1) DEFAULT 1 | Share live location during active SOS |
| AllowLocDuringProj | TINYINT(1) DEFAULT 1 | Share live location during project sessions |
| EmergencyContactName | VARCHAR(100) NULL | **v4.1** Emergency contact full name |
| EmergencyContactPhone | VARCHAR(20) NULL | **v4.1** Emergency contact phone number |
| EmergencyContactRelation | VARCHAR(50) NULL | **v4.1** Relationship (e.g. Spouse, Parent) |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME ON UPDATE CURRENT_TIMESTAMP | |

---

### Group 3 — Organisations (4 tables)

#### Organisations
| Column | Type | Notes |
|---|---|---|
| OrgId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgName | VARCHAR(300) NOT NULL | |
| RegNumber | VARCHAR(100) UNIQUE NULL | Registration number (column name: RegNumber, not RegistrationNumber) |
| OrgTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | LookupType: ORG_TYPE |
| Category | VARCHAR(100) NULL | Category tag shown on NGO cards (e.g. "Education", "Environment"); matches ORG_CATEGORY ValueCode |
| ContactPerson | VARCHAR(100) NULL | **v4.1 Section 6** Contact person name (Step 2 of create wizard) |
| About | TEXT NULL | Short description of the NGO |
| Mission | TEXT NULL | |
| Vision | TEXT NULL | |
| LogoUrl | VARCHAR(500) NULL | Azure Blob URL |
| AddressLine1 | VARCHAR(300) NULL | |
| AddressLine2 | VARCHAR(300) NULL | |
| Pincode | VARCHAR(20) NULL | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| Website | VARCHAR(300) NULL | |
| ContactEmail | VARCHAR(255) NULL | |
| ContactPhone | VARCHAR(20) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | LookupType: ORG_STATUS — PENDING/APPROVED/REJECTED/SUSPENDED |
| MemberCount | INT DEFAULT 0 | Denormalized — updated by membership SPs |
| AvgRating | DECIMAL(3,2) NOT NULL DEFAULT 0.00 | **v4.1 Section 7** Average NGO rating (0–5); updated on each rating write |
| RatingCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.1 Section 7** Number of ratings contributing to AvgRating |
| Latitude | DECIMAL(10,7) NULL | **v4.1 Section 7** NGO pin latitude; returned to client for distance calc |
| Longitude | DECIMAL(10,7) NULL | **v4.1 Section 7** NGO pin longitude |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### OrgDocuments
| Column | Type | Notes |
|---|---|---|
| OrgDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| UploadedBy | INT UNSIGNED FK→Users | Admin/staff who uploaded |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | LookupType: DOC_TYPE_ORG |
| FileUrl | VARCHAR(500) NOT NULL | Permanent URL from /media/upload |
| FileName | VARCHAR(255) NOT NULL | Stored filename (date_userId_guid.ext) |
| IsVerified | TINYINT(1) DEFAULT 0 | Admin-verified document |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | Same as UploadedBy |
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
| RequestMessage | TEXT NULL | v4.0 |
| CanPost | TINYINT(1) DEFAULT 1 | v4.0 |
| CanComment | TINYINT(1) DEFAULT 1 | v4.0 |
| CanCommunityPost | TINYINT(1) DEFAULT 1 | v4.0 |
| MaxPostsPerDay | TINYINT DEFAULT 10 | v4.0 |
| LocationSharingLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| RequestedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| JoinedAt | DATETIME NULL | Set when approved |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (OrgId, UserId) | |

#### OrgDonationSettings (legacy, kept for compatibility)
| Column | Type | Notes |
|---|---|---|
| OrgDonSettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED UNIQUE FK→Organisations | |
| RazorpayKeyId | VARCHAR(200) NULL | |
| RazorpayKeySecret | VARCHAR(200) NULL | Encrypted |
| WithdrawalEnabled | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

---

### Group 4 — Projects (6 tables)

#### Projects
| Column | Type | Notes |
|---|---|---|
| ProjectId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| Title | VARCHAR(200) NOT NULL | |
| Description | TEXT NULL | |
| ProjectTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| JoinTypeLkpId | INT UNSIGNED FK→LookupValues NULL | OPEN/APPROVAL/INVITE |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | DRAFT/ACTIVE/COMPLETED/CANCELLED |
| MaxVolunteers | INT NULL | |
| MinAge | TINYINT NULL | |
| MaxAge | TINYINT NULL | |
| IsPublic | TINYINT(1) DEFAULT 1 | |
| StartDate | DATE NULL | |
| EndDate | DATE NULL | |
| ScheduleType | VARCHAR(20) NULL | ONE_TIME/RECURRING/ONGOING |
| RecurrenceDays | VARCHAR(100) NULL | Mon,Wed,Fri |
| StartTime | TIME NULL | |
| EndTime | TIME NULL | |
| DurationMinutes | INT NULL | |
| LocationTypeLkpId | INT UNSIGNED FK→LookupValues NULL | IN_PERSON/ONLINE/HYBRID |
| LocationName | VARCHAR(200) NULL | |
| Address | VARCHAR(500) NULL | |
| Latitude | DECIMAL(10,7) NULL | |
| Longitude | DECIMAL(10,7) NULL | |
| MeetingLink | VARCHAR(500) NULL | |
| GenderRestriction | VARCHAR(20) NULL | ANY/MALE/FEMALE |
| RequiresApproval | TINYINT(1) DEFAULT 0 | |
| CoverImageUrl | VARCHAR(500) NULL | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| AppliedCount | INT DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### ProjectSkills
| Column | Type | Notes |
|---|---|---|
| ProjectSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SkillName | VARCHAR(100) NOT NULL | |
| IsRequired | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### ProjectSessions
| Column | Type | Notes |
|---|---|---|
| SessionId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SessionDate | DATE NOT NULL | |
| StartTime | TIME NOT NULL | |
| EndTime | TIME NOT NULL | |
| MaxVolunteers | INT NULL | |
| QrCode | VARCHAR(500) NULL | UUID token |
| QrExpiresAt | DATETIME NULL | |
| SessionStatusLkpId | INT UNSIGNED FK→LookupValues NULL | UPCOMING/ACTIVE/COMPLETED |
| AttendeeCount | INT DEFAULT 0 | Denormalized |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### ProjectApplications
| Column | Type | Notes |
|---|---|---|
| ApplicationId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| UserId | INT UNSIGNED FK→Users | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| Note | TEXT NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| AdminNotes | TEXT NULL | |
| AppliedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (ProjectId, UserId) | |

#### ProjectAttendance
| Column | Type | Notes |
|---|---|---|
| AttendanceId | INT UNSIGNED PK AUTO_INCREMENT | |
| SessionId | INT UNSIGNED FK→ProjectSessions | |
| UserId | INT UNSIGNED FK→Users | |
| CheckInAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| CheckInMethod | VARCHAR(20) DEFAULT 'QR' | |
| UNIQUE | (SessionId, UserId) | |

#### VolunteerCertificates
| Column | Type | Notes |
|---|---|---|
| CertificateId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| ProjectId | INT UNSIGNED FK→Projects | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CertificateUrl | VARCHAR(500) NULL | Azure Blob |
| IssuedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| HoursLogged | INT NULL | |
| UNIQUE | (UserId, ProjectId) | |

---

### Group 5 — Content (12 tables)

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
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### PostMedia
| Column | Type | Notes |
|---|---|---|
| PostMediaId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| MediaUrl | VARCHAR(500) NOT NULL | |
| MediaTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| SortOrder | TINYINT DEFAULT 0 | |

#### PostLikes
| Column | Type | Notes |
|---|---|---|
| PostLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| UserId | INT UNSIGNED FK→Users | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PostId, UserId) | |

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
| ReportedBy | INT UNSIGNED FK→Users | |
| ReasonLkpId | INT UNSIGNED FK→LookupValues | |
| Details | TEXT NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NULL | PENDING/REVIEWED/DISMISSED |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
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
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.2** Denormalized — updated by Community_LikePost SP |
| CommentCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.2** Denormalized — updated by Community_AddComment SP |
| AcknowledgeCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.2** Denormalized — updated by Community_AcknowledgePost SP |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CommunityPostLikes
**v4.2 — New table**

| Column | Type | Notes |
|---|---|---|
| CommunityPostLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (CommunityPostId, UserId) | Prevents duplicate likes; INSERT…ON DUPLICATE KEY DELETE for toggle |

**Indexes:** `idx_cpl_post (CommunityPostId)`, `idx_cpl_user (UserId)`

#### CommunityPostComments
**v4.2 — New table**

| Column | Type | Notes |
|---|---|---|
| CommunityCommentId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| Content | TEXT NOT NULL | Max 2000 chars enforced at API layer |
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized — updated by Community_LikeComment SP |
| IsDeleted | TINYINT(1) DEFAULT 0 | Soft delete — deleted comments hidden but count preserved |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

**Indexes:** `idx_cpc_post (CommunityPostId)`, `idx_cpc_user (UserId)`

#### CommunityCommentLikes
**v4.2 — New table**

| Column | Type | Notes |
|---|---|---|
| CommunityCommentLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityCommentId | INT UNSIGNED FK→CommunityPostComments NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (CommunityCommentId, UserId) | Prevents duplicate likes; toggle via INSERT…ON DUPLICATE KEY DELETE |

**Indexes:** `idx_ccl_comment (CommunityCommentId)`, `idx_ccl_user (UserId)`

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
| NotificationId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — billions at scale |
| UserId | INT UNSIGNED FK→Users | |
| TypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| Title | VARCHAR(200) NOT NULL | |
| Body | TEXT NULL | |
| EntityType | VARCHAR(50) NULL | POST/PROJECT/SOS/DONATION |
| EntityId | INT UNSIGNED NULL | Related entity ID |
| IsRead | TINYINT(1) DEFAULT 0 | |
| ReadAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 6 — Safety / SOS (3 tables)

#### SosIncidents
| Column | Type | Notes |
|---|---|---|
| SosIncidentId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users NOT NULL | **v4.2 fix**: was `VictimUserId` — actual column name is `UserId` |
| OrgId | INT UNSIGNED FK→Organisations NULL | Org the victim belongs to — used to notify members |
| AlertTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | LookupType: SOS_ALERT_TYPE |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | LookupType: SOS_STATUS — ACTIVE/RESOLVED/CANCELLED |
| Description | TEXT NULL | Optional free-text description of the situation |
| ApproxLocation | VARCHAR(300) NULL | Human-readable location (e.g. "Koregaon Park, Pune") |
| Latitude | DECIMAL(10,7) NULL | Initial GPS latitude at trigger time |
| Longitude | DECIMAL(10,7) NULL | Initial GPS longitude at trigger time |
| CancelReason | TEXT NULL | Populated by Sos_Cancel SP |
| ResolvedByLkpId | INT UNSIGNED FK→LookupValues NULL | Kept for audit; no longer set by backend SP (v4.2 fix) |
| ResolvedAt | DATETIME NULL | Set by Sos_Resolve SP |
| CancelledAt | DATETIME NULL | **v4.2** Set by Sos_Cancel SP |
| IsDeleted | TINYINT(1) DEFAULT 0 | **v4.2** Soft delete |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

**Indexes:** `idx_sos_user (UserId)`, `idx_sos_org (OrgId)`, `idx_sos_status (StatusLkpId)`

#### SosResponders
| Column | Type | Notes |
|---|---|---|
| SosResponderId | INT UNSIGNED PK AUTO_INCREMENT | |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | Responder |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| CanViewLocation | TINYINT(1) DEFAULT 0 | v4.0 |
| RespondedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (SosIncidentId, UserId) | |

#### SosLocationLogs
| Column | Type | Notes |
|---|---|---|
| SosLocationLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — every 10s |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | |
| Latitude | DECIMAL(10,7) NOT NULL | |
| Longitude | DECIMAL(10,7) NOT NULL | |
| Accuracy | DECIMAL(8,2) NULL | Metres |
| LoggedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 7 — Donations (6 tables)

#### DonationCampaigns
| Column | Type | Notes |
|---|---|---|
| CampaignId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CreatedBy | INT UNSIGNED FK→Users | |
| CampaignName | VARCHAR(200) NOT NULL | SP param: p_Title |
| Description | TEXT NULL | |
| CampaignTypeLkpId | INT UNSIGNED FK→LookupValues | |
| TargetAmount | DECIMAL(12,2) NOT NULL | SP param: p_GoalAmount |
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
| Amount | DECIMAL(10,2) NOT NULL | |
| PayMethodLkpId | INT UNSIGNED FK→LookupValues | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/COMPLETED/FAILED/REFUNDED |
| RazorpayOrderId | VARCHAR(200) NULL | |
| RazorpayPaymentId | VARCHAR(200) NULL | |
| Note | TEXT NULL | |
| IsAnonymous | TINYINT(1) DEFAULT 0 | |
| PaidAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### RecurringDonations
| Column | Type | Notes |
|---|---|---|
| RecurringDonId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| Amount | DECIMAL(10,2) NOT NULL | |
| FrequencyLkpId | INT UNSIGNED FK→LookupValues | WEEKLY/MONTHLY/QUARTERLY/YEARLY |
| StartDate | DATE NOT NULL | |
| NextRunAt | DATETIME NULL | |
| IsActive | TINYINT(1) DEFAULT 1 | |
| PausedAt | DATETIME NULL | v4.0 |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### DonationReceipts
| Column | Type | Notes |
|---|---|---|
| ReceiptId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationId | INT UNSIGNED UNIQUE FK→DonationTransactions | |
| ReceiptNumber | VARCHAR(50) UNIQUE | |
| ReceiptUrl | VARCHAR(500) NULL | Azure Blob |
| ReceiptType | VARCHAR(20) DEFAULT '80G' | |
| GeneratedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### WithdrawalRequests
| Column | Type | Notes |
|---|---|---|
| WithdrawalId | INT UNSIGNED PK AUTO_INCREMENT | |
| WithdrawalRef | VARCHAR(20) UNIQUE | WDR-2026-0001 via IdSequences |
| OrgId | INT UNSIGNED FK→Organisations | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| RequestedBy | INT UNSIGNED FK→Users | |
| Amount | DECIMAL(10,2) NOT NULL | |
| BankAccount | VARCHAR(200) NOT NULL | |
| IfscCode | VARCHAR(20) NOT NULL | |
| AccountHolder | VARCHAR(200) NOT NULL | |
| Purpose | VARCHAR(500) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| AdminNotes | TEXT NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### PaymentGatewayLogs
| Column | Type | Notes |
|---|---|---|
| GatewayLogId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationId | INT UNSIGNED FK→DonationTransactions NULL | |
| GatewayName | VARCHAR(50) DEFAULT 'Razorpay' | |
| EventType | VARCHAR(100) NULL | |
| Payload | JSON NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 8 — System (2 tables)

#### AuditLogs
| Column | Type | Notes |
|---|---|---|
| AuditLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — every write |
| UserId | INT UNSIGNED NULL | |
| Action | VARCHAR(100) NOT NULL | CREATE/UPDATE/DELETE |
| EntityName | VARCHAR(100) NOT NULL | |
| EntityId | INT UNSIGNED NULL | |
| OldValue | JSON NULL | |
| NewValue | JSON NULL | |
| IpAddress | VARCHAR(45) NULL | |
| UserAgent | VARCHAR(500) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### IdSequences
| Column | Type | Notes |
|---|---|---|
| SequenceId | INT UNSIGNED PK AUTO_INCREMENT | |
| PrefixCode | VARCHAR(10) UNIQUE NOT NULL | DON, WDR, REC |
| CurrentYear | SMALLINT NOT NULL | |
| LastNumber | INT DEFAULT 0 | |
| Padding | TINYINT DEFAULT 6 | Leading zeros |

> **Readable ID format:** `{PREFIX}-{YEAR}-{PADDED_NUMBER}`  
> DON-2026-000001, WDR-2026-0001, REC-2026-0001

---

### Group 9 — Lookup (2 tables)

#### LookupTypes
| Column | Type | Notes |
|---|---|---|
| LookupTypeId | INT UNSIGNED PK AUTO_INCREMENT | |
| TypeCode | VARCHAR(50) UNIQUE NOT NULL | GENDER, ORG_TYPE, etc. |
| TypeName | VARCHAR(200) NOT NULL | |
| Description | TEXT NULL | |
| IsSystem | TINYINT(1) DEFAULT 1 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### LookupValues
| Column | Type | Notes |
|---|---|---|
| LookupValueId | INT UNSIGNED PK AUTO_INCREMENT | |
| LookupTypeId | INT UNSIGNED FK→LookupTypes | |
| ValueCode | VARCHAR(50) NOT NULL | MALE, FEMALE, NGO, etc. |
| ValueName | VARCHAR(200) NOT NULL | Display label |
| Description | TEXT NULL | |
| OrderNo | SMALLINT DEFAULT 0 | UI display order |
| IsDefault | TINYINT(1) DEFAULT 0 | Pre-selected in UI |
| IsSystemValue | TINYINT(1) DEFAULT 1 | Cannot be deleted |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (LookupTypeId, ValueCode) | |

---

### Group 10 — Settings (1 table)

#### Settings
| Column | Type | Notes |
|---|---|---|
| SettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| SettingGroup | VARCHAR(50) NOT NULL | SMS, OTP, AUTH, UPLOAD, etc. |
| SettingKey | VARCHAR(100) UNIQUE NOT NULL | |
| SettingValue | TEXT NOT NULL | |
| DataType | VARCHAR(20) DEFAULT 'STRING' | STRING/NUMBER/BOOLEAN/URL/JSON |
| Description | VARCHAR(500) NULL | |
| IsPublic | TINYINT(1) DEFAULT 0 | Safe for frontend |
| IsEditable | TINYINT(1) DEFAULT 1 | |
| UpdatedAt | DATETIME NULL | |
| UpdatedBy | INT UNSIGNED NULL | |

> **SettingsCache:** All settings loaded at startup into singleton. Zero DB reads on config access.  
> **IsPublic=1:** returned by `GET /api/v1/settings/public` — never expose secrets.

---

## LookupTypes (44 Types)

| TypeCode | Description |
|---|---|
| GENDER | Male, Female, Non-Binary, Prefer Not to Say |
| ORG_TYPE | Trust, Society, Section 8 Company, **NGO** *(v4.3)*, **Foundation** *(v4.3)*, **Charitable Institution** *(v4.3)*, **Religious Trust** *(v4.3)*, **CSR Foundation** *(v4.3)*, **Educational Trust** *(v4.3)* |
| ORG_STATUS | Pending Verification, Verified, Suspended, Rejected |
| USER_ROLE | Super Admin, NGO Admin, Volunteer, Donor, Beneficiary, Staff |
| ORG_MEMBER_ROLE | Admin, Staff, Member |
| MEMBER_APPROVAL | Pending, Approved, Rejected |
| LOCATION_SHARING | Always, During Activity, On Request, Never |
| PROJECT_TYPE | Education, Healthcare, Environment, Animal Welfare, Disaster Relief, Women Empowerment, Child Welfare, Elderly Care, Poverty Alleviation, Arts & Culture |
| PROJECT_STATUS | Draft, Active, Completed, Cancelled, Paused |
| JOIN_TYPE | Open, Requires Approval, Invite Only |
| LOCATION_TYPE | In-Person, Online, Hybrid |
| APPLICATION_STATUS | Pending, Approved, Rejected, Waitlisted, Withdrawn |
| SESSION_STATUS | Upcoming, Active, Completed, Cancelled |
| ATTENDANCE_METHOD | QR Scan, Manual, GPS |
| BADGE_TYPE | First Volunteer, 10 Hours, 50 Hours, 100 Hours, 500 Hours, Mentor, Top Donor, SOS Hero, Community Leader, Impact Champion |
| EDUCATION | Below 10th, 10th Pass, 12th Pass, Diploma, Graduate, Post Graduate, Doctorate |
| WORK_EXPERIENCE | Fresher, 1-2 Years, 3-5 Years, 6-10 Years, 10+ Years |
| INTEREST_TYPE | Education, Healthcare, Environment, Sports, Arts, Technology, Community, Animal Welfare |
| DOC_TYPE_USER | Aadhaar, PAN, Passport, Driving License, Voter ID |
| DOC_TYPE_ORG | Registration Certificate, 80G Certificate, 12A Certificate, FCRA Certificate, CSR Policy, Annual Report |
| POST_TYPE_FEED | Update, Announcement, Opportunity, Story, Article |
| POST_VISIBILITY | Public, Followers, Organisation Members, Private |
| POST_TYPE_COMMUNITY | Discussion, Question, Announcement, Resource, Event, Achievement |
| REPORT_REASON | Spam, Inappropriate Content, Misleading, Hate Speech, Harassment, Other |
| REPORT_STATUS | Pending, Under Review, Action Taken, Dismissed |
| SOS_ALERT_TYPE | SOS Emergency, Help Request, Missing Volunteer, Safe Arrival |
| SOS_STATUS | Active, Resolved, Cancelled |
| SOS_APPROVAL | Pending, Approved, Rejected |
| SOS_RESOLUTION | Self Resolved, Helped By Volunteer, Emergency Services, False Alarm |
| OTP_PURPOSE | Login/Registration, Mobile Change, Email Change, Password Reset |
| CAMPAIGN_TYPE | General, Project Specific, Emergency, Recurring |
| CAMPAIGN_STATUS | Draft, Active, Completed, Suspended, Archived |
| PAYMENT_METHOD | UPI, Credit/Debit Card, Net Banking, Wallet, NEFT/RTGS |
| PAYMENT_STATUS | Pending, Completed, Failed, Refunded |
| RECURRING_FREQUENCY | Weekly, Monthly, Quarterly, Yearly |
| WITHDRAWAL_STATUS | Pending, Under Review, Approved, Rejected, Processed |
| NOTIFICATION_TYPE | Project Update, New Application, SOS Alert, Donation Received, Badge Earned, New Follower, Comment, Mention, System |
| RECEIPT_TYPE | 80G, General, CSR |
| MEDIA_TYPE | Image, Video, Document, Audio |
| CERTIFICATE_TYPE | Volunteer Completion, Skills Assessment, Training, Achievement |
| SETTING_DATA_TYPE | String, Number, Boolean, URL, JSON |
| BENEFICIARY_TYPE | Individual, Family, Community, Institution |
| LANGUAGE | English, Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, Gujarati |
| COUNTRY | India, USA, UK, Canada, Australia, UAE, Singapore, Germany |

---

## Stored Procedures (100 Total)

### Auth (6 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Auth_SendOTP | p_Recipient, p_CountryCode, p_OtpCode, p_PurposeLkpId, p_IpAddress, p_ExpiryMinutes | WRITE | Generates OTP; enforces 3/10min rate limit; max 3 attempts then lock |
| Auth_VerifyOTP | p_Recipient, p_OtpCode, p_PurposeLkpId, p_IpAddress | WRITE | Validates OTP; auto-creates User + UserProfiles row on first login; returns `UserId, IsNewUser` |
| Auth_SaveRefreshToken | p_UserId, p_Token, p_DeviceInfo, p_IpAddress, p_ExpiresAt | WRITE | Stores hashed token; enforces max 5 active sessions per user |
| Auth_GetRefreshToken | p_Token | READ | Validates hashed token; returns `IsSuccess, UserId, Recipient, RefreshTokenId` |
| Auth_RevokeRefreshToken | p_Token | WRITE | Soft-revokes by hashed token (logout) |
| Auth_RevokeRefreshTokenById | p_RefreshTokenId | WRITE | Revokes by ID (used during token rotation) |

### User (14 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| User_GetProfile | p_UserId, p_RequestingUserId | GET | Full profile including `VolunteerExp`, `IsVerified`, `CountryCode`, `MemberSince`, `IsProfileComplete`, `GenderLkpId`, `EducationLkpId`, `WorkExpLkpId` and lookup names |
| User_GetPublicProfile | p_UserId | GET (Dynamic) | Public-safe profile — no sensitive fields |
| User_UpdateProfile | p_UserId + 18 profile params | WRITE | **v4.1: 19 params** — all fields COALESCE (partial update safe); includes `p_VolunteerExp` |
| User_UpdateSafetyPrefs | p_UserId, p_EmergVisibilityLkpId, p_AutoShareDurLkpId, p_AllowLocDuringSos, p_AllowLocDuringProj, p_EmergencyContactName, p_EmergencyContactPhone, p_EmergencyContactRelation | WRITE | **v4.1: 8 params** — UPSERT on UserId; all fields COALESCE |
| User_SaveInterests | p_UserId, p_InterestLkpIds (JSON) | WRITE | DELETE all existing interests + INSERT from JSON array |
| User_UploadDocument | p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb | WRITE | Inserts into UserDocuments; FileUrl/FileName/FileSizeKb come from POST /media/upload |
| User_GetSkills | p_UserId | LIST | Returns UserSkills with AvgRating, RatingCount |
| User_AddSkill | p_UserId, p_SkillName | WRITE | Insert; returns `UserSkillId`; 0 if duplicate |
| User_RemoveSkill | p_UserId, p_UserSkillId | WRITE | Soft-delete (IsDeleted=1) |
| User_GetSafetyPrefs | p_UserId | GET | **v4.1 Section 5** Returns safety prefs + emergency contacts; used for Edit Profile (safety step) pre-fill. Returns: `EmergVisibilityLkpId`, `EmergVisibility`, `AutoShareDurLkpId`, `AutoShareDuration`, `AllowLocDuringSos`, `AllowLocDuringProj`, `EmergencyContactName`, `EmergencyContactPhone`, `EmergencyContactRelation` |
| User_GetInterests | p_UserId | LIST | **v4.1 Section 5** Returns user's saved interests with lookup names. Returns: `InterestLkpId`, `InterestName`, `InterestCode` |
| User_GetMyOrgs | p_UserId | LIST (Dynamic) | **v4.1 Section 5** Returns all orgs the user is an APPROVED member of. Returns: `OrgId`, `OrgName`, `LogoUrl`, `OrgType`, `City`, `State`, `Role`, `RoleCode`, `MemberStatusCode`, `OrgStatusCode`, `MemberCount`, `JoinedAt` |
| User_GetBadges | p_UserId | LIST | **v4.1 Section 5** Returns all earned badges. Returns: `UserBadgeId`, `BadgeLkpId`, `BadgeName`, `BadgeCode`, `OrgName`, `ProjectName`, `AwardedAt` |
| User_GetImpact | p_UserId | GET | **v4.1 Section 5** Returns full impact dashboard stats. Returns: `ImpactScore`, `ReliabilityPct`, `ProjectsCompleted`, `TotalHours`, `BadgeCount`, `SkillCount`, `ProjectsApplied`, `CertificateCount`, `MemberSince` |

### Lookup (4 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Lookup_GetAllTypes | — | LIST | All active LookupTypes |
| Lookup_GetValuesByTypeCode | p_TypeCode | LIST | All values for a given TypeCode |
| Lookup_GetValueByCode | p_TypeCode, p_ValueCode | GET | Single lookup value; **v4.1** returns `LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault` |
| Lookup_GetValuesByType | p_TypeCode | LIST | Alias for Lookup_GetValuesByTypeCode |

### Settings (4 SPs)
| SP Name | Type | Description |
|---|---|---|
| Settings_GetPublic | READ | IsPublic=1 settings |
| Settings_GetByGroup | READ | Filter by SettingGroup |
| Settings_GetAll | READ | Admin only |
| Settings_Update | WRITE | Update value, refresh cache |

### Organisation (24 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Org_Register | p_UserId, p_OrgName, p_RegistrationNo, p_OrgTypeLkpId, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country | WRITE | **v4.1 Section 6: 19 params** Creates org + adds creator as ADMIN member. Returns `IsSuccess`, `Message`, `OrgId` |
| Org_GetProfile | p_OrgId | GET | **v4.1 Section 6** Full org profile — now returns `OrgTypeLkpId`, `StatusLkpId`, `Category`, `ContactPerson` for edit form pre-fill |
| Org_Update | p_OrgId, p_UserId, p_OrgName, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country | WRITE | **v4.1 Section 6: 18 params** All fields COALESCE (partial update safe) |
| Org_GetDashboard | p_OrgId | GET | **v4.1 Section 6 NEW** Admin dashboard KPIs. Returns: `TotalMembers`, `NewMembersThisMonth`, `ActiveVolunteers`, `ActiveRatePct`, `VolunteerHoursMonth`, `ActiveProjects`, `PendingApplications` |
| Org_List | p_Keyword, p_Category, p_PageNumber, p_PageSize | PAGED | **v4.1 Section 7 FIXED** Always returns APPROVED orgs only. Filters by keyword (name/city) + category string. Returns `OrgId`, `OrgName`, `Category`, `LogoUrl`, `City`, `State`, `MemberCount`, `AvgRating`, `Latitude`, `Longitude` + TotalCount |
| Org_ListRecommended | p_UserId | LIST | **v4.1 Section 7 NEW** Matches user's INTEREST_TYPE ValueCodes against org Category; returns up to 20 orgs ranked by MatchScore then AvgRating. Returns same fields as Org_List + `MatchScore` |
| Campaign_ListPublicTrending | p_PageSize | LIST | **v4.1 Section 7 NEW** Active campaigns ranked by IsEmergency → DonorCount → RaisedAmount. Returns: `CampaignId`, `CampaignName`, `OrgName`, `OrgLogoUrl`, `RaisedAmount`, `TargetAmount`, `DonorCount`, `ProgressPct`, `EndDate`, `BannerUrl`, `IsEmergency` |
| Org_GetDonationDashboard | p_OrgId | GET | **v4.1 Section 7 NEW** Returns 9 donation KPIs for s-admin-donations screen: `TotalRaisedAllTime`, `ThisMonthRaised`, `LastMonthRaised`, `TodayRaised`, `TodayTransactionCount`, `RecurringMonthlyAmount`, `ActiveRecurringDonors`, `TotalCampaigns`, `ActiveCampaigns` |
| Org_GetDonors | p_OrgId, p_Tab (ALL/RECURRING/TOP), p_PageNumber, p_PageSize | PAGED | **v4.1 Section 7 NEW** Donor list for s-admin-donors. Respects IsAnonymous flag. Returns: `UserId`, `FullName`, `Email`, `Phone`, `TotalDonated`, `DonationCount`, `LastDonatedAt`, `IsAnonymous`, `IsRecurring` + TotalCount |
| Org_GetTransactions | p_OrgId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | **v4.1 Section 7 NEW** Transaction list for s-admin-transactions. Filter by statusCode (null = all). Returns: `TransactionId`, `ReadableId`, `DonorName`, `Amount`, `NetAmount`, `CampaignName`, `StatusCode`, `StatusName`, `PaymentMethod`, `CreatedAt`, `IsAnonymous` + TotalCount |
| Org_GetVolunteerProfile | p_OrgId, p_UserId | GET | **v4.1 Section 7 NEW** Admin view of volunteer for s-vol-profile. Includes reliability score (never public). Returns: `UserId`, `FullName`, `City`, `Occupation`, `ProfilePhoto`, `TotalHours`, `ProjectCount`, `OrgCount`, `ReliabilityPct`, `AvgRating`, `PeerRating`, `NoShowCount`, `ExcusedCount`, `ComplaintCount`, `RoleCode`, `RoleName`, `StatusCode`, `StatusName`, `JoinedAt` |
| Org_GetMemberImpact | p_OrgId, p_UserId | GET | **v4.1 Section 7 NEW** Admin view for s-member-impact. Returns: `UserId`, `FullName`, `Occupation`, `City`, `RoleName`, `ImpactScore`, `ReliabilityPct`, `TotalHours`, `ProjectCount`, `OrgCount`, `BadgeCount`, `NoShowCount`, `ComplaintCount` |
| Org_UpdateMemberRole | p_OrgId, p_MemberId, p_RoleLkpId, p_UpdatedBy | WRITE | **v4.1 Section 7 NEW** Changes a member's role (VOLUNTEER/COORDINATOR/ADMIN). Returns `IsSuccess`, `Message` |
| Org_GetMembers | p_OrgId | LIST (Dynamic) | All members with role, status, permissions |
| Org_AddMember | p_OrgId, p_UserId, p_RoleLkpId, p_RequestedBy | WRITE | Direct add (admin action) |
| Org_RemoveMember | p_OrgId, p_UserId, p_RequestedBy | WRITE | Soft remove |
| Org_RequestMembership | p_OrgId, p_UserId, p_Message | WRITE | User self-requests; stores RequestMessage |
| Org_ReviewMembership | p_RequestId, p_StatusCode, p_AdminNotes, p_ReviewedBy | WRITE | APPROVED/REJECTED with AdminNotes |
| Org_GetPendingMembers | p_OrgId | LIST (Dynamic) | PENDING approval requests |
| Org_UpdateMemberPermissions | p_OrgId, p_MemberId, p_CanPost, p_CanComment, p_CanCommunityPost, p_MaxPostsPerDay, p_LocationSharingLkpId, p_UpdatedBy | WRITE | Granular member permissions |
| Org_UploadDocument | p_OrgId, p_UploadedBy, p_DocumentTypeLkpId, p_FileUrl, p_FileName | WRITE | Inserts into OrgDocuments; FileUrl/FileName come from POST /media/upload |

### Project (10 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Project_Create | p_UserId, p_OrgId, p_Title, p_Description, p_Category, p_ProjectTypeLkpId, p_JoinTypeLkpId, p_StatusLkpId, p_MaxVolunteers, p_MinAge, p_MaxAge, p_IsPublic, p_StartDate, p_EndDate, p_ScheduleType, p_RecurrenceDays, p_StartTime, p_EndTime, p_DurationMinutes, p_LocationTypeLkpId, p_LocationTypeCode, p_LocationName, p_Address, p_Latitude, p_Longitude, p_GoogleMapsUrl, p_GenderRestriction, p_RequiresApproval, p_CoverImageUrl, p_City, p_State, p_IsDraft | WRITE | **v4.3 REBUILT** — 32 params matching C# DAL. Resolves `ProjectTypeLkpId` from `p_ScheduleType` string if not supplied. Maps schedule dates into correct columns (`OneTimeDate`/`RecurStart`+`RecurEnd`/`FlexFromDate`+`FlexToDate`). Defaults `IsPublic=1`, `RequiresApproval=0`. Returns `IsSuccess`, `Message`, `ProjectId` |
| Project_GetById | p_ProjectId, p_UserId | GET | Full project details: org name, all schedule fields, location fields, status label, join type, `ApprovedVolunteers` count, `MyApplicationStatusId` for the calling user |
| Project_Update | p_ProjectId + same 31 params as Create (minus p_OrgId) | WRITE | **v4.3 REBUILT** — 32 params matching C# DAL. COALESCE-safe partial update. Returns `IsSuccess`, `Message` |
| Project_List | p_OrgId, p_Category, p_City, p_StatusCode, p_TypeCode, p_PageNumber, p_PageSize | PAGED | **v4.3 UPDATED** — Returns `ScheduleType` (from `ProjectTypeLkpId` lookup: ONE_TIME/RECURRING/FLEXIBLE), `LocationName` (= `Landmark` column), `Address` (= `AddressLine` column), `ApprovedCount` (correlated subquery), `StatusCode`. Admin with `p_OrgId` sees all projects; public browse (no `p_OrgId`) sees `IsPublic=1` only |
| Project_AddSkill | WRITE | Inserts ProjectSkill |
| Project_AddSession | WRITE | Creates session + generates QR UUID |
| Project_GetSessions | LIST | Sessions with attendee count, QR, status |
| Project_GetSessionQr | GET | Returns QR token for org admin |
| Project_CheckIn | WRITE | Validates QR token, records attendance |
| Project_Apply | WRITE | Inserts application |
| Project_ReviewApplication | WRITE | APPROVED/REJECTED |
| Project_GetApplications | PAGED | Filter by statusCode |
| Project_Complete | WRITE | Sets status COMPLETED, triggers certificate generation |

### Application (4 SPs — standalone module)
| SP Name | Type | Description |
|---|---|---|
| Application_Apply | WRITE | Alias for Project_Apply |
| Application_GetByProject | PAGED | By project + statusLkpId |
| Application_Review | WRITE | Uses StatusLkpId (INT) |
| Application_GetByUser | LIST | My applications across all projects |

### Post / Feed (9 SPs)
| SP Name | Type | Description |
|---|---|---|
| Post_Create | WRITE | Content + optional MediaUrls CSV |
| Post_GetFeed | PAGED | Personalized feed for logged-in user |
| Post_GetById | GET | Single post with like/comment counts |
| Post_Delete | WRITE | Soft delete |
| Post_Pin | WRITE | Toggle IsPinned |
| Post_Like | WRITE | INSERT IGNORE into PostLikes |
| Post_Unlike | WRITE | DELETE from PostLikes |
| Post_AddComment | WRITE | Supports threading via ParentCommentId |
| Post_GetComments | PAGED | Nested comments |
| Post_Report | WRITE | PostReports insert |

### Community (9 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Community_CreatePost | p_UserId, p_OrgId, p_Title, p_Content, p_PostTypeLkpId, p_AudienceLkpId | WRITE | **v4.2 REPLACED** (was 14-param). Creates org-scoped community post. Auto-defaults `AudienceLkpId` to ALL_MEMBERS if NULL. Returns `IsSuccess`, `Message`, `CommunityPostId` |
| Community_GetFeed | p_OrgId, p_UserId, p_PageNumber, p_PageSize | PAGED (Dynamic) | **v4.3 UPDATED** — Adds `PollOptionsJson` (JSON array: `pollOptionId`, `optionText`, `voteCount`, `isVoted` per option — null for non-POLL posts), `RoleName` (author's org role: Admin/Member/etc.), `TimeAgo` (human-readable). Also returns `IsLiked`, `IsLikedByMe`, `IsAcknowledged`, `IsAcknowledgedByMe`, `LikeCount`, `CommentCount`. DAL parses `PollOptionsJson` → `pollOptions` array with computed `votePct`. Returns rows + `TotalCount` |
| Community_AcknowledgePost | p_CommunityPostId, p_UserId | WRITE | Marks a post acknowledged by the calling user (used for Announcements). Increments `AcknowledgeCount` on first call. Returns `IsSuccess`, `Message` |
| Community_CreatePoll | p_UserId, p_OrgId, p_Question, p_OptionsJson, p_ExpiresInHours | WRITE | **v4.2 REPLACED** (was 2-param). Creates CommunityPost of type POLL + PollOptions from JSON array (e.g. `["Yes","No","Maybe"]`). Returns `IsSuccess`, `Message`, `PollId` |
| Community_Vote | p_PollId, p_UserId, p_PollOptionId | WRITE | **v4.2 REPLACED** (was 2-param). INSERT IGNORE — one vote per user, checks expiry. Returns `IsSuccess`, `Message` |
| Community_LikePost | p_CommunityPostId, p_UserId | WRITE | **v4.2 NEW** Toggle like on a community post. Inserts/deletes from `CommunityPostLikes`, recalculates `CommunityPosts.LikeCount`. Returns `IsLiked INT` (1=now liked, 0=now unliked), `LikeCount INT` |
| Community_AddComment | p_CommunityPostId, p_UserId, p_Content | WRITE | **v4.2 NEW** Inserts a comment into `CommunityPostComments`, increments `CommunityPosts.CommentCount`. Returns `IsSuccess`, `Message`, `CommunityCommentId` |
| Community_GetComments | p_CommunityPostId, p_UserId | LIST (Dynamic) | **v4.2 NEW** Returns all non-deleted comments for a post in chronological order. Returns: `CommunityCommentId`, `CommunityPostId`, `UserId`, `AuthorName`, `ProfilePhoto`, `Content`, `LikeCount`, `IsLiked` (1/0), `IsLikedByMe`, `TimeAgo`, `CreatedAt` |
| Community_LikeComment | p_CommunityCommentId, p_UserId | WRITE | **v4.2 NEW** Toggle like on a comment. Inserts/deletes from `CommunityCommentLikes`, recalculates `CommunityPostComments.LikeCount`. Returns `IsLiked INT`, `LikeCount INT` |

### SOS (12 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Sos_Trigger | p_UserId, p_AlertTypeLkpId, p_OrgId, p_Latitude, p_Longitude, p_ApproxLocation, p_Description | WRITE | Creates SosIncident (status=ACTIVE); logs initial location. Returns `IsSuccess`, `Message`, `SosIncidentId` |
| Sos_GetActive | p_UserId, p_OrgId | LIST (Dynamic) | Returns active incidents visible to the user for their org. `p_OrgId` nullable. DynamicRow list |
| Sos_GetMyActive | p_UserId | GET (2 result sets) | **v4.2 NEW** Returns victim's own active incident + responders. Result set 1: incident row (same shape as Sos_GetById). Result set 2: responders list. Returns 0 rows if no active incident |
| Sos_GetById | p_SosIncidentId, p_UserId | GET (2 result sets) | **v4.3 REBUILT** — All JOINs are now LEFT JOINs (no 0-row returns). Result set 1: incident with `AlertTypeName`, `StatusName` added. Result set 2: responders list with `ProfilePhoto`, `ApprovalStatusName`. Returns 0 rows if incident not found or soft-deleted |
| Sos_Respond | p_SosIncidentId, p_UserId | WRITE | Inserts into SosResponders (status=PENDING). Returns `IsSuccess`, `Message`, `SosResponderId` |
| Sos_ApproveResponder | p_SosIncidentId, p_UserId, p_SosResponderId, p_CanViewLocation | WRITE | Updates `SosResponders.ApprovalStatusLkpId` to APPROVED; sets `CanViewLocation`. Only the victim (`p_UserId` must match incident UserId) can approve. Returns `IsSuccess`, `Message` |
| Sos_Resolve | p_SosIncidentId, p_UserId | WRITE | Sets incident status to RESOLVED, sets `ResolvedAt=NOW()`. Only victim can resolve. Returns `IsSuccess`, `Message` |
| Sos_Cancel | p_SosIncidentId, p_UserId, p_CancelReason | WRITE | Sets status to CANCELLED, sets `CancelledAt=NOW()`, stores `CancelReason`. Only victim can cancel. Returns `IsSuccess`, `Message` |
| Sos_GetLatestLocation | p_SosIncidentId, p_UserId | GET | Returns latest row from SosLocationLogs for the incident. Access gate: caller must be victim or APPROVED responder with `CanViewLocation=1`. Returns `Latitude`, `Longitude`, `Accuracy`, `LoggedAt` |
| Sos_UpdateLocation | p_SosIncidentId, p_UserId, p_Latitude, p_Longitude, p_Accuracy | WRITE | Inserts into SosLocationLogs (called every ~10s by victim's device). Returns `IsSuccess`, `Message` |
| Sos_GetOrgAlerts | p_OrgId, p_UserId, p_Limit | LIST (Dynamic) | **v4.3 NEW** — Returns all SOS incidents for an org (ACTIVE + RESOLVED + CANCELLED), newest first. Includes `IsActive` (1/0), `AlertTypeName`, `StatusName`, `MyApprovalStatus` (PENDING/APPROVED/REJECTED/NULL — the calling user's responder status for each incident). Used by CommunityScreen to show active alerts at top and history below |
| Sos_DeclineResponder | p_SosIncidentId, p_SosResponderId, p_DeclinedBy | WRITE | **v4.3 NEW** — Victim declines a pending responder. Sets `SosResponders.ApprovalStatusLkpId` to REJECTED. Validates `p_DeclinedBy` must equal the incident owner `UserId`. Returns `IsSuccess`, `Message` |

### Donation (14 SPs)
| SP Name | Type | Description |
|---|---|---|
| Donation_CreateCampaign | WRITE | All campaign fields |
| Donation_GetCampaigns | PAGED | orgId + keyword filter |
| Donation_GetCampaignById | GET | Campaign with raised amount |
| Donation_GetDonors | PAGED | Respects IsAnonymous flag |
| Donation_Donate | WRITE | Generates DON-YYYY-NNNNNN readable ID |
| Donation_ConfirmPayment | WRITE | Updates status COMPLETED, updates RaisedAmount |
| Donation_GetHistory | PAGED | Donor's transaction history |
| Donation_GetReceipt | GET | 80G receipt by DonationId |
| Donation_SetupRecurring | WRITE | Creates RecurringDonations record |
| Donation_PauseRecurring | WRITE | IsActive=0, PausedAt=NOW() |
| Donation_ResumeRecurring | WRITE | IsActive=1, PausedAt=NULL, NextRunAt=+1month |
| Donation_CancelRecurring | WRITE | Marks inactive permanently |
| Donation_GetAnnualSummary | GET | Year summary + per-NGO breakdown (2 result sets) |
| Donation_GetSupportedNGOs | LIST | All NGOs a donor has supported |
| Donation_GetOrgTransactions | PAGED | Finance view for org admins |

### Withdrawal (3 SPs)
| SP Name | Type | Description |
|---|---|---|
| Withdrawal_Create | WRITE | Validates RaisedAmount ≥ Amount; generates WDR-YYYY-NNNN |
| Withdrawal_GetByOrg | PAGED | Withdrawal list with campaign title + status |
| Withdrawal_AdminReview | WRITE | APPROVED deducts from RaisedAmount |

### Certificate / Badge / Rating / Attendance (5 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Certificate_GetByUser | p_UserId | LIST | Joins Projects + Organisations |
| UserSkillRating_Add | p_RaterUserId, p_RatedUserId, p_UserSkillId, p_Rating, p_Review, p_ProjectId | WRITE | ON DUPLICATE KEY UPDATE |
| UserBadge_Award | p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId | WRITE | **v4.1 Section 7** Awards badge from NGO admin; includes `p_OrgId` (AwardedByOrgId). Returns `IsSuccess`, `Message`, `BadgeId` |
| Attendance_ExcuseNoShow | p_AttendanceId, p_OrgId, p_ExcusedBy | WRITE | **v4.1 Section 7 NEW** Marks a NO_SHOW as EXCUSED so it doesn't penalise reliability score. Validates the attendance belongs to this org. Returns `IsSuccess`, `Message` |

### Notification (5 SPs)
| SP Name | Type | Description |
|---|---|---|
| Notification_GetByUser | PAGED | p_OnlyUnread filter (v4.0) |
| Notification_MarkRead | WRITE | Single notification |
| Notification_MarkAllRead | WRITE | All for user |
| Notification_GetUnreadCount | GET | Returns UnreadCount |
| Notification_Create | WRITE | Internal use by other SPs |
| Notification_SaveDeviceToken | WRITE | FCM token via UserDeviceTokens |

---

## IdSequences — Readable IDs

| PrefixCode | Format | Example | Padding |
|---|---|---|---|
| DON | DON-{YYYY}-{NNNNNN} | DON-2026-000001 | 6 digits |
| WDR | WDR-{YYYY}-{NNNN} | WDR-2026-0001 | 4 digits |
| REC | REC-{YYYY}-{NNNN} | REC-2026-0001 | 4 digits |

SP pattern: `SELECT ... FOR UPDATE` on IdSequences, increment, format, use in INSERT.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| BIGINT on AuditLogs, SosLocationLogs, Notifications | Volume overflow risk at scale |
| Denormalized counts (LikeCount, MemberCount, RaisedAmount) | No COUNT() on hot read paths |
| Soft delete everywhere | Audit trail, dispute resolution, compliance |
| LookupValues FK not VARCHAR enums | Dynamic — add new values without code deploy |
| Settings table not appsettings.json | Dynamic — update config without restart |
| DynamicRow for 70% of display queries | SP adds column → JSON updates, zero C# change |
| IdSequences for readable IDs | DON-2026-000001 better than raw INT for receipts |
| SchemaVersions table | Track migration history |

---

*NGOConnect v4.3 — 50 Tables, 120 Stored Procedures, 45 LookupTypes*  
*v4.3 adds: Project_Create/Update rebuilt (32 params, DAL-matching); Project_List: ScheduleType/LocationName/Address/ApprovedCount added; Sos_GetById robust (LEFT JOINs, AlertTypeName); Community_GetFeed: PollOptionsJson/RoleName/TimeAgo; 2 new SPs (Sos_GetOrgAlerts, Sos_DeclineResponder); 6 new ORG_TYPE lookup values.*  
*Run `NGOConnect_Complete_Setup_v4.3.sql` to upgrade. For incremental: run `NGOConnect_Patch_ProjectCreate_SP_Only.sql`, `NGOConnect_Patch_ProjectList_v2.sql`, `NGOConnect_Patch_PollOptions_Feed.sql`, `NGOConnect_Patch_SosFix_GetById.sql`, `NGOConnect_Patch_SosGetOrgAlertsWithUserId.sql`, `NGOConnect_Patch_SosDeclineResponder.sql`, `NGOConnect_Patch_OrgType_Seed.sql`.*

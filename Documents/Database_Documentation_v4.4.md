# NGOConnect Database Documentation v4.4

**Database:** MySQL 8.0+  
**Version:** 4.4  
**Tables:** 50  
**Stored Procedures:** 114  
**Generated:** 2026-07-10  

**Changes from v4.3 (v4.4):**

- **Project_List** — Added `p_UserLat DECIMAL(10,7)` + `p_UserLon DECIMAL(10,7)` optional params; Added `DistanceKm` (Haversine formula), `Latitude`, `Longitude` to SELECT; ORDER BY distance ASC when coords provided, else `CreatedAt DESC`.
- **Org_GetDashboard** — Added `PendingProjectApplications` KPI column (counts PENDING volunteer project applications for the org). Full SP rebuilt with correct schema refs (no `pa.ProjectId` direct column, no `pa.AttendanceStatus`, no `pa.MarkedAt`).
- **User_GetImpact** — Full rebuild: ImpactScore now calculated inline (Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5 − NoShows×20 − Withdrawals×15). New return columns: `RankName`, `RankNumber`, `TotalRanked`, `NgosJoined`, `PendingApplications`, `ApprovedApplications`, `FirstName`, `LastName`, `ProfilePhoto`, `Bio`.
- **Application_GetByUser** — Full rebuild: Added `p_PageNumber` + `p_PageSize` params; Added return columns: `OrgLogoUrl`, `ScheduleTypeCode`, `ScheduleTypeName`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `Landmark`, `City`, `ProjectStatusCode`, `ProjectStatus`, `StatusUpdatedAt`. Now returns TotalCount as second result set.
- **Post_Report** — Rebuilt: param `p_ReasonLkpId INT` → `p_ReasonCode VARCHAR(50)`. SP resolves LookupValueId internally. Prevents duplicate reports (same user + same post).
- **User_UploadDocument** — Updated to upsert pattern: soft-deletes any existing doc of same type for user before inserting new one (one doc per type per user enforced).
- **User_GetDocuments** — **NEW SP** — Lists all active documents for a user with DocTypeCode/DocTypeName from lookup.
- **User_DeleteDocument** — **NEW SP** — Soft-deletes a user document; validates ownership (`UserId` check).
- **Org_GetAdminPosts** — **NEW SP** — Returns all feed posts for an org enriched with role, report count, derived StatusCode (PUBLISHED / REPORTED).
- **Org_PinPost** — **NEW SP** — Toggles IsPinned on a feed post; validates post belongs to the org.
- **Org_DeletePost** — **NEW SP** — Soft-deletes a feed post (admin action); validates post belongs to the org.
- **Org_ModeratePost** — **NEW SP** — KEEP / REMOVE action on a reported post; resolves all pending reports.
- **Project_GetSessionQr** — Rebuilt: enforces QR time-window (`SessionStart − QR_BUFFER_MINUTES` → `SessionEnd`); returns descriptive `IsSuccess=0` messages (`Too early`, `Session ended`) when outside window; reads `QR_BUFFER_MINUTES` + `QR_EXPIRY_MINUTES` from Settings.
- **Application_GetByProject** — Rebuilt: correlated subquery joins `ProjectAttendance` — attendance status takes precedence over application status (COALESCE). New return columns: `CheckedInAt`, `HoursLogged`, `IsExcused`, `QrScannedAt`, `AdminNote`, `SessionDate`, `SessionStartTime`, `SessionEndTime`.
- **Project_ManualAttendance** — **NEW SP** — Admin marks volunteer ATTENDED for most recent past session; uses `QrScannedAt=NULL` to distinguish from QR scan; idempotent (`ON DUPLICATE KEY UPDATE`).
- **Project_AddSession** — Updated: duplicate guard prevents creating two sessions for same project+date; returns `IsSuccess=0` with `SessionId` of existing session if duplicate.
- **Project_GetSessions** — Updated: `SessionDate` returned via `DATE_FORMAT(..., '%Y-%m-%d')` to prevent DateTime serialization timezone shift in .NET MySql.Data driver.
- **Post_GetFeed** — Rebuilt: added `LEFT JOIN PostMedia` + `LEFT JOIN LookupValues` for media; returns `MediaUrls` (GROUP_CONCAT of `FileUrl`), `MediaTypes` (GROUP_CONCAT of ValueCode for each media item), `TimeAgo` (human-readable), `PostTypeLkpCode`, `IsPinned`. Pinned posts sorted first.
- **Post_Create** — Updated: auto-detects VIDEO vs IMAGE from URL extension via REGEXP (`mp4|mov|avi|mkv|webm|m4v|3gp|wmv`). Assigns correct `MediaTypeLkpId` per URL.
- **Settings seed** — Added: `QR_EXPIRY_MINUTES=60` + `QR_BUFFER_MINUTES=15` (group: PROJECT).
- **LookupValues DOCUMENT_TYPE_USER** — Updated: India-specific types (AADHAAR, PAN, VOTER_ID) soft-deleted; replaced with universal types: PHOTO_ID, ADDR_PROOF, PASSPORT, DRIVING_LIC, OTHER.
- **PostMedia table** — Documented correct column name: `FileUrl` (not `MediaUrl` as shown in v4.3).
- **PostReports table** — Documented correct column name: `ReportedByUserId` (not `ReportedBy` as shown in v4.3).
- **ProjectApplications table** — Added `Motivation TEXT NULL` (replaces `Note`), `RequestedSessions TEXT NULL`.
- **ProjectAttendance table** — Fully rebuilt documentation: added `CheckInTime`, `HoursLogged`, `IsNoShowExcused`, `QrScannedAt`, `AdminNote`, `AttendStatusLkpId` columns.

**Changes from v4.2 (v4.3):**

- **Project_Create / Project_Update** — Rebuilt to match C# DAL params: `p_UserId`, `p_Title`, `p_ScheduleType VARCHAR(20)`, `p_RecurrenceDays VARCHAR(100)`, `p_StartTime/EndTime VARCHAR(10)`, `p_DurationMinutes`, `p_LocationName`, `p_Address`, `p_IsDraft` (32 params). Removed old `p_ScheduleTypeLkpId`, `p_AddressLine`, `p_Landmark` naming.
- **Project_List** — Added `ScheduleType` (derived: `ptv.ValueCode`), `LocationName` (`p.Landmark`), `Address` (`p.AddressLine`), `ApprovedCount` (correlated subquery), `StatusCode`. Admin querying own org now sees all projects (not just `IsPublic=1`).
- **Sos_GetById** — Rebuilt: removed `JOIN Users` (caused 0-row returns); all JOINs now LEFT; added `AlertTypeName`, `StatusName` return columns; responders list includes `ProfilePhoto`, `ApprovalStatusName`.
- **Community_GetFeed** — Added `PollOptionsJson` (JSON_ARRAYAGG correlated subquery with `voteCount` + `isVoted`), `RoleName` (author's org role), `TimeAgo` (human-readable elapsed). DAL post-processes `PollOptionsJson` → `pollOptions` array.
- **Sos_GetOrgAlerts** — **NEW SP** — `p_OrgId, p_UserId, p_Limit`. Returns all incidents for org (active + resolved + cancelled) with `IsActive` flag and `MyApprovalStatus` (PENDING/APPROVED/REJECTED/NULL) per viewer.
- **Sos_DeclineResponder** — **NEW SP** — `p_SosIncidentId, p_SosResponderId, p_DeclinedBy`. Victim declines pending responder — sets `ApprovalStatusLkpId` to REJECTED. Validates caller is incident owner.
- **LookupValues (ORG_TYPE)** — Added 6 new values: NGO (4), FOUNDATION (5), CHARITABLE_INSTITUTION (6), RELIGIOUS_TRUST (7), CSR_FOUNDATION (8), EDUCATIONAL_TRUST (9).

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

## Tables (50 Total)

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
| EducationLkpId | INT UNSIGNED FK→LookupValues NULL | |
| FieldOfStudy | VARCHAR(150) NULL | |
| WorkExpLkpId | INT UNSIGNED FK→LookupValues NULL | |
| AddressLine1 | VARCHAR(200) NULL | |
| AddressLine2 | VARCHAR(200) NULL | |
| Pincode | VARCHAR(20) NULL | |
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
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | LookupType: DOCUMENT_TYPE_USER |
| FileUrl | VARCHAR(500) NOT NULL | Permanent URL from /media/upload |
| FileName | VARCHAR(255) NOT NULL | Stored filename |
| FileSizeKb | INT UNSIGNED NOT NULL | File size in KB |
| IsVerified | TINYINT(1) DEFAULT 0 | Admin-verified document |
| IsDeleted | TINYINT(1) DEFAULT 0 | **v4.4** Soft delete — supports User_UploadDocument upsert pattern |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | Same as UserId |
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
| IsDeleted | TINYINT(1) DEFAULT 0 | |
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
| EmergVisibilityLkpId | INT UNSIGNED FK→LookupValues NOT NULL | Who can see SOS alert |
| AutoShareDurLkpId | INT UNSIGNED FK→LookupValues NOT NULL | Auto-stop location sharing duration |
| AllowLocDuringSos | TINYINT(1) DEFAULT 1 | Share live location during active SOS |
| AllowLocDuringProj | TINYINT(1) DEFAULT 1 | Share live location during project sessions |
| EmergencyContactName | VARCHAR(100) NULL | Emergency contact full name |
| EmergencyContactPhone | VARCHAR(20) NULL | Emergency contact phone number |
| EmergencyContactRelation | VARCHAR(50) NULL | Relationship (e.g. Spouse, Parent) |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME ON UPDATE CURRENT_TIMESTAMP | |

---

### Group 3 — Organisations (4 tables)

#### Organisations
| Column | Type | Notes |
|---|---|---|
| OrgId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgName | VARCHAR(300) NOT NULL | |
| RegNumber | VARCHAR(100) UNIQUE NULL | Registration number |
| OrgTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | LookupType: ORG_TYPE |
| Category | VARCHAR(100) NULL | Category tag (e.g. "Education", "Environment") |
| ContactPerson | VARCHAR(100) NULL | Contact person name (Step 2 of create wizard) |
| About | TEXT NULL | Short description |
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
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | ORG_STATUS — PENDING/APPROVED/REJECTED/SUSPENDED |
| MemberCount | INT DEFAULT 0 | Denormalized |
| AvgRating | DECIMAL(3,2) NOT NULL DEFAULT 0.00 | |
| RatingCount | INT UNSIGNED NOT NULL DEFAULT 0 | |
| Latitude | DECIMAL(10,7) NULL | NGO pin latitude |
| Longitude | DECIMAL(10,7) NULL | NGO pin longitude |
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

---

### Group 4 — Projects (6 tables)

#### Projects
| Column | Type | Notes |
|---|---|---|
| ProjectId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| Title | VARCHAR(200) NOT NULL | Column used: `ProjectName` in some older SPs |
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
| LocationName | VARCHAR(200) NULL | Also referenced as `Landmark` in some SPs |
| Address | VARCHAR(500) NULL | Also referenced as `AddressLine` in some SPs |
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
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| UpdatedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### ProjectApplications
| Column | Type | Notes |
|---|---|---|
| ApplicationId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| UserId | INT UNSIGNED FK→Users | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| Motivation | TEXT NULL | **v4.4** Applicant's motivation/reason (was `Note`) |
| RequestedSessions | TEXT NULL | **v4.4** Comma-separated session preferences |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| StatusUpdatedAt | DATETIME NULL | |
| AdminNotes | TEXT NULL | |
| AppliedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (ProjectId, UserId) | |

#### ProjectAttendance
**v4.4 — Fully documented (schema extended from v4.3)**

| Column | Type | Notes |
|---|---|---|
| AttendanceId | INT UNSIGNED PK AUTO_INCREMENT | |
| SessionId | INT UNSIGNED FK→ProjectSessions | |
| UserId | INT UNSIGNED FK→Users | |
| CheckInTime | DATETIME DEFAULT CURRENT_TIMESTAMP | Time of check-in (QR scan or manual) |
| HoursLogged | DECIMAL(4,2) NULL | Computed from session EndTime − StartTime |
| AttendStatusLkpId | INT UNSIGNED FK→LookupValues | ATTENDED/NO_SHOW/EXCUSED (ATTENDANCE_STATUS lookup) |
| IsNoShowExcused | TINYINT(1) DEFAULT 0 | Admin-excused no-show — no reliability score penalty |
| QrScannedAt | DATETIME NULL | Set when scanned via QR; NULL when manually marked by admin |
| AdminNote | TEXT NULL | Admin note (e.g. "Manually marked as attended by admin.") |
| CreatedBy | INT UNSIGNED NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| UpdatedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (SessionId, UserId) | ON DUPLICATE KEY UPDATE for idempotent re-checkin |

> **Admin vs QR distinction:** `QrScannedAt IS NULL` = manually marked by admin. `QrScannedAt IS NOT NULL` = volunteer self-scanned QR.

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
| IsDeleted | TINYINT(1) DEFAULT 0 | |
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
| PinnedAt | DATETIME NULL | Set by Org_PinPost SP |
| PinnedBy | INT UNSIGNED FK→Users NULL | Set by Org_PinPost SP |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED NOT NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### PostMedia
| Column | Type | Notes |
|---|---|---|
| PostMediaId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| FileUrl | VARCHAR(500) NOT NULL | **v4.4 fix:** column name is `FileUrl` (not `MediaUrl` as shown in v4.3 docs) |
| MediaTypeLkpId | INT UNSIGNED FK→LookupValues NULL | MEDIA_TYPE lookup — IMAGE or VIDEO |
| SortOrder | TINYINT DEFAULT 0 | Display order in carousel |

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
| ReportedByUserId | INT UNSIGNED FK→Users | **v4.4 fix:** column name is `ReportedByUserId` (not `ReportedBy` as shown in v4.3 docs) |
| ReasonLkpId | INT UNSIGNED FK→LookupValues | REPORT_REASON lookup |
| Details | TEXT NULL | Optional free-text explanation |
| StatusLkpId | INT UNSIGNED FK→LookupValues NULL | REPORT_STATUS — PENDING/REVIEWED/DISMISSED/RESOLVED |
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
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized |
| CommentCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized |
| AcknowledgeCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized |
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

**Indexes:** `idx_cpl_post (CommunityPostId)`, `idx_cpl_user (UserId)`

#### CommunityPostComments
| Column | Type | Notes |
|---|---|---|
| CommunityCommentId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| Content | TEXT NOT NULL | Max 2000 chars enforced at API layer |
| LikeCount | INT UNSIGNED NOT NULL DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

**Indexes:** `idx_cpc_post (CommunityPostId)`, `idx_cpc_user (UserId)`

#### CommunityCommentLikes
| Column | Type | Notes |
|---|---|---|
| CommunityCommentLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityCommentId | INT UNSIGNED FK→CommunityPostComments NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (CommunityCommentId, UserId) | Toggle via INSERT…ON DUPLICATE KEY DELETE |

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
| UserId | INT UNSIGNED FK→Users NOT NULL | Victim (actual column name `UserId`, not `VictimUserId`) |
| OrgId | INT UNSIGNED FK→Organisations NULL | Org the victim belongs to |
| AlertTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | SOS_ALERT_TYPE |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | SOS_STATUS — ACTIVE/RESOLVED/CANCELLED |
| Description | TEXT NULL | |
| ApproxLocation | VARCHAR(300) NULL | Human-readable location |
| Latitude | DECIMAL(10,7) NULL | Initial GPS latitude |
| Longitude | DECIMAL(10,7) NULL | Initial GPS longitude |
| CancelReason | TEXT NULL | |
| ResolvedByLkpId | INT UNSIGNED FK→LookupValues NULL | Audit only |
| ResolvedAt | DATETIME NULL | |
| CancelledAt | DATETIME NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

**Indexes:** `idx_sos_user (UserId)`, `idx_sos_org (OrgId)`, `idx_sos_status (StatusLkpId)`

#### SosResponders
| Column | Type | Notes |
|---|---|---|
| SosResponderId | INT UNSIGNED PK AUTO_INCREMENT | |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | Responder |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| CanViewLocation | TINYINT(1) DEFAULT 0 | |
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
| PausedAt | DATETIME NULL | |
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
| AuditLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — every write operation |
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
| IsDeleted | TINYINT(1) DEFAULT 0 | Soft delete (preserves FK integrity) |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (LookupTypeId, ValueCode) | |

---

### Group 10 — Settings (1 table)

#### Settings
| Column | Type | Notes |
|---|---|---|
| SettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| SettingGroup | VARCHAR(50) NOT NULL | SMS, OTP, AUTH, UPLOAD, PROJECT, etc. |
| SettingKey | VARCHAR(100) UNIQUE NOT NULL | |
| SettingValue | TEXT NOT NULL | |
| DataType | VARCHAR(20) DEFAULT 'STRING' | STRING/NUMBER/BOOLEAN/URL/JSON |
| Description | VARCHAR(500) NULL | |
| IsPublic | TINYINT(1) DEFAULT 0 | Safe for frontend |
| IsEditable | TINYINT(1) DEFAULT 1 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |
| UpdatedBy | INT UNSIGNED NULL | |

> **SettingsCache:** All settings loaded at startup into singleton. Zero DB reads on config access.  
> **IsPublic=1:** returned by `GET /api/v1/settings/public` — never expose secrets.

**Key Settings (PROJECT group — v4.4):**

| SettingKey | Value | Description |
|---|---|---|
| QR_EXPIRY_MINUTES | 60 | QR code validity window in minutes after generation |
| QR_BUFFER_MINUTES | 15 | Minutes before session start that admin can generate QR |

---

## LookupTypes (44 Types)

| TypeCode | Values / Notes |
|---|---|
| GENDER | Male, Female, Non-Binary, Prefer Not to Say |
| ORG_TYPE | Trust, Society, Section 8 Company, NGO *(v4.3)*, Foundation *(v4.3)*, Charitable Institution *(v4.3)*, Religious Trust *(v4.3)*, CSR Foundation *(v4.3)*, Educational Trust *(v4.3)* |
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
| ATTENDANCE_STATUS | Attended, No Show, Excused |
| SESSION_STATUS | Upcoming, Active, Completed, Cancelled |
| ATTENDANCE_METHOD | QR Scan, Manual, GPS |
| BADGE_TYPE | First Volunteer, 10 Hours, 50 Hours, 100 Hours, 500 Hours, Mentor, Top Donor, SOS Hero, Community Leader, Impact Champion |
| EDUCATION | Below 10th, 10th Pass, 12th Pass, Diploma, Graduate, Post Graduate, Doctorate |
| WORK_EXPERIENCE | Fresher, 1-2 Years, 3-5 Years, 6-10 Years, 10+ Years |
| INTEREST_TYPE | Education, Healthcare, Environment, Sports, Arts, Technology, Community, Animal Welfare |
| DOCUMENT_TYPE_USER | **v4.4 UPDATED** — Photo ID (PHOTO_ID), Address Proof (ADDR_PROOF), Passport (PASSPORT), Driving License (DRIVING_LIC), Other (OTHER). *Previous India-specific values (AADHAAR, PAN, VOTER_ID) soft-deleted for global compatibility.* |
| DOC_TYPE_ORG | Registration Certificate, 80G Certificate, 12A Certificate, FCRA Certificate, CSR Policy, Annual Report |
| POST_TYPE_FEED | Update, Announcement, Opportunity, Story, Article |
| POST_VISIBILITY | Public, Followers, Organisation Members, Private |
| POST_TYPE_COMMUNITY | Discussion, Question, Announcement, Resource, Event, Achievement |
| REPORT_REASON | Spam, Inappropriate Content, Misleading, Hate Speech, Harassment, Other |
| REPORT_STATUS | Pending, Under Review, Action Taken, Dismissed, Resolved |
| MEDIA_TYPE | IMAGE, VIDEO, Document, Audio |
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
| CERTIFICATE_TYPE | Volunteer Completion, Skills Assessment, Training, Achievement |
| SETTING_DATA_TYPE | String, Number, Boolean, URL, JSON |
| BENEFICIARY_TYPE | Individual, Family, Community, Institution |
| LANGUAGE | English, Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, Gujarati |
| COUNTRY | India, USA, UK, Canada, Australia, UAE, Singapore, Germany |

---

## Stored Procedures (114 Total)

### Auth (6 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Auth_SendOTP | p_Recipient, p_CountryCode, p_OtpCode, p_PurposeLkpId, p_IpAddress, p_ExpiryMinutes | WRITE | Generates OTP; enforces 3/10min rate limit; max 3 attempts then lock |
| Auth_VerifyOTP | p_Recipient, p_OtpCode, p_PurposeLkpId, p_IpAddress | WRITE | Validates OTP; auto-creates User + UserProfiles row on first login; returns `UserId, IsNewUser` |
| Auth_SaveRefreshToken | p_UserId, p_Token, p_DeviceInfo, p_IpAddress, p_ExpiresAt | WRITE | Stores hashed token; enforces max 5 active sessions per user |
| Auth_GetRefreshToken | p_Token | READ | Validates hashed token; returns `IsSuccess, UserId, Recipient, RefreshTokenId` |
| Auth_RevokeRefreshToken | p_Token | WRITE | Soft-revokes by hashed token (logout) |
| Auth_RevokeRefreshTokenById | p_RefreshTokenId | WRITE | Revokes by ID (used during token rotation) |

### User (17 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| User_GetProfile | p_UserId, p_RequestingUserId | GET | Full profile including `VolunteerExp`, `IsVerified`, `CountryCode`, `MemberSince`, `IsProfileComplete`, `GenderLkpId`, `EducationLkpId`, `WorkExpLkpId` and lookup names |
| User_GetPublicProfile | p_UserId | GET (Dynamic) | Public-safe profile — no sensitive fields |
| User_UpdateProfile | p_UserId + 18 profile params | WRITE | 19 params — all fields COALESCE (partial update safe); includes `p_VolunteerExp` |
| User_UpdateSafetyPrefs | p_UserId, p_EmergVisibilityLkpId, p_AutoShareDurLkpId, p_AllowLocDuringSos, p_AllowLocDuringProj, p_EmergencyContactName, p_EmergencyContactPhone, p_EmergencyContactRelation | WRITE | 8 params — UPSERT on UserId; all fields COALESCE |
| User_SaveInterests | p_UserId, p_InterestLkpIds (JSON) | WRITE | DELETE all existing interests + INSERT from JSON array |
| User_UploadDocument | p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb | WRITE | **v4.4 UPDATED** Upsert pattern: soft-deletes existing doc of same type for user before inserting new. One doc per type per user enforced. Returns `IsSuccess`, `Message`, `UserDocumentId` |
| User_GetDocuments | p_UserId | LIST | **v4.4 NEW** Lists all active documents for user. Returns: `UserDocumentId`, `UserId`, `DocumentTypeLkpId`, `DocTypeCode`, `DocTypeName`, `FileUrl`, `FileName`, `FileSizeKb`, `IsVerified`, `UploadedAt` |
| User_DeleteDocument | p_UserDocumentId, p_UserId | WRITE | **v4.4 NEW** Soft-deletes a document. Validates `UserId` ownership. Returns `IsSuccess`, `Message` |
| User_GetSkills | p_UserId | LIST | Returns UserSkills with AvgRating, RatingCount |
| User_AddSkill | p_UserId, p_SkillName | WRITE | Insert; returns `UserSkillId`; 0 if duplicate |
| User_RemoveSkill | p_UserId, p_UserSkillId | WRITE | Soft-delete (IsDeleted=1) |
| User_GetSafetyPrefs | p_UserId | GET | Returns safety prefs + emergency contacts |
| User_GetInterests | p_UserId | LIST | Returns user's saved interests with lookup names |
| User_GetMyOrgs | p_UserId | LIST (Dynamic) | Returns all orgs the user is an APPROVED member of. Returns: `OrgId`, `OrgName`, `LogoUrl`, `OrgType`, `City`, `State`, `Role`, `RoleCode`, `MemberStatusCode`, `OrgStatusCode`, `MemberCount`, `JoinedAt` |
| User_GetBadges | p_UserId | LIST | Returns all earned badges: `UserBadgeId`, `BadgeLkpId`, `BadgeName`, `BadgeCode`, `OrgName`, `ProjectName`, `AwardedAt` |
| User_GetImpact | p_UserId | GET | **v4.4 REBUILT** ImpactScore calculated inline (Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5 − NoShows×20 − Withdrawals×15). Returns: `ImpactScore`, `ReliabilityPct`, `ProjectsCompleted`, `TotalHours`, `BadgeCount`, `SkillCount`, `ProjectsApplied`, `CertificateCount`, `MemberSince`, `NgosJoined`, `PendingApplications`, `ApprovedApplications`, `RankNumber`, `TotalRanked`, `RankName` (Newcomer/Helper/Active Volunteer/Committed Volunteer/Gold/Platinum/Diamond/Elite), `FirstName`, `LastName`, `ProfilePhoto`, `Bio` |

### Lookup (4 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Lookup_GetAllTypes | — | LIST | All active LookupTypes |
| Lookup_GetValuesByTypeCode | p_TypeCode | LIST | All values for a given TypeCode |
| Lookup_GetValueByCode | p_TypeCode, p_ValueCode | GET | Single lookup value; returns `LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault` |
| Lookup_GetValuesByType | p_TypeCode | LIST | Alias for Lookup_GetValuesByTypeCode |

### Settings (4 SPs)
| SP Name | Type | Description |
|---|---|---|
| Settings_GetPublic | READ | IsPublic=1 settings |
| Settings_GetByGroup | READ | Filter by SettingGroup |
| Settings_GetAll | READ | Admin only |
| Settings_Update | WRITE | Update value, refresh cache |

### Organisation (28 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Org_Register | p_UserId, p_OrgName, p_RegistrationNo, p_OrgTypeLkpId, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country | WRITE | 19 params. Creates org + adds creator as ADMIN member. Returns `IsSuccess`, `Message`, `OrgId` |
| Org_GetProfile | p_OrgId | GET | Full org profile — returns `OrgTypeLkpId`, `StatusLkpId`, `Category`, `ContactPerson` for edit form pre-fill |
| Org_Update | p_OrgId, p_UserId, p_OrgName, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country | WRITE | 18 params — all fields COALESCE (partial update safe) |
| Org_GetDashboard | p_OrgId | GET | **v4.4 REBUILT** Admin dashboard KPIs. Returns: `TotalMembers`, `NewMembersThisMonth`, `ActiveVolunteers`, `ActiveRatePct`, `VolunteerHoursMonth`, `ActiveProjects`, `PendingApplications` (member join requests), `PendingProjectApplications` (volunteer project applications) |
| Org_List | p_Keyword, p_Category, p_PageNumber, p_PageSize | PAGED | Always returns APPROVED orgs only. Filters by keyword + category. Returns `OrgId`, `OrgName`, `Category`, `LogoUrl`, `City`, `State`, `MemberCount`, `AvgRating`, `Latitude`, `Longitude` + TotalCount |
| Org_ListRecommended | p_UserId | LIST | Matches user's INTEREST_TYPE ValueCodes against org Category; returns up to 20 orgs + `MatchScore` |
| Campaign_ListPublicTrending | p_PageSize | LIST | Active campaigns ranked by IsEmergency → DonorCount → RaisedAmount |
| Org_GetDonationDashboard | p_OrgId | GET | 9 donation KPIs for s-admin-donations screen |
| Org_GetDonors | p_OrgId, p_Tab (ALL/RECURRING/TOP), p_PageNumber, p_PageSize | PAGED | Donor list; respects IsAnonymous flag |
| Org_GetTransactions | p_OrgId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | Transaction list; filter by statusCode (null = all) |
| Org_GetVolunteerProfile | p_OrgId, p_UserId | GET | Admin view of volunteer — includes reliability score (private to admins) |
| Org_GetMemberImpact | p_OrgId, p_UserId | GET | Admin view for s-member-impact |
| Org_UpdateMemberRole | p_OrgId, p_MemberId, p_RoleLkpId, p_UpdatedBy | WRITE | Changes member's role |
| Org_GetMembers | p_OrgId | LIST (Dynamic) | All members with role, status, permissions |
| Org_AddMember | p_OrgId, p_UserId, p_RoleLkpId, p_RequestedBy | WRITE | Direct add (admin action) |
| Org_RemoveMember | p_OrgId, p_UserId, p_RequestedBy | WRITE | Soft remove |
| Org_RequestMembership | p_OrgId, p_UserId, p_Message | WRITE | User self-requests; stores RequestMessage |
| Org_ReviewMembership | p_RequestId, p_StatusCode, p_AdminNotes, p_ReviewedBy | WRITE | APPROVED/REJECTED with AdminNotes |
| Org_GetPendingMembers | p_OrgId | LIST (Dynamic) | PENDING approval requests |
| Org_UpdateMemberPermissions | p_OrgId, p_MemberId, p_CanPost, p_CanComment, p_CanCommunityPost, p_MaxPostsPerDay, p_LocationSharingLkpId, p_UpdatedBy | WRITE | Granular member permissions |
| Org_UploadDocument | p_OrgId, p_UploadedBy, p_DocumentTypeLkpId, p_FileUrl, p_FileName | WRITE | Inserts into OrgDocuments |
| Org_GetAdminPosts | p_OrgId | LIST (Dynamic) | **v4.4 NEW** All feed Posts for org with: `FullName`, `ProfilePhoto`, `RoleCode`, `RoleName`, `Content`, `LikesCount`, `CommentsCount`, `IsPinned`, `CreatedAt`, `ReportCount` (PENDING reports only), `StatusCode` (PUBLISHED or REPORTED) |
| Org_PinPost | p_PostId, p_OrgId, p_PinnedBy | WRITE | **v4.4 NEW** Toggles IsPinned on a post. Validates post belongs to org. Returns `IsSuccess`, `Message` ("Post pinned." / "Post unpinned.") |
| Org_DeletePost | p_PostId, p_OrgId, p_DeletedBy | WRITE | **v4.4 NEW** Soft-deletes a feed post. Validates post belongs to org. Returns `IsSuccess`, `Message` |
| Org_ModeratePost | p_PostId, p_OrgId, p_ReviewedBy, p_Action (`KEEP`/`REMOVE`) | WRITE | **v4.4 NEW** Resolves all pending reports on post. If REMOVE, also soft-deletes post. Returns `IsSuccess`, `Message` ("Reports cleared." / "Post removed.") |

### Project (14 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Project_Create | p_UserId, p_OrgId, p_Title, p_Description, p_Category, p_ProjectTypeLkpId, p_JoinTypeLkpId, p_StatusLkpId, p_MaxVolunteers, p_MinAge, p_MaxAge, p_IsPublic, p_StartDate, p_EndDate, p_ScheduleType, p_RecurrenceDays, p_StartTime, p_EndTime, p_DurationMinutes, p_LocationTypeLkpId, p_LocationTypeCode, p_LocationName, p_Address, p_Latitude, p_Longitude, p_GoogleMapsUrl, p_GenderRestriction, p_RequiresApproval, p_CoverImageUrl, p_City, p_State, p_IsDraft | WRITE | 32 params. Maps schedule dates into correct columns. Returns `IsSuccess`, `Message`, `ProjectId` |
| Project_GetById | p_ProjectId, p_UserId | GET | Full project details with org name, schedule, status, `ApprovedVolunteers` count, `MyApplicationStatusId` |
| Project_Update | p_ProjectId + 31 params (same as Create minus p_OrgId) | WRITE | 32 params. COALESCE-safe partial update. Returns `IsSuccess`, `Message` |
| Project_List | p_OrgId, p_Category, p_City, p_StatusCode, p_TypeCode, p_PageNumber, p_PageSize, p_UserLat, p_UserLon | PAGED | **v4.4 UPDATED** — 9 params. Returns `ScheduleType`, `LocationName`, `Address`, `ApprovedCount`, `StatusCode`, `Latitude`, `Longitude`, `DistanceKm` (Haversine; NULL if no coords provided). Sorted by `DistanceKm ASC` when coords provided, else `CreatedAt DESC` |
| Project_AddSkill | p_ProjectId, p_SkillName, p_IsRequired | WRITE | Inserts ProjectSkill |
| Project_AddSession | p_ProjectId, p_SessionDate, p_StartTime, p_EndTime, p_MaxVolunteers, p_CreatedBy | WRITE | **v4.4 UPDATED** Duplicate guard: returns `IsSuccess=0` + existing `SessionId` if a session already exists for same project+date |
| Project_GetSessions | p_ProjectId, p_PageNumber, p_PageSize | PAGED | **v4.4 UPDATED** `SessionDate` returned via `DATE_FORMAT('%Y-%m-%d')` to prevent .NET DateTime timezone shift. Returns: `SessionId`, `SessionDate` (string), `StartTime`, `EndTime`, `MaxVolunteers`, `StatusCode`, `Status`, `QrCode`, `QrExpiresAt` + TotalCount |
| Project_GetSessionQr | p_SessionId, p_UserId | GET | **v4.4 REBUILT** Enforces time-window: QR available from `(SessionStart − QR_BUFFER_MINUTES)` to `SessionEnd`. Returns `IsSuccess=0` with descriptive message when called too early or after session ends. Reads `QR_BUFFER_MINUTES` + `QR_EXPIRY_MINUTES` from Settings. Returns: `IsSuccess`, `Message`, `QrToken` |
| Project_CheckIn | p_QrToken, p_UserId, p_SessionId | WRITE | Validates QR token, records attendance |
| Project_Apply | p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions | WRITE | Inserts application with `Motivation` (was `Note`) and optional `RequestedSessions` |
| Project_ReviewApplication | p_ApplicationId, p_StatusLkpId, p_RejectionReason, p_ReviewedBy | WRITE | APPROVED/REJECTED. Param is `p_RejectionReason` (not `p_AdminNotes`) |
| Project_GetApplications | p_ProjectId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | Alias — same as Application_GetByProject |
| Project_Complete | p_ProjectId, p_OrgId, p_CompletedBy | WRITE | Sets status COMPLETED, triggers certificate generation |
| Project_ManualAttendance | p_ApplicationId, p_MarkedBy | WRITE | **v4.4 NEW** Admin marks volunteer ATTENDED for most recent past session. Validates: application must be APPROVED or NO_SHOW. Uses `QrScannedAt=NULL` to distinguish from QR scan. Idempotent (ON DUPLICATE KEY UPDATE). Returns `IsSuccess`, `Message` |

### Application (4 SPs — standalone module)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Application_Apply | p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions | WRITE | **v4.4 UPDATED** Params renamed: `p_Note` → `p_Motivation`; `p_RequestedSessions` added |
| Application_GetByProject | p_ProjectId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | **v4.4 REBUILT** Joins `ProjectAttendance` via correlated subquery. Attendance status takes precedence over application status (COALESCE). Returns: `ApplicationId`, `UserId`, `ApplicantName`, `ProfilePhoto`, `City`, `Profession`, `Motivation`, `RequestedSessions`, `StatusCode`, `Status`, `StatusUpdatedAt`, `CreatedAt`, `CheckedInAt`, `HoursLogged`, `IsExcused`, `QrScannedAt`, `AdminNote`, `SessionDate`, `SessionStartTime`, `SessionEndTime` + TotalCount |
| Application_Review | p_ApplicationId, p_StatusLkpId, p_RejectionReason, p_ReviewedBy | WRITE | Uses `StatusLkpId` (INT) |
| Application_GetByUser | p_UserId, p_PageNumber, p_PageSize | PAGED | **v4.4 REBUILT** 3 params (was 1). Returns: `ApplicationId`, `ProjectId`, `ProjectName`, `OrgName`, `OrgLogoUrl`, `StatusCode`, `Status`, `CreatedAt`, `StatusUpdatedAt`, `ScheduleTypeCode`, `ScheduleTypeName`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `Landmark`, `City`, `ProjectStatusCode`, `ProjectStatus` + TotalCount |

### Post / Feed (11 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Post_Create | p_UserId, p_OrgId, p_Content, p_MediaUrls, p_PostTypeLkpId, p_VisibilityLkpId | WRITE | **v4.4 UPDATED** Auto-detects VIDEO vs IMAGE from URL extension via REGEXP (`mp4\|mov\|avi\|mkv\|webm\|m4v\|3gp\|wmv`). Assigns correct `MediaTypeLkpId` per URL in PostMedia. Returns `IsSuccess`, `Message`, `PostId` |
| Post_GetFeed | p_UserId, p_PageNumber, p_PageSize | PAGED | **v4.4 REBUILT** Returns: `PostId`, `Content`, `IsPinned`, `PostTypeLkpCode`, `PostType`, `LikeCount`, `CommentCount`, `IsLikedByMe`, `UserId`, `AuthorName`, `ProfilePhoto`, `OrgId`, `OrgName`, `MediaUrls` (GROUP_CONCAT of FileUrl ordered by SortOrder, comma-separated), `MediaTypes` (GROUP_CONCAT of MEDIA_TYPE ValueCode per media item, comma-separated), `CreatedAt`, `TimeAgo`. Pinned posts sorted first (`ORDER BY IsPinned DESC, CreatedAt DESC`) |
| Post_GetById | p_PostId, p_UserId | GET | Single post with like/comment counts |
| Post_Delete | p_PostId, p_UserId | WRITE | Soft delete |
| Post_Pin | p_PostId, p_OrgId, p_PinnedBy | WRITE | Toggle IsPinned |
| Post_Like | p_PostId, p_UserId | WRITE | INSERT IGNORE into PostLikes |
| Post_Unlike | p_PostId, p_UserId | WRITE | DELETE from PostLikes |
| Post_AddComment | p_PostId, p_UserId, p_Content, p_ParentCommentId | WRITE | Supports threading via ParentCommentId |
| Post_GetComments | p_PostId, p_PageNumber, p_PageSize | PAGED | Nested comments |
| Post_Report | p_PostId, p_UserId, p_ReasonCode, p_Details | WRITE | **v4.4 REBUILT** `p_ReasonCode VARCHAR(50)` (e.g. SPAM, HATE, INAPPROPRIATE, SCAM, OTHER). SP resolves `LookupValueId` internally. Prevents duplicate reports from same user on same post. Returns `IsSuccess`, `Message` |

### Community (9 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Community_CreatePost | p_UserId, p_OrgId, p_Title, p_Content, p_PostTypeLkpId, p_AudienceLkpId | WRITE | Creates org-scoped community post. Auto-defaults `AudienceLkpId` to ALL_MEMBERS if NULL. Returns `IsSuccess`, `Message`, `CommunityPostId` |
| Community_GetFeed | p_OrgId, p_UserId, p_PageNumber, p_PageSize | PAGED (Dynamic) | Returns `PollOptionsJson` (JSON array per poll post), `RoleName` (author's org role), `TimeAgo`, `IsLiked`, `IsAcknowledged`, `LikeCount`, `CommentCount` + TotalCount |
| Community_AcknowledgePost | p_CommunityPostId, p_UserId | WRITE | Marks post acknowledged; increments AcknowledgeCount |
| Community_CreatePoll | p_UserId, p_OrgId, p_Question, p_OptionsJson, p_ExpiresInHours | WRITE | Creates CommunityPost of type POLL + PollOptions from JSON array. Returns `IsSuccess`, `Message`, `PollId` |
| Community_Vote | p_PollId, p_UserId, p_PollOptionId | WRITE | INSERT IGNORE — one vote per user, checks expiry |
| Community_LikePost | p_CommunityPostId, p_UserId | WRITE | Toggle like. Returns `IsLiked INT`, `LikeCount INT` |
| Community_AddComment | p_CommunityPostId, p_UserId, p_Content | WRITE | Increments CommentCount. Returns `IsSuccess`, `Message`, `CommunityCommentId` |
| Community_GetComments | p_CommunityPostId, p_UserId | LIST (Dynamic) | Returns: `CommunityCommentId`, `UserId`, `AuthorName`, `ProfilePhoto`, `Content`, `LikeCount`, `IsLiked`, `TimeAgo`, `CreatedAt` |
| Community_LikeComment | p_CommunityCommentId, p_UserId | WRITE | Toggle like on a comment. Returns `IsLiked INT`, `LikeCount INT` |

### SOS (12 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Sos_Trigger | p_UserId, p_AlertTypeLkpId, p_OrgId, p_Latitude, p_Longitude, p_ApproxLocation, p_Description | WRITE | Creates SosIncident (status=ACTIVE). Returns `IsSuccess`, `Message`, `SosIncidentId` |
| Sos_GetActive | p_UserId, p_OrgId | LIST (Dynamic) | Active incidents visible to user for their org |
| Sos_GetMyActive | p_UserId | GET (2 result sets) | Returns victim's own active incident + responders list |
| Sos_GetById | p_SosIncidentId, p_UserId | GET (2 result sets) | All JOINs LEFT. Result 1: incident with `AlertTypeName`, `StatusName`. Result 2: responders with `ProfilePhoto`, `ApprovalStatusName` |
| Sos_Respond | p_SosIncidentId, p_UserId | WRITE | Inserts into SosResponders (status=PENDING). Returns `IsSuccess`, `Message`, `SosResponderId` |
| Sos_ApproveResponder | p_SosIncidentId, p_UserId, p_SosResponderId, p_CanViewLocation | WRITE | Updates ApprovalStatusLkpId to APPROVED. Only victim can approve |
| Sos_Resolve | p_SosIncidentId, p_UserId | WRITE | Sets RESOLVED. Only victim can resolve |
| Sos_Cancel | p_SosIncidentId, p_UserId, p_CancelReason | WRITE | Sets CANCELLED. Only victim can cancel |
| Sos_GetLatestLocation | p_SosIncidentId, p_UserId | GET | Returns latest SosLocationLogs row. Access gate: victim or APPROVED responder with CanViewLocation=1 |
| Sos_UpdateLocation | p_SosIncidentId, p_UserId, p_Latitude, p_Longitude, p_Accuracy | WRITE | Inserts into SosLocationLogs (called every ~10s) |
| Sos_GetOrgAlerts | p_OrgId, p_UserId, p_Limit | LIST (Dynamic) | All SOS incidents for org (ACTIVE + RESOLVED + CANCELLED); returns `IsActive`, `AlertTypeName`, `StatusName`, `MyApprovalStatus` |
| Sos_DeclineResponder | p_SosIncidentId, p_SosResponderId, p_DeclinedBy | WRITE | Victim declines a pending responder. Sets REJECTED. Validates `p_DeclinedBy` = incident `UserId` |

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
| Donation_ResumeRecurring | WRITE | IsActive=1, PausedAt=NULL |
| Donation_CancelRecurring | WRITE | Marks inactive permanently |
| Donation_GetAnnualSummary | GET | Year summary + per-NGO breakdown (2 result sets) |
| Donation_GetSupportedNGOs | LIST | All NGOs a donor has supported |

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
| UserBadge_Award | p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId | WRITE | Awards badge from NGO admin. Returns `IsSuccess`, `Message`, `BadgeId` |
| Attendance_ExcuseNoShow | p_AttendanceId, p_OrgId, p_ExcusedBy | WRITE | Marks a NO_SHOW as EXCUSED — no reliability score penalty. Validates attendance belongs to this org |

### Notification (6 SPs)
| SP Name | Type | Description |
|---|---|---|
| Notification_GetByUser | PAGED | p_OnlyUnread filter |
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
| QrScannedAt=NULL convention | Distinguishes admin manual attendance from volunteer QR scan |
| One doc per type per user | User_UploadDocument upserts — clean replacement, no duplicates |
| DOCUMENT_TYPE_USER universalized | Replaced India-specific with globally applicable categories |

---

*NGOConnect v4.4 — 50 Tables, 114 Stored Procedures, 44 LookupTypes*  
*v4.4 adds: Project_List distance (Haversine, p_UserLat/p_UserLon); User_GetImpact full rebuild (inline score + 9 new return cols); Application_GetByUser paged + 8 new return cols; Post_Report p_ReasonCode; User doc management (User_GetDocuments, User_DeleteDocument, User_UploadDocument upsert); 4 new Org post admin SPs; Project_GetSessionQr time-window; Application_GetByProject attendance status override; Project_ManualAttendance; Post_GetFeed MediaUrls+MediaTypes+TimeAgo; Post_Create video auto-detect; QR Settings seeds; DOCUMENT_TYPE_USER universalized.*  
*Run `NGOConnect_Complete_Setup_v4.4.sql` to install fresh. For incremental: run all patch files in Documents/ folder against your database.*

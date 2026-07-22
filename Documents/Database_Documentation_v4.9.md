# NGOConnect Database Documentation v4.9

**Database:** MySQL 8.0+  
**Version:** 4.9  
**Tables:** 55  
**Stored Procedures:** 163  
**Generated:** 2026-07-18  


**v4.9 Additions — FCM Notifications, Verification Badges, Tax Eligibility, Community All Post Types, Permission Enforcement, SuperAdmin Enhancements (2026-07-18):**

- **UserDeviceTokens table** — NEW. Stores FCM push notification tokens per user device. Maintained by `Notification_SaveDeviceToken` SP. Auto-cleaned by `Notification_DeleteStaleToken` when Firebase returns `Unregistered`.
- **Organisations table** — NEW COLUMNS: `VerificationStatusLkpId INT UNSIGNED NULL FK→LookupValues` (INDEX `idx_org_verification`); `Is80GEligible TINYINT(1) DEFAULT 0`; `Is12AEligible TINYINT(1) DEFAULT 0`.
- **Notifications table** — COLUMN RENAMES: `TypeLkpId` → `NotifType VARCHAR(50)`, `EntityType` → `RefType VARCHAR(50)`, `EntityId` → `RefId INT UNSIGNED`; NEW COLUMN `OrgId INT UNSIGNED NULL FK→Organisations` (INDEX `idx_notif_org`); NEW COLUMNS `IsRead TINYINT(1)` renamed fix, `ReadAt DATETIME NULL`.
- **CommunityPosts table** — NEW COLUMNS: `IsPinned TINYINT(1) DEFAULT 0` (ANNOUNCEMENT type pin); `VolunteersNeeded INT UNSIGNED NULL` (VOL_REQUEST slot count); `EventRef VARCHAR(200) NULL` (multi-purpose: whatChanged for EVENT_UPDATE, date/time for VOL_REQUEST, assignee name for TASK); `ResourceFileUrl VARCHAR(500) NULL` (RESOURCE type file attachment); `PollIsMultiChoice TINYINT(1) DEFAULT 0` (multi-select poll flag).
- **LookupTypes** — NEW TYPE `ORG_VERIFICATION_STATUS`: PENDING, VERIFIED, REJECTED. `PROFILE_VERIFICATION_STATUS` — added REJECTED value. `REPORT_STATUS` seeds fixed: PENDING, REVIEWED, RESOLVED.
- **Auth_VerifyOTP** — UPDATED. New `p_CountryCode VARCHAR(6)` param; new-user INSERT uses `IFNULL(NULLIF(p_CountryCode, ''), '+91')` instead of hardcoded `'+91'`.
- **Org_Register** — UPDATED. Added `p_Is80GEligible TINYINT(1)` + `p_Is12AEligible TINYINT(1)` (21 params). INSERT now includes `Is80GEligible`, `Is12AEligible` columns.
- **Org_Update** — UPDATED. Added `p_Is80GEligible TINYINT(1) NULL` + `p_Is12AEligible TINYINT(1) NULL`; COALESCE partial-update pattern.
- **Org_Resubmit** — UPDATED. Added `p_Is80GEligible TINYINT(1)` + `p_Is12AEligible TINYINT(1)`; direct assignment (full-redeclaration semantics).
- **Org_GetProfile** — UPDATED. Returns `Is80GEligible`, `Is12AEligible` (COALESCE from OrgDonationSettings OR Organisations). Added `VerificationStatusCode` from `ORG_VERIFICATION_STATUS` lookup.
- **Org_GetDocuments** — NEW SP. Returns org admin's uploaded documents from OrgDocuments with DocumentTypeLkpId, DocumentTypeCode (ValueCode), DocumentType (ValueName), FileUrl, FileName, IsVerified, VerifiedAt, CreatedAt.
- **Org_UpdateMemberRole** — UPDATED. `p_RoleLkpId INT` → `p_RoleCode VARCHAR(50)`. SP resolves LkpId internally via MEMBER_ROLE lookup. Success SELECT returns `UserId` (for FCM trigger).
- **SuperAdmin_Org_GetDetail** — UPDATED. Added `Is80GEligible`, `Is12AEligible`, `ContactPerson`, `ContactEmail`, `ContactPhone` to SELECT.
- **SuperAdmin_Org_VerifyProfile** — NEW SP. `(p_OrgId, p_StatusCode, p_SuperAdminUserId)`. Sets `VerificationStatusLkpId`. Returns IsSuccess, Message.
- **SuperAdmin_User_GetList** — UPDATED. HAVING clause zero-org-membership branch is now unconditional `COUNT(om.OrgMemberId) = 0` (removed `p_OrgIds IS NULL` condition — new users now always appear regardless of org filter).
- **Community_CreatePost** — MAJOR UPDATE. Now 10 params: `p_UserId, p_OrgId, p_Title, p_Content, p_PostTypeLkpId, p_AudienceLkpId, p_ResourceFileUrl, p_IsPinned, p_VolunteersNeeded, p_EventRef`. INSERT includes new columns. Permission gate: checks OrgMembers.CanCommunityPost.
- **Community_CreatePoll** — UPDATED. Permission gate: checks OrgMembers.CanCommunityPost.
- **Post_GetPermissions** — UPDATED. Added `CanComment TINYINT(1)` and `CanCommunityPost TINYINT(1)` to SELECT (reads from OrgMembers).
- **Post_Create** — UPDATED. Permission gate: checks OrgMembers.CanPost + MaxPostsPerDay before INSERT.
- **Post_AddComment** — UPDATED. Permission gate: checks OrgMembers.CanComment. Non-members blocked from commenting.
- **Post_GetFeed** — UPDATED. Added `NOT EXISTS (SELECT 1 FROM PostReports WHERE PostId = p.PostId AND ReportedByUserId = p_UserId)` — reported posts immediately hidden from reporter's feed.
- **Application_Apply** — UPDATED. Explicit `RequestedSessions` column add guard; fix: removed duplicate DROP+CREATE that used wrong column name.
- **Application_Review** — UPDATED. Returns `ApplicantUserId`, `ProjectId` in success SELECT (for FCM APPROVED/REJECTED triggers).
- **Notification_Create** — UPDATED. Fixed column names (`NotifType`, `RefId`, `RefType`). Added `p_OrgId INT UNSIGNED NULL` param; inserts into `Notifications.OrgId`.
- **Notification_GetByUser** — UPDATED. `LEFT JOIN Organisations` on `n.OrgId`; returns `OrgId`, `OrgName`, `OrgLogoUrl`. Removed `IsDeleted` condition (column doesn't exist). Fixed column names to match actual schema.
- **Notification_GetUnreadCount** — UPDATED. Removed `IsDeleted = 0` condition.
- **Notification_DeleteStaleToken** — NEW SP. Deletes stale/unregistered FCM tokens from UserDeviceTokens. Auto-called by C# FCMService when Firebase returns `Unregistered`.
- **6 new Notification_GetTokens* SPs** — `Notification_GetTokenByUserId`, `Notification_GetTokensByOrgId`, `Notification_GetAdminTokensByOrgId`, `Notification_GetTokensByProjectId`, `Notification_GetTokensBySosIncidentId`.
- **Org_ReviewMembership** — UPDATED. Returns `ApplicantUserId`, `OrgId` in success SELECT.
- **Sos_ApproveResponder** — UPDATED. Returns `ResponderUserId` in success SELECT.
- **Org_UpdateMemberRole** — UPDATED. Returns `UserId` in success SELECT.
- **Attendance_ExcuseNoShow** — UPDATED. Returns `UserId`, `ProjectId` in success SELECT.
- **Project_CheckIn** — UPDATED. Returns `ProjectId` in success SELECT.
- **Project_ManualAttendance** — UPDATED. Returns `v_UserId AS UserId, v_ProjectId AS ProjectId` in success SELECT.
- **Withdrawal_AdminReview** — UPDATED. Reads and returns `OrgId` in success SELECT.
- **Sos_Respond** — UPDATED. Returns `v_VictimUserId AS VictimUserId` in success SELECT.
- **User_GetMyOrgs** — UPDATED. Added `RejectionReason` to SELECT (first result set); `NULL AS RejectionReason` in second UNION result set (column count parity).
- **Donation_ConfirmPayment** — UPDATED. Fixed column names `Amount`→`DonationAmount`, `StatusLkpId`→`PayStatusLkpId`; returns `DonorUserId`, `OrgId`, `CampaignId`.
- **Org_GetMembers / Org_GetPendingMembers** — UPDATED. Returns `ProfileVerificationStatusCode` (COALESCE from PROFILE_VERIFICATION_STATUS lookup).

---

**v4.8 Additions — Community Fixes + Contact OTP + Nearby Feed + Phase 1 Personalised Feed (2026-07-12):**

- **Posts table** — NEW COLUMNS: `IsEmergency TINYINT(1) DEFAULT 0`, `IsEvergreen TINYINT(1) DEFAULT 0`, `ShareCount INT UNSIGNED DEFAULT 0`, `SaveCount INT UNSIGNED DEFAULT 0`; NEW INDEX `idx_post_emergency (IsEmergency, CreatedAt)`.
- **PostSaves table** — NEW. Records posts saved by users. UNIQUE KEY `(PostId, UserId)`. Maintained by `Post_Save` / `Post_Unsave` SPs (idempotent). Counter denormalized to `Posts.SaveCount`.
- **FeedInteractions table** — NEW. Analytics log: every user action on a feed post (impression, view, like, share, save, click, hide, report). Fire-and-forget writes. Future AI training data.
- **22 FEED_* Settings seeds** — NEW. Group `FEED`. Configurable scoring weights and window sizes for the personalised feed algorithm (e.g. `FEED_WEIGHT_MY_ORG`, `FEED_WEIGHT_EMERGENCY`, `FEED_MAX_SAME_ORG_WINDOW`, `FEED_MAX_SAME_TYPE_WINDOW`, etc.).
- **Feed_GetPersonalized** — NEW SP. Multi-source scored feed. 6 candidate pools (MY_ORG 200, FOLLOWED_ORG 200, TRENDING 100, EMERGENCY 50, INTEREST 100, RECENT 100). Inline scoring (Relationship 0–50 + Interest 0–30 + Skill 0–20 + Freshness 0–25 + Engagement 0–15 + Trust 0–10 + Quality 0–10 − Spam penalty 0–20 + Emergency override +1000). Cursor-based pagination `(FeedScore DESC, PostId DESC)`. C# diversity engine post-processes: ≤2 consecutive same org, ≤3 consecutive same type.
- **Post_Save / Post_Unsave** — NEW SPs. Save / unsave a post. Idempotent. Maintain `Posts.SaveCount` (GREATEST floor at 0 on unsave).
- **Feed_TrackInteraction** — NEW SP. Fire-and-forget insert into FeedInteractions. Used for analytics and future AI training.
- **Project_GetNearbyFeed** — NEW SP. Geo-scored project discovery. Haversine distance filter ≤1000 km; RelevanceScore (+5 member, +3 follower, +2/skill match capped at +6, +3 interest match); 10 km band sort → RelevanceScore DESC → DistanceKm ASC. Projects without GPS sorted last.
- **ProjectSkills index** — UPDATED. `idx_projskill_project` changed from `(ProjectId)` → `(ProjectId, SkillName)` — covering index for `Project_GetNearbyFeed` skill-match subquery.
- **User_SendContactOtp** — NEW SP. OTP for adding a new phone or email. Duplicate check across all other users + rate-limit guard + OTP insert.
- **User_VerifyContactOtp** — NEW SP. Verifies OTP and updates `Users.Email` or `Users.Mobile` in-place.
- **OTP_PURPOSE lookup** — UPDATED. Added `ADD_PHONE` (OrderNo 5) and `ADD_EMAIL` (OrderNo 6).
- **Community_CreatePost** — FIXED. Default audience lookup now uses TypeCode `AUDIENCE_TYPE` (was wrong `POST_VISIBILITY`).
- **Community_CreatePoll** — UPDATED. New param `p_IsMultiChoice TINYINT(1) DEFAULT 0`; persisted to `CommunityPosts.PollIsMultiChoice`. Default audience TypeCode fixed to `AUDIENCE_TYPE`.
- **Community_GetFeed** — UPDATED to v4.3. Returns `PollOptionsJson` (JSON array with voteCount + isVoted + votePct), `RoleName` (author's org role), `TimeAgo`, `PostTypeLkpCode`.
- **Post_GetFeed** — FIXED. Column alias `IsLikedByMe` → `IsLiked` (DynamicRow was sending `isLikedByMe` but mobile reads `post.isLiked`).
- **Post_GetById** — FIXED. Same rename `IsLikedByMe` → `IsLiked`.
- **User_GetImpact** — FIXED. `TotalRanked` subquery now counts ALL active non-deleted users (removed `ImpactScore > 0` filter that caused "#1 of 0" for new users). `RankNumber` subquery: added `up2.IsDeleted = 0` for consistency.

**v4.7 Additions — Org Follow + Post Permissions (2026-07-12):**

- **OrgFollowers table** — NEW. Soft-unfollow pattern; one row per (OrgId, UserId); UNIQUE KEY prevents duplicates. `IsFollowing=0` = unfollowed (row kept). `FollowedAt` / `UnfollowedAt` track state changes.
- **Organisations.FollowerCount** — NEW INT UNSIGNED DEFAULT 0. Denormalized counter maintained by `Org_Follow` / `Org_Unfollow` SPs. No live COUNT query on hot read paths.
- **Org_Follow** — NEW SP. Idempotent follow with counter increment.
- **Org_Unfollow** — NEW SP. Soft-unfollow with counter decrement (GREATEST floor at 0).
- **Post_GetPermissions** — NEW SP. Called by mobile before opening Create Post modal. Always returns exactly one row: `IsMember`, `CanPost`, `MaxPostsPerDay`, `TodayPostCount`.
- **Org_GetPendingMembers** — FIXED. Adds `p_PageNumber`/`p_PageSize` params with IFNULL defaults; aliases `mr.RequestId AS MembershipRequestId` so mobile Approve button works.
- **Org_GetProfile** — UPDATED. Returns `FollowerCount` + `IsFollowing` (0|1 subquery on OrgFollowers).
- **Org_RequestMembership** — UPDATED. Auto-follows the org on join request (idempotent, counter only incremented if transitioning 0→1).
- **Org_List** — UPDATED. Returns `FollowerCount` from denormalized column.
- **Post_GetFeed** — MERGED FINAL. Now 4 params `(p_UserId, p_OrgId, p_PageNumber, p_PageSize)`. Adds `IsFollowing` per post + OrgId filter. Supersedes two earlier patches.
- **Org_GetDashboard** — UPDATED. Returns `FollowerCount` KPI.
- **Org_GetVolunteerProfile** — FIXED. `AttendanceStatus` column (does not exist) → `AttendStatusLkpId` via DECLARE vars; `pa.ProjectId` → join via `ProjectSessions`; `ReliabilityPct` rewritten as HAVING aggregate.
- **SuperAdmin_User_GetList** — FIXED. `JOIN OrgMembers` → `LEFT JOIN`; `LEFT JOIN LookupValues sv`; HAVING clause to include new users (no org) and APPROVED-only filter. OrgNames shows APPROVED orgs only. `JoinedAt` falls back to `u.CreatedAt` for new users.

**v4.6 Additions — Super Admin Module (2026-07-11):**

- **SuperAdminUsers table** — NEW. Stores Super Admin credentials (bcrypt hash, not shared with regular Users table). Fields: `SuperAdminUserId`, `Username`, `PasswordHash`, `FullName`, `Email`, `IsActive`, `LastLoginAt`, `CreatedAt`, `UpdatedAt`. Seed: `gaurav.admin` / `NgoConnect@2026` (rotate on first login).
- **OrgStatusHistory table** — NEW. Tracks every organisation status transition (PENDING→APPROVED, APPROVED→SUSPENDED, etc.). Fields: `OrgStatusHistoryId`, `OrgId` (FK Organisations), `OldStatusLkpId`, `NewStatusLkpId`, `Reason`, `ChangedByType` (`SUPER_ADMIN` / `FOUNDER`), `ChangedBy`, `CreatedAt`. Written by every status-change SP automatically.
- **18 new SuperAdmin SPs** — see SP table below. Zero changes to any existing SP. Isolation rule: `SuperAdmin_*` prefix exclusively, never modifying existing mobile/NGO-admin SPs.
- **Org_Resubmit SP** — NEW (founder-side). Allows a REJECTED org to re-enter PENDING status after founder updates org details. 19 params. State-machine guard: only from `REJECTED`. Writes `OrgStatusHistory` row with `ChangedByType=FOUNDER`. Added to existing Org module (not Super Admin prefix — correct per isolation rule).
- **OrgController** — `PUT /org/{orgId}/resubmit` endpoint + `ResubmitOrgRequest` model + `ResubmitAsync` in `OrgDal` / `IOrgDal`.

**Bug Fixes (v4.4 corrections — 2026-07-11):**

- **Project_List** — Fixed wrong column aliases that caused `Unknown column` runtime errors: `p.LocationName` → `p.Landmark AS LocationName`; `p.Address` → `p.AddressLine AS Address`; `p.StartDate/EndDate` → removed (use `OneTimeDate`/`RecurStart`/`FlexFromDate`/`FlexToDate`); `p.StartTime/EndTime` → `p.SessionStartTime/SessionEndTime`; `p.ScheduleType` → `ptv.ValueCode AS ScheduleType` (via JOIN on `ProjectTypeLkpId`); `p.RecurrenceDays` → `p.RecurDays`; `p.CoverImageUrl` → removed (column does not exist). Also added `ProjectTypeCode`, `ProjectType`, `LocationTypeCode`, `LocationType`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `OneTimeDate`, `FlexFromDate`, `FlexToDate`, `MinHoursRequired`, `ImpactSummary`, `BeneficiaryCount` to SELECT.
- **Application_GetByUser** — Fixed wrong column aliases: `ScheduleType` now via `ptv.ValueCode`/`ptv.ValueName` JOIN; `p.StartDate` → `p.RecurStart`; `p.EndDate` → `p.RecurEnd`; `p.RecurrenceDays` → `p.RecurDays`; `p.StartTime` → `p.SessionStartTime`; `p.EndTime` → `p.SessionEndTime`; `p.LocationName` → `p.Landmark AS LocationName`. Added return columns: `OneTimeDate`, `FlexFromDate`, `FlexToDate`.
- **Certificate_GetByUser** — Fixed `p.Title AS ProjectTitle` → `p.ProjectName AS ProjectTitle`.
- **User_GetBadges** — Fixed `p.Title AS ProjectName` → `p.ProjectName`.
- **Post_Create** — Fixed parameter order and removed `p_MediaType` param: now 6 params `p_UserId, p_OrgId, p_Content, p_MediaUrls, p_PostTypeLkpId, p_VisibilityLkpId`. Auto-detects IMAGE/VIDEO from extension (no caller input needed).
- **Post_GetFeed** — Added `p_OrgId INT UNSIGNED` param (NULL = all orgs, non-null = filter to org). Now 4 params: `p_UserId, p_OrgId, p_PageNumber, p_PageSize`. COUNT query also filters by `p_OrgId`.
- **MySqlConnector** — Swapped `MySql.Data` (Oracle) 9.1.0 for `MySqlConnector` (community) 2.3.7 in `NGOConnect.Infrastructure.csproj`. Resolves IPv6 connection failure on Railway private networking. Only change: `using MySqlConnector` in `MySqlDbProvider.cs`.

**Changes from v4.3 (v4.4):**

- **Project_List** — Added `p_UserLat DECIMAL(10,7)` + `p_UserLon DECIMAL(10,7)` optional params; Added `DistanceKm` (Haversine formula), `Latitude`, `Longitude` to SELECT; ORDER BY distance ASC when coords provided, else `CreatedAt DESC`.
- **Org_GetDashboard** — Added `PendingProjectApplications` KPI column (counts PENDING volunteer project applications for the org). Full SP rebuilt with correct schema refs (no `pa.ProjectId` direct column, no `pa.AttendanceStatus`, no `pa.MarkedAt`).
- **User_GetImpact** — Full rebuild: ImpactScore now calculated inline (Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5 − NoShows×20 − Withdrawals×15). New return columns: `RankName`, `RankNumber`, `TotalRanked`, `NgosJoined`, `PendingApplications`, `ApprovedApplications`, `FirstName`, `LastName`, `ProfilePhoto`, `Bio`.
- **Application_GetByUser** — Full rebuild: Added `p_PageNumber` + `p_PageSize` params; returns paged results with `OrgLogoUrl`, `ScheduleTypeCode`, `ScheduleTypeName`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `OneTimeDate`, `FlexFromDate`, `FlexToDate`, `LocationName`, `City`, `ProjectStatusCode`, `ProjectStatus`, `StatusUpdatedAt` + TotalCount.
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
- **Post_GetFeed** — Rebuilt: added `LEFT JOIN PostMedia` + `LEFT JOIN LookupValues` for media; returns `MediaUrls` (GROUP_CONCAT of `FileUrl`), `MediaTypes` (GROUP_CONCAT of ValueCode for each media item), `TimeAgo` (human-readable), `PostTypeLkpCode`, `IsPinned`. Pinned posts sorted first. Added `p_OrgId` filter param.
- **Post_Create** — Updated: 6 params (removed `p_MediaType`, reordered); auto-detects VIDEO vs IMAGE from URL extension via REGEXP (`mp4|mov|avi|mkv|webm|m4v|3gp|wmv`). Assigns correct `MediaTypeLkpId` per URL.
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
| ProfileVerificationLkpId | INT UNSIGNED NULL FK→LookupValues | **v4.6 NEW** — Super Admin review state (PROFILE_VERIFICATION_STATUS) |
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

#### UserDeviceTokens *(v4.9 NEW)*
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

> **Lifecycle:** Tokens inserted/updated via `Notification_SaveDeviceToken` when user logs in. Auto-deleted by `Notification_DeleteStaleToken` when Firebase returns `Unregistered` (device uninstalled app or token expired). C# FCMService calls this SP fire-and-forget after multicast send.

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
| FollowerCount | INT UNSIGNED DEFAULT 0 | Denormalized follower count — maintained by Org_Follow / Org_Unfollow SPs |
| VerificationStatusLkpId | INT UNSIGNED NULL FK→LookupValues | **v4.9 NEW** ORG_VERIFICATION_STATUS — PENDING / VERIFIED / REJECTED. Set by SuperAdmin_Org_VerifyProfile SP. INDEX `idx_org_verification` |
| Is80GEligible | TINYINT(1) DEFAULT 0 | **v4.9 NEW** 80G tax exemption eligibility. Set at registration and updatable via Org_Update / Org_Resubmit |
| Is12AEligible | TINYINT(1) DEFAULT 0 | **v4.9 NEW** 12A tax registration eligibility. Set at registration and updatable via Org_Update / Org_Resubmit |
| RejectionReason | TEXT NULL | Rejection reason from latest Super Admin rejection; cleared on APPROVED |
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
| IsFollowing | TINYINT(1) DEFAULT 1 | 1 = following, 0 = unfollowed (soft-unfollow) |
| FollowedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | Last follow timestamp |
| UnfollowedAt | DATETIME NULL | Last unfollow timestamp; NULL if currently following |
| UNIQUE | (OrgId, UserId) | |
| INDEX | (OrgId, IsFollowing) | |
| INDEX | (UserId, IsFollowing) | |

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

> **Index (v4.8):** `idx_projskill_project (ProjectId, SkillName)` — covering index for skill-match subquery in `Project_GetNearbyFeed`. Replaces the previous `(ProjectId)` single-column index.

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
| IsEmergency | TINYINT(1) NOT NULL DEFAULT 0 | **v4.8 NEW** Emergency post — adds +1000 to FeedScore, floats to top of personalised feed |
| IsEvergreen | TINYINT(1) NOT NULL DEFAULT 0 | **v4.8 NEW** Evergreen content — stays in feed candidate pool beyond standard 7-day window |
| ShareCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.8 NEW** Denormalized share count |
| SaveCount | INT UNSIGNED NOT NULL DEFAULT 0 | **v4.8 NEW** Denormalized save count — maintained by Post_Save / Post_Unsave |
| PinnedAt | DATETIME NULL | Set by Org_PinPost SP |
| PinnedBy | INT UNSIGNED FK→Users NULL | Set by Org_PinPost SP |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedBy | INT UNSIGNED NOT NULL | |
| UpdatedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

**Indexes (v4.8):** `idx_post_emergency (IsEmergency, CreatedAt)` — used by Feed_GetPersonalized emergency source pool.

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

#### PostSaves *(v4.8 NEW)*
| Column | Type | Notes |
|---|---|---|
| PostSaveId | BIGINT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts NOT NULL | |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PostId, UserId) | Prevents duplicate saves |
| INDEX | idx_postsave_user (UserId) | Fast lookup of saved posts per user |

> **Pattern:** INSERT … ON DUPLICATE KEY IGNORE (idempotent). Counter maintained in `Posts.SaveCount` by `Post_Save` / `Post_Unsave` SPs.

#### FeedInteractions *(v4.8 NEW)*
| Column | Type | Notes |
|---|---|---|
| InteractionId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — high-volume analytics |
| UserId | INT UNSIGNED FK→Users NOT NULL | |
| PostId | INT UNSIGNED FK→Posts NOT NULL | |
| InteractionType | VARCHAR(30) NOT NULL | IMPRESSION \| VIEW \| LIKE \| COMMENT \| SHARE \| SAVE \| VOLUNTEER_CLICK \| DONATION_CLICK \| NGO_VISIT \| HIDE \| REPORT |
| DurationMs | INT UNSIGNED NULL | Read duration in ms (VIEW interactions only) |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| INDEX | idx_feedint_user (UserId, CreatedAt) | User interaction timeline |
| INDEX | idx_feedint_post (PostId, InteractionType) | Per-post interaction analytics |

> **Purpose:** Fire-and-forget analytics log. Used for future AI-powered feed personalisation training. Writes never block the user response path.

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
| IsPinned | TINYINT(1) DEFAULT 0 | **v4.9 NEW** ANNOUNCEMENT type — pin to top of org community feed |
| VolunteersNeeded | INT UNSIGNED NULL | **v4.9 NEW** VOL_REQUEST type — number of volunteer slots requested |
| EventRef | VARCHAR(200) NULL | **v4.9 NEW** Multi-purpose extra text: EVENT_UPDATE → whatChanged; VOL_REQUEST → date/time display; TASK → free-text assignee name |
| ResourceFileUrl | VARCHAR(500) NULL | **v4.9 NEW** RESOURCE type — uploaded file URL (PDF, image, etc.) |
| PollIsMultiChoice | TINYINT(1) DEFAULT 0 | **v4.9 NEW** POLL type — allows selecting multiple poll options |
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
| NotifType | VARCHAR(50) NULL | **v4.9 FIX** (was `TypeLkpId`) — String type code e.g. NEW_APPLICATION, MEMBERSHIP_APPROVED, SOS_TRIGGERED |
| Title | VARCHAR(200) NOT NULL | |
| Body | TEXT NULL | |
| RefType | VARCHAR(50) NULL | **v4.9 FIX** (was `EntityType`) — POST / PROJECT / SOS / DONATION |
| RefId | INT UNSIGNED NULL | **v4.9 FIX** (was `EntityId`) — Related entity ID |
| OrgId | INT UNSIGNED NULL FK→Organisations | **v4.9 NEW** Org context for the notification; used to show OrgName + OrgLogoUrl |
| IsRead | TINYINT(1) DEFAULT 0 | |
| ReadAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

**Indexes:** `idx_notif_org (OrgId)` — v4.9 NEW.

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

**FEED group Settings (v4.8 NEW — 22 keys):**

| SettingKey | Default | Description |
|---|---|---|
| FEED_WEIGHT_MY_ORG | 200 | Max candidates from orgs user is an approved member of |
| FEED_WEIGHT_FOLLOWED_ORG | 200 | Max candidates from orgs user follows |
| FEED_WEIGHT_TRENDING | 100 | Max trending candidates (last 7 days by engagement score) |
| FEED_WEIGHT_EMERGENCY | 50 | Max emergency post candidates (last 48 hours) |
| FEED_WEIGHT_INTEREST | 100 | Max interest-matched candidates |
| FEED_WEIGHT_RECENT | 100 | Max recent fallback candidates (last 7 days) |
| FEED_SCORE_MEMBER | 50 | Relationship score — approved org member |
| FEED_SCORE_FOLLOWER | 30 | Relationship score — org follower (not member) |
| FEED_SCORE_INTEREST | 30 | Interest match score |
| FEED_SCORE_SKILL_PER_MATCH | 10 | Per-skill match score (capped at 20) |
| FEED_SCORE_FRESH_1H | 25 | Freshness — posted within 1 hour |
| FEED_SCORE_FRESH_6H | 20 | Freshness — posted within 6 hours |
| FEED_SCORE_FRESH_24H | 15 | Freshness — posted within 24 hours |
| FEED_SCORE_FRESH_3D | 10 | Freshness — posted within 3 days |
| FEED_SCORE_FRESH_7D | 5 | Freshness — posted within 7 days |
| FEED_SCORE_FRESH_OLD | 2 | Freshness — older than 7 days |
| FEED_SCORE_TRUST | 10 | Trusted (APPROVED) org bonus |
| FEED_SCORE_QUALITY_TEXT | 5 | Quality — content > 100 chars |
| FEED_SCORE_QUALITY_MEDIA | 5 | Quality — has media attachment |
| FEED_SCORE_SPAM_PER_REPORT | 5 | Spam penalty per PENDING report (max −20) |
| FEED_EMERGENCY_OVERRIDE | 1000 | Score override for IsEmergency=1 posts |
| FEED_MAX_SAME_ORG_WINDOW | 2 | Diversity — max consecutive same-org posts |
| FEED_MAX_SAME_TYPE_WINDOW | 3 | Diversity — max consecutive same-type posts |

---

## LookupTypes (46 Types)

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
| REPORT_STATUS | **v4.9 SEED FIX** Corrected seeds: PENDING, REVIEWED, RESOLVED (removed duplicated/wrong names: Under Review, Action Taken, Dismissed are historical — current seeds use code-aligned ValueNames) |
| MEDIA_TYPE | IMAGE, VIDEO, Document, Audio |
| SOS_ALERT_TYPE | SOS Emergency, Help Request, Missing Volunteer, Safe Arrival |
| SOS_STATUS | Active, Resolved, Cancelled |
| SOS_APPROVAL | Pending, Approved, Rejected |
| SOS_RESOLUTION | Self Resolved, Helped By Volunteer, Emergency Services, False Alarm |
| OTP_PURPOSE | Login/Registration (LOGIN), Mobile Change (MOBILE_CHANGE), Email Change (EMAIL_CHANGE), Password Reset (PASSWORD_RESET), Add Phone (ADD_PHONE) *(v4.8)*, Add Email (ADD_EMAIL) *(v4.8)* |
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
| PROFILE_VERIFICATION_STATUS | **v4.6 NEW** — Not Reviewed (PENDING), Verified (VERIFIED), Needs Update (NEEDS_UPDATE), **REJECTED (v4.9 added)** |
| ORG_VERIFICATION_STATUS | **v4.9 NEW** — PENDING, VERIFIED, REJECTED. Used for badge-level verification of org (distinct from org approval status). Set by `SuperAdmin_Org_VerifyProfile` SP |

---

### Group 11 — Super Admin (2 tables)

#### SuperAdminUsers
| Column | Type | Notes |
|---|---|---|
| SuperAdminUserId | INT UNSIGNED PK AUTO_INCREMENT | |
| Username | VARCHAR(100) UNIQUE NOT NULL | Login identifier |
| PasswordHash | VARCHAR(255) NOT NULL | bcrypt cost 11 — never stored plaintext |
| FullName | VARCHAR(150) NOT NULL | Display name |
| Email | VARCHAR(150) NULL | |
| IsActive | TINYINT(1) DEFAULT 1 | 0 = account disabled |
| LastLoginAt | DATETIME NULL | Updated by SuperAdmin_UpdateLastLogin |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME ON UPDATE CURRENT_TIMESTAMP | |

> Seed row: `gaurav.admin` / `NgoConnect@2026` — **rotate after first login**. No self-serve password reset in v1.

#### OrgStatusHistory
| Column | Type | Notes |
|---|---|---|
| OrgStatusHistoryId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED NOT NULL FK→Organisations | |
| OldStatusLkpId | INT UNSIGNED NULL FK→LookupValues | NULL on first entry (initial submission) |
| NewStatusLkpId | INT UNSIGNED NOT NULL FK→LookupValues | ORG_STATUS value |
| Reason | TEXT NULL | Rejection/suspension reason |
| ChangedByType | VARCHAR(20) NOT NULL | `SUPER_ADMIN` or `FOUNDER` |
| ChangedBy | INT UNSIGNED NOT NULL | SuperAdminUserId or UserId depending on ChangedByType |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

> Index: `idx_orgstatushist_org (OrgId, CreatedAt DESC)` — optimised for per-org timeline queries.

---

## Stored Procedures (133 Total)

### Auth (6 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Auth_SendOTP | p_Recipient, p_CountryCode, p_OtpCode, p_PurposeLkpId, p_IpAddress, p_ExpiryMinutes | WRITE | Generates OTP; enforces 3/10min rate limit; max 3 attempts then lock |
| Auth_VerifyOTP | p_Recipient, p_OtpCode, p_PurposeLkpId, p_IpAddress, p_CountryCode | WRITE | **v4.9 UPDATED** 5 params. Validates OTP; auto-creates User + UserProfiles row on first login with `IFNULL(NULLIF(p_CountryCode, ''), '+91')` as CountryCode. Returns `UserId, IsNewUser` |
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
| User_GetMyOrgs | p_UserId | LIST (Dynamic) | **v4.9 UPDATED** Returns all orgs the user is an APPROVED member of + pending requests. First UNION branch: `OrgId`, `OrgName`, `LogoUrl`, `OrgType`, `City`, `State`, `Role`, `RoleCode`, `MemberStatusCode`, `OrgStatusCode`, `MemberCount`, `JoinedAt`, **`RejectionReason`** (from Organisations). Second branch: `NULL AS RejectionReason` (column count parity for UNION). |
| User_GetBadges | p_UserId | LIST | Returns all earned badges: `UserBadgeId`, `BadgeLkpId`, `BadgeName`, `BadgeCode`, `OrgName`, `ProjectName`, `AwardedAt` |
| User_GetImpact | p_UserId | GET | **v4.4 REBUILT / v4.8 FIXED** ImpactScore calculated inline (Hours×10 + Projects×50 + NGOs×30 + Certs×25 + Badges×15 + Skills×5 − NoShows×20 − Withdrawals×15). `TotalRanked` counts ALL active non-deleted users (v4.8 fix: removed `ImpactScore > 0` filter that caused "#1 of 0" for new users). Returns: `ImpactScore`, `ReliabilityPct`, `ProjectsCompleted`, `TotalHours`, `BadgeCount`, `SkillCount`, `ProjectsApplied`, `CertificateCount`, `MemberSince`, `NgosJoined`, `PendingApplications`, `ApprovedApplications`, `RankNumber`, `TotalRanked`, `RankName` (Newcomer/Helper/Active Volunteer/Committed Volunteer/Gold/Platinum/Diamond/Elite), `FirstName`, `LastName`, `ProfilePhoto`, `Bio` |
| User_SendContactOtp | p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress | WRITE | **v4.8 NEW** Sends OTP to add a new phone or email. `p_Type`: `PHONE` or `EMAIL`. Checks `p_Value` is not already used by another user. Rate-limit guard (same as Auth_SendOTP). Inserts OtpToken with purpose ADD_PHONE or ADD_EMAIL. Returns `IsSuccess`, `Message` |
| User_VerifyContactOtp | p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress | WRITE | **v4.8 NEW** Verifies the OTP and updates `Users.Mobile` or `Users.Email` in-place. Validates: OTP not expired, not used, matches recipient. Marks OTP used. Returns `IsSuccess`, `Message` |

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

### Organisation (31 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Org_Register | p_UserId, p_OrgName, p_RegistrationNo, p_OrgTypeLkpId, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country, p_Is80GEligible, p_Is12AEligible | WRITE | **v4.9 UPDATED** 21 params. Creates org + adds creator as ADMIN member. `p_Is80GEligible TINYINT(1)` + `p_Is12AEligible TINYINT(1)` written to Organisations. Returns `IsSuccess`, `Message`, `OrgId` |
| Org_GetProfile | p_OrgId, p_UserId | GET | **v4.9 UPDATED** Full org profile. Returns `FollowerCount`, `IsFollowing`, `OrgTypeLkpId`, `StatusLkpId`, `Category`, `ContactPerson`, `MemberCount`, `MemberStatusCode`, **`Is80GEligible`**, **`Is12AEligible`** (COALESCE from OrgDonationSettings OR Organisations), **`VerificationStatusCode`** (from ORG_VERIFICATION_STATUS lookup) |
| Org_Update | p_OrgId, p_UserId, p_OrgName, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country, p_Is80GEligible, p_Is12AEligible | WRITE | **v4.9 UPDATED** 20 params — all fields COALESCE (partial update safe). Nullable Is80GEligible/Is12AEligible: NULL preserves DB value |
| Org_GetDashboard | p_OrgId | GET | **v4.7 UPDATED** Admin dashboard KPIs. Returns: `TotalMembers`, `NewMembersThisMonth`, `ActiveVolunteers`, `ActiveRatePct`, `VolunteerHoursMonth`, `ActiveProjects`, `PendingApplications`, `PendingProjectApplications`, **`FollowerCount`** (from denormalized column, no COUNT query) |
| Org_List | p_Keyword, p_Category, p_PageNumber, p_PageSize | PAGED LIST | **v4.7 UPDATED** Returns `OrgId`, `OrgName`, `Category`, `LogoUrl`, `City`, `State`, **`FollowerCount`**, `MemberCount`, `AvgRating`, `Latitude`, `Longitude`. Second result set: `TotalCount` |
| Org_ListRecommended | p_UserId | LIST | Matches user's INTEREST_TYPE ValueCodes against org Category; returns up to 20 orgs + `MatchScore` |
| Campaign_ListPublicTrending | p_PageSize | LIST | Active campaigns ranked by IsEmergency → DonorCount → RaisedAmount |
| Org_GetDonationDashboard | p_OrgId | GET | 9 donation KPIs for s-admin-donations screen |
| Org_GetDonors | p_OrgId, p_Tab (ALL/RECURRING/TOP), p_PageNumber, p_PageSize | PAGED | Donor list; respects IsAnonymous flag |
| Org_GetTransactions | p_OrgId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | Transaction list; filter by statusCode (null = all) |
| Org_GetVolunteerProfile | p_OrgId, p_UserId | GET | **v4.7 FIXED** Full volunteer profile for admin view. Fixes: `AttendStatusLkpId` via DECLARE vars (column `AttendanceStatus` does not exist); `pa.ProjectId` routed via `ProjectSessions` JOIN; `ReliabilityPct` rewritten as HAVING aggregate. Returns `FullName`, `TotalHours`, `ProjectCount`, `OrgCount`, `ReliabilityPct`, `NoShowCount`, `ExcusedCount`, `ComplaintCount`, `RoleCode`, `RoleName`, `StatusCode`, `StatusName`, `JoinedAt`, `PrevNgoExperience`, `VolunteerSkills`, `AreasOfInterest`, `WhyJoin`, `RequestedAt` |
| Org_GetMemberImpact | p_OrgId, p_UserId | GET | Admin view for s-member-impact |
| Org_UpdateMemberRole | p_OrgId, p_MemberId, p_RoleCode, p_UpdatedBy | WRITE | **v4.9 UPDATED** `p_RoleLkpId INT` → `p_RoleCode VARCHAR(50)`. SP resolves LkpId internally via MEMBER_ROLE lookup. Success SELECT returns `UserId` (for FCM MEMBER_ROLE_CHANGED trigger) |
| Org_GetMembers | p_OrgId | LIST (Dynamic) | All members with role, status, permissions |
| Org_AddMember | p_OrgId, p_UserId, p_RoleLkpId, p_RequestedBy | WRITE | Direct add (admin action) |
| Org_RemoveMember | p_OrgId, p_UserId, p_RequestedBy | WRITE | Soft remove |
| Org_RequestMembership | p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin | WRITE | **v4.7 UPDATED** Submits join request. Auto-follows the org on success (idempotent — counter incremented only if transitioning 0→1 in OrgFollowers). Returns `IsSuccess`, `Message`, `RequestId` |
| Org_Follow | p_OrgId, p_UserId | WRITE | **v4.7 NEW** Follow an NGO. INSERT … ON DUPLICATE KEY UPDATE (idempotent). Increments `Organisations.FollowerCount` only on 0→1 transition. Returns `IsSuccess`, `Message` |
| Org_Unfollow | p_OrgId, p_UserId | WRITE | **v4.7 NEW** Soft-unfollow: sets `IsFollowing=0`, `UnfollowedAt=NOW()`. Decrements `FollowerCount` with GREATEST(n-1, 0) floor. Idempotent. Returns `IsSuccess`, `Message` |
| Org_ReviewMembership | p_RequestId, p_StatusCode, p_AdminNotes, p_ReviewedBy | WRITE | APPROVED/REJECTED with AdminNotes |
| Org_GetPendingMembers | p_OrgId, p_PageNumber, p_PageSize | LIST | **v4.7 FIXED** Pending join requests. Returns `MembershipRequestId` (alias for `mr.RequestId` — mobile Approve button requires this), `UserId`, `FullName`, `ProfilePhoto`, `City`, `State`, `PrevNgoExperience`, `VolunteerSkills`, `AreasOfInterest`, `WhyJoin`, `RequestedAt`. IFNULL defaults on pagination params. Second result set: `TotalCount` |
| Org_UpdateMemberPermissions | p_OrgId, p_MemberId, p_CanPost, p_CanComment, p_CanCommunityPost, p_MaxPostsPerDay, p_LocationSharingLkpId, p_UpdatedBy | WRITE | Granular member permissions |
| Org_UploadDocument | p_OrgId, p_UploadedBy, p_DocumentTypeLkpId, p_FileUrl, p_FileName | WRITE | Inserts into OrgDocuments |
| Org_GetDocuments | p_OrgId | LIST | **v4.9 NEW** Returns org admin's uploaded documents from OrgDocuments. Columns: `OrgDocumentId`, `DocumentTypeLkpId`, `DocumentTypeCode` (ValueCode), `DocumentType` (ValueName), `FileUrl`, `FileName`, `IsVerified`, `VerifiedAt`, `CreatedAt` |
| Org_GetAdminPosts | p_OrgId | LIST (Dynamic) | **v4.4 NEW** All feed Posts for org with: `FullName`, `ProfilePhoto`, `RoleCode`, `RoleName`, `Content`, `LikesCount`, `CommentsCount`, `IsPinned`, `CreatedAt`, `ReportCount` (PENDING reports only), `StatusCode` (PUBLISHED or REPORTED) |
| Org_PinPost | p_PostId, p_OrgId, p_PinnedBy | WRITE | **v4.4 NEW** Toggles IsPinned on a post. Validates post belongs to org. Returns `IsSuccess`, `Message` ("Post pinned." / "Post unpinned.") |
| Org_DeletePost | p_PostId, p_OrgId, p_DeletedBy | WRITE | **v4.4 NEW** Soft-deletes a feed post. Validates post belongs to org. Returns `IsSuccess`, `Message` |
| Org_ModeratePost | p_PostId, p_OrgId, p_ReviewedBy, p_Action (`KEEP`/`REMOVE`) | WRITE | **v4.4 NEW** Resolves all pending reports on post. If REMOVE, also soft-deletes post. Returns `IsSuccess`, `Message` ("Reports cleared." / "Post removed.") |
| Org_Resubmit | p_OrgId, p_UserId, p_OrgName, p_Category, p_ContactPerson, p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website, p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode, p_Country, p_Is80GEligible, p_Is12AEligible | WRITE | **v4.9 UPDATED (founder-side)** 21 params (+`p_Is80GEligible TINYINT(1)` + `p_Is12AEligible TINYINT(1)`; direct assignment). Updates org fields + resets status to PENDING. Guards: caller must be FOUNDER; org must be in REJECTED status. Inserts OrgStatusHistory row (ChangedByType=FOUNDER). Returns `IsSuccess`, `Message` |

### Project (14 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Project_Create | p_UserId, p_OrgId, p_Title, p_Description, p_Category, p_ProjectTypeLkpId, p_JoinTypeLkpId, p_StatusLkpId, p_MaxVolunteers, p_MinAge, p_MaxAge, p_IsPublic, p_StartDate, p_EndDate, p_ScheduleType, p_RecurrenceDays, p_StartTime, p_EndTime, p_DurationMinutes, p_LocationTypeLkpId, p_LocationTypeCode, p_LocationName, p_Address, p_Latitude, p_Longitude, p_GoogleMapsUrl, p_GenderRestriction, p_RequiresApproval, p_CoverImageUrl, p_City, p_State, p_IsDraft | WRITE | 32 params. Maps schedule dates into correct columns. Returns `IsSuccess`, `Message`, `ProjectId` |
| Project_GetById | p_ProjectId, p_UserId | GET | Full project details with org name, schedule, status, `ApprovedVolunteers` count, `MyApplicationStatusId` |
| Project_Update | p_ProjectId + 31 params (same as Create minus p_OrgId) | WRITE | 32 params. COALESCE-safe partial update. Returns `IsSuccess`, `Message` |
| Project_List | p_OrgId, p_Category, p_City, p_StatusCode, p_TypeCode, p_PageNumber, p_PageSize, p_UserLat, p_UserLon | PAGED | **v4.4 UPDATED** — 9 params. Returns: `ProjectId`, `OrgId`, `OrgName`, `OrgLogoUrl`, `ProjectName`, `Category`, `ScheduleType` (ptv.ValueCode), `ProjectTypeCode`, `ProjectType`, `LocationTypeCode`, `LocationType`, `LocationName` (p.Landmark), `Address` (p.AddressLine), `StatusCode`, `Status`, `City`, `State`, `Latitude`, `Longitude`, `MaxVolunteers`, `IsPublic`, `OneTimeDate`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `FlexFromDate`, `FlexToDate`, `MinHoursRequired`, `CancelReason`, `CancelledAt`, `ImpactSummary`, `BeneficiaryCount`, `ApprovedCount`, `CreatedAt`, `DistanceKm` (Haversine; NULL if no coords). Sorted by `DistanceKm ASC` when coords provided, else `CreatedAt DESC`. `p_OrgId` non-null includes private projects; null returns only public |
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
| Project_GetNearbyFeed | p_UserId, p_UserLat, p_UserLon, p_PageNumber, p_PageSize | PAGED | **v4.8 NEW** Geo-scored project discovery feed. Filters: ACTIVE/UPCOMING, IsPublic=1, no existing PENDING/APPROVED application from this user. Distance ≤1000 km via Haversine. RelevanceScore: +5 approved NGO member, +3 org follower, +2 per matching user skill (max +6 cap), +3 matching interest/category. Sort: 10 km distance band ASC → RelevanceScore DESC → DistanceKm ASC → CreatedAt DESC. Projects without GPS placed in pseudo-band 999999 (sorted last). Returns same columns as Project_List plus `DistanceKm` (NULL if no GPS), `RelevanceScore`, `ApprovedCount`. Second result set: `TotalCount` |

### Application (4 SPs — standalone module)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Application_Apply | p_ProjectId, p_UserId, p_Motivation, p_RequestedSessions | WRITE | **v4.4 UPDATED** Params renamed: `p_Note` → `p_Motivation`; `p_RequestedSessions` added |
| Application_GetByProject | p_ProjectId, p_StatusCode, p_PageNumber, p_PageSize | PAGED | **v4.4 REBUILT** Joins `ProjectAttendance` via correlated subquery. Attendance status takes precedence over application status (COALESCE). Returns: `ApplicationId`, `UserId`, `ApplicantName`, `ProfilePhoto`, `City`, `Profession`, `Motivation`, `RequestedSessions`, `StatusCode`, `Status`, `StatusUpdatedAt`, `CreatedAt`, `CheckedInAt`, `HoursLogged`, `IsExcused`, `QrScannedAt`, `AdminNote`, `SessionDate`, `SessionStartTime`, `SessionEndTime` + TotalCount |
| Application_Review | p_ApplicationId, p_StatusLkpId, p_RejectionReason, p_ReviewedBy | WRITE | Uses `StatusLkpId` (INT) |
| Application_GetByUser | p_UserId, p_PageNumber, p_PageSize | PAGED | **v4.4 REBUILT** 3 params (was 1). Returns: `ApplicationId`, `ProjectId`, `ProjectName`, `OrgName`, `OrgLogoUrl`, `StatusCode`, `Status`, `CreatedAt`, `StatusUpdatedAt`, `ScheduleTypeCode`, `ScheduleTypeName`, `RecurStart`, `RecurEnd`, `RecurDays`, `SessionStartTime`, `SessionEndTime`, `OneTimeDate`, `FlexFromDate`, `FlexToDate`, `LocationName` (alias of `p.Landmark`), `City`, `ProjectStatusCode`, `ProjectStatus` + TotalCount |

### Post / Feed (16 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Post_Create | p_UserId, p_OrgId, p_Content, p_MediaUrls, p_PostTypeLkpId, p_VisibilityLkpId | WRITE | **v4.9 UPDATED** Added permission gate: checks `OrgMembers.CanPost + MaxPostsPerDay` before INSERT; returns `IsSuccess=0` + `POSTS_LIMIT_REACHED`/`POST_NOT_ALLOWED` on failure. Auto-detects VIDEO vs IMAGE from URL extension via REGEXP. Assigns `MediaTypeLkpId` per URL in PostMedia. Returns `IsSuccess`, `Message`, `PostId` |
| Post_GetFeed | p_UserId, p_OrgId, p_PageNumber, p_PageSize | PAGED LIST | **v4.7 MERGED FINAL / v4.8 FIXED** 4 params. `p_OrgId NULL` = all orgs, non-null = filter to one org. Returns `PostId`, `Content`, `IsPinned`, `PostTypeLkpCode`, `PostType`, `LikeCount`, `CommentCount`, **`IsLiked`** *(v4.8 fix: was `IsLikedByMe`)*, `UserId`, `AuthorName`, `ProfilePhoto`, `OrgId`, `OrgName`, `IsFollowing` (0\|1 subquery on OrgFollowers), `MediaUrls` (GROUP_CONCAT), `MediaTypes` (GROUP_CONCAT), `CreatedAt`, `TimeAgo`. Second result set: `TotalCount` (also filtered by p_OrgId) |
| Post_GetPermissions | p_OrgId, p_UserId | GET | **v4.9 UPDATED** Called by mobile before opening Create Post modal. Always returns exactly one row (DECLARE defaults cover non-member case). Returns: `IsMember` TINYINT(1), `CanPost` TINYINT(1), `MaxPostsPerDay` INT (from OrgMembers), `TodayPostCount` INT, **`CanComment` TINYINT(1)**, **`CanCommunityPost` TINYINT(1)** (both from OrgMembers — v4.9 added) |
| Post_GetById | p_PostId, p_UserId | GET | **v4.8 FIXED** `IsLiked` alias (was `IsLikedByMe`). Single post with like/comment counts |
| Post_Delete | p_PostId, p_UserId | WRITE | Soft delete |
| Post_Pin | p_PostId, p_OrgId, p_PinnedBy | WRITE | Toggle IsPinned |
| Post_Like | p_PostId, p_UserId | WRITE | INSERT IGNORE into PostLikes |
| Post_Unlike | p_PostId, p_UserId | WRITE | DELETE from PostLikes |
| Post_AddComment | p_PostId, p_UserId, p_Content, p_ParentCommentId | WRITE | **v4.9 UPDATED** Permission gate: checks `OrgMembers.CanComment`; non-members blocked from commenting. Returns `IsSuccess=0` + `COMMENT_NOT_ALLOWED` on failure. Supports threading via ParentCommentId |
| Post_GetComments | p_PostId, p_PageNumber, p_PageSize | PAGED | Nested comments |
| Post_Report | p_PostId, p_UserId, p_ReasonCode, p_Details | WRITE | **v4.4 REBUILT** `p_ReasonCode VARCHAR(50)` (e.g. SPAM, HATE, INAPPROPRIATE, SCAM, OTHER). SP resolves `LookupValueId` internally. Prevents duplicate reports from same user on same post. Returns `IsSuccess`, `Message` |
| Post_Save | p_UserId, p_PostId | WRITE | **v4.8 NEW** Idempotent save. INSERT IGNORE into PostSaves; increments `Posts.SaveCount`. Returns `IsSuccess`, `Message` |
| Post_Unsave | p_UserId, p_PostId | WRITE | **v4.8 NEW** Removes from PostSaves; decrements `Posts.SaveCount` with GREATEST(n−1, 0) floor. Returns `IsSuccess`, `Message` |
| Feed_GetPersonalized | p_UserId, p_CursorPostId, p_CursorScore, p_PageSize | LIST (Dynamic) | **v4.8 NEW** Multi-source scored personalised feed. Returns 3× `p_PageSize` candidates for C# diversity engine. Columns: `PostId`, `Content`, `IsPinned`, `IsEmergency`, `IsEvergreen`, `LikeCount`, `CommentCount`, `ShareCount`, `SaveCount`, `PostTypeCode`, `PostType`, `UserId`, `AuthorName`, `ProfilePhoto`, `OrgId`, `OrgName`, `OrgLogoUrl`, `FeedSource` (MY_ORG\|FOLLOWED_ORG\|TRENDING\|EMERGENCY\|INTEREST\|RECENT), `IsLiked`, `IsSaved`, `IsFollowing`, `MediaUrls`, `MediaTypes`, `CreatedAt`, `TimeAgo`, `FeedScore` (DECIMAL — inline scoring formula). Cursor filter: `FeedScore < p_CursorScore OR (FeedScore = p_CursorScore AND PostId < p_CursorPostId)` |
| Feed_TrackInteraction | p_UserId, p_PostId, p_InteractionType, p_DurationMs | WRITE | **v4.8 NEW** Fire-and-forget. Inserts into FeedInteractions. `p_InteractionType`: IMPRESSION\|VIEW\|LIKE\|COMMENT\|SHARE\|SAVE\|VOLUNTEER_CLICK\|DONATION_CLICK\|NGO_VISIT\|HIDE\|REPORT. Returns `IsSuccess`, `Message` |

### Community (9 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Community_CreatePost | p_UserId, p_OrgId, p_Title, p_Content, p_PostTypeLkpId, p_AudienceLkpId, p_ResourceFileUrl, p_IsPinned, p_VolunteersNeeded, p_EventRef | WRITE | **v4.9 MAJOR UPDATE** 10 params (was 6). Added: `p_ResourceFileUrl VARCHAR(500)`, `p_IsPinned TINYINT(1) DEFAULT 0`, `p_VolunteersNeeded INT UNSIGNED NULL`, `p_EventRef VARCHAR(200) NULL`. Permission gate: checks `OrgMembers.CanCommunityPost`; returns `IsSuccess=0` + `COMMUNITY_POST_NOT_ALLOWED` on failure. Inserts into all new CommunityPosts columns. Auto-defaults AudienceLkpId to ALL_MEMBERS if NULL. Returns `IsSuccess`, `Message`, `CommunityPostId` |
| Community_GetFeed | p_OrgId, p_UserId, p_PageNumber, p_PageSize | PAGED (Dynamic) | **v4.8 UPDATED (v4.3)** Returns `PollOptionsJson` (JSON array per poll post with `voteCount`, `isVoted`, `votePct`), `RoleName` (author's org role name), `TimeAgo`, `PostTypeLkpCode`, `IsLiked`, `IsAcknowledged`, `LikeCount`, `CommentCount` + TotalCount |
| Community_AcknowledgePost | p_CommunityPostId, p_UserId | WRITE | Marks post acknowledged; increments AcknowledgeCount |
| Community_CreatePoll | p_UserId, p_OrgId, p_Question, p_OptionsJson, p_ExpiresInHours, p_IsMultiChoice | WRITE | **v4.9 UPDATED** 6 params. Added permission gate: checks `OrgMembers.CanCommunityPost`; returns `IsSuccess=0` + `COMMUNITY_POST_NOT_ALLOWED` on failure. `p_IsMultiChoice TINYINT(1) DEFAULT 0` — persisted to `CommunityPosts.PollIsMultiChoice`. Default audience TypeCode fixed to `AUDIENCE_TYPE`. Creates CommunityPost of type POLL + PollOptions from JSON array. Returns `IsSuccess`, `Message`, `PollId` |
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
| Withdrawal_GetByOrg| Withdrawal_GetByOrg | PAGED | p_OrgId, status filter |
| Withdrawal_Admin_Review | WRITE | Approve/Reject with reason |

### Certificate / Badge / Rating / Attendance (5 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Certificate_GetByUser | p_UserId | LIST | **v4.4 FIXED** `p.ProjectName AS ProjectTitle` (was `p.Title`). Returns certificates with project name, org name, issue date |
| Badge_GetByUser | p_UserId | LIST | **v4.4 FIXED** `p.ProjectName AS ProjectTitle` (was `p.Title`). Returns badges with type, earned date |
| SkillRating_AddOrUpdate | p_ApplicationId, p_RaterUserId, p_SkillId, p_Rating, p_RaterType | WRITE | Volunteer or Admin rates a skill after project. `RaterType`: VOLUNTEER or ADMIN |
| Attendance_GetByProject | p_ProjectId, p_PageNumber, p_PageSize | PAGED | All attendance records for a project |
| Certificate_Generate | p_ProjectId, p_UserId | WRITE | Internal: generates certificate on project completion |

### Notification (12 SPs)
| SP Name | Params | Type | Description |
|---|---|---|---|
| Notification_GetByUser | p_UserId, p_OnlyUnread, p_PageNumber, p_PageSize | PAGED | **v4.9 UPDATED** `LEFT JOIN Organisations` on `n.OrgId`; returns `OrgId`, `OrgName`, `OrgLogoUrl` in addition to core notification fields. Fixed column names (`NotifType`, `RefType`, `RefId`). Removed `IsDeleted` condition (column does not exist) |
| Notification_MarkRead | p_NotificationId, p_UserId | WRITE | Single notification |
| Notification_MarkAllRead | p_UserId | WRITE | All for user |
| Notification_GetUnreadCount | p_UserId | GET | **v4.9 UPDATED** Removed `IsDeleted = 0` condition (column does not exist). Returns `UnreadCount` |
| Notification_Create | p_UserId, p_Title, p_Body, p_NotifType, p_RefType, p_RefId, p_OrgId | WRITE | **v4.9 UPDATED** 7 params (was 6; added `p_OrgId INT UNSIGNED NULL`). Fixed column names: `NotifType VARCHAR(50)`, `RefType VARCHAR(50)`, `RefId INT UNSIGNED`. Inserts `OrgId` into new Notifications column. Internal use by other SPs |
| Notification_SaveDeviceToken | p_UserId, p_Token, p_DeviceType | WRITE | FCM token upsert via UserDeviceTokens (UNIQUE on UserId+Token) |
| Notification_DeleteStaleToken | p_Token | WRITE | **v4.9 NEW** Deletes stale/unregistered FCM tokens from UserDeviceTokens. Auto-called by C# FCMService when Firebase returns `Unregistered`. Fire-and-forget |
| Notification_GetTokenByUserId | p_UserId | READ | **v4.9 NEW** Returns FCM tokens for a single user |
| Notification_GetTokensByOrgId | p_OrgId | READ | **v4.9 NEW** Returns FCM tokens for all APPROVED members of an org |
| Notification_GetAdminTokensByOrgId | p_OrgId | READ | **v4.9 NEW** Returns FCM tokens for ADMIN-role members of an org only |
| Notification_GetTokensByProjectId | p_ProjectId | READ | **v4.9 NEW** Returns FCM tokens for all APPROVED applicants of a project |
| Notification_GetTokensBySosIncidentId | p_SosIncidentId | READ | **v4.9 NEW** Returns FCM tokens for victim + all APPROVED responders of a SOS incident |

### Super Admin (29 SPs) — v4.5 + v4.6 + v4.9

All Super Admin SPs are isolated — never called by any existing mobile/NGO-admin endpoint.
`Org_Resubmit` is listed below for reference but is a founder-side SP counted under Organisation (29 SPs).

#### Auth
| SP Name | Params | Type | Description |
|---|---|---|---|
| SuperAdmin_GetByUsername | p_Username | READ | Fetches SuperAdminUsers row for login. Returns IsActive, PasswordHash, FullName, Email |
| SuperAdmin_UpdateLastLogin | p_SuperAdminUserId | WRITE | Sets LastLoginAt = NOW() |

#### Organisation Management
| SP Name | Params | Type | Description |
|---|---|---|---|
| SuperAdmin_Org_GetList | p_StatusCode, p_PageNumber, p_PageSize | PAGED | Returns org rows: OrgId, OrgName, LogoUrl, **OrgType** (ValueName), StatusCode, StatusName, City, SubmittedAt, LastReason. **v4.6:** added `OrgType` column |
| SuperAdmin_Org_GetDetail | p_OrgId | READ | **v4.9 UPDATED** Full org detail: all list fields + About, Mission, Vision, FounderName, FounderEmail, FounderMobile, AddressLine, City, State, Pincode, MemberCount. **v4.9 added:** `Is80GEligible`, `Is12AEligible`, `ContactPerson`, `ContactEmail`, `ContactPhone`, `VerificationStatusCode` (from ORG_VERIFICATION_STATUS lookup) |
| SuperAdmin_Org_GetDocuments | p_OrgId | READ | Returns OrgDocumentId, DocType, DocUrl, IsVerified, UploadedAt |
| SuperAdmin_OrgDocument_Verify | p_OrgDocumentId, p_VerifiedBy, p_IsApproved, p_Notes | WRITE | Marks document verified/rejected. Updates OrgDocuments |
| SuperAdmin_Org_Approve | p_OrgId, p_ApprovedBy | WRITE | **State guard:** PENDING or UNDER_REVIEW only → APPROVED. Inserts OrgStatusHistory + Notifications row |
| SuperAdmin_Org_Reject | p_OrgId, p_RejectedBy, p_Reason | WRITE | **State guard:** PENDING or UNDER_REVIEW only → REJECTED. Reason required. Inserts OrgStatusHistory + Notifications row |
| SuperAdmin_Org_Suspend | p_OrgId, p_SuspendedBy, p_Reason | WRITE | **State guard:** APPROVED only → SUSPENDED. Inserts OrgStatusHistory |
| SuperAdmin_Org_Reactivate | p_OrgId, p_ReactivatedBy | WRITE | **State guard:** SUSPENDED only → APPROVED. Inserts OrgStatusHistory |
| SuperAdmin_Org_VerifyProfile | p_OrgId, p_StatusCode, p_SuperAdminUserId | WRITE | **v4.9 NEW** Sets `Organisations.VerificationStatusLkpId` by resolving `p_StatusCode` against ORG_VERIFICATION_STATUS LookupType. Valid codes: PENDING / VERIFIED / REJECTED. Returns `IsSuccess`, `Message` |
| Org_Resubmit *(founder-side, counted under Organisation)* | p_OrgId, p_UserId + 19 org fields | WRITE | **State guard:** REJECTED only → PENDING. Caller must be FOUNDER. Updates org fields (21 params incl. Is80GEligible/Is12AEligible) + inserts OrgStatusHistory (ChangedByType=FOUNDER) |
| SuperAdmin_Org_GetStatusHistory | p_OrgId | READ | **v4.6 NEW** — Full status-change timeline for org. Returns: OrgStatusHistoryId, OldStatus, OldStatusName, NewStatus, NewStatusName, Reason, ChangedByType, ChangedBy, CreatedAt. ORDER BY CreatedAt DESC |

#### Member Management
| SP Name | Params | Type | Description |
|---|---|---|---|
| SuperAdmin_User_GetList | p_OrgIds, p_Search, p_PageNumber, p_PageSize | PAGED LIST | **v4.9 UPDATED** HAVING clause zero-org-membership branch is now unconditional `COUNT(om.OrgMemberId) = 0` (removed `p_OrgIds IS NULL` condition — new users now always appear regardless of org filter). LEFT JOIN OrgMembers. OrgNames shows APPROVED orgs only. `JoinedAt` falls back to `u.CreatedAt` for new users. Returns `UserId`, `FullName`, `Email`, `Mobile`, `ProfilePhoto`, `OrgNames`, `Role`, `MembershipStatus`, `AccountStatus`, `ProfileVerificationStatus`, `JoinedAt`. Second result set: `TotalCount` |
| SuperAdmin_User_GetFullProfile | p_UserId | READ (5 result sets) | **v4.6 NEW** — RS1: core profile (FullName, Email, AccountStatus, ProfileVerificationStatus, Reliability, Hours, Projects). RS2: skills. RS3: interests. RS4: badges. RS5: NGO memberships (OrgName, Role, Status) |
| SuperAdmin_User_GetDocuments | p_UserId | READ | **v4.6 NEW** — All user documents with verification state: UserDocumentId, DocumentType, FileUrl, IsVerified, VerifiedAt |
| SuperAdmin_UserDocument_Verify | p_UserDocumentId, p_SuperAdminUserId, p_IsVerified | WRITE | **v4.6 NEW** — Marks a user document verified or unverified |
| SuperAdmin_User_VerifyProfile | p_UserId, p_SuperAdminUserId | WRITE | **v4.6 NEW** — Sets ProfileVerificationLkpId=VERIFIED. Sends PROFILE_VERIFIED notification to member |
| SuperAdmin_User_RequestUpdate | p_UserId, p_SuperAdminUserId, p_Reason | WRITE | **v4.6 NEW** — Sets ProfileVerificationLkpId=NEEDS_UPDATE. Sends PROFILE_NEEDS_UPDATE notification with reason |
| SuperAdmin_User_Suspend | p_UserId, p_SuperAdminUserId, p_Reason | WRITE | **v4.6 NEW** — Sets IsActive=0. Revokes all RefreshTokens. Sends ACCOUNT_SUSPENDED notification. Reason required |
| SuperAdmin_User_Reactivate | p_UserId, p_SuperAdminUserId | WRITE | **v4.6 NEW** — Sets IsActive=1. Sends ACCOUNT_REACTIVATED notification |

#### Dashboard
| SP Name | Params | Type | Description |
|---|---|---|---|
| SuperAdmin_Dashboard_GetKpis | — | READ | **v4.6 NEW** — Single-row KPI summary: TotalOrgs (APPROVED), PendingOrgs (PENDING+UNDER_REVIEW), TotalVolunteers, ActiveVolunteersLast30Days, TotalDonationsAmount (SUCCESS txns) |
| SuperAdmin_Org_GetRecent | p_Limit | READ | **v4.6 NEW** — N most-recently submitted orgs (any status): OrgId, OrgName, LogoUrl, StatusCode, StatusName, SubmittedAt |

#### Lookup Management
| SP Name | Params | Type | Description |
|---|---|---|---|
| SuperAdmin_LookupType_GetList | — | READ | All LookupTypes |
| SuperAdmin_LookupValue_GetByType | p_LookupTypeId | READ | All values for a type |
| SuperAdmin_LookupType_Add | p_TypeCode, p_TypeName, p_Description | WRITE | Creates new LookupType |
| SuperAdmin_LookupType_Update | p_LookupTypeId, p_TypeName, p_Description | WRITE | Updates LookupType name/description |
| SuperAdmin_LookupValue_Add | p_LookupTypeId, p_ValueCode, p_ValueName, p_OrderNo, p_IsDefault, p_IsSystemValue | WRITE | Creates new LookupValue |
| SuperAdmin_LookupValue_Update | p_LookupValueId, p_ValueName, p_OrderNo, p_IsDefault | WRITE | Updates LookupValue display properties |
| SuperAdmin_LookupValue_SetActive | p_LookupValueId, p_IsActive | WRITE | Activate/deactivate a value. Guard: IsSystemValue=1 cannot be deactivated |

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

---

*Database_Documentation_v4.9.md — 55 Tables, 46 LookupTypes, 163 Stored Procedures — Last updated 2026-07-18*

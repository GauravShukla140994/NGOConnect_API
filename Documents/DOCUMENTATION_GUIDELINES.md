# NGO Connect — Documentation Guidelines

## Overview

All documentation lives in the `/Documents` folder. Every document must always
reflect the current state of the system. No change — however minor — is too
small to track. When the user says **"update documents"**, every accumulated
change must be applied carefully before releasing a new version.

---

## Maintained Documents

| File | Purpose |
|---|---|
| `NGOConnect_Complete_Setup_v4.9.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.9.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.9.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.9.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

---

## Versioning Rule

Before applying any update, Claude will assess the change scope and ask for confirmation:

> *"These changes are [minor/significant]. Should I update the current version in-place, or create a new version file?"*

| Change scope | Definition | Default action |
|---|---|---|
| **Minor** | Typo/wording fix, description clarification, adding a missing field to existing docs, correcting a sample value | Update current file in-place — no version bump |
| **Significant** | New endpoint added, SP parameter added/removed, table column added/removed, request/response model changed | Bump to next minor version (e.g. v4.1 → v4.2) |
| **Major** | New platform version release, full module added, breaking API change | Bump to next major version (e.g. v4.x → v5.0) |

**Version bump rules (when a new version IS created):**
- Old file is deleted and replaced by the new versioned file
- All 4 documents that changed get their version bumped together
- Example: `API_Documentation_v4.1.docx` → `API_Documentation_v4.2.docx`

**Major version** (**5**.0, **6**.0 …) — full platform version release only

---

## What Triggers a Documentation Update

### Database Documentation (`Database_Documentation_v4.0.md`)

Update whenever any of the following change:

**Tables**
- New table added
- Column added, removed, or renamed
- Column data type or constraint changed (NOT NULL, DEFAULT, length)
- Index added or removed
- Foreign key added or removed

**Stored Procedures**
- New SP created
- SP dropped or renamed
- Parameter added, removed, renamed, or type changed
- Return columns added, removed, renamed, or type changed
- Business logic change that affects what the SP returns

**Views**
- New view created
- View definition changed
- View dropped

---

### API Documentation (`API_Documentation_v4.0.docx`) + Postman Collection (`NGOConnect_Postman_Collection_v4.0.json`)

Update whenever any of the following change:

**Controllers**
- New endpoint added
- Endpoint route changed
- HTTP method changed (GET → POST etc.)
- Authorization requirement added or removed
- New query parameters added

**Models (Request)**
- Field added, removed, or renamed
- Field data type changed (int → string etc.)
- Validation rule changed ([Required] added/removed, MaxLength changed)

**Models (Response)**
- Field added, removed, or renamed in response model or DynamicRow SP output
- New `ApiResponse<T>` wrapper introduced

**API Contracts**
- Error codes changed (`"OTP_INVALID"` → `"OTP_EXPIRED"` etc.)
- Success/failure message text changed in a way that affects frontend logic
- HTTP status code changed

---

### Setup SQL (`NGOConnect_Complete_Setup_v4.0.sql`)

Update whenever:
- Any table DDL changes (ALTER TABLE, new table, dropped table)
- Any SP is created, replaced, or dropped
- Seed data (LookupTypes, LookupValues, Settings) is added or changed
- An uploaded SP file (e.g. `02_SP_Auth.sql`) is confirmed as the new source of truth — replace the corresponding SP block in the setup file

---

## What Does NOT Trigger a Document Update

- Internal DAL fixes (C# property name alignment, parameter order) that do not change the public API contract
- Build error fixes (CS0246, CS1061 etc.) that only affect compilation
- Refactoring with no external behavior change
- `.gitignore`, `appsettings`, project config changes

---

## Update Process (When "Update Documents" is Said)

1. **Patch File Audit FIRST** — run `ls Documents/NGOConnect_Patch_*.sql` and cross-check every file against the Railway Patch Registry below. Any file NOT listed in the registry must be read and classified before proceeding. This step is MANDATORY — the community module incident (v4.7) was caused by skipping it.
2. **Review the pending changes list** — every change tracked since the last update
3. **Cross-check all files** — re-read relevant DAL, model, controller, and SP files to catch any missed changes
4. **Assess change scope** — classify as Minor, Significant, or Major (see Versioning Rule above)
5. **Ask for confirmation** — present the scope assessment and ask: update in-place or create new version?
6. **Apply all changes** — no change is too minor to skip
7. **Bump version (if confirmed)** — rename files to new version across all updated documents
8. **Update Railway Patch Registry** — mark all newly-included patches as applied
9. **Clear the pending changes list** after update is complete

---

## Railway Patch Registry

**Every `NGOConnect_Patch_*.sql` file in Documents/ must have an entry here.**
When a new patch file is created, add it immediately with status `🟡 Local only`.
When it is included in a Railway patch, update to `✅ Railway applied`.

### How to use this registry

- When building a Railway patch: every `🟡 Local only` entry must be reviewed and either included or explicitly marked `⛔ Superseded`.
- When creating a new patch file: add it to this table BEFORE ending the session.
- This registry is why the Patch File Audit is Step 1 of the Update Process.

### Versioned Railway Patches (cumulative)

| File | Covers | Status |
|---|---|---|
| `NGOConnect_Patch_v4.1.sql` | Auth, Org, Project core SPs | ✅ Railway applied |
| `NGOConnect_Patch_v4.5_Complete.sql` | Feed, Media, Impact, QR, SOS | ✅ Railway applied |
| `NGOConnect_Patch_v4.6.sql` | SuperAdmin module, ProfileVerification | ✅ Railway applied |
| `NGOConnect_Patch_v4.7.sql` | OrgFollowers, Follow/Unfollow, PostPermissions, Post_GetFeed merge | ✅ Railway applied |

### Community Module Patches (absorbed into v4.9)

| File | What it fixes | Status |
|---|---|---|
| `NGOConnect_Patch_CommunityFeed_ColumnFix.sql` | Community_GetFeed: AuthorName + IsAcknowledged column names | ✅ Railway applied |
| `NGOConnect_Patch_CommunityCreatePost_SPFix.sql` | Community_CreatePost: 14-param → 6-param (critical — DAL mismatch) | ✅ Railway applied |
| `NGOConnect_Patch_CommunityPollVote_SPFix.sql` | Community_CreatePoll: 5-param; Community_Vote: 3-param | ✅ Railway applied |
| `NGOConnect_Patch_CommunityLikesComments.sql` | LikeCount/CommentCount columns; 3 new tables; LikePost/AddComment/GetComments/LikeComment SPs | ✅ Railway applied |
| `NGOConnect_Patch_Community_Railway.sql` | Combined patch containing all 4 above | ✅ Railway applied |

### v4.9 Railway Deploy — ALL patches applied to staging 2026-07-18

| File | What it covers | Status |
|---|---|---|
| `NGOConnect_Patch_SuperAdminMembersList_ShowUnlinked.sql` | SuperAdmin_User_GetList: HAVING clause zero-org-membership fix | ✅ Railway applied |
| `NGOConnect_Patch_PostLike_FieldFix.sql` | Post_GetFeed + Post_GetById: rename IsLikedByMe → IsLiked alias | ✅ Railway applied |
| `NGOConnect_Patch_ImpactRankFix.sql` | User_GetImpact: TotalRanked counts all active users | ✅ Railway applied |
| `NGOConnect_Patch_ContactUpdate.sql` | ADD_PHONE + ADD_EMAIL lookup seeds; User_SendContactOtp + User_VerifyContactOtp SPs | ✅ Railway applied |
| `NGOConnect_Patch_NearbyFeed.sql` | Project_GetNearbyFeed SP + ProjectSkills covering index | ✅ Railway applied |
| `NGOConnect_Patch_PersonalizedFeed.sql` | PostSaves + FeedInteractions tables; 22 FEED_* Settings seeds; Feed_GetPersonalized, Post_Save, Post_Unsave, Feed_TrackInteraction SPs | ✅ Railway applied |
| `NGOConnect_Patch_ApplicationApply_Fix.sql` | Application_Apply SP: p_Note → p_Motivation + p_RequestedSessions | ✅ Railway applied |
| `NGOConnect_Patch_StaleTokenCleanup.sql` | Notification_DeleteStaleToken SP | ✅ Railway applied |
| `NGOConnect_Patch_NotificationOrgName.sql` | Notifications.OrgId column; Notification_Create + Notification_GetByUser SPs | ✅ Railway applied |
| `NGOConnect_Patch_SuperAdminOrgDetail_TaxEligibility.sql` | Organisations.Is80GEligible/Is12AEligible columns (idempotent ALTER); SuperAdmin_Org_GetDetail SP | ✅ Railway applied |
| `NGOConnect_Patch_OrgUpdateResubmit_TaxEligibility.sql` | Org_Update + Org_Resubmit: add p_Is80GEligible/p_Is12AEligible params | ✅ Railway applied |

### Other Individual Patches (absorbed into versioned patches or superseded)

| File | Absorbed into | Status |
|---|---|---|
| `NGOConnect_Patch_AdminPostsSP.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_ColumnFix.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_Comprehensive_SessionFix.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_DashboardFollowers.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_DashboardProjectApps.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_Distance.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_FixProjectColumns.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_FixProjectTitle.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_GetPendingMembers_Fix.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_ImpactSPs.sql` | v4.5 | ✅ Absorbed into v4.5 patch |
| `NGOConnect_Patch_OrgFollow.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_OrgGetProfile_MemberStatus.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_OrgType_Seed.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_PollOptions_Feed.sql` | Community Railway patch | ✅ Included in `NGOConnect_Patch_Community_Railway.sql` (Community_GetFeed v4.3 — was wrongly marked Superseded) |
| `NGOConnect_Patch_PostCreate_Fix.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_PostFeed_OrgFilter.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_PostFeed_VideoSupport.sql` | v4.5 | ✅ Absorbed into v4.5 patch |
| `NGOConnect_Patch_PostPermissions.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_ProjectCreate_SP_Only.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_ProjectList_SP_Only.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_ProjectList_v2.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_Project_Cancel.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_Project_Create_Fix.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_Project_List_Fix.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_ReportPost.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SessionQR.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosDeclineResponder.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosFix_GetById.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosGetMyActive.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosGetOrgAlerts.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosGetOrgAlertsWithUserId.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SosIncidents_Columns.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_SuperAdminModule.sql` | v4.6 | ✅ Absorbed into v4.6 patch |
| `NGOConnect_Patch_SuperAdminModule_Members_Dashboard.sql` | v4.6 | ✅ Absorbed into v4.6 patch |
| `NGOConnect_Patch_TestData_User4.sql` | Test data only | ✅ Not required on Railway |
| `NGOConnect_Patch_UserDocuments.sql` | v4.5 or earlier | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_UserGetMyOrgs_Final.sql` | v4.5 | ✅ Absorbed into v4.5 patch |
| `NGOConnect_Patch_UserGetMyOrgs_PendingRequests.sql` | v4.5 | ✅ Superseded by setup SQL |
| `NGOConnect_Patch_VolunteerProfileDetails.sql` | v4.7 | ✅ Absorbed into v4.7 patch |
| `NGOConnect_Patch_VolunteerProfileFix.sql` | v4.7 | ✅ Superseded by v4.7 patch |
| `NGOConnect_Patch_VolunteerSPs.sql` | v4.5 | ✅ Superseded by setup SQL |

> ⚠️ **Note on "Superseded by setup SQL"**: these patches' changes ARE in `NGOConnect_Complete_Setup_v4.7.sql` but were not explicitly tracked as absorbed into a versioned Railway patch. If Railway was bootstrapped from v4.5+ setup SQL, they are applied. If Railway was bootstrapped from an older setup SQL, run `NGOConnect_Patch_v4.5_Complete.sql` to catch up.

---

## Pending Changes Tracking

Between document updates, all changes are tracked in this format:

```
**`<Document>`**
- <SP/Table/Endpoint/Model>: <what changed>
```

Current pending list is maintained in the active conversation. When a new
conversation session starts, the pending list must be carried forward from
the session summary.

---

## Source of Truth Priority

When there is a conflict between files, this priority order applies:

1. **Uploaded SP file** (e.g. `02_SP_Auth.sql`) — highest priority, reflects what is actually running in the DB
2. **`NGOConnect_Complete_Setup_v4.0.sql`** — must be kept in sync with uploaded SP files
3. **C# DAL** — must match the SP signatures exactly
4. **C# Models** — must match what DAL sends and SP returns
5. **Documentation** — updated last, reflects all of the above

---


## Current Pending Document Updates

---

**AWS S3 Storage — C# infrastructure** (2026-07-18)
- `NGOConnect.Infrastructure.csproj`: added `AWSSDK.S3 v3.7.413.4`
- `BlobModels.cs`: `BlobUploadResult` — added `FileKey?` + `IsPrivate` fields; `FileUrl` made nullable. Added `PrivateBlobUploadResult` class (FileKey, FileName, FileSizeKb, Module)
- NEW `IPrivateBlobService.cs`: UploadAsync → PrivateBlobUploadResult, GetSignedUrlAsync(key, expiryMinutes=15), DeleteAsync
- NEW `AwsS3BlobService.cs`: IBlobService for public bucket (ripplehub-public). Modules: user-photos, org-logos, project-images, post-media
- NEW `AwsS3PrivateBlobService.cs`: IPrivateBlobService for private bucket (ripplehub-private). SSE-AES256. Presigned URLs (15-min default)
- NEW `FallbackPrivateBlobService.cs`: IPrivateBlobService wrapping IBlobService for local/cloudinary modes
- `LocalFileService.cs`: added project-images module (was missing)
- `ServiceCollectionExtensions.AddBlobService`: awss3 case registers AwsS3BlobService + AwsS3PrivateBlobService
- `MediaController.cs`: routes private modules to IPrivateBlobService; new GET /api/v1/media/signed-url endpoint
- `appsettings.json`: added AWS section (Region, PublicBucket, PrivateBucket, PublicBaseUrl)
- Railway env vars needed: AWS__AccessKeyId, AWS__SecretAccessKey, StorageProvider=awss3

---

**Fast2SMS — mobile OTP delivery** (2026-07-20)
- NEW `ISmsService.cs`: SendOtpAsync(mobile, countryCode, otpCode, expiryMinutes) → bool
- NEW `Fast2SmsService.cs`: Fast2SMS Quick route ("q") for testing; DLT route for production
- `ServiceCollectionExtensions.AddSmsService()`: registers IHttpClientFactory-backed Fast2SmsService
- `Program.cs`: added AddSmsService()
- `AuthDal.cs`: injected ISmsService; SMS now calls Fast2SmsService; real GenerateOtp() re-enabled
- `appsettings.json`: added Sms section (ApiKey, Route, SenderId, TemplateId)
- Railway env var needed: Sms__ApiKey
- **Before production**: switch Sms:Route to "dlt" + register sender/template via TRAI on Fast2SMS DLT panel

---

**Org Member Invitations — full feature (v4.9)** (2026-07-21)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- NEW table `OrgInvitations` (OrgInvitationId, OrgId, InvitedByUserId, InvitedUserId nullable, InviteTypeCode, InviteValue, CountryCode, InviteToken UNIQUE 43-char, TokenExpiry, InviteBaseUrl, StatusCode, SentAt, OpenedAt, AcceptedAt, CancelledAt, DeliveryStatus, DeliveryError, CreatedAt, UpdatedAt)
- NEW LookupType `INVITE_TYPE` (PHONE, EMAIL)
- NEW LookupType `INVITE_STATUS` (PENDING, OPENED, ACCEPTED, CANCELLED, EXPIRED)
- NEW Settings: `INVITE_BASE_URL` (URL), `INVITE_TOKEN_EXPIRY_DAYS` = 30 (NUMBER)
- NEW SPs (7 total):
  - `Org_Invite_Send(p_OrgId, p_InvitedByUserId, p_InviteTypeCode, p_InviteValue, p_CountryCode, p_InviteToken, p_TokenExpiry, p_InviteBaseUrl)` — permission check, self-invite guard, duplicate check, insert, notification
  - `Org_Invite_VerifyToken(p_Token)` — validates + auto-expires, marks OPENED, returns org + invite data
  - `Org_Invite_Accept(p_InvitationId, p_UserId)` — marks ACCEPTED, creates OrgMembershipRequest
  - `Org_Invite_Cancel(p_InvitationId, p_CancelledByUserId)` — marks CANCELLED
  - `Org_Invite_Resend(p_InvitationId, p_RequestedByUserId, p_NewToken, p_NewExpiry, p_InviteBaseUrl)` — refreshes token + expiry, resets to PENDING
  - `Org_Invite_List(p_OrgId, p_RequestorId, p_StatusCode, p_PageNumber, p_PageSize)` — paged DynamicRow with invitee + inviter info, auto-expires lapsed
  - `Org_Invite_GetPendingForUser(p_UserId)` — matches by user's phone/email, returns pending invites

_Backend:_
- NEW `NGOConnect.Core/Models/Invite/InviteModels.cs`: SendInviteRequest, InviteSendResult, ResendInviteRequest, CancelInviteRequest, AcceptInviteRequest, InviteListRequest, InviteResendResult
- NEW `NGOConnect.Core/Interfaces/IOrgInviteDal.cs`: SendAsync, CancelAsync, ResendAsync, ListAsync, VerifyTokenAsync, AcceptAsync, GetPendingForUserAsync
- MODIFIED `IEmailService.cs`: added `SendInviteAsync(toEmail, inviterName, orgName, inviteLink)`
- MODIFIED `ISmsService.cs`: added `SendAsync(mobile, countryCode, message)`
- MODIFIED `Fast2SmsService.cs`: implemented new `SendAsync` (Quick route)
- MODIFIED `AwsSesEmailService.cs`: implemented `SendInviteAsync` with HTML invite email template
- MODIFIED `SmtpEmailService.cs`: implemented `SendInviteAsync`
- NEW `NGOConnect.Infrastructure/DAL/OrgInviteDal.cs`: GenerateToken (32-byte RNG → URL-safe base64 43-char), SendAsync + fire-and-forget DeliverInviteAsync, all 7 DAL methods
- NEW `NGOConnect.API/Controllers/OrgInviteController.cs`: 7 endpoints (see API section)
- MODIFIED `ServiceCollectionExtensions.cs`: `services.AddScoped<IOrgInviteDal, OrgInviteDal>()`

_API endpoints (all under `/api/v1/`):_
- `POST org/{orgId}/invite/send` [Authorize] — send invitation; returns ExistingUserFound + profile preview
- `GET  org/{orgId}/invite/list` [Authorize] — paged invite list; query params: statusCode, pageNumber, pageSize
- `POST org/invite/{invitationId}/cancel` [Authorize]
- `POST org/invite/{invitationId}/resend` [Authorize]
- `GET  org/invite/verify/{token}` [PUBLIC] — deep link token verify; returns org + invite data
- `POST org/invite/{invitationId}/accept` [Authorize]
- `GET  org/invite/pending` [Authorize] — pending invites matched by user phone/email

_Mobile (React Native):_
- NEW `src/api/invite.api.ts`: full typed API layer — inviteApi.send/list/cancel/resend/verifyToken/accept/getPending
- NEW `src/screens/admin/InviteMembersScreen.tsx`: Invite tab (PHONE/EMAIL, country code, preview card, share sheet) + History tab (status filters, FlatList, cancel/resend)
- MODIFIED `src/navigation/AppNavigator.tsx`: added `InviteMembers` stack screen
- MODIFIED `src/screens/admin/AdminVolunteersScreen.tsx`: `+ Invite` button in header → navigates to InviteMembers
- MODIFIED `src/screens/home/HomeScreen.tsx`: `PendingInviteBanner` component; `inviteApi.getPending()` called in `init`; dismissible banners shown in ListHeaderComponent

---

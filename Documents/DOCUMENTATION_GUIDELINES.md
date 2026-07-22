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

### v4.9 Pending — Not yet applied to Railway

| File | What it covers | Status |
|---|---|---|
| `NGOConnect_Patch_InviteListAndPending_v4.9.sql` | Org_Invite_GetHistory: history list SP; Org_Invite_GetPendingForUser: UserId match fix | ⏳ Pending Railway |
| `NGOConnect_Patch_InviteAcceptDirectJoin_v4.9.sql` | Org_Invite_Accept: direct OrgMembers INSERT (skip OrgMembershipRequests approval step) | ⏳ Pending Railway |
| `NGOConnect_Patch_InviteNotifications_v4.9.sql` | Invite notification SPs | ⏳ Pending Railway |
| `NGOConnect_Patch_UrlShareToken_v4.9.sql` | Settings INSERT: SECURITY/URL_SHARE_SECRET_KEY for AES-256-GCM share URL encryption. ⚠️ Replace placeholder with `openssl rand -hex 32` output before running | ⏳ Pending Railway |

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

**Org Invite — Decline flow** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- NEW SP `Org_Invite_Decline(p_InvitationId, p_UserId)` — invitee declines their own invitation; verifies caller by matching Users.Mobile / Users.Email against OrgInvitations.InviteValue; marks status CANCELLED. Distinct from Org_Invite_Cancel (admin-only).
- NEW patch file: `NGOConnect_Patch_OrgInviteDecline_v4.9.sql`

_Backend:_
- `IOrgInviteDal.cs`: added `DeclineAsync(invitationId, userId) → ApiResponse`
- `OrgInviteDal.cs`: implemented `DeclineAsync` — calls `Org_Invite_Decline` SP
- `OrgInviteController.cs`: added `POST /api/v1/org/invite/{invitationId}/decline` [Authorize]

_Mobile (React Native):_
- `src/api/invite.api.ts`: added `decline(invitationId)` method → `POST /org/invite/{id}/decline`
- `src/screens/home/HomeScreen.tsx`:
  - `PendingInviteBanner`: added `onDecline` prop with its own loading state (`declining`); Decline button now calls `onDecline` with red styling; ✕ button still only local-dismisses (user can accept later)
  - `onDecline` callback calls `inviteApi.decline()` → on success removes invite from `pendingInvites` state (permanently, not just local dismiss)
  - `onAccept` callback: after success removes from `pendingInvites` state and re-fetches `getMyOrgs()` so the newly joined org appears in the switcher
  - Busy state guards both Accept and Decline buttons to prevent double-tap

---

**Invite Accept/Decline — Admin Notifications** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- `Org_Invite_Accept`: added cursor loop over org FOUNDER/ADMIN members; inserts `Notifications` row (NotifType=`INVITE_ACCEPTED`) for each after membership request is created; title/body include invitee's full name and org name; RefId=OrgId, RefType='ORG'
- `Org_Invite_Decline`: fetches OrgId in initial SELECT; adds cursor loop over FOUNDER/ADMIN members; inserts `Notifications` row (NotifType=`INVITE_DECLINED`) for each; now returns OrgId in result SELECT
- NEW patch file: `NGOConnect_Patch_InviteNotifications_v4.9.sql` — both updated SPs

_Backend:_
- `OrgInviteDal.cs`: injected `IFCMService` + `INotificationDal`; added private `FireAdminFcmAsync(orgId, title, body, notifType, refId, refType)` helper; `AcceptAsync` fires FCM to org admins after success; `DeclineAsync` reads OrgId from SP result row, fires FCM to org admins after success

_Mobile (React Native):_
- `NotificationsScreen.tsx` → `notifMeta`: added `INVITE_ACCEPTED` (✅ green) and `INVITE_DECLINED` (❌ red)
- `NotificationsScreen.tsx` → `resolveScreen`: `INVITE_ACCEPTED` navigates to `AdminVolunteers` (refId=orgId); `INVITE_DECLINED` navigates to `MyOrgs`

---

**Notifications — bug fixes** (2026-07-22)

_Backend:_
- `FCMService.cs` (`SendAsync` + `SendMulticastAsync`): `ChannelId` changed from `"ngoconnect_default"` → `"ripplehub_default"` to match the Android notification channel created in `MainApplication.kt`

_Mobile (React Native):_
- `src/api/notification.api.ts`: `registerDeviceToken` — `platform: 'android'` replaced with `platform: Platform.OS`; iOS devices now register with the correct platform string
- `src/screens/home/NotificationsScreen.tsx`:
  - `onPressNotif`: mark-as-read is now awaited; on API failure the optimistic update reverts (previously fire-and-forget `.catch(() => {})` silently failed, causing unread state to reappear on refresh)
  - `resolveScreen`: added `MEMBER_INVITE` → InviteAccept (refId = orgId) or MyOrgs fallback; added `DONATION_RECEIVED_ADMIN` → NgoProfile (refId = orgId) or MyOrgs fallback

---

**Home screen — re-invite banner fix** (2026-07-22)

_Mobile (React Native):_
- `src/screens/home/HomeScreen.tsx`: `init()` now calls `inviteApi.getPending()` again (in addition to `useFocusEffect`). Root cause: if user was already on Home screen when admin re-invited, `useFocusEffect` never fired. `init()` is what pull-to-refresh calls, so the banner now also refreshes on pull-to-refresh.

---

**Invite History (list) + Re-invite banner — SP fixes** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- `Org_Invite_List`: permission-denied branch changed from `SELECT 0 AS IsSuccess, 'Permission denied.'` to two empty result sets (`SELECT ... WHERE FALSE` + `SELECT 0 AS TotalCount`). The old single-row response broke `ExecuteDynamicPagedListAsync` which expects two result sets; the DAL caught the exception silently, returning an empty list with no error shown to the user.
- `Org_Invite_GetPendingForUser`: WHERE clause (SELECT and auto-expiry UPDATE) now also matches `oi.InvitedUserId = p_UserId` in addition to phone/email string match. For existing-platform users, `Org_Invite_Send` stores their UserId directly in `InvitedUserId`. Any phone format mismatch between `InviteValue` and `Users.Mobile` would cause the old string-only match to miss the invite. The UserId match bypasses that entirely.
- NEW patch file: `NGOConnect_Patch_InviteListAndPending_v4.9.sql`

---

**URL Share Token Encryption — Hide raw numeric IDs in public URLs** (2026-07-22)

_New C# files:_
- `NGOConnect.Core/Interfaces/IUrlTokenService.cs`: `Encrypt(entityType, id) → string`, `Decrypt(token) → (EntityType, Id)?`
- `NGOConnect.Infrastructure/Services/UrlTokenService.cs`: AES-256-GCM, 12-byte random nonce, 16-byte tag; payload = `"ORG:55"` or `"OPP:3"`; output = URL-safe Base64 (46 chars); key from `ISettingsCache → URL_SHARE_SECRET_KEY`
- `NGOConnect.API/Controllers/ShareController.cs`: `GET /api/v1/share/token?type=ORG&id=55` (requires `[Authorize]`); returns `{ token, url, entityType, entityId }`
- `NGOConnect.API/Controllers/PublicController.cs` (no auth):
  - `GET /api/v1/public/resolve/{token}` → `{ entityType, entityId }` — mobile deep-link resolver
  - `GET /api/v1/public/org/{token}` → org public preview via `Org_GetPublicPreview`
  - `GET /api/v1/public/opportunity/{token}` → project details via `Project_GetByIdAsync(userId=0)`

_ServiceCollectionExtensions.cs:_
- Added `services.AddSingleton<IUrlTokenService, UrlTokenService>()` (v4.9 block)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- Added `Settings` seed row: `SECURITY / URL_SHARE_SECRET_KEY` — placeholder value; replace with `openssl rand -hex 32` output before deploying

_Mobile (React Native):_
- `src/api/share.api.ts` (NEW): `shareApi.getToken(type, id)` → `GET /api/v1/share/token`; `shareApi.resolveToken(token)` → `GET /api/v1/public/resolve/{token}`
- `src/store/pendingDeepLinkStore.ts`: extended `DeepLinkTarget` to support `{ type, token }` in addition to `{ type, id }` for pre-login encrypted-token deep links
- `src/navigation/RootNavigator.tsx`: replaced `extractOrgId`/`extractProjectId` with `extractOrgLink`/`extractProjectLink` that return either `{ orgId }` (legacy) or `{ token }` (encrypted); `handleDeepLink` resolves tokens via `shareApi.resolveToken` before navigating; pending link flush updated for token case; `shareApi` imported
- `src/screens/ngo/NgoProfileScreen.tsx`: Share button now calls `shareApi.getToken('ORG', orgId)` → uses encrypted URL; brief loading spinner while fetching; fallback to legacy URL on error; `shareApi` imported
- `src/screens/volunteer/AllOpportunitiesScreen.tsx`: `ShareSheet` fetches encrypted URL via `shareApi.getToken('OPP', projectId)` on mount; shows legacy URL immediately, replaces with encrypted URL when ready; `buildShareUrl` helper removed; `shareApi` imported

_API docs (pending — add to API_Documentation_v4.9.docx):_
- New section "Share & Public Endpoints"
  - `GET /api/v1/share/token` — auth required, params: `type` (ORG|OPP), `id` (int)
  - `GET /api/v1/public/resolve/{token}` — no auth
  - `GET /api/v1/public/org/{token}` — no auth
  - `GET /api/v1/public/opportunity/{token}` — no auth

_Postman (pending — add to NGOConnect_Postman_Collection_v4.9.json):_
- Add "Share" folder: Get Share Token request
- Add "Public" folder: Resolve Token, Get Org Preview, Get Opportunity Preview requests

_Action required before first deploy:_
1. Run `openssl rand -hex 32` → paste output as `URL_SHARE_SECRET_KEY` in Railway staging Settings table (or via Railway env if preferred)
2. Never reuse the same key across staging and production environments

---

**Invite Accept — Direct Member Join (no approval step)** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- `Org_Invite_Accept`: completely reworked. Previously created an `OrgMembershipRequests` row with `APPLICATION_STATUS = PENDING`, requiring a second admin approval. Now inserts directly into `OrgMembers` with `MEMBER_ROLE = MEMBER` and `MEMBER_STATUS = APPROVED` — the invitation itself IS the approval. Uses `ON DUPLICATE KEY UPDATE` for idempotency. Also:
  - Removed `APPLICATION_STATUS` lookup (was from wrong lookup type anyway)
  - Added `MEMBER_ROLE → MEMBER` and `MEMBER_STATUS → APPROVED` lookups
  - `ALREADY_MEMBER` case now returns `IsSuccess = 1` (not 0) since the user is already in the correct state
  - Notification body updated: "has joined as a member" (was "membership request pending approval")
  - Return column `JoinType` changed from `REQUEST_SUBMITTED` → `DIRECT_JOINED`
  - Return message: "Welcome to {OrgName}! You are now a member."
- NEW patch file: `NGOConnect_Patch_InviteAcceptDirectJoin_v4.9.sql`

_Backend:_
- `OrgInviteDal.cs` `AcceptAsync`: FCM push body updated — "A user accepted your invitation and has joined the organisation as a member." (was "pending approval")

_Mobile (React Native):_
- `HomeScreen.tsx` `onAccept` Alert: changed from "Request Sent 🎉 / request submitted…" to "Welcome! 🎉 / {SP message}"
- `InviteAcceptScreen.tsx`: Alert changed from "Request Submitted 🎉" to "Welcome! 🎉 / {SP message}"; body copy updated from "Accept to submit a membership request — admins will approve it" to "Accept the invitation to join instantly as a member"

---

**Profile Stats Sync — Hours / Projects / Score / NGOs now match Impact screen** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- `User_GetProfile`: added `TotalHours`, `ProjectsCount`, `NgosJoined` subqueries (identical logic to `User_GetImpact` — same ATTENDANCE_STATUS/ATTENDED lookup, same COMPLETED/EXPIRED project filter, same APPROVED OrgMembers count). Profile screen stats now computed at read time, not from stale stored columns.
- `User_GetImpact`: added `UPDATE UserProfiles SET ImpactScore = v_ImpactScore WHERE UserId = p_UserId` after score calculation so stored `ImpactScore` is kept in sync. Profile screen Score is now correct even before the user visits the Impact tab.
- NEW patch file: `NGOConnect_Patch_ProfileStatsSync_v4.9.sql` — both updated SPs

_Backend:_
- `NGOConnect.Core/Models/User/UserModels.cs` → `UserProfileModel`: added `TotalHours (decimal)`, `ProjectsCount (int)`, `NgosJoined (int)` properties
- `NGOConnect.Infrastructure/DAL/UserDal.cs` → `MapProfile`: added `Col<decimal>(row, "TotalHours")`, `Col<int>(row, "ProjectsCount")`, `Col<int>(row, "NgosJoined")` mappings

_Mobile (React Native):_
- `src/types/api.types.ts` → `UserProfile`: added `ngosJoined?: number`
- `src/screens/profile/ProfileScreen.tsx`: NGOs stat changed from `orgs.length` (all orgs including pending) → `profile?.ngosJoined ?? 0` (approved memberships only, matches Impact screen)

---

**Help & Support — Phase 1 (email-only)** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- NEW SP `Support_LogContact(p_UserId, p_CategoryCode, p_Subject, p_Description, p_ContactEmail, p_ContactName, p_IpAddress)` — inserts a row into `AuditLogs` (Action=`SUPPORT_CONTACT`, EntityName=`SupportContact`, NewValue=JSON). Returns `IsSuccess=1, Message='Your message has been sent…'`. No new tables in Phase 1.
- NEW patch file: `NGOConnect_Patch_SupportLogContact_v4.9.sql`

_Backend:_
- `IEmailService.cs`: added `SendSupportEmailAsync(contactName, categoryLabel, subject, description, contactEmail)`; email goes TO `Email:SupportAddress` (default: `support@ripplehub.app`), Reply-To = user's contactEmail
- `SmtpEmailService.cs`: implemented `SendSupportEmailAsync` with branded HTML template (category badge, from/email detail table, message body, Reply-To tip)
- `AwsSesEmailService.cs`: implemented `SendSupportEmailAsync` (ReplyToAddresses = user email)
- NEW `NGOConnect.Core/Models/Support/SupportModels.cs`: `SupportContactRequest` (CategoryCode, CategoryLabel, Subject, Description, ContactEmail, ContactName)
- NEW `NGOConnect.Core/Interfaces/ISupportDal.cs`: `LogContactAsync(userId, request, ipAddress) → WriteResult`
- NEW `NGOConnect.Infrastructure/DAL/SupportDal.cs`: calls `Support_LogContact` via `ExecuteWriteAsync`
- NEW `NGOConnect.API/Controllers/SupportController.cs`: `POST /api/v1/support/contact` [Authorize] — logs then fires email (fire-and-forget so email glitch never fails the user)
- `ServiceCollectionExtensions.cs` `AddDataAccessLayer`: added `services.AddScoped<ISupportDal, SupportDal>()`

_New Railway env var (optional):_
- `Email__SupportAddress` — override support inbox (default: `support@ripplehub.app`)

_API endpoint (add to API_Documentation_v4.9.docx):_
- `POST /api/v1/support/contact` [Authorize]
  - Body: `{ categoryCode, categoryLabel, subject, description, contactEmail, contactName }`
  - Response: `ApiResponse` (IsSuccess=1, Message = confirmation string)
  - Category codes: `GENERAL_QUERY | DONATION_SUPPORT | ORG_APPROVAL | BUG_REPORT | FEEDBACK`

_Postman (add to NGOConnect_Postman_Collection_v4.9.json):_
- New "Support" folder: Submit Contact request

_Mobile (React Native):_
- NEW `src/api/support.api.ts`: `submitSupportContact(request)` → `POST /support/contact`
- NEW `src/screens/profile/HelpSupportScreen.tsx`: category chip picker (5 options), Subject + Description inputs (char count), pre-filled Name + Email (editable), Submit → API → success state ("Message Sent!")
- `src/navigation/AppNavigator.tsx`: added `HelpSupport` stack screen → `HelpSupportScreen`
- `src/screens/profile/ProfileScreen.tsx` `SETTINGS_ITEMS`: added `{ icon: '🆘', label: 'Help & Support', screen: 'HelpSupport' }` after Privacy Policy

---

**Help & Support — Attachment support (≤ 5 MB)** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- `Support_LogContact`: added `IN p_AttachmentUrl VARCHAR(2048)`; stored in AuditLogs NewValue JSON as `attachmentUrl` key
- `NGOConnect_Patch_SupportLogContact_v4.9.sql`: updated with new param

_Backend:_
- `SupportModels.cs` → `SupportContactRequest`: added `AttachmentUrl? (string, max 2048)`
- `ISupportDal.cs` / `SupportDal.cs`: passes `p_AttachmentUrl` to SP
- `IEmailService.cs` → `SendSupportEmailAsync`: added `attachmentUrl? = null` param
- `SmtpEmailService.cs` + `AwsSesEmailService.cs`: HTML shows 📎 ATTACHMENT block with clickable link when present; plain-text body appends `\nAttachment: {url}`
- `SupportController.cs`: passes `request.AttachmentUrl` to email service

_Mobile (React Native):_
- `support.api.ts` → `SupportContactRequest`: added `attachmentUrl?: string`
- `HelpSupportScreen.tsx`:
  - "Attach a file" dashed-border button (📎) opens Alert with two options: Photo/Image (launchImageLibrary — photos + videos) and PDF/Video/File (DocumentPicker — pdf, video, allFiles)
  - 5 MB guard: `picked.size > MAX_BYTES` → Alert and abort before attaching
  - Attachment preview card: image thumbnail for photos; emoji icon (📄/🎬/📁) for docs/videos; file name + "Ready to upload" label; ✕ remove button
  - On submit: uploads to `/media/upload?module=support-attachments` (public module → directly-clickable URL); upload failure prompts "Send anyway?" — non-blocking
  - `attachmentUrl` included in `submitSupportContact` request body

---

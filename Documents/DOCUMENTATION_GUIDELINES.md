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
| `NGOConnect_Complete_Setup_v4.8.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.8.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.8.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.8.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

### Community Module Patches (missed in v4.7 — apply via combined patch below)

| File | What it fixes | Status |
|---|---|---|
| `NGOConnect_Patch_CommunityFeed_ColumnFix.sql` | Community_GetFeed: AuthorName + IsAcknowledged column names | 🟡 Local only |
| `NGOConnect_Patch_CommunityCreatePost_SPFix.sql` | Community_CreatePost: 14-param → 6-param (critical — DAL mismatch) | 🟡 Local only |
| `NGOConnect_Patch_CommunityPollVote_SPFix.sql` | Community_CreatePoll: 5-param; Community_Vote: 3-param | 🟡 Local only |
| `NGOConnect_Patch_CommunityLikesComments.sql` | LikeCount/CommentCount columns; 3 new tables; LikePost/AddComment/GetComments/LikeComment SPs | 🟡 Local only |
| `NGOConnect_Patch_Community_Railway.sql` | **Combined patch containing all 4 above — apply this to Railway** | 🟡 Pending Railway |

### v4.8 Patches (local only — pending Railway deployment)

| File | What it covers | Status |
|---|---|---|
| `NGOConnect_Patch_SuperAdminMembersList_ShowUnlinked.sql` | SuperAdmin_User_GetList: HAVING clause's zero-org-membership branch no longer requires p_OrgIds to be NULL/empty — brand-new registrants with no org link now show regardless of which orgs are selected in the Members page filter | 🟡 Local only |
| `NGOConnect_Patch_PostLike_FieldFix.sql` | Post_GetFeed + Post_GetById: rename IsLikedByMe → IsLiked alias | 🟡 Local only |
| `NGOConnect_Patch_ImpactRankFix.sql` | User_GetImpact: TotalRanked counts all active users (fixes "#1 of 0") | 🟡 Local only |
| `NGOConnect_Patch_ContactUpdate.sql` | ADD_PHONE + ADD_EMAIL lookup seeds; User_SendContactOtp + User_VerifyContactOtp SPs | 🟡 Local only |
| `NGOConnect_Patch_NearbyFeed.sql` | Project_GetNearbyFeed SP + ProjectSkills covering index (ProjectId, SkillName) | 🟡 Local only |
| `NGOConnect_Patch_PersonalizedFeed.sql` | ALTER TABLE Posts (4 cols + index); PostSaves + FeedInteractions tables; 22 FEED_* Settings seeds; Feed_GetPersonalized, Post_Save, Post_Unsave, Feed_TrackInteraction SPs | 🟡 Local only |
| `NGOConnect_Patch_ApplicationApply_Fix.sql` | Add RequestedSessions column to ProjectApplications if missing; fix Application_Apply SP — p_Note → p_Motivation + add p_RequestedSessions (DAL/SP param mismatch causing "An error occurred" on apply) | 🟡 Local only |
| `NGOConnect_Patch_StaleTokenCleanup.sql` | Add `Notification_DeleteStaleToken` SP — deletes stale FCM tokens when Firebase returns `Unregistered`; auto-called by FCMService | 🟡 Local only |
| `NGOConnect_Patch_NotificationOrgName.sql` | ALTER TABLE Notifications ADD OrgId; recreate Notification_Create (adds p_OrgId); recreate Notification_GetByUser (LEFT JOIN Organisations → OrgName + OrgLogoUrl) | 🟡 Local only |
| `NGOConnect_Patch_SuperAdminOrgDetail_TaxEligibility.sql` | Organisations: adds Is80GEligible/Is12AEligible columns (idempotent ALTER, for DBs that predate v4.0); SuperAdmin_Org_GetDetail: adds Is80GEligible, Is12AEligible to SELECT | 🟡 Local only |
| `NGOConnect_Patch_OrgUpdateResubmit_TaxEligibility.sql` | Org_Update + Org_Resubmit: adds p_Is80GEligible/p_Is12AEligible params (run AFTER the patch above) | 🟡 Local only |

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

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-17) — notification org name
- Added `OrgId INT UNSIGNED NULL` column to `Notifications` table (with index `idx_notif_org`)
- Updated `Notification_Create` SP: new `p_OrgId INT UNSIGNED` parameter; inserts into `OrgId` column
- Updated `Notification_GetByUser` SP: `LEFT JOIN Organisations` on `n.OrgId`; returns `OrgId`, `OrgName`, `OrgLogoUrl`
- Patch file: `NGOConnect_Patch_NotificationOrgName.sql` — 🟡 PENDING Railway deployment

**API — `INotificationDal.cs` / `NotificationDal.cs` / `OrgDal.cs` / `CommunityDal.cs`** (2026-07-17) — notification org name
- `INotificationDal.CreateAsync`: added `int? orgId = null` parameter
- `NotificationDal.CreateAsync`: passes `p_OrgId` to `Notification_Create` SP
- `OrgDal.FireUserNotifAsync`: added `int? orgId = null`; passed to `CreateAsync` — wired for MEMBERSHIP_APPROVED, MEMBERSHIP_REJECTED, MEMBER_REMOVED, MEMBER_ROLE_CHANGED
- `CommunityDal.CreatePostAsync` / `CreatePollAsync`: pass `request.OrgId` to `CreateAsync`

**Mobile — `api.types.ts` / `NotificationsScreen.tsx`** (2026-07-17) — notification org name
- `Notification` interface: added `orgId?`, `orgName?`, `orgLogoUrl?` fields
- `NotificationsScreen.NotifRow`: shows `🏢 <OrgName>` tag below notification body when `orgName` is present

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-17) — stale token cleanup
- Added `Notification_DeleteStaleToken(p_Token VARCHAR(512))` SP — deletes stale/unregistered FCM tokens from `UserDeviceTokens`; called automatically by `FCMService` when Firebase returns `Unregistered`
- Patch file: `NGOConnect_Patch_StaleTokenCleanup.sql` — 🟡 PENDING Railway deployment

**API — `INotificationDal.cs` / `NotificationDal.cs` / `FCMService.cs`** (2026-07-17) — stale token cleanup
- `INotificationDal`: added `DeleteStaleTokenAsync(string token)`
- `NotificationDal`: implemented via `Notification_DeleteStaleToken` SP
- `FCMService`: injected `IServiceScopeFactory`; `SendMulticastAsync` now collects tokens with `MessagingErrorCode.Unregistered` and fire-and-forgets their deletion via a new DI scope (singleton-safe pattern)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-17)
- File was truncated — `SuperAdmin_User_GetList` TotalCount subquery was cut off mid-statement. Fixed: appended the missing `SELECT COUNT(*) AS TotalCount ...` subquery + `END //` + `DELIMITER ;`
- Added missing Feed SPs that were in `NGOConnect_Patch_PersonalizedFeed.sql` but absent from setup SQL: `Feed_GetPersonalized`, `Post_Save`, `Post_Unsave`, `Feed_TrackInteraction`
- Note: Tables (`PostSaves`, `FeedInteractions`) and Posts columns (`IsEmergency`, `IsEvergreen`, `ShareCount`, `SaveCount`) were already present in the setup SQL; only the SP bodies were missing

**Railway — deploy `NGOConnect_Patch_PersonalizedFeed.sql` to staging** (2026-07-17) — 🟡 PENDING
- Root cause of feed images/videos not showing: `Feed_GetPersonalized` SP on Railway staging is an older version WITHOUT `LEFT JOIN PostMedia` — so `mediaUrls` is NULL in every API response
- All patch steps are idempotent (ALTER TABLE uses `_ngo_add_col` helper, `CREATE TABLE IF NOT EXISTS`, `INSERT IGNORE`, `DROP + CREATE` SPs) — safe to run regardless of Railway's current state
- Run: `NGOConnect_Patch_PersonalizedFeed.sql` directly on Railway staging MySQL



**Mobile — `AdminOrgScreen.tsx`** (2026-07-17) — read-only org profile
- Complete rewrite: removed all edit/save plumbing (`save` callback, `saving` state, `Alert`, `KeyboardAvoidingView`, `Switch`).
- All `FieldRow` components now hardcoded `editable={false}`.
- `Switch` replaced with `BadgeRow` component showing ✓ Yes / ✗ No badge for 80G and 12A fields.
- Added blue info banner "Profile editing is coming soon."
- Added `orgStatus` and `regNumber` state; status badge (APPROVED=green, other=yellow) shown in logo row.
- No API or DB change.

**Mobile — `CreateOrgScreen.tsx`** (2026-07-18) — documents step + country code + certifications
- Bumped to 5-step wizard (was 4). New step 4 = "Documents & Certifications".
- Step 2 Contact Phone: replaced plain TextInput with country code picker + number input (same pattern as LoginScreen). Uses `COUNTRIES`/`DEFAULT_COUNTRY` from `src/constants/countries.ts`. `contactPhoneCountry` stored in FormData; submitted as `{dial}{phone}`.
- New Step 4: registration certificate upload (launchImageLibrary → uploadFile with `AppConfig.UPLOAD_MODULES.ORG_DOCUMENTS`), other document upload, 80G Switch, 12A Switch.
- Review step (step 5) shows `is80G`, `is12A`, cert upload status.
- `orgApi.register` now receives `is80G`, `is12A`, `registrationCertUrl`, `otherDocumentUrl` fields.
- No API or DB change — fields already accepted by backend.

**Mobile — `ExploreScreen.tsx` / `CommunityScreen.tsx`** (2026-07-17) — consistent header
- `ExploreScreen`: added org-switcher header (left = org logo/initials + name + ▾, taps to open org switcher modal); right = 🔔 bell with unread badge + user avatar → Profile. Full org state + useFocusEffect unread poll added. No API or DB change.
- `CommunityScreen`: right side of header — replaced ☰ menu with 🔔 bell (unread badge) + user avatar → Profile. `notificationApi.getUnreadCount()` polled on focus. No API or DB change.

**Deployment — `appsettings.Staging.json`** (2026-07-17)
- Added `https://stage.ripplehub.app` to `Cors:AllowedOrigins` — Website repo's `/admin` panel is being deployed there on Railway (built with `npm run build:staging`)
- No document update needed (config, not a public API contract change) — noted here only so a future session knows why this origin is in the list
- **Still pending:** add `https://ripplehub.app` to `appsettings.json`'s production CORS list once the production Railway service is actually set up (user said "later")

**Deployment — `Website/package.json`** (2026-07-17)
- Added `serve` dependency + `"start": "serve -s dist -l $PORT"` script so Railway can serve the Vite build output as a single-page app (client-side routes fall back to `index.html`)
- No document update needed — deployment tooling, not an API/DB contract change

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-15)
- `SuperAdmin_User_GetList` (both the main SELECT and the TotalCount subquery): HAVING clause's zero-org-membership branch changed from `(COUNT(om.OrgMemberId) = 0 AND (p_OrgIds IS NULL OR p_OrgIds = ''))` to unconditional `COUNT(om.OrgMemberId) = 0`. Root cause: the admin Members page always sends a real, non-empty org ID list (its "all organisations" default resolves to an explicit list, never a true empty filter), so the old condition was never actually satisfied on any real page load — a brand-new registrant with zero org memberships was silently excluded from the Members list no matter what filter was active. Confirmed via user report: API returned the member when queried directly without an orgIds param, but the real Members page (which always sends one) never showed them.
- Patch file: `NGOConnect_Patch_SuperAdminMembersList_ShowUnlinked.sql` — apply to Railway staging + production. Also needs running against whatever local/dev DB is in use.

**Frontend — `Website/src/admin/pages/MembersPage.jsx`** (2026-07-15)
- Org filter dropdown now built from `orgsApi.getAllOrgsBucketed()` (all 5 org statuses) instead of `getOrgsByStatus('APPROVED')` only — lets the admin explicitly filter by members of a still-pending/rejected/suspended org, and prevents the default "select all" from silently narrowing to approved-only orgs.
- Table rendering: `m.orgNames` falls back to `'No organisation yet'` instead of blank; `m.membershipStatus` renders a plain `—` instead of an empty `StatusPill` when null (zero-org members have no membership status at all).

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-14)
- Added `REPORT_STATUS` to LookupTypes seed (`'Report Status'`, `'Review status of a post report'`)
- Added seed values for `REPORT_STATUS`: `PENDING`, `REVIEWED`, `RESOLVED`
- Removed duplicate/broken `Post_Report` SP (old version at ~line 2998 that took `p_ReasonLkpId INT` and used `ORG_STATUS`/PENDING for StatusLkpId — wrong type); the correct SP at line ~5855 remains (takes `p_ReasonCode VARCHAR(50)`, uses `REPORT_STATUS`/PENDING)
- `Post_GetFeed` SP: added `NOT EXISTS (SELECT 1 FROM PostReports pr WHERE pr.PostId = p.PostId AND pr.ReportedByUserId = p_UserId)` to both main SELECT and TotalCount WHERE — reported posts are immediately hidden from the reporter's feed

**SQL — `NGOConnect_Complete_Setup_v4.7.sql`** (2026-07-14)
- `Feed_GetPersonalized` SP: same `NOT EXISTS` PostReports filter added to outer WHERE clause

**Patch file** — `NGOConnect_Patch_PostReport_Fix.sql` — apply to Railway staging + production:
- Seeds REPORT_STATUS lookup type + values
- Backfills NULL StatusLkpId on existing PostReports rows
- Replaces Post_Report SP (correct REPORT_STATUS lookup)
- Replaces Post_GetFeed SP (reported posts hidden from reporter)

**Mobile — `HomeScreen.tsx`** (2026-07-14)
- `submitReport()`: now checks `res.data?.isSuccess` before calling `setReportDone(true)`; shows server error message if `isSuccess = 0` instead of silently showing fake success

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-15)
- `Auth_VerifyOTP` SP: added `IN p_CountryCode VARCHAR(6)` parameter; new-user INSERT now uses `IFNULL(NULLIF(p_CountryCode, ''), '+91')` instead of hardcoded `'+91'`

**Patch file** — `NGOConnect_Patch_AuthVerifyOTP_CountryCode.sql` — apply to Railway staging + production:
- Full rewrite of `Auth_VerifyOTP` SP with `p_CountryCode` param + correct INSERT

**C# — `NGOConnect.Core/Models/Auth/AuthModels.cs`** (2026-07-15)
- `VerifyOtpRequest`: added `CountryCode` property (default `"+91"`)

**C# — `NGOConnect.Infrastructure/DAL/AuthDal.cs`** (2026-07-15)
- `VerifyOtpAsync`: passes `p_CountryCode = request.CountryCode` to `Auth_VerifyOTP`

**Mobile — `OtpScreen.tsx`** (2026-07-15)
- `handleVerify()`: now passes `countryCode` (from route params) to `authApi.verifyOtp`

**Mobile — `src/constants/countries.ts`** (2026-07-15) — NEW FILE
- Shared country list (61 countries, India first, all European countries), `Country` interface, `DEFAULT_COUNTRY`, `EMAIL_REGEX`

**Mobile — `LoginScreen.tsx`** (2026-07-15)
- Country picker replaced with full bottom-sheet Modal + FlatList + search (61 countries)
- Per-country digit validation (minLen/maxLen), email regex validation
- Hint text ("Enter 10 digit number for India") removed
- Imports `COUNTRIES`, `DEFAULT_COUNTRY`, `EMAIL_REGEX` from shared constants

**Mobile — `ContactUpdateModal.tsx`** (2026-07-15) — REWRITTEN
- Country picker (inline, no nested Modal) with search, 61-country list
- Per-country digit validation; passes `country.dial` as `countryCode` to `sendContactOtp`
- Two-step flow: enter contact → enter OTP; step indicator, resend/back

**Mobile — `user.api.ts`** (2026-07-15)
- `sendContactOtp`: added optional `countryCode?: string` param; included in POST body

**Mobile — `CreateProjectScreen.tsx`**
- GPS options: `enableHighAccuracy: true → false`, `maximumAge: 60000 → 300000` — fixes location not detected on tester devices (GPS satellite lock required indoors; network/WiFi location used instead, matching HomeScreen behaviour)

**Mobile — `LiveLocationScreen.tsx`**
- GPS options: `enableHighAccuracy: true → false`, `maximumAge: 15000 → 60000` — fixes "You" marker missing on SOS map for users indoors
- Marker injection trigger: `mapReady` (WebView `onLoad`) → `tilesLoaded` (TILES_LOADED message) — fixes markers not appearing because `window.setMarker` (Leaflet) was not yet defined when `onLoad` fired (Leaflet loads from CDN after the HTML DOM is ready)

**`NGOConnect_Complete_Setup_v4.8.sql`**
- `Application_Apply` SP: remove the duplicate DROP+CREATE block at the bottom of the file (line ~5506) that incorrectly uses `AppliedAt` column (not in v4.8 table schema) and lacks the duplicate-application check. The correct version already exists earlier in the file with `p_Motivation`, `p_RequestedSessions`, `CreatedBy`, and duplicate guard.

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-18) — Community all post types (save + view)
- `Community_CreatePost` SP: supersedes previous ResourceUpload patch. Now adds:
  - `IN p_ResourceFileUrl VARCHAR(500)` — RESOURCE type file URL
  - `IN p_IsPinned TINYINT(1)` — ANNOUNCEMENT: pin to top of feed (stored in `IsPinned` column)
  - `IN p_VolunteersNeeded INT UNSIGNED` — VOL_REQUEST: slots count (stored in `VolunteersNeeded` column)
  - `IN p_EventRef VARCHAR(200)` — multipurpose extra text (stored in `EventRef` column):
      EVENT_UPDATE → whatChanged text; VOL_REQUEST → date/time display text; TASK → free-text assignee name
  - `INSERT INTO CommunityPosts` now includes `IsPinned, VolunteersNeeded, EventRef, ResourceFileUrl` columns
- Patch file: `NGOConnect_Patch_Community_AllTypes.sql` — 🟡 PENDING local DB + Railway deployment
  (supersedes `NGOConnect_Patch_Community_ResourceUpload.sql` — apply AllTypes patch only)

**C# — `CommunityModels.cs`** (2026-07-18) — Community all post types
- `CreateCommunityPostRequest`: added `ResourceFileUrl?`, `IsPinned?` (bool), `VolunteersNeeded?` (int), `EventRef?` (string)

**C# — `CommunityDal.cs`** (2026-07-18) — Community all post types
- `CreatePostAsync`: added `p_ResourceFileUrl`, `p_IsPinned`, `p_VolunteersNeeded`, `p_EventRef` params

**Mobile — `community.api.ts`** (2026-07-18) — Community all post types
- `CreatePostPayload`: added `resourceFileUrl?`, `eventRef?` fields (isPinned + volunteersNeeded already present)

**Mobile — `api.types.ts`** (2026-07-18) — Community all post types
- `CommunityPost` interface: added `eventRef?` (SP EventRef column), `volunteersNeeded?` (SP VolunteersNeeded), `dueDate?` (SP DueDate), `assignedToUserId?`; renamed `totalNeeded` → legacy alias for `volunteersNeeded`; removed dead fields `changeType`, `changeDetail`, `mapsUrl`, `startTime`, `requiredSkills[]`

**Mobile — `NewPostModal.tsx`** (2026-07-18) — Community all post types
- Submit now passes `isPinned` (ANNOUNCEMENT), `volunteersNeeded` (VOL_REQUEST), `eventRef` computed per type (whatChanged for EVENT_UPDATE, eventDateTime text for VOL_REQUEST, assignedTo for TASK)
- Upload box for RESOURCE type: `TouchableOpacity` calling `handlePickResourceFile`; file preview row with remove (✕)

**Mobile — `CommunityPostCard.tsx`** (2026-07-18) — Community all post types
- AnnouncementCard: shows "📌 Pinned" orange badge in header when `item.isPinned`
- QuestionCard: removed misleading inline reply input (discarded typed text). Replaced with tappable "💬 Write an answer..." prompt that opens comment sheet
- EventUpdateCard: change badge now reads from `item.eventRef` (whatChanged) + `item.title` (event name); removed dead `mapsUrl` link
- VolRequestCard: `total` now reads `item.volunteersNeeded` (was `totalNeeded`); date/time shows from `item.eventRef` (was dead `startTime`); removed dead `requiredSkills` chip array
- TaskCard: assignee shows `item.assignedToName || item.eventRef` (eventRef = free-text name stored by form); dueBy shows `item.dueBy || item.dueDate`

**Fix: Member Role Update — all 3 layers** (2026-07-14)
(Patch file: `NGOConnect_Patch_UpdateMemberRole_RoleCode.sql` — apply to Railway staging + production)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`**
- `Org_UpdateMemberRole` SP: changed `p_RoleLkpId INT` → `p_RoleCode VARCHAR(50)`; SP now resolves to LkpId internally via MEMBER_ROLE lookup (same pattern as Org_AddMember)

**C# — `NGOConnect.Core/Models/Org/OrgModels.cs`**
- `UpdateMemberRoleRequest`: changed `RoleLkpId int` → `RoleCode string`

**C# — `NGOConnect.Infrastructure/DAL/OrgDal.cs`**
- `UpdateMemberRoleAsync`: changed `p_RoleLkpId` → `p_RoleCode` parameter

**Mobile — `App/src/api/org.api.ts`**
- `updateMemberRole`: changed `data: { memberId, roleLkpId: number }` → `{ memberId, roleCode: string }`

**Mobile — `App/src/screens/admin/AdminVolunteersScreen.tsx`**
- `MemberDetailsSheet`: added `saveRole` callback + "Save Role" button below role picker dropdown (was previously missing — role change was never sent to API)

---

---

### Session: Mobile Fixes (2026-07-18)

**Mobile — `App/src/api/upload.api.ts`** (2026-07-18) — private module upload fix
- `UploadResult` interface: `fileUrl` made `string | null`; added `fileKey: string | null`, `fileSizeKb?: number`, `isPrivate?: boolean`
- `uploadFile`: return logic changed from `res.data.data?.fileUrl` to `res.data.data?.fileUrl ?? res.data.data?.fileKey` — private modules (`user-documents`, `org-documents`) return `fileKey` not `fileUrl`; old code was throwing the server success message as an error dialog

**Mobile — `App/src/api/org.api.ts`** (2026-07-18) — org document upload after registration
- Added `uploadDocument(orgId, { documentTypeLkpId, fileUrl, fileName })` → `POST /org/{orgId}/documents`

**Mobile — `App/src/screens/ngo/CreateOrgScreen.tsx`** (2026-07-18) — org documents actually saved to DB
- Root cause fix: `registrationCertUrl` / `otherDocumentUrl` / `is80G` / `is12A` were being sent on `orgApi.register()` payload but ASP.NET silently drops unknown JSON fields — nothing was ever written to `OrgDocuments` table
- `FormData`: added `regCertFileName: string` and `otherDocFileName: string`
- `INITIAL`: default values `''` for both new fields
- `pickDoc`: now saves `picked.name` to `regCertFileName` / `otherDocFileName` alongside the URI
- `useEffect`: added `lookupApi.getValuesByTypeCode('DOCUMENT_TYPE_ORG')` → stored in `orgDocTypes` state; provides `REG_CERT` and `OTHER` LookupValueIds at runtime (never hardcoded)
- `handleSubmit`: removed `registrationCertUrl`, `otherDocumentUrl`, `is80G`, `is12A` from `orgApi.register()` payload; after successful register returns `orgId`, calls `orgApi.uploadDocument()` once per uploaded file using lookup IDs resolved from `orgDocTypes`. Failures are non-fatal (caught silently — user can re-upload later)
- ⚠️ `is80G` / `is12A` still not persisted — `Org_Register` SP has no params for them. Needs separate SP change: add `p_Is80GEligible TINYINT(1)` + `p_Is12AEligible TINYINT(1)` to `Org_Register` SP and corresponding DAL params

**Mobile — `App/src/components/community/CommunityPostCard.tsx`** (2026-07-18) — RESOURCE card download
- Added `react-native-blob-util` import for native file download
- Added `DownloadIcon` component (drawn with `View` — no icon library required): vertical shaft + arrowhead + base line
- Added `getMimeType(fileName)` helper
- `ResourceCard`: file rows changed from `TouchableOpacity` (full row tappable → Linking.openURL) to `View` with a separate circular download button on the right
- Download button states: `idle` (shows `DownloadIcon`), `downloading` (shows `ActivityIndicator`), `done` (shows ✓ green), `error` (shows ✕ red — resets after 2 s)
- Uses `ReactNativeBlobUtil.config({ addAndroidDownloads: { useDownloadManager: true, notification: true } })` — Android DownloadManager handles background download + notification tray progress. File URL never shown to user
- Removed `Share` and `Linking` imports (no longer needed in this component)

**Mobile — `App/android/app/src/main/AndroidManifest.xml`** (2026-07-18)
- Added `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />` — required for Downloads folder on Android 9 and below; Android 10+ (API 29+) uses scoped storage and does not require this permission

**Mobile — `App/NGOConnectApp/package.json`** (2026-07-18)
- Added `react-native-blob-util@0.24.10` (supports new architecture via codegenConfig)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-18) — Org_Register 80G/12A
- `Org_Register` SP: added `IN p_Is80GEligible TINYINT(1)` and `IN p_Is12AEligible TINYINT(1)` params; INSERT now includes `Is80GEligible, Is12AEligible` columns using `IFNULL(p_Is80GEligible, 0)` / `IFNULL(p_Is12AEligible, 0)`
- Patch file: `NGOConnect_Patch_OrgRegister_Is80G_Is12A.sql` — 🟡 PENDING local DB + Railway

**C# — `NGOConnect.Core/Models/Org/OrgModels.cs`** (2026-07-18) — Org_Register 80G/12A
- `RegisterOrgRequest`: added `Is80GEligible bool` (default false) and `Is12AEligible bool` (default false)

**C# — `NGOConnect.Infrastructure/DAL/OrgDal.cs`** (2026-07-18) — Org_Register 80G/12A
- `RegisterAsync`: added `p_Is80GEligible` and `p_Is12AEligible` params (bool → 0/1 conversion)

**Mobile — `App/src/screens/ngo/CreateOrgScreen.tsx`** (2026-07-18) — Org_Register 80G/12A
- `handleSubmit`: added `is80GEligible: form.is80G` and `is12AEligible: form.is12A` to `orgApi.register()` payload (previously omitted — values were captured in UI but never sent; now wired through)

**Railway env vars — staging** (2026-07-18) — discussed but not yet verified applied:
- AWS S3 buckets: `AWS__PublicBucket=ripplehub-public`, `AWS__PrivateBucket=ripplehub-private`, `AWS__PublicBaseUrl=https://ripplehub-public.s3.ap-south-1.amazonaws.com`
- Email SMTP: `Email__SmtpHost=smtp.hostinger.com`, `Email__SmtpPort=587`, `Email__FromAddress=no-reply@ripplehub.app`, `Email__FromName=NGO Connect`, `Email__UseSsl=false`, `Email__SmtpUsername=<hostinger-username>`, `Email__SmtpPassword=<password>`

---

**AWS S3 Storage — C# infrastructure** (2026-07-18)
- `NGOConnect.Infrastructure.csproj`: added `AWSSDK.S3 v3.7.413.4`
- `BlobModels.cs`: `BlobUploadResult` — added `FileKey?` + `IsPrivate` fields; `FileUrl` made nullable. Added new `PrivateBlobUploadResult` class (FileKey, FileName, FileSizeKb, Module)
- NEW `IPrivateBlobService.cs`: interface with `UploadAsync` → `PrivateBlobUploadResult`, `GetSignedUrlAsync(key, expiryMinutes=15)` → string URL, `DeleteAsync(key)` → bool
- NEW `AwsS3BlobService.cs`: implements `IBlobService` for public S3 bucket (`ripplehub-public`). Modules: user-photos, org-logos, project-images, post-media
- NEW `AwsS3PrivateBlobService.cs`: implements `IPrivateBlobService` for private S3 bucket (`ripplehub-private`). Modules: user-documents, org-documents, certificates, donation-receipts. All objects SSE-AES256 encrypted. Uses `GetPreSignedURLAsync` for 15-min expiring access links
- NEW `FallbackPrivateBlobService.cs`: implements `IPrivateBlobService` by wrapping `IBlobService` — used in local/cloudinary modes (returns public URL as opaque FileKey, no real expiry)
- `ServiceCollectionExtensions.AddBlobService`: updated to switch on `"awss3"` → registers `AwsS3BlobService` + `AwsS3PrivateBlobService`. Other modes register `FallbackPrivateBlobService` for `IPrivateBlobService`
- `MediaController.cs`: injected both `IBlobService` + `IPrivateBlobService`. `POST /api/v1/media/upload` now auto-routes to private storage for private modules. Added `GET /api/v1/media/signed-url?key={key}&expiryMinutes=15` endpoint
- `appsettings.json`: added `AWS` section (Region, PublicBucket, PrivateBucket, PublicBaseUrl — no secrets). StorageProvider comment updated to include "awss3"
- `appsettings.Development.json`: StorageProvider changed from "cloudinary" → "awss3". Added AWS credentials block (AccessKeyId + SecretAccessKey placeholder)
- AWS setup: account `RippleHub (862012315782)`, IAM user `ripplehub-s3-service` (AKIA4RM7QDCDAPIRCGF4), policy `NGOConnect-S3-Policy`, buckets `ripplehub-public` + `ripplehub-private` in ap-south-1 (Mumbai)
- Railway env vars to add: `AWS__AccessKeyId`, `AWS__SecretAccessKey`, `StorageProvider=awss3`

### Session: Org Documents — View + Download (2026-07-18)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-18) — Org_GetDocuments SP
- Added `Org_GetDocuments(p_OrgId)` SP — returns OrgDocumentId, DocumentTypeLkpId, DocumentType (ValueName), FileUrl, FileName, IsVerified, VerifiedAt, CreatedAt from `OrgDocuments` joined to `LookupValues` for the org admin's own document list
- Patch file: `NGOConnect_Patch_OrgGetDocuments.sql` — 🟡 PENDING local DB + Railway deployment

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** (2026-07-18) — Org_GetProfile 80G/12A fix
- `Org_GetProfile` SP: added `o.Is80GEligible, o.Is12AEligible` to SELECT — these columns were missing so admin screen always showed "No" regardless of DB value
- Patch file: `NGOConnect_Patch_OrgGetProfile_80G12A.sql` — 🟡 PENDING local DB + Railway deployment

**Mobile — `App/src/screens/admin/AdminOrgScreen.tsx`** (2026-07-18) — field name fixes
- `setIs80G`: changed `o.is80G` → `(o as any).is80GEligible ?? (o as any).is80G` (SP column is `Is80GEligible`)
- `setIs12A`: changed `o.is12A` → `(o as any).is12AEligible ?? (o as any).is12A`
- `setRegNumber`: changed `(o as any).registrationNumber` → `(o as any).regNumber ?? (o as any).registrationNumber` (SP column is `RegNumber`)
- `setOrgStatus`: changed `(o as any).orgStatusCode ?? (o as any).status` → `(o as any).statusCode ?? (o as any).orgStatusCode ?? (o as any).status` (SP returns `OrgStatusCode`)

**C# — `NGOConnect.Core/Interfaces/IOrgDal.cs`** (2026-07-18) — Org_GetDocuments
- Added `GetDocumentsAsync(int orgId)` → `Task<ApiResponse<List<DynamicRow>>>`

**C# — `NGOConnect.Infrastructure/DAL/OrgDal.cs`** (2026-07-18) — Org_GetDocuments
- Implemented `GetDocumentsAsync`: calls `Org_GetDocuments` via `ExecuteDynamicListAsync`

**C# — `NGOConnect.API/Controllers/OrgController.cs`** (2026-07-18) — Org_GetDocuments
- Added `GET /api/v1/org/{orgId}/documents` → calls `_org.GetDocumentsAsync(orgId)`. Returns `ApiResponse<List<DynamicRow>>`. Auth: `[Authorize]`

**Mobile — `App/src/api/upload.api.ts`** (2026-07-18) — signed URL helper
- Added `getSignedUrl(fileKey: string)` → `GET /media/signed-url?key={key}` — returns temporary HTTPS URL for private documents; used before every download

**Mobile — `App/src/api/org.api.ts`** (2026-07-18) — fetch org documents
- Added `getDocuments(orgId)` → `GET /org/{orgId}/documents`

**Mobile — `App/src/components/common/DocumentUploadSection.tsx`** (2026-07-18) — download button for user docs
- Added `DownloadIcon` component (pure Views), `getMimeType` helper, `DlState` type
- Added `dlState` state (keyed by `userDocumentId`): idle → downloading → done/error
- Added `downloadDoc(doc)`: calls `getSignedUrl(doc.fileUrl)` then `ReactNativeBlobUtil.config({ addAndroidDownloads: { useDownloadManager: true } }).fetch('GET', signedUrl)` — file saves to Downloads folder via Android DownloadManager, no URL ever shown
- Download button (30×30 circle) added in `uploadedActions` row before Replace button

**Mobile — `App/src/screens/admin/AdminOrgScreen.tsx`** (2026-07-18) — org documents section
- Added `DownloadIcon`, `getMimeType`, `DlState` (same patterns as DocumentUploadSection)
- Added `orgDocs: any[]` and `dlState` state
- `load()` now also calls `orgApi.getDocuments(oid)` after profile fetch — non-blocking
- Added `downloadOrgDoc(doc)` function: same signed-URL + ReactNativeBlobUtil pattern
- Added "Organisation Documents" section in JSX after Certifications: shows each doc (icon + fileName + documentType + verified badge) with circular download button; shows "No documents uploaded yet." when empty

---

**Super Admin — Org detail missing 80G/12A tax eligibility, AND live schema drift discovered** (2026-07-19)
- Initial fix: `SuperAdmin_Org_GetDetail` never selected `Is80GEligible`/`Is12AEligible`, so the Organisations drawer had nothing to render for tax eligibility.
- **Bigger discovery while testing the fix**: `CALL SuperAdmin_Org_GetDetail(55)` on the user's local DB threw `Error 1054: Unknown column 'o.Is80GEligible' in 'field list'`. Root cause: `Organisations.Is80GEligible`/`Is12AEligible` have been in the setup SQL's `CREATE TABLE` definition since v4.0 (any DB built fresh from setup SQL has them), but **no ALTER TABLE patch was ever written to retrofit them onto an already-running DB**. The user's local DB predates that column being added and never got it. This means `Org_Register`'s INSERT (which references the same two columns, added 2026-07-18) has likely also been silently failing with the same "Unknown column" error on this DB for every org registration attempt since — **needs verification: ask user to test Create Org on mobile against local DB after the patch below is applied.**
- **SQL — `NGOConnect_Complete_Setup_v4.8.sql`**: `SuperAdmin_Org_GetDetail` SELECT — added `o.Is80GEligible, o.Is12AEligible`. `CREATE TABLE Organisations` already correct for fresh DBs, no change needed there.
- **Patch file — `NGOConnect_Patch_SuperAdminOrgDetail_TaxEligibility.sql`** (rewritten to fix root cause, not just the symptom) — 🟡 PENDING local DB + Railway staging + Railway production. Now does BOTH: (1) idempotent `ALTER TABLE Organisations ADD COLUMN Is80GEligible/Is12AEligible` via the standard `_ngo_add_col` INFORMATION_SCHEMA-checked helper (safe to re-run, safe on DBs that already have the columns — e.g. Railway may already be fine if it was built from a v4.0+ setup SQL), (2) recreates `SuperAdmin_Org_GetDetail` with the new SELECT columns.
- **Action needed before assuming Railway has the same bug**: run `CALL SuperAdmin_Org_GetDetail(<any orgId>)` on Railway staging/production directly to check if those DBs also predate the column, or were built fresh from a v4.0+ setup SQL (in which case only the SP half of the patch matters there — the ALTER TABLE step is a no-op either way since it's idempotent).
- **Frontend — `Website/src/admin/pages/OrgDrawer.jsx`**: added a "Tax eligibility" section showing 80G/12A as ✓ Yes / ✗ No pills, reading `org.is80GEligible`/`org.is12AEligible` (DynamicRow auto-camelCases the new SP columns — no C# change needed for `GetOrgDetailAsync`, per CORE_MANDATE DynamicRow pattern).
- Ran `scripts/validate_sp_params.py` before the SP change — confirmed clean (163 SPs, 264 DAL call sites, no mismatches). Note: this script only checks DAL↔SP *parameter* names, not SP↔table *column* names — it would not have caught this specific bug. Worth keeping in mind for future schema-drift issues.

**Org_Update / Org_Resubmit — add tax eligibility flags** (2026-07-19)
- Gap found while fixing the SuperAdmin display bug above: `Org_Register` already accepted `Is80GEligible`/`Is12AEligible`, but `Org_Update` (Edit Organisation) and `Org_Resubmit` (founder resubmits after rejection) did not — so once set at registration, these flags could never be changed.
- **SQL — `NGOConnect_Complete_Setup_v4.8.sql`**: `Org_Update` — added `p_Is80GEligible`/`p_Is12AEligible` params, COALESCE pattern (matches its existing partial-update style). `Org_Resubmit` — added same two params, direct assignment (matches its existing full-redeclaration style, no COALESCE).
- **Patch file — `NGOConnect_Patch_OrgUpdateResubmit_TaxEligibility.sql`** — 🟡 PENDING local DB + Railway staging + Railway production. Depends on `NGOConnect_Patch_SuperAdminOrgDetail_TaxEligibility.sql` having already added the columns to `Organisations` — run that one first if not already applied.
- **C# — `OrgModels.cs`**: `UpdateOrgRequest` — added `bool? Is80GEligible`, `bool? Is12AEligible` (nullable, so omitting them in an edit leaves the DB value untouched). `ResubmitOrgRequest` — added `bool Is80GEligible = false`, `bool Is12AEligible = false` (non-nullable, matches the full-redeclaration semantics of resubmission).
- **C# — `OrgDal.cs`**: `UpdateAsync` — passes `p_Is80GEligible`/`p_Is12AEligible` as nullable int (null → DBNull, preserves COALESCE passthrough). `ResubmitAsync` — passes as required int 1/0.
- Ran `scripts/validate_sp_params.py` after these changes — confirmed clean (163 SPs, 264 DAL call sites, no mismatches).
- **Still needed, mobile side (no repo access this session)**: Edit Organisation screen and Resubmit-after-rejection screen need a UI toggle for 80G/12A added, and must send the field. Also unverified: whether `CreateOrgScreen.tsx`'s JSON payload actually uses the key names `is80GEligible`/`is12AEligible` that ASP.NET model binding expects — the changelog entry for that screen describes the fields as `is80G`/`is12A`, which would NOT bind and would silently be dropped, the same failure mode as the OrgDocuments linking gap. Needs a mobile-side check.

**Super Admin — Document View fix for AWS S3 private storage** (2026-07-18)
- Root cause: after the S3 private-storage switch, `OrgDocuments.FileUrl` / `UserDocuments.FileUrl` store a bare S3 object key, not a browsable URL. The Members/Organisations drawer "View" buttons were still doing `<a href={d.fileUrl}>`, which is broken for any document uploaded under `StorageProvider=awss3`.
- **C# — `NGOConnect.API/Controllers/SuperAdminController.cs`**: injected `IPrivateBlobService`; added `GET /api/v1/superadmin/documents/signed-url?fileKey={key}&expiryMinutes=15` endpoint calling `_privateBlob.GetSignedUrlAsync(fileKey, expiryMinutes)`. No DB/SP change needed — this is a pure blob-service passthrough.
- **Frontend — NEW `Website/src/admin/api/media.js`**: `getDocumentSignedUrl(fileKey, expiryMinutes=15)` calling the new endpoint.
- **Frontend — `Website/src/admin/pages/OrgDrawer.jsx` / `MemberDrawer.jsx`**: "View" `<a href={d.fileUrl}>` replaced with a button that fetches a fresh signed URL on click and opens it in a new tab (shows "Loading…" while fetching). Works transparently for pre-S3 documents too, since `FallbackPrivateBlobService` just returns the stored URL as-is.
- **Status: uncompiled/untested** — no .NET SDK available to build in this session. Will not work on Railway staging/production until `StorageProvider=awss3` + `AWS__AccessKeyId` + `AWS__SecretAccessKey` env vars are actually set there (still pending — see AWS S3 Storage entry above).
- **API Documentation** — New endpoint: `GET /api/v1/superadmin/documents/signed-url`
- **Postman Collection** — Add request for new signed-url endpoint

---

**Permission Enforcement — all 3 layers** (2026-07-14)
(Patch file: `NGOConnect_Patch_PermissionEnforcement.sql` — apply to Railway staging + production)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`**
- `Post_GetPermissions` SP: added `CanComment` and `CanCommunityPost` columns to DECLARE + SELECT INTO + final SELECT (reads from OrgMembers)
- `Post_Create` SP: wrapped INSERT logic in CanPost + MaxPostsPerDay gate — returns `IsSuccess=0` + message if either check fails; non-members are blocked
- `Post_AddComment` SP: now looks up post's OrgId, checks OrgMembers.CanComment; non-members and members with CanComment=0 are blocked (returns `IsSuccess=0`); public posts (OrgId=0) are unrestricted
- `Community_CreatePost` SP: checks OrgMembers.CanCommunityPost before INSERT; returns `IsSuccess=0` if blocked
- `Community_CreatePoll` SP: checks OrgMembers.CanCommunityPost before INSERT; returns `IsSuccess=0` if blocked

**C# — `NGOConnect.Core/Models/Post/PostModels.cs`**
- `PostPermissionsModel`: added `CanComment` (bool) and `CanCommunityPost` (bool) properties

**C# — `NGOConnect.Infrastructure/DAL/PostDal.cs`**
- `GetPermissionsAsync`: added `CanComment` and `CanCommunityPost` column mappings

**Mobile — `App/src/types/api.types.ts`**
- `PostPermissions` interface: added `canComment: boolean` and `canCommunityPost: boolean`

**Mobile — `App/src/screens/home/HomeScreen.tsx`**
- Added `postPermsCache` ref (caches fetched permissions per org so comment gate reuses FAB-fetched data)
- `handleComposeFabPress`: stores fetched permissions in `postPermsCache.current[orgId]` after FAB check
- Added `handleCommentPress` callback: checks cached `canComment`; fetches if not cached; shows Alert if disabled; replaces `onCommentPress={p => setCommentPost(p)}`

**Mobile — `App/src/screens/community/CommunityScreen.tsx`**
- Added import: `feedApi` from `feed.api`
- Added `communityPermChecking` state
- Added `handleComposeFabPress` callback: checks `canCommunityPost` via `feedApi.getPostPermissions(orgId)` before opening NewPostModal
- FAB `onPress` changed from `() => setShowModal(true)` → `handleComposeFabPress`

---

### Timezone Fix — UTC Timestamp Parsing (2026-07-15)

**Root cause:** Railway's MySQL server runs in UTC. All `NOW()` calls store UTC datetimes. C#/ASP.NET serializes `DateTime` (Kind=Unspecified from MySQL) as `"2026-07-14T09:00:00"` — no `Z` suffix. JavaScript's `new Date("2026-07-14T09:00:00")` (no timezone marker) treats the value as **local time**, not UTC (per ECMAScript spec). On a device in IST (UTC+5:30), a UTC timestamp of 09:00 is parsed as IST 09:00 (= UTC 03:30), creating a 5.5-hour offset — shown as "5H ago" for a just-created record.

**Fix (mobile only — no DB or C# changes needed):** Added `asUtc()` helper in each file that force-appends `Z` to the string before parsing. This is timezone-agnostic: `Date.now()` and `asUtc(iso).getTime()` are both UTC ms, so the diff is correct for any user worldwide.

**Mobile — `App/src/components/home/FeedCommentsModal.tsx`**
- Added `asUtc(iso: string): Date` helper
- `timeAgoFromDate`: replaced `new Date(iso)` → `asUtc(iso)` (both the diff calculation and the `toLocaleDateString` fallback)

**Mobile — `App/src/components/community/CommunityCommentsModal.tsx`**
- Added `asUtc(iso: string): Date` helper
- `timeAgoFromDate`: replaced `new Date(iso)` → `asUtc(iso)` in diff calculation and date fallback

**Mobile — `App/src/screens/community/CommunityScreen.tsx`**
- Added `asUtc(iso: string): Date` helper
- `timeAgoShort`: replaced `new Date(iso)` → `asUtc(iso)`

**Mobile — `App/src/screens/sos/LiveLocationScreen.tsx`**
- Added `asUtc(iso: string): Date` helper
- `timeAgoShort`: replaced `new Date(iso)` → `asUtc(iso)`
- `fmtTime`: replaced `new Date(iso)` → `asUtc(iso)` (SOS timestamp display)

---

### Project Create/Update Fix (2026-07-14)

**Root cause:** `Project_Create` and `Project_Update` SPs both referenced `RequiresApproval`, `GenderRestriction`, and `CoverImageUrl` columns in their INSERT/UPDATE statements. None of these columns exist in the `Projects` table. MySQL threw `Unknown column` on every project creation/edit, caught by the C# DAL as "An error occurred."

**Note:** `p_RequiresApproval` parameter is still kept on both SPs — it is used in the logic to resolve `JoinTypeLkpId` (APPROVE_REQ vs OPEN_SIGNUP). It just no longer gets written to a non-existent column.

**`NGOConnect_Complete_Setup_v4.8.sql`** — Fixed:
- `Project_Create` INSERT: removed `RequiresApproval, GenderRestriction, CoverImageUrl` from column list and corresponding values
- `Project_Update` SET: removed `RequiresApproval = ...`, `GenderRestriction = ...`, `CoverImageUrl = ...` lines

**Patch file** — `NGOConnect_Patch_ProjectCreate_Fix.sql` — **apply to Railway staging + production immediately**:
- DROP + CREATE `Project_Create` (fixed)
- DROP + CREATE `Project_Update` (fixed)

---

### Verification Badges Feature (2026-07-14)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`**
- Added `ORG_VERIFICATION_STATUS` to LookupTypes seed; seed values: PENDING(1), VERIFIED(2), REJECTED(3)
- Added `REJECTED` (OrderNo=4) to `PROFILE_VERIFICATION_STATUS` lookup values
- Added `VerificationStatusLkpId INT UNSIGNED NULL` column + `INDEX idx_org_verification` to `Organisations` table
- Added FK: `fk_orgs_verificationstatus` on `Organisations.VerificationStatusLkpId → LookupValues`
- Updated `Org_GetProfile` SP: returns `COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode`
- Updated `Org_ListRecommended` SP: returns `COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode`
- Updated `Org_GetMembers` SP: returns `COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode`
- Updated `Org_GetPendingMembers` SP: returns `COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode`
- Added new SP: `SuperAdmin_Org_VerifyProfile(p_OrgId, p_StatusCode, p_SuperAdminId)`

**Patch file** — `NGOConnect_Patch_VerificationBadges.sql` — apply to Railway staging + production:
- Seeds ORG_VERIFICATION_STATUS + REJECTED to PROFILE_VERIFICATION_STATUS
- ALTER TABLE Organisations ADD COLUMN VerificationStatusLkpId + INDEX + FK
- DROP+CREATE for: Org_GetMembers, Org_GetPendingMembers, Org_GetProfile, Org_ListRecommended, SuperAdmin_Org_VerifyProfile

**C# — `NGOConnect.Core/Interfaces/ISuperAdminDal.cs`**
- Added `Task<ApiResponse> VerifyOrgProfileAsync(int orgId, string statusCode, int superAdminUserId)`

**C# — `NGOConnect.Infrastructure/DAL/SuperAdminDal.cs`**
- Added `VerifyOrgProfileAsync` implementation calling `SuperAdmin_Org_VerifyProfile` SP

**C# — `NGOConnect.API/Controllers/SuperAdminController.cs`**
- Added `PUT /api/v1/superadmin/orgs/{orgId}/verify-profile?statusCode=VERIFIED` endpoint

**Mobile — `src/types/api.types.ts`**
- `OrgMember` interface: added `profileVerificationStatusCode?: string`
- `Organisation` interface: added `verificationStatusCode?: string`

**Mobile — `src/components/profile/ProfileIncompleteSheet.tsx`** (NEW FILE)
- Reusable bottom sheet for profile gate — shows missing items + routes to EditProfileScreen step

**Mobile — `src/screens/profile/EditProfileScreen.tsx`**
- Reads `route.params?.initialStep` to open on a specific step (Documents = 4)

**Mobile — `src/screens/opportunities/AllOpportunitiesScreen.tsx`**
- Profile gate before Apply: checks firstName+lastName, city, mobile, Govt Photo ID, Address Proof
- Shows `ProfileIncompleteSheet` with missing items + deep-link to EditProfileScreen

**Mobile — `src/screens/ngo/MyOrgsScreen.tsx`**
- Profile gate before Create Org: same check as AllOpportunitiesScreen
- Shows `ProfileIncompleteSheet` if profile incomplete

**Mobile — `src/screens/admin/AdminVolunteersScreen.tsx`**
- `PendingCard`: shows ✓ Verified badge next to member name when `profileVerificationStatusCode === 'VERIFIED'`
- `MemberRow`: same verified badge

**Mobile — `src/screens/ngo/NgoProfileScreen.tsx`**
- Hero section: shows ✓ Verified badge next to org name when `verificationStatusCode === 'VERIFIED'`

**Mobile — `src/screens/ngo/ExploreScreen.tsx`**
- `OrgRowCard` (Recommended tab): shows ✓ badge next to org name
- `OrgGridCard` (All NGOs tab): shows ✓ badge next to org name

**API Documentation** — New endpoint: `PUT /api/v1/superadmin/orgs/{orgId}/verify-profile`
**Postman Collection** — Add request for new verify-org-profile endpoint

**`Database_Documentation_v4.8.md`**
- `Application_Apply` SP: confirm params shown as `p_Motivation TEXT`, `p_RequestedSessions TEXT`

**`API_Documentation_v4.8.docx`** — no change (endpoint signature unchanged)
**`NGOConnect_Postman_Collection_v4.8.json`** — no change

---

### Session: DAL→SP Parameter Mismatch Audit & Fix (2026-07-12/13)

Comprehensive audit of all 156 SP calls across 11 DAL files. 25+ mismatches fixed.

**`NGOConnect.Core/Models/Application/ApplicationModels.cs`**
- `ReviewApplicationRequest`: `StatusLkpId` (int) → `StatusCode` (string, MaxLength 20); `Note` → `RejectionReason` — matches `Application_Review` SP. ⚠️ API contract change: mobile app must now send `statusCode` (string) not `statusLkpId` (int)

**`NGOConnect.Core/Models/Project/ProjectModels.cs`**
- `CompleteProjectRequest`: added `BeneficiaryCount` (int?) — `Project_Complete` SP requires `p_BeneficiaryCount`

**`NGOConnect.Core/Models/Org/OrgModels.cs`**
- `AddMemberRequest`: added `RoleCode` (string, MaxLength 50, default "MEMBER"); deprecated `RoleLkpId` (Obsolete attribute) — `Org_AddMember` SP takes `p_RoleCode` (string ValueCode), not int

**`NGOConnect.Infrastructure/DAL/ApplicationDal.cs`**
- `GetByProjectAsync` (`Application_GetByProject`): `p_StatusLkpId` → `p_StatusCode`
- `ReviewAsync` (`Application_Review`): `p_StatusLkpId` → `p_StatusCode`; `p_Note` → `p_RejectionReason`; field refs `request.StatusLkpId` → `request.StatusCode`; `request.Note` → `request.RejectionReason`

**`NGOConnect.Infrastructure/DAL/DonationDal.cs`**
- `CreateCampaignAsync` (`Donation_CreateCampaign`): removed `p_UserId`; `p_GoalAmount` → `p_TargetAmount`; removed `p_BannerUrl`; added `p_CreatedBy`=userId; removed post-create `Donation_GetCampaignById` call (SP not in setup SQL) — returns DynamicRow from write result
- `GetCampaignsAsync` (`Donation_GetCampaigns`): `p_Keyword` → `p_StatusCode`
- `GetDonorsAsync` (`Donation_GetDonors`): added `p_OrgId = null`
- `InitiateDonationAsync` (`Donation_Donate`): `p_Note` → `p_Message`; removed `p_PayMethodLkpId`; added `p_PaymentGatewayRef=null`, `p_IsRecurring=0`, `p_RecurringFrequencyLkpId=null`
- `ConfirmPaymentAsync` (`Donation_ConfirmPayment`): removed `p_UserId`; `p_DonationRef` → `p_TransactionId`; added `p_StatusCode="COMPLETED"`, `p_GatewayResponse=null`
- `PauseRecurringAsync` (`Donation_PauseRecurring`): `p_RecurringDonId` → `p_RecurringDonationId`
- `ResumeRecurringAsync` (`Donation_ResumeRecurring`): `p_RecurringDonId` → `p_RecurringDonationId`

**`NGOConnect.Infrastructure/DAL/OrgDal.cs`**
- `RegisterAsync` post-create `Org_GetProfile` call: added `p_UserId` = userId
- `ListAsync` (`Org_List`): removed `p_Lat` and `p_Lng` (SP does not accept these params)
- `AddMemberAsync` (`Org_AddMember`): `p_RequestedBy` → `p_AddedBy`; `p_RoleLkpId` → `p_RoleCode` = `request.RoleCode`
- `RemoveMemberAsync` (`Org_RemoveMember`): `p_RequestedBy` → `p_RemovedBy`
- `UpdateMemberPermissionsAsync` (`Org_UpdateMemberPermissions`): `p_MemberId` → `p_OrgMemberId`

**`NGOConnect.Infrastructure/DAL/PostDal.cs`**
- `PinAsync` (`Post_Pin`): added `p_Pin = true` (SP requires this boolean param)

**`NGOConnect.Infrastructure/DAL/ProjectDal.cs`**
- `AddSkillAsync` (`Project_AddSkill`): removed `p_UserId` and `p_IsRequired` (SP only takes `p_ProjectId`, `p_SkillName`)
- `CheckInAsync` (`Project_CheckIn`): `p_QrToken` → `p_QrCode`
- `CompleteAsync` (`Project_Complete`): `p_UserId` → `p_CompletedBy`; `p_CompletionNotes` → `p_ImpactSummary`; added `p_BeneficiaryCount` = `request.BeneficiaryCount`
- `ApplyAsync`: SP call changed from non-existent `Project_Apply` → `Application_Apply` with `p_Motivation=null`, `p_RequestedSessions=null`

**`NGOConnect.Infrastructure/DAL/SettingsDal.cs`**
- `GetByGroupAsync` (`Settings_GetByGroup`): `p_SettingGroup` → `p_Group`
- `UpdateAsync` (`Settings_Update`): `p_SettingKey` → `p_Key`; `p_SettingValue` → `p_Value`

**`NGOConnect.Infrastructure/DAL/SosDal.cs`**
- `GetLatestLocationAsync` (`Sos_GetLatestLocation`): `p_UserId` → `p_RequestingUserId`

**`NGOConnect.Infrastructure/DAL/BadgeDal.cs`**
- `AwardAsync` (`UserBadge_Award`): added `p_OrgId = null`; fixed param order to match SP (`p_UserId, p_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId`)

**`NGOConnect.Infrastructure/DAL/SkillRatingDal.cs`**
- `AddRatingAsync` (`UserSkillRating_Add`): `p_RaterUserId` → `p_RatedBy`; `p_RatedUserId` → `p_UserId`; `p_UserSkillId` → `p_SkillId`; `p_Review` → `p_Notes`; added `p_OrgId = null`

**`NGOConnect.Infrastructure/DAL/WithdrawalDal.cs`**
- `CreateAsync` (`Withdrawal_Create`): `p_UserId` → `p_RequestedBy`; `p_BankAccount` → `p_BankAccountNumber`; `p_IfscCode` → `p_BankIfsc`; `p_AccountHolder` → `p_BankAccountName`; `p_Purpose` → `p_Notes`
- `AdminReviewAsync` (`Withdrawal_AdminReview`): `p_WithdrawalId` → `p_WithdrawalRequestId`

**`NGOConnect_Complete_Setup_v4.8.sql` + `NGOConnect_Patch_NearbyFeed.sql`**
- `Project_GetNearbyFeed`: EXISTS filter updated — was excluding PENDING/APPROVED only; now excludes ANY non-deleted application (PENDING, APPROVED, REJECTED, WITHDRAWN, ATTENDED, NO_SHOW). A project the user has ever applied to is hidden from their nearby feed. Re-appears only if project completes, a new cycle starts, and admin re-activates it. Removes the JOIN on LookupValues + ValueCode filter from both SELECT and TotalCount queries (simpler, faster — no extra JOIN needed)
- `Application_Apply`: no change needed — existing `IsDeleted = 0` check already blocks re-application for all statuses

### Session: Safe Area Fixes — Bottom Sheet Modals (2026-07-13)

**Mobile only — no API, DB, or document changes required.**

Root cause: `useSafeAreaInsets()` inside React Native `Modal` on Android returns `insets.bottom = 0` because the Modal renders in a new native window that does not receive the JS-side SafeAreaProvider context. Fix: replace all `paddingBottom: insets.bottom + X` patterns inside Modals with `<SafeAreaView edges={['bottom']} style={{ minHeight: X }} />` spacers — native SafeAreaView reads insets at the native layer.

**`App/NGOConnectApp/src/screens/home/HomeScreen.tsx`**
- Report Post modal (`reportSheet`): removed `paddingBottom: 32` from StyleSheet; added `<SafeAreaView edges={['bottom']} style={{ minHeight: 16 }} />` as last child of `<Pressable style={styles.reportSheet}>` — fixes "Submit Report" button hidden behind 3-button nav bar

**`App/NGOConnectApp/src/screens/ngo/NgoProfileScreen.tsx`** (local `ProjectDetailModal`)
- Apply footer: removed `{ paddingBottom: insets.bottom + 12 }` inline style from `<View style={mdStyles.applyFooter}>`; added `<SafeAreaView edges={['bottom']} style={{ minHeight: 12 }} />` as last child — fixes "Apply for Selected Sessions" button overlapping nav bar

**`App/NGOConnectApp/src/components/profile/ContactUpdateModal.tsx`**
- Replaced `import { useSafeAreaInsets }` with `import { SafeAreaView }` from react-native-safe-area-context
- Removed `const insets = useSafeAreaInsets();` hook call
- Changed `<View style={[s.sheet, { paddingBottom: Math.max(insets.bottom + 16, 32) }]}>` → `<View style={s.sheet}>`
- Added `<SafeAreaView edges={['bottom']} style={{ minHeight: 16 }} />` as last child of the sheet — fixes "Send OTP →" button hidden behind nav bar

---

**Still deferred (SPs missing from setup SQL — fix when user instructs):**
- `Settings_GetAll` SP does not exist in setup SQL; `SettingsDal.GetAllAsync` calls it
- `Project_Cancel` SP does not exist in setup SQL; `ProjectDal.CancelAsync` calls it
- `Donation_CancelRecurring` (`DonationDal.CancelRecurringAsync`): `p_RecurringDonId` → `p_RecurringDonationId` (needs SP verification first)
- Missing SPs to add to setup SQL: `Feed_GetPersonalized`, `Feed_TrackInteraction`, `Post_Save`, `Post_Unsave`, `Notification_SaveDeviceToken`, `Donation_GetReceipt`, `Donation_GetCampaignById`, `Donation_SetupRecurring`, `Donation_CancelRecurring`, `Project_Cancel`, all SuperAdmin SPs

<!-- Version bumped: v4.7 → v4.8 (2026-07-13). Active files are now v4.8. -->
<!-- Rule: next version bump happens ONLY when changes are deployed to Railway staging -->

### v4.8 — Applied ✅ (2026-07-13)

All changes below are reflected in all 4 v4.8 documents.

- **NEW TABLE** `PostSaves` — UserId, PostId, SavedAt; UNIQUE KEY (UserId, PostId)
- **NEW TABLE** `FeedInteractions` — UserId, PostId, InteractionType, OccurredAt, DurationMs; 2 indexes
- **NEW COLUMNS** `Posts.IsEmergency`, `Posts.IsEvergreen`, `Posts.ShareCount`, `Posts.SaveCount` + `idx_post_emergency (IsEmergency, CreatedAt)` index
- **COVERING INDEX** `ProjectSkills.idx_projskill_project (ProjectId, SkillName)` — replaces single-col index
- **LOOKUP VALUES** `OTP_PURPOSE`: ADD_PHONE (OrderNo 5), ADD_EMAIL (OrderNo 6)
- **22 FEED_* Settings seeds** (group FEED) — algorithm weights + window sizes
- **NEW SP** `User_SendContactOtp(p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress)` — duplicate check + rate-limit + OTP insert
- **NEW SP** `User_VerifyContactOtp(p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress)` — OTP verify + update Email/Mobile
- **NEW SP** `Project_GetNearbyFeed(p_UserId, p_UserLat, p_UserLon, p_PageNumber, p_PageSize)` — geo-scored opportunities
- **NEW SP** `Feed_GetPersonalized(p_UserId, p_CursorPostId, p_CursorScore, p_PageSize)` — cursor-paginated algorithmic feed
- **NEW SP** `Post_Save(p_UserId, p_PostId)` — idempotent save + SaveCount increment
- **NEW SP** `Post_Unsave(p_UserId, p_PostId)` — unsave + SaveCount decrement
- **NEW SP** `Feed_TrackInteraction(p_UserId, p_PostId, p_InteractionType, p_DurationMs)` — fire-and-forget interaction log
- **FIXED SP** `Post_GetFeed` — IsLikedByMe → IsLiked alias
- **FIXED SP** `Post_GetById` — IsLikedByMe → IsLiked alias
- **FIXED SP** `User_GetImpact` — TotalRanked counts all active users (not just ImpactScore > 0)
- **FIXED SP** `Community_CreatePost` — audience TypeCode AUDIENCE_TYPE (was POST_VISIBILITY)
- **FIXED SP** `Community_CreatePoll` — added p_IsMultiChoice param; audience TypeCode fix
- **FIXED SP** `Community_GetFeed` — v4.3 columns: PollOptionsJson, RoleName, TimeAgo, PostTypeLkpCode
- **NEW endpoints** POST /user/contact/send-otp, POST /user/contact/verify
- **NEW endpoint** GET /project/nearby-feed
- **NEW endpoints** GET /feed/personalized, POST /feed/post/{postId}/save, DELETE /feed/post/{postId}/save, POST /feed/interaction

---

### v4.7 — Applied ✅ (2026-07-12)

All changes below are reflected in all 4 v4.7 documents.

- **NEW TABLE** `OrgFollowers` — soft-unfollow pattern; UNIQUE KEY (OrgId, UserId); IsFollowing TINYINT(1), FollowedAt, UnfollowedAt
- **NEW COLUMN** `Organisations.FollowerCount` INT UNSIGNED DEFAULT 0 — denormalized, maintained by Org_Follow / Org_Unfollow SPs
- **NEW SP** `Org_Follow(p_OrgId, p_UserId)` — idempotent follow with FollowerCount increment
- **NEW SP** `Org_Unfollow(p_OrgId, p_UserId)` — soft-unfollow with GREATEST(n-1,0) counter decrement
- **NEW SP** `Post_GetPermissions(p_OrgId, p_UserId)` — always one row: IsMember, CanPost, MaxPostsPerDay, TodayPostCount
- **FIXED SP** `Org_GetPendingMembers` — adds p_PageNumber/p_PageSize params (IFNULL defaults); mr.RequestId AS MembershipRequestId alias
- **UPDATED SP** `Org_GetProfile` — adds FollowerCount + IsFollowing (0|1 subquery on OrgFollowers)
- **UPDATED SP** `Org_RequestMembership` — auto-follows org on join request (idempotent counter)
- **UPDATED SP** `Org_List` — adds FollowerCount from denormalized column
- **MERGED SP** `Post_GetFeed` — final 4-param version (p_UserId, p_OrgId, p_PageNumber, p_PageSize) + IsFollowing per post + OrgId filter
- **UPDATED SP** `Org_GetDashboard` — adds FollowerCount KPI
- **FIXED SP** `Org_GetVolunteerProfile` — AttendStatusLkpId via DECLARE vars; pa→ProjectSessions join; ReliabilityPct as HAVING aggregate
- **FIXED SP** `SuperAdmin_User_GetList` — LEFT JOIN OrgMembers; HAVING to include new users + APPROVED-only filter; JoinedAt fallback to u.CreatedAt
- **NEW endpoint** POST /api/v1/org/{orgId}/follow
- **NEW endpoint** DELETE /api/v1/org/{orgId}/follow
- **NEW endpoint** GET /api/v1/post/permissions/{orgId}
- **UPDATED** GET /api/v1/org/{orgId} response — followerCount, isFollowing
- **UPDATED** GET /api/v1/org/list response — followerCount per item
- **UPDATED** GET /api/v1/org/{orgId}/dashboard response — followerCount KPI
- **UPDATED** GET /api/v1/feed response — isFollowing per post

---

### v4.6 — Applied ✅ (2026-07-12)

All changes below are reflected in all 4 v4.6 documents.

- `Users.ProfileVerificationLkpId` column + FK → LookupValues
- `PROFILE_VERIFICATION_STATUS` LookupType + 3 values (PENDING, VERIFIED, NEEDS_UPDATE)
- `SuperAdmin_Org_GetList` updated — adds `orgType` response field
- `SuperAdmin_Org_GetDetail` updated — adds `memberCount` (APPROVED members) response field
- 11 new SPs: `SuperAdmin_Org_GetStatusHistory`, `SuperAdmin_User_GetList`, `SuperAdmin_User_GetFullProfile`, `SuperAdmin_User_GetDocuments`, `SuperAdmin_UserDocument_Verify`, `SuperAdmin_User_VerifyProfile`, `SuperAdmin_User_RequestUpdate`, `SuperAdmin_User_Suspend`, `SuperAdmin_User_Reactivate`, `SuperAdmin_Dashboard_GetKpis`, `SuperAdmin_Org_GetRecent`
- 10 new API endpoints in API_Documentation_v4.6.docx and Postman v4.6
- C# fixes: `SuperAdminDal.cs` `Get<bool?>()` / `Get<int?>()` (CS0019 fix); BCrypt.Net-Next 4.0.3 → 4.2.0 (NU1605 fix)

---

### Pending — Email OTP (code-only, no DB change, docs not yet updated)

- `IEmailService` (new interface): `NGOConnect.Core/Interfaces/IEmailService.cs` — `SendOtpAsync(email, otpCode, expiryMinutes)`
- `SmtpEmailService` (new class): `NGOConnect.Infrastructure/Services/SmtpEmailService.cs` — MailKit SMTP, reads `Email:*` from IConfiguration, HTML email template
- `Infrastructure.csproj`: added `MailKit 4.7.1.1`
- `appsettings.json`: added `Email` section — `SmtpHost: smtp.hostinger.com`, port 587 STARTTLS, `FromAddress: no-reply@ripplehub.app`, `FromName: NGO Connect`
- `appsettings.Development.json`: added `Email:SmtpUsername: contact@ripplehub.app` + `Email:SmtpPassword` placeholder (gitignored)
- Hostinger alias rule: authenticate with `contact@ripplehub.app` (main mailbox), send FROM `no-reply@ripplehub.app` (alias) — MailKit supports this natively
- `AuthDal.cs`: injected `IEmailService`; removed hardcoded `otp = "123456"`; fixed `ExpiresInSeconds` bug (`Convert.ToInt32(otp)` → `expiryMinutes * 60`); email/mobile detection + `_email.SendOtpAsync()` for email; SMS logs warning (not yet implemented)
- `ServiceCollectionExtensions.cs`: `AddEmailService()` → `SmtpEmailService` as singleton
- `Program.cs`: wired `builder.Services.AddEmailService()`
- HTML template: blue header (`#1a56db`), monospace OTP box, expiry + security notes, RippleHub footer
- **Railway env vars to set**: `Email__SmtpUsername = contact@ripplehub.app` · `Email__SmtpPassword = <password>`
- **Docs to update on next version**: internal change only — no endpoint or DB change
- `UserDal.cs`: injected `IEmailService`; `SendContactOtpAsync` now calls `_email.SendOtpAsync()` when `request.Type == "EMAIL"` (Edit Profile email OTP delivery); SMS still logs warning only
- **Frontend note**: "Email Login will be available soon" is a frontend-only guard — backend already fully supports email login via `Auth_SendOTP` + `Auth_VerifyOTP`. Mobile team should remove the client-side restriction.

---

### Pending — SP Fixes (patch applied, setup SQL + docs not yet updated)

- `SuperAdmin_User_GetList`: `JOIN OrgMembers` → `LEFT JOIN` + `LEFT JOIN LookupValues sv` on status + `HAVING` clause. Now shows: (1) new users with no org connection, (2) approved members only. Pending membership users excluded. OrgNames shows APPROVED orgs only. JoinedAt falls back to `u.CreatedAt` for new users. Patch addendum added to `NGOConnect_Patch_v4.6.sql` (2026-07-12). **Needs: setup SQL + Database_Documentation update on next version.**

---

### Pending — C# Endpoints for v4.6 SPs (SPs exist in DB, C# not yet built)

When these are built, append to this section immediately and apply to all 4 docs on next "update documents".

#### Member Admin endpoints (`/superadmin/members/*`)
**⚠️ OPEN QUESTION (unresolved):** `AuthDal` does NOT check `Users.IsActive` on login. So `SuperAdmin_User_Suspend` blocks existing sessions (revokes refresh tokens) but a suspended user can still start a brand-new login. Fixing this requires editing existing `AuthDal.cs`. **Get explicit user sign-off before touching AuthDal.**

Build needed:
- `ISuperAdminDal` + `SuperAdminDal`: add 9 methods (`GetMembersAsync`, `GetMemberProfileAsync`, `GetMemberDocumentsAsync`, `VerifyMemberDocumentAsync`, `VerifyMemberProfileAsync`, `RequestMemberUpdateAsync`, `SuspendMemberAsync`, `ReactivateMemberAsync`)
- `SuperAdminController`: add 9 endpoints (`GET /members`, `GET /members/{userId}`, `GET /members/{userId}/documents`, `PUT /members/documents/verify`, `PUT /members/{userId}/verify-profile`, `PUT /members/request-update`, `PUT /members/{userId}/suspend`, `PUT /members/{userId}/reactivate`)

#### Dashboard endpoint (`GET /superadmin/dashboard`)
Build needed:
- `ISuperAdminDal` + `SuperAdminDal`: `GetDashboardAsync()` — calls `SuperAdmin_Dashboard_GetKpis` + `SuperAdmin_Org_GetRecent(10)`
- `SuperAdminController`: `GET /superadmin/dashboard`

#### CORS — Production origin
- Once Railway/Vercel/Netlify prod URL is confirmed, add to `appsettings.json` Cors:AllowedOrigins
- Then update `API_Documentation_v4.7.docx` with the CORS note

---

### Outstanding — Future Sessions (backend bugs / features, no work yet)

**Community Module (Phase 2 — after Railway community patch is confirmed working):**
- `Community_CreatePost` SP: Add optional params `p_IsPinned`, `p_NotifyAll`, `p_AllowBestAnswer`, `p_EventReference`, `p_WhatChanged` — Phase 2 feature expansion
- `Community_CreatePoll` SP: Add optional params `p_IsMultiChoice`, `p_AudienceLkpId`
- New endpoint: `PATCH /community/post/{id}/pin` — not yet built
- New endpoint: `DELETE /community/post/{id}` — not yet built

**Other bugs:**
- `Post_Report` SP: looks up `ORG_STATUS` instead of `REPORT_STATUS` — copy-paste bug, fix in a future session

---

**Mobile — Notification History screen + unread badge (2026-07-17)**

_No SQL or C# changes — all SPs and endpoints were already built. Mobile-only changes:_

- `App/src/types/api.types.ts` — `Notification` interface field names corrected to match actual SP output: `notificationType` → `notifType`, `referenceId` → `refId`, `referenceType` → `refType`; added `readAt?: string`; `isRead` typed as `number` (MySQL returns 0/1, not boolean)
- `App/src/api/notification.api.ts` — `getUnreadCount` response type corrected: `{count: number}` → `{unreadCount: number}` (matches SP column `UnreadCount`)
- `App/src/screens/home/NotificationsScreen.tsx` — Full rewrite. Features: paginated list (30/page), pull-to-refresh, load-more on scroll, per-type emoji icon + colour, read/unread visual state (bold title + tinted row background + coloured dot), tap → navigate to relevant screen (mirrors `resolveScreen` in RootNavigator) + optimistic mark-as-read, "Mark all read" header button, empty state
- `App/src/screens/home/HomeScreen.tsx` — Added `notificationApi` import, `useFocusEffect` import, `unreadCount` state. `useFocusEffect` calls `getUnreadCount` on every screen focus. Bell icon now shows a red badge overlay (`unreadCount > 0`) capped at 99+. Tapping bell sets count to 0 optimistically before navigating to `Notifications` screen.

---

**FCM Push Notifications — Full Implementation (2026-07-17)**

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`** + patch file `NGOConnect_Patch_FCM_Notifications.sql`:
- Fixed `Notification_Create` SP: uses `NotifType`/`RefId`/`RefType` (was `NotificationTypeLkpId`/`EntityId`/`EntityType`)
- Fixed `Notification_GetByUser` SP: removed `IsDeleted` (column doesn't exist), fixed column names
- Fixed `Notification_GetUnreadCount` SP: removed `IsDeleted = 0` condition
- Fixed `Donation_ConfirmPayment` SP: column names `Amount`→`DonationAmount`, `StatusLkpId`→`PayStatusLkpId`; now returns `DonorUserId`, `OrgId`, `CampaignId`
- Modified `Application_Apply` SP: now returns `OrgId` in result row
- Modified `Application_Review` SP: now returns `ApplicantUserId`, `ProjectId` in result row
- Modified `Org_ReviewMembership` SP: now returns `ApplicantUserId`, `OrgId` in result row
- Modified `Sos_ApproveResponder` SP: now returns `ResponderUserId` in result row
- Added 6 new token-fetch SPs: `Notification_GetTokenByUserId`, `Notification_GetTokensByOrgId`, `Notification_GetAdminTokensByOrgId`, `Notification_GetTokensByProjectId`, `Notification_GetTokensBySosIncidentId`, `Notification_SaveDeviceToken`
- **Patch file must be run on Railway staging + production**

**API — C# changes:**
- `NGOConnect.Infrastructure.csproj`: added `FirebaseAdmin v3.1.0` NuGet
- New: `NGOConnect.Core/Interfaces/IFCMService.cs` — `SendAsync` + `SendMulticastAsync`
- New: `NGOConnect.Infrastructure/Services/FCMService.cs` — singleton, reads `Firebase__CredentialsJson` env var
- Extended `INotificationDal` + `NotificationDal`: added `CreateAsync`, 5 `GetTokensBy*Async` methods
- `ServiceCollectionExtensions.cs`: registered `IFCMService` as singleton
- `ApplicationDal`: wired `NEW_APPLICATION` (→ org admins), `APPLICATION_APPROVED`/`REJECTED` (→ user)
- `OrgDal`: wired `MEMBERSHIP_REQUEST` (→ admins), `MEMBERSHIP_APPROVED`/`REJECTED`/`MEMBER_REMOVED` (→ user)
- `SosDal`: wired `SOS_TRIGGERED` (→ org), `SOS_RESPONDER_APPROVED` (→ responder), `SOS_RESOLVED` (→ all responders)
- `DonationDal`: wired `DONATION_CONFIRMED` (→ donor), `DONATION_RECEIVED_ADMIN` (→ org admins)
- `CommunityDal`: wired `COMMUNITY_POST` (→ org members), `NEW_POLL` (→ org members)
- `BadgeDal`: wired `BADGE_AWARDED` (→ user)
- `SkillRatingDal`: wired `SKILL_RATING` (→ rated user)
- `SuperAdminDal`: wired `ORG_APPROVED`/`ORG_REJECTED`/`ORG_SUSPENDED` (→ org admins), `PROFILE_VERIFIED`/`ACCOUNT_SUSPENDED` (→ user)
- New: `NotificationController POST /api/v1/notifications/send-test` — fires FCM to a specific token (QA tool)
- New model: `SendTestNotificationRequest`

**New API endpoint:**
- `POST /api/v1/notifications/send-test` �
**FCM Triggers — 15 missing v1.0 triggers wired** (2026-07-17)
(Patch file: `NGOConnect_Patch_FCM_SPOutputs.sql` — apply to Railway staging + production before this build)

**SQL — `NGOConnect_Complete_Setup_v4.8.sql`**
- `Org_UpdateMemberRole` SP: success SELECT now returns `UserId` column (subquery from OrgMembers)
- `Attendance_ExcuseNoShow` SP: pre-reads `UserId + ProjectId` from ProjectAttendance+ProjectSessions, returns both in success SELECT
- `Project_CheckIn` SP: success SELECT now returns `ProjectId` (subquery from ProjectSessions)
- `Project_ManualAttendance` SP: success SELECT now returns `v_UserId AS UserId, v_ProjectId AS ProjectId`
- `Withdrawal_AdminReview` SP: added `DECLARE v_OrgId`; SELECT now reads `OrgId` from WithdrawalRequests; returns `v_OrgId AS OrgId` in success SELECT
- `Sos_Respond` SP: added `DECLARE v_VictimUserId`; reads victim UserId from SosIncidents; returns `v_VictimUserId AS VictimUserId` in success SELECT

**C# — `NGOConnect.Infrastructure/DAL/WithdrawalDal.cs`**
- Constructor: now injects `INotificationDal` + `IFCMService`
- `AdminReviewAsync`: reads `OrgId` from result row; fires `FireAdminNotifAsync` for APPROVED (#16) and REJECTED (#17)
- Added `FireAdminNotifAsync` helper (calls `GetAdminTokensByOrgIdAsync` + `SendMulticastAsync`)

**C# — `NGOConnect.Infrastructure/DAL/ProjectDal.cs`**
- Constructor: now injects `INotificationDal` + `IFCMService`
- `CreateAsync`: fires `FireOrgNotifAsync` → `NEW_PROJECT` to all org members (excludes creator) (#27)
- `CheckInAsync`: reads `ProjectId` from result row; fires `FireUserNotifAsync` → `QR_CHECKIN` (#21)
- `CompleteAsync`: fires `FireProjectNotifAsync(ATTENDED)` → `PROJECT_COMPLETED` (#20)
- `CancelAsync`: fires `FireProjectNotifAsync(APPROVED)` → `PROJECT_CANCELLED` (#19)
- `ManualAttendanceAsync`: reads `UserId + ProjectId` from result row; fires `FireUserNotifAsync` → `MANUAL_ATTENDANCE` (#22)
- Added `FireUserNotifAsync`, `FireOrgNotifAsync`, `FireProjectNotifAsync` helpers

**C# — `NGOConnect.Infrastructure/DAL/OrgDal.cs`**
- `ExcuseNoShowAsync`: reads `UserId + ProjectId` from result row; fires `FireUserNotifAsync` → `NO_SHOW_EXCUSED` (#24)
- `UpdateMemberRoleAsync`: reads `UserId` from result row; fires `FireUserNotifAsync` → `MEMBER_ROLE_CHANGED` (#26)

**C# — `NGOConnect.Infrastructure/DAL/SuperAdminDal.cs`**
- `VerifyOrgProfileAsync`: fires `FireOrgAdminNotifAsync` → `ORG_PROFILE_VERIFIED` (#10) or `ORG_PROFILE_REJECTED` (#11)
- `ReactivateOrgAsync`: fires `FireOrgAdminNotifAsync` → `ORG_REACTIVATED` (#31)
- `RequestMemberUpdateAsync`: fires `FireUserNotifAsync` → `PROFILE_UPDATE_REQUIRED` (#33)
- `ReactivateMemberAsync`: fires `FireUserNotifAsync` → `ACCOUNT_REACTIVATED` (#35)

**C# — `NGOConnect.Infrastructure/DAL/SosDal.cs`**
- `RespondAsync`: reads `VictimUserId` from result row; fires `FireUserNotifAsync` → `SOS_RESPONDER_INCOMING` to SOS victim (#36)

Also created: `NGOConnect_Patch_UserDeviceTokens.sql` — run this FIRST before FCM_SPOutputs patch
- Creates `UserDeviceTokens` table (`IF NOT EXISTS`) + re-applies `Notification_SaveDeviceToken` SP

---

### Session: AWS SES Email Integration (2026-07-19)

**C# — `NGOConnect.Infrastructure/Services/AwsSesEmailService.cs`** (2026-07-19) — NEW FILE
- Implements `IEmailService` using `AWSSDK.SimpleEmailV2` SDK
- Reuses existing `AWS:Region`, `AWS:AccessKeyId`, `AWS:SecretAccessKey` config (same as S3 — no separate SMTP credentials needed)
- IAM user (`ripplehub-s3-service`) must have `ses:SendEmail` permission added
- Sending domain `ripplehub.app` must be verified in AWS SES console
- HTML email template identical to `SmtpEmailService`
- Logs `[INF] OTP email sent via AWS SES` on success

**C# — `NGOConnect.Infrastructure/NGOConnect.Infrastructure.csproj`** (2026-07-19)
- Added `AWSSDK.SimpleEmailV2 v3.7.400.76`

**C# — `NGOConnect.API/Extensions/ServiceCollectionExtensions.cs`** (2026-07-19)
- `AddEmailService()` now accepts `IConfiguration config` parameter
- Reads `EmailProvider` config key: `"awsses"` → registers `AwsSesEmailService`; anything else → `SmtpEmailService`
- Logs which provider is active at startup

**C# — `NGOConnect.API/Program.cs`** (2026-07-19)
- `AddEmailService()` call updated to pass `builder.Configuration`

**C# — `NGOConnect.API/appsettings.json`** (2026-07-19)
- Added `"EmailProvider": "smtp"` (default — local dev stays on SMTP)

**C# — `NGOConnect.Infrastructure/Services/SmtpEmailService.cs`** (2026-07-19)
- Added `client.Timeout = 8_000` — caps SMTP socket hang at 8 seconds (Hostinger blocks Railway IPs at TCP level; without this the default 2-minute hang was causing slow OTP responses on staging)

**Railway staging — env vars to add:**
- `EmailProvider = awsses`
- `AWS__AccessKeyId` = (already set for S3)
- `AWS__SecretAccessKey` = (already set for S3)

**AWS Console — one-time setup required before deploy:**
1. SES → Verified Identities → verify domain `ripplehub.app` (add DKIM DNS records in Hostinger DNS)
2. IAM → user `ripplehub-s3-service` → attach inline policy adding `ses:SendEmail` on `*`
3. SES → Account Dashboard → Request Production Access (to send to any recipient, not just verified addresses)

---

### Session: Rejected Org Resubmit Flow (2026-07-19)

**DB — `User_GetMyOrgs` SP** (patch file: `NGOConnect_Patch_UserGetMyOrgs_RejectionReason.sql`)
- Added `o.RejectionReason` to first SELECT (approved-member branch)
- Added `NULL AS RejectionReason` to second SELECT (pending join-request branch) — UNION column count must match
- 🟡 PENDING: apply patch to local DB + Railway staging

**C# — `NGOConnect.Infrastructure/DAL/OrgDal.cs`**
- `ResubmitAsync` — already implemented (no change needed)

**C# — `NGOConnect.API/Controllers/OrgController.cs`**
- `PUT /org/{orgId}/resubmit` endpoint — already exists (no change needed)

**Mobile — `App/NGOConnectApp/src/api/org.api.ts`**
- `orgApi.resubmit()` type signature expanded from 6 fields to all 16 fields (`category`, `contactPerson`, `vision`, `logoUrl`, `addressLine1`, `addressLine2`, `pincode`, `city`, `state`, `country` added)

**Mobile — `App/NGOConnectApp/src/screens/ngo/MyOrgsScreen.tsx`**
- `RejectedOrgCard` — 3 fixes:
  1. Logo: now shows `org.logoUrl` as `<Image>` if present, falls back to colour-initial avatar (was always showing initials)
  2. Rejection reason: changed `org.lastRejectionReason` → `(org as any).rejectionReason` (DynamicRow camelCases the SP column `RejectionReason`)
  3. Fix & Resubmit button: now navigates to `CreateOrg` with `{ mode: 'resubmit', orgId, prefill: org }` instead of calling `orgApi.resubmit()` directly (org must be reviewed + edited before resubmitting)
- Removed unused `Alert`, `orgApi` imports and `submitting` state from `RejectedOrgCard`

**Mobile — `App/NGOConnectApp/src/screens/ngo/CreateOrgScreen.tsx`**
- Added resubmit mode triggered by route params `{ mode: 'resubmit', orgId }`
- On mount (resubmit mode): calls `orgApi.getProfile(orgId)` and pre-fills all form fields
- `categoryLkpId` resolved by matching `org.category` (ValueCode) against loaded `categories` array
- Header title changes to "Edit & Resubmit" in resubmit mode
- Submit button text changes to "Resubmit for Review" in resubmit mode
- Loading spinner shown while org profile is fetching
- `handleResubmit()` function added: uploads any new logo/docs, calls `orgApi.resubmit()` with all 16 fields, navigates to `MyOrgs` on success
- In resubmit mode, submit button calls `handleResubmit` instead of `handleSubmit`

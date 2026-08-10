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
| `NGOConnect_Complete_Setup_v5.0.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v5.0.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v5.0.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v5.0.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

### v5.0 Release — ALL patches applied to Railway staging 2026-08-05

| File | What it covers | Status |
|---|---|---|
| `NGOConnect_Patch_InviteListAndPending_v4.9.sql` | Org_Invite_GetHistory: history list SP; Org_Invite_GetPendingForUser: UserId match fix | ✅ Railway applied |
| `NGOConnect_Patch_InviteAcceptDirectJoin_v4.9.sql` | Org_Invite_Accept: direct OrgMembers INSERT (skip OrgMembershipRequests approval step) | ✅ Railway applied |
| `NGOConnect_Patch_InviteNotifications_v4.9.sql` | Invite notification SPs | ✅ Railway applied |
| `NGOConnect_Patch_UrlShareToken_v4.9.sql` | Settings INSERT: SECURITY/URL_SHARE_SECRET_KEY for AES-256-GCM share URL encryption. ⚠️ Replace placeholder with `openssl rand -hex 32` output before running | ✅ Railway applied |
| `NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql` | 6 new tables (UserCommunicationPreferences, Campaigns, CampaignChannels, CampaignAudienceRules, CampaignRecipients, CampaignQueueJobs); 2 new Users indexes; MKTG_CAMPAIGN_TYPE/PRIORITY/STATUS/CHANNEL lookups; COMMUNICATION Settings group; 20 new SPs | ✅ Railway applied |
| `NGOConnect_Patch_MarketingCommunicationCenter_DeliveryAck.sql` | CampaignRecipient_AckDelivered + Campaign_GetRecipientList SPs; SentCount/DeliveredCount split in Campaign_GetList/GetHistoryDetail/Communication_GetDashboardStats | ✅ Railway applied |
| `NGOConnect_Patch_ImpactSummary.sql` | User_GetImpactSummary (7 result sets) SP | ✅ Railway applied |
| `NGOConnect_Patch_BadgeAward_AwardedCodes.sql` | UserBadge_Award: duplicate guard, BadgeName+UserId in result; Application_GetByProject: AwardedBadgeCodes column | ✅ Railway applied |
| `NGOConnect_Patch_UserBadges_SchemaFix.sql` | UserBadges table schema rebuild (BadgeLkpId FK, AwardedByOrgId, ProjectId); User_GetBadges SP rewrite | ✅ Railway applied |
| `NGOConnect_Patch_CertificateVerifyToken.sql` | Certificate_GetDataById SP; IUrlTokenService wired for CERT entityType | ✅ Railway applied |
| `NGOConnect_Patch_ExcludeExpiredProjects.sql` | Project_List: ACTIVE+UPCOMING whitelist for public browse; approved-orgs-only filter | ✅ Railway applied |

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

**Certificate verify page — height-reporting ratchet bug (2026-08-07)**
- Website-only, no SP/API/DB changes.
- `Website/src/assets/certificate-template.html` → `reportHeight()`: was measuring `document.body.scrollHeight`, but body has `min-height: 100vh` and inside an iframe `100vh` == the iframe's own current CSS height — so the reported height could only ratchet upward, never shrink back down once the iframe grew to its 900px default. Left a permanent gap between the certificate card and the buttons below it whenever the real certificate was shorter than 900px. Fixed by measuring the `.certificate` element's own `getBoundingClientRect().height` (+ body padding) instead.
- `Documents/ripplehub_volunteer_certificate_template.html` (master copy) has no height-reporting code at all — that logic is served-copy-only (parent/iframe glue), so nothing to sync there.
- No documents to update (template is a design artefact, not tracked in DB/API docs).

**Browser tab favicon — regenerated then reverted (2026-08-07)**
- Website-only, no SP/API/DB changes.
- `public/favicon-32x32.png` + `public/favicon.ico` regenerated from a transparent-background RippleHub logo (user-reported dark-square favicon in the browser tab), then reverted back to the original "Logo updated" version (`git checkout 1b38bd2`) after the user said the new one didn't look good. Net effect: no change from before this session — flagging only so a future session doesn't rediscover/redo this.
- No documents to update.

**Visibility & Audience enforcement — SP + DAL fix (2026-08-07)**
- `NGOConnect_Complete_Setup_v5.0.sql` → `Post_GetFeed`: added `LEFT JOIN LookupValues lv_vis` + visibility filter in both main SELECT WHERE and TotalCount WHERE; added `lv_vis.ValueCode` to GROUP BY.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Feed_GetPersonalized`: same `lv_vis` JOIN + visibility AND clause in inner WHERE; added `lv_vis.ValueCode` to GROUP BY.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Community_GetFeed`: added audience AND clause (using already-joined `av`) in main WHERE + TotalCount WHERE (with `av2` join).
- `NGOConnect_Complete_Setup_v5.0.sql` → `Community_CreatePost`: failure and success SELECTs both now return `AudienceCode`; success row adds subquery `(SELECT lv.ValueCode FROM LookupValues lv WHERE lv.LookupValueId = p_AudienceLkpId LIMIT 1)`.
- `NGOConnect.Infrastructure/DAL/CommunityDal.cs` → `CreatePostAsync`: reads `AudienceCode` from SP result; branches notification fan-out — `ADMINS_ONLY` calls `GetAdminsWithTokensAsync` (with manual author-exclusion), all others call `GetMembersWithTokensAsync`.
- Patch file: `Documents/NGOConnect_Patch_VisibilityAudienceFilter.sql`
- **API Documentation** (`API_Documentation_v4.6.docx`): no endpoint signature changes — internal SP/DAL change only.
- **Database Documentation** (`Database_Documentation_v4.6.md`): note visibility enforcement in `Post_GetFeed`, `Feed_GetPersonalized`, `Community_GetFeed` SP descriptions; note `AudienceCode` added to `Community_CreatePost` result row.

**Project_Create SP — duplicate project prevention (2026-08-07)**
- Backend-only, no mobile/API contract change (SP returns IsSuccess=0 + message, DAL surfaces it as an Alert already).
- `NGOConnect_Complete_Setup_v5.0.sql` → `Project_Create`: added two duplicate guards before INSERT:
  1. Same OrgId + same ProjectName (LOWER+TRIM, IsDeleted=0) → "A project with this title already exists…"
  2. Same OrgId + same Category + same date range (OneTimeDate / RecurStart+RecurEnd / FlexFromDate+FlexToDate per schedule type) + same SessionStartTime + same SessionEndTime → "A project in this category is already scheduled for the same date and time…"
- Patch file: `Documents/NGOConnect_Patch_ProjectDuplicateCheck.sql`
- **Database Documentation**: note duplicate-check logic in `Project_Create` SP description.

**Create Project wizard — Date and Time now mandatory for all schedule types (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- `screens/admin/CreateProjectScreen.tsx` → `validate()` (step 2): added `startTime` and `endTime` checks for ONE_TIME, RECURRING, and FLEXIBLE schedule types — each fires its own Alert before returning false.
- `renderStep2()` — ONE_TIME: "Start Time" → "Start Time *", "End Time" → "End Time *"; RECURRING: same label update; FLEXIBLE: added Start Time * + End Time * time-picker row + duration badge (was missing entirely).
- No documents to update (UI-only change, no API contract change).

**Mobile — "Apply for Selected Sessions" shown on completed/cancelled/expired projects (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- Root cause: neither `screens/volunteer/ProjectDetailScreen.tsx` (the app-wide `ProjectDetail` stack route) nor the separate local `ProjectDetailModal` component inside `screens/ngo/NgoProfileScreen.tsx` (used by the NGO profile's Projects/Volunteer tabs — a different code path, easy to miss) checked project status before showing the Apply button.
- Fix (both places): added `isClosed = ['COMPLETED','CANCELLED','EXPIRED'].includes(project.statusCode) || isProjectExpired(project)` — gates the footer to show "Applications Closed" instead of the Apply button. Reuses the existing `isProjectExpired` helper from `utils/dateUtils.ts` (same one `AllOpportunitiesScreen`/`AdminProjectsScreen` already use) since projects can stay `statusCode = 'ACTIVE'` past their end date — nothing auto-transitions status to `COMPLETED`.
- `screens/projects/ProjectDetailScreen.tsx` has the same unguarded button text but is dead code (not imported/wired into any navigator) — left untouched.
- No documents to update.

**Self-attendance for OPEN_SIGNUP projects (2026-08-07)**
- NEW SP: `Project_SelfCheckIn(p_ProjectId, p_UserId)` — volunteer marks own attendance without QR scan. Validates: project is OPEN_SIGNUP, user has APPROVED application, today is a valid session day for the schedule type, current IST time is within [sessionStart - QR_BUFFER_MINUTES, sessionEnd]. Auto-creates a `ProjectSessions` row for today if none exists (same pattern as `Project_ManualAttendance`). Inserts into `ProjectAttendance` with ATTENDED status.
- `NGOConnect_Complete_Setup_v5.0.sql` → SP appended.
- NEW `NGOConnect.Core/Interfaces/IProjectDal.cs` → `SelfCheckInAsync(int projectId, int userId)` added.
- NEW `NGOConnect.Infrastructure/DAL/ProjectDal.cs` → `SelfCheckInAsync` calls `Project_SelfCheckIn`; fires `SELF_CHECKIN` push notification on success.
- NEW `NGOConnect.API/Controllers/ProjectController.cs` → `POST {projectId}/self-checkin` endpoint (Authorize).
- NEW `App/NGOConnectApp/src/api/project.api.ts` → `selfCheckIn(projectId)` method.
- `App/NGOConnectApp/src/screens/profile/ImpactScreen.tsx` → `UpcomingCard` now accepts `onSelfCheckIn` prop; when `!app.requiresApproval && !app.isCheckedIn` shows "✅ Mark My Attendance" button instead of QR scan; `handleSelfCheckIn` handler added.
- Patch file: `Documents/NGOConnect_Patch_SelfCheckIn.sql`
- **API Documentation**: NEW endpoint `POST /project/{projectId}/self-checkin` — no request body; returns `ApiResponse` with IsSuccess + Message.
- **Database Documentation**: Add `Project_SelfCheckIn` SP description with parameters and validation logic.
- **Postman Collection**: Add `POST self-checkin` request under Project folder.

**Project_SelfCheckIn SP — SessionStatusLkpId bug fix (2026-08-07)**
- `NGOConnect_Complete_Setup_v5.0.sql` → `Project_SelfCheckIn`: `ProjectSessions` INSERT was missing `SessionStatusLkpId` (NOT NULL, no default) causing MySQL error on first use. Added `DECLARE v_StatusLkpId INT UNSIGNED DEFAULT NULL` and a lookup (`SESSION_STATUS / UPCOMING`) before the INSERT — identical pattern to `Project_ManualAttendance`.
- `Documents/NGOConnect_Patch_SelfCheckIn.sql` → same fix applied to the patch file.
- **Database Documentation**: Update `Project_SelfCheckIn` SP description to reflect the corrected INSERT.

**ParticipantsScreen — skill ratings persistence + certificate lock (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- `App/NGOConnectApp/src/screens/admin/ParticipantsScreen.tsx`:
  1. **Ratings not persisting on re-visit**: `skillRatings` and `submittedRatings` were reset to `{}` on every mount. Fix: in `load()`, after apps resolve, call `projectApi.getSkillRatings(projectId, a.userId)` for each ATTENDED app in parallel; pre-populate `skillRatings` (projectSkillId → rating) and set `submittedRatings[appId] = true` for any app that already has ratings (`rating > 0`). SP `Project_GetSkillRatings` returns all project skills with existing rating (0 if not yet rated).
  2. **Stars + Save button not locked when `hasCertificate`**: Added `|| hasCertificate` to `disabled` condition on star `TouchableOpacity`; changed Save button guard from `!submittedRatings` to `!submittedRatings && !hasCertificate`; added "🔒 Locked — certificate issued" message when `!submittedRatings && hasCertificate`.
  3. **Badge buttons not locked when `hasCertificate`**: Added `|| hasCertificate` to `disabled` on badge `TouchableOpacity`.
- No documents to update.

**Admin ProjectDetailScreen — QR Attendance section hidden for OPEN_SIGNUP projects (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- `App/NGOConnectApp/src/screens/admin/AdminProjectDetailScreen.tsx`: QR Attendance card was already hidden for read-only (completed/cancelled) projects. Added second condition: also hidden when `project?.joinTypeCode?.toUpperCase() === 'OPEN_SIGNUP'`. These projects use volunteer self-check-in — no QR is needed or generated.
- No documents to update.

**ProjectDetailModal + MyProjectsScreen — QR button shown for OPEN_SIGNUP projects (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- `App/NGOConnectApp/src/screens/profile/ProjectDetailModal.tsx`: added `onSelfCheckIn?: () => void` to Props; CTA section now branches on `app.isCheckedIn` → "Attendance Marked" badge (no button), `app.requiresApproval` → QR button (existing), else → "Mark My Attendance" button (calls `onSelfCheckIn`). Previously showed QR button unconditionally for all upcoming/active APPROVED projects.
- `App/NGOConnectApp/src/screens/profile/ImpactScreen.tsx`: passes `onSelfCheckIn={() => handleSelfCheckIn(detailApp)}` to `ProjectDetailModal`.
- `App/NGOConnectApp/src/screens/volunteer/MyProjectsScreen.tsx`: added `projectApi` import; added `handleSelfCheckIn(app)` handler (calls `projectApi.selfCheckIn`, shows Alert, refreshes list); passes `onSelfCheckIn` to `ProjectDetailModal`.
- No documents to update.

**Project expiry — timezone fix + time picker 24-hour fix (2026-08-07)**
- Mobile-only, no SP/API/DB changes.
- `App/NGOConnectApp/src/utils/dateUtils.ts` → `isProjectExpired`: `sessionEndTime` is stored in IST (not UTC); was using `Z` suffix (`new Date(\`..T..Z\`)`) which shifted the expiry 5.5 hours late. Changed to `+05:30` suffix (`new Date(\`..T..+05:30\`)`). Also corrected the JSDoc comment (removed "stored as UTC" — was wrong) and changed the default fallback from `'18:29:59'` (UTC 23:59 IST) to `'23:59:59'` (IST end of day directly).
- `App/NGOConnectApp/src/screens/admin/CreateProjectScreen.tsx` → Both `DateTimePicker` instances (Android `display="default"` and iOS `display="spinner"`): added `is24Hour={pickerMode === 'time'}` to switch the time picker to 24-hour format. Prevents the AM/PM confusion where selecting "12:00" on the clock could silently save as midnight (00:00) instead of noon (12:00).
- No documents to update (mobile-only, no API contract change).

---

**Resend email provider added (2026-08-05)**
- NEW `NGOConnect.Infrastructure/Services/ResendEmailService.cs` — implements `IEmailService` via Resend HTTPS API (not SMTP; Railway-compatible)
- `SmtpEmailService.cs` — added `internal static` HTML builder methods (`BuildOtpHtmlInternal`, `BuildInviteHtmlInternal`, `BuildSupportHtmlInternal`) so both services share the same email templates
- `ServiceCollectionExtensions.AddEmailService()` — added third provider case: `"resend"` → `AddHttpClient<IEmailService, ResendEmailService>()`
- `appsettings.json` — added `Resend:ApiKey` (empty, secret), updated `EmailProvider` comment to list smtp/resend/awsses, added `Email:SupportAddress` field, updated `Email:FromName` to "RippleHub"
- `appsettings.Development.json` — added `Resend:ApiKey` placeholder, `EmailProvider` set back to `"smtp"` for local dev
- **Railway staging action required**: set `EmailProvider = resend` + `Resend__ApiKey = <key>` as env vars; remove `EmailProvider = smtp`
- **Documents to update**: API_Documentation (no new endpoints — internal infra change only); no DB/SP changes

**Like/Comment Notifications — post author alert (2026-08-06)**
- **SPs changed** (4) — all in `NGOConnect_Complete_Setup_v5.0.sql`, patch file `Documents/patch_like_comment_notifications.sql`:
  - `Post_Like` — now returns `PostAuthorUserId` + `ActorName` (actor's full name) in SELECT result
  - `Post_AddComment` — now returns `PostAuthorUserId` + `ActorName` in success SELECT result; also added `DECLARE v_AuthorUserId` to capture post owner's UserId
  - `Community_LikePost` — now returns `PostAuthorUserId` + `ActorName` alongside existing `IsLiked` + `LikeCount`
  - `Community_AddComment` — now returns `PostAuthorUserId` + `ActorName` alongside existing `CommunityCommentId`
- **DAL changed** (2):
  - `NGOConnect.Infrastructure/DAL/PostDal.cs` → `LikeAsync`: fires `_notif.CreateAsync` + `_fcm.SendAsync` to post author (notifType `POST_LIKED`, refId = postId) when author ≠ liker
  - `NGOConnect.Infrastructure/DAL/PostDal.cs` → `AddCommentAsync`: fires `POST_COMMENTED` notification to post author when author ≠ commenter
  - `NGOConnect.Infrastructure/DAL/CommunityDal.cs` → `LikePostAsync`: fires `COMMUNITY_POST_LIKED` notification only when `IsLiked = 1` (new like, not unlike) and author ≠ liker
  - `NGOConnect.Infrastructure/DAL/CommunityDal.cs` → `AddCommentAsync`: fires `COMMUNITY_POST_COMMENTED` notification to community post author when author ≠ commenter
- **Mobile changed** (4 files):
  - `RootNavigator.tsx` → `resolveScreen`: added cases for `POST_LIKED`/`POST_COMMENTED` → `{ screen: 'Home', params: { focusPostId: refId } }`; `COMMUNITY_POST_LIKED`/`COMMUNITY_POST_COMMENTED` → `{ screen: 'Community', params: { focusCommunityPostId: refId } }`
  - `NotificationsScreen.tsx` → `notifMeta`: added ❤️/💬 emoji+color for 4 new types; `resolveScreen`: same new cases as RootNavigator
  - `HomeScreen.tsx`: added `focusPostId` route param support, `flatListRef`, `focusedPostId` state, `scrollToIndex` effect, primary-border highlight on focused post
  - `CommunityScreen.tsx`: added `focusCommunityPostId` route param support, `flatListRef`, `focusedCommunityPostId` state, `scrollToIndex` effect, primary-border highlight on focused post
- **Patch file to apply to Railway**: `Documents/patch_like_comment_notifications.sql`
- **Documents to update when "update documents" is called**:
  - `NGOConnect_Complete_Setup_v5.0.sql` ✅ already updated (4 SPs fixed in-place)
  - `Database_Documentation_v5.0.md` → update `Post_Like`, `Post_AddComment`, `Community_LikePost`, `Community_AddComment` SP result columns

**HoursLogged backfill — QR / self-check-in volunteers (2026-08-07)**
- Root cause: `Project_CheckIn` and `Project_SelfCheckIn` insert into `ProjectAttendance` without `HoursLogged` (NULL). `Project_Complete` skips already-ATTENDED volunteers (NOT EXISTS guard), so QR/self-check-in volunteers never get hours calculated. Impact screen showed "—" for completed projects.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Project_Complete`: added step 8 after the main ATTENDED INSERT — UPDATE to backfill `HoursLogged` for already-ATTENDED rows where `HoursLogged IS NULL`. Formula: `GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, att.CheckInTime, LEAST(NOW(), CONVERT_TZ(TIMESTAMP(ps.SessionDate, ps.EndTime), '+05:30', '+00:00'))) / 60.0, 2), 0.50)`. `CheckInTime` is UTC (stored as `NOW()`); session `EndTime` is IST (entered by admin) → converted to UTC via `CONVERT_TZ`.
- NEW patch file: `Documents/NGOConnect_Patch_HoursLogged.sql` — Part A: updated `Project_Complete` SP; Part B: one-time backfill UPDATE for existing records already in DB.
- `App/NGOConnectApp/src/screens/profile/ImpactScreen.tsx` → changed `app.hoursLogged ? ...` to `(app.hoursLogged ?? 0) > 0 ? ...` (explicit guard against falsy 0).
- `App/NGOConnectApp/src/screens/volunteer/MyProjectsScreen.tsx` → same guard fix on `item.hoursLogged`.
- **Database Documentation**: Update `Project_Complete` SP description — add step 8 (backfill HoursLogged for QR/self-check-in attendees).
- **Apply to Railway**: Run `NGOConnect_Patch_HoursLogged.sql` (Part A updates the SP; Part B one-time backfill fixes existing NULL records).

**FCMService — Firebase:CredentialsFilePath support added (2026-08-08)**
- `NGOConnect.Infrastructure/Services/FCMService.cs`: added `ResolveCredentialJson(IConfiguration)` private method. Credentials now resolved in priority order:
  1. `Firebase:CredentialsFilePath` — if the value is an existing file path on disk, reads the file (production VPS: `/etc/ripplehub/firebase.json`). If the file does not exist (e.g. Railway storing the full JSON in this var), the value is used as raw inline JSON.
  2. `Firebase:CredentialsJson` — legacy inline JSON fallback (unchanged).
- **Railway action**: rename env var `Firebase__CredentialsFilePath` → keep as-is (value = full JSON string). Code now handles it correctly without needing a rename.
- **Production server**: no change needed — `Firebase__CredentialsFilePath=/etc/ripplehub/firebase.json` is already correct and will now be read from file.
- No SP/DB/API changes.

**Feed Seen-Post Tracking — Feed_GetPersonalized + Feed_BulkMarkViewed (2026-08-09)**
- Goal: stop repeating posts the user has already scrolled past; keep feed fresh.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Feed_GetPersonalized`:
  - New param `p_SeenExpiryDays INT` (NULL guard: defaults to 30 if not supplied).
  - Outer WHERE gains seen filter: `NOT EXISTS` on `FeedInteractions` WHERE `InteractionType = 'VIEW'` and `CreatedAt >= DATE_SUB(NOW(), INTERVAL p_SeenExpiryDays DAY)`. Emergency posts (`IsEmergency = 1`) bypass filter unconditionally.
  - MY_ORG and FOLLOWED_ORG candidate buckets: removed 30-day time limit (now unlimited — member/followed posts always surface).
  - TRENDING: extended from 7 DAY → 30 DAY.
  - INTEREST: extended from 14 DAY → 45 DAY.
  - New PINNED_EVERGREEN bucket: pinned or evergreen posts from user's own NGOs, no time limit, LIMIT 50.
  - New DISCOVERY bucket: top public posts all time by engagement, LIMIT 100 (safety net when all personalised buckets exhausted).
- `NGOConnect_Complete_Setup_v5.0.sql` → NEW SP `Feed_BulkMarkViewed(p_UserId, p_PostIds JSON)`:
  - Bulk INSERT IGNORE into `FeedInteractions (UserId, PostId, InteractionType='VIEW')` using `JSON_TABLE` (MySQL 8.0+). Validates PostId existence against Posts table. Returns `IsSuccess + Message`.
- NEW Settings seed: `FEED / FEED_SEEN_EXPIRY_DAYS = 30` (skip if already exists via `INSERT IGNORE`).
- `NGOConnect.Core/Interfaces/IFeedDal.cs` → added `BulkMarkViewedAsync(int userId, List<int> postIds)`.
- `NGOConnect.Infrastructure/DAL/FeedDal.cs`:
  - Added `private const int SeenExpiryDays = 30`; `GetPersonalizedAsync` passes it as `p_SeenExpiryDays`.
  - Added `BulkMarkViewedAsync` — serializes postIds to JSON, calls `Feed_BulkMarkViewed`.
- `NGOConnect.API/Controllers/FeedController.cs` → NEW endpoint `POST /feed/viewed` (`[Authorize]`), request model `MarkViewedRequest { List<int> PostIds }`.
- `App/NGOConnectApp/src/api/feed.api.ts` → added `markPostsViewed(postIds: number[])` (calls `POST /feed/viewed`) + named export.
- `App/NGOConnectApp/src/screens/home/HomeScreen.tsx`:
  - Added `seenBufferRef` (Set<number> in a ref, writable by frozen callbacks).
  - `onViewableItemsChanged` ref extended to add all visible postIds into `seenBufferRef`.
  - `flushSeenBuffer` callback: drains buffer, calls `feedApi.markPostsViewed` (fire-and-forget).
  - `useEffect` wires a 10-second interval flush + unmount flush.
- Patch file: `Documents/patch_feed_seen_tracking.sql`
- Validator run: Phase 1-3 clean (Org_GetDashboard false positive unchanged, pre-existing).
- **Apply to Railway**: Run `patch_feed_seen_tracking.sql` on Railway staging → production; redeploy C# backend.
- **Database Documentation**: Add `Feed_BulkMarkViewed` SP description; update `Feed_GetPersonalized` — new param, seen filter, bucket changes, new buckets.
- **API Documentation**: NEW endpoint `POST /feed/viewed` — request `{ postIds: number[] }`, response `ApiResponse`.
- **Postman Collection**: Add `POST /feed/viewed` request with sample `{ "postIds": [1,2,3] }`.

**Feed_GetPersonalized — Members-Only post visibility fix (2026-08-07)**
- Root cause: `Feed_GetPersonalized` SP's TRENDING, RECENT, and INTEREST candidate sources selected posts from ALL orgs with no visibility filter. A Members-Only (`ORG_MEMBERS`) post created by any NGO would enter these global-discovery buckets and appear in the Home feed of users who are not members of that NGO.
- Fix — two layers of defence:
  - Layer 1 (candidate-source filtering): Added `DECLARE v_PublicLkpId INT UNSIGNED DEFAULT 0` and a single lookup of the `PUBLIC` LkpId at SP start. TRENDING, RECENT, and INTEREST candidate sources now filter `p.VisibilityLkpId = v_PublicLkpId` — ORG_MEMBERS posts never enter global-discovery buckets. MY_ORG and FOLLOWED_ORG are left unrestricted (outer WHERE handles their visibility checks).
  - Layer 2 (outer WHERE gate): Already present in the SP — retained as safety net for FOLLOWED_ORG posts with ORG_MEMBERS visibility and any future candidate sources.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Feed_GetPersonalized`: updated with both layers.
- NEW patch file: `Documents/NGOConnect_Patch_FeedVisibility.sql` — full DROP + CREATE of updated SP for Railway.
- **Database Documentation**: Update `Feed_GetPersonalized` SP description — note `v_PublicLkpId` variable, candidate-source visibility pre-filter on TRENDING/RECENT/INTEREST, and outer WHERE gate.
- **Apply to Railway**: Run `NGOConnect_Patch_FeedVisibility.sql` on Railway staging → production.

**Community_CreatePoll — audience support added (2026-08-08)**
- Root cause: `Community_CreatePoll` SP had no `p_AudienceLkpId` parameter — polls were always saved with the `ALL_MEMBERS` lookup ID regardless of user selection. Mobile was already sending `audienceLkpId` in the request body, but both the C# model (`CreatePollRequest`) and the SP silently discarded it. Notification fan-out also always notified ALL members, leaking ADMINS_ONLY poll alerts to regular members.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Community_CreatePoll`: added `p_AudienceLkpId INT UNSIGNED` parameter (NULL/0 = ALL_MEMBERS fallback). Validates supplied ID against `AUDIENCE_TYPE` LookupType; falls back to ALL_MEMBERS if not found. Returns `AudienceCode` in both success and failure result rows.
- `NGOConnect.Core/Models/Community/CommunityModels.cs` → `CreatePollRequest`: added `public int? AudienceLkpId { get; set; }`. Fixed stale comment (`POST_VISIBILITY` → `AUDIENCE_TYPE`).
- `NGOConnect.Infrastructure/DAL/CommunityDal.cs` → `CreatePollAsync`: added `p_AudienceLkpId` to SP call; reads `AudienceCode` from result; scopes notification fan-out — ADMINS_ONLY → `GetAdminsWithTokensAsync` (author excluded), all others → `GetMembersWithTokensAsync`.
- NEW patch file: `Documents/NGOConnect_Patch_CommunityPollAudience.sql` — DROP + CREATE of updated SP for Railway.
- **NOTE**: If `NGOConnect_Patch_VisibilityAudienceFilter.sql` has NOT yet been applied to Railway, apply it FIRST — it contains the `Community_GetFeed` SP with the ADMINS_ONLY read filter. Without it, polls are saved correctly but still returned to all members on read.
- **Apply to Railway**: Run `NGOConnect_Patch_CommunityPollAudience.sql` on Railway staging → production (after `NGOConnect_Patch_VisibilityAudienceFilter.sql` if not already applied).
- **Database Documentation**: Update `Community_CreatePoll` SP description — add `p_AudienceLkpId` parameter, audience resolution logic, `AudienceCode` result column.

**Post Report Notifications — SP + DAL + Email (2026-08-08)**
- `NGOConnect_Complete_Setup_v5.0.sql` → `Post_Report`: now returns three extra columns on success — `ReportCount` (total reports on this post), `PostAuthorUserId`, `OrgId`. Failure paths (unknown reason code, duplicate report) still return NULL for all three so the DAL can distinguish.
- `NGOConnect.Infrastructure/DAL/PostDal.cs` → constructor now injects `IEmailService _email` + `IConfiguration _config`. `ReportAsync` reads `ReportCount`, `PostAuthorUserId`, `OrgId` via `ColNullable<int>`. Threshold check: `reportCount == 1 || reportCount % 5 == 0`. On threshold:
  - Fires FCM + inbox notification → post author (`POST_REPORTED`, refId = postId)
  - Fires FCM + inbox notification → all org admins (`POST_REPORTED_ADMIN`, refId = postId, orgId)
  - Sends HTML email to `Email:SupportAddress` from appsettings (same address used by Help & Support feature) via `_email.SendCampaignEmailAsync`. No DB lookup — config-driven.
- Patch file: `Documents/NGOConnect_Patch_PostReportNotifications.sql` (Post_Report SP only — no new SPs)
- **Apply to Railway**: Run `NGOConnect_Patch_PostReportNotifications.sql` on Railway staging → production; redeploy C# backend to pick up PostDal constructor change.
- **Database Documentation**: Update `Post_Report` SP result columns (add ReportCount, PostAuthorUserId, OrgId).
- **API Documentation**: No endpoint change — internal DAL behaviour only.

**Review Notifications + Own-Review Pinning + 30-Day Delete Window (2026-08-09)**
- `NGOConnect_Complete_Setup_v5.0.sql` → `OrgReview_Add`: success branch now returns `ReviewId`, `ReviewerUserId`, `AuthorName`, `OrgName` — used by DAL to fire `REVIEW_NEW` fan-out to org admins.
- `NGOConnect_Complete_Setup_v5.0.sql` → `OrgReview_Delete`: added `DECLARE v_DaysOld INT DEFAULT 0`; `DATEDIFF(NOW(), CreatedAt)` captured at SELECT; new `ELSEIF v_DaysOld > 30` guard returns IsSuccess=0 + "Reviews can only be deleted within 30 days of posting." (no notifications fired). Success branch returns `ReviewerUserId`, `AuthorName`, `OverallRating`, `OrgName`, `OrgId` for `REVIEW_DELETED` fan-out.
- `NGOConnect_Complete_Setup_v5.0.sql` → `OrgReview_AddResponse`: success branch returns `ReviewerUserId`, `OrgName` for `REVIEW_RESPONSE` push.
- `NGOConnect_Complete_Setup_v5.0.sql` → `OrgReview_GetList`: `ORDER BY` updated — `(r.UserId = p_CurrentUserId) DESC` as first key (own review always pinned to top); added `CanDelete` column: `IF(r.UserId = p_CurrentUserId AND DATEDIFF(NOW(), r.CreatedAt) <= 30, 1, 0)`.
- `NGOConnect_Complete_Setup_v5.0.sql` → LookupValues: 3 new notification type seeds — `REVIEW_NEW` (9), `REVIEW_RESPONSE` (10), `REVIEW_DELETED` (11) under `NOTIFICATION_TYPE`.
- `NGOConnect.Infrastructure/DAL/OrgReviewDal.cs`: fully rewritten — constructor injects `INotificationDal` + `IFCMService`; `AddAsync` fires fire-and-forget `REVIEW_NEW` to all org admins; `DeleteAsync` fires `REVIEW_DELETED` to all org admins; `AddResponseAsync` fires `REVIEW_RESPONSE` to reviewer.
- `App/NGOConnectApp/src/api/review.api.ts` → `ReviewItem`: added `canDelete: 1 | 0` field.
- `App/NGOConnectApp/src/screens/ngo/ReviewCard.tsx`: delete button now uses `review.canDelete === 1` (was `review.isOwnReview === 1`) — button shown for own reviews but dimmed (`opacity: 0.35`, `onPress: undefined`) when `canDelete === 0` (past 30-day window).
- `App/NGOConnectApp/src/screens/home/NotificationsScreen.tsx`: added `REVIEW_NEW` (⭐), `REVIEW_RESPONSE` (💬), `REVIEW_DELETED` (🗑️) to `notifMeta()` and `resolveScreen()` (deep-links to NgoProfile Reviews tab).
- `App/NGOConnectApp/src/screens/ngo/NgoProfileScreen.tsx`: reads `initialTab` from route params; validates against `TABS` array; `useState<Tab>(initialTab)` — enables deep-link from notification tap directly to Reviews tab.
- Patch file: `Documents/patch_review_notifications.sql` — contains all 4 SP changes + 3 LookupValue inserts + SchemaVersions `v5.2` entry.
- **Apply to Railway**: Run `patch_review_notifications.sql` on local DB first, then Railway staging.
- **Database Documentation**: Update `OrgReview_Add`, `OrgReview_Delete`, `OrgReview_AddResponse`, `OrgReview_GetList` SP descriptions — new result columns, 30-day guard, CanDelete column, ORDER BY change.
- **API Documentation**: No endpoint signature changes — internal DAL behaviour only.

**v5.0 Release Summary (2026-08-05)**
All 4 documents bumped from v4.9 → v5.0. All Railway staging patches through 2026-08-05 absorbed. Documents:
- `NGOConnect_Complete_Setup_v5.0.sql` — ✅ Created (all SPs and tables current)
- `Database_Documentation_v5.0.md` — ✅ Created (62 tables, 52 LookupTypes, 204 SPs)
- `API_Documentation_v5.0.docx` — ✅ Created (all endpoints including 8 Org Invite, 13 Marketing Campaign, Share, Support, Certificate, etc.)
- `NGOConnect_Postman_Collection_v5.0.json` — ✅ Created (all requests with sample bodies, organized in 16 folders)

---

<!--
PREVIOUS PENDING ITEMS — ALL APPLIED IN v5.0
(kept below for reference; remove when next version bump occurs)

**Certificate verify link security fix — encrypted token replaces guessable CertCode** (2026-08-02)
- **Root issue**: the verify page (and every "share my certificate" button, mobile + website) built public links directly from CertCode — `CERT-{year}-{6-digit sequential counter}` via the `CERT` IdSequences row. That's a bare incrementing number, not sparse — user caught this immediately: anyone could walk `CERT-2026-000001`, `000002`, `000003`, ... off the public, `[AllowAnonymous]` `GET /certificates/{certCode}` endpoint and pull every volunteer's name, photo, org, and hours off the platform. An earlier version of this spec's own security notes incorrectly claimed the codes were "sparse" — they are not.
- **Fix reuses existing infrastructure** rather than inventing new crypto: `IUrlTokenService` (AES-256-GCM, already built for `/ngo` and `/opportunity` share links) now also handles entityType `"CERT"`.
- New SP `Certificate_GetDataById(IN p_CertificateId INT UNSIGNED)` — same shape as `Certificate_GetData`, keyed by the internal numeric `CertificateId` instead of `CertCode`. Added to `NGOConnect_Complete_Setup_v4.9.sql` and `Documents/NGOConnect_Patch_CertificateVerifyToken.sql` (new patch file, DROP+CREATE, idempotent, not yet run against any DB besides local dev).
- `ICertificateDal`/`CertificateDal`: new `GetDataByIdAsync(int certificateId)`; new private `AttachVerifyLink(DynamicRow row)` helper (constructor now also takes `IUrlTokenService`) that encrypts `certificateId` → `verifyToken` + `verifyUrl` (`https://ripplehub.app/verify/{token}`) and attaches both fields to every certificate row returned by `GetByUserAsync`, `GetDataAsync`, `GetDataByIdAsync`, and `IssueAsync`. Callers (mobile, website) must use `verifyUrl` from the API response — never build the link themselves from `certCode`.
- `CertificateController.cs`: **removed `[AllowAnonymous]` from `GET /certificates/{certCode}`** — now auth-required (mobile's own JWT already covers this; it was only ever meant for the logged-in user viewing their own cert, not public access). New `GET /certificates/verify/{token}` (`[AllowAnonymous]`) — decrypts the token, validates `entityType == "CERT"`, calls `GetDataByIdAsync`. Bad/tampered/foreign-type tokens return generic `NOT_FOUND` (no oracle leak), matching the `/ngo` and `/opportunity` share-token posture.
- `Website/src/pages/VerifyCertificatePage.jsx` + `main.jsx`: route changed from `/verify/:certCode` to `/verify/:token`; fetches `GET /certificates/verify/{token}` instead of the old certCode endpoint. Error copy no longer references the raw URL segment (it's an opaque token now, not a meaningful ID to show a human).
- `App/.../screens/common/CertificateModal.tsx`: `CertData` gained `verifyUrl`; `buildCertHtml`'s embedded "Verify at" link and the Share button both now use `d.verifyUrl`/state `verifyUrl` from the API response, not a client-built `ripplehub.app/verify/${certCode}` string. `App/.../types/api.types.ts`: `UserCert.verifyUrl?: string` added.
- `validate_sp_params.py` re-run after all changes: clean (only the pre-existing, unrelated, already-flagged `User_GetMyOrgs`/`SuspendedAt` mismatch, not touched).
- Build verified: `Website` `npm run build` clean (519 modules). No `dotnet` SDK in this sandbox — backend changes reviewed manually (DI registrations for `ICertificateDal`/`IUrlTokenService` confirmed present and lifetime-compatible: scoped depending on singleton). **Not yet build-verified with the actual .NET SDK or run against any live DB** — do that before deploying.
- **Also reported same session, separate issue**: user said `/verify/{certCode}` was loading the full marketing site instead of the certificate. Could not confirm root cause directly (sandbox network blocks `ripplehub.app`), but the local commit history shows the verify page's initial commit (`cf53a4e`) is in sync with `origin/main` — most likely explanation is Railway simply hadn't redeployed that commit yet when it was tested. Given the route has now changed again (`:certCode` → `:token`), **a fresh deploy is required regardless** — confirm Railway has picked up the latest commit before re-testing.

---

**ImpactScreen performance — single API call replaces 3 separate calls** (2026-08-02)
- Root issue: ImpactScreen called `getMyImpact()` + `getMyBadges()` + `getMyApplications()` in parallel on mount. `getMyApplications()` returned ALL applications with no server-side limit — would become O(N) data transfer as users accumulate applications. Client-side slicing to 5 items was cosmetic, not a perf fix.
- New SP `User_GetImpactSummary(p_UserId, p_AppLimit, p_BadgeLimit)` — 7 result sets: RS0-3 (Applied/Upcoming/Completed/Cancelled tabs, each LIMIT p_AppLimit, server-filtered by status/project-status), RS4 (latest p_BadgeLimit badges), RS5 (TotalApplied/Upcoming/Completed/Cancelled/Badges counts), RS6 (full impact stats, same logic as User_GetImpact).
- `NGOConnect_Patch_ImpactSummary.sql` created — apply to Railway staging → production.
- `NGOConnect_Complete_Setup_v4.9.sql` — `User_GetImpactSummary` SP added (section 3.03; `Application_GetByUser` renumbered to 3.04).
- `NGOConnect.Core/Models/User/UserModels.cs` — `ImpactSummaryModel` class added (5 DynamicRow list props + 5 total count ints + full impact stat fields).
- `NGOConnect.Core/Interfaces/IUserDal.cs` — `GetImpactSummaryAsync(int userId)` added.
- `NGOConnect.Infrastructure/DAL/UserDal.cs` — `GetImpactSummaryAsync` implemented using `FillDataSetAsync` + `DataSet.Tables[0..6]` pattern (no new BaseDal method needed — DataSet natively captures all result sets).
- `NGOConnect.API/Controllers/UserController.cs` — `GET /api/v1/user/impact-summary [Authorize]` endpoint added.
- `App/.../types/api.types.ts` — `ImpactSummary` interface added.
- `App/.../api/user.api.ts` — `getImpactSummary()` added (named export + userApi member).
- `App/.../screens/profile/ImpactScreen.tsx` — refactored: 3 state vars (`impact`, `badges`, `applications`) replaced with single `summary: ImpactSummary`; `load()` now one call; client-side tab filtering removed; tab badge counts use `tabTotals[tab]` (full DB counts) not visible list length; "View N more" uses `totalX - TAB_LIMIT`.
- Documents to update when "update documents" is called:
  - `Database_Documentation_v4.9.md` → new SP `User_GetImpactSummary` (params + 7 result sets)
  - `API_Documentation_v4.9.docx` → new endpoint `GET /user/impact-summary` (request: none; response: ImpactSummary shape)
  - `NGOConnect_Postman_Collection_v4.9.json` → add `GET /user/impact-summary` request

---

**Badge system — ImpactScreen display + notification fix + User_GetBadges SP duplicate removed** (2026-08-02)
- **Setup SQL `NGOConnect_Complete_Setup_v4.9.sql`** — removed duplicate `User_GetBadges` SP definition (old schema version at line ~6274 was overriding the correct one at line ~4609; old definition returned `ub.BadgeType` as both BadgeName and BadgeCode — a raw VARCHAR, never matched BADGE_META keys in the mobile app).
- **`NGOConnect.Infrastructure/DAL/BadgeDal.cs`** — badge award notification now carries `ProjectId` (not `UserId`) as `refId`, `EntityType = "PROJECT"`; body personalized with actual badge name from SP result row (e.g. "You've earned the Star Volunteer badge").
- **`NGOConnect.Infrastructure/DAL/SkillRatingDal.cs`** — notification title/body improved; already used `ProjectId` / `"PROJECT"` — no structural change.
- **Mobile `RootNavigator.tsx`** — `BADGE_AWARDED` and `SKILL_RATING` notification taps now navigate to `ProjectDetail` with `projectId`; fall back to Impact tab when no refId.
- **Mobile `ImpactScreen.tsx`** — `BadgeCard` fully redesigned: horizontal row layout, emoji/color from `BADGE_META` keyed on `badgeCode` (STAR_VOL ⭐ amber, TEAM_PLAYER 🤝 blue, TOP_PERFORM 🏆 purple, fallback 🏅); shows badge name, org name, project name, awarded date. Badge list changed from horizontal ScrollView to vertical View. Removed `badge.tier ?? 'Helper'` chip — `tier` was never returned by the SP.
- **`Documents/NGOConnect_Patch_UserBadges_SchemaFix.sql`** — Part 2 appended: DROP + CREATE `User_GetBadges` with correct schema (lv.ValueCode AS BadgeCode, lv.ValueName AS BadgeName, JOIN Projects for ProjectName, AwardedByOrgId for OrgName). **Apply this full patch to Railway staging → production** (Part 1 = ALTER TABLE, Part 2 = SP fix — both needed).
- Documents to update when "update documents" is called:
  - `Database_Documentation_v4.9.md` → `User_GetBadges` SP — updated return columns (BadgeName from lv.ValueName, BadgeCode from lv.ValueCode, OrgName via AwardedByOrgId, ProjectName via ProjectId JOIN)

---

**Certificate template — hide skills section when no skills rated** (2026-08-02)
- Template-only change — no SP/API/DB/C# changes.
- `Documents/ripplehub_volunteer_certificate_template.html` → `renderCertificate()` updated:
  - Added parsing for `data.skillRatings` (pipe-separated string from API, e.g. `"Communication:4.0|Leadership:3.5"`) in addition to `data.skills` array — accepts both formats.
  - `#skillChips` container now hidden (`style.display = 'none'`) when no skills have been rated. Previously the container remained visible but empty.
- No documents to update (template is a design artefact, not tracked in DB/API docs).
- **Skill rating flow clarification** (no code change needed): the admin rates skills from the ATTENDED section of `ParticipantsScreen` — each ATTENDED volunteer card shows star rating rows per project skill + "Save Ratings" button. Ratings are stored in `UserSkillRatings` and appear on the certificate via `Certificate_GetData` SP.

---

**Public certificate verify page — Website-only, built from existing spec** (2026-08-01)
- No SP/API/DB changes — `GET /api/v1/certificates/{certCode}` (`CertificateController.GetCertificate`, `[AllowAnonymous]`) already existed and already had a comment referencing this exact page (`Documents/ripplehub_verify_page_spec.md`), so this was purely a Website-side build against a spec that was already fully written.
- New route `Website/src/pages/VerifyCertificatePage.jsx` at `/verify/:certCode` (registered in `main.jsx`), unauthenticated, no app-redirect (unlike `/invite`, `/ngo`, `/opportunity` which use `useDeepLinkLanding` and auto-open the app — this page is meant to stay in-browser for any visitor).
- States implemented per spec: loading, valid (renders certificate + trust badge strip: "Issued by RippleHub / {orgName} / Verified {date}"), not found, revoked (`isDeleted = 1`), and a network-error state the spec didn't explicitly call out but `Implementation Notes` required ("Always handle network errors").
- Certificate rendering: `Documents/ripplehub_volunteer_certificate_template.html`'s `renderCertificate(data)` function is reused as-is via a same-origin `<iframe src="/certificate-template.html">` (copy placed in `Website/public/`, demo auto-render call stripped, everything else identical — **keep both files in sync if the template markup/CSS/placeholders ever change**). Iframe height is dynamic via `postMessage`, not a fixed guess. Print button calls `iframe.contentWindow.print()`, using the template's existing `@media print` styles.
- Data mapping API→template implemented exactly per the spec's table, including parsing the pipe-delimited `skillRatings` string. One field, `coordinatorName`, has no real source in the API response at all — spec's own mapping table already says to fall back to a generic label, so it's hardcoded to `"NGO Coordinator"` always, not actually mapped from any field.
- **Known limitation, same as the other landing pages**: this is a client-rendered SPA with no SSR, so the per-certificate `og:title`/`og:description` set via `document.title`/meta tag mutation in `useEffect` only helps crawlers that execute JS. WhatsApp/Facebook link previews will still show the site's generic OG image/description, not the volunteer's name — would need SSR or a prerender step to fix properly. Not attempted — flagging as a known gap, not a bug in this page.
- Spec also references `og:image` = `https://ripplehub.app/og-certificate.png` — this asset does not exist; not created, since per the SSR limitation above it wouldn't be picked up by real crawlers anyway without further work. Low priority.
- Build verified (`npm run build` — clean, 519 modules) and both `/verify/CERT-2026-000042` (SPA route) and `/certificate-template.html` (static asset) confirmed serving HTTP 200 via `vite preview`. Could not do a full headless-browser render check (no puppeteer/playwright in this sandbox) — worth a quick manual check (`npm run dev` → open `/verify/{a real certCode}`) before relying on this in production.
- Unrelated, noticed while building this: the spec's example API URL says `api.ngoconnect.in` — actual code everywhere else uses `VITE_API_BASE_URL`/the `.app` domain. Used the existing env var as the codebase already does; the `.in` in the spec doc looks like a typo, not an instruction to follow.

---

**Badge award — full wiring (admin → volunteer Impact screen + FCM notification)** (2026-08-01)

- **SP `UserBadge_Award`** — updated in setup SQL v4.9 + patch `NGOConnect_Patch_BadgeAward_AwardedCodes.sql`:
  - Added duplicate guard: prevents re-awarding same badge (same UserId + BadgeLkpId + ProjectId)
  - Added `BadgeName` (from LookupValues) + `UserId` to result set — used by OrgDal for personalised FCM notification body
- **SP `Application_GetByProject`** — updated in setup SQL v4.9 + same patch (supersedes `NGOConnect_Patch_QR_Attendance_Fixes.sql`):
  - Added `AwardedBadgeCodes` — `GROUP_CONCAT` of badge ValueCodes already awarded to each volunteer for this project
  - Already includes: `CheckedInAt` (IST ISO datetime), `Profession`, `StatusUpdatedAt`, `HoursLogged`, `IsExcused`, attendance join
- **`OrgDal.AwardBadgeAsync`** — added `FireUserNotifAsync` after successful award (personalized message with badge name + FCM push)
- **React Native `ParticipantsScreen`** — wired badge buttons to `POST /org/{orgId}/badges` API; fixed `TOP_PERFORMER` → `TOP_PERFORM` ValueCode; pre-populates awarded badges from `awardedBadgeCodes` on load; loading spinner per badge during API call
- **Patch file**: `Documents/NGOConnect_Patch_BadgeAward_AwardedCodes.sql` — apply to Railway staging then production
- Documents to update when "update documents" is called:
  - `NGOConnect_Complete_Setup_v4.9.sql` ✅ already updated
  - `Database_Documentation_v4.9.md` → `UserBadge_Award` SP signature (params unchanged, result set changed); `Application_GetByProject` SP (new `AwardedBadgeCodes` column)
  - `API_Documentation_v4.9.docx` → `POST /org/{orgId}/badges` — note that badge is only available for ATTENDED volunteers; response now returns error if already awarded
  - `NGOConnect_Postman_Collection_v4.9.json` → update `POST /org/{orgId}/badges` sample request

---

**Push notifications silently not displaying — mobile-only, root cause + fix** (2026-08-01)
- Mobile-only changes, no SP/API/DB changes.
- **Root cause**: both `notifee.displayNotification()` call sites (`index.js` background/killed handler, `RootNavigator.tsx` foreground handler) set `smallIcon: 'ic_notification'`, but that drawable did not exist anywhere in `android/app/src/main/res/` — no density folder had it. Android/notifee has no fallback to the launcher icon when a named smallIcon resource is missing; the call throws instead. The background handler's throw was swallowed by a `try/catch` that only did `console.error(...)` (invisible outside Metro/adb logcat), so **every** notification type, in every app state (foreground/background/killed), silently failed to display. This affected all notification types, not just Marketing Campaign pushes — it was surfaced via campaign testing but is a platform-wide notification bug.
- Fix: generated `ic_notification.png` (white silhouette derived from the RippleHub ribbon mark, transparent background) at all 5 Android density buckets — `drawable-mdpi` (24px) / `-hdpi` (36px) / `-xhdpi` (48px) / `-xxhdpi` (72px) / `-xxxhdpi` (96px). Corrected the inaccurate "falls back to app icon if not found" comments at both call sites. Added a `try/catch` around the foreground `displayNotification()` call (background handler already had one) so any future failure here logs visibly instead of disappearing.
- **Separate, previously-unimplemented gap fixed in the same pass**: campaign/notification images were only ever set as `largeIcon` (small thumbnail, visible collapsed and expanded) — there was no `AndroidStyle.BIGPICTURE`, so the full-width banner image on expand (the behavior originally expected) never existed in code at all, independent of the icon crash. Added `style: { type: AndroidStyle.BIGPICTURE, picture: imageUrl }` alongside `largeIcon` at both call sites (`index.js`, `RootNavigator.tsx`).
- Verified via `notificationApi.sendTest` → `NotificationController.SendTest` → `FCMService.SendAsync` (existing endpoint, `ImageUrl` param already supported end-to-end) and the FCMTestScreen dev tool — user confirmed both status-bar icon and expanded banner image now render correctly on-device.
- `src/screens/home/FCMTestScreen.tsx` (dev-only QA screen): added an Image URL field (defaults + quick-fill presets for `https://ripplehub.app/og-image.png` and a third-party `fastly.picsum.photos` URL, to test both an own-domain asset and an external CDN/redirect/query-string case) wired into the existing Send Test Push flow, plus a new "Test Image Locally (no FCM)" button that exercises smallIcon/largeIcon/BigPicture via notifee directly, bypassing the backend entirely — isolates on-device rendering bugs from backend/FCM delivery bugs.
- `src/screens/profile/ProfileScreen.tsx`: temporarily uncommented the "🧪 Test Push Notification" menu item (routes to the already-registered `FCMTest` stack screen) so the user could reach the tester from the Profile menu. **User has stated they'll ask for this to be disabled again once testing is done — remember to re-comment it out when asked, before any Play Store submission.**
- Noted but not fixed (not this bug, not mobile-code related): `https://ripplehub.app/og-image.png` — file confirmed present and committed to the Website repo (`public/og-image.png`, part of commit `1b38bd2 Logo updated`, already pushed to `origin/main`) but the user reports the live URL doesn't load. Likely a Railway deployment/serving issue, not a code issue — worth checking the Railway dashboard for that service's latest deploy and confirming static assets under `public/` are actually being served, next time Website/Railway is being worked on.
- No document updates required (mobile-only, no SP/API/DB changes) — logged here per this repo's change-tracking convention.

---

**Marketing & Communication Center — real delivery acknowledgment + per-recipient drill-down** (2026-07-24)
- **Root issue**: "Delivered" in the dashboard/list/history has only ever meant `QueueStatus IN ('SENT','DELIVERED')` — i.e. "Firebase accepted the send request" — because `CampaignDispatchService` never actually set `QueueStatus = 'DELIVERED'` anywhere. A campaign could show "completed, delivered" while the device never displayed anything. User confirmed hitting exactly this. Decision made with user: build real device-side acknowledgment rather than just relabeling.
- New SP `CampaignRecipient_AckDelivered(p_CampaignRecipientId, p_UserId)` — updates `QueueStatus` to `DELIVERED` + sets `DeliveredAt`, ownership-checked (`UserId` must match), always reports success regardless of match (best-effort beacon from an untrusted client, no oracle leak). Won't downgrade a terminal FAILED/SKIPPED row.
- New SP `Campaign_GetRecipientList` — paginated per-recipient drill-down (name, email, mobile, channel, status, timestamps, fail reason) for the Super Admin UI's new "view recipients" action.
- Split `SentCount`/`TotalSent` (accepted-by-FCM, the old — misleadingly labeled — meaning) from real `DeliveredCount`/`TotalDelivered` (ack-based) in `Campaign_GetList`, `Campaign_GetHistoryDetail`, `Communication_GetDashboardStats`. Field names kept where they already existed (`DeliveredCount`) since their meaning is now honest; `SentCount`/`TotalSent` are new additive fields.
- `IFCMService`/`FCMService`: added optional `extraData` dictionary param to `SendAsync`/`SendMulticastAsync`, merged into the FCM data payload — keeps the shared, domain-agnostic FCM service from needing to know about campaign-specific concepts. `CampaignDispatchService.SendPushAsync` passes `campaignRecipientId` via this mechanism so the device can ack against the right row.
- New endpoints: `POST /api/v1/campaign-recipients/{campaignRecipientId}/delivered` (any authenticated user — added to `CommunicationPreferencesController` since it's the existing "any authenticated user, communication-domain" home rather than a new controller for one endpoint) and `GET /api/v1/superadmin/campaigns/{campaignId}/recipients` (Super Admin, paginated).
- Patch file: `Documents/NGOConnect_Patch_MarketingCommunicationCenter_DeliveryAck.sql` — 2 new SPs + 3 modified SPs, all DROP-then-CREATE, safe to re-run, not yet applied to any DB.
- **Mobile app work needed** (separate session, not started as of this entry): call the new ack endpoint the moment the device's notifee handler actually renders a `CAMPAIGN` notification, using `data.campaignRecipientId` from the FCM payload. Instructions added as an addendum to `Documents/MarketingCommunicationCenter_MobileApp_Phase1_Prompt.md` (2026-07-30) — also documents the updated data-only Android payload shape (title/body/imageUrl/campaignRecipientId now all under `data`, not `notification`).
- `validate_sp_params.py` re-run: all new/modified SPs pass. **Unrelated pre-existing issue surfaced by the same run, not touched**: `UserDal.cs -> User_GetMyOrgs` — SP selects a `SuspendedAt` column that no `Col<T>` mapper reads (silent data loss). Predates this session's work entirely; flagging for awareness, not fixing without being asked.
- **Frontend (Website) built 2026-07-30**: `src/admin/api/communication.js` — added `getCampaignRecipients`. New page `src/admin/pages/communication/CampaignRecipientsPage.jsx` — paginated per-recipient drill-down (status tabs, name/email/mobile/channel/status/timestamps/fail reason), routed at `communication/campaigns/:campaignId/recipients` in `AdminApp.jsx`, linked from `CampaignsPage.jsx` ("Recipients" row action, shown once a campaign has recipients) and from `CampaignWizardPage.jsx`'s read-only view ("View recipients" button). `CampaignsPage.jsx` — added a `Sent` column alongside `Delivered` (both from the SentCount/DeliveredCount split above) and a `Duplicate` action for COMPLETED/CANCELLED/FAILED campaigns (pure frontend: replays create → save channels → save audience against the source campaign's detail, then opens the new draft in the wizard — no new backend endpoint). `CommunicationDashboardPage.jsx` — split the KPI row into `Sent (accepted)` vs `Delivered (confirmed)` with tooltips explaining the distinction. Build verified (`npm run build` — clean, 518 modules). Backend (steps 67-72) has no further changes this pass — only the mobile-prompt addendum above and this frontend work are new.

---

**Super admin org notifications fix — backend-only** (2026-07-25)
- No SP, table, or API endpoint changes. C# DAL fix only — no document updates required.
- Root cause: `FireOrgAdminNotifAsync` in `SuperAdminDal` was only calling `_fcm.SendMulticastAsync` (push notification only). It never called `_notif.CreateAsync`, so no row was saved to the `Notifications` table. This meant the bell icon count and notification page never showed super admin org status notifications.
- `INotificationDal.cs`: Added new method `GetAdminsWithTokensAsync(int orgId)` returning `List<(int UserId, string Token)>` — same shape as `GetMembersWithTokensAsync`. Reuses existing SP `Notification_GetAdminTokensByOrgId` (which already returns both `UserId` and `Token`).
- `NotificationDal.cs`: Implemented `GetAdminsWithTokensAsync`. Simplified `GetAdminTokensByOrgIdAsync` to delegate to it.
- `SuperAdminDal.cs`: Fixed `FireOrgAdminNotifAsync` to (1) call `GetAdminsWithTokensAsync`, (2) call `_notif.CreateAsync` per admin to persist to Notifications inbox, (3) then fire FCM push. Also improved notification bodies for `RejectOrgAsync` and `SuspendOrgAsync` to include the rejection/suspension reason if one was provided.
- No document updates required (no SP/API/DB changes).

---

**Suspended org visibility fix — mobile-only** (2026-07-25)
- Mobile-only changes, no SP/API/DB changes.
- Root cause: `approvedOrgs` filter in CommunityScreen and ExploreScreen only checked `memberStatusCode === 'APPROVED'` but not `orgStatusCode === 'APPROVED'`. A suspended org where the user is an approved member incorrectly appeared in the header org-switcher list on both screens.
- Note: `Org_List` and `Org_ListRecommended` SPs already filter by `StatusLkpId = v_ApprovedId`, so the public Explore browse was always correct server-side.
- HomeScreen was already correct (`isFullyApproved` checks both fields).
- `App/.../screens/community/CommunityScreen.tsx`: `approvedOrgs` filter — added `&& o.orgStatusCode === 'APPROVED'`; `activeOrg` derivation — added `&& o.orgStatusCode === 'APPROVED'` to both find calls; initial `setActiveOrgId` — added same check and removed `orgs[0]` fallback (a suspended-only user should get `null`, not a suspended org).
- `App/.../screens/ngo/ExploreScreen.tsx`: same three fixes as CommunityScreen.
- No document updates required (mobile-only, no SP/API changes).

---

**Saved Posts feature — full stack** (2026-07-25)
- `NGOConnect_Complete_Setup_v4.9.sql`: New SP `Post_GetSaved(p_UserId, p_PageNumber, p_PageSize)` — returns paginated saved posts for a user ordered by `ps.CreatedAt DESC` (most recently saved first). Joins PostSaves → Posts → UserProfiles → Organisations → LookupValues → PostMedia. Returns same columns as Feed_GetPersonalized (PostId, Content, AuthorName, PostTypeCode, MediaUrls, MediaTypes, IsLiked, IsSaved=1 constant, TimeAgo, SavedAt) plus `TotalCount` in second result set. Run patch against local DB and Railway staging.
- `NGOConnect.Core/Interfaces/IFeedDal.cs`: Added `GetSavedPostsAsync(int userId, int pageNumber, int pageSize)` returning `ApiResponse<PagedResult<DynamicRow>>`.
- `NGOConnect.Infrastructure/DAL/FeedDal.cs`: Implemented `GetSavedPostsAsync` using `ExecuteDynamicPagedListAsync("Post_GetSaved", ...)`.
- `NGOConnect.API/Controllers/FeedController.cs`: New `GET /api/v1/feed/saved?pageNumber=1&pageSize=30` endpoint — returns paged saved posts.
- `App/.../api/feed.api.ts`: Added `feedApi.getSavedPosts()` + named export `getSavedPosts`.
- `App/.../types/api.types.ts`: Added `savedAt?: string` to `Post` interface (ISO datetime when saved — returned by Post_GetSaved only).
- `App/.../screens/home/HomeScreen.tsx`: Fixed PostCard save toggle — was only updating local state; now calls `feedApi.savePost`/`feedApi.unsavePost` with optimistic update (reverts on error). Menu label also dynamically shows "Save" vs "Unsave".
- NEW `App/.../screens/profile/SavedPostsScreen.tsx`: Read-only saved posts list. SavedPostCard shows author avatar, org name, post type badge, content (truncatable), media thumbnail grid (up to 3 with "+N more" overlay), like/comment counts, saved date. Pull-to-refresh + infinite scroll pagination. Unsave via alert confirmation with optimistic removal + revert on API failure.
- `App/.../navigation/AppNavigator.tsx`: Imported and registered `SavedPostsScreen` as `Stack.Screen name="SavedPosts"`.
- `App/.../screens/profile/ProfileScreen.tsx`: Added `{ icon: '🔖', label: 'Saved Posts', screen: 'SavedPosts' }` to `ACTIVITY_ITEMS` (MY ACTIVITY section).
- Patch required: extract `Post_GetSaved` SP block and apply to Railway staging. No separate patch file created — use the setup SQL directly.

---

**Expired project filtering — Project_List SP** (2026-07-25)
- `NGOConnect_Complete_Setup_v4.9.sql`: `Project_List` SP updated — added `v_ExpiredLkpId` variable (resolved from `LookupValues` where `TypeCode='PROJECT_STATUS'` and `ValueCode='EXPIRED'`) and added exclusion condition to both the main SELECT WHERE and the COUNT WHERE: `AND (p_OrgId IS NOT NULL OR v_ExpiredLkpId IS NULL OR p.StatusLkpId != v_ExpiredLkpId)`. This means EXPIRED projects are excluded from the public volunteer browse (All Opportunities screen) but remain visible via admin tabs (p_OrgId is always set for admin queries, so the condition is skipped). Dynamic — resolves LkpId from LookupValues, no hardcoded IDs.
- No client-side changes needed: MyProjectsScreen and ImpactScreen already correctly route EXPIRED projects to the "Completed" tab via `isCompleted` filter, and exclude them from "Upcoming" via `isUpcoming` only matching APPROVED+UPCOMING/ACTIVE. AdminProjectsScreen always passes an explicit statusCode so EXPIRED naturally never appears in ACTIVE or UPCOMING admin tabs.
- Patch file: `Documents/NGOConnect_Patch_ExcludeExpiredProjects.sql` — run against Railway staging before next deploy.
- Document updates needed: `NGOConnect_Complete_Setup_v4.9.sql` (updated ✅), `Database_Documentation_v4.6.md` (note SP change in Project_List section).

---

**Marketing & Communication Center — Mobile Phase 1 implemented** (2026-07-22)
- Mobile-only changes (no backend changes, no SP changes, no DB changes):
  - `index.js`: background/quit `displaySystemNotification()` now sets `showTimestamp: true` + `when: Date.now()` — fixes notifications showing a date instead of precise delivery time.
  - `src/navigation/RootNavigator.tsx`: Extended `NotifData` type with `deepLink?` + `actionLabel?`; added `handleDeepLinkRef` (always-current ref pattern) so FCM/notifee tap effects can call `handleDeepLink` without stale-closure issues; foreground `notifee.displayNotification()` now sets `when: Date.now()` and reads `imageUrl` from FCM notification android payload for `largeIcon` (CAMPAIGN image support); all three tap handlers (foreground notifee press, background FCM, cold-start FCM) now check for `notifType === 'CAMPAIGN'` + `deepLink` before calling `resolveScreen`, routing through `handleDeepLink` instead; `resolveScreen()` has new `CAMPAIGN` fallback case → `{ screen: 'Notifications' }`.
  - `src/screens/home/NotificationsScreen.tsx`: Added `NEW_FEED_POST` + `CAMPAIGN` to `notifMeta()` (📝 purple, 📣 violet); added `NEW_FEED_POST` case to `resolveScreen()` → Home; CAMPAIGN deepLink handling in `onPressNotif` via `Linking.openURL()`.
  - `src/screens/home/FCMTestScreen.tsx`: Added CAMPAIGN to NOTIF_TYPES list.
  - `src/types/api.types.ts`: Added `deepLink?: string` + `actionLabel?: string` to `Notification` interface (for in-app notification list).
  - NEW `src/api/communication.api.ts`: `communicationApi.get()` + `communicationApi.update()` wired to `GET/PUT /api/v1/communication-preferences`.
  - NEW `src/screens/profile/CommunicationPreferencesScreen.tsx`: 6-toggle screen (receivePushNotifications, receivePromotionalEmails, receivePromotionalSms, receiveNgoUpdates, receiveDonationAlerts, receiveVolunteerOpportunities); graceful fallback to all-enabled defaults if API not yet deployed.
  - `src/navigation/AppNavigator.tsx`: Registered `CommunicationPreferences` screen.
  - `src/screens/profile/ProfileScreen.tsx`: Added "📣 Communication Preferences" entry to SETTINGS_ITEMS (between Notifications and Terms of Service).
- API documentation impact: `GET/PUT /api/v1/communication-preferences` endpoints already documented if the Phase 0+1 API doc was written — no new endpoints, this is the mobile client consuming them.
- No DB/SP/C# changes this session.

---

**Marketing & Communication Center — FCMService.SendMulticastAsync false-positive success bug fixed** (2026-07-24)
- Found while debugging "Test send completed" appearing with no notification actually received on device: `SendMulticastAsync` unconditionally `return true`d at the end of its try block regardless of per-token delivery outcome — it logged `FailureCount`/per-token error codes as warnings but never let a fully-failed batch (every token stale/invalid/mismatched) affect the return value. Since the Firebase Admin SDK's `SendEachForMulticastAsync` call itself doesn't throw just because individual tokens failed, this meant total delivery failure was reported as success both to `TestSendAsync` (misleading "Test send completed" message) and to the real dispatch path (`CampaignDispatchService.SendPushAsync` would mark a `CampaignRecipient` row `SENT` even when Firebase actually delivered to nobody).
- Fixed: now accumulates `SuccessCount` across every batch and returns `totalSuccess > 0`. No signature change, no DAL/SP involvement — pure logic fix inside `FCMService.cs`.
- **Still needs on-device confirmation**: rebuild + restart the API, re-run Test Send. If it now reports failure, check the Serilog log line `FCMService token[{Index}] error: {Code} — {Msg}` for the actual per-token `MessagingErrorCode` (e.g. `Unregistered`/`InvalidArgument` → stale/invalid device token, needs re-registration; a mismatch error → Firebase project credentials mismatch between this API's `Firebase:CredentialsJson` and whatever Firebase project the mobile app build is registered against).

---

**Marketing & Communication Center — push payload fix + local DB patch bugs fixed** (2026-07-24)
- **Hangfire namespace collision (build-breaking, now fixed):** `NGOConnect.API/Hangfire/HangfireDashboardAuthFilter.cs`'s namespace was `NGOConnect.API.Hangfire` — a segment literally named "Hangfire" nested under `NGOConnect.API` shadowed the real `Hangfire` NuGet package namespace for any file elsewhere under `NGOConnect.API.*` referencing bare `Hangfire.Xxx` (caused CS0234 on `Hangfire.MySql.MySqlStorage`/`Hangfire.CompatibilityLevel` in `ServiceCollectionExtensions.cs`). Renamed namespace to `NGOConnect.API.HangfireSupport`; updated the one `using` in `Program.cs`. Also added a missing `using Hangfire;` to `Program.cs` (needed for the `UseHangfireDashboard` extension method — CS1061).
- **Patch file bugs found while running `NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql` against the local dev DB, all now fixed in the patch file:**
  1. The Settings section accidentally included a full duplicate copy of every pre-v5.0 Settings row (OTP/AUTH/PAGINATION/PLATFORM/FEATURE/DONATION/UPLOAD/SOS/SMS/INVITE) — Error 1062 duplicate entry. Removed; only the new `COMMUNICATION` group insert remains.
  2. Made the whole patch genuinely idempotent (safe to run start-to-finish any number of times): the two `Users` index adds now go through a conditional helper procedure (checks `information_schema.STATISTICS`) instead of bare `ALTER TABLE`; `LookupTypes`/`LookupValues`/`Settings` inserts switched to `INSERT IGNORE`.
- **Push payload gap found and fixed:** `IFCMService.SendAsync`/`SendMulticastAsync` had no parameters for image/deep-link/action-label at all — `CampaignChannels.PushImageUrl`/`PushDeepLink`/`PushActionLabel` were being saved to the DB but never actually reaching the FCM payload, contradicting the wizard UI's own caption. Fixed additively (new optional params, existing callers unaffected):
  - `IFCMService.cs`: added optional `imageUrl`, `deepLink`, `actionLabel` params to both methods.
  - `FCMService.cs`: `BuildData()` now packs `deepLink`/`actionLabel` into the FCM data payload; `imageUrl` is set on FCM's native `Notification.ImageUrl` (renders in the system tray automatically on Android/iOS with no app code, for background/quit-state notifications — foreground-state display still depends on the app's own local-notification renderer, if any).
  - `Campaign_GetQueuedRecipients` SP: added `cc.PushActionLabel` to its SELECT (setup SQL + patch file both updated — it was already selecting `PushImageUrl`/`PushDeepLink`, just not `PushActionLabel`).
  - `CampaignDispatchService.cs`: `SendPushAsync` and `TestSendAsync`'s `ChannelPreview` class + PUSH branch now read and pass through all three fields.
  - Decision locked in with the user: "Action label" = **in-app CTA text** shown on the deep-linked screen after the user taps the notification (e.g., "Donate Now" button) — NOT a native notification action button (that would need per-platform notification-category registration, explicitly deferred as more mobile work than scoped here).
  - `python3 scripts/validate_sp_params.py` re-run after these changes — all phases pass (196 SPs, no IN-param or `Col<T>` mismatches; the new SELECT column is read via `DynamicRow.Get<string>`, not a typed mapper, so it isn't in scope for that check anyway).
- **Mobile app work still needed** (not started, no mobile repo connected this session — see chat for the full checklist given to the user): notification tap-handler needs a `notifType === "CAMPAIGN"` branch reading `refId`/`deepLink` from the FCM data payload to navigate, and reading `actionLabel` to render the in-app CTA text on the destination screen. No self-service Communication Preferences screen exists on mobile yet either (`GET`/`PUT /api/v1/communication-preferences` are live and unconsumed).

---

**Marketing & Communication Center — Phase 0 + Phase 1 IMPLEMENTED (applied to local dev DB 2026-07-24, see fixes entry above)** (2026-07-23)
- BRD: `Documents/MarketingCommunicationCenter_BRD_v1.0.docx` (not one of the 4 maintained documents, no version-bump workflow applies to it).
- Setup SQL (`NGOConnect_Complete_Setup_v4.9.sql`) updated directly, per the mandatory SP-first workflow:
  - New tables: `UserCommunicationPreferences`, `Campaigns`, `CampaignChannels`, `CampaignAudienceRules`, `CampaignRecipients` (BIGINT PK), `CampaignQueueJobs` (BIGINT PK).
  - Two new additive indexes: `Users.idx_users_lastlogin`, `Users.idx_users_createdat` (support Active/Inactive/New audience segment queries).
  - New LookupTypes: `MKTG_CAMPAIGN_TYPE`, `MKTG_CAMPAIGN_PRIORITY`, `MKTG_CAMPAIGN_STATUS`, `MKTG_CAMPAIGN_CHANNEL` (deliberately `MKTG_`-prefixed — plain `CAMPAIGN_TYPE`/`CAMPAIGN_STATUS` already exist for the donation-fundraising module, different feature, would have collided on the TypeCode unique key).
  - New Settings group `COMMUNICATION`: `CAMPAIGN_BATCH_SIZE` (500), `CAMPAIGN_RETRY_MAX_ATTEMPTS` (3), `CAMPAIGN_RETRY_BACKOFF_MINUTES` (5), `CAMPAIGN_SMS_ENABLED` (false — SMS gate), `HANGFIRE_DASHBOARD_KEY` (empty — fail-closed dashboard gate, must be set before relying on `/hangfire` outside Development).
  - 20 new SPs: `UserCommunicationPreference_Get/Update`, `Campaign_Create/Update/SetStatus`, `CampaignChannel_Save/Delete`, `CampaignAudienceRule_Save`, `Campaign_EstimateAudience`, `Campaign_ResolveRecipients`, `Campaign_GetQueuedRecipients`, `CampaignRecipient_MarkStatus/MarkEngagement`, `CampaignQueueJob_Create/MarkStatus`, `Campaign_GetList/GetById/GetHistoryDetail`, `Communication_GetDashboardStats`, `User_GetContactsByIds`.
  - Patch file (local DB only, not yet run anywhere): `Documents/NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql` — all 6 tables use `CREATE TABLE IF NOT EXISTS`; re-running is safe except the two `ALTER TABLE ... ADD INDEX` lines (harmless duplicate-key error on re-run) and the lookup/settings INSERTs (harmless duplicate-key error on re-run).
- C# additions (all additive, nothing existing touched except two interface extensions below):
  - `NGOConnect.Core/Models/Campaign/CampaignModels.cs`, `ICampaignDal`, `ICommunicationPreferenceDal`, `ICampaignDispatchService`.
  - `NGOConnect.Infrastructure/DAL/CampaignDal.cs`, `CommunicationPreferenceDal.cs`, `Services/CampaignDispatchService.cs` (the Hangfire-invoked worker — resolves audience, batches sends, respects opt-outs, marks Running/Completed/Failed).
  - `IEmailService` interface extended with `SendCampaignEmailAsync(toEmail, subject, htmlBody)` — implemented in **both** `AwsSesEmailService` and `SmtpEmailService` (existing methods untouched).
  - `NGOConnect.API/Controllers/CampaignController.cs` (`/api/v1/superadmin/campaigns/*`, `/api/v1/superadmin/communication/dashboard` — SUPER_ADMIN only) and `CommunicationPreferencesController.cs` (`/api/v1/communication-preferences` — any authenticated user).
  - `NGOConnect.API/Hangfire/HangfireDashboardAuthFilter.cs` — gates `/hangfire`; Development always allowed, otherwise requires `Settings.COMMUNICATION.HANGFIRE_DASHBOARD_KEY` via `?key=` or `X-Hangfire-Key` header, fails closed if unset.
  - `ServiceCollectionExtensions.cs`: new `AddHangfireBackgroundJobs()` extension (reuses `DefaultConnection`, Hangfire manages its own storage schema — not part of the setup SQL) + DI registrations for the three new interfaces above. `Program.cs`: calls the new extension method, adds `UseHangfireDashboard("/hangfire", ...)` to the pipeline.
  - Packages added: `Hangfire.AspNetCore` 1.8.14, `Hangfire.MySqlStorage` 2.0.3 (both in `NGOConnect.API.csproj`) — **versions unverified against live NuGet**, this sandbox has no internet access to nuget.org and no .NET SDK installed, so `dotnet restore`/`dotnet build` could not actually be run. Please run a local build before relying on this — see note below.
- Scope decisions confirmed 2026-07-23: SMS excluded from Phase 1 (Fast2SMS is test-route only; blocked at three layers — Settings toggle, `CampaignChannel_Save` SP guard, and simply never enabled in the dispatcher — until DLT/TRAI registration completes). AWS SES confirmed production-ready, so Email works from Phase 1. WhatsApp confirmed for a later stage (Phase 4) — seeded as an inert `MKTG_CAMPAIGN_CHANNEL` lookup value now so activating it later is a feature flag, not a schema change.
- Known simplifications/limitations, stated openly rather than silently shipped as "done":
  - Phase 1 supports exactly **one** audience rule per campaign (no composable combinations across rule types) — full reusable Segment Builder is Phase 2, per the BRD.
  - `Campaign_EstimateAudience` runs a live `COUNT()` when called (on wizard step transitions, not per keystroke) rather than the BRD's fuller pre-aggregated-cache proposal — a documented, deliberate simplification.
  - ~~Push notifications only send `title`+`body`~~ — **fixed 2026-07-24**, see new entry below. `PushImageUrl`/`PushDeepLink`/`PushActionLabel` are now transmitted in the FCM payload.
  - Open/click tracking has a DB hook (`CampaignRecipient_MarkEngagement`) but no HTTP tracking-pixel/redirect endpoints wired yet — natural fit alongside Phase 2's richer HTML editor.
  - ~~No Super Admin frontend UI was built this session~~ — **built 2026-07-23/24**: Dashboard, Campaigns list (doubles as history), Create/Edit wizard (4 steps) in the `Website` repo's admin panel (`src/admin/pages/communication/*`, `src/admin/api/communication.js`). Templates/Segments/Message Queue console/A-B testing UI intentionally not built — Phase 2/3 backend doesn't exist yet.
- **Not yet done, must happen before this is usable anywhere:**
  1. Run `Documents/NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql` against the local dev DB.
  2. Run `dotnet restore` + `dotnet build` locally (or in CI) — package versions and full compilation were not verifiable in this session's sandbox (no .NET SDK, no NuGet network access). `python3 scripts/validate_sp_params.py` was run and passed cleanly (196 SPs, all IN-params and `Col<T>` reads matched) — that check doesn't require the SDK and is a strong signal, but it is not a substitute for an actual build.
  3. Once building locally: exercise the endpoints via Swagger/Postman before combining into a Railway staging patch.
- **Two corrections identified for the `software-architect-skill`'s Decisions Log** (cannot edit the skill file directly — read-only cache in this session): (1) SMS provider is actually **Fast2SMS**, not "Twilio or MSG91"; (2) Cloud is actually **AWS-only** in practice (S3 + SES), not "Azure primary, AWS secondary". Gaurav should update these via Settings > Capabilities so future sessions plan against the real stack.

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

**Application Withdraw — 24-hour rule** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql):_
- NEW SP `Application_Withdraw(p_ApplicationId, p_UserId)`:
  - Validates application belongs to user and is in PENDING status
  - For ONE_TIME/RECURRING projects: blocks if `TIMESTAMPDIFF(HOUR, NOW(), start_datetime) < 24`
  - For FLEXIBLE projects: always allows withdrawal
  - On success: sets `StatusLkpId → WITHDRAWN` on `ProjectApplications`
- NEW patch file: `NGOConnect_Patch_ApplicationWithdraw_v4.9.sql`

_Backend:_
- `IApplicationDal.cs`: added `WithdrawAsync(applicationId, userId) → ApiResponse`
- `ApplicationDal.cs`: implemented `WithdrawAsync` calling `Application_Withdraw` SP
- `ApplicationController.cs`: added `DELETE /api/v1/applications/{applicationId}/withdraw` [Authorize]

_Mobile (React Native):_
- `user.api.ts`: added `withdrawApplication(applicationId)` → `DELETE /applications/{id}/withdraw`
- `ImpactScreen.tsx`: `canWithdraw(app)` helper, disabled button style, `handleWithdraw` with confirmation + local state update

---

**Help & Support — attachment upload fix** (2026-07-22)

_Backend:_
- `AwsS3BlobService.cs`: added `support-attachments` to `AllowedExtensions` (jpg/jpeg/png/pdf/mp4/mov) and `MaxFileSizePerModule` (5 MB). Root cause: upload was throwing `ArgumentException("Unknown module")` which the frontend caught as "attachment has failed".
- `LocalFileService.cs`: same addition to `AllowedExtensions` + `MaxFileSizePerModule`.
- `CloudinaryBlobService.cs`: same addition to `AllowedExtensions`.

---

**Personalised Feed — latest-first ordering** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql + NGOConnect_Patch_PersonalizedFeed.sql):_
- `Feed_GetPersonalized`: changed `ORDER BY sf.FeedScore DESC, sf.PostId DESC` → `ORDER BY sf.CreatedAt DESC, sf.PostId DESC`
- Cursor filter changed: `p_CursorScore` now carries `UNIX_TIMESTAMP(CreatedAt)` of last seen post (was FeedScore). Filter: `UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)`. FeedScore still computed and returned for analytics; emergency posts (IsEmergency=1, FeedScore +1000) still float to top naturally via CreatedAt since they are recent by definition.

_Backend:_
- `FeedDal.cs` → `ApplyDiversityEngine`: `NextCursorScore` now set to `UNIX_TIMESTAMP(lastCreatedAt)` (Unix epoch seconds as decimal) instead of reading `feedScore`. No parameter, type, or endpoint changes needed.

---

**Feed Post Notification — NEW_FEED_POST fan-out** (2026-07-22)

_Database (NGOConnect_Complete_Setup_v4.9.sql + NGOConnect_Patch_FeedPostNotification_v4.9.sql):_
- NEW SP `Post_BulkNotifyOrgMembers(p_PostId, p_OrgId, p_AuthorUserId)`: bulk-inserts one `Notifications` inbox row per approved org member (excluding author); NotifType=`NEW_FEED_POST`, RefId=PostId, RefType=`POST`. Returns `(UserId, Token, Platform, Title, Body)` rows for FCM multicast dispatch. Title = "[AuthorName] posted in [OrgName]"; Body = first 100 chars of content.

_Backend:_
- `NotificationModels.cs`: NEW class `FeedPostNotifData { Title, Body, Tokens }`
- `INotificationDal.cs`: added `BulkNotifyFeedPostAsync(postId, orgId, authorUserId) → FeedPostNotifData`
- `NotificationDal.cs`: implemented `BulkNotifyFeedPostAsync` — calls `Post_BulkNotifyOrgMembers` via `ExecuteReaderListAsync`, returns tokens + text
- `PostDal.cs`: injected `INotificationDal` + `IFCMService` into constructor; `CreateAsync` fires background Task (fire-and-forget) after post creation for org posts — calls `BulkNotifyFeedPostAsync` then `SendMulticastAsync("NEW_FEED_POST")`

_Mobile (React Native):_
- `RootNavigator.tsx` → `resolveScreen`: added `NEW_FEED_POST` → navigates to `Home` screen
- `FCMTestScreen.tsx` → `NOTIF_TYPES`: added `📝 New Feed Post (→ home)` entry with `refType: 'POST'`

---

**Full FCM + CreateAsync audit fixes — backend + mobile** (2026-07-26)
- Backend-only + mobile navigation. No SP, table, or API endpoint changes — no document version bump required.
- Root cause: multiple `FireAdminNotifAsync` / `FireOrgNotifAsync` / `FireSosResponderNotifAsync` helpers across DAL files were only calling `_fcm.SendMulticastAsync` (push notification only), never `_notif.CreateAsync`. This meant the bell icon count and notification page (inbox) never showed those notifications for recipients.
- **`INotificationDal.cs`**: Added new method `GetSosRespondersWithTokensAsync(int sosIncidentId)` returning `List<(int UserId, string Token)>` — reads from SP `Notification_GetTokensBySosIncidentId` which already returns both columns.
- **`NotificationDal.cs`**: Implemented `GetSosRespondersWithTokensAsync`. Refactored `GetTokensBySosIncidentIdAsync` to delegate to it (same pattern as `GetTokensByOrgIdAsync` → `GetMembersWithTokensAsync`).
- **`ApplicationDal.cs`**: `FireAdminNotifAsync` — now uses `GetAdminsWithTokensAsync` + `CreateAsync` per admin before FCM multicast. Removed incorrect comment "no DB record saved for admin notifications".
- **`OrgDal.cs`**: `FireAdminNotifAsync` — same fix (affects `MEMBERSHIP_REQUEST` notifications).
- **`WithdrawalDal.cs`**: `FireAdminNotifAsync` — same fix (affects `WITHDRAWAL_APPROVED`/`WITHDRAWAL_REJECTED` notifications).
- **`DonationDal.cs`**: `ConfirmPaymentAsync` admin block — now uses `GetAdminsWithTokensAsync` + `CreateAsync` per admin before FCM (affects `DONATION_RECEIVED_ADMIN` notifications).
- **`SosDal.cs`**: `FireOrgNotifAsync` — now uses `GetMembersWithTokensAsync` + `CreateAsync` per member before FCM (affects `SOS_TRIGGERED`). `FireSosResponderNotifAsync` — now uses `GetSosRespondersWithTokensAsync` + `CreateAsync` per responder before FCM (affects `SOS_RESOLVED`).
- **`RootNavigator.tsx`** → `resolveScreen`: Added all previously missing notifType cases — `NO_SHOW_EXCUSED` → `MyProjects`; `NEW_APPLICATION` → `AdminProjects` (was incorrectly `MyProjects`); `MEMBER_ROLE_CHANGED`, `ORG_REACTIVATED`, `ORG_PROFILE_VERIFIED`, `ORG_PROFILE_REJECTED`, `INVITE_ACCEPTED`, `INVITE_DECLINED` → `MyOrgs`; `SOS_RESPONDER_INCOMING` → `SosActive` with `sosIncidentId`; `DONATION_RECEIVED_ADMIN` → `AdminDonations`; `WITHDRAWAL_APPROVED`, `WITHDRAWAL_REJECTED` → `AdminWithdrawal`; `PROFILE_UPDATE_REQUIRED`, `ACCOUNT_SUSPENDED`, `ACCOUNT_REACTIVATED` → `Profile`.
- No document updates required (no SP/API/DB changes).

---

**Nearby Feed — exclude capacity-full projects** (2026-07-24)
- `NGOConnect_Complete_Setup_v4.9.sql`: `Project_GetNearbyFeed` SP updated — added capacity-full exclusion to both the main SELECT WHERE clause and the TotalCount WHERE clause:
  `AND (p.MaxVolunteers = 0 OR (SELECT COUNT(*) FROM ProjectApplications pa2 JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId WHERE pa2.ProjectId = p.ProjectId AND alv2.ValueCode = 'APPROVED' AND pa2.IsDeleted = 0) < p.MaxVolunteers)`
  `MaxVolunteers = 0` = unlimited slots (never excluded). Cancelled projects were already excluded (status filter: ACTIVE/UPCOMING only).
- Patch file: `Documents/NGOConnect_Patch_NearbyFeed_ExcludeCapacityFull.sql` — run against Railway staging before next deploy.
- Document updates needed: `Database_Documentation_v4.9.md` (update `Project_GetNearbyFeed` SP description).

---

**Nearby ordering + All Opportunities project list fixes** (2026-07-24)

_Database (`NGOConnect_Complete_Setup_v4.9.sql`):_
- `Project_List` SP: added `p_Keyword VARCHAR(200)` param — LIKE search on `ProjectName` and `Description`; public volunteer browse (p_OrgId IS NULL) now restricted to ACTIVE + UPCOMING only (whitelist replaces old EXPIRED blacklist — also hides DRAFT/CANCELLED/COMPLETED from volunteer browse); TotalCount query now has `JOIN Organisations` to match main SELECT (was missing, causing count mismatch for deleted-org projects); removed erroneous `OR ptv.ValueCode = p_Category` in category filter (ptv is schedule type, not category).
- `Project_GetNearbyFeed` SP: ORDER BY changed from 10km-band+relevance to pure distance (nearest first); `RelevanceScore` subquery removed from SELECT (was 4 correlated subqueries per row; no longer needed).
- Patch file: `Documents/NGOConnect_Patch_NearbyOrdering_ProjectListFix.sql` — run against Railway staging before next deploy.

_Backend:_
- `IProjectDal.cs`: `ListAsync` signature — added `string? keyword = null` param.
- `ProjectDal.cs`: `ListAsync` — added `keyword` param; added `_db.AddParameter(cmd, "p_Keyword", keyword)`.
- `ProjectController.cs`: `List` action — added `[FromQuery] string? keyword = null`; passes to `ListAsync`.

_Mobile (`AllOpportunitiesScreen.tsx`):_
- `fetchData`: added `TYPE_CODE_MAP` to convert `activeType` chip labels → SP codes (`Recurring`→`RECURRING`, `One-time`→`ONE_TIME`, `Flexible`→`FLEXIBLE`); passes `typeCode` to `listProjects` (was in `useCallback` deps but never sent to API — schedule type filter was silently broken).
- `useEffect`: added `activeType` to dependency array so schedule type chip changes trigger a refetch.

_Note on "missing projects":_ If projects from an org don't appear on All Opportunities, the most likely cause is `IsPublic = false` on those projects. Volunteer browse hard-filters `IsPublic = 1`. Admin can toggle this on the project visibility step (Create/Edit project wizard) or via the admin project detail screen.

---

**Project_GetNearbyFeed SP — NULL MaxVolunteers excluded all projects** (2026-07-26)
- Root cause: `MaxVolunteers INT UNSIGNED NULL` — the column is nullable. The capacity-full exclusion added in the previous session only checked `p.MaxVolunteers = 0` as the "unlimited" guard. In MySQL `NULL = 0` evaluates to UNKNOWN (not TRUE), so `FALSE OR (count < NULL)` → UNKNOWN → row excluded. Every project with `MaxVolunteers IS NULL` (no seat limit set) was silently filtered out of the nearby feed, resulting in zero results on the Home screen.
- Fix: added `p.MaxVolunteers IS NULL` as the first OR branch in both the main SELECT WHERE clause and the TotalCount WHERE clause in `Project_GetNearbyFeed`.
- Same fix applied to `NGOConnect_Patch_NearbyOrdering_ProjectListFix.sql` (both WHERE clauses) and `NGOConnect_Patch_NearbyFeed_ExcludeCapacityFull.sql`.
- No mobile or C# changes needed.

---

**Project_GetById SP — capacity-full block + application status fix** (2026-07-26)

_Database (`NGOConnect_Complete_Setup_v4.9.sql`):_
- `Project_GetById` SP: two column alias bugs fixed:
  1. `ApprovedVolunteers` → renamed to `ApprovedCount` (matches `Project_GetNearbyFeed` and the mobile `Project` TypeScript type field `approvedCount`). Bug: mobile `isFull` calculation used `project.approvedCount` which was always `undefined` → `curr = 0` → `isFull = false` → "Apply" button showed on capacity-full projects even after SP-level capacity filter on the list view excluded them.
  2. `MyApplicationStatusId` (raw `LookupValueId` integer subquery) → replaced with a JOIN returning `lv2.ValueCode AS ApplicationStatusCode` (string like `'APPROVED'`/`'PENDING'`). Bug: mobile checked `project.applicationStatusCode === 'APPROVED'` which was always `undefined` → Pending/Approved states never rendered on Project Detail screen.
- Patch file: `Documents/NGOConnect_Patch_ProjectGetById_CapacityAndStatus.sql` — run against local dev DB, Railway staging, and Railway production.
- No mobile or C# changes needed — `Project` TypeScript type already has `approvedCount?: number` and `applicationStatusCode?: string`; DynamicRow camelCase converts `ApprovedCount → approvedCount` and `ApplicationStatusCode → applicationStatusCode` automatically.

---

**Nearby Opportunities — schedule type filter chip fix** (2026-07-26)

_Mobile (`App/NGOConnectApp/src/screens/opportunities/AllOpportunitiesScreen.tsx` — the "View All" screen reached from HomeScreen Nearby Opportunities):_
- Root cause: the client-side `typeMatch` filter used a fragile chain of `includes()` string checks against `typeCode`. `Project_GetNearbyFeed` SP returns `ptv.ValueCode AS ProjectTypeCode` (→ `projectTypeCode` after DynamicRow camelCase) but the `Project` TypeScript interface only defines `scheduleType` — so `p.scheduleType` is always `undefined` and code fell back to `p.projectTypeCode`. The `includes()` checks could match incorrectly across type codes.
- Added `TYPE_CODE_MAP` constant mapping chip labels → SP ValueCodes: `One-time → ONE_TIME`, `Recurring → RECURRING`, `Flexible → FLEXIBLE`.
- Replaced `typeMatch` with exact `toUpperCase()` comparison: `typeCode === TYPE_CODE_MAP[activeType]`.
- Fixed type pill display in `OppCard`: was `item.scheduleType ?? item.projectTypeCode ?? 'One-time'` (showed raw code like `ONE_TIME`). Changed to `(item as any).projectType ?? item.scheduleType ?? 'One-time'` to use `ptv.ValueName AS ProjectType` (human-readable: 'One-time', 'Recurring', 'Flexible').
- Updated subtitle copy: "Sorted by distance · relevance" → "Sorted nearest first" (relevance scoring was removed from SP last session).
- No SP, backend, or DB changes — client-side only.

---

**Project_List SP — patch file missing p_Keyword, p_UserLat, p_UserLon** (2026-07-26)
- Root cause: `NGOConnect_Patch_NearbyOrdering_ProjectListFix.sql` contained the OLD `Project_List` SP (7 params, no `p_Keyword`/`p_UserLat`/`p_UserLon`). The setup SQL at line 6183 already had the correct 10-param version (added `p_Keyword`, `p_UserLat`, `p_UserLon`, ACTIVE+UPCOMING whitelist for public browse, keyword LIKE filter in both SELECT and COUNT WHEREs, DistanceKm Haversine in SELECT, ORDER BY distance ASC / CreatedAt DESC). MySQL error 1318 (wrong number of arguments) was silently swallowed by the DAL — old unfiltered results remained visible, making keyword search appear broken.
- Fix: replaced `Project_List` DROP+CREATE block in `NGOConnect_Patch_NearbyOrdering_ProjectListFix.sql` with the correct 10-param version matching setup SQL line 6183.
- `NGOConnect.Infrastructure/DAL/ProjectDal.cs` `ListAsync` was already correct — passes all 10 params in the right order (`p_Keyword` at line 163, `p_UserLat`/`p_UserLon` at 166-167). No C# changes needed.
- **OrgName added to keyword search** (same session): both WHERE clauses in patch and setup SQL now include `OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')`.
- **Location fields added to keyword search** (2026-07-27): keyword LIKE filter now also searches `City`, `State`, `Landmark`, `AddressLine` — so typing "Mumbai" or an address finds matching projects. Both WHERE clauses (SELECT + TotalCount) updated in setup SQL and patch file.
- New patch file: `NGOConnect_Patch_ProjectList_KeywordLocationSearch.sql` — run against Railway staging and production.

---

**Org_RequestMembership SP — re-join blocked by historical APPROVED request + duplicate key on INSERT** (2026-07-28)
- **Bug 1 — "Request already submitted":** after a member is deactivated (`OrgMembers.IsDeleted = 1`), their old `OrgMembershipRequests` row is not deleted — it stays with `IsDeleted = 0` and status `APPROVED`. The duplicate-check in `Org_RequestMembership` was `WHERE IsDeleted = 0` with no status filter, so it matched the old APPROVED row and returned "Request already submitted." Same bug affected users who were previously REJECTED — they also could never re-apply.
- **Fix 1:** Changed duplicate-check to JOIN `LookupValues`/`LookupTypes` and filter by `ValueCode = 'PENDING'` only. APPROVED and REJECTED rows no longer block re-joining.
- **Bug 2 — "An error occurred" after Fix 1:** `OrgMembershipRequests` has `UNIQUE KEY uq_memreq_org_user (OrgId, UserId, IsDeleted)`. After Fix 1 passes the duplicate-check, the plain INSERT tries to create a new row with `IsDeleted=0` — which collides with the existing APPROVED row that also has `IsDeleted=0`. MySQL throws a duplicate-key error → DAL catch block → "An error occurred."
- **Fix 2:** Replaced the plain INSERT with an UPDATE-first pattern. First tries to UPDATE the existing non-deleted row back to PENDING (re-join case). Only INSERTs if no such row exists (first-time join). Both fixes applied to `NGOConnect_Complete_Setup_v4.9.sql`.
- Patch file `NGOConnect_Patch_RejoinMembership.sql` updated to v2 with both fixes — re-apply to Railway staging and production (the original v1 patch only had Fix 1 and will cause "An error occurred" on re-join).
- No C# or mobile changes needed.

---

**Org_UpdateMemberRole SP — wrong version on Railway (Save Role fix)** (2026-07-28)
- "An error occurred" on Save Role after Save Permissions was fixed. Static analysis (validate_sp_params.py) confirmed local code is clean. Root cause: Railway still has the v4.1 version of `Org_UpdateMemberRole` using `p_RoleLkpId INT` — the DAL passes `p_RoleCode VARCHAR(50)`. MySqlConnector throws a parameter name mismatch MySqlException → caught by DAL catch block → "An error occurred."
- New patch file: `NGOConnect_Patch_UpdateMemberRole_Latest.sql` — DROP + CREATE with the latest correct version (p_RoleCode, returns UserId for FCM notification). Apply to Railway staging and production.
- No C# or mobile changes needed.

---

**Org_UpdateMemberPermissions SP — missing from Railway (Save Permissions fix)** (2026-07-28)
- Root cause of "An error occurred" on Save Permissions button: `Org_UpdateMemberPermissions` has NEVER appeared in any standalone patch file — only in complete setup SQL files. Railway staging may have a missing or outdated version if DB was not rebuilt from a recent complete setup SQL.
- `Org_UpdateMemberRole` is confirmed correct on Railway (patched twice: v4.1 → RoleCode, FCM patch → returns UserId). Save Role error is likely the same root cause (SP may be erroring internally) OR the same general DB state issue — the FCM patch file is the authoritative version.
- New patch file: `NGOConnect_Patch_MemberUpdateSPs.sql` — contains DROP+CREATE for `Org_UpdateMemberPermissions` only. Apply to Railway staging to fix the Save Permissions button. Does NOT touch `Org_UpdateMemberRole` (already correct from FCM patch).
- No C# or mobile changes — DAL params and mobile call chain are correct. SP-only fix.
- `Database_Documentation_v4.9.md`: Update `Org_UpdateMemberPermissions` SP entry to confirm it is now patched to Railway.

---

**Org_RemoveMember SP — admin check + founder protection** (2026-07-28)
- Security fix: the previous setup SQL version had **no access control** — any authenticated user could call `DELETE /api/v1/orgs/{orgId}/members/{userId}` directly and the SP would blindly soft-delete the target member. No requester role check, no founder protection.
- Additionally, `Database/04_SP_All_New_Modules.sql` had a different version of the SP using params `p_RequestedBy` + `p_OrgMemberId` which did NOT match the DAL params (`p_UserId`, `p_RemovedBy`) — parameter name mismatch would cause errors if that version was ever applied.
- **Fixed in both files**: `NGOConnect_Complete_Setup_v4.9.sql` (line ~2660) and `Database/04_SP_All_New_Modules.sql` (line ~383). Both now use matching params (`p_OrgId`, `p_UserId`, `p_RemovedBy`) and include:
  1. Requester check: `p_RemovedBy` must be ADMIN or FOUNDER of the org — returns `IsSuccess=0` with "Access denied" message if not.
  2. Target founder protection: if `p_UserId` is a FOUNDER, returns `IsSuccess=0` with "Founder cannot be removed" — blocks bypass even via direct API call.
- New patch file: `NGOConnect_Patch_OrgRemoveMember_FounderProtection.sql` — apply to Railway staging and production.
- `Database_Documentation_v4.9.md`: Update `Org_RemoveMember` SP entry — new param descriptions, add requester role check and founder protection notes.

---

**OrgDal.UpdateMemberRoleAsync — InvalidCastException on Save Role** (2026-07-29)
- C# DAL fix only. No SP, DB, or API changes — no document updates required.
- Root cause: `OrgMembers.UserId` is `INT UNSIGNED` — MySQL connector returns `UInt32`. `BaseDal.Col<int?>` uses `Convert.DefaultToType` which cannot cast `UInt32` → `Nullable<Int32>` → throws `InvalidCastException`.
- Fix: changed to `Col<uint?>` with an explicit `(int)` cast when passing to `FireUserNotifAsync`.
- File: `NGOConnect.Infrastructure/DAL/OrgDal.cs` line ~535.

---

**Expired project handling — mobile-only** (2026-07-29)
- Mobile-only changes. No SP, DB, or API changes — no document updates required.
- `App/NGOConnectApp/src/utils/dateUtils.ts`: added `isProjectExpired(p)` export — checks `oneTimeDate`, `recurEnd`, or `flexToDate` against UTC `sessionEndTime`; returns `true` if past deadline. Default `sessionEndTime = '18:29:59'` UTC (≈ 23:59 IST) when not provided.
- `App/.../screens/admin/AdminProjectsScreen.tsx`: UPCOMING projects now partitioned before filters run — expired unstarted ones injected into CANCELLED source array. Expired projects render with amber "Expired" badge and "NOT STARTED" notice in the Cancelled tab. Tab counts always use the filtered array (not raw `projects[tab]`). Import: `isProjectExpired` from `dateUtils`.
- `App/.../screens/admin/AdminProjectDetailScreen.tsx`: added `isExpiredUnstarted = project?.statusCode === 'UPCOMING' && isProjectExpired(project)`. When true: Edit button replaced with static "Expired" label; Complete/Cancel section replaced with amber info panel. Import: `isProjectExpired` from `dateUtils`.
- `App/.../screens/opportunities/AllOpportunitiesScreen.tsx` (screens/opportunities/ — the Nearby Opportunities "View All" screen): Import `isProjectExpired`; added `if (isProjectExpired(p as any)) return false;` at top of `displayed` filter.
- `App/.../screens/volunteer/AllOpportunitiesScreen.tsx` (screens/volunteer/ — the main All Opportunities screen): Import `isProjectExpired`; FlatList `data` filtered with `.filter(p => !isProjectExpired(p as any))`; `OppCard` shows amber "Deadline Passed" chip instead of Apply button when `isExpiredUnstarted`.

---

**Project_List SP — exclude projects from non-APPROVED organisations** (2026-07-29)
- `NGOConnect_Complete_Setup_v4.9.sql`: `Project_List` SP updated — added `v_ApprovedOrgLkpId` (resolved from `ORG_STATUS / APPROVED` lookup). Both the main SELECT WHERE and the TotalCount WHERE now include: `AND (p_OrgId IS NOT NULL OR o.StatusLkpId = v_ApprovedOrgLkpId)`. Admin browse (`p_OrgId IS NOT NULL`) is unaffected — admins always see their own org's projects. Public volunteer browse now silently hides projects from SUSPENDED, PENDING, or REJECTED orgs.
- New patch file: `Documents/NGOConnect_Patch_ProjectList_ApprovedOrgsOnly.sql` — run against Railway staging and production.
- Document updates needed: `Database_Documentation_v4.9.md` (update `Project_List` SP section — add `v_ApprovedOrgLkpId` variable and org status filter condition).

---

**Project_Cancel SP — missing from all setup SQLs** (2026-07-27)
- Root cause of Cancel Project button not working: `Project_Cancel` SP was never added to any version of the setup SQL (v4.0–v4.9). It only existed in `NGOConnect_Patch_Project_Cancel.sql`, which also clobbers `Project_List` with a dangerously outdated version using wrong column names — **do NOT re-run that old patch file**.
- `NGOConnect_Complete_Setup_v4.9.sql`: `Project_Cancel` SP added after `Project_Complete` — params `p_ProjectId`, `p_UserId`, `p_CancelReason`; dynamically resolves CANCELLED LkpId; guards for missing lookup and not-found project; sets `StatusLkpId`, `CancelReason`, `CancelledBy`, `CancelledAt`, `UpdatedAt`, `UpdatedBy`.
- New clean patch file: `Documents/NGOConnect_Patch_ProjectCancel_Clean.sql` — contains ONLY `Project_Cancel` SP, safe to apply. Apply to Railway staging and production.
- `Mark as Completed` button: `Project_Complete` SP was always present in every setup SQL — should work. If it also fails, verify it was applied to the current Railway DB instance.
- Document updates needed: `Database_Documentation_v4.9.md` (add `Project_Cancel` SP entry — params, return values, guards).

---

**Project_GetSessionQr SP — UTC vs IST timezone bug (QR rejected during active sessions)** (2026-07-29)
- Root cause: Railway MySQL server runs UTC. Session times (`StartTime`, `EndTime`, `SessionDate`) are stored in IST as entered by admin. The previous version of `Project_GetSessionQr` (from `NGOConnect_Patch_QR_TimeWindow_ManualAttendance.sql`) compared `NOW()` (UTC) against IST-stored DATETIME values — e.g., at 9:20 PM IST = 3:50 PM UTC, `3:50 PM UTC < 8:15 PM IST` → true → SP returned "QR not yet available" even during an active session.
- Fix: declared `v_NowIST = CONVERT_TZ(NOW(), '+00:00', '+05:30')` and used `v_NowIST` for both `v_NowIST < v_WindowStart` and `v_NowIST > v_WindowEnd` comparisons. `QrExpiresAt` intentionally kept UTC (`DATE_ADD(NOW(),...)`) — `Project_CheckIn` validates it with `NOW()` which is also UTC, so both sides are consistent — no change needed there.
- `NGOConnect_Complete_Setup_v4.9.sql`: fix already in the 3.19 section (line ~7225). No change needed to setup SQL.
- New patch file: `Documents/NGOConnect_Patch_QR_TimezoneAndDateFix.sql` — apply to Railway staging and production.
- Document updates needed: `Database_Documentation_v4.9.md` (update `Project_GetSessionQr` SP notes — add IST timezone comment).

---

**Project_GetById SP — DATE_FORMAT for date columns** (2026-07-29)
- Root cause: SP returned MySQL `DATE` columns (`OneTimeDate`, `RecurStart`, `RecurEnd`, `FlexFromDate`, `FlexToDate`) as raw values → Pomelo/C# serialised them as `DateTime` → JSON produced `"2026-07-26T00:00:00"` (with T00:00:00 suffix). The `fmtDate` utility splits on `'T'` and should handle it, but the raw ISO string was visible in the admin project detail screen.
- Fix: wrapped all five columns in `DATE_FORMAT(p.XXX, '%Y-%m-%d') AS XXX` — C# receives a plain `string`, not `DateTime` → JSON produces `"2026-07-26"` with no suffix.
- `NGOConnect_Complete_Setup_v4.9.sql`: updated (line ~2971-2977).
- Patch file: included in `Documents/NGOConnect_Patch_QR_TimezoneAndDateFix.sql` (combined with the QR timezone fix above for a single Railway deploy).
- Document updates needed: `Database_Documentation_v4.9.md` (update `Project_GetById` SP return-value column types for the 5 date fields — note they now return `VARCHAR` / date string, not `DATE`).

---

**AdminProjectDetailScreen — real QR code display** (2026-07-29)
- Mobile-only change. No SP, DB, or API changes — no document updates required.
- Root cause: QR token was displayed as an emoji placeholder (`⬛⬜⬛`/`⬜⬛⬜`/`⬛⬜⬛`) — not a real scannable QR code. Volunteers on the ImpactScreen use `react-native-vision-camera` to scan the QR; the emoji was never scannable.
- Fix: replaced emoji placeholder with `<QRCode>` component from `react-native-qrcode-svg` (v6.3.x). Renders a real 180×180 scannable QR code from the `qrToken` UUID string. Wrapped in `qrCodeWrapper` View with drop shadow for visual polish.
- `App/NGOConnectApp/package.json`: added `react-native-qrcode-svg ^6.3.0` and `react-native-svg ^15.8.0` to `dependencies`.
- `App/NGOConnectApp/src/screens/admin/AdminProjectDetailScreen.tsx`: imported `QRCode from 'react-native-qrcode-svg'`; replaced emoji block with `<QRCode value={qrToken} size={180} />` inside `qrCodeWrapper`; updated styles.
- **Action required**: run `npm install && cd ios && pod install` in the `NGOConnectApp` directory after pulling this change (two new native packages need linking).

---

**Suspended NGO visibility fix — full stack (Home / Admin / Community / Explore)** (2026-07-31)
- Root cause (multi-layer): (1) `User_GetMyOrgs` SP on Railway may be the old pre-v4.5 version that returns no `OrgStatusCode` column — all client filters silently fail. (2) `adminStore.setAdminOrgs` used `orgs[0]` as the `selectedOrg` fallback with no status check — a suspended admin org could become `selectedOrg`. (3) `AdminDashboardScreen.loadOrgs` filtered by FOUNDER/ADMIN role only, not `orgStatusCode === 'APPROVED'` — suspended orgs entered `adminOrgs` and appeared in the admin org picker. (4) `HomeScreen` had `?? orgs[0]` fallback (after `approvedOrgs[0]`) — could pick a suspended org as the active volunteer org when `approvedOrgs` was empty. (5) `CommunityScreen` and `ExploreScreen` initial `activeOrgId` read from `selectedOrg?.orgId` (the admin org, possibly suspended), and `activeOrg` derivation fell through to `?? selectedOrg` as a last resort.
- **Railway patch required**: `Documents/NGOConnect_Patch_UserGetMyOrgs_WithOrgStatus.sql` — apply to Railway staging and production. Replaces the old SP with the v4.5 version that returns `MemberStatusCode` + `OrgStatusCode` on every row. Without this patch, all client-side suspended-org guards return false.
- `App/.../store/adminStore.ts`: `setAdminOrgs` — `selectedOrg` fallback now requires `orgStatusCode === 'APPROVED'` on both the existing-org match (`find` by orgId) and the default fallback (`find` first approved); returns `null` if no approved orgs.
- `App/.../screens/admin/AdminDashboardScreen.tsx`: `loadOrgs` — filter changed to `isAdminOrg(o) && o.orgStatusCode === 'APPROVED'`; fallback `filtered = all` (which could include suspended) replaced with `filtered = all.filter(o => o.orgStatusCode === 'APPROVED')`.
- `App/.../screens/home/HomeScreen.tsx`: `chosen` fallback changed from `?? orgs[0]` to `?? null` — prevents selecting a suspended org when `approvedOrgs` is empty.
- `App/.../screens/community/CommunityScreen.tsx`: initial `activeOrgId` state no longer reads from `selectedOrg?.orgId` (admin scope — may be suspended); changed to `storeActiveOrg?.orgId ?? null`. `activeOrg` derivation: removed `?? selectedOrg` from final fallback chain.
- `App/.../screens/ngo/ExploreScreen.tsx`: same two fixes as CommunityScreen.
- No document updates required (no SP signature change, no new endpoints, no DB schema change — the patch replaces an SP that already existed under the same name).

---

**MyOrgsScreen — show suspension date/time on suspended org card + SuspendedAt pipeline** (2026-07-31)
- `Documents/NGOConnect_Complete_Setup_v4.9.sql` — `User_GetMyOrgs` SP (line ~7716): added `SuspendedAt` subquery in first UNION SELECT (approved memberships); added `NULL AS SuspendedAt` in second UNION SELECT (pending join requests).
- `Documents/NGOConnect_Patch_UserGetMyOrgs_WithOrgStatus.sql` — patch file updated with same `SuspendedAt` changes; header updated to reflect both OrgStatusCode + SuspendedAt changes. **Must apply to Railway staging + production** (supersedes any prior version of this patch).
- `NGOConnect.Core/Models/User/UserModels.cs` — `UserOrgModel`: added `public DateTime? SuspendedAt { get; set; }` — populated when `OrgStatusCode = SUSPENDED`, null otherwise.
- `NGOConnect.Infrastructure/DAL/UserDal.cs` — `GetMyOrgsAsync` mapper: added `SuspendedAt = Col<DateTime?>(r, "SuspendedAt")`.
- `App/.../types/api.types.ts` — `Organisation` interface: added `suspendedAt?: string` (ISO datetime from SP).
- `App/.../screens/ngo/MyOrgsScreen.tsx` — `SuspendedOrgCard`: parses `org.suspendedAt` into `en-IN` locale string (`DD Mon YYYY, HH:MM AM/PM`); renders "Suspended on …" below the "Suspended" pill. Added `suspendedDate` style (`fontSize: 11, color: '#EA580C', fontWeight: '500'`).
- No new endpoints. No DB schema change (reads from existing `OrgStatusHistory` table).

---

**Cancel membership request — full stack** (2026-07-31)
- `Documents/NGOConnect_Complete_Setup_v4.9.sql` — new SP `Org_CancelMembershipRequest(p_OrgId, p_UserId)`: soft-deletes the PENDING `OrgMembershipRequests` row (`IsDeleted = 1`). Returns `IsSuccess=0` if no pending request found.
- `Documents/NGOConnect_Patch_CancelMembershipRequest.sql` — Railway patch (new file). **Apply to Railway staging + production.**
- `NGOConnect.Core/Interfaces/IOrgDal.cs` — added `CancelMembershipRequestAsync(int orgId, int userId)`.
- `NGOConnect.Infrastructure/DAL/OrgDal.cs` — implemented `CancelMembershipRequestAsync` calling `Org_CancelMembershipRequest`.
- `NGOConnect.API/Controllers/OrgController.cs` — new endpoint: `DELETE /api/v1/org/{orgId}/membership-request` (Authorize).
- `App/.../api/org.api.ts` — added `cancelMembershipRequest(orgId)` (DELETE) + named export.
- `App/.../screens/ngo/MyOrgsScreen.tsx` — new `PendingRequestCard` component: shows org logo/name/requested-date + amber "Pending" pill + "Cancel Request" button. Button triggers `Alert.alert` confirmation before calling the API. On success, calls `load()` to refresh the list. Pending rows that are member-PENDING now use `PendingRequestCard`; org-PENDING rows (founder waiting for Super Admin approval) continue to use the plain `OrgCard`. Added styles: `pendingCard`, `pendingCardHeader`, `cancelRequestBtn`, `cancelRequestBtnText`.
- No DB schema change (no new tables or columns).

---

**Impact screen — ProjectsCompleted always 0 + Completed tab always empty — full fix** (2026-07-31)

Two separate root causes, one patch file fixes both.

Root cause 1 — `User_GetImpact` (old version on Railway):
- Old SP used `pa.AttendanceStatus = 'ATTENDED'` (a VARCHAR column that no longer exists on `ProjectAttendance` — replaced by `AttendStatusLkpId INT UNSIGNED FK`). Every attendance join silently returned no rows → `v_ProjCompleted = 0` always.
- Even after fixing the column bug: the query required explicit `ProjectAttendance` rows marked ATTENDED, which are only created when admin manually records per-session attendance. Admin completing a project without this step left `ProjectsCompleted = 0` even for fully approved volunteers.
- Fix: `v_ProjCompleted` now counts via `ProjectApplications` (APPROVED status) + project `StatusLkpId` IN (COMPLETED, EXPIRED). This is reliable regardless of whether admin records individual attendance.

Root cause 2 — `Application_GetByUser` (old version on Railway):
- Old SP returned only `StatusCode`, `Status`, `CreatedAt` — no `ProjectStatusCode` field.
- Mobile `isCompleted` filter: `['COMPLETED','EXPIRED'].includes(a.projectStatusCode ?? '')` → `projectStatusCode` was `undefined` → always false → Completed tab always empty.
- Fix: new SP returns `ProjectStatusCode`, `ProjectStatus`, `ScheduleTypeCode`, and all schedule fields.

Changes:
- `Documents/NGOConnect_Complete_Setup_v4.9.sql` — `User_GetImpact` (section 3.02): updated `v_ProjCompleted` block to use `ProjectApplications` JOIN instead of `ProjectAttendance` JOIN; updated header comment.
- `Documents/NGOConnect_Patch_ImpactSPs_Fix.sql` — new combined Railway patch. **Apply to Railway staging + production.**
- No C#, no API, no mobile changes needed — the issue was entirely SP-side.
- `ImpactScreen.tsx` `isCompleted` filter and `User_GetImpact` DAL mapper are both already correct; they just need the SPs to return the right data.

---

**RippleHub logo — app-wide branding** (2026-07-31)
- Mobile-only changes + email template changes. No SP, DB, or API changes — no document updates required.
- Source logo: `Documents/Logo/logo_512x512 google play.png` (512×512 RGBA PNG, dark navy background with blue/green gradient ripple mark).
- `App/NGOConnectApp/src/assets/images/logo.png` (NEW) — 512×512 copy for React Native asset bundle.
- `App/NGOConnectApp/src/assets/images/logo_180.png` (NEW) — 180×180 copy (Apple touch icon).
- `App/NGOConnectApp/ios/NGOConnectApp/Images.xcassets/RippleLogo.imageset/` (NEW) — imageset registered for iOS LaunchScreen storyboard (3x slot = logo.png 512×512).
- `App/NGOConnectApp/android/app/src/main/res/drawable/logo.png` (NEW) — 192×192 resized via PIL for Android notifee `largeIcon`.
- **LoginScreen.tsx**: replaced heart emoji placeholder with `<Image source={LOGO} style={logoImage} resizeMode="cover" />` (80×80, borderRadius 22).
- **OtpScreen.tsx**: added brand block above back button — logo (64×64, borderRadius 16) + "RippleHub" bold text.
- **InviteAcceptScreen.tsx**: logo shown inline with "Invitation" title in header; "Sent via RippleHub" strip (logo 20×20 + text) at bottom of card above CTA buttons.
- **LaunchScreen.storyboard** (iOS): removed default "NGOConnectApp" label; added UIImageView referencing RippleLogo (100×100, borderRadius 22, centred at ~42% height), "RippleHub" bold label (28pt), tagline label (14pt); background #F0F2F8.
- **index.js** + **RootNavigator.tsx**: notifee `largeIcon: 'logo'` — references `res/drawable/logo.png` by resource name; campaign notifications use FCM imageUrl if present, falls back to brand logo.
- **AwsSesEmailService.cs** + **SmtpEmailService.cs** — `BuildOtpHtml`: OTP email header updated from blue (#1a56db) plain text to dark navy (#0A1628) header with embedded base64 RippleHub logo (80×80 PNG, 8,388 bytes → 11,184 char base64 data URI) above "RippleHub" h1 and updated tagline color (#93c5fd). Same `<img>` tag with `border-radius:14px` for compatible clients; logo blends seamlessly against matching dark navy background on Outlook (no border-radius support needed).
- **Note**: Metro cache reset required after adding new image assets — run `npx react-native start --reset-cache` then rebuild.
- **Note**: iOS notifications always use the app icon in system notifications — no per-notification override possible; since the app icon was already updated to RippleHub, iOS notifications automatically show the correct logo.

---

---

**Marketing & Communication Center — Mobile App Phase 1 (Addendum)** (2026-08-01)

Backend-side delivery tracking, CAMPAIGN image + timestamp, and in-app CTA banner. No SP/DB/API contract changes.

- `App/NGOConnectApp/src/api/notification.api.ts` — new method `acknowledgeDelivery(campaignRecipientId: string)`: fires `POST /api/v1/campaign-recipients/{campaignRecipientId}/delivered` fire-and-forget. Called the moment notifee renders a CAMPAIGN notification (foreground and background/killed state).
- `App/NGOConnectApp/src/navigation/RootNavigator.tsx` — three changes:
  1. `NotifData` type: added `campaignRecipientId?: string` field.
  2. Foreground `onMessage` handler: after `notifee.displayNotification()`, calls `notificationApi.acknowledgeDelivery(data.campaignRecipientId)` for CAMPAIGN type (fire-and-forget, `.catch(() => {})`).
  3. All three tap handlers (foreground notifee press, background FCM `onNotificationOpenedApp`, cold-start `getInitialNotification`): for CAMPAIGN with no `deepLink`, spreads `{ actionLabel: data.actionLabel }` into the navigate call params so the destination screen (Notifications fallback) can render a CTA banner.
- `App/NGOConnectApp/index.js` — two changes:
  1. `displaySystemNotification(title, body, channelId, imageUrl)` now accepts `imageUrl` and uses it as `largeIcon` (falls back to `'logo'` brand icon). Previously always used brand logo even for campaign image pushes.
  2. `setBackgroundMessageHandler`: after displaying notification, calls `notificationApi.acknowledgeDelivery(data.campaignRecipientId)` for CAMPAIGN type (fire-and-forget). Added import `import { notificationApi } from './src/api/notification.api'`.
- `App/NGOConnectApp/src/screens/home/NotificationsScreen.tsx` — CTA banner: added `useRoute` import; reads `route.params?.actionLabel` on mount into `ctaLabel` state; renders a dismissible purple banner (`backgroundColor: '#7C3AED'`) showing `📣 {ctaLabel}` with a ✕ dismiss button when `ctaLabel` is set. Only shown when a CAMPAIGN notification with `actionLabel` (no `deepLink`) navigates to this screen. No changes to existing notification list behavior.
- No new endpoints, SP changes, or DB changes. All additive.

---

**Skill Rating + Certificate Flow** (2026-08-01)

DB schema fixes + new SPs + new API endpoints + React Native UI. Patch file: `patch_skill_rating_and_certificate.sql`.

**DB — Schema fixes (setup SQL + patch):**
- `UserSkillRatings` table — completely rebuilt. Old columns (`UserSkillId, RatedByUserId, SessionId, Rating TINYINT, RatedAt`) replaced with correct schema: `(SkillRatingId, UserId, OrgId, ProjectId, SkillId, Rating DECIMAL(3,2), RatedBy, Notes, CreatedAt, UpdatedAt)`. UNIQUE KEY on `(UserId, ProjectId, SkillId)` for upsert. `SkillId` references `ProjectSkills.ProjectSkillId`.
- `VolunteerCertificates` table — rebuilt with new columns: `CertCode VARCHAR(20) UNIQUE` (CERT-YYYY-NNNNNN), `OrgId` (FK Organisations), `TotalHours DECIMAL(6,2)`, `IsDeleted`. `CertificateUrl` now nullable (reserved for future PDF upload).
- `IdSequences` — added `('CERT', YEAR(CURDATE()), 0)` seed row.

**DB — New / updated SPs (setup SQL + patch):**
- `Certificate_GetByUser` — fixed; now references correct `vc.CertCode, vc.OrgId, vc.TotalHours, vc.IsDeleted` columns (old SP used non-existent columns).
- `Certificate_GetData(p_CertCode)` — NEW; returns full certificate data (volunteer, NGO, project, skills+ratings, impact score) for verify page and app. AllowAnonymous endpoint.
- `Certificate_Issue(p_ProjectId, p_UserId, p_OrgId, p_IssuedBy, p_TotalHours)` — NEW; generates CERT-YYYY-NNNNNN, inserts into `VolunteerCertificates`, returns `CertCode`.
- `Project_GetSkillRatings(p_ProjectId, p_UserId)` — NEW; returns all `ProjectSkills` for a project with the volunteer's existing rating (LEFT JOIN to `UserSkillRatings`). Used by admin skill rating UI to show already-saved stars on screen open.

**Backend C# changes:**
- `SkillModels.cs` — `AddSkillRatingRequest`: renamed `UserSkillId` → `ProjectSkillId` (clarify it's `ProjectSkills.ProjectSkillId`), `Review` → `Notes`, `Rating` type `int` → `decimal`, added `OrgId?`. Added new `IssueCertificateRequest` model `(ProjectId, UserId, OrgId, TotalHours?)`.
- `SkillRatingDal.cs` — updated params to match renamed model fields: `p_SkillId ← request.ProjectSkillId`, `p_Notes ← request.Notes`, `p_OrgId ← request.OrgId`.
- `IProjectDal.cs` — added `GetSkillsAsync(projectId)` and `GetSkillRatingsAsync(projectId, userId)`.
- `ProjectDal.cs` — implemented `GetSkillsAsync` (calls `Project_GetSkills`) and `GetSkillRatingsAsync` (calls `Project_GetSkillRatings`).
- `ICertificateDal.cs` — added `GetDataAsync(certCode)` and `IssueAsync(issuedBy, request)`.
- `CertificateDal.cs` — implemented `GetDataAsync` (calls `Certificate_GetData`) and `IssueAsync` (calls `Certificate_Issue`, returns cert data via second SP call).
- `ProjectController.cs` — new endpoints: `GET /project/{projectId}/skills`, `GET /project/{projectId}/skill-ratings/{userId}`.
- `CertificateController.cs` — new endpoints: `GET /certificates/{certCode}` (AllowAnonymous, for verify page), `POST /certificates/issue`.

**Frontend (React Native) changes:**
- `project.api.ts` — added `getSkills(projectId)`, `getSkillRatings(projectId, userId)`, `rateSkill(data)` methods + named exports.
- `ParticipantsScreen.tsx`:
  - `projectSkills` type changed from `string[]` → `{id: number, name: string}[]`.
  - Load function now calls `projectApi.getSkills(projectId)` (dedicated endpoint) instead of reading `skills` from the project get response (which never returned them).
  - `skillRatings` state key changed from skill name string to `projectSkillId` number.
  - Added `submittingRatings` and `submittedRatings` per-app state.
  - Added `handleSubmitRatings(app)` — loops through rated skills and calls `projectApi.rateSkill()` for each; marks card as submitted on success.
  - `AttendedCard` — new "Save Ratings" button appears when any star is tapped; shows spinner while saving; shows "✓ Ratings saved" confirmation; stars become non-interactive after submit.
  - New styles: `skillRatingSection`, `saveRatingsBtn`, `saveRatingsBtnText`, `ratingsSubmittedRow`, `ratingsSubmittedText`.

**New documents:**
- `Documents/patch_skill_rating_and_certificate.sql` — apply to Railway staging then production.
- `Documents/ripplehub_verify_page_spec.md` — full spec for `ripplehub.app/verify/{certCode}` web page (API contract, data mapping, page states, implementation notes).

---

**Completed/cancelled project participant screen fixes — mobile-only** (2026-08-01)
- No SP/API/DB changes. React Native mobile app only.
- Root cause (participant preview wrong): `recentApps = apps.slice(0, 3)` always showed the 3 most recently *applied* volunteers (ordered by `CreatedAt DESC`). For a COMPLETED project, these were often `APPROVED`/`PENDING` volunteers (who didn't get attendance recorded), not `ATTENDED` ones — so the preview looked wrong.
- Root cause (section labels wrong): `ParticipantsScreen` had no knowledge of project status (it wasn't passed via navigation params), so labels always read "APPROVED — UPCOMING" and "ATTENDED — LAST SESSION" / "NO SHOWS — LAST SESSION" even on fully completed projects.
- `AdminProjectDetailScreen.tsx`:
  - `recentApps` — for `isReadOnly` (COMPLETED/CANCELLED) projects, sort by status priority (`ATTENDED` first, then `NO_SHOW`, `APPROVED`, `PENDING`) before slicing to 3, so the preview shows the most relevant volunteers.
  - Both `nav.navigate('Participants', ...)` calls — now pass `projectStatus: project?.statusCode` as a third param.
- `ParticipantsScreen.tsx`:
  - Destructures new `projectStatus` param from `route.params`; derives `isCompleted`, `isCancelled`, `isReadOnly`.
  - Section labels: "APPROVED — UPCOMING" → "APPROVED — NOT MARKED (N)" when `isReadOnly`; "ATTENDED — LAST SESSION (DATE)" → "ATTENDED (N)"; "NO SHOWS — LAST SESSION" → "NO SHOWS (N)".
  - KPI strip: "Approved" label → "Not marked"; `Pending` KPI hidden entirely for read-only projects.
  - Pending applications section — hidden entirely for `isReadOnly` projects (no point approving/rejecting on a completed project).
- No document updates required for API/DB docs (mobile-only change).

---

**Project_ManualAttendance SP — auto-create session if none exists** (2026-08-01)
- Root cause: `Project_ManualAttendance` returned `'No past session found'` when admin never created a QR session before completing the project. Blocked all retroactive attendance marking on completed projects.
- Fix: If `ProjectSessions` has no row for this project, create one from `Projects.OneTimeDate` / `RecurStart` / `FlexFromDate` (in that priority), `SessionStartTime`, `SessionEndTime`, `MaxVolunteers`. Then proceed with the attendance insert as normal.
- Result: Admin can now individually mark APPROVED volunteers as ATTENDED on the completed project participants screen, even if the QR flow was never used.
- `Documents/NGOConnect_Complete_Setup_v4.9.sql` — `Project_ManualAttendance` SP updated ✅
- `Documents/patch_manual_attendance_auto_session.sql` — NEW; apply to Railway staging → production
- DB docs to update when "update documents" called: `Database_Documentation_v4.9.md` → `Project_ManualAttendance` SP description (no param change, just behavior change — auto-creates session).

---

**CRITICAL BUG FIX — UserBadges schema + 0 KPIs bug** (2026-08-01)
- Root cause: `UserBadges` table was created with OLD schema (`BadgeType VARCHAR(50) NOT NULL`, `AwardedByUserId INT UNSIGNED NOT NULL`) — missing columns `BadgeLkpId`, `AwardedBy`, `AwardedByOrgId`, `ProjectId`, `CreatedAt` that all post-badge-patch SPs reference.
- Effect: `Application_GetByProject` crashed on every call ("Unknown column 'ub.BadgeLkpId'"), causing ALL project participants to show 0 across every project tab in `AdminProjectDetailScreen` and `ParticipantsScreen`.
- Same crash affected `UserBadge_Award` (badge awarding broken) and `User_GetBadges` (Impact screen badges broken).
- Fix: `Documents/NGOConnect_Patch_UserBadges_SchemaFix.sql` — NEW; ALTER TABLE adds missing columns, relaxes NOT NULL on old columns. **Apply to Railway FIRST (before any other patch).**
- `Documents/NGOConnect_Complete_Setup_v4.9.sql` — `CREATE TABLE UserBadges` replaced with correct modern schema. Both `User_GetBadges` definitions updated to use `CreatedAt` instead of the removed `AwardedAt`.
- DB docs to update when "update documents" called: `Database_Documentation_v4.9.md` → `UserBadges` table schema (full column list updated).

---

**Certificate issuance — admin Issue Certificate button + per-project cert visibility on volunteer screens** (2026-08-02)

- **Root issue**: Certificate button on volunteer Impact/MyProjects screens was always visible, even before any cert was issued. Admin had no way to issue a cert from the ParticipantsScreen.

- **SP `Application_GetByProject`** — updated in `NGOConnect_Complete_Setup_v4.9.sql` (both definitions — initial at line ~3310 and section 3.20): added `HasCertificate` subquery:
  ```sql
  IF(EXISTS(SELECT 1 FROM VolunteerCertificates vc WHERE vc.ProjectId = pa.ProjectId AND vc.UserId = pa.UserId AND vc.IsDeleted = 0), 1, 0) AS HasCertificate
  ```
  Section 3.20 was also missing `AwardedBadgeCodes` from the prior session; that defect is fixed in this same update (both definitions now identical and correct).

- **SP `User_GetImpactSummary`** — RS2 (Completed tab) updated in `NGOConnect_Complete_Setup_v4.9.sql` to include the same `HasCertificate` subquery.

- **Patch file `Documents/NGOConnect_Patch_CertificateIssuance.sql`** — NEW; DROP+CREATE for `Application_GetByProject` (full version with AwardedBadgeCodes + HasCertificate) and `User_GetImpactSummary` (HasCertificate in RS2). Apply to Railway staging → production.

- **`App/.../types/api.types.ts`** — `hasCertificate?: number` added to `UserApplication` interface. MySQL IF() returns integer 1/0; check as `!!app.hasCertificate`.

- **`App/.../api/user.api.ts`** — `issueCertificate(data)` added to `userApi` + named export. Calls `POST /certificates/issue`.

- **`App/.../screens/admin/ParticipantsScreen.tsx`** — Issue Certificate button added to `AttendedCard`, shown only when `isCompleted` (project is COMPLETED status); button shows "✓ Certificate Issued" if already issued (`hasCertificate`), otherwise "📄 Issue Certificate". `issuedCerts` state pre-populated from `app.hasCertificate` on data load. `handleIssueCertificate` callback calls API, updates local state on success. New style constants: `issueCertBtn`, `issueCertBtnIssued`, `issueCertBtnText`, `issueCertBtnIssuedText`.

- **`App/.../screens/profile/ImpactScreen.tsx`** — `CompletedCard` cert button now only renders when `!!app.hasCertificate`. `onCertPress` prop made optional.

- **`App/.../screens/volunteer/MyProjectsScreen.tsx`** — Completed tab cert button now only renders when `!!item.hasCertificate`.

- Documents to update when "update documents" is called:
  - `Database_Documentation_v4.9.md` → `Application_GetByProject` SP (new `HasCertificate` column); `User_GetImpactSummary` RS2 (new `HasCertificate` column)
  - `API_Documentation_v4.9.docx` → `POST /certificates/issue` — note admin-only, ATTENDED volunteers on COMPLETED projects only

---

**HoursLogged + HasCertificate missing from User_GetImpactSummary RS2 and Application_GetByUser** (2026-08-02)

- **Root issue**: `hoursLogged` was not shown on Impact screen (Completed) or MyProjects screen (Completed tab). `hasCertificate` was also missing from MyProjects screen because `Application_GetByUser` had neither column.

- **SP `User_GetImpactSummary`** RS2 (Completed projects) — added `HoursLogged` subquery:
  ```sql
  COALESCE((SELECT SUM(ata2.HoursLogged) FROM ProjectAttendance ata2 JOIN ProjectSessions pss2 ON ata2.SessionId = pss2.SessionId WHERE pss2.ProjectId = p.ProjectId AND ata2.UserId = p_UserId), 0) AS HoursLogged
  ```
  Already had `HasCertificate`. Fixed in `NGOConnect_Complete_Setup_v4.9.sql`.

- **SP `Application_GetByUser`** — added both `HoursLogged` (same subquery) and `HasCertificate` (VolunteerCertificates EXISTS subquery). Fixed in `NGOConnect_Complete_Setup_v4.9.sql`.

- **Patch file `Documents/NGOConnect_Patch_HoursLogged_HasCertificate.sql`** — NEW; DROP+CREATE for both SPs. Apply to Railway staging → production.

- No C# or mobile changes needed — both fields are DynamicRow/camelCase auto-mapped; frontend already reads `hoursLogged` and `hasCertificate`.

- Documents to update when "update documents" is called:
  - `Database_Documentation_v4.9.md` → `User_GetImpactSummary` RS2 (new `HoursLogged` column); `Application_GetByUser` (new `HoursLogged` + `HasCertificate` columns)

---

**Org_GetDashboard — ActiveProjects count fix** (2026-08-08)

- **Root issue**: `ActiveProjects` KPI on the Admin Dashboard was counting only projects with `PROJECT_STATUS = ACTIVE`. Since Hangfire status auto-transition (UPCOMING → ACTIVE) is not implemented, projects remain `UPCOMING` even after their start date passes. The count was therefore lower than the real number of projects currently in play.

- **All other KPI counts audited and confirmed correct**: TotalMembers, NewMembersThisMonth, ActiveVolunteers, ActiveRatePct, VolunteerHoursMonth, PendingApplications, PendingProjectApplications, FollowerCount.

- **SP `Org_GetDashboard`** — `ActiveProjects` subquery changed from `StatusLkpId = v_ActiveProjectStatusId` (ACTIVE only) to `ValueCode IN ('ACTIVE', 'UPCOMING')` **plus** an expiry exclusion filter mirroring the mobile `isProjectExpired()` helper: projects where `OneTimeDate < CURDATE()`, `RecurEnd < CURDATE()`, or `FlexToDate < CURDATE()` are excluded (treated as cancelled). The now-unused `DECLARE v_ActiveProjectStatusId` variable removed. Fixed in `NGOConnect_Complete_Setup_v5.0.sql`.

- **Patch file `Documents/NGOConnect_Patch_DashboardActiveCounts.sql`** — NEW; full DROP+CREATE of `Org_GetDashboard`. Apply to Railway staging → production.

- No C# or mobile changes needed — SP column name `ActiveProjects` unchanged; DynamicRow maps it to `activeProjects` as before.

- Documents to update when "update documents" is called:
  - `Database_Documentation_v5.0.md` → `Org_GetDashboard` SP: note that `ActiveProjects` now counts ACTIVE + UPCOMING statuses

-->

**NGO Reviews module — v5.1 (2026-08-09)**

DB changes:
- `NGOConnect_Complete_Setup_v5.0.sql` → appended v5.1 block:
  - 3 new LookupTypes: `REVIEWER_TYPE`, `REVIEW_MEDIA_TYPE`, `REVIEW_SORT`
  - 14 new LookupValues across those 3 types
  - 4 new tables: `OrgReviews`, `OrgReviewMedia`, `OrgReviewResponses`, `OrgReviewHelpful`
  - `AvgRating` + `RatingCount` on `Organisations` now wired to OrgReview_Add / OrgReview_Delete
  - 7 new SPs: `OrgReview_Add`, `OrgReview_GetList`, `OrgReview_GetAggregate`, `OrgReview_MarkHelpful`, `OrgReview_Delete`, `OrgReview_AddResponse`, `OrgReview_Report`
  - SchemaVersions entry `v5.1`
- Standalone patch: `Documents/patch_org_reviews.sql`

Backend changes:
- `NGOConnect.Core/Models/OrgReview/OrgReviewModels.cs` — `AddReviewRequest`, `ReviewMediaItem`, `MarkHelpfulRequest`, `AddReviewResponseRequest`
- `NGOConnect.Core/Interfaces/IOrgReviewDal.cs` — 7-method interface
- `NGOConnect.Infrastructure/DAL/OrgReviewDal.cs` — full implementation
- `NGOConnect.API/Controllers/OrgReviewController.cs` — 6 endpoints under `/api/v1/orgs/{orgId}/reviews`
- `NGOConnect.API/Extensions/ServiceCollectionExtensions.cs` — `IOrgReviewDal` registered

Mobile changes:
- `App/NGOConnectApp/src/api/review.api.ts` — 7 API functions
- `App/NGOConnectApp/src/screens/ngo/ReviewCard.tsx` — review card component
- `App/NGOConnectApp/src/screens/ngo/WriteReviewSheet.tsx` — write review bottom sheet
- `App/NGOConnectApp/src/screens/ngo/ReviewsTab.tsx` — aggregate + list + infinite scroll
- `App/NGOConnectApp/src/screens/ngo/NgoProfileScreen.tsx` — Reviews tab added (5th tab), rating chip in header

SP validator: 215 SPs parsed, all new OrgReview SP↔DAL params clean. Pre-existing Org_GetDashboard false positive only (SQL keyword NOT misread as column alias — confirmed non-issue).

Documents to update when "update documents" is called:
- `Database_Documentation_v5.0.md` → add OrgReviews, OrgReviewMedia, OrgReviewResponses, OrgReviewHelpful tables; add 3 LookupTypes; document 7 new SPs
- `API_Documentation_v5.0.docx` → add OrgReviews section with 6 endpoints, request/response shapes
- `NGOConnect_Postman_Collection_v5.0.json` → add 6 OrgReview request examples

**Review Notifications — v5.2 (2026-08-09)**

DB changes:
- `NGOConnect_Complete_Setup_v5.0.sql`:
  - `NOTIFICATION_TYPE` LookupValues — 3 new entries: `REVIEW_NEW` (OrderNo 9), `REVIEW_RESPONSE` (10), `REVIEW_DELETED` (11)
  - `OrgReview_Add` SP — success branch now returns `ReviewerUserId`, `AuthorName`, `OrgName` alongside `ReviewId` (for REVIEW_NEW fan-out in DAL)
  - `OrgReview_Delete` SP — success branch now returns `ReviewerUserId`, `AuthorName`, `OverallRating`, `OrgName`, `OrgId` (for REVIEW_DELETED fan-out in DAL)
  - `OrgReview_AddResponse` SP — success branch now returns `ReviewerUserId`, `OrgName` (for REVIEW_RESPONSE push in DAL)
  - SchemaVersions entry `v5.2`
- Standalone patch: `Documents/patch_review_notifications.sql`

Backend changes:
- `NGOConnect.Infrastructure/DAL/OrgReviewDal.cs`:
  - Constructor now injects `INotificationDal` + `IFCMService`
  - `AddAsync` — fire-and-forget `REVIEW_NEW` fan-out to all NGO admins via `GetAdminsWithTokensAsync`
  - `DeleteAsync` — fire-and-forget `REVIEW_DELETED` fan-out to all NGO admins
  - `AddResponseAsync` — fire-and-forget `REVIEW_RESPONSE` push to the reviewer via `GetTokensByUserIdAsync`
  - All notification failures are logged as Warning, never bubble up to the API caller

Mobile changes:
- `App/NGOConnectApp/src/screens/home/NotificationsScreen.tsx`:
  - `notifMeta()` — 3 new cases: `REVIEW_NEW` (⭐ amber), `REVIEW_RESPONSE` (💬 primary), `REVIEW_DELETED` (🗑️ grey)
  - `resolveScreen()` — `REVIEW_NEW` + `REVIEW_DELETED` → `NgoProfile` with `initialTab: 'reviews'` (admin opens reviews tab); `REVIEW_RESPONSE` → same (reviewer sees the response)
- `App/NGOConnectApp/src/screens/ngo/NgoProfileScreen.tsx`:
  - Reads `route.params?.initialTab` on mount; validates against `TABS` array; used as `useState` initial value — allows deep-link from notification to open Reviews tab directly

Documents to update when "update documents" is called:
- `Database_Documentation_v5.0.md` → NOTIFICATION_TYPE LookupValues: add REVIEW_NEW, REVIEW_RESPONSE, REVIEW_DELETED; document updated SP return columns for OrgReview_Add, OrgReview_Delete, OrgReview_AddResponse
- `API_Documentation_v5.0.docx` → OrgReviews section: note FCM notifications sent for add/delete/response; document notifType values
- `NGOConnect_Postman_Collection_v5.0.json` → no new endpoints (notifications are internal)

**OrgReview_GetList — own review pinned to top (2026-08-09)**

DB change:
- `NGOConnect_Complete_Setup_v5.0.sql` + `patch_review_notifications.sql`:
  - `OrgReview_GetList` ORDER BY: added `(r.UserId = p_CurrentUserId) DESC` as the first sort key — own review always appears at position 1 on page 1, regardless of selected sort order (RECENT / HELPFUL / HIGHEST / LOWEST)

Documents to update when "update documents" is called:
- `Database_Documentation_v5.0.md` → `OrgReview_GetList` SP: note that own review is always pinned first

**Post ViewCount tracking (2026-08-09)**
- `NGOConnect_Complete_Setup_v5.0.sql` → `Posts` table: added `ViewCount INT UNSIGNED NOT NULL DEFAULT 0` column (after SaveCount).
- `NGOConnect_Complete_Setup_v5.0.sql` → `Feed_BulkMarkViewed` SP rewritten:
  - Uses temp table `_tmp_new_views` to find posts NOT yet viewed by this user (NOT EXISTS check on FeedInteractions).
  - Inserts only new VIEW rows (deduplication — one unique view per user per post).
  - `UPDATE Posts SET ViewCount = ViewCount + 1` for newly inserted rows only.
  - Old behaviour: INSERT IGNORE with no deduplication and no ViewCount update.
- `App/NGOConnectApp/src/components/home/FeedShortsModal.tsx`:
  - Added `viewedBuffer` (Set<number> ref) and `dwellTimer` ref.
  - When `activePost` changes, starts 1.5 s dwell timer; commits postId to buffer only if user stays ≥ 1.5 s.
  - Buffer auto-flushes at 10 items or on modal close → calls existing `feedApi.markPostsViewed` (fire-and-forget).
  - HomeScreen's existing 10 s interval flush already covers card-feed view tracking.
- Patch file: `Documents/patch_view_count.sql` (ALTER TABLE + backfill UPDATE + new SP DROP+CREATE).
- **Apply to Railway**: Run `patch_view_count.sql` on local → Railway staging → production. No C# backend change needed (existing `/feed/viewed` endpoint unchanged).
- **Database Documentation**: Add `ViewCount` to Posts table description; update `Feed_BulkMarkViewed` SP description (deduplication + ViewCount increment).

**Post_GetPermissions — CanComment default fix (2026-08-10)**
- Bug: `DECLARE v_CanComment TINYINT(1) DEFAULT 0` caused the SP to return `CanComment=0` for any user who is NOT an approved member of the org that authored the post (SELECT INTO finds no row → variable stays at default). This blocked commenting on all public posts for non-members.
- Fix: Changed default to `1`. Non-members have no per-member commenting restriction; the flag only takes effect when the user IS an approved member and an admin has explicitly set `OrgMembers.CanComment = 0`.
- `NGOConnect_Complete_Setup_v5.0.sql` → `Post_GetPermissions`: `DECLARE v_CanComment TINYINT(1) DEFAULT 0` → `DEFAULT 1`.
- Patch file: `Documents/patch_fix_comment_permission.sql`
- No C# / mobile changes needed — SP output is the source of truth.
- **Database Documentation**: Update `Post_GetPermissions` SP description — note that `CanComment` defaults to 1 (non-members allowed).

**Org category showing ValueCode instead of ValueName (2026-08-10)**
- Bug: `Organisations.Category` stores the `ORG_CATEGORY` ValueCode (e.g. `"WOMEN_EMP"`) because `CreateOrgScreen.tsx` sends `categories.find(...)?.valueCode` when registering/updating an org. Three read SPs returned `o.Category` as-is — no JOIN to LookupValues — so the mobile displayed the raw code instead of "Women Empowerment". It appeared intermittent because codes like "EDUCATION" look readable while "WOMEN_EMP", "ANIMAL_WELFARE" do not.
- Mobile already has `categoryName ?? category` fallback in both `ExploreScreen.tsx` and `NgoProfileScreen.tsx` — no mobile change needed.
- Fix (SP-only): added `LEFT JOIN LookupValues cv ON cv.ValueCode = o.Category AND cv.LookupTypeId = v_OrgCatTypeId` + `COALESCE(cv.ValueName, o.Category) AS CategoryName` to three SPs:
  - `Org_List` (Explore tab) — also added `DECLARE v_OrgCatTypeId`
  - `Org_GetProfile` (NgoProfileScreen — DROP+CREATE version)
  - `Org_ListRecommended` (Home recommendations) — also added `DECLARE v_OrgCatTypeId`; updated `GROUP BY` to include `cv.ValueName`
- `NGOConnect_Complete_Setup_v5.0.sql` → all three SPs updated.
- NEW patch file: `Documents/patch_org_category_name.sql` — all three DROP+CREATEs for Railway.
- **Apply to Railway**: Run `patch_org_category_name.sql` on local → Railway staging → production.
- **Database Documentation**: Update `Org_List`, `Org_GetProfile`, `Org_ListRecommended` SP descriptions — note new `CategoryName` output column.

**SOS_RESPONDER_INCOMING mobile notification fix (2026-08-10)**
- Bug: When a responder tapped "I Can Assist" from the Community SOS history, the backend correctly sent FCM + DB notification to the SOS victim (`FireUserNotifAsync` via `Sos_Respond` SP's `VictimUserId`). Three mobile-side gaps prevented the victim from acting on it:
  1. `SOS_RESPONDER_INCOMING` was missing from `SOS_NOTIF_TYPES` in `RootNavigator.tsx` → notification was delivered on the default (silent) channel instead of the urgent alarm channel (`ripplehub_sos`) — victim had no alarm sound/vibration to prompt them.
  2. `RootNavigator.resolveScreen` routed `SOS_RESPONDER_INCOMING` to `SosActive` but did NOT pass `isVictim: true` → victim landed on the screen without Approve/Decline buttons (those are gated on `isVictimParam ?? false`).
  3. `NotificationsScreen.tsx` had no case for `SOS_RESPONDER_INCOMING` in either `notifMeta()` (showed generic 🔔 icon) or `resolveScreen()` (tapping notification in the list did nothing).
- Fixes (mobile only — no backend/SP/DB change):
  - `App/NGOConnectApp/src/navigation/RootNavigator.tsx`: added `SOS_RESPONDER_INCOMING` to `SOS_NOTIF_TYPES`; split `SOS_RESPONDER_INCOMING` into its own `resolveScreen` case passing `{ sosIncidentId: refId, isVictim: true }`.
  - `App/NGOConnectApp/src/screens/home/NotificationsScreen.tsx`: added `SOS_RESPONDER_INCOMING` → `{ emoji: '🙋', color: '#F97316' }` in `notifMeta()`; added `SOS_RESPONDER_INCOMING` → `{ screen: 'SosActive', params: { sosIncidentId: refId, isVictim: true } }` in `resolveScreen()`.
- No documentation updates needed (mobile-only fix; no API or DB surface changed).

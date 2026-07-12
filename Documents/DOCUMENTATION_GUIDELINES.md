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
| `NGOConnect_Complete_Setup_v4.7.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.7.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.7.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.7.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

### Community Module fixes — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`**
- `Community_CreatePost` SP: fix default audience lookup TypeCode → `AUDIENCE_TYPE` (was wrong `POST_VISIBILITY`)
- `Community_CreatePoll` SP: add `p_IsMultiChoice TINYINT(1)` param + persist `PollIsMultiChoice` in INSERT
- `Community_CreatePoll` SP: fix default audience lookup TypeCode → `AUDIENCE_TYPE`

**`NGOConnect_Patch_Community_Railway.sql`** (new combined Railway patch — already updated locally)
- Community_GetFeed: upgraded to v4.3 (PollOptionsJson, RoleName, TimeAgo, PostTypeLkpCode)
- Community_CreatePost: audience TypeCode fixed
- Community_CreatePoll: p_IsMultiChoice added + audience TypeCode fixed
- Patch registry entry for `NGOConnect_Patch_PollOptions_Feed.sql` corrected

**`API_Documentation_v4.6.docx`**
- `POST /community/poll` request body: add `isMultiChoice` (boolean, optional, default false)
- `GET /community/feed` response: add `pollEndsAt` (was pollExpiresAt), `timeAgo`, `roleName`, `postTypeLkpCode`, `pollOptions[].votePct`

**`Database_Documentation_v4.6.md`**
- `Community_CreatePoll` SP: document `p_IsMultiChoice` parameter
- `Community_GetFeed` SP: document v4.3 columns (PollOptionsJson, RoleName, TimeAgo, PostTypeLkpCode)

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_Community_Railway.sql` on Railway staging before testing community page.

### User Contact Update Feature — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`**
- LookupValues seed: added `ADD_PHONE` (OrderNo 5) and `ADD_EMAIL` (OrderNo 6) to `OTP_PURPOSE` type
- New SP `User_SendContactOtp(p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress)`: duplicate check across other users + rate-limit + OTP insert
- New SP `User_VerifyContactOtp(p_UserId, p_Type, p_Value, p_OtpCode, p_IpAddress)`: OTP verify + UPDATE Users.Email or Users.Mobile

**`NGOConnect_Patch_ContactUpdate.sql`** (new Railway patch — already created locally)
- Seeds ADD_PHONE + ADD_EMAIL lookup values
- Creates User_SendContactOtp and User_VerifyContactOtp SPs

**`API_Documentation_v4.7.docx`**
- `POST /user/contact/send-otp` — new endpoint; body: `{ type, value }` where type = "EMAIL" | "PHONE"
- `POST /user/contact/verify` — new endpoint; body: `{ type, value, otpCode }`

**`Database_Documentation_v4.7.md`**
- OTP_PURPOSE lookup: document ADD_PHONE and ADD_EMAIL values
- Document User_SendContactOtp and User_VerifyContactOtp SP signatures and behaviour

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_ContactUpdate.sql` on Railway staging before testing contact update flow.

### Post Like field name fix — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`** (already fixed in-place)
- `Post_GetFeed` SP: renamed column alias `IsLikedByMe` → `IsLiked` (DynamicRow was sending `isLikedByMe` but mobile reads `post.isLiked`)
- `Post_GetById` SP: same rename `IsLikedByMe` → `IsLiked`

**`NGOConnect_Patch_PostLike_FieldFix.sql`** (new Railway patch — already created locally)
- Replaces `Post_GetFeed` and `Post_GetById` SPs with the `IsLiked` alias fix

**`Database_Documentation_v4.7.md`**
- `Post_GetFeed` SP return columns: rename `isLikedByMe` → `isLiked`
- `Post_GetById` SP return columns: rename `isLikedByMe` → `isLiked`

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_PostLike_FieldFix.sql` on Railway staging to fix like persistence.

### Impact rank "#1 of 0" fix — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`** (already fixed in-place)
- `User_GetImpact` SP: `TotalRanked` query changed — removed `ImpactScore > 0` filter so all active non-deleted users are counted (fixes "#1 of 0" for new users with 0 score)
- `User_GetImpact` SP: `RankNumber` query: added `up2.IsDeleted = 0` for consistency

**`NGOConnect_Patch_ImpactRankFix.sql`** (new Railway patch — already created locally)
- Replaces `User_GetImpact` SP with the TotalRanked fix

**`Database_Documentation_v4.7.md`**
- `User_GetImpact`: document that `TotalRanked` counts all active users (not just ImpactScore > 0)

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_ImpactRankFix.sql` on Railway staging to fix "#1 of 0" on Impact screen.

### Nearby Feed algorithm — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`** (already added in-place)
- New SP `Project_GetNearbyFeed(p_UserId, p_UserLat, p_UserLon, p_PageNumber, p_PageSize)`
  - Filters: ACTIVE/UPCOMING, IsPublic=1, no existing PENDING/APPROVED application, DistanceKm ≤ 1000
  - RelevanceScore: +5 NGO member, +3 NGO follower, +2/skill match (cap 3 = max +6), +3 interest/category match
  - Sort: 10 km band ASC → RelevanceScore DESC → DistanceKm ASC → CreatedAt DESC
  - Projects without GPS coordinates sorted last (pseudo-band 999999)
  - Returns 2 result sets: main rows + TotalCount

**`NGOConnect_Patch_NearbyFeed.sql`** (new Railway patch — already created locally)
- Creates `Project_GetNearbyFeed` SP

**`API_Documentation_v4.7.docx`**
- New endpoint `GET /api/v1/project/nearby-feed` — requires auth
  - Query params: `userLat` (decimal?), `userLon` (decimal?), `pageNumber` (int, default 1), `pageSize` (int, default 10)
  - Response: `PagedResult<Project>` — same fields as Project_List plus `distanceKm` (null if no GPS) and `relevanceScore`

**`Database_Documentation_v4.7.md`**
- Document `Project_GetNearbyFeed` SP: params, algorithm, return columns (DistanceKm, RelevanceScore, ApprovedCount)

**`NGOConnect_Postman_Collection_v4.7.json`**
- Add request `GET /project/nearby-feed?userLat=&userLon=&pageNumber=1&pageSize=10` under Project folder

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_NearbyFeed.sql` on Railway staging before testing home screen Nearby Opportunities.
> ⚠️ Patch now also includes `ALTER TABLE ProjectSkills DROP INDEX / ADD INDEX idx_projskill_project (ProjectId, SkillName)` — covering index for the skill-match subquery. Safe to run live.

**`Database_Documentation_v4.7.md`** (add under ProjectSkills table)
- `idx_projskill_project` index changed from `(ProjectId)` → `(ProjectId, SkillName)` — covering index for `Project_GetNearbyFeed` skill-match subquery

### Phase 1 Personalised Feed Algorithm — 2026-07-12 (apply when user says "update documents")

**`NGOConnect_Complete_Setup_v4.7.sql`** (already added in-place)
- `ALTER TABLE Posts` — new columns: `IsEmergency TINYINT(1)`, `IsEvergreen TINYINT(1)`, `ShareCount INT UNSIGNED`, `SaveCount INT UNSIGNED`; new index `idx_post_emergency (IsEmergency, CreatedAt)`
- **NEW TABLE** `PostSaves` — UserId, PostId, SavedAt; UNIQUE KEY (UserId, PostId)
- **NEW TABLE** `FeedInteractions` — UserId, PostId, InteractionType (ENUM), OccurredAt, DurationMs; INDEX (PostId, InteractionType), INDEX (UserId, OccurredAt)
- **22 Settings seeds** — all keys prefixed `FEED_*` (e.g. `FEED_WEIGHT_MY_ORG`, `FEED_WEIGHT_EMERGENCY`, `FEED_MAX_SAME_ORG_WINDOW`, etc.) in group `FEED`
- **NEW SP** `Feed_GetPersonalized(p_UserId, p_CursorPostId, p_CursorScore, p_PageSize)` — multi-source scored feed (MY_ORG 200, FOLLOWED_ORG 200, TRENDING 100, EMERGENCY 50, INTEREST 100, RECENT 100 candidates); inline scoring formula; cursor-based pagination `(FeedScore DESC, PostId DESC)`; IsEmergency adds +1000 override
- **NEW SP** `Post_Save(p_UserId, p_PostId)` — idempotent insert into PostSaves + increment `Posts.SaveCount`
- **NEW SP** `Post_Unsave(p_UserId, p_PostId)` — delete from PostSaves + decrement `Posts.SaveCount` (GREATEST n-1, 0)
- **NEW SP** `Feed_TrackInteraction(p_UserId, p_PostId, p_InteractionType, p_DurationMs)` — fire-and-forget insert into FeedInteractions

**`NGOConnect_Patch_PersonalizedFeed.sql`** (new Railway patch — already created locally)
- ALTER TABLE Posts + CREATE TABLE PostSaves + CREATE TABLE FeedInteractions
- 22 FEED_* Settings seeds (INSERT IGNORE)
- Feed_GetPersonalized, Post_Save, Post_Unsave, Feed_TrackInteraction SPs

**`API_Documentation_v4.7.docx`** — new `FeedController` endpoints:
- `GET /api/v1/feed/personalized` — `[Authorize]`; query params: `cursorPostId?` (int), `cursorScore?` (decimal), `pageSize` (int, default 20); response: `ApiResponse<FeedPageResult>` with `items[]`, `nextCursorPostId`, `nextCursorScore`, `hasMore`
- `POST /api/v1/feed/post/{postId}/save` — `[Authorize]`; saves post to user's collection
- `DELETE /api/v1/feed/post/{postId}/save` — `[Authorize]`; removes post from saved collection
- `POST /api/v1/feed/interaction` — `[Authorize]`; body: `{ postId, interactionType, durationMs? }`; interactionType: IMPRESSION | VIEW | LIKE | COMMENT | SHARE | SAVE | VOLUNTEER_CLICK | DONATION_CLICK | NGO_VISIT | HIDE | REPORT

**`NGOConnect_Postman_Collection_v4.7.json`**
- Add request `GET /feed/personalized?pageSize=20` (first page — no cursor params)
- Add request `GET /feed/personalized?cursorPostId=123&cursorScore=850.5&pageSize=20` (subsequent page)
- Add request `POST /feed/post/{{postId}}/save`
- Add request `DELETE /feed/post/{{postId}}/save`
- Add request `POST /feed/interaction` — body: `{ "postId": 1, "interactionType": "VIEW", "durationMs": 3000 }`

**`Database_Documentation_v4.7.md`**
- Document `PostSaves` table: columns, UNIQUE KEY, purpose
- Document `FeedInteractions` table: columns, ENUMs, indexes, purpose
- Document altered `Posts` table columns: IsEmergency, IsEvergreen, ShareCount, SaveCount, idx_post_emergency index
- Document `Feed_GetPersonalized` SP: params, candidate sources, scoring formula, diversity engine (C#-side), cursor pagination
- Document `Post_Save` and `Post_Unsave` SPs: params, idempotency, counter maintenance
- Document `Feed_TrackInteraction` SP: params, fire-and-forget nature, future AI training use
- Document 22 `FEED_*` Settings seeds: group FEED, list keys with default values

> ⚠️ **Railway Action Required** — Run `NGOConnect_Patch_PersonalizedFeed.sql` on Railway staging before testing personalised feed endpoint.

<!-- Version bumped: v4.6 → v4.7 (2026-07-12). Active files are now v4.7. -->
<!-- Patch file: NGOConnect_Patch_v4.7.sql — apply to Railway staging to bring it current -->
<!-- Rule: next version bump happens ONLY when changes are deployed to Railway staging -->

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

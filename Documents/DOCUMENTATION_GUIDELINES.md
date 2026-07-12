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
| `NGOConnect_Complete_Setup_v4.6.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.6.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.6.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.6.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

1. **Review the pending changes list** — every change tracked since the last update
2. **Cross-check all files** — re-read relevant DAL, model, controller, and SP files to catch any missed changes
3. **Assess change scope** — classify as Minor, Significant, or Major (see Versioning Rule above)
4. **Ask for confirmation** — present the scope assessment and ask: update in-place or create new version?
5. **Apply all changes** — no change is too minor to skip
6. **Bump version (if confirmed)** — rename files to new version across all updated documents
7. **Clear the pending changes list** after update is complete

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

<!-- Added 2026-07-12: NGO Follow feature (Source: NGOConnect_Patch_OrgFollow.sql) -->
<!-- Added 2026-07-12: FollowerCount on Admin Dashboard (Source: NGOConnect_Patch_DashboardFollowers.sql) -->
<!-- Added 2026-07-12: Org_GetVolunteerProfile SP fix (Source: NGOConnect_Patch_VolunteerProfileFix.sql) -->
<!-- Added 2026-07-12: Post_GetPermissions SP + endpoint (Source: NGOConnect_Patch_PostPermissions.sql) -->

**`NGOConnect_Complete_Setup_v4.6.sql`** — already updated in-file ✅
- NEW SP `Post_GetPermissions(p_OrgId, p_UserId)` — returns IsMember, CanPost, MaxPostsPerDay, TodayPostCount; always one row; used by mobile before opening Create Post modal

**`API_Documentation_v4.6.docx`**
- NEW endpoint: GET /api/v1/post/permissions/{orgId} — returns PostPermissionsModel (isMember, canPost, maxPostsPerDay, todayPostCount); Authorize required

**`NGOConnect_Postman_Collection_v4.6.json`**
- Add GET /post/permissions/{{orgId}} sample request
- NEW TABLE `OrgFollowers`: OrgFollowerId, OrgId, UserId, IsFollowing TINYINT(1), FollowedAt, UnfollowedAt — soft-unfollow pattern; UNIQUE KEY (OrgId, UserId)
- NEW COLUMN `Organisations.FollowerCount` INT UNSIGNED DEFAULT 0 — denormalized, maintained by Org_Follow / Org_Unfollow SPs
- NEW SP `Org_Follow(p_OrgId, p_UserId)` — INSERT ... ON DUPLICATE KEY UPDATE; increments FollowerCount; idempotent (returns success if already following)
- NEW SP `Org_Unfollow(p_OrgId, p_UserId)` — soft-unfollow (IsFollowing=0, UnfollowedAt=NOW()); decrements FollowerCount with GREATEST floor; idempotent
- UPDATED SP `Org_GetProfile` — adds `FollowerCount` + `IsFollowing` (0|1 subquery on OrgFollowers for p_UserId)
- UPDATED SP `Post_GetFeed` — adds `IsFollowing` (0|1) per post based on post's OrgId and p_UserId
- UPDATED SP `Org_List` — adds `FollowerCount` from denormalized column
- UPDATED SP `Org_GetDashboard` — adds `FollowerCount` subquery (reads from Organisations.FollowerCount)
- UPDATED SP `Org_GetVolunteerProfile` — fixed: AttendanceStatus → AttendStatusLkpId via declared vars; pa.ProjectId → JOIN ProjectSessions; ReliabilityPct rewritten as HAVING aggregate

**`Database_Documentation_v4.6.md`**
- Add OrgFollowers table documentation (all columns, indexes, FKs)
- Add FollowerCount column to Organisations table documentation
- Add Org_Follow SP documentation (params, return, behaviour)
- Add Org_Unfollow SP documentation (params, return, behaviour)
- Update Org_GetProfile SP — add FollowerCount + IsFollowing to return columns
- Update Post_GetFeed SP — add IsFollowing to return columns
- Update Org_List SP — add FollowerCount to return columns
- Update Org_GetDashboard SP — add FollowerCount to return columns

**`API_Documentation_v4.6.docx`**
- NEW endpoint: POST /api/v1/org/{orgId}/follow — follow an NGO (Authorize required)
- NEW endpoint: DELETE /api/v1/org/{orgId}/follow — unfollow an NGO (Authorize required)
- Both return ApiResponse (no data payload); IsSuccess=1 even if already following/unfollowing (idempotent)
- Update GET /api/v1/org/{orgId} response — new fields: followerCount (int), isFollowing (0|1)
- Update GET /api/v1/feed response — new field per post: isFollowing (0|1)
- Update GET /api/v1/org/list response — new field per item: followerCount (int)

**`NGOConnect_Postman_Collection_v4.6.json`**
- Add POST /org/{{orgId}}/follow sample request
- Add DELETE /org/{{orgId}}/follow sample request
<!-- Version bumped: v4.5 → v4.6 (2026-07-12). Active files are now v4.6. -->
<!-- Patch file: NGOConnect_Patch_v4.6.sql — apply to Railway staging to bring it current -->
<!-- Rule: next version bump happens ONLY when changes are deployed to Railway staging -->

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
- Then update `API_Documentation_v4.6.docx` with the CORS note

---

### Outstanding — Future Sessions (backend bugs, no work yet)

- `Community_CreatePost` SP: Add params `p_IsPinned`, `p_NotifyAll`, `p_AllowBestAnswer`, `p_EventReference`, `p_WhatChanged`
- `Community_CreatePoll` SP: Add params `p_IsMultiChoice`, `p_AudienceLkpId`
- New endpoint: `PATCH /community/post/{id}/pin` — not yet built
- New endpoint: `DELETE /community/post/{id}` — not yet built
- `Post_Report` SP: looks up `ORG_STATUS` instead of `REPORT_STATUS` — copy-paste bug, fix in a future session

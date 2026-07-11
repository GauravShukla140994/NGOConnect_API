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
| `NGOConnect_Complete_Setup_v4.5.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.5.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.5.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.5.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

<!-- All Super Admin module changes (2026-07-11 sessions) applied to all 4 documents ✅ -->
<!-- Version bumped: v4.4 → v4.5 (2026-07-11). Active files are now v4.5. -->
<!-- Patch file: NGOConnect_Patch_v4.5_Complete.sql covers all v4.4→v4.5 changes for Railway staging/prod -->
<!-- Next pending items are backend-build tasks — no document updates needed until those are built -->

### Backend build (Steps 1–4) — COMPLETE 2026-07-11, docs not yet updated

All four steps below are now built end-to-end (SQL + C# DAL/interface/controller) and the
frontend (`Website` repo `/admin`) has been reconciled to the real field names. Apply to all
4 maintained documents next time the user says "update documents".

**Not yet done — needs the user:**
- Run `Documents/NGOConnect_Patch_SuperAdminModule_Members_Dashboard.sql` against local (and later staging/prod) MySQL — creates the `Users.ProfileVerificationLkpId` column, `PROFILE_VERIFICATION_STATUS` lookup, and re-creates `SuperAdmin_Org_GetDetail` / `SuperAdmin_Org_GetList` (both gained new output columns) plus 9 brand-new SPs. Safe to re-run (idempotent).
- `dotnet build` the solution — no .NET SDK was available in this environment, so all C# changes were verified by manual read-through only, never compiled.
- **⚠️ OPEN QUESTION, still unresolved:** `AuthDal` never checks `Users.IsActive`, so `SuperAdmin_User_Suspend` blocks continuing an existing session (revokes refresh tokens) but does NOT block a suspended member from starting a brand-new login. Fixing this means editing existing `AuthDal.cs` — out of scope for the isolated Super Admin module without explicit sign-off. Ask the user before touching it.

#### Step 1 — Org Status History
- `Database_Documentation_v4.5.md` → Add `SuperAdmin_Org_GetStatusHistory(p_OrgId)`. Returns: OrgStatusHistoryId, OldStatus, OldStatusName, NewStatus, NewStatusName, Reason, ChangedByType, ChangedBy, CreatedAt. ORDER BY CreatedAt DESC.
- `API_Documentation_v4.5.docx` → Add `GET /superadmin/orgs/{orgId}/history`
- `NGOConnect_Postman_Collection_v4.5.json` → Add request "Get Org Status History" to Super Admin folder
- `NGOConnect_Complete_Setup_v4.5.sql` → Already contains `SuperAdmin_Org_GetStatusHistory` (appended this session)

#### Step 2 — Member / User Admin Module
- `Database_Documentation_v4.5.md` → New column `Users.ProfileVerificationLkpId INT UNSIGNED NULL`; new LookupType `PROFILE_VERIFICATION_STATUS` (PENDING, VERIFIED, NEEDS_UPDATE); add 9 new SPs: `SuperAdmin_User_GetList` (now includes `Role`), `SuperAdmin_User_GetFullProfile` (5 result sets: profile, skills, interests, badges, other-orgs), `SuperAdmin_User_GetDocuments`, `SuperAdmin_UserDocument_Verify`, `SuperAdmin_User_VerifyProfile`, `SuperAdmin_User_RequestUpdate`, `SuperAdmin_User_Suspend`, `SuperAdmin_User_Reactivate`
- `API_Documentation_v4.5.docx` → Add 8 endpoints: `GET /superadmin/members`, `GET /superadmin/members/{userId}`, `GET /superadmin/members/{userId}/documents`, `PUT /superadmin/members/documents/verify` (body: `{userDocumentId, isVerified}`), `PUT /superadmin/members/{userId}/verify-profile`, `PUT /superadmin/members/request-update`, `PUT /superadmin/members/{userId}/suspend`, `PUT /superadmin/members/{userId}/reactivate`
- `NGOConnect_Postman_Collection_v4.5.json` → Add 8 requests to Super Admin folder
- `NGOConnect_Complete_Setup_v4.5.sql` → Already contains the `ALTER TABLE`, lookup seed, and all 8 SPs (appended this session)

#### Step 3 — Dashboard KPIs
- `Database_Documentation_v4.5.md` → Add `SuperAdmin_Dashboard_GetKpis()` (TotalOrgs, PendingOrgs, TotalVolunteers, ActiveVolunteersLast30Days, TotalDonationsAmount) and `SuperAdmin_Org_GetRecent(p_Limit)`
- `API_Documentation_v4.5.docx` → Add `GET /superadmin/dashboard` (flat KPI fields + `recentOrgs` array)
- `NGOConnect_Postman_Collection_v4.5.json` → Add "Get Dashboard" request
- `NGOConnect_Complete_Setup_v4.5.sql` → Already contains both SPs (appended this session)

#### Step 4 — CORS for Website React App
- Done for local dev only: `appsettings.Development.json` `Cors:AllowedOrigins` now includes `http://localhost:5173` and `http://localhost:4173`. Production origin still needs to be confirmed with the user and added to `appsettings.json`/Railway config before prod deploy.
- `API_Documentation_v4.5.docx` → Add CORS note once prod origin is confirmed.

#### Additional SP enhancements this session (isolated SPs, safe to modify per isolation rule)
- `SuperAdmin_Org_GetDetail` → added `MemberCount` (subquery, counts APPROVED `OrgMembers`) so the Organisations drawer can show a real member count instead of a permanently blank field
- `SuperAdmin_Org_GetList` → added `OrgType` (was missing entirely — the Organisations list "Type" column was silently blank before this fix)
- Both changes are in `NGOConnect_Complete_Setup_v4.5.sql` and in the standalone patch file — need the same `Database_Documentation_v4.5.md` / `API_Documentation_v4.5.docx` updates as above (new response fields on `GET /superadmin/orgs` and `GET /superadmin/orgs/{orgId}`)

---

### Outstanding (future sessions — backend bugs flagged, no backend work yet)

- `Community_CreatePost` SP: Add params `p_IsPinned`, `p_NotifyAll`, `p_AllowBestAnswer`, `p_EventReference`, `p_WhatChanged` (mobile sends these; SP does not yet accept them)
- `Community_CreatePoll` SP: Add params `p_IsMultiChoice`, `p_AudienceLkpId`
- New endpoint: `PATCH /community/post/{id}/pin` — does not exist in backend yet
- New endpoint: `DELETE /community/post/{id}` — does not exist in backend yet
- `Post_Report` SP: sets `PostReports.StatusLkpId` by looking up `ORG_STATUS` type instead of `REPORT_STATUS` — copy-paste bug, flagged for future fix

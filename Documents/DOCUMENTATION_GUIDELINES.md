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
| `NGOConnect_Complete_Setup_v4.4.sql` | Single-run DB script — tables, seed data, all SPs |
| `Database_Documentation_v4.4.md` | Full DB reference — tables, columns, indexes, SP signatures, parameters, return values |
| `API_Documentation_v4.4.docx` | API reference for frontend/mobile teams — endpoints, request bodies, responses, auth |
| `NGOConnect_Postman_Collection_v4.4.json` | Ready-to-import Postman collection — all endpoints with sample request bodies |

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

<!-- Accumulated since: 2026-07-10 (v4.4 released — all prior pending changes applied) -->

**`NGOConnect_Complete_Setup_v4.4.sql`**
- `Post_Create`: Remove duplicate 7-param definition at line ~2695 (old version with `p_MediaType`). The canonical 6-param version at line ~6243 (from `NGOConnect_Patch_PostFeed_VideoSupport.sql`, auto-detects IMAGE/VIDEO from URL extension) is the one running in DB — the duplicate causes confusion.
- `Post_GetFeed`: Update to 4-param signature: `p_UserId, p_OrgId, p_PageNumber, p_PageSize`. Add `AND (p_OrgId IS NULL OR p.OrgId = p_OrgId)` to both SELECT and COUNT. Source: `NGOConnect_Patch_PostFeed_OrgFilter.sql`.

---

### Outstanding (future sessions — needs backend work before docs can be updated)

- `Community_CreatePost` SP: Add params `p_IsPinned`, `p_NotifyAll`, `p_AllowBestAnswer`, `p_EventReference`, `p_WhatChanged` (mobile sends these; SP does not yet accept them)
- `Community_CreatePoll` SP: Add params `p_IsMultiChoice`, `p_AudienceLkpId`
- New endpoint: `PATCH /community/post/{id}/pin` — does not exist in backend yet
- New endpoint: `DELETE /community/post/{id}` — does not exist in backend yet
- `03_SP_User.sql` file: Update to match patched `User_GetProfile` (2-param version with full column list)

# NGO Connect — SOS Feature: Complete Development Prompt

> **Version:** v4.1  
> **Date:** 2026-07-04  
> **Scope:** Full SOS module implementation — DB, SPs, C# backend, SignalR real-time, community integration  
> **Document update rule:** Do NOT update API_Documentation, Database_Documentation, or Postman collection mid-task.  
> Accumulate all changes and apply only when user says "update documents".

---

## 1. Project Stack & Architecture (Non-Negotiable)

- ASP.NET Core 8, C#, MySQL 8.0
- Architecture: **Controller → Interface → DAL (inherits BaseDal) → Stored Procedure**
- No EF Core — ADO.NET + Stored Procedures only
- API standard: `ApiResponse<T>` (IsSuccess, Message, Data, ErrorCode)
- All lookups via `LookupTypes + LookupValues` (never hardcoded enums)
- All write SPs return: `SELECT IsSuccess, Message [, EntityId]`
- DynamicRow for all display/read queries — typed models for write requests only

---

## 2. What Already Exists — Do Not Recreate

### DB Tables (all correct, no changes needed)
```
SosIncidents      — SosIncidentId, UserId, OrgId, AlertTypeLkpId, Description,
                    ApproxLocation, Latitude, Longitude, StatusLkpId,
                    ResolvedAt, ResolvedByLkpId, CancelReason, IsDeleted,
                    CreatedAt, UpdatedAt
SosResponders     — SosResponderId, SosIncidentId, UserId, RespondedAt,
                    ApprovalStatusLkpId, ApprovedAt, ApprovedBy, CanViewLocation
SosLocationLogs   — SosLocationLogId (BIGINT), SosIncidentId, UserId,
                    Latitude, Longitude, Accuracy, LoggedAt
```

### Stored Procedures (all exist in NGOConnect_Complete_Setup_v4.1.sql)
```
Sos_Trigger           Sos_Respond          Sos_UpdateLocation
Sos_GetActive         Sos_Resolve          Sos_ApproveResponder
Sos_Cancel            Sos_GetLatestLocation Sos_GetById
```

### C# Files (all exist, need fixes — see Section 3)
```
NGOConnect.Core/Models/Sos/SosModels.cs
NGOConnect.Core/Interfaces/ISosDal.cs
NGOConnect.Infrastructure/DAL/SosDal.cs
NGOConnect.API/Controllers/SosController.cs
```

---

## 3. Bugs to Fix First (Before Any New Work)

### Bug 1 — `Sos_ApproveResponder` SP parameter mismatch (CRITICAL)

**SP signature:**
```sql
Sos_ApproveResponder(IN p_SosResponderId INT UNSIGNED,
                     IN p_ApprovedBy     INT UNSIGNED,
                     IN p_CanViewLocation TINYINT(1))
```

**Current DAL (WRONG):**
```csharp
_db.AddParameter(cmd, "p_SosIncidentId",   sosIncidentId);  // ← wrong param name
_db.AddParameter(cmd, "p_ApprovedBy",      userId);
_db.AddParameter(cmd, "p_ResponderId",     request.ResponderId); // ← wrong param name
_db.AddParameter(cmd, "p_CanViewLocation", request.CanViewLocation);
```

**Fix — `SosDal.ApproveResponderAsync`:**
```csharp
public async Task<ApiResponse> ApproveResponderAsync(int sosIncidentId, int userId, ApproveResponderRequest request)
{
    try
    {
        var result = await ExecuteWriteAsync("Sos_ApproveResponder", cmd =>
        {
            _db.AddParameter(cmd, "p_SosResponderId",  request.SosResponderId); // ← SosResponderId from request
            _db.AddParameter(cmd, "p_ApprovedBy",      userId);
            _db.AddParameter(cmd, "p_CanViewLocation", request.CanViewLocation);
        });
        return result.ToApiResponse();
    }
    catch (Exception ex)
    {
        Log.Error(ex, "ApproveResponderAsync failed SosIncidentId={Id}", sosIncidentId);
        return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
    }
}
```

Also update **`ApproveResponderRequest`** model in `SosModels.cs`:
```csharp
public class ApproveResponderRequest
{
    [Required] public int  SosResponderId   { get; set; }  // was ResponderId — rename to match SP
    public bool            CanViewLocation  { get; set; } = true;
}
```

---

### Bug 2 — `Sos_Resolve` has extra param that SP does not accept

**SP signature:**
```sql
Sos_Resolve(IN p_SosIncidentId INT UNSIGNED,
            IN p_UserId        INT UNSIGNED,
            IN p_StatusCode    VARCHAR(50),
            IN p_CancelReason  TEXT)
```
SP resolves `ResolvedByLkpId` internally — it does NOT accept it as a param.

**Current DAL (WRONG):**
```csharp
_db.AddParameter(cmd, "p_ResolvedByLkpId", request.ResolvedByLkpId); // ← param does not exist in SP
```

**Fix — `SosDal.ResolveAsync`:** Remove `p_ResolvedByLkpId`. Remove `ResolvedByLkpId` from `ResolveSosRequest` model. The SP handles it internally based on `p_StatusCode = 'RESOLVED'`.

```csharp
public async Task<ApiResponse> ResolveAsync(int sosIncidentId, int userId)
{
    try
    {
        var result = await ExecuteWriteAsync("Sos_Resolve", cmd =>
        {
            _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
            _db.AddParameter(cmd, "p_UserId",        userId);
            _db.AddParameter(cmd, "p_StatusCode",    "RESOLVED");
            _db.AddParameter(cmd, "p_CancelReason",  (object?)null);
        });
        return result.ToApiResponse();
    }
    catch (Exception ex)
    {
        Log.Error(ex, "ResolveAsync failed SosIncidentId={Id}", sosIncidentId);
        return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
    }
}
```

Update `ISosDal` signature: `Task<ApiResponse> ResolveAsync(int sosIncidentId, int userId);`  
Update `ResolveSosRequest`: remove entirely (no request body needed — victim just hits the endpoint).  
Update `SosController.Resolve`: `[HttpPut("{sosIncidentId:int}/resolve")] public async Task<ApiResponse> Resolve(int sosIncidentId) => await _sos.ResolveAsync(sosIncidentId, GetUserId());`

---

### Bug 3 — `GetByIdAsync` misses second result set (responders list)

`Sos_GetById` SP returns **2 result sets**:
1. Incident details (1 row)
2. Responders list (0–N rows)

Current `ExecuteDynamicGetAsync` only reads result set 1. Fix by using `FillDataSetAsync` directly:

```csharp
public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int sosIncidentId, int userId)
{
    try
    {
        using var conn = await _db.CreateConnectionAsync();
        using var cmd  = _db.CreateCommand("Sos_GetById", conn);
        _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
        _db.AddParameter(cmd, "p_UserId",        userId);

        var ds = await _db.FillDataSetAsync(cmd);

        if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            return ApiResponse<DynamicRow>.Failure("SOS incident not found.", "NOT_FOUND");

        // Result set 1: incident details
        var incident = DynamicRow.FromDataRow(ds.Tables[0].Rows[0]);

        // Result set 2: responders list
        var responders = new List<DynamicRow>();
        if (ds.Tables.Count > 1)
            foreach (DataRow r in ds.Tables[1].Rows)
                responders.Add(DynamicRow.FromDataRow(r));

        incident["responders"] = responders;
        return ApiResponse<DynamicRow>.Success(incident);
    }
    catch (Exception ex)
    {
        Log.Error(ex, "GetByIdAsync failed SosIncidentId={Id}", sosIncidentId);
        return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
    }
}
```

> Note: Check if `DynamicRow.FromDataRow` exists in the codebase. If not, map manually using `Col<T>` or build a `DynamicRow` from the `DataRow` columns.

---

### Bug 4 — `TriggerAsync` hardcodes `p_OrgId = null`

The SP accepts `p_OrgId`. Currently the DAL passes `null` always. Add `OrgId` to the model:

**Update `TriggerSosRequest`:**
```csharp
public class TriggerSosRequest
{
    [Required] public decimal Latitude        { get; set; }
    [Required] public decimal Longitude       { get; set; }
    public string?            Description     { get; set; }
    [Required] public int     AlertTypeLkpId  { get; set; }
    public int?               OrgId           { get; set; }  // ← ADD THIS
    public string?            ApproxLocation  { get; set; }  // ← ADD THIS (address string)
}
```

**Update `SosDal.TriggerAsync`:**
```csharp
_db.AddParameter(cmd, "p_OrgId",          (object?)request.OrgId);
_db.AddParameter(cmd, "p_ApproxLocation", request.ApproxLocation);
```

---

## 4. New SP Required — `Sos_GetMyActive`

The existing `Sos_GetActive` returns all active SOS for an org. The `s-sos-active` screen (victim view) needs the **current user's own active incident**. Add this SP:

```sql
CREATE PROCEDURE Sos_GetMyActive(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ActiveLkpId INT UNSIGNED;
    SELECT LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    -- Return the victim's own active incident
    SELECT si.SosIncidentId, si.OrgId, o.OrgName,
           atv.ValueCode AS AlertType, atv.ValueName AS AlertTypeName,
           si.Description, si.ApproxLocation, si.Latitude, si.Longitude,
           si.CreatedAt,
           sv.ValueCode AS Status
    FROM SosIncidents si
    LEFT JOIN Organisations o    ON si.OrgId = o.OrgId
    LEFT JOIN LookupValues atv   ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT JOIN LookupValues sv    ON si.StatusLkpId    = sv.LookupValueId
    WHERE si.UserId = p_UserId AND si.StatusLkpId = v_ActiveLkpId AND si.IsDeleted = 0
    ORDER BY si.CreatedAt DESC LIMIT 1;

    -- Return the responders for that incident
    SELECT sr.SosResponderId, sr.UserId,
           CONCAT(up.FirstName,' ',up.LastName) AS ResponderName,
           up.ProfilePhoto,
           rv.ValueCode AS ApprovalStatus,
           sr.RespondedAt, sr.CanViewLocation
    FROM SosResponders sr
    JOIN SosIncidents si2     ON sr.SosIncidentId = si2.SosIncidentId
    JOIN UserProfiles up      ON sr.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE si2.UserId = p_UserId AND si2.StatusLkpId = v_ActiveLkpId AND si2.IsDeleted = 0;
END //
```

Add to `ISosDal`:
```csharp
Task<ApiResponse<DynamicRow>> GetMyActiveAsync(int userId);
```

Add to `SosDal`:
```csharp
public async Task<ApiResponse<DynamicRow>> GetMyActiveAsync(int userId)
{
    try
    {
        using var conn = await _db.CreateConnectionAsync();
        using var cmd  = _db.CreateCommand("Sos_GetMyActive", conn);
        _db.AddParameter(cmd, "p_UserId", userId);

        var ds = await _db.FillDataSetAsync(cmd);

        if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            return ApiResponse<DynamicRow>.Failure("No active SOS found.", "NOT_FOUND");

        var incident = DynamicRow.FromDataRow(ds.Tables[0].Rows[0]);
        var responders = new List<DynamicRow>();
        if (ds.Tables.Count > 1)
            foreach (DataRow r in ds.Tables[1].Rows)
                responders.Add(DynamicRow.FromDataRow(r));

        incident["responders"] = responders;
        return ApiResponse<DynamicRow>.Success(incident);
    }
    catch (Exception ex)
    {
        Log.Error(ex, "GetMyActiveAsync failed UserId={UserId}", userId);
        return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
    }
}
```

Add to `SosController`:
```csharp
[HttpGet("my-active")]
public async Task<ApiResponse<DynamicRow>> GetMyActive()
    => await _sos.GetMyActiveAsync(GetUserId());
```

---

## 5. SignalR Hub — `SosHub`

> File: `NGOConnect.API/Hubs/SosHub.cs`

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using System.Security.Claims;

namespace NGOConnect.API.Hubs
{
    [Authorize]
    public class SosHub : Hub
    {
        // Client joins the group for a specific SOS incident
        public async Task JoinSosGroup(int sosIncidentId)
            => await Groups.AddToGroupAsync(Context.ConnectionId, $"sos-{sosIncidentId}");

        public async Task LeaveSosGroup(int sosIncidentId)
            => await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"sos-{sosIncidentId}");

        // Victim broadcasts their live location to all approved responders in the group
        public async Task SendLocation(int sosIncidentId, decimal latitude, decimal longitude)
        {
            await Clients.OthersInGroup($"sos-{sosIncidentId}")
                .SendAsync("LocationUpdated", new { sosIncidentId, latitude, longitude, timestamp = DateTime.UtcNow });
        }
    }
}
```

**Hub events (client receives):**
| Event | Sent by | Data | When |
|---|---|---|---|
| `LocationUpdated` | Hub (from victim) | `{ sosIncidentId, latitude, longitude, timestamp }` | Victim calls `SendLocation` |
| `ResponderApproved` | Server (after approve API) | `{ sosIncidentId, sosResponderId }` | Victim approves a responder |
| `SosResolved` | Server (after resolve/cancel API) | `{ sosIncidentId, status }` | SOS ends |
| `NewResponder` | Server (after respond API) | `{ sosIncidentId, responderName }` | Someone clicks "I Can Assist" |

**Register SignalR in `Program.cs`:**
```csharp
builder.Services.AddSignalR();
// ...
app.MapHub<SosHub>("/hubs/sos");
```

**Broadcast from SosDal after approve (inject `IHubContext<SosHub>`):**
```csharp
// After successful ApproveResponder SP call:
await _sosHubContext.Clients.Group($"sos-{sosIncidentId}")
    .SendAsync("ResponderApproved", new { sosIncidentId, request.SosResponderId });
```

**Broadcast from SosDal after resolve/cancel:**
```csharp
await _sosHubContext.Clients.Group($"sos-{sosIncidentId}")
    .SendAsync("SosResolved", new { sosIncidentId, status });
```

**Broadcast from SosDal after respond:**
```csharp
await _sosHubContext.Clients.Group($"sos-{sosIncidentId}")
    .SendAsync("NewResponder", new { sosIncidentId, responderName = "..." });
```

---

## 6. Complete API Contracts (All SOS Endpoints)

### POST `/api/v1/sos` — Trigger SOS
**Auth:** Required  
**Request body:**
```json
{
  "alertTypeLkpId": 1,
  "orgId": 5,
  "latitude": 12.9716,
  "longitude": 77.5946,
  "approxLocation": "Whitefield, Bangalore",
  "description": "Need immediate help"
}
```
**Response:** `ApiResponse<DynamicRow>` — `{ sosIncidentId, message }`

---

### GET `/api/v1/sos/my-active` — Get My Own Active SOS (s-sos-active screen)
**Auth:** Required  
**Response:** `ApiResponse<DynamicRow>` — incident details + `responders[]` array

**Response shape:**
```json
{
  "isSuccess": 1,
  "data": {
    "sosIncidentId": 7,
    "orgName": "Education First",
    "alertType": "SOS_ALERT",
    "alertTypeName": "SOS Alert",
    "description": "Need help",
    "approxLocation": "Whitefield Area",
    "latitude": 12.9716,
    "longitude": 77.5946,
    "status": "ACTIVE",
    "createdAt": "2026-07-04T09:21:00Z",
    "responders": [
      {
        "sosResponderId": 3,
        "userId": 12,
        "responderName": "Priya Sharma",
        "profilePhoto": null,
        "approvalStatus": "PENDING",
        "respondedAt": "2026-07-04T09:22:00Z",
        "canViewLocation": false
      }
    ]
  }
}
```

---

### GET `/api/v1/sos/active?orgId=5` — Get All Active SOS for Org (community feed)
**Auth:** Required  
**Response:** `ApiResponse<List<DynamicRow>>` — list of active incidents with `responderCount`

---

### GET `/api/v1/sos/{sosIncidentId}` — Get SOS Details (View Details button)
**Auth:** Required  
**Response:** `ApiResponse<DynamicRow>` — incident + responders array (2 result sets merged)

---

### POST `/api/v1/sos/{sosIncidentId}/respond` — I Can Assist
**Auth:** Required, no request body  
**Response:** `ApiResponse` — `{ isSuccess: 1, message: "Response registered, awaiting approval." }`

---

### PUT `/api/v1/sos/{sosIncidentId}/approve-responder` — Approve Responder (victim action)
**Auth:** Required  
**Request body:**
```json
{
  "sosResponderId": 3,
  "canViewLocation": true
}
```
**Response:** `ApiResponse`  
**Side effect:** Broadcast `ResponderApproved` SignalR event to group `sos-{sosIncidentId}`

---

### PUT `/api/v1/sos/{sosIncidentId}/resolve` — Mark as Resolved (victim action)
**Auth:** Required, no request body  
**Response:** `ApiResponse`  
**Side effect:** Broadcast `SosResolved` SignalR event

---

### PUT `/api/v1/sos/{sosIncidentId}/cancel` — Cancel SOS
**Auth:** Required  
**Request body:**
```json
{
  "cancelReason": "I am safe now"
}
```
**Response:** `ApiResponse`  
**Side effect:** Broadcast `SosResolved` SignalR event

---

### GET `/api/v1/sos/{sosIncidentId}/location` — Get Latest Location (s-live-location polling)
**Auth:** Required (only victim or approved responder with CanViewLocation=1 can access)  
**Response:** `ApiResponse<DynamicRow>` — `{ latitude, longitude, accuracy, loggedAt }`

---

### POST `/api/v1/sos/{sosIncidentId}/location` — Update Location (victim sends every ~10 sec)
**Auth:** Required  
**Request body:**
```json
{
  "latitude": 12.9716,
  "longitude": 77.5946,
  "accuracy": 15.5
}
```
**Response:** `ApiResponse`  
**Side effect:** Optionally call `SosHub.SendLocation` via `IHubContext` to push live instead of poll

---

## 7. UI Requirements — Exact Prototype Mapping

### s-sos-trigger (Entry: Profile menu → SOS Emergency Alert)
- Top bar: `#FFF0F0` background, red border-bottom, back arrow (red) → returns to `s-profile`
- Page title: "🆘 SOS Alert" (red, 14px bold)
- **Location card** (auto-detect GPS on page load): shows current lat/lng or reverse-geocoded address
- **Section label:** "Select Alert Type" (slab style)
- **4 alert type cards** (tap to select, only one active at a time):
  - Border: `2px solid var(--bd)` default → `2px solid var(--rd)` + `#FFF0F0` background when selected
  - Icon box `42×42px`, rounded 12px, `#F0F2F8` default → `#FECACA` when selected
  - Each card: icon + title (13px bold) + description (10px grey)
  
  | Icon | Title | Description |
  |------|-------|-------------|
  | 🆘 | SOS Alert | Immediate danger · Need urgent help right now |
  | 🙋 | Help Request | Need assistance · Lost, injured or stuck |
  | 🔍 | Missing Volunteer | Report a volunteer who is unreachable or missing |
  | ✅ | Safe Arrival | Confirm you have safely reached your destination |

- **Description textarea** (optional, placeholder: "Describe your situation…")
- **SEND SOS ALERT NOW** button: full-width, `var(--rd)` background, white text, 16px bold, 18px padding, 🆘 emoji, pulsing animation (`sosPulse` keyframe, box-shadow red glow)
- **On tap:** button text → "Sending SOS...", darker red `#CC2222`, then navigate to `s-sos-active`
- **API call:** `POST /api/v1/sos`

---

### s-sos-active (Victim's view — shows after trigger, or re-opens if active)
- **Header bar:** solid `var(--rd)` background, white text "🆘 SOS ACTIVE" (13px bold)
- **Incident card** (below red header): alert type emoji + type name, "Sent at HH:MM · Location"
- **Elapsed timer** (counts up in MM:SS format)
- **Responders section:**
  - Title: "Responding Members" with count badge
  - Each responder row: profile photo circle + name + responded time + status badge
  - Status = PENDING: show **APPROVE** button (small, red outlined) → calls `PUT /approve-responder`
  - Status = APPROVED: show green ✓ "Approved" badge + "Can view location" note
- **Admin notification banner:** 📋 "Admin [Name] has been notified and is monitoring this SOS. Approved helpers can view your live location only after approval."
- **Primary button:** "✅ Mark as Resolved — I am Safe" (full-width, `var(--tl)` green, 12px padding) → calls `PUT /resolve` → navigates to `s-sos-resolved`
- **Secondary button:** "Cancel SOS Alert" (full-width, `#F0F2F8` grey, grey text, border) → opens `sh-sos-cancel` bottom sheet
- **SignalR:** join group `sos-{sosIncidentId}` on page open; refresh responders on `NewResponder` event

---

### sh-sos-cancel (Bottom sheet)
- **Title:** "Cancel SOS Alert ✕" (red)
- **Subtitle:** "Are you sure you want to cancel? All responders will be notified."
- **Warning box** (`#FFF0F0` bg, `#FECACA` border):
  - "⚠️ Cancelling will:" (red, bold)
  - • Stop all responders from seeing your location
  - • Notify admin that SOS was cancelled
  - • Log this incident in your profile
- **Reason dropdown:** `<select>` with options:
  - "I am safe now" (default)
  - "Alert sent by mistake"
  - "Situation resolved on its own"
  - "Other"
- **Button row:**
  - "Keep SOS Active" (outlined, flex:1) → closes sheet
  - "Cancel SOS" (red filled, flex:1) → calls `PUT /cancel` with selected reason → navigates to `s-sos-resolved`

---

### s-sos-resolved (Final confirmation screen)
- **Green circle icon** (72×72px, `#EDFAF3` bg, `var(--tl)` border 3px, ✓ SVG icon 36px teal)
- **Headline:** "You're Safe!" (bold, 20px)
- **Message:** "Your SOS has been marked as resolved. All helpers and admin have been notified. Location sharing has stopped automatically."
- **Incident summary slab:** "SOS INCIDENT SUMMARY"
  - Alert Type: [type name]
  - Duration: [calculated from CreatedAt to now]
  - Responders: [count]
  - Status: Resolved / Cancelled
- **Home button:** "Go to Home" → navigates to `s-home`
- **SignalR:** leave group on this screen

---

### s-community — SOS Alert Card (special post type)

The frontend calls `GET /api/v1/sos/active?orgId={currentOrgId}` alongside the normal community posts feed and renders active SOS incidents as special pinned cards **above** normal posts.

**Card layout:**
- **Header row:** profile photo (36px circle) + name + "🆘 SOS Alert" pill (red, `font-size:10px`) + time ago (right-aligned)
- **Sub-header:** Org name · location (approxLocation)
- **Description** (if any, max 2 lines)
- **Button row (3 equal columns):**
  - `🙋 I Can Assist` — red filled, bold 11px → calls `POST /respond` → on success: disable button, change text to "Response Sent ✓"
  - `View Details` — grey border → calls `GET /{sosIncidentId}` → shows detail sheet
  - `🗺️ Open Map` — blue (`#EFF6FF` bg, `#2563EB` text, `#BFDBFE` border) → navigates to `s-live-location`
    - **"Open Map" is DISABLED (greyed out)** until the current user's `ApprovalStatus = APPROVED` and `CanViewLocation = 1` for this incident
- **Footer line:** "X members responded · Admin notified" (10px grey)

**State management:**
- On page load: check each active SOS — has current user responded? (`SosResponders` lookup via `Sos_GetById`)
- If user already responded: "I Can Assist" → "Response Sent ✓" (disabled)
- If user is approved responder with `CanViewLocation=1`: "Open Map" enabled

---

### s-live-location (Responder/helper view)
- **Header:** red bar — back arrow (→ `s-community`) | "Live Location · SOS" (white, 12px bold)
- **Victim card** (below header): profile photo + name + "🆘 SOS Active" pill + org name + "Sent at HH:MM"
- **Map area** (full-width, ~280px height): Google Maps embed or static map centered on victim's last known lat/lng, with red SOS pin
- **Coordinates display:** lat/lng formatted (or reverse-geocoded address if available)
- **Footer note:** "Location sharing stops when [Victim Name] resolves SOS or after **1 hour** (per their Safety Preferences)."
- **Location polling:** Call `GET /api/v1/sos/{sosIncidentId}/location` every 10 seconds; update map pin
- **OR SignalR:** listen for `LocationUpdated` events on group `sos-{sosIncidentId}` — update map pin in real-time
- **On `SosResolved` SignalR event:** show "SOS Resolved — [Victim] is safe" overlay and stop polling

---

## 8. LookupTypes Required

Verify these LookupTypes and values exist in the DB (check `NGOConnect_Complete_Setup_v4.1.sql` seed data):

| TypeCode | Required ValueCodes |
|---|---|
| `SOS_ALERT_TYPE` | `SOS_ALERT`, `HELP_REQUEST`, `MISSING_VOLUNTEER`, `SAFE_ARRIVAL` |
| `SOS_STATUS` | `ACTIVE`, `RESOLVED`, `CANCELLED` |
| `SOS_RESOLVED_BY` | `SELF`, `RESPONDER`, `ADMIN` |
| `RESPONDER_STATUS` | `PENDING`, `APPROVED`, `REJECTED` |

If any are missing, add them to the seed INSERT statements in the setup SQL.

---

## 9. Implementation Order

Follow this exact sequence to avoid breaking existing code:

1. **Fix Bug 1** — `SosModels.cs` rename `ResponderId` → `SosResponderId`
2. **Fix Bug 1** — `SosDal.ApproveResponderAsync` — fix SP params
3. **Fix Bug 2** — `SosDal.ResolveAsync` — remove `p_ResolvedByLkpId`; update `ISosDal` + Controller
4. **Fix Bug 3** — `SosDal.GetByIdAsync` — read 2 result sets
5. **Fix Bug 4** — `SosModels.TriggerSosRequest` — add `OrgId`, `ApproxLocation`; update DAL
6. **Add `Sos_GetMyActive` SP** — write and run SQL (single SP, no DB schema change)
7. **Add `GetMyActiveAsync`** — `ISosDal`, `SosDal`, `SosController`
8. **Add SignalR** — `SosHub.cs`, register in `Program.cs`
9. **Inject `IHubContext<SosHub>`** into `SosDal` — broadcast on approve, resolve, cancel, respond
10. **Build + test** — `dotnet build`, test all SOS endpoints in Postman
11. **Verify LookupTypes** — check seed data for all 4 required LookupTypes
12. **Track document changes** — append to `Documents/DOCUMENTATION_GUIDELINES.md` pending list

---

## 10. Document Changes to Track (apply only on "update documents")

### API_Documentation_v4.1.docx
- `GET /api/v1/sos/my-active` — new endpoint
- `PUT /api/v1/sos/{id}/resolve` — remove request body (was ResolveSosRequest)
- `PUT /api/v1/sos/{id}/approve-responder` — request body field renamed `ResponderId` → `SosResponderId`
- `POST /api/v1/sos` — request body updated: add `orgId`, `approxLocation` fields
- SignalR hub: `/hubs/sos` — new section documenting all events

### Database_Documentation_v4.1.md
- New SP: `Sos_GetMyActive` — parameters, behaviour, result sets
- No table changes

### NGOConnect_Postman_Collection_v4.1.json
- Add `GET my-active` request
- Update `POST /sos` request body (add `orgId`, `approxLocation`)
- Update `PUT /approve-responder` body (`sosResponderId`)
- Remove body from `PUT /resolve`

---

## 11. No New Tables Required

All 3 SOS tables are already correctly defined. The only DB change is the new `Sos_GetMyActive` SP. After confirming the SP works in MySQL Workbench, add it to `NGOConnect_Complete_Setup_v4.1.sql` in the SOS SPs section and update the SP count in the file header.


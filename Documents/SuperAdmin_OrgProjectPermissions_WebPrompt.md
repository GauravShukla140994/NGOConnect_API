# Prompt: Add Org Project Permissions Toggle to Super Admin Website

Paste this prompt to Claude when you want to implement the RECURRING/FLEXIBLE permission toggles on the Super Admin website.

---

## Context

We have a Super Admin website (React) for the NGO Connect platform. We've added a plan/subscription permission gate for organisations:

- Two new columns on `Organisations` table: `CanCreateRecurring` (TINYINT default 0) and `CanCreateFlexible` (TINYINT default 0)
- The mobile app already blocks orgs from creating RECURRING/FLEXIBLE projects unless these flags are ON
- A new API endpoint lets Super Admin toggle the flags per org:

```
PATCH /super-admin/orgs/{orgId}/project-permissions
Authorization: Bearer {superAdminToken}
Content-Type: application/json

{
  "canCreateRecurring": true,
  "canCreateFlexible": false
}

Response: { "isSuccess": 1, "message": "Project permissions updated successfully." }
```

- The existing `GET /super-admin/orgs/{orgId}` (org detail) already returns `canCreateRecurring` and `canCreateFlexible` in its response (added to `Org_GetProfile` SP).

---

## Task

Add a **Project Permissions** section to the existing Super Admin **Org Detail page** (the page that shows an NGO's full profile, documents, and approval actions).

### UI Requirements

1. **Section heading**: "Project Permissions" with a brief subtitle: "Control which project types this organisation can create."

2. **Two toggle rows** (one per permission):

   | Label | Sub-label | Flag |
   |---|---|---|
   | Recurring Projects | Allow this org to create multi-session recurring projects | `canCreateRecurring` |
   | Flexible Projects | Allow this org to create open-ended flexible projects | `canCreateFlexible` |

   Each row:
   - Left: label + sub-label
   - Right: a toggle switch (React Switch or similar)
   - Current state loaded from the org detail API response
   - Toggling calls `PATCH /super-admin/orgs/{orgId}/project-permissions` with **both** current values (not just the changed one — the endpoint takes both flags together)
   - Show a loading spinner on the row being toggled while the API call is in progress
   - On success: show a brief toast/success message "Permissions updated"
   - On failure: revert the toggle to its previous state + show error toast

3. **Placement**: Place the section below the "Verification Status" section and above the "Documents" section on the org detail page. If those sections don't exist in that order, place it below the org's basic info card.

4. **Permissions guard**: Only render this section if the current Super Admin user is authenticated (the page already has auth guards, so just follow the existing pattern).

5. **No separate page/route** — this is an inline section on the existing org detail page.

### Implementation Notes

- Read existing org detail fetch to know the API call pattern and where `canCreateRecurring` / `canCreateFlexible` appear in the response
- State management: local component state is fine — two booleans, two loading booleans
- Both flags must be sent together on every PATCH (backend expects both)
- If the org detail fetch returns `canCreateRecurring: 0` / `canCreateFlexible: 0` (numeric from SP), treat as false
- Follow the existing styling conventions of the Super Admin website (colours, card styles, button styles, toast notifications)

### Files to look at first

Before writing any code, read:
1. The existing org detail page component to understand structure and API call pattern
2. The existing API service file for Super Admin calls to understand the axios/fetch setup and auth token pattern
3. Any existing toggle or switch component already used in the project

Then implement the section.

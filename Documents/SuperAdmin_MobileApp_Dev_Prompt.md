# NGO Connect — Mobile App Changes for the Super Admin Module: Complete Development Prompt

> **Version:** v1.0
> **Date:** 2026-07-11
> **Scope:** Everything the Android/iOS (React Native) app needs so a founder or member correctly experiences the new Super Admin review flow — org rejection + resubmission, profile verification requests, account suspension.
> **Not verified against real code:** the mobile app repo was not available in the session that produced this document. Every instruction below names the *screen/flow* by its known behavior, not an exact file path. **First step for whoever implements this: locate the actual files** (My Organisations screen, Notifications screen/list component, auth/login flow, `AppConfig.ts`) and confirm names before editing — do not guess file paths from this document.
> **Companion docs:** `SuperAdmin_Backend_Dev_Prompt.md` and `ADMIN_PANEL_IMPLEMENTATION_PROMPT.md` (both cover the API/DB and web admin sides of this same feature set). Some items below depend on backend work marked "not yet built" there — see Section 5.

---

## 1. Why the Mobile App Needs Changes at All

Super Admin can now, from the web admin panel, take four actions that a founder or member will directly experience inside the app:
1. **Reject** a submitted organisation, with a reason
2. **Suspend** an organisation (already-approved orgs can be taken offline)
3. **Request a profile update** from a member (their submitted documents/info needs correction) — *backend not yet built, see Section 5*
4. **Suspend a member's account** — *backend not yet built, see Section 5*

The app currently has no UI concept of "rejected, please fix and resubmit" or "your profile needs an update" — those are new states introduced by this module.

---

## 2. Organisation Status — Use the Real Values Everywhere

Real `ORG_STATUS` lookup values (verified from actual seed data): `PENDING`, `UNDER_REVIEW`, `APPROVED`, `REJECTED`, `SUSPENDED`. If the app currently shows a binary Active/Inactive style badge anywhere in the "My Organisations" flow, replace it with these five, each with its own color/badge treatment. `Org_List`/`Org_ListRecommended` already filter to `APPROVED` only for public listings, so `SUSPENDED` orgs disappearing from public/explore views requires zero backend change — only confirm the founder's own "My Organisations" screen (which shows the founder's own orgs regardless of public visibility) still displays a `SUSPENDED` org with a clear status badge and explanation, rather than hiding it or erroring.

---

## 3. Organisation Resubmission Flow (backend already live — `PUT /org/{orgId}/resubmit`)

**Where:** the founder's "My Organisations" screen/detail view.

**When status = `REJECTED`:**
- Show the rejection reason prominently (fetch from the org detail endpoint the app already uses — the reason is stored in the new `OrgStatusHistory` table server-side and should be surfaced through the existing org-detail response; confirm with backend whether `lastReason`/similar field was added to the org-detail SP the app already calls, or whether a new field needs to be exposed there)
- Show a **"Resubmit"** button
- Tapping it opens the existing org-edit form (reuse whatever screen already lets a founder edit org details — do not build a new form) pre-filled with current values
- On submit, call `PUT /org/{orgId}/resubmit` (new endpoint, `ResubmitOrgRequest` body — mirrors the existing update-org request fields, `OrgName` required, everything else optional) instead of whatever update endpoint is normally used
- On success: status returns to `PENDING`, show a confirmation ("Resubmitted — pending review again") and navigate back to the org detail/status screen

**When status = `SUSPENDED`:** read-only — no resubmit action. Show the reason and a note to contact support if the founder disputes it (Super Admin manual suspend is for-cause: fraud, complaint, dormancy — not something a founder self-resolves by resubmitting).

---

## 4. Notifications — New Types to Handle

The backend inserts rows into the existing `Notifications` table for these events (confirm exact `NotificationType`/`ValueCode` strings with the backend once built — likely candidates below). If the app's notification list already renders generically by title/body text regardless of type (check this first — many apps do), no code change is needed beyond confirming the generic renderer doesn't choke on an unrecognized type code. If the app maps specific types to specific icons/colors/deep-links, add these:

| Type | Triggered by | Suggested icon/treatment | Suggested deep-link |
|---|---|---|---|
| `ORG_APPROVED` | Super Admin approves | ✅ green | Org detail screen |
| `ORG_REJECTED` | Super Admin rejects | ❌ red | Org detail screen (resubmit CTA visible) |
| `ORG_SUSPENDED` | Super Admin suspends | ⚠️ orange | Org detail screen |
| `ORG_REACTIVATED` | Super Admin reactivates | ✅ green | Org detail screen |
| `PROFILE_NEEDS_UPDATE` | Super Admin requests member update — *not yet built* | 📝 yellow | Profile/edit-profile screen |
| `PROFILE_VERIFIED` | Super Admin verifies member — *not yet built* | ✅ green | Profile screen |
| `ACCOUNT_SUSPENDED` | Super Admin suspends member — *not yet built* | 🚫 red | none (informational only) |
| `ACCOUNT_REACTIVATED` | Super Admin reactivates member — *not yet built* | ✅ green | none |

---

## 5. Items That Depend on Not-Yet-Built Backend Work

These three cannot be finished until `SuperAdmin_Backend_Dev_Prompt.md` Section 2 (member/user admin module) ships. Safe to scaffold the UI now, but hold off wiring/testing:

1. **Profile "needs update" banner** — if a member's profile verification status is `NEEDS_UPDATE`, show a persistent banner on their Profile screen with the reason, linking to edit-profile / re-upload-documents. Requires the new `Users.ProfileVerificationLkpId` field to be exposed on whatever endpoint the app calls to load its own profile.
2. **Suspended-account handling** — if Super Admin suspends a member's account, the app needs to handle this gracefully at the auth layer. **Important open question flagged in the backend prompt:** it's not yet confirmed whether `Users.IsActive` is actually checked anywhere in the login/OTP-verify SP chain. Until backend confirms that check exists (or adds it), a "suspended" member may still be able to log in with no visible effect — this is a backend gap, not a mobile one, but the mobile team should insist on a clear, specific error message/screen ("Your account has been suspended — contact support") for whatever error code the backend eventually returns for this case, rather than a generic login-failure toast.
3. **Verified profile badge** — cosmetic addition to the Profile screen once `PROFILE_VERIFIED` exists.

---

## 6. Suggested Release Packaging

This is a small, self-contained batch of UI changes (status badges, one new button + form reuse, notification type additions) — a good first candidate for finally wiring up `react-native-code-push` (already installed per earlier project notes, v9.0.1, never activated). Worth raising with the user once this batch is ready: ship it as the first CodePush-delivered update instead of a full store release, as a low-risk way to validate the CodePush setup end-to-end.

---

## 7. Implementation Order

1. Locate the real files (My Organisations screen, org detail screen, notification list/renderer, `AppConfig.ts` or equivalent) — confirm names before editing anything
2. Update org status badge rendering to the 5 real status codes (Section 2)
3. Add rejection-reason display + Resubmit button + wire to `PUT /org/{orgId}/resubmit` (Section 3)
4. Confirm/add notification type handling for the 4 org-related types already live (Section 4)
5. Scaffold (do not fully wire) the profile-needs-update banner and suspended-account error screen (Section 5) — revisit once backend Section 2 ships
6. Test against staging API (`https://ngoconnectapi-staging.up.railway.app/api/v1`, already the app's configured Stage `BASE_URL`)
7. Once verified, propose to the user bundling this as the first CodePush release (Section 6)

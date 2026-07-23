# Mobile App Add-On — Marketing & Communication Center, Phase 1

## Context

RippleHub's Super Admin panel just shipped Phase 0 + Phase 1 of a new "Marketing & Communication Center" — a tool for Super Admins to broadcast Push + Email campaigns to segments of users (all users, recently active, inactive, new signups, members of specific NGOs, or by role/donor status). The backend (ASP.NET Core + MySQL) and the Super Admin web UI are both built and working.

**This is a pure add-on to the mobile app.** It must not disturb, refactor, or change behavior for anything that already exists — existing notification types (SOS alerts, project updates, donation alerts, org invites, community posts, etc.) must keep working exactly as they do today. We're only adding a new notification type on top.

## Step 1 — Read before writing anything

Before implementing anything, read and understand the app's existing notification handling end to end:

1. Which FCM/push library is in use (`@react-native-firebase/messaging`, `expo-notifications`, `notifee`, or something else).
2. Where device tokens are registered with the backend.
3. How the app currently handles a notification tap — specifically, wherever it reads a `notifType` field from the payload and switches/branches on it to decide what screen to open. This almost certainly already exists for SOS/project/donation/etc. notification types — find that exact code.
4. How foreground notifications are handled (i.e., when the app is open and a push arrives) versus background/killed-state notifications — these are often two separate code paths in RN push libraries.
5. How deep-linking / in-app navigation currently works (React Navigation linking config, or a custom resolver) — this determines what format a "deep link" string needs to be in in this app.

Report back briefly on what you find for 1-4 before writing code, so the actual implementation matches how this app already does things rather than introducing a second pattern.

## Step 2 — What the backend now sends for a campaign push

A campaign push arrives as a standard FCM message shaped like this:

```json
{
  "notification": {
    "title": "<campaign push title>",
    "body": "<campaign push body>",
    "image": "<PushImageUrl, only if the campaign set one>"
  },
  "data": {
    "notifType": "CAMPAIGN",
    "refId": "<campaignId, as a string>",
    "refType": "Campaign",
    "deepLink": "<PushDeepLink, only if the campaign set one>",
    "actionLabel": "<PushActionLabel, only if the campaign set one>"
  }
}
```

Notes:
- `notifType`/`refId`/`refType` follow the exact same convention already used by every other notification type in this app — this should slot into the existing switch/handler with a new case, not a new mechanism.
- `image` is set on FCM's native notification object (not just a data field), so Android/iOS render it automatically in the system tray for background/killed-app notifications with zero app code. The only thing to check: if there's a custom local-notification renderer for the foreground case (e.g. via `notifee`), make sure that path also reads and displays the image — otherwise foregrounded users won't see it even though backgrounded users do.
- `deepLink` and `actionLabel` are plain strings, free-typed by the Super Admin in the campaign wizard — there is no enforced format on the backend. Confirm what format this app's router/deep-link resolver actually expects (a custom scheme like `ripplehub://project/123`, an internal path, a full URL, etc.) and document it, since that's what Super Admins need to type correctly.

## Step 3 — What to add

1. Add a `CAMPAIGN` case to the existing notifType tap-handler:
   - Parse `refId` (campaign ID) from the data payload.
   - If `deepLink` is present, navigate using it via the app's existing deep-link/navigation mechanism.
   - If `deepLink` is absent, fall back to some sensible default screen (e.g. a notifications list or generic campaign-detail screen) rather than doing nothing.
2. If `actionLabel` is present, pass it as a navigation param to the destination screen and have that screen render it as an in-app call-to-action button/banner (e.g. "Donate Now"). This is deliberately **not** a native notification action button — no per-platform notification-category/action registration needed, keep this simple.
3. Verify/fix foreground image display per the note in Step 2 if applicable.

## Step 4 — Separate add-on: Communication Preferences screen

There's no way for a user to opt out of promotional pushes/emails yet. Build a simple screen (inside Profile/Settings) with six toggles, wired to:

- `GET /api/v1/communication-preferences` (any authenticated user, existing JWT) → returns:
  ```json
  { "userId": 123, "receivePushNotifications": true, "receivePromotionalEmails": true,
    "receivePromotionalSms": true, "receiveNgoUpdates": true,
    "receiveDonationAlerts": true, "receiveVolunteerOpportunities": true }
  ```
  (no row yet for a user = all default to `true`, so a brand-new user is reachable by default)
- `PUT /api/v1/communication-preferences` with any subset of the same six boolean fields — omit a field to leave it unchanged, only send the ones the user actually toggled.

## Step 5 — Separate issue, noticed while testing this feature (possibly pre-existing, unrelated to the campaign work)

Every push notification currently showing in the system notification tray only displays a **date**, not the actual delivery/received **time**. It should show the precise time the notification arrived — e.g. "10:34 PM" — the way most apps' notifications do. Please investigate why (likely candidates: the notification's `when`/timestamp isn't being explicitly set by whichever push/notification library this app uses, or `showWhen` is off, or there's custom formatting somewhere that only renders the date) and fix it so all notifications — existing types and the new CAMPAIGN type alike — show an accurate delivery time. This is worth fixing regardless of whether it's connected to this feature, since it affects every notification the app has ever sent.

## Reminder

Everything above is additive. Do not refactor the existing notification handler, change the payload shape/behavior for any existing `notifType`, or touch code paths unrelated to what's listed here.

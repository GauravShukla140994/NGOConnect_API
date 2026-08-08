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

## Addendum (2026-07-30) — payload shape changed + new delivery-acknowledgment call required

Two things changed on the backend since Step 2 above was written. Both apply to **every** notification type, not just CAMPAIGN — this is describing the current actual payload shape, not a CAMPAIGN-specific change.

### 1. Android is now data-only; iOS is unchanged

Root cause of the "wrong/frozen date" bug from Step 5: FCM's own auto-display on Android was using its own `event_time`, and racing with this app's notifee-based rendering, sometimes showing two notifications or the wrong timestamp. Fix applied backend-side: `Message.Notification` / `AndroidConfig.Notification` were removed entirely from the FCM message the backend sends. Android now **only** gets a `data` payload — there is no top-level `notification` block anymore, so Android's OS-level auto-display no longer fires at all. Every Android notification must now be rendered by this app's own notifee code, reading title/body/image from `data`, e.g.:

```json
{
  "data": {
    "notifType": "CAMPAIGN",
    "refId": "<campaignId>",
    "refType": "Campaign",
    "title": "<push title>",
    "body": "<push body>",
    "imageUrl": "<PushImageUrl, only if set>",
    "deepLink": "<PushDeepLink, only if set>",
    "actionLabel": "<PushActionLabel, only if set>",
    "campaignRecipientId": "<CampaignRecipientId, as a string — new, see below>"
  }
}
```

iOS keeps getting a native `aps.alert` (title/body) so it continues to display via the OS as before — no change needed on the iOS side. If your notifee/render code currently falls back to `remoteMessage.notification` first and `remoteMessage.data` second, flip that priority for Android (data first) since `remoteMessage.notification` will now be empty/undefined for Android. This should already be handled if you applied the FCMService.cs-side fix described earlier in this thread; this section is just documenting the final payload shape for reference.

This same `title`/`body`/`imageUrl` triad is now present in `data` for every notification type this backend sends (not only CAMPAIGN) — if other notifType handlers were written assuming `remoteMessage.notification` is always populated on Android, they need the same fallback-order fix, not just the CAMPAIGN case.

### 2. New: call the delivery-acknowledgment endpoint when a CAMPAIGN notification actually renders

"Delivered" in the Super Admin dashboard used to just mean "FCM accepted the send" — which is why campaigns could show "delivered" while some users never actually saw anything. There is now a real device-confirmed delivery signal, and it depends entirely on the mobile app calling this endpoint:

```
POST /api/v1/campaign-recipients/{campaignRecipientId}/delivered
Authorization: Bearer <existing JWT>
```

- `campaignRecipientId` comes from `data.campaignRecipientId` in the FCM payload shown above (present only on `notifType: "CAMPAIGN"` pushes — other notification types don't have it and don't need this call).
- Call this **the moment the app actually renders/displays the notification** — i.e. right where your notifee `displayNotification()` (or equivalent) call succeeds for a CAMPAIGN-type message, in both foreground and background/killed-state handler paths. Don't call it just because a message was *received*; call it after it's actually shown to the user, since that's what "delivered" is meant to mean.
- No request body needed. The endpoint always returns success regardless of whether the ID matched (deliberate — it's a best-effort beacon, not something that should leak whether an ID is valid). Fire-and-forget is fine; don't block notification rendering on this call's response, and don't retry aggressively on failure — a missed ack just means that one row won't show as confirmed-delivered, which is a low-stakes miss.
- This is additive — do not add this call to any existing (non-CAMPAIGN) notification type's handler.

## Reminder

Everything above is additive. Do not refactor the existing notification handler, change the payload shape/behavior for any existing `notifType`, or touch code paths unrelated to what's listed here.

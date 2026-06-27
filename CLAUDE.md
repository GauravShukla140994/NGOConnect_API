# NGO Connect — Project Instructions

## MANDATORY: Load Skill Before Any Work

**Always invoke the `software-architect-skill` at the start of every session before doing anything else.**

This skill contains all architectural decisions, database design standards, SP patterns, DAL patterns, API contracts, and the Core Mandate for the NGO Connect platform. No design, code, or documentation decision should be made without it.

## Documentation Guidelines

All project documentation is governed by `Documents/DOCUMENTATION_GUIDELINES.md`. Read it before updating any of the 4 maintained documents:

- `Documents/NGOConnect_Complete_Setup_v4.1.sql`
- `Documents/API_Documentation_v4.1.docx`
- `Documents/NGOConnect_Postman_Collection_v4.1.json`
- `Documents/Database_Documentation_v4.1.md`

Key rules:
- Never update documents mid-task — accumulate all changes and apply only when the user says "update documents"
- Before applying any update, assess scope (Minor / Significant / Major) and ask for confirmation: update in-place or create new version?
- Minor changes (typo, wording, missing description) → update current file in-place, no version bump
- Significant changes (new endpoint, SP param change, model field change) → ask before bumping version
- Uploaded SP files are the highest source of truth — they override the setup SQL

## Prototype Reference

The approved UI prototype is `Documents/NGO_Connect_Final_v1.6.html` — this is the design baseline for all API and DB work. Any new feature or screen must trace back to this prototype or be explicitly discussed and approved before implementation.

### 38 Screens in v1.6 (Screen ID → Purpose)

**Auth**
- `s-login` — Login / Welcome (mobile + email)
- `s-otp` — OTP verification

**Volunteer / User Screens**
- `s-home` — Home feed (posts, announcements)
- `s-all-opps` — All volunteer opportunities (filterable)
- `s-all-projects` — My projects (Applied / Upcoming / Completed)
- `s-explore` — Explore NGOs (by category)
- `s-ngo` — NGO public profile + Join request
- `s-proj-vol` — Project detail (volunteer view)
- `s-join-form` — Membership application form (4 steps)
- `s-impact` — My Impact profile (hours, score, badges)
- `s-community` — Community feed (members-only posts, polls)
- `s-profile` — My profile (stats, NGOs, activity)
- `s-edit-profile` — Edit profile (5-step wizard)
- `s-my-orgs` — My organisations + Create new NGO
- `s-donate` — Donate to NGO (campaign overview)
- `s-donation-payment` — Payment step (amount + method)
- `s-donation-success` — Donation confirmation + receipt
- `s-my-donations` — My donation history (History / Recurring / Receipts / NGOs tabs)

**SOS**
- `s-sos-trigger` — Trigger SOS alert
- `s-sos-active` — Active SOS (live responders, timer)
- `s-sos-resolved` — SOS resolved confirmation
- `s-live-location` — Live location map (helper view)

**NGO Admin Screens**
- `s-admin` — NGO dashboard (overview stats)
- `s-admin-proj` — Projects list (Active / Upcoming / Completed / Cancelled)
- `s-proj-detail` — Project detail (admin view, edit/cancel)
- `s-create-proj` — Create project wizard (5 steps: info → schedule → skills → visibility → publish)
- `s-participants` — Project participants (Approved / Pending / No-show / Attended)
- `s-vol-profile` — Volunteer profile (admin view — ratings, badges, reliability)
- `s-admin-vols` — All volunteers (Members / Pending / Posts tabs)
- `s-admin-comm` — Community posts admin (pin, announce)
- `s-admin-org` — Organisation profile editor
- `s-member-impact` — Member impact detail (admin view)
- `s-create-org` — Create Organisation wizard (4 steps)

**Admin — Donations**
- `s-admin-donations` — Donation dashboard (live stats)
- `s-admin-campaigns` — Campaigns list + create
- `s-admin-donors` — Donor list (All / Recurring / Top)
- `s-admin-transactions` — Transaction history (filter by status)
- `s-admin-withdrawal` — Withdrawal requests + available balance

### Key Design Decisions from Prototype
- Project schedules: One-time, Recurring (specific days/time), Open/Flexible
- Google Maps pin per project (separate from text address)
- Skills per project — each rated individually by admin + volunteers
- Participant tracker: Approved / Pending / No-show / Attended states
- Reliability score: private to NGO admins only (not public on volunteer profile)
- No-show: can be marked "excused" by admin to prevent unfair penalties
- Donation readable IDs: DON-2026-000001 format
- 80G eligibility shown on NGO donate screen
- Community posts: Announcements (📢), Polls, General — with pin option

## Project Stack (Quick Reference)

- ASP.NET Core 8, C#, MySQL 8.0
- Architecture: Controller → Interface → DAL (inherits BaseDal) → Stored Procedure
- No EF Core — ADO.NET + Stored Procedures only
- API standard: `ApiResponse<T>` with IsSuccess, Message, Data, ErrorCode
- All config via Settings table + SettingsCache (never appsettings.json)
- All lookups via LookupTypes + LookupValues (never hardcoded enums)

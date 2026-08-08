-- ============================================================
-- NGO Connect — Community Posts Test Data
-- Version: 1.0  |  Date: 2026-07-04
-- ============================================================

USE ngoconnect;   -- ← database name from appsettings.Development.json
-- Tests all 8 post types: ANNOUNCEMENT, DISCUSSION, QUESTION,
-- POLL, EVENT_UPDATE, VOL_REQUEST, TASK, RESOURCE
--
-- Users in test:
--   User 1 = Gaurav Shukla  (Founder / Admin)
--   User 2 = Priya Sharma   (Teacher / Volunteer)
--   User 3 = Rahul Mehta    (Donor / Member)
--   User 4 = Test User 4    (Member)
--
-- BEFORE RUNNING:
--   1. Confirm OrgId 1 exists  (Green Future NGO from seed)
--   2. Confirm Users 1–4 exist in Users + UserProfiles tables
--   3. Run Section A (OrgMembers) only if users 2–4 are not
--      already members of Org 1
--
-- KNOWN FRONTEND ISSUES TO VERIFY WHILE TESTING:
--   [!] SP returns column "AuthorName" but CommunityScreen reads
--       item.fullName — author names will be blank until SP is
--       updated to alias as "FullName"
--   [!] DB post type code is "VOL_REQUEST" but CommunityScreen
--       TYPE_META key is "VOLUNTEER_REQUEST" — that card will
--       fall back to default DISCUSSION styling (no colored chip)
-- ============================================================

SET @orgId = 1;   -- Green Future NGO  (change if your OrgId differs)
SET @user1 = 1;   -- Gaurav Shukla  — Founder / Admin
SET @user2 = 2;   -- Priya Sharma   — Teacher / Volunteer
SET @user3 = 3;   -- Rahul Mehta    — Donor / Member
SET @user4 = 4;   -- Test User 4    — Member

-- ============================================================
-- SECTION A: OrgMembers — ensure all 4 users are APPROVED members
-- Safe to re-run; INSERT IGNORE skips duplicates
-- ============================================================

INSERT IGNORE INTO OrgMembers
    (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
SELECT
    @orgId, @user2,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_ROLE'   AND lv.ValueCode = 'VOLUNTEER'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'),
    1, 1, 1, 10, NOW(), @user1;

INSERT IGNORE INTO OrgMembers
    (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
SELECT
    @orgId, @user3,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_ROLE'   AND lv.ValueCode = 'VOLUNTEER'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'),
    1, 1, 1, 10, NOW(), @user1;

INSERT IGNORE INTO OrgMembers
    (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
SELECT
    @orgId, @user4,
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_ROLE'   AND lv.ValueCode = 'VOLUNTEER'),
    (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'),
    1, 1, 1, 10, NOW(), @user1;

-- ============================================================
-- SECTION B: Resolve LookupValueIds  (safe — subqueries)
-- ============================================================

-- Post types
SET @lkp_announcement = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'ANNOUNCEMENT');
SET @lkp_discussion   = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'DISCUSSION');
SET @lkp_question     = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'QUESTION');
SET @lkp_poll         = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL');
SET @lkp_event        = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'EVENT_UPDATE');
SET @lkp_vol_request  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'VOL_REQUEST');
SET @lkp_task         = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'TASK');
SET @lkp_resource     = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'RESOURCE');

-- Audience
SET @aud_all     = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS');
SET @aud_admins  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ADMINS_ONLY');
SET @aud_vols    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'VOLUNTEERS');

-- Task status
SET @task_open   = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'TASK_STATUS' AND lv.ValueCode = 'OPEN');
SET @task_wip    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'TASK_STATUS' AND lv.ValueCode = 'IN_PROGRESS');

-- ============================================================
-- SECTION C: Community Posts
-- Order: pinned first, then newest → oldest (mirrors feed order)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- POST 1 · ANNOUNCEMENT · Pinned · Author: User 1 (Gaurav)
-- UI check: purple chip "PINNED ANNOUNCEMENT", pinned at top,
--           Acknowledge button, badge count shows 3
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, AcknowledgeCount,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_announcement, @aud_all,
    'Welcome to the NGO Connect Community! 📢',
    'We are excited to launch our official community space for all Green Future NGO members.\n\nThis is your space to:\n• Share project updates and success stories\n• Ask questions and get help from fellow volunteers\n• Vote on important decisions via polls\n• Stay updated on events and announcements\n\nPlease read the Community Guidelines pinned in Resources and acknowledge this post to confirm you have received it. Looking forward to an amazing journey together! 🌱',
    1, 3,
    @user1, NOW() - INTERVAL 7 DAY
);
SET @p1 = LAST_INSERT_ID();

-- 3 acknowledgements (users 2, 3, 4 have acked — user 1 is the author)
INSERT INTO CommunityPostAcknowledgements (CommunityPostId, UserId, AcknowledgedAt) VALUES
    (@p1, @user2, NOW() - INTERVAL 6 DAY),
    (@p1, @user3, NOW() - INTERVAL 5 DAY),
    (@p1, @user4, NOW() - INTERVAL 4 DAY);

-- ────────────────────────────────────────────────────────────
-- POST 2 · ANNOUNCEMENT · Not pinned · Author: User 1
-- UI check: same purple chip but NOT at top (not pinned),
--           Acknowledge button, badge shows 1
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, AcknowledgeCount,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_announcement, @aud_all,
    'Monthly Volunteer Meetup — July 15th, 2026',
    'Our monthly virtual meetup is scheduled for Tuesday, July 15th at 6:00 PM IST.\n\nAgenda:\n1. June project review and attendance certificates\n2. Upcoming August project preview\n3. New volunteer orientation Q&A\n4. Open floor\n\nZoom link will be shared 1 hour before. Please acknowledge if you plan to attend so we can arrange breakout rooms accordingly.',
    0, 1,
    @user1, NOW() - INTERVAL 4 DAY
);
SET @p2 = LAST_INSERT_ID();

INSERT INTO CommunityPostAcknowledgements (CommunityPostId, UserId, AcknowledgedAt) VALUES
    (@p2, @user2, NOW() - INTERVAL 3 DAY);

-- ────────────────────────────────────────────────────────────
-- POST 3 · DISCUSSION · Author: User 2 (Priya)
-- UI check: gray chip "DISCUSSION", no special widgets,
--           long content tests text truncation (5 lines)
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, CreatedBy, CreatedAt)
VALUES (
    @orgId, @user2, @lkp_discussion, @aud_all,
    'My experience from the Cubbon Park Tree Plantation Drive',
    'Just returned from the most rewarding Sunday of 2026! We planted over 200 saplings at Cubbon Park in just 3 hours alongside 40 volunteers and 60 school children.\n\nWhat struck me most was the enthusiasm of the children — each one wanted to know the name of their tree, where it would grow, and what birds it would attract. One 8-year-old named his sapling "Mango Hero" and promised to visit it every month!\n\nThe logistics team deserves a special mention — gloves, water, refreshments, and even a first-aid volunteer were all arranged perfectly. Not a single person left tired.\n\nThis is exactly why I joined Green Future NGO. Has anyone else attended a plantation drive recently? Would love to hear your stories and compare notes on which park soil responds best to which sapling species.',
    0, @user2, NOW() - INTERVAL 3 DAY
);

-- ────────────────────────────────────────────────────────────
-- POST 4 · QUESTION · Author: User 3 (Rahul)
-- UI check: blue chip "QUESTION",
--           tests question-style content with no special widget
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, CreatedBy, CreatedAt)
VALUES (
    @orgId, @user3, @lkp_question, @aud_all,
    'How do I get my volunteer hours certificate?',
    'I completed the Waste Management Project (WM-2026-003) last month and my attendance is marked as "Attended" in the app. I can see the project under My Projects → Completed.\n\nHowever I have not received a volunteer certificate yet. Is it:\na) Auto-generated after a certain delay?\nb) Manually issued by the admin?\nc) Something I need to request via the app?\n\nAlso — does the 80G receipt for my donation go to the same email as my profile? Please help, I need this for my office CSR report by July 31st. Thanks!',
    0, @user3, NOW() - INTERVAL 2 DAY
);

-- ────────────────────────────────────────────────────────────
-- POST 5 · POLL · Author: User 1 · Single-choice · Expires 7 days
-- UI check: teal chip "POLL", PollView widget renders,
--           progress bars show vote percentages,
--           Option 2 has most votes (should have widest bar)
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, PollEndsAt, PollIsMultiChoice,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_poll, @aud_all,
    'When should we schedule weekend volunteer sessions?',
    'We are planning the Q3 volunteer calendar and want to pick timeslots that suit the most members. This is a single-choice poll — please vote for the slot that works best for you on a typical Saturday.',
    0, NOW() + INTERVAL 7 DAY, 0,
    @user1, NOW() - INTERVAL 1 DAY
);
SET @p5 = LAST_INSERT_ID();

-- Poll options with pre-seeded vote counts (total = 20 votes)
INSERT INTO PollOptions (CommunityPostId, OptionText, VoteCount, SortOrder) VALUES
    (@p5, 'Early Morning (6:00 AM – 9:00 AM)',    4,  1),
    (@p5, 'Morning (9:00 AM – 12:00 PM)',         9,  2),
    (@p5, 'Afternoon (1:00 PM – 4:00 PM)',        3,  3),
    (@p5, 'Evening (5:00 PM – 8:00 PM)',          4,  4);

-- Votes from our 4 users (one vote each — single-choice poll)
SET @opt5_1 = (SELECT PollOptionId FROM PollOptions WHERE CommunityPostId = @p5 AND SortOrder = 1);
SET @opt5_2 = (SELECT PollOptionId FROM PollOptions WHERE CommunityPostId = @p5 AND SortOrder = 2);
SET @opt5_3 = (SELECT PollOptionId FROM PollOptions WHERE CommunityPostId = @p5 AND SortOrder = 3);
SET @opt5_4 = (SELECT PollOptionId FROM PollOptions WHERE CommunityPostId = @p5 AND SortOrder = 4);

INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId) VALUES
    (@opt5_2, @p5, @user1),   -- Gaurav → Morning
    (@opt5_2, @p5, @user2),   -- Priya  → Morning
    (@opt5_1, @p5, @user3),   -- Rahul  → Early Morning
    (@opt5_4, @p5, @user4);   -- User4  → Evening

-- ────────────────────────────────────────────────────────────
-- POST 6 · POLL · Multi-choice · Author: User 2 · Expired
-- UI check: teal "POLL" chip, expired poll,
--           multiple options can be voted, tests isMultiChoice flag
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, PollEndsAt, PollIsMultiChoice,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user2, @lkp_poll, @aud_all,
    'Which skills should our next workshop cover? (Pick all that apply)',
    'We are planning a Skills Development Workshop for volunteers in August. This is a multi-choice poll — please select ALL topics you would like to see covered. Results will guide the agenda.',
    0, NOW() - INTERVAL 1 DAY, 1,
    @user2, NOW() - INTERVAL 5 DAY
);
SET @p6 = LAST_INSERT_ID();

INSERT INTO PollOptions (CommunityPostId, OptionText, VoteCount, SortOrder) VALUES
    (@p6, 'First Aid & Emergency Response', 12, 1),
    (@p6, 'Fundraising & Grant Writing',     8, 2),
    (@p6, 'Social Media for NGOs',          15, 3),
    (@p6, 'Field Documentation & Reporting', 6, 4);

-- ────────────────────────────────────────────────────────────
-- POST 7 · EVENT_UPDATE · Author: User 2 · Has EventRef
-- UI check: green chip "EVENT UPDATE",
--           content has rescheduling info, tests EventRef field
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, EventRef,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user2, @lkp_event, @aud_all,
    '🔄 Update: River Clean-Up Drive rescheduled to July 20th',
    'Due to IMD heavy rainfall warning for Delhi NCR this weekend, the Yamuna River Clean-Up Drive has been rescheduled.\n\n📅 New Date: Sunday, July 20th, 2026\n⏰ Time: 7:00 AM – 11:00 AM (unchanged)\n📍 Location: Yamuna Ghat, Sector 5 (unchanged)\n🚌 Pickup: Metro Station Exit 2 at 6:30 AM\n\nAll registered volunteers will receive a confirmation SMS by Friday evening. No re-registration needed — your slot is held.\n\nApologies for the short notice. Safety of our volunteers comes first. See you on the 20th! 💚',
    0, 'PROJ-2026-007',
    @user2, NOW() - INTERVAL 18 HOUR
);

-- ────────────────────────────────────────────────────────────
-- POST 8 · VOL_REQUEST · Author: User 1 · Has VolunteersNeeded
-- UI check: ⚠️ KNOWN BUG — DB code "VOL_REQUEST" does not match
--           frontend TYPE_META key "VOLUNTEER_REQUEST"
--           → card will render with default DISCUSSION gray chip
--           Fix: update CommunityScreen TYPE_META to use key 'VOL_REQUEST'
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, VolunteersNeeded,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_vol_request, @aud_all,
    '🙋 Need 5 volunteers: School Awareness Camp — July 18th',
    'We are conducting an Environmental Awareness Camp at Delhi Public School, Dwarka on July 18th, 2026 from 9:00 AM to 1:00 PM.\n\nActivities:\n• Classroom presentations on climate change (Grades 6–8)\n• Tree sapling distribution and planting in school garden\n• Eco-quiz competition and judging\n• Certificate distribution ceremony\n\nSkills needed: Good communication, comfortable interacting with children. No technical expertise required — enthusiasm is enough!\n\n📌 Lunch will be provided. Transport reimbursement available.\nReply below or contact admin directly to confirm your slot. First come, first served!',
    0, 5,
    @user1, NOW() - INTERVAL 10 HOUR
);

-- ────────────────────────────────────────────────────────────
-- POST 9 · TASK · Author: User 1 · Assigned to User 3 · Due in 6 days
-- UI check: amber chip "TASK ASSIGNMENT",
--           shows AssignedToName, DueDate, TaskStatus = OPEN
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, AssignedToUserId, DueDate, TaskStatusLkpId,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_task, @aud_admins,
    'Prepare volunteer attendance report — June 2026',
    'Please compile the attendance data from all June 2026 projects into the standard monthly report template.\n\nRequired columns: Volunteer Name | Project | Date | Hours Logged | Status (Attended / No-Show / Excused)\n\nTemplate: Available in the Admin Google Drive > Reports > 2026 > Monthly-Template.xlsx\n\nOnce ready, upload it to the same folder and post the link as a Resource post in this community.\n\nDeadline: July 10th, 2026. Ping admin if you need access to any project attendance data.',
    0, @user3, NOW() + INTERVAL 6 DAY, @task_open,
    @user1, NOW() - INTERVAL 5 HOUR
);

-- ────────────────────────────────────────────────────────────
-- POST 10 · TASK · Author: User 1 · Assigned to User 2 · In Progress
-- UI check: amber chip, TaskStatus = IN_PROGRESS for variety
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, AssignedToUserId, DueDate, TaskStatusLkpId,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user1, @lkp_task, @aud_admins,
    'Draft Q3 project calendar and share for review',
    'Please draft the volunteer project calendar for July–September 2026 based on the approved activity plan.\n\nInclude: Project name, category, tentative date, location, estimated volunteers needed, and lead coordinator.\n\nShare as a Google Sheet and post the link here once the first draft is ready for admin review.',
    0, @user2, NOW() + INTERVAL 3 DAY, @task_wip,
    @user1, NOW() - INTERVAL 2 HOUR
);

-- ────────────────────────────────────────────────────────────
-- POST 11 · RESOURCE · Author: User 4 · Has ResourceFileUrl
-- UI check: gray chip "RESOURCE / FILE",
--           tests ResourceFileUrl field rendering
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, ResourceFileUrl,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user4, @lkp_resource, @aud_all,
    'Volunteer Handbook 2026 — Updated (v3.1)',
    'Sharing the updated Volunteer Handbook for FY 2026. Key changes in this version:\n\n📌 Section 4 — SOS Emergency Protocol (new)\n📌 Section 7 — Updated 80G receipt collection procedure\n📌 Section 9 — Volunteer badge criteria (revised)\n📌 Section 11 — Code of Conduct (minor updates)\n\nAll new members must read Sections 1–3 before their first project.\nExisting volunteers: please review Section 4 (SOS) and Section 9 (badges).\n\nDownload link below. If you spot errors, raise them in the community and tag admin.',
    0, 'https://drive.google.com/file/d/ngo-connect-volunteer-handbook-2026-v3',
    @user4, NOW() - INTERVAL 1 HOUR
);

-- ────────────────────────────────────────────────────────────
-- POST 12 · RESOURCE · Author: User 3 · Admins Only audience
-- UI check: tests ADMINS_ONLY audience visibility filtering
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, ResourceFileUrl,
     CreatedBy, CreatedAt)
VALUES (
    @orgId, @user3, @lkp_resource, @aud_admins,
    '[Admin Only] June Financial Report — Donations & Expenses',
    'Uploading the June 2026 financial summary for admin review before the board meeting.\n\nContents: Donation inflows, campaign-wise breakdown, operational expenses, volunteer transport reimbursements, and net balance.\n\nDo not share externally. Raise queries in this thread or directly with the treasurer.',
    0, 'https://drive.google.com/file/d/admin-june-2026-financial-report',
    @user3, NOW() - INTERVAL 45 MINUTE
);

-- ────────────────────────────────────────────────────────────
-- POST 13 · DISCUSSION · Author: User 4 · Volunteers Only audience
-- UI check: tests VOLUNTEERS audience filter,
--           also tests the most-recent post appearing at top of feed
-- ────────────────────────────────────────────────────────────
INSERT INTO CommunityPosts
    (OrgId, UserId, PostTypeLkpId, AudienceLkpId,
     Title, Content,
     IsPinned, CreatedBy, CreatedAt)
VALUES (
    @orgId, @user4, @lkp_discussion, @aud_vols,
    'Tip: How to track your volunteer hours in the app',
    'Quick tip for new members — the Impact screen in the app shows your total logged hours, projects completed, impact score, and badges earned in real time.\n\nIt updates automatically once the project admin marks attendance. You do not need to log hours manually.\n\nI just hit 50 hours and received the Silver Volunteer badge this week! 🏅 Check yours and share your milestone in the comments — would love to celebrate together.',
    0, @user4, NOW() - INTERVAL 20 MINUTE
);

-- ============================================================
-- SECTION D: VERIFICATION QUERY
-- Run this after the inserts to confirm everything looks correct
-- ============================================================
SELECT
    cp.CommunityPostId                                          AS PostId,
    lv.ValueCode                                               AS PostType,
    av.ValueCode                                               AS Audience,
    cp.UserId                                                  AS AuthorId,
    CONCAT(up.FirstName, ' ', up.LastName)                     AS AuthorName,
    LEFT(cp.Title, 50)                                         AS Title,
    cp.IsPinned,
    cp.AcknowledgeCount,
    cp.VolunteersNeeded,
    cp.PollIsMultiChoice,
    (SELECT COUNT(*) FROM PollOptions    po WHERE po.CommunityPostId = cp.CommunityPostId)         AS PollOptions,
    (SELECT COUNT(*) FROM PollVotes      pv WHERE pv.CommunityPostId = cp.CommunityPostId)         AS PollVotes,
    (SELECT COUNT(*) FROM CommunityPostAcknowledgements a WHERE a.CommunityPostId = cp.CommunityPostId) AS Acks,
    CASE WHEN cp.AssignedToUserId IS NOT NULL
         THEN CONCAT(au.FirstName, ' ', au.LastName) ELSE NULL END                                 AS AssignedTo,
    cp.TaskStatusLkpId                                         AS TaskStatusId,
    cp.ResourceFileUrl                                         AS HasFile,
    cp.CreatedAt
FROM CommunityPosts cp
JOIN LookupValues lv   ON cp.PostTypeLkpId  = lv.LookupValueId
JOIN LookupValues av   ON cp.AudienceLkpId  = av.LookupValueId
JOIN UserProfiles up   ON cp.UserId         = up.UserId
LEFT JOIN UserProfiles au ON cp.AssignedToUserId = au.UserId
WHERE cp.OrgId = @orgId AND cp.IsDeleted = 0
ORDER BY cp.IsPinned DESC, cp.CreatedAt DESC;

-- ============================================================
-- SECTION E: QUICK CLEANUP (run only if you want to reset)
-- Uncomment and run to delete all test posts for OrgId 1
-- ============================================================
-- DELETE pv FROM PollVotes pv
--   JOIN PollOptions po ON pv.PollOptionId = po.PollOptionId
--   JOIN CommunityPosts cp ON po.CommunityPostId = cp.CommunityPostId
--   WHERE cp.OrgId = @orgId;
-- DELETE po FROM PollOptions po
--   JOIN CommunityPosts cp ON po.CommunityPostId = cp.CommunityPostId
--   WHERE cp.OrgId = @orgId;
-- DELETE a FROM CommunityPostAcknowledgements a
--   JOIN CommunityPosts cp ON a.CommunityPostId = cp.CommunityPostId
--   WHERE cp.OrgId = @orgId;
-- DELETE FROM CommunityPosts WHERE OrgId = @orgId;

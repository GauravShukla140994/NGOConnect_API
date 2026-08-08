-- ============================================================
-- NGO Connect -- Test Project Seed Data
-- User: 4 (admin), Org: 2
-- 10 projects covering all status tabs + all schedule types
-- Run against: ngodb
-- ============================================================

SET @uid = 4;
SET @oid = 2;

-- Resolve all LkpIds dynamically (safe regardless of seed order)
SET @lkp_onetime   = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_TYPE'       AND lv.ValueCode = 'ONE_TIME');
SET @lkp_recurring = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_TYPE'       AND lv.ValueCode = 'RECURRING');
SET @lkp_flexible  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_TYPE'       AND lv.ValueCode = 'FLEXIBLE');

SET @lkp_active    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'     AND lv.ValueCode = 'ACTIVE');
SET @lkp_upcoming  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'     AND lv.ValueCode = 'UPCOMING');
SET @lkp_completed = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'     AND lv.ValueCode = 'COMPLETED');
SET @lkp_cancelled = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'     AND lv.ValueCode = 'CANCELLED');
SET @lkp_draft     = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_STATUS'     AND lv.ValueCode = 'DRAFT');

SET @lkp_inperson  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'LOCATION_TYPE'     AND lv.ValueCode = 'IN_PERSON');
SET @lkp_remote    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'LOCATION_TYPE'     AND lv.ValueCode = 'REMOTE');
SET @lkp_hybrid    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'LOCATION_TYPE'     AND lv.ValueCode = 'HYBRID');

SET @lkp_open      = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'  AND lv.ValueCode = 'OPEN_SIGNUP');
SET @lkp_approve   = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'  AND lv.ValueCode = 'APPROVE_REQ');
SET @lkp_slot      = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode = 'PROJECT_JOIN_TYPE'  AND lv.ValueCode = 'SLOT_PICK');

-- Sanity check: all 14 should be non-NULL before proceeding
SELECT 'ONE_TIME'    AS lkp, @lkp_onetime   AS id UNION ALL
SELECT 'RECURRING',          @lkp_recurring        UNION ALL
SELECT 'FLEXIBLE',           @lkp_flexible         UNION ALL
SELECT 'ACTIVE',             @lkp_active           UNION ALL
SELECT 'UPCOMING',           @lkp_upcoming         UNION ALL
SELECT 'COMPLETED',          @lkp_completed        UNION ALL
SELECT 'CANCELLED',          @lkp_cancelled        UNION ALL
SELECT 'DRAFT',              @lkp_draft            UNION ALL
SELECT 'IN_PERSON',          @lkp_inperson         UNION ALL
SELECT 'REMOTE',             @lkp_remote           UNION ALL
SELECT 'HYBRID',             @lkp_hybrid           UNION ALL
SELECT 'OPEN_SIGNUP',        @lkp_open             UNION ALL
SELECT 'APPROVE_REQ',        @lkp_approve          UNION ALL
SELECT 'SLOT_PICK',          @lkp_slot;

-- ============================================================
-- P1: ACTIVE | ONE_TIME | In-person | Open Signup
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, OneTimeDate, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State, Latitude, Longitude,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Weekly Tuition Drive', 'EDUCATION',
     'Free tutoring for underprivileged children in government schools. Subjects: Math, Science, English for grades 5-10.',
     @lkp_onetime, '2026-07-20', '09:00:00', '12:00:00',
     @lkp_inperson, 'Sector 12, Near Govt School', 'City Park Gate', 'Mumbai', 'Maharashtra', 19.0760, 72.8777,
     25, @lkp_open, 1, 0, 0, 0,
     @lkp_active, @uid);
SET @p1 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p1, 'Teaching'), (@p1, 'Communication'), (@p1, 'Patience');

-- ============================================================
-- P2: ACTIVE | RECURRING | In-person | Open Signup
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State, Latitude, Longitude,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Tree Plantation Campaign', 'ENVIRONMENT',
     'Weekend tree plantation in Aarey Forest. Volunteers help with digging, planting, and watering saplings.',
     @lkp_recurring, '2026-07-01', '2026-09-30', 'SAT,SUN', '07:00:00', '10:00:00',
     @lkp_inperson, 'Aarey Colony, Gate 4', 'Aarey Milk Colony', 'Mumbai', 'Maharashtra', 19.1663, 72.8526,
     40, @lkp_open, 1, 0, 0, 0,
     @lkp_active, @uid);
SET @p2 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p2, 'Gardening'), (@p2, 'Physical Fitness');

-- ============================================================
-- P3: ACTIVE | FLEXIBLE | In-person | Approval Required | 18+ | ID Required
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, FlexFromDate, FlexToDate, MinHoursRequired,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Blood Donation Support Camp', 'HEALTH',
     'Assist medical staff at blood donation drives. Flexible timing -- contribute whenever available this month.',
     @lkp_flexible, '2026-07-01', '2026-08-31', 4,
     @lkp_inperson, 'District Hospital, Ward 3', 'Civil Hospital', 'Pune', 'Maharashtra',
     30, @lkp_approve, 1, 1, 1, 0,
     @lkp_active, @uid);
SET @p3 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p3, 'First Aid'), (@p3, 'Empathy'), (@p3, 'Crowd Management');

-- ============================================================
-- P4: UPCOMING | ONE_TIME | Hybrid | Slot Pick
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, OneTimeDate, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State, GoogleMapsUrl,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Youth Leadership Workshop', 'EDUCATION',
     'Full-day leadership workshop for college students. Communication, team building, public speaking. Online slots available.',
     @lkp_onetime, '2026-08-15', '10:00:00', '17:00:00',
     @lkp_hybrid, 'Innovation Hub, Floor 2', 'T-Hub Building', 'Hyderabad', 'Telangana', 'https://meet.google.com/ngo-leadership-26',
     50, @lkp_slot, 1, 0, 0, 0,
     @lkp_upcoming, @uid);
SET @p4 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p4, 'Public Speaking'), (@p4, 'Mentoring'), (@p4, 'Leadership');

-- ============================================================
-- P5: UPCOMING | RECURRING | In-person | Open Signup
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Senior Citizen Companion Program', 'ELDERLY_CARE',
     'Weekly visits to old-age homes. Volunteers spend time with elders through reading, music, and light mobility exercises.',
     @lkp_recurring, '2026-08-01', '2026-10-31', 'WED,SAT', '14:00:00', '17:00:00',
     @lkp_inperson, 'Shanti Niwas Old Age Home', 'Kothrud', 'Pune', 'Maharashtra',
     20, @lkp_open, 1, 0, 0, 0,
     @lkp_upcoming, @uid);
SET @p5 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p5, 'Empathy'), (@p5, 'Music'), (@p5, 'Patience');

-- ============================================================
-- P6: COMPLETED | ONE_TIME | In-person (with impact summary)
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, OneTimeDate, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CompletedAt, CompletedBy, ImpactSummary, BeneficiaryCount,
     CreatedBy)
VALUES
    (@oid, 'Annual Cleanliness Drive - Juhu Beach', 'ENVIRONMENT',
     'Large-scale beach cleaning event. Volunteers collected plastic waste from Juhu Beach in a single morning session.',
     @lkp_onetime, '2026-06-05', '06:00:00', '10:00:00',
     @lkp_inperson, 'Juhu Beach, North End', 'Juhu Chowpatty', 'Mumbai', 'Maharashtra',
     80, @lkp_open, 1, 0, 0, 0,
     @lkp_completed, DATE_SUB(NOW(), INTERVAL 30 DAY), @uid,
     '78 volunteers participated. 210 kg of plastic waste collected. Beach declared clean by local municipality.', 0,
     @uid);
SET @p6 = LAST_INSERT_ID();

-- ============================================================
-- P7: COMPLETED | RECURRING | Remote | Approval Required (with impact)
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, GoogleMapsUrl,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CompletedAt, CompletedBy, ImpactSummary, BeneficiaryCount,
     CreatedBy)
VALUES
    (@oid, 'Digital Literacy for Rural Women', 'WOMENS_EMPOWERMENT',
     'Online training teaching smartphones, UPI payments, and government app usage to rural women SHG members.',
     @lkp_recurring, '2026-04-01', '2026-06-30', 'MON,WED,FRI', '18:00:00', '19:30:00',
     @lkp_remote, 'https://zoom.us/j/ngoc-digital-literacy',
     15, @lkp_approve, 1, 0, 0, 0,
     @lkp_completed, DATE_SUB(NOW(), INTERVAL 5 DAY), @uid,
     '36 sessions over 3 months. 142 women trained across 8 villages. 93% can now independently use UPI and Aadhaar services.', 142,
     @uid);
SET @p7 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p7, 'Teaching'), (@p7, 'Digital Skills'), (@p7, 'Hindi Communication');

-- ============================================================
-- P8: CANCELLED | ONE_TIME | In-person (with cancel reason)
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, OneTimeDate, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CancelledAt, CancelledBy, CancelReason,
     CreatedBy)
VALUES
    (@oid, 'Flood Relief Food Distribution', 'DISASTER_RELIEF',
     'Emergency food packet distribution for flood-affected families. Volunteers assist with packing and delivery logistics.',
     @lkp_onetime, '2026-07-10', '08:00:00', '18:00:00',
     @lkp_inperson, 'Collector Office Compound', 'District Collector Office', 'Kolhapur', 'Maharashtra',
     60, @lkp_approve, 1, 0, 0, 0,
     @lkp_cancelled, DATE_SUB(NOW(), INTERVAL 3 DAY), @uid,
     'Cancelled due to improved flood situation. Government relief agencies have taken over. All registered volunteers notified.',
     @uid);
SET @p8 = LAST_INSERT_ID();

-- ============================================================
-- P9: CANCELLED | RECURRING | In-person | High Reliability (with cancel reason)
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, RecurStart, RecurEnd, RecurDays, SessionStartTime, SessionEndTime,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CancelledAt, CancelledBy, CancelReason,
     CreatedBy)
VALUES
    (@oid, 'Rural Health Screening Camp', 'HEALTH',
     'Monthly health camps in remote tribal villages: BP check, sugar test, eye screening. MBBS student volunteers preferred.',
     @lkp_recurring, '2026-06-01', '2026-09-30', 'SUN', '09:00:00', '15:00:00',
     @lkp_inperson, 'Tribal Village Panchayat, Melghat', 'Dharni Tehsil', 'Amravati', 'Maharashtra',
     20, @lkp_approve, 1, 0, 1, 60,
     @lkp_cancelled, DATE_SUB(NOW(), INTERVAL 10 DAY), @uid,
     'Partner hospital withdrew due to staffing shortage. Will relaunch October 2026 with a new medical partner.',
     @uid);
SET @p9 = LAST_INSERT_ID();

-- ============================================================
-- P10: DRAFT | FLEXIBLE | In-person | Private (for draft/publish testing)
-- ============================================================
INSERT INTO Projects
    (OrgId, ProjectName, Category, Description,
     ProjectTypeLkpId, FlexFromDate, FlexToDate, MinHoursRequired,
     LocationTypeLkpId, AddressLine, Landmark, City, State,
     MaxVolunteers, JoinTypeLkpId, IsPublic, AgeRestriction, IdVerRequired, MinReliability,
     StatusLkpId, CreatedBy)
VALUES
    (@oid, 'Street Children Education Initiative', 'CHILD_WELFARE',
     'Informal schooling for street children near railway stations. Volunteers teach basic literacy, numeracy, and life skills.',
     @lkp_flexible, '2026-09-01', '2026-12-31', 3,
     @lkp_inperson, 'Platform 1, CST Station Area', 'CST Railway Station', 'Mumbai', 'Maharashtra',
     15, @lkp_open, 0, 0, 0, 0,
     @lkp_draft, @uid);
SET @p10 = LAST_INSERT_ID();
INSERT INTO ProjectSkills (ProjectId, SkillName) VALUES
    (@p10, 'Teaching'), (@p10, 'Child Psychology'), (@p10, 'Marathi');

-- ============================================================
-- Verification query -- shows all 10 projects with key fields
-- ============================================================
SELECT
    p.ProjectId,
    p.ProjectName,
    pt.ValueCode  AS ProjectType,
    ps.ValueCode  AS Status,
    lt.ValueCode  AS LocationType,
    jt.ValueCode  AS JoinType,
    p.City,
    p.MaxVolunteers,
    p.IsPublic,
    p.CancelledAt IS NOT NULL  AS IsCancelled,
    p.CompletedAt IS NOT NULL  AS IsCompleted,
    COUNT(sk.ProjectSkillId)   AS SkillCount
FROM Projects p
JOIN LookupValues pt ON p.ProjectTypeLkpId  = pt.LookupValueId
JOIN LookupValues ps ON p.StatusLkpId       = ps.LookupValueId
JOIN LookupValues lt ON p.LocationTypeLkpId = lt.LookupValueId
JOIN LookupValues jt ON p.JoinTypeLkpId     = jt.LookupValueId
LEFT JOIN ProjectSkills sk ON sk.ProjectId  = p.ProjectId
WHERE p.OrgId = 2 AND p.CreatedBy = 4
GROUP BY p.ProjectId
ORDER BY p.ProjectId DESC
LIMIT 10;

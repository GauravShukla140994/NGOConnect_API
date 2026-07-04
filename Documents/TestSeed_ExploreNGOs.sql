-- =============================================================================
-- NGO Connect — Test Seed Data
-- 10 NGOs: 5 in Chandigarh, 5 in Bangalore
-- UserId 1 added as FOUNDER (Admin) for all orgs
-- Run directly in MySQL Workbench (no DELIMITER needed)
-- =============================================================================

-- Lookup ID variables (resolved once, reused throughout)
SET @role_founder  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE'   AND lv.ValueCode='FOUNDER'  LIMIT 1);
SET @status_approved_member = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='MEMBER_STATUS' AND lv.ValueCode='APPROVED' LIMIT 1);
SET @status_approved_org    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_STATUS'    AND lv.ValueCode='APPROVED' LIMIT 1);
SET @type_trust    = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE'      AND lv.ValueCode='TRUST'    LIMIT 1);
SET @type_society  = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE'      AND lv.ValueCode='SOCIETY'  LIMIT 1);
SET @type_sec8     = (SELECT lv.LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE'      AND lv.ValueCode='SECTION_8' LIMIT 1);

SELECT CONCAT('LookupIds resolved — role_founder=', @role_founder,
              ', member_approved=', @status_approved_member,
              ', org_approved=', @status_approved_org,
              ', trust=', @type_trust,
              ', society=', @type_society,
              ', sec8=', @type_sec8) AS status_check;

-- =============================================================================
-- CHANDIGARH NGOs  (centre ~30.7333° N, 76.7794° E)
-- =============================================================================

-- 1. EduRise Chandigarh (Education)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'EduRise Chandigarh', 'Priya Sharma', @type_trust,
    'TEST-CHD-001', 'Education',
    'Empowering underprivileged children in Chandigarh with quality education, digital literacy, and scholarships.',
    'Ensure every child in Chandigarh has access to quality education by 2030.',
    'A fully literate, digitally enabled youth of Punjab & Haryana.',
    'contact@edurisechd.org', '9815001001', 'www.edurisechd.org',
    'SCO 45-46, Sector 17-C', 'Chandigarh', 'Chandigarh', '160017', 'India',
    4.70, 312, 30.7419, 76.7842,
    @status_approved_org, 1
);
SET @org_chd1 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_chd1, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 2. Green Tricity (Environment)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Green Tricity', 'Arjun Mehta', @type_society,
    'TEST-CHD-002', 'Environment',
    'Working across the Tricity (Chandigarh, Mohali, Panchkula) to plant trees, clean Sukhna Lake, and reduce plastic waste.',
    'Plant 1 million trees across Tricity by 2027 and achieve zero single-use plastic.',
    'Tricity as the greenest urban cluster in North India.',
    'info@greentricity.in', '9815002002', 'www.greentricity.in',
    'House 210, Sector 20-A', 'Chandigarh', 'Chandigarh', '160020', 'India',
    4.85, 528, 30.7250, 76.8100,
    @status_approved_org, 1
);
SET @org_chd2 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_chd2, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 3. HealthFirst Punjab (Healthcare)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'HealthFirst Punjab', 'Dr. Navdeep Kaur', @type_trust,
    'TEST-CHD-003', 'Healthcare',
    'Free health camps, mobile clinics, and mental health awareness programs across rural Punjab and Chandigarh slums.',
    'Bring quality preventive healthcare within 5 km of every rural household in Punjab.',
    'A healthy Punjab where no one skips treatment due to cost.',
    'care@healthfirstpunjab.org', '9815003003', NULL,
    'Plot 88, Industrial Area Phase-1', 'Chandigarh', 'Chandigarh', '160002', 'India',
    4.60, 198, 30.7010, 76.8030,
    @status_approved_org, 1
);
SET @org_chd3 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_chd3, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 4. Paws Chandigarh (Animal Welfare)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Paws Chandigarh', 'Simran Bedi', @type_society,
    'TEST-CHD-004', 'Animal Welfare',
    'Rescuing, treating, and rehoming stray animals in Chandigarh. Running a shelter with 200+ animals.',
    'Zero animal cruelty in Chandigarh by 2028 through rescue, neuter, and adopt programs.',
    'A city where every animal is safe, healthy, and loved.',
    'adopt@pawschandigarh.org', '9815004004', 'www.pawschandigarh.org',
    'Sector 38-B, Near Dog Shelter', 'Chandigarh', 'Chandigarh', '160038', 'India',
    4.90, 743, 30.7190, 76.7510,
    @status_approved_org, 1
);
SET @org_chd4 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_chd4, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 5. Saathi Community Foundation (Community Dev)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Saathi Community Foundation', 'Rajveer Singh', @type_sec8,
    'TEST-CHD-005', 'Community Dev',
    'Building community halls, skill centres, and women empowerment programs in underserved sectors of Chandigarh.',
    'Empower 10,000 women and youth in Chandigarh with vocational skills by 2026.',
    'Self-reliant, inclusive communities across North India.',
    'hello@saathifoundation.org', '9815005005', 'www.saathifoundation.org',
    'Community Centre, Sector 45-A', 'Chandigarh', 'Chandigarh', '160045', 'India',
    4.45, 156, 30.7095, 76.7980,
    @status_approved_org, 1
);
SET @org_chd5 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_chd5, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

SELECT CONCAT('Chandigarh NGOs inserted — IDs: ', @org_chd1, ', ', @org_chd2, ', ', @org_chd3, ', ', @org_chd4, ', ', @org_chd5) AS chd_status;

-- =============================================================================
-- BANGALORE NGOs  (centre ~12.9716° N, 77.5946° E)
-- =============================================================================

-- 6. TechForGood Bangalore (Education)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'TechForGood Bangalore', 'Ananya Krishnan', @type_sec8,
    'TEST-BLR-001', 'Education',
    'Bridging the digital divide in Bangalore by training government school students in coding, AI basics, and digital safety.',
    'Train 50,000 students in digital skills across Bangalore government schools by 2027.',
    'Every Karnataka student, regardless of background, is digitally fluent.',
    'contact@techforgoodblr.org', '9916001001', 'www.techforgoodblr.org',
    '4th Floor, Prestige Tech Park, Outer Ring Road', 'Bangalore', 'Karnataka', '560103', 'India',
    4.80, 891, 12.9352, 77.6245,
    @status_approved_org, 1
);
SET @org_blr1 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_blr1, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 7. Hasiru Dala (Environment)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Hasiru Dala Foundation', 'Nalini Shekar', @type_trust,
    'TEST-BLR-002', 'Environment',
    'Integrating waste pickers into the formal recycling economy and driving zero-waste initiatives across Bangalore.',
    'Achieve zero landfill waste from Bangalore by 2030 through inclusive circular economy.',
    'A waste-free Bangalore that values every waste worker.',
    'info@hasirudala.in', '9916002002', 'www.hasirudala.in',
    'No.14, 3rd Cross, Sadashivanagar', 'Bangalore', 'Karnataka', '560080', 'India',
    4.95, 1420, 13.0050, 77.5718,
    @status_approved_org, 1
);
SET @org_blr2 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_blr2, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 8. Aarogya Seva (Healthcare)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Aarogya Seva Bangalore', 'Dr. Suresh Babu', @type_society,
    'TEST-BLR-003', 'Healthcare',
    'Free medical camps, dialysis support, and mental health counselling for migrant workers and slum communities in Bangalore.',
    'Ensure no migrant worker or slum resident in Bangalore lacks emergency medical care.',
    'A Bangalore where healthcare is a right, not a privilege.',
    'help@aarogyaseva.org', '9916003003', NULL,
    '23, 1st Main, Koramangala 3rd Block', 'Bangalore', 'Karnataka', '560034', 'India',
    4.55, 267, 12.9340, 77.6101,
    @status_approved_org, 1
);
SET @org_blr3 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_blr3, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 9. People for Animals Bangalore (Animal Welfare)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'People for Animals Bangalore', 'Meera Iyer', @type_trust,
    'TEST-BLR-004', 'Animal Welfare',
    'Rescue, rehabilitation, and adoption of stray and injured animals across Bangalore with a 24x7 ambulance service.',
    'End animal homelessness in Bangalore by running 5 shelters and 100 foster families.',
    'Bangalore — a city of compassion for all living beings.',
    'rescue@pfablr.org', '9916004004', 'www.pfablr.org',
    'Shelter Complex, Hennur Road', 'Bangalore', 'Karnataka', '560043', 'India',
    4.75, 612, 13.0420, 77.6290,
    @status_approved_org, 1
);
SET @org_blr4 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_blr4, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

-- 10. Namma Bengaluru Foundation (Community Dev)
INSERT INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
    ContactEmail, ContactPhone, Website, AddressLine1, City, State, Pincode, Country,
    AvgRating, RatingCount, Latitude, Longitude, StatusLkpId, CreatedBy)
VALUES (
    'Namma Bengaluru Foundation', 'Srinivas Rao', @type_sec8,
    'TEST-BLR-005', 'Community Dev',
    'Civic engagement, lake restoration, footpath repair drives, and traffic safety campaigns run by Bangalore citizens for Bangalore.',
    'Make Bangalore the most liveable and citizen-run city in India by 2030.',
    'A Bangalore where every resident is an active co-creator of the city.',
    'connect@nammabengaluru.org', '9916005005', 'www.nammabengaluru.org',
    '6th Floor, UB City, Vittal Mallya Road', 'Bangalore', 'Karnataka', '560001', 'India',
    4.65, 389, 12.9716, 77.5946,
    @status_approved_org, 1
);
SET @org_blr5 = LAST_INSERT_ID();
INSERT INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
VALUES (@org_blr5, 1, @role_founder, @status_approved_member, 1, 1, 1, 50, NOW(), 1);

SELECT CONCAT('Bangalore NGOs inserted — IDs: ', @org_blr1, ', ', @org_blr2, ', ', @org_blr3, ', ', @org_blr4, ', ', @org_blr5) AS blr_status;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
SELECT
    o.OrgId,
    o.OrgName,
    o.Category,
    o.City,
    o.AvgRating,
    o.Latitude,
    o.Longitude,
    lv.ValueName AS OrgStatus,
    lr.ValueName AS MemberRole,
    ls.ValueName AS MemberStatus
FROM Organisations o
JOIN OrgMembers    om ON om.OrgId = o.OrgId AND om.UserId = 1 AND om.IsDeleted = 0
JOIN LookupValues  lv ON o.StatusLkpId  = lv.LookupValueId
JOIN LookupValues  lr ON om.RoleLkpId   = lr.LookupValueId
JOIN LookupValues  ls ON om.StatusLkpId = ls.LookupValueId
WHERE o.RegNumber IN (
    'TEST-CHD-001','TEST-CHD-002','TEST-CHD-003','TEST-CHD-004','TEST-CHD-005',
    'TEST-BLR-001','TEST-BLR-002','TEST-BLR-003','TEST-BLR-004','TEST-BLR-005'
)
ORDER BY o.City, o.OrgId;

-- =============================================================================
-- CLEANUP (run this block separately when you want to remove test data)
-- =============================================================================
/*
DELETE om FROM OrgMembers om
JOIN Organisations o ON om.OrgId = o.OrgId
WHERE o.RegNumber IN (
    'TEST-CHD-001','TEST-CHD-002','TEST-CHD-003','TEST-CHD-004','TEST-CHD-005',
    'TEST-BLR-001','TEST-BLR-002','TEST-BLR-003','TEST-BLR-004','TEST-BLR-005'
);
DELETE FROM Organisations WHERE RegNumber IN (
    'TEST-CHD-001','TEST-CHD-002','TEST-CHD-003','TEST-CHD-004','TEST-CHD-005',
    'TEST-BLR-001','TEST-BLR-002','TEST-BLR-003','TEST-BLR-004','TEST-BLR-005'
);
*/

-- ============================================================
-- NGO Connect — Comprehensive Test Seed Data
-- Date    : 2026-07-11
--
-- CONTENTS:
--   • 10 test users  (mobile +919000000001 … +919000000010)
--   • 50 NGOs across 15 Indian cities
--   • OrgMembers: User 1 = ADMIN of all orgs, users 2-10 distributed as MEMBERs
--   • 4 projects per NGO = 200 projects (ACTIVE / UPCOMING / COMPLETED mix)
--   • Sessions + Skills per project
--   • 80 posts across orgs (text); 20 of them with placeholder images (picsum)
--
-- SAFE: INSERT IGNORE — re-runnable without duplicates.
-- Run against: NGOConnect DB (use NGOConnect;)
-- ============================================================

USE NGOConnect;

-- ── LOOKUP VARIABLES ─────────────────────────────────────────────────────────
SET @lkp_org_trust    = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE'       AND lv.ValueCode='TRUST');
SET @lkp_org_society  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='ORG_TYPE'       AND lv.ValueCode='SOCIETY');
SET @lkp_org_approved = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='ORG_STATUS'     AND lv.ValueCode='APPROVED');
SET @lkp_role_admin   = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE'    AND lv.ValueCode='ADMIN');
SET @lkp_role_member  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='MEMBER_ROLE'    AND lv.ValueCode='MEMBER');
SET @lkp_mem_approved = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='MEMBER_STATUS'  AND lv.ValueCode='APPROVED');
SET @lkp_proj_onetime = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_TYPE'   AND lv.ValueCode='ONE_TIME');
SET @lkp_proj_recur   = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_TYPE'   AND lv.ValueCode='RECURRING');
SET @lkp_proj_flex    = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_TYPE'   AND lv.ValueCode='FLEXIBLE');
SET @lkp_proj_active  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_STATUS' AND lv.ValueCode='ACTIVE');
SET @lkp_proj_upcoming= (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_STATUS' AND lv.ValueCode='UPCOMING');
SET @lkp_proj_done    = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='PROJECT_STATUS' AND lv.ValueCode='COMPLETED');
SET @lkp_loc_inperson = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='LOCATION_TYPE' AND lv.ValueCode='IN_PERSON');
SET @lkp_loc_hybrid   = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='LOCATION_TYPE' AND lv.ValueCode='HYBRID');
SET @lkp_join_open    = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='JOIN_TYPE'     AND lv.ValueCode='OPEN');
SET @lkp_join_approval= (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='JOIN_TYPE'     AND lv.ValueCode='APPROVAL_REQUIRED');
SET @lkp_sess_upcoming= (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='SESSION_STATUS' AND lv.ValueCode='UPCOMING');
SET @lkp_sess_done    = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='SESSION_STATUS' AND lv.ValueCode='COMPLETED');
SET @lkp_post_general = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='POST_TYPE_FEED' AND lv.ValueCode='GENERAL');
SET @lkp_post_announce= (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='POST_TYPE_FEED' AND lv.ValueCode='ANNOUNCEMENT');
SET @lkp_post_event   = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='POST_TYPE_FEED' AND lv.ValueCode='EVENT');
SET @lkp_vis_public   = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='POST_VISIBILITY' AND lv.ValueCode='PUBLIC');
SET @lkp_vis_members  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='POST_VISIBILITY' AND lv.ValueCode='ORG_MEMBERS');
SET @lkp_media_image  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='MEDIA_TYPE'     AND lv.ValueCode='IMAGE');
SET @lkp_gender_male  = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='GENDER'         AND lv.ValueCode='MALE');
SET @lkp_gender_female= (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='GENDER'         AND lv.ValueCode='FEMALE');


-- ═══════════════════════════════════════════════════════════
-- 1. USERS (10 test users)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO Users (Mobile, Email, CountryCode, IsVerified, IsActive, CreatedBy) VALUES
('+919000000001', 'arjun.sharma@testmail.in', '+91', 1, 1, 1),
('+919000000002', 'priya.patel@testmail.in', '+91', 1, 1, 1),
('+919000000003', 'rohit.verma@testmail.in', '+91', 1, 1, 1),
('+919000000004', 'sunita.nair@testmail.in', '+91', 1, 1, 1),
('+919000000005', 'vikram.singh@testmail.in', '+91', 1, 1, 1),
('+919000000006', 'meera.krishnan@testmail.in', '+91', 1, 1, 1),
('+919000000007', 'aakash.gupta@testmail.in', '+91', 1, 1, 1),
('+919000000008', 'deepika.reddy@testmail.in', '+91', 1, 1, 1),
('+919000000009', 'manish.joshi@testmail.in', '+91', 1, 1, 1),
('+919000000010', 'kavita.mishra@testmail.in', '+91', 1, 1, 1);

-- Store user IDs
SET @u1 = (SELECT UserId FROM Users WHERE Mobile='+919000000001' AND IsDeleted=0);
SET @u2 = (SELECT UserId FROM Users WHERE Mobile='+919000000002' AND IsDeleted=0);
SET @u3 = (SELECT UserId FROM Users WHERE Mobile='+919000000003' AND IsDeleted=0);
SET @u4 = (SELECT UserId FROM Users WHERE Mobile='+919000000004' AND IsDeleted=0);
SET @u5 = (SELECT UserId FROM Users WHERE Mobile='+919000000005' AND IsDeleted=0);
SET @u6 = (SELECT UserId FROM Users WHERE Mobile='+919000000006' AND IsDeleted=0);
SET @u7 = (SELECT UserId FROM Users WHERE Mobile='+919000000007' AND IsDeleted=0);
SET @u8 = (SELECT UserId FROM Users WHERE Mobile='+919000000008' AND IsDeleted=0);
SET @u9 = (SELECT UserId FROM Users WHERE Mobile='+919000000009' AND IsDeleted=0);
SET @u10 = (SELECT UserId FROM Users WHERE Mobile='+919000000010' AND IsDeleted=0);

-- UserProfiles
INSERT IGNORE INTO UserProfiles (UserId, FirstName, LastName, DateOfBirth, GenderLkpId, Bio, Occupation, Organisation, City, State, Country, CreatedBy) VALUES
(@u1, 'Arjun', 'Sharma', '1990-03-12', @lkp_gender_male, 'Passionate volunteer committed to social impact and community development.', 'Software Engineer', 'Tata Consultancy Services', 'Delhi', 'Delhi', 'India', 1),
(@u2, 'Priya', 'Patel', '1992-07-24', @lkp_gender_female, 'Passionate volunteer committed to social impact and community development.', 'NGO Coordinator', 'CRY India', 'Ahmedabad', 'Gujarat', 'India', 1),
(@u3, 'Rohit', 'Verma', '1988-11-05', @lkp_gender_male, 'Passionate volunteer committed to social impact and community development.', 'Doctor', 'Apollo Hospitals', 'Mumbai', 'Maharashtra', 'India', 1),
(@u4, 'Sunita', 'Nair', '1995-02-18', @lkp_gender_female, 'Passionate volunteer committed to social impact and community development.', 'Teacher', 'St. Marys School', 'Kochi', 'Kerala', 'India', 1),
(@u5, 'Vikram', 'Singh', '1985-08-30', @lkp_gender_male, 'Passionate volunteer committed to social impact and community development.', 'Project Manager', 'Infosys', 'Lucknow', 'Uttar Pradesh', 'India', 1),
(@u6, 'Meera', 'Krishnan', '1993-05-14', @lkp_gender_female, 'Passionate volunteer committed to social impact and community development.', 'Social Worker', 'UNICEF India', 'Chennai', 'Tamil Nadu', 'India', 1),
(@u7, 'Aakash', 'Gupta', '1991-09-22', @lkp_gender_male, 'Passionate volunteer committed to social impact and community development.', 'Journalist', 'The Hindu', 'Kolkata', 'West Bengal', 'India', 1),
(@u8, 'Deepika', 'Reddy', '1994-12-01', @lkp_gender_female, 'Passionate volunteer committed to social impact and community development.', 'Architect', 'L and T Construction', 'Hyderabad', 'Telangana', 'India', 1),
(@u9, 'Manish', 'Joshi', '1987-04-17', @lkp_gender_male, 'Passionate volunteer committed to social impact and community development.', 'HR Manager', 'Wipro', 'Pune', 'Maharashtra', 'India', 1),
(@u10, 'Kavita', 'Mishra', '1996-06-28', @lkp_gender_female, 'Passionate volunteer committed to social impact and community development.', 'Environmental Scientist', 'WWF India', 'Bhopal', 'Madhya Pradesh', 'India', 1);

-- ═══════════════════════════════════════════════════════════
-- 2. ORGANISATIONS (50 NGOs across India)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO Organisations (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, ContactEmail, ContactPhone, City, State, Country, Latitude, Longitude, StatusLkpId, CreatedBy) VALUES
('Dilli Shiksha Foundation', 'Dilli Foundation Admin', @lkp_org_trust, 'REG-DL-001', 'Education', 'Empowering underprivileged children through quality education across Delhi slums', 'To empowering underprivileged children through quality education across delhi slums through sustained community engagement and partnership.', 'regdl001@ngoconnect.test', '+919800000010', 'Delhi', 'Delhi', 'India', 28.6139, 77.209, @lkp_org_approved, 1),
('Delhi Green Warriors', 'Delhi Foundation Admin', @lkp_org_society, 'REG-DL-002', 'Environment', 'Planting trees and fighting air pollution in the national capital region', 'To planting trees and fighting air pollution in the national capital region through sustained community engagement and partnership.', 'regdl002@ngoconnect.test', '+919800000011', 'Delhi', 'Delhi', 'India', 28.628, 77.2189, @lkp_org_approved, 1),
('Capital Health Care Trust', 'Capital Foundation Admin', @lkp_org_trust, 'REG-DL-003', 'Healthcare', 'Free mobile health clinics serving Delhi migrant worker communities', 'To free mobile health clinics serving delhi migrant worker communities through sustained community engagement and partnership.', 'regdl003@ngoconnect.test', '+919800000012', 'Delhi', 'Delhi', 'India', 28.6448, 77.2167, @lkp_org_approved, 1),
('Naari Shakti Delhi', 'Naari Foundation Admin', @lkp_org_society, 'REG-DL-004', 'Women Empowerment', 'Skill development and self-defence training for women in Delhi', 'To skill development and self-defence training for women in delhi through sustained community engagement and partnership.', 'regdl004@ngoconnect.test', '+919800000013', 'Delhi', 'Delhi', 'India', 28.5921, 77.223, @lkp_org_approved, 1),
('Delhi Bal Kalyan Sangh', 'Delhi Foundation Admin', @lkp_org_trust, 'REG-DL-005', 'Child Welfare', 'Rescue and rehabilitation of street children in Delhi NCR', 'To rescue and rehabilitation of street children in delhi ncr through sustained community engagement and partnership.', 'regdl005@ngoconnect.test', '+919800000014', 'Delhi', 'Delhi', 'India', 28.6692, 77.4538, @lkp_org_approved, 1),
('Mumbai Literacy Mission', 'Mumbai Foundation Admin', @lkp_org_trust, 'REG-MH-001', 'Education', 'Adult literacy programs reaching 50000 residents in Mumbai chawls', 'To adult literacy programs reaching 50000 residents in mumbai chawls through sustained community engagement and partnership.', 'regmh001@ngoconnect.test', '+919800000015', 'Mumbai', 'Maharashtra', 'India', 19.076, 72.8777, @lkp_org_approved, 1),
('Dharavi Clean Future', 'Dharavi Foundation Admin', @lkp_org_society, 'REG-MH-002', 'Environment', 'Waste segregation and recycling initiative born in Dharavi', 'To waste segregation and recycling initiative born in dharavi through sustained community engagement and partnership.', 'regmh002@ngoconnect.test', '+919800000016', 'Mumbai', 'Maharashtra', 'India', 19.0387, 72.8546, @lkp_org_approved, 1),
('Arogya Setu Mumbai', 'Arogya Foundation Admin', @lkp_org_trust, 'REG-MH-003', 'Healthcare', 'Free diagnostic camps and mental health support across Mumbai', 'To free diagnostic camps and mental health support across mumbai through sustained community engagement and partnership.', 'regmh003@ngoconnect.test', '+919800000017', 'Mumbai', 'Maharashtra', 'India', 19.1136, 72.8697, @lkp_org_approved, 1),
('Stree Uday Foundation', 'Stree Foundation Admin', @lkp_org_trust, 'REG-MH-004', 'Women Empowerment', 'Micro-lending and entrepreneurship for Mumbai women artisans', 'To micro-lending and entrepreneurship for mumbai women artisans through sustained community engagement and partnership.', 'regmh004@ngoconnect.test', '+919800000018', 'Mumbai', 'Maharashtra', 'India', 19.0522, 72.8318, @lkp_org_approved, 1),
('Mumbai Child First', 'Mumbai Foundation Admin', @lkp_org_society, 'REG-MH-005', 'Child Welfare', 'Nutrition and early childhood development for Mumbai slum communities', 'To nutrition and early childhood development for mumbai slum communities through sustained community engagement and partnership.', 'regmh005@ngoconnect.test', '+919800000019', 'Mumbai', 'Maharashtra', 'India', 19.0825, 72.7411, @lkp_org_approved, 1),
('Bengaluru Edu Connect', 'Bengaluru Foundation Admin', @lkp_org_trust, 'REG-KA-001', 'Education', 'Bridging the digital divide by providing tech education to rural Karnataka', 'To bridging the digital divide by providing tech education to rural karnataka through sustained community engagement and partnership.', 'regka001@ngoconnect.test', '+919800000020', 'Bangalore', 'Karnataka', 'India', 12.9716, 77.5946, @lkp_org_approved, 1),
('Namma Bengaluru Green', 'Namma Foundation Admin', @lkp_org_society, 'REG-KA-002', 'Environment', 'Urban garden initiative with 200 community gardens across Bangalore', 'To urban garden initiative with 200 community gardens across bangalore through sustained community engagement and partnership.', 'regka002@ngoconnect.test', '+919800000021', 'Bangalore', 'Karnataka', 'India', 12.9352, 77.6245, @lkp_org_approved, 1),
('Swasthya Bengaluru', 'Swasthya Foundation Admin', @lkp_org_trust, 'REG-KA-003', 'Healthcare', 'Mental health awareness and affordable counselling services in Bangalore', 'To mental health awareness and affordable counselling services in bangalore through sustained community engagement and partnership.', 'regka003@ngoconnect.test', '+919800000022', 'Bangalore', 'Karnataka', 'India', 12.9762, 77.6033, @lkp_org_approved, 1),
('She Leads Bangalore', 'She Foundation Admin', @lkp_org_society, 'REG-KA-004', 'Women Empowerment', 'Tech careers for women through coding bootcamps and job placement support', 'To tech careers for women through coding bootcamps and job placement support through sustained community engagement and partnership.', 'regka004@ngoconnect.test', '+919800000023', 'Bangalore', 'Karnataka', 'India', 12.954, 77.6161, @lkp_org_approved, 1),
('Bangalore Rural Uplift', 'Bangalore Foundation Admin', @lkp_org_trust, 'REG-KA-005', 'Rural Development', 'Connecting Bangalore CSR network with 50 surrounding villages', 'To connecting bangalore csr network with 50 surrounding villages through sustained community engagement and partnership.', 'regka005@ngoconnect.test', '+919800000024', 'Bangalore', 'Karnataka', 'India', 13.01, 77.55, @lkp_org_approved, 1),
('Chennai Vidya Trust', 'Chennai Foundation Admin', @lkp_org_trust, 'REG-TN-001', 'Education', 'Free coaching for Tamil Nadu government school students for competitive exams', 'To free coaching for tamil nadu government school students for competitive exams through sustained community engagement and partnership.', 'regtn001@ngoconnect.test', '+919800000025', 'Chennai', 'Tamil Nadu', 'India', 13.0827, 80.2707, @lkp_org_approved, 1),
('Marina Beach Clean Project', 'Marina Foundation Admin', @lkp_org_society, 'REG-TN-002', 'Environment', 'Weekly beach cleaning drives and plastic ban awareness in Chennai', 'To weekly beach cleaning drives and plastic ban awareness in chennai through sustained community engagement and partnership.', 'regtn002@ngoconnect.test', '+919800000026', 'Chennai', 'Tamil Nadu', 'India', 13.05, 80.2824, @lkp_org_approved, 1),
('Tamil Nadu Healthcare Reach', 'Tamil Foundation Admin', @lkp_org_trust, 'REG-TN-003', 'Healthcare', 'Rural health outreach across 100 villages in Tamil Nadu', 'To rural health outreach across 100 villages in tamil nadu through sustained community engagement and partnership.', 'regtn003@ngoconnect.test', '+919800000027', 'Chennai', 'Tamil Nadu', 'India', 13.0569, 80.2425, @lkp_org_approved, 1),
('Chennai Women Collective', 'Chennai Foundation Admin', @lkp_org_society, 'REG-TN-004', 'Women Empowerment', 'Legal aid and shelter for survivors of domestic abuse in Tamil Nadu', 'To legal aid and shelter for survivors of domestic abuse in tamil nadu through sustained community engagement and partnership.', 'regtn004@ngoconnect.test', '+919800000028', 'Chennai', 'Tamil Nadu', 'India', 13.1067, 80.2206, @lkp_org_approved, 1),
('Hyderabad Reads', 'Hyderabad Foundation Admin', @lkp_org_trust, 'REG-TS-001', 'Education', 'Library network with 80 free reading centres across Telangana', 'To library network with 80 free reading centres across telangana through sustained community engagement and partnership.', 'regts001@ngoconnect.test', '+919800000029', 'Hyderabad', 'Telangana', 'India', 17.385, 78.4867, @lkp_org_approved, 1),
('Musi River Rejuvenation', 'Musi Foundation Admin', @lkp_org_society, 'REG-TS-002', 'Environment', 'Water purification and riverbank restoration along the Musi River', 'To water purification and riverbank restoration along the musi river through sustained community engagement and partnership.', 'regts002@ngoconnect.test', '+919800000030', 'Hyderabad', 'Telangana', 'India', 17.3753, 78.4744, @lkp_org_approved, 1),
('Deccan Community Health', 'Deccan Foundation Admin', @lkp_org_trust, 'REG-TS-003', 'Healthcare', 'Affordable dialysis centres for kidney patients in Hyderabad', 'To affordable dialysis centres for kidney patients in hyderabad through sustained community engagement and partnership.', 'regts003@ngoconnect.test', '+919800000031', 'Hyderabad', 'Telangana', 'India', 17.4126, 78.4772, @lkp_org_approved, 1),
('Telangana Tribe Connect', 'Telangana Foundation Admin', @lkp_org_society, 'REG-TS-004', 'Rural Development', 'Tribal art preservation and livelihood support in Adilabad district', 'To tribal art preservation and livelihood support in adilabad district through sustained community engagement and partnership.', 'regts004@ngoconnect.test', '+919800000032', 'Hyderabad', 'Telangana', 'India', 17.3241, 78.5528, @lkp_org_approved, 1),
('Kolkata Pathshala', 'Kolkata Foundation Admin', @lkp_org_trust, 'REG-WB-001', 'Education', 'Night schools for working children in Kolkata industrial belts', 'To night schools for working children in kolkata industrial belts through sustained community engagement and partnership.', 'regwb001@ngoconnect.test', '+919800000033', 'Kolkata', 'West Bengal', 'India', 22.5726, 88.3639, @lkp_org_approved, 1),
('Sundarban Eco Warriors', 'Sundarban Foundation Admin', @lkp_org_society, 'REG-WB-002', 'Environment', 'Mangrove restoration and tiger habitat conservation in Sundarbans', 'To mangrove restoration and tiger habitat conservation in sundarbans through sustained community engagement and partnership.', 'regwb002@ngoconnect.test', '+919800000034', 'Kolkata', 'West Bengal', 'India', 22.4755, 88.394, @lkp_org_approved, 1),
('Kolkata Mother Care Trust', 'Kolkata Foundation Admin', @lkp_org_trust, 'REG-WB-003', 'Healthcare', 'Maternal health and safe delivery support for underprivileged women', 'To maternal health and safe delivery support for underprivileged women through sustained community engagement and partnership.', 'regwb003@ngoconnect.test', '+919800000035', 'Kolkata', 'West Bengal', 'India', 22.5448, 88.3426, @lkp_org_approved, 1),
('Paschim Banga Grameen Seva', 'Paschim Foundation Admin', @lkp_org_society, 'REG-WB-004', 'Rural Development', 'Water harvesting and organic farming support for West Bengal villages', 'To water harvesting and organic farming support for west bengal villages through sustained community engagement and partnership.', 'regwb004@ngoconnect.test', '+919800000036', 'Kolkata', 'West Bengal', 'India', 22.604, 88.4326, @lkp_org_approved, 1),
('Pune Shikshan Sanstha', 'Pune Foundation Admin', @lkp_org_trust, 'REG-PU-001', 'Education', 'Scholarship and mentorship program for tribal students in Pune district', 'To scholarship and mentorship program for tribal students in pune district through sustained community engagement and partnership.', 'regpu001@ngoconnect.test', '+919800000037', 'Pune', 'Maharashtra', 'India', 18.5204, 73.8567, @lkp_org_approved, 1),
('Sahyadri Nature Trust', 'Sahyadri Foundation Admin', @lkp_org_society, 'REG-PU-002', 'Environment', 'Western Ghats biodiversity conservation and ecotourism in Pune region', 'To western ghats biodiversity conservation and ecotourism in pune region through sustained community engagement and partnership.', 'regpu002@ngoconnect.test', '+919800000038', 'Pune', 'Maharashtra', 'India', 18.4655, 73.8233, @lkp_org_approved, 1),
('Vatsalya Child Home', 'Vatsalya Foundation Admin', @lkp_org_trust, 'REG-PU-003', 'Child Welfare', 'Shelter, education and care for orphaned children in Pune', 'To shelter, education and care for orphaned children in pune through sustained community engagement and partnership.', 'regpu003@ngoconnect.test', '+919800000039', 'Pune', 'Maharashtra', 'India', 18.5642, 73.901, @lkp_org_approved, 1),
('Pune Senior Care Society', 'Pune Foundation Admin', @lkp_org_society, 'REG-PU-004', 'Elderly Care', 'Day care centres and home assistance for senior citizens in Pune', 'To day care centres and home assistance for senior citizens in pune through sustained community engagement and partnership.', 'regpu004@ngoconnect.test', '+919800000040', 'Pune', 'Maharashtra', 'India', 18.5074, 73.807, @lkp_org_approved, 1),
('Ahmedabad Literacy Drive', 'Ahmedabad Foundation Admin', @lkp_org_trust, 'REG-GJ-001', 'Education', 'Adult literacy and vocational training for migrant workers in Gujarat', 'To adult literacy and vocational training for migrant workers in gujarat through sustained community engagement and partnership.', 'reggj001@ngoconnect.test', '+919800000041', 'Ahmedabad', 'Gujarat', 'India', 23.0225, 72.5714, @lkp_org_approved, 1),
('Sabarmati Clean Waters', 'Sabarmati Foundation Admin', @lkp_org_society, 'REG-GJ-002', 'Environment', 'Sabarmati river clean-up and water conservation in Gujarat', 'To sabarmati river clean-up and water conservation in gujarat through sustained community engagement and partnership.', 'reggj002@ngoconnect.test', '+919800000042', 'Ahmedabad', 'Gujarat', 'India', 23.0395, 72.5511, @lkp_org_approved, 1),
('Gujarat Mahila Vikas', 'Gujarat Foundation Admin', @lkp_org_trust, 'REG-GJ-003', 'Women Empowerment', 'Self-help groups and fair-trade handicraft marketing for Gujarat women', 'To self-help groups and fair-trade handicraft marketing for gujarat women through sustained community engagement and partnership.', 'reggj003@ngoconnect.test', '+919800000043', 'Ahmedabad', 'Gujarat', 'India', 23.0139, 72.507, @lkp_org_approved, 1),
('Rajasthan Bal Vidyalay', 'Rajasthan Foundation Admin', @lkp_org_trust, 'REG-RJ-001', 'Child Welfare', 'Mobile classrooms reaching desert villages in Rajasthan', 'To mobile classrooms reaching desert villages in rajasthan through sustained community engagement and partnership.', 'regrj001@ngoconnect.test', '+919800000044', 'Jaipur', 'Rajasthan', 'India', 26.9124, 75.7873, @lkp_org_approved, 1),
('Aravalli Green Mission', 'Aravalli Foundation Admin', @lkp_org_society, 'REG-RJ-002', 'Environment', 'Afforestation of the degraded Aravalli hills in Rajasthan', 'To afforestation of the degraded aravalli hills in rajasthan through sustained community engagement and partnership.', 'regrj002@ngoconnect.test', '+919800000045', 'Jaipur', 'Rajasthan', 'India', 26.8865, 75.8093, @lkp_org_approved, 1),
('Rajputana Heritage Trust', 'Rajputana Foundation Admin', @lkp_org_trust, 'REG-RJ-003', 'Arts & Culture', 'Preservation of Rajasthani folk music, crafts and heritage sites', 'To preservation of rajasthani folk music, crafts and heritage sites through sustained community engagement and partnership.', 'regrj003@ngoconnect.test', '+919800000046', 'Jaipur', 'Rajasthan', 'India', 26.926, 75.8235, @lkp_org_approved, 1),
('Awadh Shiksha Samiti', 'Awadh Foundation Admin', @lkp_org_society, 'REG-UP-001', 'Education', 'Free tuition centres in Lucknow underserved neighbourhoods', 'To free tuition centres in lucknow underserved neighbourhoods through sustained community engagement and partnership.', 'regup001@ngoconnect.test', '+919800000047', 'Lucknow', 'Uttar Pradesh', 'India', 26.8467, 80.9462, @lkp_org_approved, 1),
('Gomti River Trust', 'Gomti Foundation Admin', @lkp_org_trust, 'REG-UP-002', 'Environment', 'Gomti clean-up drives and sewage monitoring in Lucknow', 'To gomti clean-up drives and sewage monitoring in lucknow through sustained community engagement and partnership.', 'regup002@ngoconnect.test', '+919800000048', 'Lucknow', 'Uttar Pradesh', 'India', 26.86, 80.952, @lkp_org_approved, 1),
('UP Senior Citizens Welfare', 'UP Foundation Admin', @lkp_org_society, 'REG-UP-003', 'Elderly Care', 'Pension aid navigation and elder abuse prevention in Uttar Pradesh', 'To pension aid navigation and elder abuse prevention in uttar pradesh through sustained community engagement and partnership.', 'regup003@ngoconnect.test', '+919800000049', 'Lucknow', 'Uttar Pradesh', 'India', 26.8274, 80.9081, @lkp_org_approved, 1),
('Chandigarh Education Trust', 'Chandigarh Foundation Admin', @lkp_org_trust, 'REG-CH-001', 'Education', 'Career counselling and digital literacy for Chandigarh youth', 'To career counselling and digital literacy for chandigarh youth through sustained community engagement and partnership.', 'regch001@ngoconnect.test', '+919800000050', 'Chandigarh', 'Punjab', 'India', 30.7333, 76.7794, @lkp_org_approved, 1),
('Shivalik Nature Society', 'Shivalik Foundation Admin', @lkp_org_society, 'REG-CH-002', 'Environment', 'Shivalik foothills reforestation and wildlife corridor protection', 'To shivalik foothills reforestation and wildlife corridor protection through sustained community engagement and partnership.', 'regch002@ngoconnect.test', '+919800000051', 'Chandigarh', 'Punjab', 'India', 30.7195, 76.8101, @lkp_org_approved, 1),
('Kerala Vidya Jyoti', 'Kerala Foundation Admin', @lkp_org_trust, 'REG-KL-001', 'Education', 'Special education support for differently-abled children in Kerala', 'To special education support for differently-abled children in kerala through sustained community engagement and partnership.', 'regkl001@ngoconnect.test', '+919800000052', 'Kochi', 'Kerala', 'India', 9.9312, 76.2673, @lkp_org_approved, 1),
('Kerala Coastal Care', 'Kerala Foundation Admin', @lkp_org_society, 'REG-KL-002', 'Environment', 'Coral reef restoration and fisher folk livelihood support in Kerala', 'To coral reef restoration and fisher folk livelihood support in kerala through sustained community engagement and partnership.', 'regkl002@ngoconnect.test', '+919800000053', 'Kochi', 'Kerala', 'India', 9.9633, 76.3128, @lkp_org_approved, 1),
('Vidarbha Farmers Support', 'Vidarbha Foundation Admin', @lkp_org_trust, 'REG-NA-001', 'Rural Development', 'Farmer suicide prevention through crop insurance guidance in Vidarbha', 'To farmer suicide prevention through crop insurance guidance in vidarbha through sustained community engagement and partnership.', 'regna001@ngoconnect.test', '+919800000054', 'Nagpur', 'Maharashtra', 'India', 21.1458, 79.0882, @lkp_org_approved, 1),
('Nagpur Animal Welfare', 'Nagpur Foundation Admin', @lkp_org_society, 'REG-NA-002', 'Animal Welfare', 'Stray animal rescue, sterilisation and adoption drives in Nagpur', 'To stray animal rescue, sterilisation and adoption drives in nagpur through sustained community engagement and partnership.', 'regna002@ngoconnect.test', '+919800000055', 'Nagpur', 'Maharashtra', 'India', 21.1611, 79.105, @lkp_org_approved, 1),
('Surat Bal Shiksha Trust', 'Surat Foundation Admin', @lkp_org_trust, 'REG-SU-001', 'Child Welfare', 'Child labour prevention and school enrolment drives in Surat', 'To child labour prevention and school enrolment drives in surat through sustained community engagement and partnership.', 'regsu001@ngoconnect.test', '+919800000056', 'Surat', 'Gujarat', 'India', 21.1702, 72.8311, @lkp_org_approved, 1),
('Diamond City Green', 'Diamond Foundation Admin', @lkp_org_society, 'REG-SU-002', 'Environment', 'Air quality monitoring and green industry campaigns in Surat', 'To air quality monitoring and green industry campaigns in surat through sustained community engagement and partnership.', 'regsu002@ngoconnect.test', '+919800000057', 'Surat', 'Gujarat', 'India', 21.1948, 72.8256, @lkp_org_approved, 1),
('MP Adivasi Kalyan Samiti', 'MP Foundation Admin', @lkp_org_society, 'REG-MP-001', 'Rural Development', 'Tribal rights advocacy and forest produce marketing in Madhya Pradesh', 'To tribal rights advocacy and forest produce marketing in madhya pradesh through sustained community engagement and partnership.', 'regmp001@ngoconnect.test', '+919800000058', 'Bhopal', 'Madhya Pradesh', 'India', 23.2599, 77.4126, @lkp_org_approved, 1),
('Bhopal Animal Rescue', 'Bhopal Foundation Admin', @lkp_org_trust, 'REG-MP-002', 'Animal Welfare', 'Wildlife rescue and rehabilitation around Bhopal lakes', 'To wildlife rescue and rehabilitation around bhopal lakes through sustained community engagement and partnership.', 'regmp002@ngoconnect.test', '+919800000059', 'Bhopal', 'Madhya Pradesh', 'India', 23.2756, 77.4006, @lkp_org_approved, 1);

-- Store Org IDs
SET @o1 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-DL-001' AND IsDeleted=0);
SET @o2 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-DL-002' AND IsDeleted=0);
SET @o3 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-DL-003' AND IsDeleted=0);
SET @o4 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-DL-004' AND IsDeleted=0);
SET @o5 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-DL-005' AND IsDeleted=0);
SET @o6 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MH-001' AND IsDeleted=0);
SET @o7 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MH-002' AND IsDeleted=0);
SET @o8 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MH-003' AND IsDeleted=0);
SET @o9 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MH-004' AND IsDeleted=0);
SET @o10 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MH-005' AND IsDeleted=0);
SET @o11 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KA-001' AND IsDeleted=0);
SET @o12 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KA-002' AND IsDeleted=0);
SET @o13 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KA-003' AND IsDeleted=0);
SET @o14 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KA-004' AND IsDeleted=0);
SET @o15 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KA-005' AND IsDeleted=0);
SET @o16 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TN-001' AND IsDeleted=0);
SET @o17 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TN-002' AND IsDeleted=0);
SET @o18 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TN-003' AND IsDeleted=0);
SET @o19 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TN-004' AND IsDeleted=0);
SET @o20 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TS-001' AND IsDeleted=0);
SET @o21 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TS-002' AND IsDeleted=0);
SET @o22 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TS-003' AND IsDeleted=0);
SET @o23 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-TS-004' AND IsDeleted=0);
SET @o24 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-WB-001' AND IsDeleted=0);
SET @o25 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-WB-002' AND IsDeleted=0);
SET @o26 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-WB-003' AND IsDeleted=0);
SET @o27 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-WB-004' AND IsDeleted=0);
SET @o28 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-PU-001' AND IsDeleted=0);
SET @o29 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-PU-002' AND IsDeleted=0);
SET @o30 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-PU-003' AND IsDeleted=0);
SET @o31 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-PU-004' AND IsDeleted=0);
SET @o32 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-GJ-001' AND IsDeleted=0);
SET @o33 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-GJ-002' AND IsDeleted=0);
SET @o34 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-GJ-003' AND IsDeleted=0);
SET @o35 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-RJ-001' AND IsDeleted=0);
SET @o36 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-RJ-002' AND IsDeleted=0);
SET @o37 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-RJ-003' AND IsDeleted=0);
SET @o38 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-UP-001' AND IsDeleted=0);
SET @o39 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-UP-002' AND IsDeleted=0);
SET @o40 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-UP-003' AND IsDeleted=0);
SET @o41 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-CH-001' AND IsDeleted=0);
SET @o42 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-CH-002' AND IsDeleted=0);
SET @o43 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KL-001' AND IsDeleted=0);
SET @o44 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-KL-002' AND IsDeleted=0);
SET @o45 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-NA-001' AND IsDeleted=0);
SET @o46 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-NA-002' AND IsDeleted=0);
SET @o47 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-SU-001' AND IsDeleted=0);
SET @o48 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-SU-002' AND IsDeleted=0);
SET @o49 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MP-001' AND IsDeleted=0);
SET @o50 = (SELECT OrgId FROM Organisations WHERE RegNumber='REG-MP-002' AND IsDeleted=0);

-- ═══════════════════════════════════════════════════════════
-- 3. ORG MEMBERS
-- User 1 = ADMIN of all 50 orgs
-- Users 2-10 = MEMBER in ~2 orgs each (distributed)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO OrgMembers (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, JoinedAt, CreatedBy) VALUES
(@o1, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o2, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o3, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o4, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o5, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o6, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o7, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o8, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o9, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o10, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o11, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o12, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o13, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o14, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o15, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o16, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o17, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o18, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o19, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o20, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o21, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o22, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o23, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o24, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o25, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o26, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o27, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o28, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o29, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o30, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o31, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o32, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o33, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o34, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o35, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o36, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o37, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o38, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o39, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o40, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o41, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o42, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o43, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o44, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o45, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o46, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o47, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o48, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o49, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o50, @u1, @lkp_role_admin, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o1, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o1, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o2, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o2, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o3, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o3, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o4, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o4, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o5, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o5, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o6, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o6, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o7, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o7, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o8, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o8, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o9, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o9, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o10, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o10, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o11, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o11, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o12, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o12, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o13, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o13, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o14, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o14, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o15, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o15, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o16, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o16, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o17, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o17, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o18, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o18, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o19, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o19, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o20, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o20, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o21, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o21, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o22, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o22, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o23, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o23, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o24, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o24, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o25, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o25, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o26, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o26, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o27, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o27, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o28, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o28, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o29, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o29, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o30, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o30, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o31, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o31, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o32, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o32, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o33, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o33, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o34, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o34, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o35, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o35, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o36, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o36, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o37, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o37, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o38, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o38, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o39, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o39, @u2, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o40, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o40, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o41, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o41, @u3, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o42, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o42, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o43, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o43, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o44, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o44, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o45, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o45, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o46, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o46, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o47, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o47, @u6, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o48, @u8, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o48, @u10, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o49, @u7, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o49, @u5, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o50, @u4, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1),
(@o50, @u9, @lkp_role_member, @lkp_mem_approved, 1, 1, 1, NOW(), 1);

-- ═══════════════════════════════════════════════════════════
-- 4. PROJECTS (4 per NGO = 200 projects)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO Projects (OrgId, ProjectName, Category, Description, ProjectTypeLkpId, ScheduleTypeLkpId, LocationTypeLkpId, JoinTypeLkpId, StatusLkpId, OneTimeDate, RecurStart, RecurEnd, FlexFromDate, FlexToDate, City, State, MaxVolunteers, IsPublic, CreatedBy) VALUES
(@o1, 'Community Cleanup Drive - Delhi', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-10', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 15, 1, 1),
(@o1, 'Free Tuition Centre - Delhi', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Delhi', 'Delhi', 13, 1, 1),
(@o1, 'Health Camp and Checkup - Delhi', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 17, 1, 1),
(@o1, 'Digital Literacy Workshop - Delhi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Delhi', 'Delhi', 19, 1, 1),
(@o2, 'Free Tuition Centre - Delhi', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Delhi', 'Delhi', 50, 1, 1),
(@o2, 'Health Camp and Checkup - Delhi', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 20, 1, 1),
(@o2, 'Digital Literacy Workshop - Delhi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Delhi', 'Delhi', 37, 1, 1),
(@o2, 'Tree Plantation Drive - Delhi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 48, 1, 1),
(@o3, 'Health Camp and Checkup - Delhi', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 14, 1, 1),
(@o3, 'Digital Literacy Workshop - Delhi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Delhi', 'Delhi', 34, 1, 1),
(@o3, 'Tree Plantation Drive - Delhi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 34, 1, 1),
(@o3, 'Women Skill Workshop - Delhi', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Delhi', 'Delhi', 48, 1, 1),
(@o4, 'Digital Literacy Workshop - Delhi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Delhi', 'Delhi', 39, 1, 1),
(@o4, 'Tree Plantation Drive - Delhi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 43, 1, 1),
(@o4, 'Women Skill Workshop - Delhi', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Delhi', 'Delhi', 26, 1, 1),
(@o4, 'Blood Donation Camp - Delhi', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 45, 1, 1),
(@o5, 'Tree Plantation Drive - Delhi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 10, 1, 1),
(@o5, 'Women Skill Workshop - Delhi', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Delhi', 'Delhi', 17, 1, 1),
(@o5, 'Blood Donation Camp - Delhi', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Delhi', 'Delhi', 44, 1, 1),
(@o5, 'Rural Survey and Mapping - Delhi', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Delhi', 'Delhi', 27, 1, 1),
(@o6, 'Women Skill Workshop - Mumbai', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 31, 1, 1),
(@o6, 'Blood Donation Camp - Mumbai', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 17, 1, 1),
(@o6, 'Rural Survey and Mapping - Mumbai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Mumbai', 'Maharashtra', 28, 1, 1),
(@o6, 'Awareness Street Play - Mumbai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 37, 1, 1),
(@o7, 'Blood Donation Camp - Mumbai', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 20, 1, 1),
(@o7, 'Rural Survey and Mapping - Mumbai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Mumbai', 'Maharashtra', 39, 1, 1),
(@o7, 'Awareness Street Play - Mumbai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 10, 1, 1),
(@o7, 'Child Nutrition Program - Mumbai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 26, 1, 1),
(@o8, 'Rural Survey and Mapping - Mumbai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Mumbai', 'Maharashtra', 42, 1, 1),
(@o8, 'Awareness Street Play - Mumbai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 21, 1, 1),
(@o8, 'Child Nutrition Program - Mumbai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 42, 1, 1),
(@o8, 'Community Cleanup Drive - Mumbai', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-25', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 16, 1, 1),
(@o9, 'Awareness Street Play - Mumbai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 50, 1, 1),
(@o9, 'Child Nutrition Program - Mumbai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 29, 1, 1),
(@o9, 'Community Cleanup Drive - Mumbai', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-20', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 50, 1, 1),
(@o9, 'Free Tuition Centre - Mumbai', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 42, 1, 1),
(@o10, 'Child Nutrition Program - Mumbai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 48, 1, 1),
(@o10, 'Community Cleanup Drive - Mumbai', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-15', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 22, 1, 1),
(@o10, 'Free Tuition Centre - Mumbai', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Mumbai', 'Maharashtra', 19, 1, 1),
(@o10, 'Health Camp and Checkup - Mumbai', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Mumbai', 'Maharashtra', 33, 1, 1),
(@o11, 'Community Cleanup Drive - Bangalore', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-10', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 20, 1, 1),
(@o11, 'Free Tuition Centre - Bangalore', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bangalore', 'Karnataka', 44, 1, 1),
(@o11, 'Health Camp and Checkup - Bangalore', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 43, 1, 1),
(@o11, 'Digital Literacy Workshop - Bangalore', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Bangalore', 'Karnataka', 10, 1, 1),
(@o12, 'Free Tuition Centre - Bangalore', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bangalore', 'Karnataka', 48, 1, 1),
(@o12, 'Health Camp and Checkup - Bangalore', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 30, 1, 1),
(@o12, 'Digital Literacy Workshop - Bangalore', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Bangalore', 'Karnataka', 41, 1, 1),
(@o12, 'Tree Plantation Drive - Bangalore', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 11, 1, 1),
(@o13, 'Health Camp and Checkup - Bangalore', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 17, 1, 1),
(@o13, 'Digital Literacy Workshop - Bangalore', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Bangalore', 'Karnataka', 33, 1, 1),
(@o13, 'Tree Plantation Drive - Bangalore', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 29, 1, 1),
(@o13, 'Women Skill Workshop - Bangalore', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bangalore', 'Karnataka', 25, 1, 1),
(@o14, 'Digital Literacy Workshop - Bangalore', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Bangalore', 'Karnataka', 13, 1, 1),
(@o14, 'Tree Plantation Drive - Bangalore', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 25, 1, 1),
(@o14, 'Women Skill Workshop - Bangalore', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bangalore', 'Karnataka', 46, 1, 1),
(@o14, 'Blood Donation Camp - Bangalore', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 15, 1, 1),
(@o15, 'Tree Plantation Drive - Bangalore', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 15, 1, 1),
(@o15, 'Women Skill Workshop - Bangalore', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bangalore', 'Karnataka', 41, 1, 1),
(@o15, 'Blood Donation Camp - Bangalore', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Bangalore', 'Karnataka', 14, 1, 1),
(@o15, 'Rural Survey and Mapping - Bangalore', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Bangalore', 'Karnataka', 44, 1, 1),
(@o16, 'Women Skill Workshop - Chennai', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chennai', 'Tamil Nadu', 18, 1, 1),
(@o16, 'Blood Donation Camp - Chennai', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 18, 1, 1),
(@o16, 'Rural Survey and Mapping - Chennai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Chennai', 'Tamil Nadu', 40, 1, 1),
(@o16, 'Awareness Street Play - Chennai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 45, 1, 1),
(@o17, 'Blood Donation Camp - Chennai', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 20, 1, 1),
(@o17, 'Rural Survey and Mapping - Chennai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Chennai', 'Tamil Nadu', 26, 1, 1),
(@o17, 'Awareness Street Play - Chennai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 43, 1, 1),
(@o17, 'Child Nutrition Program - Chennai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chennai', 'Tamil Nadu', 48, 1, 1),
(@o18, 'Rural Survey and Mapping - Chennai', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Chennai', 'Tamil Nadu', 37, 1, 1),
(@o18, 'Awareness Street Play - Chennai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 23, 1, 1),
(@o18, 'Child Nutrition Program - Chennai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chennai', 'Tamil Nadu', 44, 1, 1),
(@o18, 'Community Cleanup Drive - Chennai', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-25', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 22, 1, 1),
(@o19, 'Awareness Street Play - Chennai', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 29, 1, 1),
(@o19, 'Child Nutrition Program - Chennai', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chennai', 'Tamil Nadu', 35, 1, 1),
(@o19, 'Community Cleanup Drive - Chennai', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-20', NULL, NULL, NULL, NULL, 'Chennai', 'Tamil Nadu', 33, 1, 1),
(@o19, 'Free Tuition Centre - Chennai', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chennai', 'Tamil Nadu', 38, 1, 1),
(@o20, 'Child Nutrition Program - Hyderabad', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Hyderabad', 'Telangana', 43, 1, 1),
(@o20, 'Community Cleanup Drive - Hyderabad', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-15', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 38, 1, 1),
(@o20, 'Free Tuition Centre - Hyderabad', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Hyderabad', 'Telangana', 17, 1, 1),
(@o20, 'Health Camp and Checkup - Hyderabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 25, 1, 1),
(@o21, 'Community Cleanup Drive - Hyderabad', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-10', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 24, 1, 1),
(@o21, 'Free Tuition Centre - Hyderabad', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Hyderabad', 'Telangana', 14, 1, 1),
(@o21, 'Health Camp and Checkup - Hyderabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 31, 1, 1),
(@o21, 'Digital Literacy Workshop - Hyderabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Hyderabad', 'Telangana', 11, 1, 1),
(@o22, 'Free Tuition Centre - Hyderabad', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Hyderabad', 'Telangana', 47, 1, 1),
(@o22, 'Health Camp and Checkup - Hyderabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 45, 1, 1),
(@o22, 'Digital Literacy Workshop - Hyderabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Hyderabad', 'Telangana', 24, 1, 1),
(@o22, 'Tree Plantation Drive - Hyderabad', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 47, 1, 1),
(@o23, 'Health Camp and Checkup - Hyderabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 24, 1, 1),
(@o23, 'Digital Literacy Workshop - Hyderabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Hyderabad', 'Telangana', 10, 1, 1),
(@o23, 'Tree Plantation Drive - Hyderabad', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Hyderabad', 'Telangana', 14, 1, 1),
(@o23, 'Women Skill Workshop - Hyderabad', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Hyderabad', 'Telangana', 50, 1, 1),
(@o24, 'Digital Literacy Workshop - Kolkata', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kolkata', 'West Bengal', 13, 1, 1),
(@o24, 'Tree Plantation Drive - Kolkata', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 24, 1, 1),
(@o24, 'Women Skill Workshop - Kolkata', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kolkata', 'West Bengal', 14, 1, 1),
(@o24, 'Blood Donation Camp - Kolkata', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 12, 1, 1),
(@o25, 'Tree Plantation Drive - Kolkata', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 31, 1, 1),
(@o25, 'Women Skill Workshop - Kolkata', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kolkata', 'West Bengal', 14, 1, 1),
(@o25, 'Blood Donation Camp - Kolkata', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 42, 1, 1),
(@o25, 'Rural Survey and Mapping - Kolkata', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kolkata', 'West Bengal', 25, 1, 1),
(@o26, 'Women Skill Workshop - Kolkata', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kolkata', 'West Bengal', 27, 1, 1),
(@o26, 'Blood Donation Camp - Kolkata', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 41, 1, 1),
(@o26, 'Rural Survey and Mapping - Kolkata', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kolkata', 'West Bengal', 23, 1, 1),
(@o26, 'Awareness Street Play - Kolkata', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 44, 1, 1),
(@o27, 'Blood Donation Camp - Kolkata', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 18, 1, 1),
(@o27, 'Rural Survey and Mapping - Kolkata', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kolkata', 'West Bengal', 46, 1, 1),
(@o27, 'Awareness Street Play - Kolkata', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Kolkata', 'West Bengal', 46, 1, 1),
(@o27, 'Child Nutrition Program - Kolkata', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kolkata', 'West Bengal', 40, 1, 1),
(@o28, 'Rural Survey and Mapping - Pune', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Pune', 'Maharashtra', 25, 1, 1),
(@o28, 'Awareness Street Play - Pune', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 40, 1, 1),
(@o28, 'Child Nutrition Program - Pune', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 36, 1, 1),
(@o28, 'Community Cleanup Drive - Pune', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-25', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 22, 1, 1),
(@o29, 'Awareness Street Play - Pune', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 16, 1, 1),
(@o29, 'Child Nutrition Program - Pune', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 16, 1, 1),
(@o29, 'Community Cleanup Drive - Pune', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-20', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 37, 1, 1),
(@o29, 'Free Tuition Centre - Pune', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 32, 1, 1),
(@o30, 'Child Nutrition Program - Pune', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 37, 1, 1),
(@o30, 'Community Cleanup Drive - Pune', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-15', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 36, 1, 1),
(@o30, 'Free Tuition Centre - Pune', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 39, 1, 1),
(@o30, 'Health Camp and Checkup - Pune', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 13, 1, 1),
(@o31, 'Community Cleanup Drive - Pune', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-10', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 16, 1, 1),
(@o31, 'Free Tuition Centre - Pune', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Pune', 'Maharashtra', 13, 1, 1),
(@o31, 'Health Camp and Checkup - Pune', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Pune', 'Maharashtra', 35, 1, 1),
(@o31, 'Digital Literacy Workshop - Pune', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Pune', 'Maharashtra', 31, 1, 1),
(@o32, 'Free Tuition Centre - Ahmedabad', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Ahmedabad', 'Gujarat', 16, 1, 1),
(@o32, 'Health Camp and Checkup - Ahmedabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 25, 1, 1),
(@o32, 'Digital Literacy Workshop - Ahmedabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Ahmedabad', 'Gujarat', 22, 1, 1),
(@o32, 'Tree Plantation Drive - Ahmedabad', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 22, 1, 1),
(@o33, 'Health Camp and Checkup - Ahmedabad', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 44, 1, 1),
(@o33, 'Digital Literacy Workshop - Ahmedabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Ahmedabad', 'Gujarat', 38, 1, 1),
(@o33, 'Tree Plantation Drive - Ahmedabad', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 18, 1, 1),
(@o33, 'Women Skill Workshop - Ahmedabad', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Ahmedabad', 'Gujarat', 37, 1, 1),
(@o34, 'Digital Literacy Workshop - Ahmedabad', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Ahmedabad', 'Gujarat', 21, 1, 1),
(@o34, 'Tree Plantation Drive - Ahmedabad', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 27, 1, 1),
(@o34, 'Women Skill Workshop - Ahmedabad', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Ahmedabad', 'Gujarat', 39, 1, 1),
(@o34, 'Blood Donation Camp - Ahmedabad', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Ahmedabad', 'Gujarat', 25, 1, 1),
(@o35, 'Tree Plantation Drive - Jaipur', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 14, 1, 1),
(@o35, 'Women Skill Workshop - Jaipur', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Jaipur', 'Rajasthan', 38, 1, 1),
(@o35, 'Blood Donation Camp - Jaipur', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 45, 1, 1),
(@o35, 'Rural Survey and Mapping - Jaipur', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Jaipur', 'Rajasthan', 16, 1, 1),
(@o36, 'Women Skill Workshop - Jaipur', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Jaipur', 'Rajasthan', 13, 1, 1),
(@o36, 'Blood Donation Camp - Jaipur', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 44, 1, 1),
(@o36, 'Rural Survey and Mapping - Jaipur', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Jaipur', 'Rajasthan', 10, 1, 1),
(@o36, 'Awareness Street Play - Jaipur', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 15, 1, 1),
(@o37, 'Blood Donation Camp - Jaipur', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 25, 1, 1),
(@o37, 'Rural Survey and Mapping - Jaipur', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Jaipur', 'Rajasthan', 20, 1, 1),
(@o37, 'Awareness Street Play - Jaipur', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Jaipur', 'Rajasthan', 36, 1, 1),
(@o37, 'Child Nutrition Program - Jaipur', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Jaipur', 'Rajasthan', 41, 1, 1),
(@o38, 'Rural Survey and Mapping - Lucknow', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Lucknow', 'Uttar Pradesh', 40, 1, 1),
(@o38, 'Awareness Street Play - Lucknow', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 23, 1, 1),
(@o38, 'Child Nutrition Program - Lucknow', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Lucknow', 'Uttar Pradesh', 35, 1, 1),
(@o38, 'Community Cleanup Drive - Lucknow', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-25', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 13, 1, 1),
(@o39, 'Awareness Street Play - Lucknow', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 20, 1, 1),
(@o39, 'Child Nutrition Program - Lucknow', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Lucknow', 'Uttar Pradesh', 34, 1, 1),
(@o39, 'Community Cleanup Drive - Lucknow', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-20', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 10, 1, 1),
(@o39, 'Free Tuition Centre - Lucknow', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Lucknow', 'Uttar Pradesh', 34, 1, 1),
(@o40, 'Child Nutrition Program - Lucknow', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Lucknow', 'Uttar Pradesh', 26, 1, 1),
(@o40, 'Community Cleanup Drive - Lucknow', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-15', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 39, 1, 1),
(@o40, 'Free Tuition Centre - Lucknow', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Lucknow', 'Uttar Pradesh', 28, 1, 1),
(@o40, 'Health Camp and Checkup - Lucknow', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Lucknow', 'Uttar Pradesh', 37, 1, 1),
(@o41, 'Community Cleanup Drive - Chandigarh', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-10', NULL, NULL, NULL, NULL, 'Chandigarh', 'Punjab', 45, 1, 1),
(@o41, 'Free Tuition Centre - Chandigarh', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chandigarh', 'Punjab', 41, 1, 1),
(@o41, 'Health Camp and Checkup - Chandigarh', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Chandigarh', 'Punjab', 19, 1, 1),
(@o41, 'Digital Literacy Workshop - Chandigarh', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Chandigarh', 'Punjab', 22, 1, 1),
(@o42, 'Free Tuition Centre - Chandigarh', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Chandigarh', 'Punjab', 28, 1, 1),
(@o42, 'Health Camp and Checkup - Chandigarh', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Chandigarh', 'Punjab', 23, 1, 1),
(@o42, 'Digital Literacy Workshop - Chandigarh', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Chandigarh', 'Punjab', 13, 1, 1),
(@o42, 'Tree Plantation Drive - Chandigarh', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Chandigarh', 'Punjab', 47, 1, 1),
(@o43, 'Health Camp and Checkup - Kochi', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Kochi', 'Kerala', 44, 1, 1),
(@o43, 'Digital Literacy Workshop - Kochi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kochi', 'Kerala', 13, 1, 1),
(@o43, 'Tree Plantation Drive - Kochi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Kochi', 'Kerala', 30, 1, 1),
(@o43, 'Women Skill Workshop - Kochi', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kochi', 'Kerala', 13, 1, 1),
(@o44, 'Digital Literacy Workshop - Kochi', 'Education', 'Hands-on smartphone and internet training for senior citizens and homemakers.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_hybrid, @lkp_join_open, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Kochi', 'Kerala', 13, 1, 1),
(@o44, 'Tree Plantation Drive - Kochi', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Kochi', 'Kerala', 47, 1, 1),
(@o44, 'Women Skill Workshop - Kochi', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Kochi', 'Kerala', 40, 1, 1),
(@o44, 'Blood Donation Camp - Kochi', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Kochi', 'Kerala', 42, 1, 1),
(@o45, 'Tree Plantation Drive - Nagpur', 'Environment', 'Plant 500 saplings near the riverbank with follow-up watering schedule.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Nagpur', 'Maharashtra', 43, 1, 1),
(@o45, 'Women Skill Workshop - Nagpur', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Nagpur', 'Maharashtra', 20, 1, 1),
(@o45, 'Blood Donation Camp - Nagpur', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-20', NULL, NULL, NULL, NULL, 'Nagpur', 'Maharashtra', 13, 1, 1),
(@o45, 'Rural Survey and Mapping - Nagpur', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Nagpur', 'Maharashtra', 42, 1, 1),
(@o46, 'Women Skill Workshop - Nagpur', 'Women Empowerment', 'Tailoring, embroidery and entrepreneurship training for women in the community.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Nagpur', 'Maharashtra', 15, 1, 1),
(@o46, 'Blood Donation Camp - Nagpur', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-15', NULL, NULL, NULL, NULL, 'Nagpur', 'Maharashtra', 21, 1, 1),
(@o46, 'Rural Survey and Mapping - Nagpur', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Nagpur', 'Maharashtra', 14, 1, 1),
(@o46, 'Awareness Street Play - Nagpur', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-25', NULL, NULL, NULL, NULL, 'Nagpur', 'Maharashtra', 48, 1, 1),
(@o47, 'Blood Donation Camp - Surat', 'Healthcare', 'Organised blood donation drive in partnership with local hospitals.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-10', NULL, NULL, NULL, NULL, 'Surat', 'Gujarat', 14, 1, 1),
(@o47, 'Rural Survey and Mapping - Surat', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Surat', 'Gujarat', 25, 1, 1),
(@o47, 'Awareness Street Play - Surat', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-20', NULL, NULL, NULL, NULL, 'Surat', 'Gujarat', 35, 1, 1),
(@o47, 'Child Nutrition Program - Surat', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Surat', 'Gujarat', 17, 1, 1),
(@o48, 'Rural Survey and Mapping - Surat', 'Rural Development', 'Door-to-door survey to map needs of 500 households in surrounding villages.', @lkp_proj_flex, @lkp_proj_flex, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, NULL, NULL, '2026-06-01', '2026-12-31', 'Surat', 'Gujarat', 46, 1, 1),
(@o48, 'Awareness Street Play - Surat', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-15', NULL, NULL, NULL, NULL, 'Surat', 'Gujarat', 25, 1, 1),
(@o48, 'Child Nutrition Program - Surat', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Surat', 'Gujarat', 47, 1, 1),
(@o48, 'Community Cleanup Drive - Surat', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-25', NULL, NULL, NULL, NULL, 'Surat', 'Gujarat', 48, 1, 1),
(@o49, 'Awareness Street Play - Bhopal', 'Environment', 'Street march and street play to raise awareness on plastic pollution.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_done, '2026-05-10', NULL, NULL, NULL, NULL, 'Bhopal', 'Madhya Pradesh', 12, 1, 1),
(@o49, 'Child Nutrition Program - Bhopal', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bhopal', 'Madhya Pradesh', 49, 1, 1),
(@o49, 'Community Cleanup Drive - Bhopal', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-20', NULL, NULL, NULL, NULL, 'Bhopal', 'Madhya Pradesh', 15, 1, 1),
(@o49, 'Free Tuition Centre - Bhopal', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bhopal', 'Madhya Pradesh', 36, 1, 1),
(@o50, 'Child Nutrition Program - Bhopal', 'Child Welfare', 'Mid-day meal support and nutritional assessment for children under 5.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bhopal', 'Madhya Pradesh', 47, 1, 1),
(@o50, 'Community Cleanup Drive - Bhopal', 'Environment', 'Monthly cleanup drive engaging volunteers for waste collection and plastic segregation.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_active, '2026-07-15', NULL, NULL, NULL, NULL, 'Bhopal', 'Madhya Pradesh', 46, 1, 1),
(@o50, 'Free Tuition Centre - Bhopal', 'Education', 'Weekly tutoring sessions for underprivileged children in grades 6 to 10.', @lkp_proj_recur, @lkp_proj_recur, @lkp_loc_inperson, @lkp_join_approval, @lkp_proj_active, NULL, '2026-01-01', '2026-12-31', NULL, NULL, 'Bhopal', 'Madhya Pradesh', 43, 1, 1),
(@o50, 'Health Camp and Checkup - Bhopal', 'Healthcare', 'Free health screening for blood pressure, diabetes, eye and dental checkups.', @lkp_proj_onetime, @lkp_proj_onetime, @lkp_loc_inperson, @lkp_join_open, @lkp_proj_upcoming, '2026-08-25', NULL, NULL, NULL, NULL, 'Bhopal', 'Madhya Pradesh', 30, 1, 1);

-- ═══════════════════════════════════════════════════════════
-- 5. PROJECT SESSIONS
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
SELECT p.ProjectId,
       CASE
         WHEN p.StatusLkpId = @lkp_proj_done     THEN COALESCE(p.OneTimeDate, '2026-05-10')
         WHEN p.StatusLkpId = @lkp_proj_upcoming THEN DATE_ADD(CURDATE(), INTERVAL 30 DAY)
         ELSE CURDATE()
       END,
       '09:00:00', '13:00:00', p.MaxVolunteers,
       CASE WHEN p.StatusLkpId = @lkp_proj_done THEN @lkp_sess_done ELSE @lkp_sess_upcoming END,
       1
FROM   Projects p
WHERE  p.IsDeleted = 0
  AND  p.OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0);

-- Second session for recurring/flexible projects
INSERT IGNORE INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
SELECT p.ProjectId,
       DATE_ADD(CURDATE(), INTERVAL 14 DAY),
       '14:00:00', '17:00:00', p.MaxVolunteers, @lkp_sess_upcoming, 1
FROM   Projects p
WHERE  p.IsDeleted = 0
  AND  p.ProjectTypeLkpId IN (@lkp_proj_recur, @lkp_proj_flex)
  AND  p.OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0);


-- ═══════════════════════════════════════════════════════════
-- 6. PROJECT SKILLS (2-3 per project via category mapping)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO ProjectSkills (ProjectId, SkillName)
SELECT p.ProjectId, s.SkillName
FROM   Projects p
JOIN (
    SELECT 'Teaching'                AS SkillName, 'Education'          AS cat UNION ALL
    SELECT 'Communication',                         'Education'               UNION ALL
    SELECT 'Waste Management',                       'Environment'             UNION ALL
    SELECT 'Environmental Awareness',                'Environment'             UNION ALL
    SELECT 'First Aid',                              'Healthcare'              UNION ALL
    SELECT 'Medical Knowledge',                      'Healthcare'              UNION ALL
    SELECT 'Tailoring',                              'Women Empowerment'       UNION ALL
    SELECT 'Business Skills',                        'Women Empowerment'       UNION ALL
    SELECT 'Child Care',                             'Child Welfare'           UNION ALL
    SELECT 'Nutrition',                              'Child Welfare'           UNION ALL
    SELECT 'Field Work',                             'Rural Development'       UNION ALL
    SELECT 'Research',                               'Rural Development'       UNION ALL
    SELECT 'Public Speaking',                        'Arts & Culture'          UNION ALL
    SELECT 'Animal Care',                            'Animal Welfare'          UNION ALL
    SELECT 'Empathy',                                'Elderly Care'            UNION ALL
    SELECT 'Teamwork',                               'Elderly Care'
) s ON p.Category = s.cat
WHERE  p.IsDeleted = 0
  AND  p.OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0);

-- Add Teamwork as fallback skill for any project still without skills
INSERT IGNORE INTO ProjectSkills (ProjectId, SkillName)
SELECT p.ProjectId, 'Teamwork'
FROM   Projects p
WHERE  p.IsDeleted = 0
  AND  p.OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0)
  AND  NOT EXISTS (SELECT 1 FROM ProjectSkills ps WHERE ps.ProjectId = p.ProjectId);


-- ═══════════════════════════════════════════════════════════
-- 7. POSTS (80 posts across 50 orgs)
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO Posts (OrgId, UserId, PostTypeLkpId, Content, VisibilityLkpId, LikeCount, CommentCount, CreatedBy, CreatedAt) VALUES
(@o1, @u1, @lkp_post_general, 'We are thrilled to share that our literacy program has helped 1200 children learn to read this year. Every child deserves access to quality education. Thank you to all our volunteers and supporters!', @lkp_vis_members, 68, 5, 1, DATE_SUB(NOW(), INTERVAL 52 DAY)),
(@o2, @u5, @lkp_post_announce, 'Volunteers needed this Sunday for our upcoming health camp! We are setting up free checkup stalls for blood pressure, diabetes, and eye care. Register now to join us.', @lkp_vis_public, 27, 2, 1, DATE_SUB(NOW(), INTERVAL 48 DAY)),
(@o3, @u9, @lkp_post_event, 'Join us this weekend for our annual tree plantation drive! We will be planting 500 saplings near the riverbank. Bring your family and friends - gloves and tools provided.', @lkp_vis_public, 143, 21, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o4, @u1, @lkp_post_general, 'Our women skill development batch has graduated 45 women this month! These incredible individuals have mastered tailoring and have already started taking orders. Proud of every one of them.', @lkp_vis_public, 40, 8, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o5, @u9, @lkp_post_announce, 'We have partnered with the local municipal corporation to set up 3 new community libraries. Books, computers, and internet access - free for all residents!', @lkp_vis_public, 85, 15, 1, DATE_SUB(NOW(), INTERVAL 20 DAY)),
(@o6, @u1, @lkp_post_general, 'Last weekend beach cleanup was a massive success! 320 volunteers collected over 2 tonnes of plastic waste. The ocean thanks you all.', @lkp_vis_public, 111, 5, 1, DATE_SUB(NOW(), INTERVAL 76 DAY)),
(@o7, @u7, @lkp_post_event, 'This Saturday: FREE blood donation camp at our centre from 9AM to 3PM. Every unit of blood can save up to 3 lives. Walk in or register in advance.', @lkp_vis_public, 17, 0, 1, DATE_SUB(NOW(), INTERVAL 40 DAY)),
(@o8, @u8, @lkp_post_general, 'We just completed our 100th free health camp! In 3 years, we have served over 85000 patients who had no access to private healthcare. This is why we do what we do.', @lkp_vis_members, 26, 2, 1, DATE_SUB(NOW(), INTERVAL 11 DAY)),
(@o9, @u3, @lkp_post_announce, 'Calling all teachers and retired educators! We need volunteer tutors for our evening classes for working children. Even 2 hours per week can transform a life.', @lkp_vis_public, 32, 1, 1, DATE_SUB(NOW(), INTERVAL 37 DAY)),
(@o10, @u7, @lkp_post_general, 'Our team spent 3 days in flood-affected villages distributing food, clothes, and hygiene kits to 800 families. Grateful for every donor who made this possible.', @lkp_vis_public, 146, 30, 1, DATE_SUB(NOW(), INTERVAL 33 DAY)),
(@o11, @u8, @lkp_post_event, 'Community open day this Sunday! Come meet our team, see our project impact, meet the beneficiaries, and learn how you can contribute. Refreshments and cultural performances planned!', @lkp_vis_public, 9, 19, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o12, @u9, @lkp_post_general, 'Happy to report that 18 of our scholarship students have secured college admissions this year - 3 at IIT and 5 at NIT. Education is the greatest equaliser.', @lkp_vis_public, 123, 13, 1, DATE_SUB(NOW(), INTERVAL 77 DAY)),
(@o13, @u9, @lkp_post_announce, 'Winter blanket collection drive is open! Drop off woollen blankets, shawls, and warm clothes at any of our 12 collection points across the city.', @lkp_vis_public, 144, 20, 1, DATE_SUB(NOW(), INTERVAL 1 DAY)),
(@o14, @u7, @lkp_post_general, 'Our urban garden project now has 250 active community plots! Families are growing vegetables, reducing food bills, and building community bonds. Urban farming is the future.', @lkp_vis_public, 131, 27, 1, DATE_SUB(NOW(), INTERVAL 87 DAY)),
(@o15, @u9, @lkp_post_event, 'Awareness walkathon this Sunday at 7AM from City Park! Walk 5 km to raise awareness on malnutrition among children. Register teams online - prizes for top fundraisers!', @lkp_vis_members, 124, 33, 1, DATE_SUB(NOW(), INTERVAL 85 DAY)),
(@o16, @u7, @lkp_post_general, 'We installed 6 water purification units in drought-prone villages this month. Clean water is not a luxury - it is a right. Grateful to our CSR partners for funding this.', @lkp_vis_public, 95, 32, 1, DATE_SUB(NOW(), INTERVAL 4 DAY)),
(@o17, @u3, @lkp_post_announce, 'Our legal aid clinic is now open on the 1st and 3rd Saturday of every month. Free consultations for domestic violence survivors, property disputes, and labour rights cases.', @lkp_vis_public, 21, 31, 1, DATE_SUB(NOW(), INTERVAL 84 DAY)),
(@o18, @u5, @lkp_post_general, 'Exciting news! We have been selected as one of the top 10 NGOs in our state for the Chief Minister Social Impact Award. This belongs to our 500 volunteers.', @lkp_vis_public, 43, 21, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o19, @u9, @lkp_post_event, 'Mental health awareness workshop next Friday evening. Join counsellors, survivors, and advocates for an open, stigma-free conversation. Limited seats - register now!', @lkp_vis_public, 100, 4, 1, DATE_SUB(NOW(), INTERVAL 58 DAY)),
(@o20, @u7, @lkp_post_general, 'Every Saturday, our 40 volunteers visit the homes of 120 elderly citizens who live alone. A cup of tea, a warm conversation, and the reminder that someone cares.', @lkp_vis_public, 146, 21, 1, DATE_SUB(NOW(), INTERVAL 2 DAY)),
(@o21, @u4, @lkp_post_announce, 'New batch registrations open for our digital literacy program! Seniors, homemakers, and first-time smartphone users - all are welcome. Classes are free, batches start next Monday.', @lkp_vis_public, 150, 5, 1, DATE_SUB(NOW(), INTERVAL 80 DAY)),
(@o22, @u6, @lkp_post_general, 'We rescued 18 injured animals this month and successfully treated and released 14 of them back to their habitat. Our veterinary team works round the clock.', @lkp_vis_members, 3, 22, 1, DATE_SUB(NOW(), INTERVAL 29 DAY)),
(@o23, @u7, @lkp_post_event, 'Heritage walk this Sunday - explore the forgotten history of our city with our volunteer guides. Proceeds support our arts preservation program.', @lkp_vis_public, 136, 32, 1, DATE_SUB(NOW(), INTERVAL 7 DAY)),
(@o24, @u5, @lkp_post_general, 'Our mobile health van has now visited 75 villages across the district. We conduct checkups, dispense medicine, and refer critical cases - all for free. 10000+ patients served.', @lkp_vis_public, 126, 40, 1, DATE_SUB(NOW(), INTERVAL 29 DAY)),
(@o25, @u9, @lkp_post_announce, 'We are launching our rural entrepreneurship program next month! If you have expertise in marketing, accounts, or product design, we need your mentoring skills.', @lkp_vis_public, 123, 11, 1, DATE_SUB(NOW(), INTERVAL 19 DAY)),
(@o26, @u9, @lkp_post_general, 'This Diwali, we distributed sweets and stationery kits to 600 children in our care homes. A brighter Diwali, a safer community.', @lkp_vis_public, 113, 24, 1, DATE_SUB(NOW(), INTERVAL 59 DAY)),
(@o27, @u1, @lkp_post_event, 'Mangrove planting day next weekend at the estuary. We need 100 volunteers - no experience needed. Transport and lunch provided.', @lkp_vis_public, 2, 8, 1, DATE_SUB(NOW(), INTERVAL 58 DAY)),
(@o28, @u4, @lkp_post_general, 'Our crop insurance guidance camp helped 340 farmers file insurance claims they never knew they were entitled to. Total claims filed: Rs 1.8 crore.', @lkp_vis_public, 5, 16, 1, DATE_SUB(NOW(), INTERVAL 45 DAY)),
(@o29, @u5, @lkp_post_announce, 'Important update: Our new centre in the industrial area is now operational! Drop-in hours are Monday to Saturday, 10AM to 6PM.', @lkp_vis_members, 111, 40, 1, DATE_SUB(NOW(), INTERVAL 53 DAY)),
(@o30, @u1, @lkp_post_general, 'Heartfelt thanks to the 200 students from three colleges who spent their weekend with us at the rural survey camp. Your energy gave our data wings.', @lkp_vis_public, 27, 39, 1, DATE_SUB(NOW(), INTERVAL 8 DAY)),
(@o31, @u9, @lkp_post_general, 'We planted 1000 trees along the river this monsoon with the help of the forest department and 150 volunteers. In 10 years, this will be a green corridor.', @lkp_vis_public, 90, 5, 1, DATE_SUB(NOW(), INTERVAL 10 DAY)),
(@o32, @u7, @lkp_post_event, 'Volunteer recognition night this Thursday! We will be honouring our top 30 volunteers of the year with certificates and awards. All NGO members welcome.', @lkp_vis_public, 2, 34, 1, DATE_SUB(NOW(), INTERVAL 48 DAY)),
(@o33, @u2, @lkp_post_announce, 'Our school book collection drive has gathered 4500 books! These will be distributed to 15 government schools next week.', @lkp_vis_public, 139, 40, 1, DATE_SUB(NOW(), INTERVAL 51 DAY)),
(@o34, @u1, @lkp_post_general, '6 women from our self-help group just sold their first collection of embroidered handbags at the craft fair and sold out completely! Business skills plus creativity equals magic.', @lkp_vis_public, 82, 16, 1, DATE_SUB(NOW(), INTERVAL 60 DAY)),
(@o35, @u1, @lkp_post_general, 'Our volunteer coordinators did an outstanding job managing 400 volunteers during the flood relief operations this week.', @lkp_vis_public, 143, 21, 1, DATE_SUB(NOW(), INTERVAL 53 DAY)),
(@o36, @u6, @lkp_post_event, 'Free legal awareness camp on property rights for women this Saturday, 10AM to 1PM at our main office. Bring your queries.', @lkp_vis_members, 6, 40, 1, DATE_SUB(NOW(), INTERVAL 81 DAY)),
(@o37, @u3, @lkp_post_announce, 'We are expanding our mental health program to 3 new districts! Looking for trained counsellors willing to volunteer 4 hours per month.', @lkp_vis_public, 107, 4, 1, DATE_SUB(NOW(), INTERVAL 86 DAY)),
(@o38, @u3, @lkp_post_general, 'Our nature trail cleanup brought together school kids, parents, and senior citizens for a morning of teamwork and environmental education.', @lkp_vis_public, 95, 15, 1, DATE_SUB(NOW(), INTERVAL 10 DAY)),
(@o39, @u1, @lkp_post_general, 'Update from our Sundarban project: 40000 mangrove saplings planted in the last 18 months. The community is already reporting improved fish yields.', @lkp_vis_public, 132, 24, 1, DATE_SUB(NOW(), INTERVAL 68 DAY)),
(@o40, @u5, @lkp_post_event, 'Donation drive this weekend - clothes, shoes, toys, and books for children in need. Drop points at our 8 offices across the city.', @lkp_vis_public, 37, 18, 1, DATE_SUB(NOW(), INTERVAL 49 DAY)),
(@o41, @u6, @lkp_post_announce, 'Urgent: We need 20 more volunteers for our night shelter operations during the cold wave. Shifts are 8PM to 8AM. Warm meals and transport provided.', @lkp_vis_public, 32, 34, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o42, @u9, @lkp_post_general, 'Our elder care team organised a picnic for 60 senior citizens today - music, stories, laughter, and a delicious meal.', @lkp_vis_public, 30, 40, 1, DATE_SUB(NOW(), INTERVAL 21 DAY)),
(@o43, @u10, @lkp_post_general, 'Big milestone: Our animal rescue centre has now completed 1000 successful adoptions! Every animal deserves a loving home. Thank you to our amazing adoption families.', @lkp_vis_members, 98, 27, 1, DATE_SUB(NOW(), INTERVAL 7 DAY)),
(@o44, @u3, @lkp_post_event, 'Pottery and craft workshop for children this Sunday! Our tribal artisans will teach traditional clay work to city kids. Limited spots - ages 8 to 16.', @lkp_vis_public, 116, 1, 1, DATE_SUB(NOW(), INTERVAL 44 DAY)),
(@o45, @u8, @lkp_post_announce, 'Registration open for our 3-month entrepreneurship bootcamp for women. Topics: business planning, digital marketing, finance, and legal basics. Fully free, certificate provided.', @lkp_vis_public, 115, 19, 1, DATE_SUB(NOW(), INTERVAL 54 DAY)),
(@o46, @u1, @lkp_post_general, 'Our reading circle completed its 50th session today! 120 children, 50 Saturdays, and thousands of stories shared. Literacy is not just about reading - it is about dreaming.', @lkp_vis_public, 40, 33, 1, DATE_SUB(NOW(), INTERVAL 41 DAY)),
(@o47, @u9, @lkp_post_general, 'This week our team walked into the most remote villages of the district to distribute solar lamps to 200 households. Light changes everything.', @lkp_vis_public, 131, 35, 1, DATE_SUB(NOW(), INTERVAL 17 DAY)),
(@o48, @u6, @lkp_post_event, 'Documentary film screening on plastic pollution this Friday evening. Free entry. Discussion with environmental activists to follow.', @lkp_vis_public, 128, 6, 1, DATE_SUB(NOW(), INTERVAL 69 DAY)),
(@o49, @u6, @lkp_post_announce, 'We are raising funds to build a new skill training centre for 300 women per year. Every Rs 500 contribution buys one woman a month of training.', @lkp_vis_public, 57, 36, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o50, @u2, @lkp_post_general, 'Grateful to the 15 doctors who spent their Sunday with our free health camp. Their expertise and smiles brought hope to 800 patients today.', @lkp_vis_members, 69, 32, 1, DATE_SUB(NOW(), INTERVAL 31 DAY)),
(@o1, @u4, @lkp_post_general, 'Our tribal crafts fair raised Rs 4.2 lakh for 30 artisan families! Each piece sold is a livelihood sustained, a tradition preserved.', @lkp_vis_public, 82, 16, 1, DATE_SUB(NOW(), INTERVAL 50 DAY)),
(@o2, @u1, @lkp_post_announce, 'Applications open for our annual scholarship - Class 10 to 12 students from families earning under Rs 2 lakh per annum are eligible.', @lkp_vis_public, 128, 5, 1, DATE_SUB(NOW(), INTERVAL 25 DAY)),
(@o3, @u9, @lkp_post_event, 'Yoga and wellness camp for senior citizens at City Park this Saturday, 6AM to 8AM. Led by certified instructors. Free for all.', @lkp_vis_public, 51, 1, 1, DATE_SUB(NOW(), INTERVAL 24 DAY)),
(@o4, @u5, @lkp_post_general, 'We have just crossed 10000 volunteer registrations on our platform! From engineers to teachers, students to retirees - our community is a force for good.', @lkp_vis_public, 144, 14, 1, DATE_SUB(NOW(), INTERVAL 10 DAY)),
(@o5, @u10, @lkp_post_general, 'Our team spent the week auditing water quality in 30 village wells. Results are alarming and we are working with the panchayat to address contamination immediately.', @lkp_vis_public, 81, 5, 1, DATE_SUB(NOW(), INTERVAL 43 DAY)),
(@o6, @u9, @lkp_post_event, 'Cycling for a cause - join our charity cycling event on August 15th! 21 km route through the city, raising funds for our children nutrition program.', @lkp_vis_public, 137, 8, 1, DATE_SUB(NOW(), INTERVAL 68 DAY)),
(@o7, @u3, @lkp_post_announce, 'We urgently need medical supplies for our mobile health van: BP monitors, glucometers, and first-aid kits. If you can donate, please contact our team.', @lkp_vis_members, 123, 31, 1, DATE_SUB(NOW(), INTERVAL 50 DAY)),
(@o8, @u1, @lkp_post_general, 'Our volunteers taught 80 migrant workers how to use UPI and digital wallets this week. Financial inclusion is the key to dignity.', @lkp_vis_public, 65, 36, 1, DATE_SUB(NOW(), INTERVAL 62 DAY)),
(@o9, @u6, @lkp_post_general, 'Celebrating 5 years of this NGO today! From 3 volunteers and one room to 800 volunteers and 15 active projects. None of this would exist without your support.', @lkp_vis_public, 101, 14, 1, DATE_SUB(NOW(), INTERVAL 64 DAY)),
(@o10, @u3, @lkp_post_event, 'Mega career fair for youth from underserved communities - 40 employers, 500 seats, free registration. Bring your resume.', @lkp_vis_public, 1, 38, 1, DATE_SUB(NOW(), INTERVAL 77 DAY)),
(@o11, @u8, @lkp_post_announce, 'Our new toll-free helpline for elderly abuse is now live. Spread the word - no senior should suffer in silence.', @lkp_vis_public, 87, 37, 1, DATE_SUB(NOW(), INTERVAL 15 DAY)),
(@o12, @u1, @lkp_post_general, 'Last month our rural survey team covered 300 km on foot, bicycles, and bullock carts to reach the most isolated communities.', @lkp_vis_public, 92, 29, 1, DATE_SUB(NOW(), INTERVAL 46 DAY)),
(@o13, @u7, @lkp_post_general, 'Our first cohort of 25 women trained in plumbing and electrical work has been placed with construction firms across the city. Breaking gender barriers!', @lkp_vis_public, 80, 22, 1, DATE_SUB(NOW(), INTERVAL 27 DAY)),
(@o14, @u8, @lkp_post_event, 'Photography contest on the theme Faces of Hope - open to all. Best 20 photos exhibited at our annual fundraiser.', @lkp_vis_members, 87, 12, 1, DATE_SUB(NOW(), INTERVAL 23 DAY)),
(@o15, @u7, @lkp_post_announce, 'We have received approval to expand our shelter home capacity from 40 to 80 children. Construction begins next month.', @lkp_vis_public, 15, 26, 1, DATE_SUB(NOW(), INTERVAL 48 DAY)),
(@o16, @u9, @lkp_post_general, 'Our beach cleanup collected 3.5 tonnes of plastic this season. We are also working with fisherfolk to remove ghost nets from the ocean.', @lkp_vis_public, 67, 11, 1, DATE_SUB(NOW(), INTERVAL 71 DAY)),
(@o17, @u7, @lkp_post_general, 'The monsoon has arrived and so has the risk of vector diseases. Our team is conducting free dengue awareness sessions in high-risk areas.', @lkp_vis_public, 94, 4, 1, DATE_SUB(NOW(), INTERVAL 37 DAY)),
(@o18, @u2, @lkp_post_event, 'Annual charity cricket tournament this Sunday - 8 teams, great food, and all proceeds to our child nutrition program.', @lkp_vis_public, 67, 32, 1, DATE_SUB(NOW(), INTERVAL 77 DAY)),
(@o19, @u6, @lkp_post_announce, 'Volunteer induction this Saturday at 10AM. If you registered online in the last 30 days, please attend with a valid ID.', @lkp_vis_public, 14, 24, 1, DATE_SUB(NOW(), INTERVAL 6 DAY)),
(@o20, @u10, @lkp_post_general, 'Our nature education camp for 200 school children was a huge success. Butterfly spotting, soil science, water testing - learning beyond textbooks.', @lkp_vis_public, 99, 19, 1, DATE_SUB(NOW(), INTERVAL 13 DAY)),
(@o21, @u8, @lkp_post_general, 'We are now working with the railway station to identify abandoned children and connect them with child protection services. 27 children helped in 3 months.', @lkp_vis_members, 146, 20, 1, DATE_SUB(NOW(), INTERVAL 31 DAY)),
(@o22, @u8, @lkp_post_event, 'Handicraft mela this weekend - buy beautiful handmade products from our women SHG members. 100 percent of proceeds go directly to the artisans.', @lkp_vis_public, 68, 28, 1, DATE_SUB(NOW(), INTERVAL 72 DAY)),
(@o23, @u10, @lkp_post_announce, 'We are partnering with a national bank to open zero-balance accounts for 1000 unbanked rural women. Volunteers needed for enrollment drives.', @lkp_vis_public, 88, 15, 1, DATE_SUB(NOW(), INTERVAL 88 DAY)),
(@o24, @u8, @lkp_post_general, 'Our Diwali outreach reached 1500 families in resettlement colonies with food kits, sweets, and diyas. Because every family deserves to celebrate.', @lkp_vis_public, 128, 36, 1, DATE_SUB(NOW(), INTERVAL 35 DAY)),
(@o25, @u6, @lkp_post_general, 'This World Environment Day, our volunteers organised 12 simultaneous events across 5 cities. Clean-ups, art installations, and pledge drives by 900 volunteers.', @lkp_vis_public, 12, 11, 1, DATE_SUB(NOW(), INTERVAL 15 DAY)),
(@o26, @u1, @lkp_post_event, 'Poster-making competition for schools on the theme Save Our Rivers - open to students aged 10 to 16. Submit entries by this Friday.', @lkp_vis_public, 109, 31, 1, DATE_SUB(NOW(), INTERVAL 16 DAY)),
(@o27, @u8, @lkp_post_announce, 'Our free eye camp next month will include cataract surgeries for 50 patients at zero cost. Doctors from a leading hospital are volunteering.', @lkp_vis_public, 136, 2, 1, DATE_SUB(NOW(), INTERVAL 60 DAY)),
(@o28, @u9, @lkp_post_general, '350 beneficiaries of our vocational training program are now employed. The ripple effect reaches their families, their communities, and the next generation.', @lkp_vis_members, 36, 20, 1, DATE_SUB(NOW(), INTERVAL 47 DAY)),
(@o29, @u4, @lkp_post_general, 'We are grateful to our 120 corporate volunteers who spent their CSR day with us this quarter - painting school walls, fixing computers, and mentoring youth.', @lkp_vis_public, 8, 29, 1, DATE_SUB(NOW(), INTERVAL 64 DAY)),
(@o30, @u10, @lkp_post_event, 'Movie screening - a documentary on water scarcity - followed by a panel discussion with experts. Free entry. Saturday at 6:30 PM.', @lkp_vis_public, 73, 37, 1, DATE_SUB(NOW(), INTERVAL 1 DAY));

-- ═══════════════════════════════════════════════════════════
-- 8. POST MEDIA (placeholder images for the 20 most recent posts)
-- Uses picsum.photos — stable public placeholder image service
-- ═══════════════════════════════════════════════════════════
INSERT IGNORE INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
SELECT p.PostId,
       CONCAT('https://picsum.photos/seed/ngopost', p.PostId, '/800/600') AS FileUrl,
       @lkp_media_image,
       1
FROM   Posts p
WHERE  p.IsDeleted = 0
  AND  p.OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0)
ORDER  BY p.CreatedAt DESC
LIMIT  20;

-- ── VERIFICATION COUNTS ────────────────────────────────────────────────────
SELECT 'Test Users'     AS entity, COUNT(*) AS count FROM Users         WHERE Mobile LIKE '+91900000000%' AND IsDeleted=0;
SELECT 'Organisations'  AS entity, COUNT(*) AS count FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0;
SELECT 'OrgMembers'     AS entity, COUNT(*) AS count FROM OrgMembers    WHERE OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%');
SELECT 'Projects'       AS entity, COUNT(*) AS count FROM Projects      WHERE OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0);
SELECT 'Sessions'       AS entity, COUNT(*) AS count FROM ProjectSessions WHERE ProjectId IN (SELECT ProjectId FROM Projects WHERE OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0));
SELECT 'Posts'          AS entity, COUNT(*) AS count FROM Posts         WHERE OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0);
SELECT 'PostMedia'      AS entity, COUNT(*) AS count FROM PostMedia     WHERE PostId IN (SELECT PostId FROM Posts WHERE OrgId IN (SELECT OrgId FROM Organisations WHERE RegNumber LIKE 'REG-%' AND IsDeleted=0));
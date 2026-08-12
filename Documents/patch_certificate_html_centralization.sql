-- ============================================================
-- Patch: Certificate HTML Centralization (v5.2)
-- Date : 2026-08-12
-- What : Adds CoordinatorName to Certificate_GetData and
--        Certificate_GetDataById by JOINing UserProfiles on
--        vc.IssuedBy = cp.UserId.
--
-- Run this patch on Railway staging and production after updating
-- the setup SQL (NGOConnect_Complete_Setup_v5.0.sql).
-- No table schema changes — SP-only patch.
-- ============================================================

DROP PROCEDURE IF EXISTS Certificate_GetData;

DELIMITER //

CREATE PROCEDURE Certificate_GetData(IN p_CertCode VARCHAR(20))
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt, vc.TotalHours,
        -- Volunteer
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VolunteerName,
        up.ProfilePhoto,
        -- Project
        p.ProjectId, p.ProjectName,
        -- Organisation
        o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        -- Impact score
        up.ImpactScore,
        -- Coordinator (admin who issued the certificate)
        CONCAT(cp.FirstName, ' ', cp.LastName) AS CoordinatorName,
        -- Skill ratings for this project (pipe-separated SkillName:Rating pairs)
        (SELECT GROUP_CONCAT(ps.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    JOIN  UserProfiles  cp ON vc.IssuedBy  = cp.UserId
    WHERE vc.CertCode = p_CertCode;
END //

DELIMITER ;

-- -----------------------------------------------------------

DROP PROCEDURE IF EXISTS Certificate_GetDataById;

DELIMITER //

CREATE PROCEDURE Certificate_GetDataById(IN p_CertificateId INT UNSIGNED)
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt, vc.TotalHours,
        -- Volunteer
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VolunteerName,
        up.ProfilePhoto,
        -- Project
        p.ProjectId, p.ProjectName,
        -- Organisation
        o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        -- Impact score
        up.ImpactScore,
        -- Coordinator (admin who issued the certificate)
        CONCAT(cp.FirstName, ' ', cp.LastName) AS CoordinatorName,
        -- Skill ratings for this project (pipe-separated SkillName:Rating pairs)
        (SELECT GROUP_CONCAT(ps.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    JOIN  UserProfiles  cp ON vc.IssuedBy  = cp.UserId
    WHERE vc.CertificateId = p_CertificateId;
END //

DELIMITER ;

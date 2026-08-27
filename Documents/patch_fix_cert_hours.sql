-- ─────────────────────────────────────────────────────────────────────────────
-- patch_fix_cert_hours.sql
-- Fix: Certificate hours sometimes incorrect.
--
-- Root cause: Certificate_GetData / Certificate_GetDataById read vc.TotalHours
-- (stamped at issuance time). If attendance was marked or hours were backfilled
-- AFTER the cert was issued, the stored value is stale.
--
-- Fix: Replace vc.TotalHours with a live subquery that sums HoursLogged from
-- ProjectAttendance for ATTENDED records. Alias remains TotalHours — no DAL
-- or frontend changes needed.
--
-- No table schema changes. Apply to Railway staging + production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Certificate_GetData //
CREATE PROCEDURE Certificate_GetData(IN p_CertCode VARCHAR(20))
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt,
        -- Live-computed so late attendance marks are reflected accurately
        COALESCE((SELECT SUM(pa.HoursLogged)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE ps.ProjectId = vc.ProjectId AND pa.UserId = vc.UserId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalHours,
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
        (SELECT GROUP_CONCAT(ps2.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps2.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps2
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps2.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps2.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    JOIN  UserProfiles  cp ON vc.IssuedBy  = cp.UserId
    WHERE vc.CertCode = p_CertCode;
END //

DROP PROCEDURE IF EXISTS Certificate_GetDataById //
CREATE PROCEDURE Certificate_GetDataById(IN p_CertificateId INT UNSIGNED)
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt,
        -- Live-computed so late attendance marks are reflected accurately
        COALESCE((SELECT SUM(pa.HoursLogged)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE ps.ProjectId = vc.ProjectId AND pa.UserId = vc.UserId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                 ), 0) AS TotalHours,
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
        (SELECT GROUP_CONCAT(ps2.SkillName, ':', ROUND(usr.Rating, 1)
                             ORDER BY ps2.SkillName SEPARATOR '|')
         FROM   ProjectSkills ps2
         JOIN   UserSkillRatings usr
                ON  usr.SkillId    = ps2.ProjectSkillId
                AND usr.UserId     = vc.UserId
                AND usr.ProjectId  = vc.ProjectId
         WHERE  ps2.ProjectId = vc.ProjectId) AS SkillRatings,
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

SELECT 'patch_fix_cert_hours applied successfully.' AS Status;

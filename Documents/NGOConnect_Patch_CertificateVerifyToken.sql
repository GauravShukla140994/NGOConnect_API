-- ============================================================
-- NGOConnect_Patch_CertificateVerifyToken.sql
--
-- Public certificate verify page — encrypted verify token instead of the raw,
-- guessable CertCode.
--
-- WHY: The public /verify/{certCode} page (and the mobile app's "share my
-- certificate" button) built shareable links straight from CertCode, which is
-- CERT-{year}-{6-digit sequential counter} — a plain incrementing number, not
-- sparse. Anyone could walk CERT-2026-000001, 000002, 000003, ... and pull
-- every volunteer's name, photo, org, and hours off the public verify
-- endpoint. User caught this immediately after the verify page went live.
--
-- FIX: Reuses the AES-256-GCM IUrlTokenService already built for /ngo and
-- /opportunity share links (entityType "CERT" instead of "ORG"/"OPP"). The API
-- now attaches an encrypted verifyToken/verifyUrl to every certificate
-- response; the public verify page and share buttons use that instead of
-- CertCode. This patch is DB-only (one new SP) — no C# is deployed by running
-- this file, that's a separate app deployment.
--
-- WORKFLOW (per this project's CLAUDE.md):
--   1. This patch has ALREADY been merged into
--      Documents/NGOConnect_Complete_Setup_v4.9.sql (source of truth).
--   2. Run THIS file against your LOCAL dev DB first.
--   3. Do not run against Railway staging/production yet — combine with any
--      other pending patches first, per this project's own patch workflow.
--
-- SAFETY: DROP PROCEDURE IF EXISTS + CREATE PROCEDURE — safe to re-run any
-- number of times. No table changes.
-- ============================================================

DROP PROCEDURE IF EXISTS Certificate_GetDataById;

DELIMITER //

-- Same data as Certificate_GetData, keyed by the internal numeric CertificateId
-- instead of the sequential, guessable CertCode. Only reachable via a decrypted
-- verify token (see CertificateController.GetCertificateByToken) — the raw
-- CertificateId itself is never exposed in a URL.
CREATE PROCEDURE Certificate_GetDataById(IN p_CertificateId INT UNSIGNED)
BEGIN
    SELECT
        vc.CertificateId, vc.CertCode, vc.IssuedAt, vc.TotalHours,
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS VolunteerName,
        up.ProfilePhoto,
        p.ProjectId, p.ProjectName,
        o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
        up.ImpactScore,
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
    WHERE vc.CertificateId = p_CertificateId;
END //

DELIMITER ;

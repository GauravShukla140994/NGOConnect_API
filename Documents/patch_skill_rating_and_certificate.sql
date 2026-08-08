-- ============================================================
-- PATCH: Skill Rating + Certificate Flow
-- Apply to: Railway Staging → Railway Production
-- Generated: 2026-08-01
-- Covers:
--   1. Rebuild UserSkillRatings table (wrong columns in v4.9)
--   2. Rebuild VolunteerCertificates table (add OrgId, TotalHours, CertCode, IsDeleted)
--   3. Add CERT sequence to IdSequences
--   4. Drop + recreate Certificate_GetByUser SP (column fixes)
--   5. Add Certificate_GetData SP (for verify page + app)
--   6. Add Certificate_Issue SP
--   7. Add Project_GetSkillRatings SP (admin skill rating UI)
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ── 1. Rebuild UserSkillRatings ─────────────────────────────
DROP TABLE IF EXISTS UserSkillRatings;
CREATE TABLE UserSkillRatings (
    SkillRatingId  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    UserId         INT UNSIGNED   NOT NULL,
    OrgId          INT UNSIGNED   NULL,
    ProjectId      INT UNSIGNED   NULL,
    SkillId        INT UNSIGNED   NOT NULL,    -- ProjectSkills.ProjectSkillId
    Rating         DECIMAL(3,2)   NOT NULL,
    RatedBy        INT UNSIGNED   NOT NULL,
    Notes          TEXT           NULL,
    CreatedAt      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SkillRatingId),
    UNIQUE KEY uq_rating (UserId, ProjectId, SkillId),
    INDEX idx_rating_user    (UserId),
    INDEX idx_rating_project (ProjectId),
    CONSTRAINT fk_skillrating_user    FOREIGN KEY (UserId)   REFERENCES Users(UserId),
    CONSTRAINT fk_skillrating_ratedby FOREIGN KEY (RatedBy)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 2. Rebuild VolunteerCertificates ────────────────────────
DROP TABLE IF EXISTS VolunteerCertificates;
CREATE TABLE VolunteerCertificates (
    CertificateId  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    CertCode       VARCHAR(20)    NOT NULL,
    ProjectId      INT UNSIGNED   NOT NULL,
    UserId         INT UNSIGNED   NOT NULL,
    OrgId          INT UNSIGNED   NOT NULL,
    TotalHours     DECIMAL(6,2)   NULL,
    CertificateUrl VARCHAR(500)   NULL,
    IssuedAt       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IssuedBy       INT UNSIGNED   NULL,
    IsDeleted      TINYINT(1)     NOT NULL DEFAULT 0,
    PRIMARY KEY (CertificateId),
    UNIQUE KEY uq_cert_code         (CertCode),
    UNIQUE KEY uq_cert_project_user (ProjectId, UserId),
    INDEX idx_cert_user (UserId),
    CONSTRAINT fk_cert_project FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId),
    CONSTRAINT fk_cert_user    FOREIGN KEY (UserId)    REFERENCES Users(UserId),
    CONSTRAINT fk_cert_org     FOREIGN KEY (OrgId)     REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ── 3. Add CERT sequence ────────────────────────────────────
INSERT IGNORE INTO IdSequences (SequenceName, CurrentYear, LastValue)
VALUES ('CERT', YEAR(CURDATE()), 0);

-- ── 4–7. Stored Procedures ──────────────────────────────────
DROP PROCEDURE IF EXISTS Certificate_GetByUser;
DROP PROCEDURE IF EXISTS Certificate_GetData;
DROP PROCEDURE IF EXISTS Certificate_Issue;
DROP PROCEDURE IF EXISTS Project_GetSkillRatings;

DELIMITER //

CREATE PROCEDURE Certificate_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT vc.CertificateId, vc.CertCode,
           vc.ProjectId, p.ProjectName AS ProjectTitle,
           vc.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
           vc.TotalHours, vc.CertificateUrl, vc.IssuedAt
    FROM VolunteerCertificates vc
    JOIN Projects      p ON vc.ProjectId = p.ProjectId
    JOIN Organisations o ON vc.OrgId     = o.OrgId
    WHERE vc.UserId = p_UserId AND vc.IsDeleted = 0
    ORDER BY vc.IssuedAt DESC;
END //

CREATE PROCEDURE Certificate_GetData(IN p_CertCode VARCHAR(20))
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
                ON  usr.SkillId   = ps.ProjectSkillId
                AND usr.UserId    = vc.UserId
                AND usr.ProjectId = vc.ProjectId
         WHERE  ps.ProjectId = vc.ProjectId) AS SkillRatings,
        vc.IsDeleted
    FROM  VolunteerCertificates vc
    JOIN  Projects      p  ON vc.ProjectId = p.ProjectId
    JOIN  Organisations o  ON vc.OrgId     = o.OrgId
    JOIN  Users         u  ON vc.UserId    = u.UserId
    JOIN  UserProfiles  up ON vc.UserId    = up.UserId
    WHERE vc.CertCode = p_CertCode;
END //

CREATE PROCEDURE Certificate_Issue(
    IN p_ProjectId  INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,
    IN p_IssuedBy   INT UNSIGNED,
    IN p_TotalHours DECIMAL(6,2)
)
BEGIN
    DECLARE v_CertCode VARCHAR(20);

    SELECT CertCode INTO v_CertCode
    FROM   VolunteerCertificates
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_CertCode IS NOT NULL THEN
        SELECT 1 AS IsSuccess, 'Certificate already issued.' AS Message, v_CertCode AS CertCode;
    ELSE
        UPDATE IdSequences SET LastValue = LastValue + 1
        WHERE  SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
        FROM   IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
        VALUES (v_CertCode, p_ProjectId, p_UserId, p_OrgId, p_TotalHours, p_IssuedBy);

        SELECT 1 AS IsSuccess, 'Certificate issued successfully.' AS Message, v_CertCode AS CertCode;
    END IF;
END //

CREATE PROCEDURE Project_GetSkillRatings(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ps.ProjectSkillId,
        ps.SkillName,
        COALESCE(usr.Rating, 0)  AS Rating,
        usr.Notes
    FROM  ProjectSkills ps
    LEFT JOIN UserSkillRatings usr
          ON  usr.SkillId   = ps.ProjectSkillId
          AND usr.UserId    = p_UserId
          AND usr.ProjectId = p_ProjectId
    WHERE ps.ProjectId = p_ProjectId
    ORDER BY ps.SkillName;
END //

DELIMITER ;

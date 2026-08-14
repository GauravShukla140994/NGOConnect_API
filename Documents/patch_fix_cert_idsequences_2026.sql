-- ============================================================
-- patch_fix_cert_idsequences_2026.sql
-- Fix: Certificate issuance "an error occurred" when Railway DB
--      was deployed in 2025 — IdSequences had CERT/2025 row but
--      not CERT/2026. SP used WHERE CurrentYear = YEAR(NOW())
--      = 2026, found nothing, v_CertCode stayed NULL, and the
--      INSERT into VolunteerCertificates (NOT NULL on CertCode)
--      threw an exception.
--
-- Run on: local → Railway staging → Railway production
-- ============================================================

-- 1. Ensure 2026 rows exist for all sequences (safe INSERT IGNORE)
INSERT IGNORE INTO IdSequences (SequenceName, CurrentYear, LastValue)
VALUES
  ('CERT', 2026, 0),
  ('DON',  2026, 0),
  ('WDR',  2026, 0),
  ('REC',  2026, 0);

-- 2. Redeploy Certificate_Issue SP — now self-healing (auto-inserts
--    the current-year row on first use, handles year rollover forever)
DROP PROCEDURE IF EXISTS Certificate_Issue;
DELIMITER //
CREATE PROCEDURE Certificate_Issue(
    IN p_ProjectId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_IssuedBy  INT UNSIGNED
)
BEGIN
    DECLARE v_CertCode   VARCHAR(20);
    DECLARE v_TotalHours DECIMAL(6,2) DEFAULT 0;

    SELECT COALESCE(SUM(pa.HoursLogged), 0) INTO v_TotalHours
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
    JOIN   LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
    JOIN   LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  ps.ProjectId = p_ProjectId AND pa.UserId = p_UserId
      AND  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED';

    SELECT CertCode INTO v_CertCode
    FROM   VolunteerCertificates
    WHERE  ProjectId = p_ProjectId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_CertCode IS NOT NULL THEN
        SELECT 1 AS IsSuccess, 'Certificate already issued.' AS Message, v_CertCode AS CertCode;
    ELSE
        -- Self-healing: ensure the current-year row exists (handles year rollover)
        INSERT IGNORE INTO IdSequences (SequenceName, CurrentYear, LastValue)
        VALUES ('CERT', YEAR(NOW()), 0);

        UPDATE IdSequences SET LastValue = LastValue + 1
        WHERE  SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        SELECT CONCAT('CERT-', CurrentYear, '-', LPAD(LastValue, 6, '0')) INTO v_CertCode
        FROM   IdSequences WHERE SequenceName = 'CERT' AND CurrentYear = YEAR(NOW());

        INSERT INTO VolunteerCertificates (CertCode, ProjectId, UserId, OrgId, TotalHours, IssuedBy)
        VALUES (v_CertCode, p_ProjectId, p_UserId, p_OrgId, v_TotalHours, p_IssuedBy);

        SELECT 1 AS IsSuccess, 'Certificate issued successfully.' AS Message, v_CertCode AS CertCode;
    END IF;
END //
DELIMITER ;

-- ============================================================
-- Patch: Post Report Email Enhancement
-- Adds Post_GetReportDetails SP for enriched super-admin email
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetReportDetails //
CREATE PROCEDURE Post_GetReportDetails(IN p_PostId INT UNSIGNED)
BEGIN
    SELECT
        p.PostId,
        p.OrgId,
        COALESCE(o.OrgName, 'Not linked')                AS OrgName,
        p.UserId                                          AS PostAuthorUserId,
        CONCAT(ap.FirstName, ' ', ap.LastName)            AS PostAuthorName,
        DATE_FORMAT(p.CreatedAt,  '%d-%b-%Y %h:%i %p')   AS PostCreatedAt,
        pr.ReportedByUserId,
        CONCAT(rp.FirstName, ' ', rp.LastName)            AS ReporterName,
        DATE_FORMAT(pr.CreatedAt, '%d-%b-%Y %h:%i %p')   AS ReportedAt
    FROM   Posts        p
    LEFT   JOIN Organisations o  ON o.OrgId   = p.OrgId
    LEFT   JOIN UserProfiles  ap ON ap.UserId  = p.UserId              AND ap.IsDeleted = 0
    JOIN   PostReports        pr ON pr.PostId  = p.PostId
    LEFT   JOIN UserProfiles  rp ON rp.UserId  = pr.ReportedByUserId   AND rp.IsDeleted = 0
    WHERE  p.PostId = p_PostId
    ORDER  BY pr.CreatedAt DESC
    LIMIT  1;
END //

DELIMITER ;

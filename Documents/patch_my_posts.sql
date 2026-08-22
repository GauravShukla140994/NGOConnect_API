-- ============================================================
-- NGO Connect — Patch: My Posts feature
-- New SP: Post_GetByUser
-- Safe to re-run (DROP IF EXISTS + CREATE)
-- Apply: local → Railway staging → Railway production
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetByUser //
CREATE PROCEDURE Post_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        p.IsEmergency,
        p.IsEvergreen,
        p.LikeCount,
        p.CommentCount,
        p.ShareCount,
        p.SaveCount,
        p.ViewCount,
        lv_type.ValueCode  AS PostTypeCode,
        lv_type.ValueName  AS PostType,
        p.UserId,
        CONCAT(up.FirstName, ' ', COALESCE(up.LastName, '')) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        o.LogoUrl          AS OrgLogoUrl,
        (SELECT COUNT(*) FROM PostSaves ps2
         WHERE ps2.PostId = p.PostId AND ps2.UserId = p_UserId) AS IsSaved,
        1                  AS IsLiked,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts         p
    JOIN   UserProfiles  up     ON up.UserId          = p.UserId
    LEFT JOIN Organisations o   ON o.OrgId            = p.OrgId  AND o.IsDeleted = 0
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm      ON pm.PostId          = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.UserId = p_UserId AND p.IsDeleted = 0
    GROUP BY
        p.PostId,  p.Content,     p.IsPinned,   p.IsEmergency, p.IsEvergreen,
        p.LikeCount, p.CommentCount, p.ShareCount, p.SaveCount, p.ViewCount,
        lv_type.ValueCode, lv_type.ValueName,
        p.UserId,  up.FirstName,  up.LastName,  up.ProfilePhoto,
        p.OrgId,   o.OrgName,     o.LogoUrl,
        p.CreatedAt
    ORDER BY p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.UserId = p_UserId AND p.IsDeleted = 0;
END //

DELIMITER ;

-- Verify
SELECT ROUTINE_NAME, LAST_ALTERED
FROM   INFORMATION_SCHEMA.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'Post_GetByUser';

-- ============================================================
-- NGO Connect — Patch: Saved Posts feature
-- Version : applied to v4.9
-- Date    : 2026-07-25
-- Scope   : Post_GetSaved SP (new)
-- Reason  : New "Saved Posts" screen in Profile requires an SP
--           that returns the posts a user has bookmarked,
--           ordered most-recently-saved first, with pagination.
-- Safe    : Purely additive — no existing SP is touched.
--           PostSaves table already exists (created in v4.7 feed patch).
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetSaved //
CREATE PROCEDURE Post_GetSaved(
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
        lv_type.ValueCode  AS PostTypeCode,
        lv_type.ValueName  AS PostType,
        p.UserId,
        CONCAT(up.FirstName, ' ', COALESCE(up.LastName, '')) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        o.LogoUrl          AS OrgLogoUrl,
        1                  AS IsSaved,
        (SELECT COUNT(*) FROM PostLikes pl
         WHERE pl.PostId = p.PostId AND pl.UserId = p_UserId) AS IsLiked,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        ps.CreatedAt AS SavedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   PostSaves     ps
    JOIN   Posts         p      ON p.PostId          = ps.PostId AND p.IsDeleted = 0
    JOIN   UserProfiles  up     ON up.UserId          = p.UserId
    LEFT JOIN Organisations o   ON o.OrgId            = p.OrgId  AND o.IsDeleted = 0
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm      ON pm.PostId          = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  ps.UserId = p_UserId
    GROUP BY
        p.PostId,  p.Content,     p.IsPinned,   p.IsEmergency, p.IsEvergreen,
        p.LikeCount, p.CommentCount, p.ShareCount, p.SaveCount,
        lv_type.ValueCode, lv_type.ValueName,
        p.UserId,  up.FirstName,  up.LastName,  up.ProfilePhoto,
        p.OrgId,   o.OrgName,     o.LogoUrl,
        p.CreatedAt, ps.CreatedAt
    ORDER BY ps.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   PostSaves ps
    JOIN   Posts     p ON p.PostId = ps.PostId AND p.IsDeleted = 0
    WHERE  ps.UserId = p_UserId;
END //

DELIMITER ;

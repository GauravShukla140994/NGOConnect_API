-- ============================================================
-- NGOConnect Patch — Fix Post Like field name
-- Apply to: Railway staging + production
-- Date: 2026-07-12
-- Root Cause:
--   Post_GetFeed and Post_GetById returned column `IsLikedByMe`
--   which serialises to `isLikedByMe` in JSON (DynamicRow camelCase).
--   The mobile app reads `post.isLiked` — so liked state was always
--   lost on page refresh (optimistic UI worked, DB save worked, but
--   the refreshed response had the wrong key name).
-- Fix:
--   Rename alias IsLikedByMe → IsLiked in both SPs.
--   No table changes, no C# changes, no mobile changes needed.
-- ============================================================

DELIMITER //

-- ── Post_GetFeed (latest version with IsFollowing + MediaTypes) ──────────────
DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,   -- NULL = all orgs | non-null = filter to one org
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,
        p.LikeCount,
        p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLiked,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1
                THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up          ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o       ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type  ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm           ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt    ON lv_mt.LookupValueId   = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,   p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId);
END //

-- ── Post_GetById ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_GetById //
CREATE PROCEDURE Post_GetById(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.PostId, p.Content,
        ptv.ValueCode AS PostType, ptv.ValueName AS PostTypeName,
        p.LikeCount, p.CommentCount, p.IsPinned, p.CreatedAt, p.UpdatedAt,
        p.UserId, CONCAT(up.FirstName,' ',up.LastName) AS AuthorName, up.ProfilePhoto,
        p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        IF(pl.PostLikeId IS NOT NULL, 1, 0) AS IsLiked,
        (SELECT GROUP_CONCAT(pm2.FileUrl ORDER BY pm2.SortOrder SEPARATOR ',') FROM PostMedia pm2 WHERE pm2.PostId = p.PostId) AS MediaUrls,
        (SELECT lv2.ValueCode FROM PostMedia pm3 JOIN LookupValues lv2 ON pm3.MediaTypeLkpId = lv2.LookupValueId WHERE pm3.PostId = p.PostId LIMIT 1) AS MediaType
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.PostTypeLkpId = ptv.LookupValueId
    LEFT JOIN PostLikes pl ON p.PostId = pl.PostId AND pl.UserId = p_UserId
    WHERE p.PostId = p_PostId AND p.IsDeleted = 0;
END //

DELIMITER ;

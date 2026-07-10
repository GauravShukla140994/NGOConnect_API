-- ============================================================
-- NGO Connect — Patch: Post_GetFeed — add p_OrgId filter
-- Date    : 2026-07-11
--
-- PROBLEM:
--   PostDal.GetFeedAsync passes 4 params:
--     p_UserId, p_OrgId, p_PageNumber, p_PageSize
--   But Post_GetFeed (from VideoSupport patch) only accepts 3:
--     p_UserId, p_PageNumber, p_PageSize
--   → MySqlException: Incorrect number of arguments, expected 3, got 4
--
-- FIX:
--   Add p_OrgId INT UNSIGNED (NULL = all orgs, non-null = filter to that org).
--   Parameter order matches DAL exactly (positional matching in ADO.NET).
--
-- SAFE TO RUN MULTIPLE TIMES.
-- ============================================================

USE NGOConnect;

DELIMITER //

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
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe,

        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,

        p.OrgId,
        o.OrgName,

        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,

        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo

    FROM   Posts p
    JOIN   UserProfiles up         ON up.UserId           = p.UserId    AND up.IsDeleted = 0
    LEFT JOIN Organisations o      ON o.OrgId             = p.OrgId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm         ON pm.PostId           = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId = pm.MediaTypeLkpId

    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)

    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,
        p.CreatedAt

    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId);

END //

DELIMITER ;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- All orgs:          CALL Post_GetFeed(4, NULL, 1, 10);
-- Filter to org 1:   CALL Post_GetFeed(4, 1,    1, 10);

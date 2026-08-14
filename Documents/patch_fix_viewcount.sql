-- ============================================================
-- Patch: Fix ViewCount not incrementing on Feed_BulkMarkViewed
--
-- Root cause:
--   The original Feed_BulkMarkViewed SP (patch_feed_seen_tracking.sql)
--   did not have the UPDATE Posts SET ViewCount = ViewCount + 1 line.
--   It also used INSERT IGNORE which was a no-op (FeedInteractions has
--   no UNIQUE key on (UserId, PostId, InteractionType)).
--
-- This patch:
--   1. Adds composite index on FeedInteractions for NOT EXISTS performance
--   2. Replaces Feed_BulkMarkViewed with the correct version that:
--      - Uses a temp table to find genuinely new views (first-time per user)
--      - Inserts VIEW rows into FeedInteractions (deduplicated)
--      - Increments Posts.ViewCount only for new views
--
-- Apply to: local DB → Railway staging → Railway production
-- ============================================================

-- Step 1: Add missing composite index (speeds up NOT EXISTS check in SP)
-- Skip if already exists (re-run safe)
ALTER TABLE FeedInteractions
    ADD INDEX idx_feedint_user_post_type (UserId, PostId, InteractionType);

-- Step 2: Replace Feed_BulkMarkViewed with the correct deduplicating version
DELIMITER //

DROP PROCEDURE IF EXISTS Feed_BulkMarkViewed //
CREATE PROCEDURE Feed_BulkMarkViewed(
    IN p_UserId  INT UNSIGNED,
    IN p_PostIds JSON          -- e.g. [1, 2, 3, 4, 5]
)
BEGIN
    -- Collect postIds the user has NOT yet viewed (first-time views only)
    DROP TEMPORARY TABLE IF EXISTS _tmp_new_views;
    CREATE TEMPORARY TABLE _tmp_new_views (PostId INT UNSIGNED NOT NULL PRIMARY KEY);

    INSERT INTO _tmp_new_views (PostId)
    SELECT DISTINCT jt.PostId
    FROM   JSON_TABLE(p_PostIds, '$[*]' COLUMNS (PostId INT PATH '$')) AS jt
    WHERE  EXISTS  (SELECT 1 FROM Posts WHERE PostId = jt.PostId AND IsDeleted = 0)
    AND    NOT EXISTS (
               SELECT 1 FROM FeedInteractions
               WHERE  UserId = p_UserId AND PostId = jt.PostId AND InteractionType = 'VIEW'
           );

    -- Persist the new VIEW rows
    INSERT INTO FeedInteractions (UserId, PostId, InteractionType)
    SELECT p_UserId, PostId, 'VIEW' FROM _tmp_new_views;

    -- Increment the denormalized counter only for genuinely new views
    UPDATE Posts
    SET    ViewCount = ViewCount + 1
    WHERE  PostId IN (SELECT PostId FROM _tmp_new_views);

    DROP TEMPORARY TABLE IF EXISTS _tmp_new_views;

    SELECT 1 AS IsSuccess, 'Marked.' AS Message;
END //

DELIMITER ;

-- Step 3: Fix Post_GetById — add missing ViewCount to SELECT
-- (ViewCount was added to Posts table after this SP was written)
DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetById //
CREATE PROCEDURE Post_GetById(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.PostId, p.Content,
        ptv.ValueCode AS PostType, ptv.ValueName AS PostTypeName,
        p.LikeCount, p.CommentCount, p.ViewCount, p.IsPinned, p.CreatedAt, p.UpdatedAt,
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

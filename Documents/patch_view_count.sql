-- ============================================================
-- patch_view_count.sql
-- Adds Posts.ViewCount and upgrades Feed_BulkMarkViewed SP
-- to deduplicate views and maintain the denormalized counter.
--
-- Apply to: local dev → Railway staging → Railway production
-- Run order: this file only (no dependencies on other patches)
-- ============================================================

-- Step 1: Add ViewCount column to Posts table
ALTER TABLE Posts
    ADD COLUMN ViewCount INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Denormalized unique-user view count — incremented by Feed_BulkMarkViewed'
        AFTER SaveCount;

-- Step 2: Backfill ViewCount from existing FeedInteractions VIEW rows
--         (counts distinct users who have a VIEW row per post)
UPDATE Posts p
INNER JOIN (
    SELECT PostId, COUNT(DISTINCT UserId) AS uv
    FROM   FeedInteractions
    WHERE  InteractionType = 'VIEW'
    GROUP  BY PostId
) fi ON fi.PostId = p.PostId
SET p.ViewCount = fi.uv;

-- Step 3: Replace Feed_BulkMarkViewed with the deduplicated version
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
    WHERE  EXISTS (SELECT 1 FROM Posts WHERE PostId = jt.PostId AND IsDeleted = 0)
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

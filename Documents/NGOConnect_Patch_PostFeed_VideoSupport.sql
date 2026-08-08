-- ============================================================
-- NGO Connect — Patch: Video Support in Feed
-- Date    : 2026-07-09
--
-- CHANGES:
--   1. Post_GetFeed — adds MediaUrls, MediaTypes, TimeAgo, IsPinned,
--      PostTypeLkpCode (ValueCode). Previously no media was returned.
--   2. Post_Create  — auto-detects VIDEO vs IMAGE from URL extension
--      instead of blindly assigning IMAGE to every media file.
--
-- SAFE TO RUN MULTIPLE TIMES (DROP IF EXISTS pattern).
-- Run against NGOConnect database.
-- ============================================================

USE NGOConnect;

DELIMITER //

-- ============================================================
-- 1. Post_GetFeed — now returns media + time-ago + type code
-- ============================================================
DROP PROCEDURE IF EXISTS Post_GetFeed //

CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    -- ── Main feed query (posts + media, grouped) ─────────────────────────────
    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,

        -- Post type (code for frontend logic, name for display)
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,

        -- Engagement
        p.LikeCount,
        p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe,

        -- Author
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,

        -- Organisation
        p.OrgId,
        o.OrgName,

        -- Media (CSV ordered by SortOrder — normalise to [] client-side)
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,

        -- Timestamps
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
    JOIN   UserProfiles up      ON up.UserId             = p.UserId    AND up.IsDeleted = 0
    LEFT JOIN Organisations o   ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    -- Media join (LEFT so posts without media still appear)
    LEFT JOIN PostMedia pm      ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt ON lv_mt.LookupValueId  = pm.MediaTypeLkpId

    WHERE  p.IsDeleted = 0

    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,
        p.CreatedAt

    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- ── Total count (for pagination) ─────────────────────────────────────────
    SELECT COUNT(*) AS TotalCount FROM Posts WHERE IsDeleted = 0;

END //


-- ============================================================
-- 2. Post_Create — auto-detect IMAGE vs VIDEO from extension
-- ============================================================
DROP PROCEDURE IF EXISTS Post_Create //

CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,          -- comma-separated remote URLs
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ImageTypeLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_VideoTypeLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultTypeLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve default post type (GENERAL) if not supplied
    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
        SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
    END IF;

    -- Insert post
    INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
    VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

    SET @NewPostId = LAST_INSERT_ID();

    -- Store media with correct type (IMAGE or VIDEO detected from extension)
    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN

        -- Look up IMAGE LkpId
        SELECT lv.LookupValueId INTO v_ImageTypeLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

        -- Look up VIDEO LkpId
        SELECT lv.LookupValueId INTO v_VideoTypeLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'VIDEO' LIMIT 1;

        -- Safety fallbacks
        IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;
        IF v_VideoTypeLkpId = 0 THEN SET v_VideoTypeLkpId = v_ImageTypeLkpId; END IF;

        -- Insert one row per URL; REGEXP detects video extensions
        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT
            @NewPostId,
            TRIM(j.val),
            CASE
                WHEN LOWER(TRIM(j.val)) REGEXP '\\.(mp4|mov|avi|mkv|webm|m4v|3gp|wmv)$'
                     THEN v_VideoTypeLkpId
                ELSE v_ImageTypeLkpId
            END,
            j.rn
        FROM JSON_TABLE(
            CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
            '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')
        ) AS j
        WHERE TRIM(j.val) != '';

    END IF;

    SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
END //

DELIMITER ;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- CALL Post_GetFeed(1, 1, 10);
-- CALL Post_Create(1, 1, 'Test video post', 'https://cdn.example.com/video.mp4', NULL, NULL);

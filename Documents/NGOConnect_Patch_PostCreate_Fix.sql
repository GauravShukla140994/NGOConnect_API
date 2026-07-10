-- ============================================================
-- NGOConnect Patch: Post_Create — null-safe defaults
-- Fixes:
--   1. p_PostTypeLkpId NULL → defaults to GENERAL (POST_TYPE_FEED)
--   2. p_VisibilityLkpId NULL → defaults to PUBLIC (POST_VISIBILITY)
--   (p_MediaType is optional — COALESCE already handled in body)
-- Run against: ngodb  (any environment)
-- Date: 2026-07-05
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Post_Create //

CREATE PROCEDURE Post_Create(
    IN p_OrgId           INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_VisibilityLkpId INT UNSIGNED,
    IN p_MediaUrls       TEXT,
    IN p_MediaType       VARCHAR(20)
)
BEGIN
    DECLARE v_PostId         INT UNSIGNED;
    DECLARE v_MediaTypeLkpId INT UNSIGNED;

    -- ── Default PostType to GENERAL if not supplied ──────────────
    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO p_PostTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL'
        LIMIT 1;
    END IF;

    -- ── Default Visibility to PUBLIC if not supplied ─────────────
    IF p_VisibilityLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO p_VisibilityLkpId
        FROM LookupValues lv
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC'
        LIMIT 1;
    END IF;

    INSERT INTO Posts (OrgId, UserId, PostTypeLkpId, Content, VisibilityLkpId, CreatedBy)
    VALUES (p_OrgId, p_UserId, p_PostTypeLkpId, p_Content, p_VisibilityLkpId, p_UserId);

    SET v_PostId = LAST_INSERT_ID();

    -- ── Insert media rows if URLs supplied ───────────────────────
    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN
        SELECT lv.LookupValueId INTO v_MediaTypeLkpId
        FROM LookupValues lv
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'MEDIA_TYPE'
          AND lv.ValueCode = UPPER(COALESCE(p_MediaType, 'IMAGE'))
        LIMIT 1;

        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT v_PostId, TRIM(j.url), v_MediaTypeLkpId,
               ROW_NUMBER() OVER () AS SortOrder
        FROM JSON_TABLE(
            CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
            '$[*]' COLUMNS (url VARCHAR(500) PATH '$')
        ) j
        WHERE TRIM(j.url) != '';
    END IF;

    SELECT 1 AS IsSuccess, 'Post created.' AS Message, v_PostId AS PostId;
END //

DELIMITER ;

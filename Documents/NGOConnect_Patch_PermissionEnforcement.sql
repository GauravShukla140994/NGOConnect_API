-- ============================================================
-- NGO Connect — Patch: Permission Enforcement in SPs
-- Changes:
--   1. Post_GetPermissions  — add CanComment + CanCommunityPost to return
--   2. Post_Create          — enforce CanPost + MaxPostsPerDay server-side
--   3. Post_AddComment      — enforce CanComment server-side
--   4. Community_CreatePost — enforce CanCommunityPost server-side
--   5. Community_CreatePoll — enforce CanCommunityPost server-side
-- Apply to: Railway staging + production
-- Date: 2026-07-14
-- ============================================================

DELIMITER //

-- ── 1. Post_GetPermissions — add CanComment + CanCommunityPost ───────────────
DROP PROCEDURE IF EXISTS Post_GetPermissions //
CREATE PROCEDURE Post_GetPermissions(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember         TINYINT(1)  DEFAULT 0;
    DECLARE v_CanPost          TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment       TINYINT(1)  DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay        INT         DEFAULT 10;
    DECLARE v_TodayCount       INT         DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT 1, om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay
    INTO   v_IsMember, v_CanPost, v_CanComment, v_CanCommunityPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    SELECT COUNT(*) INTO v_TodayCount
    FROM   Posts
    WHERE  UserId = p_UserId AND OrgId = p_OrgId
      AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

    SELECT
        v_IsMember          AS IsMember,
        v_CanPost           AS CanPost,
        v_CanComment        AS CanComment,
        v_CanCommunityPost  AS CanCommunityPost,
        v_MaxPerDay         AS MaxPostsPerDay,
        v_TodayCount        AS TodayPostCount;
END //

-- ── 2. Post_Create — enforce CanPost + MaxPostsPerDay ────────────────────────
DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,           -- comma-separated remote URLs
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ApprovedLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_CanPost         TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay       INT         DEFAULT 10;
    DECLARE v_TodayCount      INT         DEFAULT 0;
    DECLARE v_ImageTypeLkpId  INT UNSIGNED DEFAULT 0;
    DECLARE v_VideoTypeLkpId  INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultTypeLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve APPROVED status LkpId
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    -- Load member's posting permission
    SELECT om.CanPost, om.MaxPostsPerDay INTO v_CanPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to post in this organisation.' AS Message,
               NULL AS PostId;
    ELSE
        -- Count today's posts for daily limit check
        SELECT COUNT(*) INTO v_TodayCount
        FROM   Posts
        WHERE  UserId = p_UserId AND OrgId = p_OrgId
          AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

        IF v_MaxPerDay > 0 AND v_TodayCount >= v_MaxPerDay THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('Daily post limit of ', v_MaxPerDay, ' reached.') AS Message,
                   NULL AS PostId;
        ELSE
            -- Resolve default post type (GENERAL) if not supplied
            IF p_PostTypeLkpId IS NULL THEN
                SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
                SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
            END IF;

            -- Insert post
            INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
            VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

            SET @NewPostId = LAST_INSERT_ID();

            -- Store media with correct type (IMAGE or VIDEO detected from extension)
            IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN

                SELECT lv.LookupValueId INTO v_ImageTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

                SELECT lv.LookupValueId INTO v_VideoTypeLkpId
                FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'VIDEO' LIMIT 1;

                IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;
                IF v_VideoTypeLkpId = 0 THEN SET v_VideoTypeLkpId = v_ImageTypeLkpId; END IF;

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
        END IF;
    END IF;
END //

-- ── 3. Post_AddComment — enforce CanComment ──────────────────────────────────
DROP PROCEDURE IF EXISTS Post_AddComment //
CREATE PROCEDURE Post_AddComment(
    IN p_PostId          INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_ParentCommentId INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember      TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment    TINYINT(1)  DEFAULT 1;  -- default allow (no OrgId = public post)

    -- Look up the post's OrgId
    SELECT OrgId INTO v_OrgId
    FROM   Posts WHERE PostId = p_PostId AND IsDeleted = 0 LIMIT 1;

    -- Enforce CanComment only for org-scoped posts
    IF v_OrgId > 0 THEN
        SELECT lv.LookupValueId INTO v_ApprovedLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        SELECT 1, om.CanComment INTO v_IsMember, v_CanComment
        FROM   OrgMembers om
        WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
          AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
        LIMIT 1;

        -- Non-members cannot comment on org posts
        IF v_IsMember = 0 THEN SET v_CanComment = 0; END IF;
    END IF;

    IF v_CanComment = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to comment in this organisation.' AS Message,
               NULL AS CommentId;
    ELSE
        INSERT INTO PostComments (PostId, UserId, ParentCommentId, Content)
        VALUES (p_PostId, p_UserId, p_ParentCommentId, p_Content);
        UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId;
    END IF;
END //

-- ── 4. Community_CreatePost — enforce CanCommunityPost ───────────────────────
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Title          VARCHAR(300),
    IN p_Content        TEXT,
    IN p_PostTypeLkpId  INT UNSIGNED,
    IN p_AudienceLkpId  INT UNSIGNED
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT om.CanCommunityPost INTO v_CanCommunityPost
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanCommunityPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to post in this community.' AS Message,
               NULL AS CommunityPostId;
    ELSE
        IF p_AudienceLkpId IS NULL OR p_AudienceLkpId = 0 THEN
            SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;
            SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
        END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_UserId);

        SELECT 1 AS IsSuccess, 'Post created.' AS Message, LAST_INSERT_ID() AS CommunityPostId;
    END IF;
END //

-- ── 5. Community_CreatePoll — enforce CanCommunityPost ───────────────────────
DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT,
    IN p_IsMultiChoice  TINYINT(1)
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT om.CanCommunityPost INTO v_CanCommunityPost
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanCommunityPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to create polls in this community.' AS Message,
               NULL AS PollId;
    ELSE
        SELECT lv.LookupValueId INTO v_PollTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

        SELECT lv.LookupValueId INTO v_AudienceLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;

        IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
        IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, PollIsMultiChoice, CreatedBy)
        VALUES (
            p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
            v_AudienceLkpId,
            CASE WHEN p_ExpiresInHours > 0
                 THEN DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR)
                 ELSE NULL END,
            COALESCE(p_IsMultiChoice, 0),
            p_UserId
        );

        SET @PollId = LAST_INSERT_ID();

        INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
        SELECT @PollId, jt.opt, jt.rn
        FROM JSON_TABLE(p_OptionsJson, '$[*]' COLUMNS (
            rn   FOR ORDINALITY,
            opt  VARCHAR(200) PATH '$'
        )) AS jt
        WHERE TRIM(jt.opt) != '';

        SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId;
    END IF;
END //

DELIMITER ;

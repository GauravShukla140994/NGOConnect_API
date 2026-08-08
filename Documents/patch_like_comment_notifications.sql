-- ─────────────────────────────────────────────────────────────────────────────
-- Patch: Like / Comment Notification — Author Identification
-- Affected SPs: Post_Like, Post_AddComment, Community_LikePost, Community_AddComment
-- Purpose: Return PostAuthorUserId + ActorName so DAL can fire push notifications
--          to post authors when their posts are liked or commented on.
-- Apply to: Railway staging, then production
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

-- ── 1. Post_Like ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_Like //
CREATE PROCEDURE Post_Like(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    INSERT IGNORE INTO PostLikes (PostId, UserId) VALUES (p_PostId, p_UserId);
    UPDATE Posts SET LikeCount = (SELECT COUNT(*) FROM PostLikes WHERE PostId = p_PostId) WHERE PostId = p_PostId;
    SELECT 1 AS IsSuccess, 'Post liked.' AS Message,
           p.UserId AS PostAuthorUserId,
           CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM   Posts p
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE  p.PostId = p_PostId AND p.IsDeleted = 0
    LIMIT  1;
END //

-- ── 2. Post_AddComment ───────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_AddComment //
CREATE PROCEDURE Post_AddComment(IN p_PostId INT UNSIGNED, IN p_UserId INT UNSIGNED, IN p_Content TEXT, IN p_ParentCommentId INT UNSIGNED)
BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT 0;
    DECLARE v_AuthorUserId  INT UNSIGNED DEFAULT 0;
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember      TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment    TINYINT(1)  DEFAULT 1;

    SELECT OrgId, UserId INTO v_OrgId, v_AuthorUserId
    FROM   Posts WHERE PostId = p_PostId AND IsDeleted = 0 LIMIT 1;

    IF v_OrgId > 0 THEN
        SELECT lv.LookupValueId INTO v_ApprovedLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        SELECT 1, om.CanComment INTO v_IsMember, v_CanComment
        FROM   OrgMembers om
        WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId
          AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
        LIMIT 1;

        IF v_IsMember = 0 THEN SET v_CanComment = 0; END IF;
    END IF;

    IF v_CanComment = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to comment in this organisation.' AS Message,
               NULL AS CommentId,
               NULL AS PostAuthorUserId,
               NULL AS ActorName;
    ELSE
        INSERT INTO PostComments (PostId, UserId, ParentCommentId, Content)
        VALUES (p_PostId, p_UserId, p_ParentCommentId, p_Content);
        UPDATE Posts SET CommentCount = CommentCount + 1 WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommentId,
               v_AuthorUserId AS PostAuthorUserId,
               CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
        FROM   UserProfiles up
        WHERE  up.UserId = p_UserId AND up.IsDeleted = 0
        LIMIT  1;
    END IF;
END //

-- ── 3. Community_LikePost ────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_LikePost //
CREATE PROCEDURE Community_LikePost(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists
    FROM CommunityPostLikes
    WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        DELETE FROM CommunityPostLikes
        WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;
        UPDATE CommunityPosts
        SET LikeCount = GREATEST(0, LikeCount - 1)
        WHERE CommunityPostId = p_CommunityPostId;
    ELSE
        INSERT INTO CommunityPostLikes (CommunityPostId, UserId, CreatedAt)
        VALUES (p_CommunityPostId, p_UserId, NOW());
        UPDATE CommunityPosts
        SET LikeCount = LikeCount + 1
        WHERE CommunityPostId = p_CommunityPostId;
    END IF;

    SELECT
        CASE WHEN v_Exists > 0 THEN 0 ELSE 1 END AS IsLiked,
        cp.LikeCount,
        cp.UserId AS PostAuthorUserId,
        CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM CommunityPosts cp
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE cp.CommunityPostId = p_CommunityPostId;
END //

-- ── 4. Community_AddComment ──────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_AddComment //
CREATE PROCEDURE Community_AddComment(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT
)
BEGIN
    INSERT INTO CommunityPostComments (CommunityPostId, UserId, Content, CreatedAt)
    VALUES (p_CommunityPostId, p_UserId, p_Content, NOW());

    UPDATE CommunityPosts
    SET CommentCount = CommentCount + 1
    WHERE CommunityPostId = p_CommunityPostId;

    SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommunityCommentId,
           cp.UserId AS PostAuthorUserId,
           CONCAT(COALESCE(up.FirstName, ''), ' ', COALESCE(up.LastName, '')) AS ActorName
    FROM   CommunityPosts cp
    LEFT JOIN UserProfiles up ON up.UserId = p_UserId AND up.IsDeleted = 0
    WHERE  cp.CommunityPostId = p_CommunityPostId
    LIMIT  1;
END //

DELIMITER ;

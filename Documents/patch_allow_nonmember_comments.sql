-- ─────────────────────────────────────────────────────────────────────────────
-- patch_allow_nonmember_comments.sql
-- Policy change: org post comments now open to everyone by default.
--
-- Old behaviour: only APPROVED members of the org could comment on its posts.
-- New behaviour: anyone can comment on an org post UNLESS the admin has
--               explicitly set OrgMembers.CanComment = 0 for that user.
--               Non-members (no row in OrgMembers) are always allowed.
--
-- No table/column changes. Apply to Railway staging + production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Post_AddComment //
CREATE PROCEDURE Post_AddComment(
    IN p_PostId          INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_ParentCommentId INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId         INT UNSIGNED DEFAULT 0;
    DECLARE v_AuthorUserId  INT UNSIGNED DEFAULT 0;
    DECLARE v_CanComment    TINYINT(1)   DEFAULT 1;  -- default allow for everyone

    -- Look up the post's OrgId and author
    SELECT OrgId, UserId INTO v_OrgId, v_AuthorUserId
    FROM   Posts WHERE PostId = p_PostId AND IsDeleted = 0 LIMIT 1;

    -- For org posts: block only if admin has explicitly set CanComment = 0 for this member.
    -- Non-members (no row in OrgMembers) are allowed by default.
    IF v_OrgId > 0 THEN
        SELECT COALESCE(om.CanComment, 1) INTO v_CanComment
        FROM   OrgMembers om
        WHERE  om.OrgId = v_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
        LIMIT  1;
        -- If no membership row found, COALESCE returns 1 → allowed
    END IF;

    IF v_CanComment = 0 THEN
        SELECT 0    AS IsSuccess,
               'You have been restricted from commenting in this organisation.' AS Message,
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

DELIMITER ;

SELECT 'patch_allow_nonmember_comments applied successfully.' AS Status;

-- =============================================================================
-- Patch: Community Likes + Comments full feature
-- Adds: LikeCount, CommentCount to CommunityPosts
--       CommunityPostLikes, CommunityPostComments, CommunityCommentLikes tables
--       SPs: Community_LikePost, Community_AddComment,
--            Community_GetComments, Community_LikeComment
-- Also updates Community_GetFeed to return LikeCount, CommentCount, IsLikedByMe
-- =============================================================================
USE ngoconnect;

-- ── 1. Add columns to CommunityPosts ─────────────────────────────────────────
ALTER TABLE CommunityPosts
  ADD COLUMN LikeCount    INT UNSIGNED NOT NULL DEFAULT 0 AFTER AcknowledgeCount,
  ADD COLUMN CommentCount INT UNSIGNED NOT NULL DEFAULT 0 AFTER LikeCount;

-- ── 2. CommunityPostLikes ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityPostLikes (
    CommunityPostLikeId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    CommunityPostId     INT UNSIGNED  NOT NULL,
    UserId              INT UNSIGNED  NOT NULL,
    CreatedAt           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityPostLikeId),
    UNIQUE KEY uq_commlike_post_user (CommunityPostId, UserId),
    INDEX idx_commlike_user          (UserId),
    CONSTRAINT fk_commlike_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId),
    CONSTRAINT fk_commlike_user FOREIGN KEY (UserId)          REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 3. CommunityPostComments ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityPostComments (
    CommunityCommentId  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    CommunityPostId     INT UNSIGNED  NOT NULL,
    UserId              INT UNSIGNED  NOT NULL,
    Content             TEXT          NOT NULL,
    LikeCount           INT UNSIGNED  NOT NULL DEFAULT 0,
    IsDeleted           TINYINT(1)    NOT NULL DEFAULT 0,
    DeletedAt           DATETIME      NULL,
    DeletedBy           INT UNSIGNED  NULL,
    CreatedAt           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityCommentId),
    INDEX idx_commcomment_post (CommunityPostId, IsDeleted),
    INDEX idx_commcomment_user (UserId),
    CONSTRAINT fk_commcomment_post FOREIGN KEY (CommunityPostId) REFERENCES CommunityPosts(CommunityPostId),
    CONSTRAINT fk_commcomment_user FOREIGN KEY (UserId)          REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 4. CommunityCommentLikes ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS CommunityCommentLikes (
    CommunityCommentLikeId INT UNSIGNED NOT NULL AUTO_INCREMENT,
    CommunityCommentId     INT UNSIGNED NOT NULL,
    UserId                 INT UNSIGNED NOT NULL,
    CreatedAt              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (CommunityCommentLikeId),
    UNIQUE KEY uq_commcommentlike (CommunityCommentId, UserId),
    CONSTRAINT fk_commcommentlike_comment FOREIGN KEY (CommunityCommentId) REFERENCES CommunityPostComments(CommunityCommentId),
    CONSTRAINT fk_commcommentlike_user    FOREIGN KEY (UserId)              REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER //

-- ── 5. Community_GetFeed (updated: adds LikeCount, CommentCount, IsLikedByMe) ─
DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId, cp.Title, cp.Content,
        ptv.ValueCode  AS PostType,
        ptv.ValueName  AS PostTypeName,
        av.ValueCode   AS AudienceCode,
        cp.IsPinned,
        cp.AcknowledgeCount,
        cp.LikeCount,
        cp.CommentCount,
        cp.AssignedToUserId,
        CONCAT(aup.FirstName,' ',aup.LastName) AS AssignedToName,
        cp.DueDate,
        tsv.ValueCode  AS TaskStatus,
        cp.PollEndsAt,
        cp.PollIsMultiChoice,
        cp.VolunteersNeeded,
        cp.ResourceFileUrl,
        cp.EventRef,
        cp.CreatedAt,
        cp.UserId,
        CONCAT(up.FirstName,' ',up.LastName) AS AuthorName,
        CONCAT(up.FirstName,' ',up.LastName) AS FullName,
        up.ProfilePhoto,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledged,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe,
        IF(cpl.CommunityPostLikeId IS NOT NULL,  1, 0) AS IsLiked,
        IF(cpl.CommunityPostLikeId IS NOT NULL,  1, 0) AS IsLikedByMe
    FROM   CommunityPosts cp
    JOIN   UserProfiles up  ON cp.UserId = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN UserProfiles aup ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT   JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT   JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT   JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT   JOIN CommunityPostAcknowledgements cpa
               ON cp.CommunityPostId = cpa.CommunityPostId AND cpa.UserId = p_UserId
    LEFT   JOIN CommunityPostLikes cpl
               ON cp.CommunityPostId = cpl.CommunityPostId AND cpl.UserId = p_UserId
    WHERE  cp.OrgId = p_OrgId AND cp.IsDeleted = 0
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts WHERE OrgId = p_OrgId AND IsDeleted = 0;
END //

-- ── 6. Community_LikePost — toggle like, returns new state ───────────────────
DROP PROCEDURE IF EXISTS Community_LikePost //
CREATE PROCEDURE Community_LikePost(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED
)
BEGIN
    DECLARE v_Exists   INT DEFAULT 0;
    DECLARE v_NewCount INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM CommunityPostLikes
    WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        DELETE FROM CommunityPostLikes
        WHERE CommunityPostId = p_CommunityPostId AND UserId = p_UserId;
    ELSE
        INSERT IGNORE INTO CommunityPostLikes (CommunityPostId, UserId)
        VALUES (p_CommunityPostId, p_UserId);
    END IF;

    UPDATE CommunityPosts
    SET LikeCount = (SELECT COUNT(*) FROM CommunityPostLikes WHERE CommunityPostId = p_CommunityPostId)
    WHERE CommunityPostId = p_CommunityPostId;

    SELECT LikeCount INTO v_NewCount FROM CommunityPosts WHERE CommunityPostId = p_CommunityPostId;

    SELECT 1 AS IsSuccess,
           IF(v_Exists > 0, 'Post unliked.' , 'Post liked.') AS Message,
           IF(v_Exists > 0, 0, 1)                            AS IsLiked,
           v_NewCount                                         AS LikeCount;
END //

-- ── 7. Community_AddComment ───────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_AddComment //
CREATE PROCEDURE Community_AddComment(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_Content         TEXT
)
BEGIN
    IF p_Content IS NULL OR TRIM(p_Content) = '' THEN
        SELECT 0 AS IsSuccess, 'Comment cannot be empty.' AS Message, NULL AS CommunityCommentId;
    ELSE
        INSERT INTO CommunityPostComments (CommunityPostId, UserId, Content)
        VALUES (p_CommunityPostId, p_UserId, TRIM(p_Content));

        UPDATE CommunityPosts
        SET CommentCount = CommentCount + 1
        WHERE CommunityPostId = p_CommunityPostId;

        SELECT 1 AS IsSuccess, 'Comment added.' AS Message, LAST_INSERT_ID() AS CommunityCommentId;
    END IF;
END //

-- ── 8. Community_GetComments ──────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_GetComments //
CREATE PROCEDURE Community_GetComments(
    IN p_CommunityPostId INT UNSIGNED,
    IN p_UserId          INT UNSIGNED
)
BEGIN
    SELECT
        cc.CommunityCommentId,
        cc.CommunityPostId,
        cc.UserId,
        CONCAT(up.FirstName,' ',up.LastName) AS AuthorName,
        up.ProfilePhoto,
        cc.Content,
        cc.LikeCount,
        IF(cl.CommunityCommentLikeId IS NOT NULL, 1, 0) AS IsLikedByMe,
        cc.CreatedAt
    FROM   CommunityPostComments cc
    JOIN   UserProfiles up ON cc.UserId = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN CommunityCommentLikes cl
               ON cc.CommunityCommentId = cl.CommunityCommentId AND cl.UserId = p_UserId
    WHERE  cc.CommunityPostId = p_CommunityPostId AND cc.IsDeleted = 0
    ORDER  BY cc.CreatedAt ASC;
END //

-- ── 9. Community_LikeComment — toggle like on a comment ──────────────────────
DROP PROCEDURE IF EXISTS Community_LikeComment //
CREATE PROCEDURE Community_LikeComment(
    IN p_CommunityCommentId INT UNSIGNED,
    IN p_UserId             INT UNSIGNED
)
BEGIN
    DECLARE v_Exists   INT DEFAULT 0;
    DECLARE v_NewCount INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM CommunityCommentLikes
    WHERE CommunityCommentId = p_CommunityCommentId AND UserId = p_UserId;

    IF v_Exists > 0 THEN
        DELETE FROM CommunityCommentLikes
        WHERE CommunityCommentId = p_CommunityCommentId AND UserId = p_UserId;
    ELSE
        INSERT IGNORE INTO CommunityCommentLikes (CommunityCommentId, UserId)
        VALUES (p_CommunityCommentId, p_UserId);
    END IF;

    UPDATE CommunityPostComments
    SET LikeCount = (SELECT COUNT(*) FROM CommunityCommentLikes WHERE CommunityCommentId = p_CommunityCommentId)
    WHERE CommunityCommentId = p_CommunityCommentId;

    SELECT LikeCount INTO v_NewCount FROM CommunityPostComments WHERE CommunityCommentId = p_CommunityCommentId;

    SELECT 1 AS IsSuccess,
           IF(v_Exists > 0, 'Comment unliked.', 'Comment liked.') AS Message,
           IF(v_Exists > 0, 0, 1) AS IsLiked,
           v_NewCount              AS LikeCount;
END //

DELIMITER ;

-- =============================================================================
-- NGO Connect — Community Module: Combined Railway Patch (v2 — 2026-07-12)
-- Applies all community patch files in correct order.
-- Safe to re-run: SP fixes use DROP IF EXISTS; DDL uses INFORMATION_SCHEMA guard.
--
-- Fixes:
--   1. CommunityPosts: add LikeCount + CommentCount columns (if missing)
--   2. New tables: CommunityPostLikes, CommunityPostComments, CommunityCommentLikes
--   3. Community_CreatePost: 14-param → 6-param; FIXED audience TypeCode AUDIENCE_TYPE
--   4. Community_CreatePoll: ADDED p_IsMultiChoice param; FIXED audience TypeCode AUDIENCE_TYPE
--   5. Community_Vote: fixed to 3-param
--   6. Community_GetFeed: v4.3 FINAL — PollOptionsJson, RoleName, TimeAgo, PostTypeLkpCode
--   7. New SPs: Community_LikePost, Community_AddComment,
--               Community_GetComments, Community_LikeComment
-- =============================================================================

USE ngoconnect;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1: DDL — Add columns to CommunityPosts (guarded)
-- ─────────────────────────────────────────────────────────────────────────────

-- Add LikeCount if missing
SET @like_exists = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ngoconnect'
      AND TABLE_NAME   = 'CommunityPosts'
      AND COLUMN_NAME  = 'LikeCount'
);
SET @sql1 = IF(@like_exists = 0,
    'ALTER TABLE CommunityPosts ADD COLUMN LikeCount INT UNSIGNED NOT NULL DEFAULT 0 AFTER AcknowledgeCount',
    'SELECT 1 -- LikeCount already exists'
);
PREPARE stmt1 FROM @sql1; EXECUTE stmt1; DEALLOCATE PREPARE stmt1;

-- Add CommentCount if missing
SET @comment_exists = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ngoconnect'
      AND TABLE_NAME   = 'CommunityPosts'
      AND COLUMN_NAME  = 'CommentCount'
);
SET @sql2 = IF(@comment_exists = 0,
    'ALTER TABLE CommunityPosts ADD COLUMN CommentCount INT UNSIGNED NOT NULL DEFAULT 0 AFTER LikeCount',
    'SELECT 1 -- CommentCount already exists'
);
PREPARE stmt2 FROM @sql2; EXECUTE stmt2; DEALLOCATE PREPARE stmt2;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2: New tables (CREATE TABLE IF NOT EXISTS = always safe)
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3: Stored Procedures
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── Community_CreatePost: 14-param → 6-param (THE critical fix) ──────────────
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId        INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_Title         VARCHAR(300),
    IN p_Content       TEXT,
    IN p_PostTypeLkpId INT UNSIGNED,
    IN p_AudienceLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    IF p_AudienceLkpId IS NULL OR p_AudienceLkpId = 0 THEN
        SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS'
        LIMIT  1;
        SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
    END IF;

    INSERT INTO CommunityPosts
        (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, CreatedBy)
    VALUES
        (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_UserId);

    SELECT 1                    AS IsSuccess,
           'Post created.'      AS Message,
           LAST_INSERT_ID()     AS CommunityPostId;
END //

-- ── Community_CreatePoll: 6-param (added p_IsMultiChoice; AUDIENCE_TYPE fix) ──
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
    DECLARE v_PollTypeLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId INT UNSIGNED DEFAULT 0;

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
END //

-- ── Community_Vote: fixed to 3-param ─────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_Vote //
CREATE PROCEDURE Community_Vote(
    IN p_PollId       INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_PollOptionId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists  INT DEFAULT 0;
    DECLARE v_Expired INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Expired FROM CommunityPosts
    WHERE  CommunityPostId = p_PollId
      AND  PollEndsAt IS NOT NULL AND PollEndsAt < NOW();

    SELECT COUNT(*) INTO v_Exists FROM PollVotes
    WHERE  CommunityPostId = p_PollId AND UserId = p_UserId;

    IF v_Expired > 0 THEN
        SELECT 0 AS IsSuccess, 'This poll has expired.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already voted on this poll.' AS Message;
    ELSE
        INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId)
        VALUES (p_PollOptionId, p_PollId, p_UserId);

        UPDATE PollOptions SET VoteCount = VoteCount + 1
        WHERE  PollOptionId = p_PollOptionId;

        SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
    END IF;
END //

-- ── Community_GetFeed: v4.3 FINAL — PollOptionsJson, RoleName, TimeAgo ────────
DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId,
        cp.Title,
        cp.Content,
        ptv.ValueCode  AS PostType,
        ptv.ValueCode  AS PostTypeLkpCode,
        ptv.ValueName  AS PostTypeName,
        av.ValueCode   AS AudienceCode,
        cp.IsPinned,
        cp.AcknowledgeCount,
        cp.LikeCount,
        cp.CommentCount,
        cp.AssignedToUserId,
        CONCAT(aup.FirstName, ' ', aup.LastName) AS AssignedToName,
        cp.DueDate,
        tsv.ValueCode  AS TaskStatus,
        cp.PollEndsAt,
        cp.PollIsMultiChoice,
        cp.VolunteersNeeded,
        cp.ResourceFileUrl,
        cp.EventRef,
        cp.CreatedAt,
        cp.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledged,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLiked,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLikedByMe,

        -- Author's role in the org (Admin / Member / Volunteer / etc.)
        rv.ValueName AS RoleName,

        -- Human-readable elapsed time since post was created
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()), 'd ago')
            ELSE DATE_FORMAT(cp.CreatedAt, '%d %b')
        END AS TimeAgo,

        -- Poll options JSON — populated for POLL type only.
        -- DAL parses this into typed pollOptions array with votePct calculation.
        (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'pollOptionId', po.PollOptionId,
                    'optionText',   po.OptionText,
                    'voteCount',    po.VoteCount,
                    'isVoted',      IF(pv.PollVoteId IS NOT NULL, 1, 0)
                )
            )
            FROM   PollOptions po
            LEFT   JOIN PollVotes pv
                       ON po.PollOptionId = pv.PollOptionId
                      AND pv.UserId       = p_UserId
            WHERE  po.CommunityPostId = cp.CommunityPostId
        ) AS PollOptionsJson

    FROM   CommunityPosts cp
    JOIN   UserProfiles up   ON cp.UserId           = up.UserId  AND up.IsDeleted  = 0
    LEFT   JOIN UserProfiles aup
                             ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT   JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT   JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT   JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT   JOIN CommunityPostAcknowledgements cpa
                             ON cp.CommunityPostId = cpa.CommunityPostId
                            AND cpa.UserId         = p_UserId
    LEFT   JOIN CommunityPostLikes cpl
                             ON cp.CommunityPostId = cpl.CommunityPostId
                            AND cpl.UserId         = p_UserId
    -- Author's membership role badge
    LEFT   JOIN OrgMembers om ON om.OrgId    = cp.OrgId
                             AND om.UserId   = cp.UserId
                             AND om.IsDeleted = 0
    LEFT   JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId

    WHERE  cp.OrgId    = p_OrgId
      AND  cp.IsDeleted = 0
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts
    WHERE  OrgId     = p_OrgId
      AND  IsDeleted = 0;
END //

-- ── Community_LikePost: toggle like ──────────────────────────────────────────
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

-- ── Community_AddComment ──────────────────────────────────────────────────────
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

-- ── Community_GetComments ─────────────────────────────────────────────────────
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

-- ── Community_LikeComment ─────────────────────────────────────────────────────
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

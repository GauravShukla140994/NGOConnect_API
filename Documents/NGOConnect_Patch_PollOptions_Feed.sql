-- =============================================================================
-- Patch: Community_GetFeed — add PollOptionsJson, RoleName, TimeAgo
--
-- Run AFTER:
--   NGOConnect_Patch_CommunityLikesComments.sql     (adds LikeCount, CommentCount cols + tables)
--   NGOConnect_Patch_CommunityCreatePost_SPFix.sql  (6-param Community_CreatePost)
--   NGOConnect_Patch_CommunityPollVote_SPFix.sql    (5-param Community_CreatePoll, 3-param Community_Vote)
--
-- This patch ONLY replaces Community_GetFeed. No table changes.
-- All required columns (LikeCount, CommentCount) already exist from LikesComments patch.
--
-- What changes vs. previous Community_GetFeed version:
--   + PollOptionsJson  — correlated subquery: poll options with voteCount + isVoted per user
--   + RoleName         — author's role in the org (Admin / Member / etc.)
--   + TimeAgo          — human-readable "2h ago", "3d ago" (computed from CreatedAt)
--   + PostTypeLkpCode  — alias so frontend can use either PostType or PostTypeLkpCode
--
-- Safe to re-run: uses DROP PROCEDURE IF EXISTS.
-- =============================================================================

USE ngoconnect;

DELIMITER //

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

        -- Poll options as a JSON array — only populated for POLL post type.
        -- DAL (CommunityDal.GetFeedAsync) parses this into typed pollOptions array.
        -- Includes voteCount per option and whether the current user voted on it.
        -- NOTE: JSON_ARRAYAGG in MySQL 8.0 does NOT support ORDER BY inside the aggregate.
        -- Options are returned in PollOptionId (PK) order, which matches SortOrder
        -- because Community_CreatePoll inserts options sequentially (SortOrder = insertion rn).
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
    -- Join on the POST AUTHOR's membership to show their role badge on the card
    LEFT   JOIN OrgMembers om ON om.OrgId    = cp.OrgId
                             AND om.UserId   = cp.UserId
                             AND om.IsDeleted = 0
    LEFT   JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId

    WHERE  cp.OrgId    = p_OrgId
      AND  cp.IsDeleted = 0
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- Second result set: total count for pagination
    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts
    WHERE  OrgId      = p_OrgId
      AND  IsDeleted  = 0;
END //

DELIMITER ;

-- =============================================================================
-- Patch: Community_GetFeed — fix column name mismatches
-- Problem: SP returned AuthorName + IsAcknowledgedByMe but frontend
--          types expect authorName (same) and isAcknowledgedByMe (same).
--          Frontend had: item.fullName (crash), item.isAcknowledged (always false).
-- Fix: Rename AuthorName → FullName so CommunityPost.fullName works too;
--      rename IsAcknowledgedByMe → IsAcknowledged to match the type field.
-- Frontend fix also applied: CommunityScreen uses (item.authorName ?? item.fullName)
--                            so either column name works.
-- Run once in MySQL Workbench against ngoconnect DB.
-- =============================================================================

USE ngoconnect;

DROP PROCEDURE IF EXISTS Community_GetFeed;

DELIMITER //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT; SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId,
        cp.Title,
        cp.Content,
        ptv.ValueCode  AS PostType,
        ptv.ValueName  AS PostTypeName,
        av.ValueCode   AS AudienceCode,
        cp.IsPinned,
        cp.AcknowledgeCount,
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
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,   -- frontend reads authorName (camelCase)
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,     -- also expose as fullName for type compat
        up.ProfilePhoto,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledged,      -- matches CommunityPost.isAcknowledged
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe   -- also expose legacy name
    FROM   CommunityPosts cp
    JOIN   UserProfiles up  ON cp.UserId = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN UserProfiles aup ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT   JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT   JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT   JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT   JOIN CommunityPostAcknowledgements cpa
           ON cp.CommunityPostId = cpa.CommunityPostId AND cpa.UserId = p_UserId
    WHERE  cp.OrgId = p_OrgId AND cp.IsDeleted = 0
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts
    WHERE  OrgId = p_OrgId AND IsDeleted = 0;
END //
DELIMITER ;

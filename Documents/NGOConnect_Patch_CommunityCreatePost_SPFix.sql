-- =============================================================================
-- Patch: Community_CreatePost — replace 14-param setup SQL version
--        with the correct 6-param version that matches CommunityDal.cs
--
-- Problem: NGOConnect_Complete_Setup_v4.1.sql had a 14-param version:
--   Community_CreatePost(p_OrgId, p_UserId, p_PostTypeLkpId, p_AudienceLkpId,
--                        p_Title, p_Content, p_AssignedToUserId, p_DueDate,
--                        p_TaskStatusLkpId, p_PollEndsAt, p_PollIsMultiChoice,
--                        p_VolunteersNeeded, p_ResourceFileUrl, p_EventRef)
--
-- DAL (CommunityDal.CreatePostAsync) only sends 6 params →
--   "Parameter not found" error for all non-poll post types.
--
-- Run AFTER NGOConnect_Patch_CommunityFeed_ColumnFix.sql
-- Run BEFORE or AFTER NGOConnect_Patch_CommunityPollVote_SPFix.sql (order doesn't matter)
--
-- Safe to re-run: uses DROP PROCEDURE IF EXISTS.
-- =============================================================================

USE ngoconnect;

DELIMITER //

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

    -- Default audience to ALL_MEMBERS if not provided
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

DELIMITER ;

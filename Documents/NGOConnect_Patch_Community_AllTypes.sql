-- ═══════════════════════════════════════════════════════════════════════════════
-- PATCH: Community — All Post Types (Save + View)
-- Version: v4.8
-- Date:    2026-07-18
-- Author:  Gaurav Shukla
--
-- Purpose
-- ───────
-- Community_CreatePost previously saved only Title, Content, AudienceLkpId,
-- and ResourceFileUrl.  The following data was silently dropped:
--
--   ANNOUNCEMENT  → IsPinned (pin the post to top of feed)
--   VOL_REQUEST   → VolunteersNeeded (count), EventRef (date/time display text)
--   EVENT_UPDATE  → EventRef (whatChanged text, e.g. "Venue changed")
--   TASK          → EventRef (free-text assignee name)
--
-- Three new SP parameters are added.  All target columns already exist in the
-- CommunityPosts table — NO schema changes required.
--
-- Apply order
-- ───────────
-- 1. Run this patch on LOCAL DB first and smoke-test all 8 post types.
-- 2. Run on Railway staging → full QA pass.
-- 3. Run on Railway production during next release window.
--
-- Related patches already pending Railway deploy
-- ───────────────────────────────────────────────
--   NGOConnect_Patch_Community_ResourceUpload.sql  (ResourceFileUrl — superseded by this patch)
--   This patch supersedes the ResourceUpload patch — apply THIS one only.
-- ═══════════════════════════════════════════════════════════════════════════════

DELIMITER //

-- ── Community_CreatePost ─────────────────────────────────────────────────────
-- New params:
--   p_IsPinned         TINYINT(1)    — ANNOUNCEMENT: pin post to top of feed
--   p_VolunteersNeeded INT UNSIGNED  — VOL_REQUEST: number of slots needed
--   p_EventRef         VARCHAR(200)  — multipurpose extra text (see above)
-- ─────────────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId           INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_Title            VARCHAR(300),
    IN p_Content          TEXT,
    IN p_PostTypeLkpId    INT UNSIGNED,
    IN p_AudienceLkpId    INT UNSIGNED,
    IN p_ResourceFileUrl  VARCHAR(500),
    IN p_IsPinned         TINYINT(1),
    IN p_VolunteersNeeded INT UNSIGNED,
    IN p_EventRef         VARCHAR(200)
)
BEGIN
    DECLARE v_ApprovedLkpId        INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost     TINYINT(1)  DEFAULT 0;
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
            FROM   LookupValues lv
            JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS'
            LIMIT  1;
            SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
        END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId,
             IsPinned, VolunteersNeeded, EventRef, ResourceFileUrl, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId,
             COALESCE(p_IsPinned, 0), p_VolunteersNeeded, p_EventRef, p_ResourceFileUrl, p_UserId);

        SELECT 1                    AS IsSuccess,
               'Post created.'      AS Message,
               LAST_INSERT_ID()     AS CommunityPostId;
    END IF;
END //

DELIMITER ;

-- ═══════════════════════════════════════════════════════════════════════════════
-- Smoke test (run manually after applying):
--
-- CALL Community_CreatePost(1, 1, 'Test Announcement', 'Body text',
--   (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt
--    ON lt.LookupTypeId=lv.LookupTypeId
--    WHERE lt.TypeCode='POST_TYPE_COMMUNITY' AND lv.ValueCode='ANNOUNCEMENT' LIMIT 1),
--   NULL, NULL, 1, NULL, NULL);
--
-- CALL Community_CreatePost(1, 1, 'Need help at food drive', 'Cooking skills preferred',
--   (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt
--    ON lt.LookupTypeId=lv.LookupTypeId
--    WHERE lt.TypeCode='POST_TYPE_COMMUNITY' AND lv.ValueCode='VOL_REQUEST' LIMIT 1),
--   NULL, NULL, 0, 10, 'Jun 14, 6:30 AM');
--
-- CALL Community_CreatePost(1, 1, 'Food Drive - Jun 3', 'Venue has moved to City Hall',
--   (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt
--    ON lt.LookupTypeId=lv.LookupTypeId
--    WHERE lt.TypeCode='POST_TYPE_COMMUNITY' AND lv.ValueCode='EVENT_UPDATE' LIMIT 1),
--   NULL, NULL, 0, NULL, 'Venue changed');
--
-- CALL Community_CreatePost(1, 1, 'Set up registration table', 'Arrive 30 min early',
--   (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt
--    ON lt.LookupTypeId=lv.LookupTypeId
--    WHERE lt.TypeCode='POST_TYPE_COMMUNITY' AND lv.ValueCode='TASK' LIMIT 1),
--   NULL, NULL, 0, NULL, 'Priya Sharma');
--
-- After each call verify in CommunityPosts table:
--   SELECT CommunityPostId, IsPinned, VolunteersNeeded, EventRef, ResourceFileUrl
--   FROM   CommunityPosts ORDER BY CommunityPostId DESC LIMIT 5;
-- ═══════════════════════════════════════════════════════════════════════════════

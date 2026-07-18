-- ═══════════════════════════════════════════════════════════════════
-- NGOConnect Patch — Community_CreatePost: ResourceFileUrl support
-- Adds p_ResourceFileUrl param so RESOURCE post type can attach a file
-- Apply to: local dev DB and Railway staging/production
-- ═══════════════════════════════════════════════════════════════════

DELIMITER //

DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Title           VARCHAR(300),
    IN p_Content         TEXT,
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_AudienceLkpId   INT UNSIGNED,
    IN p_ResourceFileUrl VARCHAR(500)
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
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId, ResourceFileUrl, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId, p_ResourceFileUrl, p_UserId);

        SELECT 1                    AS IsSuccess,
               'Post created.'      AS Message,
               LAST_INSERT_ID()     AS CommunityPostId;
    END IF;
END //

DELIMITER ;

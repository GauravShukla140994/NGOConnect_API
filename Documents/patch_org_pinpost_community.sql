-- ============================================================
-- Patch: Fix Org_PinPost — was querying Posts (feed) table,
--        corrected to CommunityPosts table.
-- Root cause: Admin Community tab sends CommunityPostId but
--   SP was doing SELECT/UPDATE on Posts with PostId — always
--   returned "Post not found."
-- No C# / mobile changes needed.
-- Apply to: local → Railway staging → Railway production
-- ============================================================

DROP PROCEDURE IF EXISTS Org_PinPost;

DELIMITER $$

CREATE PROCEDURE Org_PinPost(
    IN p_PostId   INT UNSIGNED,
    IN p_OrgId    INT UNSIGNED,
    IN p_PinnedBy INT UNSIGNED
)
BEGIN
    DECLARE v_Current TINYINT(1);
    SELECT IsPinned INTO v_Current FROM CommunityPosts
    WHERE CommunityPostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1;

    IF v_Current IS NULL THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        UPDATE CommunityPosts
        SET IsPinned  = NOT v_Current,
            UpdatedBy = p_PinnedBy
        WHERE CommunityPostId = p_PostId AND OrgId = p_OrgId;

        SELECT 1 AS IsSuccess,
               CASE WHEN NOT v_Current = 1 THEN 'Post pinned.' ELSE 'Post unpinned.' END AS Message;
    END IF;
END$$

DELIMITER ;

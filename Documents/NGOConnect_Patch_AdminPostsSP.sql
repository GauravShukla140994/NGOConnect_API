-- ============================================================
-- NGO Connect — Patch: Org_GetAdminPosts + Org_PinPost +
--               Org_DeletePost + Org_ModeratePost
-- Version : v4.3 patch
-- Date    : 2026-07-07
-- Purpose : Posts tab in s-admin-vols was completely missing on backend.
--           These SPs power GET/admin community-posts and moderation actions.
-- Apply   : Run against NGOConnect database.
-- ============================================================

DELIMITER //

-- ── Org_GetAdminPosts ───────────────────────────────────────────────────────
-- Returns all feed Posts for an org (OrgId = p_OrgId) enriched with:
--   - poster's name, role inside the org
--   - denormalized LikeCount + CommentCount (already on Posts table)
--   - ReportCount from PostReports (PENDING reports only = unresolved)
--   - derived StatusCode: REPORTED if has pending reports, else PUBLISHED
DROP PROCEDURE IF EXISTS Org_GetAdminPosts //
CREATE PROCEDURE Org_GetAdminPosts(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_PendingReportLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingReportLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    SELECT
        p.PostId,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)  AS FullName,
        up.ProfilePhoto,
        rv.ValueCode                             AS RoleCode,
        rv.ValueName                             AS RoleName,
        p.Content,
        p.LikeCount                              AS LikesCount,
        p.CommentCount                           AS CommentsCount,
        p.IsPinned,
        p.CreatedAt,
        -- Count unresolved (PENDING) reports against this post
        COALESCE((
            SELECT COUNT(*) FROM PostReports pr
            WHERE pr.PostId = p.PostId
              AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
        ), 0)                                    AS ReportCount,
        -- StatusCode: REPORTED if any pending reports, else PUBLISHED
        CASE
            WHEN COALESCE((
                SELECT COUNT(*) FROM PostReports pr
                WHERE pr.PostId = p.PostId
                  AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
            ), 0) > 0 THEN 'REPORTED'
            ELSE 'PUBLISHED'
        END                                      AS StatusCode
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om ON p.UserId = om.UserId AND om.OrgId = p_OrgId AND om.IsDeleted = 0
    LEFT JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
    WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC;
END //

-- ── Org_PinPost ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_PinPost //
CREATE PROCEDURE Org_PinPost(
    IN p_PostId   INT UNSIGNED,
    IN p_OrgId    INT UNSIGNED,
    IN p_PinnedBy INT UNSIGNED
)
BEGIN
    DECLARE v_Current TINYINT(1);
    SELECT IsPinned INTO v_Current FROM Posts
    WHERE PostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0 LIMIT 1;

    IF v_Current IS NULL THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        UPDATE Posts
        SET IsPinned = NOT v_Current,
            PinnedAt = CASE WHEN NOT v_Current = 1 THEN NOW() ELSE NULL END,
            PinnedBy = CASE WHEN NOT v_Current = 1 THEN p_PinnedBy ELSE NULL END,
            UpdatedBy = p_PinnedBy
        WHERE PostId = p_PostId AND OrgId = p_OrgId;

        SELECT 1 AS IsSuccess,
               CASE WHEN NOT v_Current = 1 THEN 'Post pinned.' ELSE 'Post unpinned.' END AS Message;
    END IF;
END //

-- ── Org_DeletePost ──────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_DeletePost //
CREATE PROCEDURE Org_DeletePost(
    IN p_PostId    INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_DeletedBy INT UNSIGNED
)
BEGIN
    UPDATE Posts
    SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_DeletedBy, UpdatedBy = p_DeletedBy
    WHERE PostId = p_PostId AND OrgId = p_OrgId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Post not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Post deleted.' AS Message;
    END IF;
END //

-- ── Org_ModeratePost ────────────────────────────────────────────────────────
-- action: KEEP (clear reports) | REMOVE (delete post + clear reports)
DROP PROCEDURE IF EXISTS Org_ModeratePost //
CREATE PROCEDURE Org_ModeratePost(
    IN p_PostId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,
    IN p_ReviewedBy INT UNSIGNED,
    IN p_Action     VARCHAR(10)     -- 'KEEP' or 'REMOVE'
)
BEGIN
    DECLARE v_ResolvedLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ResolvedLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'RESOLVED'
    LIMIT 1;

    -- Mark all reports on this post as RESOLVED
    UPDATE PostReports
    SET StatusLkpId = v_ResolvedLkpId,
        ReviewedBy  = p_ReviewedBy,
        ReviewedAt  = NOW()
    WHERE PostId = p_PostId;

    -- If REMOVE, also soft-delete the post
    IF p_Action = 'REMOVE' THEN
        UPDATE Posts
        SET IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_ReviewedBy, UpdatedBy = p_ReviewedBy
        WHERE PostId = p_PostId AND OrgId = p_OrgId;
    END IF;

    SELECT 1 AS IsSuccess,
           CASE WHEN p_Action = 'REMOVE' THEN 'Post removed.' ELSE 'Reports cleared.' END AS Message;
END //

DELIMITER ;

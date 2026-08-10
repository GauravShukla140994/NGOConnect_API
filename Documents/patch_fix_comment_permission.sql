-- ── patch_fix_comment_permission.sql ─────────────────────────────────────────
-- Fix: Post_GetPermissions returned CanComment=0 for non-members of the org
--      that authored the post, blocking comments on all public posts for users
--      who had not joined that specific organisation.
--
-- Root cause: DECLARE v_CanComment DEFAULT 0 — when the user is not an approved
--   member, the SELECT INTO finds no row and v_CanComment stays at 0.
--
-- Fix: Default changed to 1.  Non-members have no per-member restriction.
--   The CanComment flag is only meaningful when the user IS an approved member
--   AND an admin has explicitly set OrgMembers.CanComment = 0 for them.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetPermissions //
CREATE PROCEDURE Post_GetPermissions(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember         TINYINT(1)  DEFAULT 0;
    DECLARE v_CanPost          TINYINT(1)  DEFAULT 0;
    DECLARE v_CanComment       TINYINT(1)  DEFAULT 1;  -- non-members can comment freely; only blocked when member has CanComment=0
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay        INT         DEFAULT 10;
    DECLARE v_TodayCount       INT         DEFAULT 0;

    -- Resolve APPROVED status lookup id
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Load member's permissions (only if APPROVED member)
    SELECT 1, om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay
    INTO   v_IsMember, v_CanPost, v_CanComment, v_CanCommunityPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    -- Count posts created today for this org
    SELECT COUNT(*) INTO v_TodayCount
    FROM   Posts
    WHERE  UserId = p_UserId AND OrgId = p_OrgId
      AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

    SELECT
        v_IsMember          AS IsMember,
        v_CanPost           AS CanPost,
        v_CanComment        AS CanComment,
        v_CanCommunityPost  AS CanCommunityPost,
        v_MaxPerDay         AS MaxPostsPerDay,
        v_TodayCount        AS TodayPostCount;
END //

DELIMITER ;

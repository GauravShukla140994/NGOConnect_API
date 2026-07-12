-- ══════════════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Post_GetPermissions SP
-- Date   : 2026-07-12
-- Scope  : 1 new SP
-- Run on : Local DB → verify → Railway staging (as part of combined v4.7 patch)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- New SP Post_GetPermissions(p_OrgId, p_UserId):
--   Returns exactly one row with:
--     IsMember      TINYINT(1) — 1 if user is an APPROVED member of the org
--     CanPost       TINYINT(1) — from OrgMembers.CanPost (default 1)
--     MaxPostsPerDay INT       — from OrgMembers.MaxPostsPerDay (default 10)
--     TodayPostCount INT       — posts created today by this user for this org
--
--   Used by mobile HomeScreen before opening Create Post modal.
--   Always returns one row (DECLARE defaults cover non-member case).
--
-- ══════════════════════════════════════════════════════════════════════════════

DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetPermissions //
CREATE PROCEDURE Post_GetPermissions(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember      TINYINT(1)  DEFAULT 0;
    DECLARE v_CanPost       TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay     INT         DEFAULT 10;
    DECLARE v_TodayCount    INT         DEFAULT 0;

    -- Resolve APPROVED status lookup id
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Load member's permissions (only if APPROVED member)
    SELECT 1, om.CanPost, om.MaxPostsPerDay
    INTO   v_IsMember, v_CanPost, v_MaxPerDay
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
        v_IsMember   AS IsMember,
        v_CanPost    AS CanPost,
        v_MaxPerDay  AS MaxPostsPerDay,
        v_TodayCount AS TodayPostCount;
END //

DELIMITER ;

-- ── patch_followed_orgs.sql ──────────────────────────────────────────────────
-- Feature : "Following" section on My Organizations screen.
--           Users who follow an NGO without being a member had no way to see
--           or access those organizations. This adds a dedicated section between
--           "Linked Organizations" and "Pending Review" on the My Orgs screen.
--
-- Changes:
--   SP NEW  : Org_GetFollowedByUser(p_UserId) — returns orgs the user actively
--             follows (IsFollowing=1) where they are NOT an approved member.
--             Returns: OrgId, OrgName, LogoUrl, City, State, MemberCount,
--                      FollowerCount, FollowedAt.
--             The NOT EXISTS sub-select ensures a member-org never appears in
--             both the Linked and Following sections simultaneously.
--
-- No table / column changes — OrgFollowers table already exists.
-- Safe to re-run. Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetFollowedByUser //

CREATE PROCEDURE Org_GetFollowedByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        o.City,
        o.State,
        o.FollowerCount,
        IFNULL((
            SELECT COUNT(*) FROM OrgMembers om2
            JOIN  LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
            JOIN  LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE om2.OrgId    = o.OrgId
              AND om2.IsDeleted = 0
              AND lt2.TypeCode  = 'MEMBER_STATUS'
              AND lv2.ValueCode = 'APPROVED'
        ), 0) AS MemberCount,
        f.FollowedAt
    FROM OrgFollowers f
    JOIN Organisations o ON f.OrgId = o.OrgId AND o.IsDeleted = 0
    WHERE f.UserId      = p_UserId
      AND f.IsFollowing = 1
      -- Exclude orgs where the user is already an active member
      AND NOT EXISTS (
          SELECT 1 FROM OrgMembers om
          JOIN  LookupValues ms ON om.StatusLkpId  = ms.LookupValueId
          JOIN  LookupTypes  mt ON ms.LookupTypeId = mt.LookupTypeId
          WHERE om.OrgId    = o.OrgId
            AND om.UserId   = p_UserId
            AND om.IsDeleted = 0
            AND mt.TypeCode  = 'MEMBER_STATUS'
            AND ms.ValueCode = 'APPROVED'
      )
    ORDER BY f.FollowedAt DESC;
END //

DELIMITER ;

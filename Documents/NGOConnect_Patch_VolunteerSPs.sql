-- ============================================================
-- NGO Connect — Patch: Org_GetMembers + Org_GetPendingMembers
-- Version : v4.3 patch
-- Date    : 2026-07-07
-- Problems:
--   1. Both SPs require (p_OrgId, p_PageNumber, p_PageSize) but
--      DAL passes only p_OrgId → MySQL throws param-count error
--      → catch block silently returns empty list → nothing shows in app.
--   2. Column name mismatches vs OrgMember frontend interface:
--      - OrgMemberId  → must alias as MemberId
--      - RequestId    → must alias as MembershipRequestId
--      - WhyJoin      → must alias as Motivation
--      - LocationSharingCode (string) → must return boolean LocationSharing
--      - Missing: Email, Phone, Occupation from Users/UserProfiles
-- Fix: Remove pagination params (DAL fetches all; paging handled client-side
--      for now). Alias all columns to match OrgMember interface exactly.
-- Apply : Run against NGOConnect database.
-- ============================================================

DELIMITER //

-- ── Org_GetMembers ──────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetMembers //
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId                                        AS MemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)               AS FullName,
        u.Email,
        u.Mobile                                             AS Phone,
        up.ProfilePhoto,
        up.Occupation,
        rv.ValueCode                                         AS RoleCode,
        rv.ValueName                                         AS RoleName,
        sv.ValueCode                                         AS StatusCode,
        sv.ValueName                                         AS StatusName,
        om.CanPost,
        om.CanComment,
        om.CanCommunityPost,
        om.MaxPostsPerDay,
        -- Return boolean: location sharing is ON when LkpId is not null and code != 'DISABLED'
        CASE WHEN lsv.ValueCode IS NOT NULL AND lsv.ValueCode != 'DISABLED'
             THEN 1 ELSE 0
        END                                                  AS LocationSharing,
        om.JoinedAt,
        u.IsActive,
        u.LastLoginAt                                        AS LastActiveAt
    FROM OrgMembers om
    JOIN Users        u  ON om.UserId = u.UserId  AND u.IsDeleted  = 0
    JOIN UserProfiles up ON om.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv  ON om.RoleLkpId            = rv.LookupValueId
    LEFT JOIN LookupValues sv  ON om.StatusLkpId          = sv.LookupValueId
    LEFT JOIN LookupValues lsv ON om.LocationSharingLkpId = lsv.LookupValueId
    WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt ASC;
END //

-- ── Org_GetPendingMembers ────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_GetPendingMembers //
CREATE PROCEDURE Org_GetPendingMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_PendingLkpId INT UNSIGNED;

    SELECT LookupValueId INTO v_PendingLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    SELECT
        mr.RequestId                                         AS MembershipRequestId,
        mr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)               AS FullName,
        u.Email,
        u.Mobile                                             AS Phone,
        up.ProfilePhoto,
        up.Occupation,
        up.City,
        up.State,
        mr.WhyJoin                                           AS Motivation,
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.CreatedAt                                         AS RequestedAt
    FROM OrgMembershipRequests mr
    JOIN Users        u  ON mr.UserId = u.UserId  AND u.IsDeleted  = 0
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    WHERE mr.OrgId = p_OrgId
      AND mr.StatusLkpId = v_PendingLkpId
      AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC;
END //

DELIMITER ;

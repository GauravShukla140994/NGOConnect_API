-- ============================================================
-- Patch: Fix Org_GetPendingMembers
-- Issues fixed:
--   1. mr.RequestId was not aliased → frontend received `requestId`
--      but OrgMember.membershipRequestId was undefined → Approve
--      button silently returned without calling the API.
--   2. p_PageNumber / p_PageSize had no defaults → DAL passing 0
--      params caused LIMIT NULL OFFSET NULL (broken results).
-- How to apply: run this file in MySQL Workbench on Railway staging
--               and production.
-- ============================================================

USE ngoconnect;

DROP PROCEDURE IF EXISTS Org_GetPendingMembers;

DELIMITER //

CREATE PROCEDURE Org_GetPendingMembers(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_PageSize    INT;
    DECLARE v_PageNumber  INT;
    DECLARE v_PendingLkpId INT UNSIGNED;

    -- Default to page 1, 100 rows when caller omits pagination
    SET v_PageNumber = IFNULL(p_PageNumber, 1);
    SET v_PageSize   = IFNULL(p_PageSize,   100);
    SET v_Offset     = (v_PageNumber - 1) * v_PageSize;

    SELECT LookupValueId INTO v_PendingLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    -- KEY FIX: alias RequestId AS MembershipRequestId so the JSON
    -- field `membershipRequestId` matches OrgMember.membershipRequestId
    -- on the mobile app.
    SELECT
        mr.RequestId   AS MembershipRequestId,   -- ← was: mr.RequestId (no alias)
        mr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        up.City,
        up.State,
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.WhyJoin,
        mr.CreatedAt AS RequestedAt
    FROM OrgMembershipRequests mr
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    WHERE mr.OrgId = p_OrgId
      AND mr.StatusLkpId = v_PendingLkpId
      AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC
    LIMIT v_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM OrgMembershipRequests
    WHERE OrgId = p_OrgId
      AND StatusLkpId = v_PendingLkpId
      AND IsDeleted = 0;
END //

DELIMITER ;

-- ============================================================
-- NGO Connect — Patch: Show unlinked members in SuperAdmin Members list
-- Apply directly to Railway staging/prod (or local) without
-- re-running the full setup script.
--
-- Root cause: SuperAdmin_User_GetList's HAVING clause only let a
-- zero-org-membership user through when p_OrgIds was NULL/empty.
-- The admin panel's Members page always sends a real, non-empty
-- org ID list (even its "all organisations" default resolves every
-- org into an explicit list) — so that condition was never actually
-- true on a real page load, and brand-new registrants who haven't
-- joined/founded any organisation yet were silently excluded no
-- matter what filter was selected.
--
-- Fix: the zero-org branch of HAVING no longer depends on p_OrgIds
-- at all — a user with no org memberships always passes, since
-- there's no org to filter them by. Behavior for everyone else
-- (must have at least one APPROVED membership) is unchanged.
--
-- Zero changes to any other table, SP, or the mobile/NGO-admin flow.
-- Safe to re-run: SP dropped first.
-- ============================================================

DROP PROCEDURE IF EXISTS SuperAdmin_User_GetList;

DELIMITER //

CREATE PROCEDURE SuperAdmin_User_GetList(
    IN p_OrgIds     TEXT,
    IN p_Search     VARCHAR(150),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT CASE WHEN sv.ValueCode = 'APPROVED' THEN o.OrgName END
                     ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS Role,
        (SELECT sv2.ValueCode FROM OrgMembers om2
            JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS MembershipStatus,
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        COALESCE(
            MIN(CASE WHEN sv.ValueCode = 'APPROVED' THEN om.JoinedAt END),
            u.CreatedAt
        ) AS JoinedAt
    FROM Users u
    JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
        AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
    LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN Organisations  o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues  pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.IsDeleted = 0
      AND (p_Search IS NULL OR p_Search = ''
           OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
           OR u.Email  LIKE CONCAT('%', p_Search, '%')
           OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
    GROUP BY
        u.UserId, up.FirstName, up.LastName, u.Email, u.Mobile,
        up.ProfilePhoto, u.IsActive, pv.ValueCode, u.CreatedAt
    HAVING
        COUNT(om.OrgMemberId) = 0
        OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ORDER BY JoinedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM (
        SELECT u.UserId
        FROM Users u
        JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
        LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
        WHERE u.IsDeleted = 0
          AND (p_Search IS NULL OR p_Search = ''
               OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
               OR u.Email  LIKE CONCAT('%', p_Search, '%')
               OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
        GROUP BY u.UserId
        HAVING
            COUNT(om.OrgMemberId) = 0
            OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ) t;
END //

DELIMITER ;

-- ============================================================
-- END OF PATCH
-- ============================================================

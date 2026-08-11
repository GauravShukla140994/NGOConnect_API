-- ============================================================
-- Patch: Org_GetAdminPosts — add PostMedia join
-- Adds MediaUrls (CSV) and MediaTypes (CSV) columns so the
-- Admin Volunteers → Posts tab can display post images/videos.
-- No C# / mobile DAL changes needed (DynamicRow auto-maps).
-- Apply to: local → Railway staging → Railway production
-- ============================================================

DROP PROCEDURE IF EXISTS Org_GetAdminPosts;

DELIMITER $$

CREATE PROCEDURE Org_GetAdminPosts(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_PendingReportLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_PendingReportLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT
        p.PostId, p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        rv.ValueCode AS RoleCode, rv.ValueName AS RoleName,
        p.Content,
        p.LikeCount    AS LikesCount,
        p.CommentCount AS CommentsCount,
        p.IsPinned, p.CreatedAt,
        COALESCE((SELECT COUNT(*) FROM PostReports pr
                  WHERE pr.PostId = p.PostId
                    AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
        ), 0) AS ReportCount,
        CASE WHEN COALESCE((SELECT COUNT(*) FROM PostReports pr
                            WHERE pr.PostId = p.PostId
                              AND (v_PendingReportLkpId IS NULL OR pr.StatusLkpId = v_PendingReportLkpId)
        ), 0) > 0 THEN 'REPORTED' ELSE 'PUBLISHED' END AS StatusCode,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes
    FROM Posts p
    JOIN UserProfiles up ON p.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om    ON p.UserId = om.UserId AND om.OrgId = p_OrgId AND om.IsDeleted = 0
    LEFT JOIN LookupValues rv    ON om.RoleLkpId = rv.LookupValueId
    LEFT JOIN PostMedia     pm   ON pm.PostId = p.PostId
    LEFT JOIN LookupValues  lv_mt ON lv_mt.LookupValueId = pm.MediaTypeLkpId
    WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
    GROUP BY
        p.PostId, p.UserId, up.FirstName, up.LastName, up.ProfilePhoto,
        rv.ValueCode, rv.ValueName, p.Content, p.LikeCount, p.CommentCount,
        p.IsPinned, p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC;
END$$

DELIMITER ;

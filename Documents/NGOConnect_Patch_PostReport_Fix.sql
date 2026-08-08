-- ============================================================
-- NGO Connect — Patch: Post Report Fix
-- Fixes: REPORT_STATUS lookup missing + duplicate Post_Report SP
-- Apply to: Railway staging + production
-- Date: 2026-07-14
-- ============================================================

-- ── 1. Seed REPORT_STATUS LookupType (missing from original seed) ──────────
INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType)
VALUES ('REPORT_STATUS', 'Report Status', 'Review status of a post report', 1);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT LookupTypeId, 'PENDING',  'Pending Review', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'REPORT_STATUS' AND lv2.ValueCode = 'PENDING')
UNION ALL
SELECT LookupTypeId, 'REVIEWED', 'Reviewed',       2, 1, 0 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'REPORT_STATUS' AND lv2.ValueCode = 'REVIEWED')
UNION ALL
SELECT LookupTypeId, 'RESOLVED', 'Resolved',       3, 1, 0 FROM LookupTypes WHERE TypeCode = 'REPORT_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'REPORT_STATUS' AND lv2.ValueCode = 'RESOLVED');

-- ── 2. Fix existing PostReports rows with NULL StatusLkpId ─────────────────
-- (Reports submitted before this patch will have NULL StatusLkpId due to the bug)
UPDATE PostReports pr
SET pr.StatusLkpId = (
    SELECT lv.LookupValueId FROM LookupValues lv
    JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1
)
WHERE pr.StatusLkpId IS NULL;

-- ── 3. Re-create Post_Report SP with correct REPORT_STATUS lookup ───────────
-- ── 4. Re-create Post_GetFeed — hide reported posts from the reporter ───────
DELIMITER //

DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId     INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_ReasonCode VARCHAR(50),
    IN p_Details    TEXT
)
BEGIN
    DECLARE v_ReasonLkpId  INT UNSIGNED;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_AlreadyExists INT DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ReasonLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'REPORT_REASON' AND lv.ValueCode = p_ReasonCode LIMIT 1;

    IF v_ReasonLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown reason code: ', p_ReasonCode) AS Message;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyExists
        FROM   PostReports
        WHERE  PostId = p_PostId AND ReportedByUserId = p_UserId;

        IF v_AlreadyExists > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
            VALUES (p_PostId, p_UserId, v_ReasonLkpId, p_Details, v_StatusLkpId);

            SELECT 1 AS IsSuccess, 'Post reported.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

-- ── 4. Re-create Post_GetFeed — hide reported posts from the reporter ────────
DELIMITER //

DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,
        p.LikeCount,
        p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLiked,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up         ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o      ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm         ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      AND  NOT EXISTS (
               SELECT 1 FROM PostReports pr
               WHERE pr.PostId = p.PostId AND pr.ReportedByUserId = p_UserId
           )
    GROUP BY
        p.PostId, p.Content, p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId, up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId, o.OrgName,
        p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      AND  NOT EXISTS (
               SELECT 1 FROM PostReports pr
               WHERE pr.PostId = p.PostId AND pr.ReportedByUserId = p_UserId
           );
END //

DELIMITER ;

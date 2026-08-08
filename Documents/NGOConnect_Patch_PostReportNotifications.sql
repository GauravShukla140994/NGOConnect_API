-- ============================================================
-- NGO Connect — Patch: Post Report Notifications
-- Version : Applies on top of v5.0 schema
-- Date    : 2026-08-08
-- Author  : NGO Connect Platform
-- ============================================================
-- Changes:
--   1. Post_Report  — now returns ReportCount, PostAuthorUserId, OrgId
--      so the C# DAL can fire notifications on the 1st report and
--      every 5th report thereafter (1, 5, 10, 15 …).
--      Failure paths (unknown reason code, duplicate report) still
--      return NULL for these three columns so the DAL can distinguish.
--
-- C# changes that ship with this patch:
--   • PostDal.cs — IEmailService + IConfiguration injected; ReportAsync
--     reads the three new columns, checks threshold (count==1 || count%5==0),
--     then fires:
--       – FCM + inbox notification → post author
--       – FCM + inbox notification → all org admins
--       – email (SendCampaignEmailAsync) → Email:SupportAddress from appsettings
-- ============================================================

DELIMITER //

-- ── 1. Post_Report (updated) ──────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId     INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_ReasonCode VARCHAR(50),
    IN p_Details    TEXT
)
BEGIN
    DECLARE v_ReasonLkpId   INT UNSIGNED;
    DECLARE v_StatusLkpId   INT UNSIGNED;
    DECLARE v_AlreadyExists INT DEFAULT 0;
    DECLARE v_ReportCount   INT DEFAULT 0;
    DECLARE v_AuthorUserId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgId         INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ReasonLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'REPORT_REASON' AND lv.ValueCode = p_ReasonCode LIMIT 1;

    IF v_ReasonLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown reason code: ', p_ReasonCode) AS Message,
               NULL AS ReportCount, NULL AS PostAuthorUserId, NULL AS OrgId;
    ELSE
        SELECT COUNT(*) INTO v_AlreadyExists
        FROM   PostReports
        WHERE  PostId = p_PostId AND ReportedByUserId = p_UserId;

        IF v_AlreadyExists > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message,
                   NULL AS ReportCount, NULL AS PostAuthorUserId, NULL AS OrgId;
        ELSE
            SELECT lv.LookupValueId INTO v_StatusLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
            VALUES (p_PostId, p_UserId, v_ReasonLkpId, p_Details, v_StatusLkpId);

            -- Total reports on this post (including the one just inserted)
            SELECT COUNT(*) INTO v_ReportCount FROM PostReports WHERE PostId = p_PostId;

            -- Post author + org for notification fan-out
            SELECT UserId, OrgId INTO v_AuthorUserId, v_OrgId
            FROM   Posts WHERE PostId = p_PostId LIMIT 1;

            SELECT 1               AS IsSuccess,
                   'Post reported.' AS Message,
                   v_ReportCount    AS ReportCount,
                   v_AuthorUserId   AS PostAuthorUserId,
                   v_OrgId          AS OrgId;
        END IF;
    END IF;
END //


DELIMITER ;

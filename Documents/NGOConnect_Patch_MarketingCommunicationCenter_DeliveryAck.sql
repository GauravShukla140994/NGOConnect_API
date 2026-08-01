-- ============================================================
-- NGOConnect_Patch_MarketingCommunicationCenter_DeliveryAck.sql
--
-- Marketing & Communication Center — real delivery acknowledgment +
-- per-recipient drill-down. Follow-up to
-- NGOConnect_Patch_MarketingCommunicationCenter_Phase0Phase1.sql.
--
-- WHY: "Delivered" in the dashboard/campaign list/history has only ever meant
-- "Firebase's Admin SDK accepted the send request" (QueueStatus IN ('SENT',
-- 'DELIVERED')) — CampaignDispatchService never actually set QueueStatus =
-- 'DELIVERED' anywhere, so a campaign could show "completed, delivered" while
-- the end user's device never displayed anything. This patch adds a real
-- device-side acknowledgment path and splits the honest "Sent" (accepted by
-- FCM) signal from real "Delivered" (device-confirmed) everywhere it's reported.
--
-- WORKFLOW (per this project's CLAUDE.md):
--   1. This patch has ALREADY been merged into
--      Documents/NGOConnect_Complete_Setup_v4.9.sql (source of truth).
--   2. Run THIS file against your LOCAL dev DB first.
--   3. Do not run against Railway staging/production yet — combine with any
--      other pending patches first, per this project's own patch workflow.
--
-- SAFETY: every statement here is DROP PROCEDURE IF EXISTS + CREATE PROCEDURE —
-- safe to re-run any number of times. No new tables, no ALTER TABLE.
-- ============================================================

-- ── New: real delivery acknowledgment from the mobile device ──────────────
-- Called by the app itself the moment it actually renders/displays a campaign
-- push. Ownership-checked (p_UserId must match the row's UserId) so one user
-- can never ack another user's recipient row. Always reports success
-- regardless of whether a row actually matched — best-effort beacon from an
-- untrusted client, deliberately not leaking whether a given
-- CampaignRecipientId exists or belongs to someone else. Won't downgrade a
-- terminal FAILED/SKIPPED_* row.
DROP PROCEDURE IF EXISTS CampaignRecipient_AckDelivered;

DELIMITER //
CREATE PROCEDURE CampaignRecipient_AckDelivered(
    IN p_CampaignRecipientId BIGINT UNSIGNED,
    IN p_UserId              INT UNSIGNED
)
BEGIN
    UPDATE CampaignRecipients
    SET QueueStatus = 'DELIVERED', DeliveredAt = NOW()
    WHERE CampaignRecipientId = p_CampaignRecipientId
      AND UserId = p_UserId
      AND QueueStatus IN ('SENT', 'QUEUED', 'PROCESSING');

    SELECT 1 AS IsSuccess, 'Acknowledged.' AS Message;
END //
DELIMITER ;

-- ── New: per-recipient drill-down (phone/email/name + individual status) ──
DROP PROCEDURE IF EXISTS Campaign_GetRecipientList;

DELIMITER //
CREATE PROCEDURE Campaign_GetRecipientList(
    IN p_CampaignId INT UNSIGNED,
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT cr.CampaignRecipientId, cr.UserId,
           CONCAT(up.FirstName, ' ', up.LastName) AS UserName,
           u.Email, u.Mobile,
           lv_ch.ValueCode AS ChannelCode,
           cr.QueueStatus, cr.FailReason, cr.RetryCount,
           cr.QueuedAt, cr.SentAt, cr.DeliveredAt, cr.OpenedAt, cr.ClickedAt
    FROM CampaignRecipients cr
    JOIN Users u              ON u.UserId = cr.UserId
    LEFT JOIN UserProfiles up ON up.UserId = cr.UserId
    JOIN LookupValues lv_ch   ON lv_ch.LookupValueId = cr.ChannelLkpId
    WHERE cr.CampaignId = p_CampaignId
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR cr.QueueStatus = p_StatusCode)
    ORDER BY cr.CampaignRecipientId
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM CampaignRecipients cr
    WHERE cr.CampaignId = p_CampaignId
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR cr.QueueStatus = p_StatusCode);
END //
DELIMITER ;

-- ── Modified: Campaign_GetList — split SentCount vs real DeliveredCount ────
DROP PROCEDURE IF EXISTS Campaign_GetList;

DELIMITER //
CREATE PROCEDURE Campaign_GetList(
    IN p_StatusCode VARCHAR(50),
    IN p_Search     VARCHAR(200),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT c.CampaignId, c.CampaignName, c.ScheduleType, c.ScheduledAt, c.EstimatedRecipients,
           lv_type.ValueCode   AS CampaignTypeCode, lv_type.ValueName AS CampaignTypeName,
           lv_pri.ValueCode    AS PriorityCode,
           lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
           c.CreatedAt, c.CreatedBy,
           CONCAT(up.FirstName, ' ', up.LastName) AS CreatedByName,
           (SELECT GROUP_CONCAT(lv_ch.ValueCode) FROM CampaignChannels cc
              JOIN LookupValues lv_ch ON lv_ch.LookupValueId = cc.ChannelLkpId
              WHERE cc.CampaignId = c.CampaignId) AS Channels,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId) AS TotalRecipients,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus IN ('SENT','DELIVERED')) AS SentCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus = 'DELIVERED') AS DeliveredCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.OpenedAt IS NOT NULL) AS OpenedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.ClickedAt IS NOT NULL) AS ClickedCount,
           (SELECT COUNT(*) FROM CampaignRecipients cr WHERE cr.CampaignId = c.CampaignId AND cr.QueueStatus = 'FAILED') AS FailedCount
    FROM Campaigns c
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = c.CampaignTypeLkpId
    JOIN LookupValues lv_pri    ON lv_pri.LookupValueId    = c.PriorityLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    LEFT JOIN UserProfiles up ON up.UserId = c.CreatedBy
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'))
    ORDER BY c.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Campaigns c
    JOIN LookupValues lv_status ON lv_status.LookupValueId = c.StatusLkpId
    WHERE c.IsDeleted = 0
      AND (p_StatusCode IS NULL OR p_StatusCode = '' OR lv_status.ValueCode = p_StatusCode)
      AND (p_Search IS NULL OR p_Search = '' OR c.CampaignName LIKE CONCAT('%', p_Search, '%'));
END //
DELIMITER ;

-- ── Modified: Campaign_GetHistoryDetail — same split ───────────────────────
DROP PROCEDURE IF EXISTS Campaign_GetHistoryDetail;

DELIMITER //
CREATE PROCEDURE Campaign_GetHistoryDetail(IN p_CampaignId INT UNSIGNED)
BEGIN
    SELECT
        c.CampaignId, c.CampaignName,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId) AS TotalRecipients,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus IN ('SENT','DELIVERED')) AS SentCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus = 'DELIVERED') AS DeliveredCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND OpenedAt IS NOT NULL) AS OpenedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND ClickedAt IS NOT NULL) AS ClickedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus = 'FAILED') AS FailedCount,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE CampaignId = c.CampaignId AND QueueStatus LIKE 'SKIPPED%') AS SkippedCount
    FROM Campaigns c
    WHERE c.CampaignId = p_CampaignId AND c.IsDeleted = 0;
END //
DELIMITER ;

-- ── Modified: Communication_GetDashboardStats — TotalSent vs TotalDelivered ─
DROP PROCEDURE IF EXISTS Communication_GetDashboardStats;

DELIMITER //
CREATE PROCEDURE Communication_GetDashboardStats()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'PUSH'  AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalPushSent,
        (SELECT COUNT(*) FROM CampaignRecipients cr JOIN LookupValues lv ON lv.LookupValueId = cr.ChannelLkpId WHERE lv.ValueCode = 'EMAIL' AND cr.QueueStatus IN ('SENT','DELIVERED')) AS TotalEmailSent,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus = 'FAILED') AS TotalFailed,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus IN ('SENT','DELIVERED')) AS TotalSent,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus = 'DELIVERED') AS TotalDelivered,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE QueueStatus NOT LIKE 'SKIPPED%') AS TotalAttempted,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE OpenedAt IS NOT NULL) AS TotalOpened,
        (SELECT COUNT(*) FROM CampaignRecipients WHERE ClickedAt IS NOT NULL) AS TotalClicked,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'RUNNING'   AND c.IsDeleted = 0) AS ActiveCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'SCHEDULED' AND c.IsDeleted = 0) AS ScheduledCampaigns,
        (SELECT COUNT(*) FROM Campaigns c JOIN LookupValues lv ON lv.LookupValueId = c.StatusLkpId WHERE lv.ValueCode = 'DRAFT'     AND c.IsDeleted = 0) AS DraftCampaigns;
END //
DELIMITER ;

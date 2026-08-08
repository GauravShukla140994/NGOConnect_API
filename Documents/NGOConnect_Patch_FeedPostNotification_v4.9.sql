-- ─────────────────────────────────────────────────────────────────────────────
-- NGOConnect Patch: Feed Post Notification (NEW_FEED_POST)
-- Version : v4.9
-- Date    : 2026-07-22
-- Purpose : Notify all approved org members when any member publishes a feed post.
--           Saves Notifications inbox rows + returns FCM tokens for multicast.
-- Apply to: Railway staging → Railway production
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS Post_BulkNotifyOrgMembers //
CREATE PROCEDURE Post_BulkNotifyOrgMembers(
    IN p_PostId       INT UNSIGNED,
    IN p_OrgId        INT UNSIGNED,
    IN p_AuthorUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Title VARCHAR(200);
    DECLARE v_Body  VARCHAR(104);

    -- Build title "[AuthorName] posted in [OrgName]" and body (first 100 chars of content)
    SELECT CONCAT(TRIM(CONCAT(up.FirstName, ' ', COALESCE(up.LastName, ''))),
                  ' posted in ', o.OrgName),
           CONCAT(LEFT(p.Content, 100),
                  IF(CHAR_LENGTH(p.Content) > 100, '…', ''))
    INTO   v_Title, v_Body
    FROM   Posts         p
    JOIN   Organisations o  ON o.OrgId   = p.OrgId
    JOIN   UserProfiles  up ON up.UserId = p.UserId
    WHERE  p.PostId    = p_PostId
      AND  p.OrgId     = p_OrgId
      AND  p.IsDeleted = 0
    LIMIT  1;

    -- Guard: post or org not found — return empty result set, nothing to do
    IF v_Title IS NULL THEN
        SELECT NULL AS UserId, NULL AS Token, NULL AS Platform, NULL AS Title, NULL AS Body LIMIT 0;
    ELSE
        -- Bulk-insert one Notifications inbox row per approved org member (excluding author)
        INSERT INTO Notifications (UserId, OrgId, NotifType, Title, Body, RefId, RefType, CreatedAt)
        SELECT om.UserId, p_OrgId, 'NEW_FEED_POST', v_Title, v_Body, p_PostId, 'POST', NOW()
        FROM   OrgMembers   om
        JOIN   LookupValues lv ON lv.LookupValueId = om.StatusLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  om.OrgId     = p_OrgId
          AND  lt.TypeCode  = 'MEMBER_STATUS'
          AND  lv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  om.UserId   != p_AuthorUserId;

        -- Return token rows for FCM multicast (only members with a registered device)
        SELECT om.UserId,
               dt.Token,
               dt.Platform,
               v_Title AS Title,
               v_Body  AS Body
        FROM   OrgMembers       om
        JOIN   LookupValues     lv ON lv.LookupValueId = om.StatusLkpId
        JOIN   LookupTypes      lt ON lt.LookupTypeId  = lv.LookupTypeId
        JOIN   UserDeviceTokens dt ON dt.UserId = om.UserId
        WHERE  om.OrgId     = p_OrgId
          AND  lt.TypeCode  = 'MEMBER_STATUS'
          AND  lv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  om.UserId   != p_AuthorUserId;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- NGO Connect — Patch: Notification OrgName on History List
-- Date   : 2026-07-17
--
-- PURPOSE:
--   Show which organisation triggered a notification on the
--   Notifications list screen in the mobile app.
--
-- CHANGES:
--   1. ALTER TABLE Notifications — add OrgId column
--   2. Recreate Notification_Create — new p_OrgId parameter
--   3. Recreate Notification_GetByUser — LEFT JOIN Organisations
--      returning OrgName + OrgLogoUrl
--
-- SAFE TO RUN MULTIPLE TIMES:
--   ALTER TABLE uses INFORMATION_SCHEMA guard.
--   SPs use DROP IF EXISTS + CREATE.
-- ============================================================

USE NGOConnect;

DELIMITER //

-- ── Step 1: Add OrgId column to Notifications if missing ──────
CREATE PROCEDURE _Patch_NotifAddOrgId()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   INFORMATION_SCHEMA.COLUMNS
        WHERE  TABLE_SCHEMA = DATABASE()
          AND  TABLE_NAME   = 'Notifications'
          AND  COLUMN_NAME  = 'OrgId'
    ) THEN
        ALTER TABLE Notifications
            ADD COLUMN OrgId INT UNSIGNED NULL AFTER UserId,
            ADD INDEX  idx_notif_org (OrgId);
    END IF;
END //

DELIMITER ;
CALL _Patch_NotifAddOrgId();
DROP PROCEDURE IF EXISTS _Patch_NotifAddOrgId;

-- ── Step 2: Recreate Notification_Create (new p_OrgId param) ──
DELIMITER //

DROP PROCEDURE IF EXISTS Notification_Create //
CREATE PROCEDURE Notification_Create(
    IN p_UserId    INT UNSIGNED,
    IN p_Title     VARCHAR(200),
    IN p_Body      TEXT,
    IN p_NotifType VARCHAR(50),
    IN p_RefId     INT UNSIGNED,
    IN p_RefType   VARCHAR(50),
    IN p_OrgId     INT UNSIGNED
)
BEGIN
    INSERT INTO Notifications (UserId, OrgId, Title, Body, NotifType, RefId, RefType, IsSent)
    VALUES (p_UserId, p_OrgId, p_Title, p_Body, p_NotifType, p_RefId, p_RefType, 0);

    SELECT 1 AS IsSuccess, 'Notification created.' AS Message,
           LAST_INSERT_ID() AS NotificationId;
END //

-- ── Step 3: Recreate Notification_GetByUser (returns OrgName + OrgLogoUrl) ─
DROP PROCEDURE IF EXISTS Notification_GetByUser //
CREATE PROCEDURE Notification_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_OnlyUnread TINYINT(1),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT n.NotificationId, n.Title, n.Body, n.NotifType,
           n.RefId, n.RefType, n.IsRead, n.ReadAt, n.CreatedAt,
           o.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl
    FROM   Notifications n
    LEFT JOIN Organisations o ON o.OrgId = n.OrgId AND o.IsDeleted = 0
    WHERE  n.UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR n.IsRead = 0)
    ORDER  BY n.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Notifications
    WHERE  UserId = p_UserId
      AND  (p_OnlyUnread = 0 OR IsRead = 0);
END //

DELIMITER ;

-- ── Verify ────────────────────────────────────────────────────
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Notifications' AND COLUMN_NAME = 'OrgId';
-- Expected: 1 row
--
-- SELECT PARAM_NAME FROM INFORMATION_SCHEMA.PARAMETERS
-- WHERE SPECIFIC_SCHEMA = DATABASE() AND SPECIFIC_NAME = 'Notification_Create'
-- ORDER BY ORDINAL_POSITION;
-- Expected: p_UserId, p_Title, p_Body, p_NotifType, p_RefId, p_RefType, p_OrgId

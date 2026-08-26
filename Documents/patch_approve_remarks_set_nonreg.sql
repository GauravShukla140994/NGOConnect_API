-- ============================================================
-- Patch: Approval Remarks + Set Non-Registered (any org)
-- Feature: Super Admin can add remarks on approval (stored in
--          OrgStatusHistory, pushed to org admins); and can
--          mark/unmark any org as non-registered post-approval.
-- Affected SPs: SuperAdmin_Org_Approve (modified),
--               SuperAdmin_Org_SetNonRegistered (new)
-- Author : NGO Connect
-- Date   : 2026-08-26
-- ============================================================

USE ngoconnect;
DELIMITER //

-- ── 1. Drop and recreate SuperAdmin_Org_Approve (adds p_Remarks) ─────────────

DROP PROCEDURE IF EXISTS SuperAdmin_Org_Approve //

CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 0 = registered, 1 = non-registered
    IN p_Remarks          VARCHAR(1000)  -- optional admin remarks shown to org admins
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        -- Build history reason: combine non-registered flag + optional remarks
        SET v_Reason = IF(p_IsNonRegistered = 1, 'Approved as non-registered organisation', 'Approved');
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_Reason = CONCAT(v_Reason, '. ', TRIM(p_Remarks));
        END IF;

        -- Build notification body
        SET v_NotifBody = 'Congratulations — your organisation is now live on Ripple Hub.';
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_NotifBody = CONCAT(v_NotifBody, ' Note from admin: ', TRIM(p_Remarks));
        END IF;

        UPDATE Organisations
        SET StatusLkpId     = v_ApprovedId,
            IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, v_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved', v_NotifBody, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

-- ── 2. New SP: SuperAdmin_Org_SetNonRegistered ────────────────────────────────

DROP PROCEDURE IF EXISTS SuperAdmin_Org_SetNonRegistered //

CREATE PROCEDURE SuperAdmin_Org_SetNonRegistered(
    IN p_OrgId            INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 1 = non-registered, 0 = registered
    IN p_Remarks          VARCHAR(1000), -- optional admin remarks shown to org admins
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifTitle      VARCHAR(200);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT StatusLkpId INTO v_CurrentStatusId
    FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSE
        -- Build history reason
        SET v_Reason = IF(p_IsNonRegistered = 1, 'Marked as non-registered', 'Marked as registered');
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_Reason = CONCAT(v_Reason, '. ', TRIM(p_Remarks));
        END IF;

        -- Build notification
        SET v_NotifTitle = IF(p_IsNonRegistered = 1,
            'Organisation Marked as Non-Registered',
            'Organisation Registration Status Updated');
        SET v_NotifBody = IF(p_IsNonRegistered = 1,
            'Your organisation has been classified as non-registered by the platform admin.',
            'Your organisation registration status has been updated by the platform admin.');
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_NotifBody = CONCAT(v_NotifBody, ' Note from admin: ', TRIM(p_Remarks));
        END IF;

        UPDATE Organisations
        SET IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId AND IsDeleted = 0;

        -- Record in history (status unchanged — OldId = NewId = current status)
        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_CurrentStatusId, v_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        -- Notify founder
        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        SELECT om.UserId, 'ORG_STATUS_UPDATE', v_NotifTitle, v_NotifBody, p_OrgId, 'ORGANISATION'
        FROM OrgMembers om
        JOIN LookupValues lv ON om.RoleLkpId = lv.LookupValueId
        JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
          AND lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER'
        LIMIT 1;

        SELECT 1 AS IsSuccess,
               IF(p_IsNonRegistered = 1,
                  'Organisation marked as non-registered.',
                  'Organisation marked as registered.') AS Message;
    END IF;
END //

DELIMITER ;

INSERT INTO SchemaVersions (Version, Description, AppliedAt)
VALUES ('5.1.8', 'Approval remarks + SuperAdmin_Org_SetNonRegistered SP', NOW());

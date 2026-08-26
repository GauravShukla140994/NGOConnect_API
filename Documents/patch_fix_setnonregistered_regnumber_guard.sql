-- ============================================================
-- Patch: Bug fix — SuperAdmin_Org_SetNonRegistered allowed flipping an org
-- to "Registered" (IsNonRegistered = 0) even with a blank RegNumber. Now
-- blocks the transition and returns an error message until a Registration
-- Number is set (via Edit Organisation / SuperAdmin_Org_UpdateProfile).
-- Safe to re-run.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_SetNonRegistered //
CREATE PROCEDURE SuperAdmin_Org_SetNonRegistered(
    IN p_OrgId            INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 1 = non-registered, 0 = registered
    IN p_Remarks          VARCHAR(1000), -- optional admin remarks shown to org admins
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_RegNumber       VARCHAR(100);
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifTitle      VARCHAR(200);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT StatusLkpId, RegNumber INTO v_CurrentStatusId, v_RegNumber
    FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    -- v5.2: block flipping to Registered (IsNonRegistered=0) while RegNumber is
    -- blank — previously the SP let this through since it only ever toggled the
    -- flag, never checked the field it's supposed to represent.
    ELSEIF IFNULL(p_IsNonRegistered, 0) = 0 AND (v_RegNumber IS NULL OR TRIM(v_RegNumber) = '') THEN
        SELECT 0 AS IsSuccess, 'Cannot mark as registered — a Registration Number is required first. Add it via Edit Organisation, then try again.' AS Message;
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

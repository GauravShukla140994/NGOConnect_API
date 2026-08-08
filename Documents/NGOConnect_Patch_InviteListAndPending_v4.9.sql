-- ═══════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Invite List & GetPendingForUser fixes (v4.9)
-- Date   : 2026-07-22
-- Fixes  :
--   1. Org_Invite_List — permission-denied branch now returns two empty
--      result sets instead of a single SELECT, so ExecuteDynamicPagedListAsync
--      no longer throws and the History tab renders correctly.
--   2. Org_Invite_GetPendingForUser — WHERE clause now also matches on
--      oi.InvitedUserId = p_UserId (direct FK) in addition to phone/email
--      string comparison, ensuring the banner appears for existing platform
--      users even when phone number format differs between InviteValue and
--      Users.Mobile.
-- Apply  : Run on Railway staging → verify → run on Railway production.
-- ═══════════════════════════════════════════════════════════════════════

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- Fix 1: Org_Invite_List
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_List //
CREATE PROCEDURE Org_Invite_List(
    IN p_OrgId        INT UNSIGNED,
    IN p_RequestorId  INT UNSIGNED,
    IN p_StatusCode   VARCHAR(20),    -- NULL = all
    IN p_PageNumber   INT UNSIGNED,
    IN p_PageSize     INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_RoleCode VARCHAR(50) DEFAULT NULL;
    DECLARE v_Offset   INT UNSIGNED;

    SELECT lv.ValueCode INTO v_RoleCode FROM OrgMembers om
    JOIN LookupValues lv ON lv.LookupValueId = om.RoleLkpId
    WHERE om.OrgId = p_OrgId AND om.UserId = p_RequestorId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_RoleCode IS NULL OR v_RoleCode NOT IN ('FOUNDER','ADMIN') THEN
        -- Return two empty result sets so ExecuteDynamicPagedListAsync
        -- does not throw (it expects data rows + TotalCount)
        SELECT NULL AS OrgInvitationId WHERE FALSE;
        SELECT 0 AS TotalCount;
        LEAVE main_block;
    END IF;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    -- Auto-expire any lapsed PENDING invitations for this org before listing
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.OrgId = p_OrgId AND oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv2
                            JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
                            WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode = 'PENDING');

    SELECT
        oi.OrgInvitationId,
        lv_type.ValueCode       AS InviteType,
        oi.InviteValue,
        oi.CountryCode,
        lv_status.ValueCode     AS StatusCode,
        lv_status.ValueName     AS StatusName,
        oi.SentAt,
        oi.TokenExpiry,
        oi.OpenedAt,
        oi.AcceptedAt,
        oi.CancelledAt,
        oi.DeliveryStatus,
        -- Invited user info (NULL if not on platform)
        oi.InvitedUserId,
        up_inv.FirstName        AS InviteeName,
        up_inv.LastName         AS InviteeLastName,
        up_inv.ProfilePhoto     AS InviteePhoto,
        -- Inviter info
        up_by.FirstName         AS InvitedByName,
        up_by.ProfilePhoto      AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN LookupValues lv_type   ON lv_type.LookupValueId   = oi.InviteTypeLkpId
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up_by     ON up_by.UserId = oi.InvitedByUserId
    LEFT JOIN UserProfiles up_inv ON up_inv.UserId = oi.InvitedUserId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode)
    ORDER BY oi.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    -- TotalCount
    SELECT COUNT(*) AS TotalCount
    FROM OrgInvitations oi
    JOIN LookupValues lv_status ON lv_status.LookupValueId = oi.StatusLkpId
    WHERE oi.OrgId = p_OrgId
      AND oi.IsDeleted = 0
      AND (p_StatusCode IS NULL OR lv_status.ValueCode = p_StatusCode);
END //

-- ─────────────────────────────────────────────────────────────
-- Fix 2: Org_Invite_GetPendingForUser
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Invite_GetPendingForUser //
CREATE PROCEDURE Org_Invite_GetPendingForUser(
    IN p_UserId  INT UNSIGNED
)
main_block: BEGIN
    DECLARE v_Mobile VARCHAR(20)  DEFAULT NULL;
    DECLARE v_Email  VARCHAR(150) DEFAULT NULL;

    SELECT Mobile, Email INTO v_Mobile, v_Email
    FROM Users WHERE UserId = p_UserId AND IsDeleted = 0 LIMIT 1;

    -- Auto-expire lapsed tokens first
    UPDATE OrgInvitations oi
    SET oi.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                          JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
                          WHERE lt.TypeCode = 'INVITE_STATUS' AND lv.ValueCode = 'EXPIRED')
    WHERE oi.TokenExpiry < NOW() AND oi.IsDeleted = 0
      AND (
          oi.InvitedUserId = p_UserId
          OR oi.InviteValue = v_Mobile
          OR oi.InviteValue = LOWER(IFNULL(v_Email,''))
      )
      AND oi.StatusLkpId IN (
          SELECT LookupValueId FROM LookupValues lv2
          JOIN LookupTypes lt2 ON lt2.LookupTypeId = lv2.LookupTypeId
          WHERE lt2.TypeCode = 'INVITE_STATUS' AND lv2.ValueCode IN ('PENDING','OPENED')
      );

    SELECT
        oi.OrgInvitationId,
        oi.OrgId,
        o.OrgName,
        o.LogoUrl               AS OrgLogo,
        o.City                  AS OrgCity,
        oi.InviteToken,
        lv_status.ValueCode     AS StatusCode,
        oi.TokenExpiry,
        CONCAT(up.FirstName, ' ', up.LastName) AS InvitedByName,
        up.ProfilePhoto         AS InvitedByPhoto
    FROM OrgInvitations oi
    JOIN Organisations o         ON o.OrgId = oi.OrgId
    JOIN LookupValues lv_status  ON lv_status.LookupValueId = oi.StatusLkpId
    JOIN UserProfiles up         ON up.UserId = oi.InvitedByUserId
    WHERE oi.IsDeleted = 0
      AND lv_status.ValueCode IN ('PENDING','OPENED')
      AND oi.TokenExpiry > NOW()
      AND (
          oi.InvitedUserId = p_UserId                          -- direct match for existing users
          OR oi.InviteValue = v_Mobile                         -- phone match
          OR oi.InviteValue = LOWER(IFNULL(v_Email,''))        -- email match
      )
    ORDER BY oi.CreatedAt DESC
    LIMIT 5;
END //

DELIMITER ;

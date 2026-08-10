-- ============================================================
-- Patch: SOS Alert Fan-out — respect EmergVisibility preference
-- Adds: Notification_GetSosMemberTokens SP
-- Affected C#: INotificationDal, NotificationDal, SosDal
-- Apply to: local → Railway staging → Railway production
-- ============================================================

DROP PROCEDURE IF EXISTS Notification_GetSosMemberTokens;

DELIMITER $$

-- SOS-specific recipient lookup: respects victim's EmergVisibilityLkpId
-- ADMIN_ONLY  → FOUNDER + ADMIN roles only
-- ADMIN_MODS  → FOUNDER + ADMIN + MODERATOR roles
-- ALL_MEMBERS → all approved members  (default if no preference saved)
CREATE PROCEDURE Notification_GetSosMemberTokens(
    IN p_OrgId        INT UNSIGNED,
    IN p_VictimUserId INT UNSIGNED
)
BEGIN
    DECLARE v_VisCode VARCHAR(50) DEFAULT 'ALL_MEMBERS';

    SELECT lv.ValueCode INTO v_VisCode
    FROM   UserSafetyPreferences sp
    JOIN   LookupValues lv ON lv.LookupValueId = sp.EmergVisibilityLkpId
    WHERE  sp.UserId = p_VictimUserId LIMIT 1;

    IF v_VisCode IS NULL THEN SET v_VisCode = 'ALL_MEMBERS'; END IF;

    IF v_VisCode = 'ALL_MEMBERS' THEN
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    ELSEIF v_VisCode = 'ADMIN_MODS' THEN
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
        INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN','MODERATOR')
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    ELSE -- ADMIN_ONLY
        SELECT DISTINCT dt.UserId, dt.Token
        FROM   UserDeviceTokens dt
        INNER JOIN OrgMembers   om  ON om.UserId = dt.UserId AND om.OrgId = p_OrgId
        INNER JOIN LookupValues slv ON slv.LookupValueId = om.StatusLkpId
        INNER JOIN LookupTypes  slt ON slt.LookupTypeId  = slv.LookupTypeId
        INNER JOIN LookupValues rlv ON rlv.LookupValueId = om.RoleLkpId
        INNER JOIN LookupTypes  rlt ON rlt.LookupTypeId  = rlv.LookupTypeId
        WHERE  slt.TypeCode = 'MEMBER_STATUS' AND slv.ValueCode = 'APPROVED'
          AND  rlt.TypeCode = 'MEMBER_ROLE'   AND rlv.ValueCode IN ('FOUNDER','ADMIN')
          AND  om.IsDeleted = 0
          AND  dt.Token IS NOT NULL AND dt.Token != ''
          AND  dt.UserId != p_VictimUserId;
    END IF;
END$$

DELIMITER ;

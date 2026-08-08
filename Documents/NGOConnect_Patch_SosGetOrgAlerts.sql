-- =============================================================================
-- NGOConnect_Patch_SosGetOrgAlerts.sql
--
-- Purpose: New SP that returns ALL SOS incidents for an org — both active and
--          historical (resolved / cancelled) — ordered by CreatedAt DESC.
--
--          Used by the Community page to show SOS history below the active alert
--          pinned section. Active incidents show "I Can Assist" button; resolved
--          and cancelled incidents show status badge + "View Details" only.
--
-- SP name    : Sos_GetOrgAlerts
-- Parameters : p_OrgId INT UNSIGNED — the organisation to query
--              p_Limit INT UNSIGNED — max rows to return (default usage: 20)
--
-- Returns    : Flat SELECT — one row per incident (NO responder result set)
--              Columns match Sos_GetActive for easy frontend reuse.
--
-- Safe to re-run: DROP PROCEDURE IF EXISTS before CREATE.
-- =============================================================================

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_GetOrgAlerts //
CREATE PROCEDURE Sos_GetOrgAlerts(
    IN p_OrgId INT UNSIGNED,
    IN p_Limit INT UNSIGNED
)
BEGIN
    -- Resolve the 'ACTIVE' status LookupValueId so frontend can distinguish
    DECLARE v_ActiveLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE'
    LIMIT  1;

    -- All incidents for this org, newest first
    SELECT
        si.SosIncidentId,
        si.OrgId,
        si.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS UserName,
        up.ProfilePhoto,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName,
        -- Convenience flag: 1 = ACTIVE, 0 = resolved/cancelled
        CASE WHEN si.StatusLkpId = v_ActiveLkpId THEN 1 ELSE 0 END AS IsActive,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CancelReason,
        si.ResolvedAt,
        si.CreatedAt
    FROM   SosIncidents si
    LEFT   JOIN UserProfiles up  ON si.UserId         = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT   JOIN LookupValues sv  ON si.StatusLkpId    = sv.LookupValueId
    WHERE  si.OrgId     = p_OrgId
      AND  si.IsDeleted = 0
    ORDER  BY si.CreatedAt DESC
    LIMIT  p_Limit;
END //

DELIMITER ;

-- Sanity check: how many SOS incidents exist for each org?
SELECT
    o.OrgName,
    COUNT(*)                                    AS TotalIncidents,
    SUM(CASE WHEN sv.ValueCode = 'ACTIVE'    THEN 1 ELSE 0 END) AS Active,
    SUM(CASE WHEN sv.ValueCode = 'RESOLVED'  THEN 1 ELSE 0 END) AS Resolved,
    SUM(CASE WHEN sv.ValueCode = 'CANCELLED' THEN 1 ELSE 0 END) AS Cancelled
FROM SosIncidents si
LEFT JOIN Organisations o  ON si.OrgId       = o.OrgId
LEFT JOIN LookupValues  sv ON si.StatusLkpId = sv.LookupValueId
WHERE si.IsDeleted = 0
GROUP BY si.OrgId, o.OrgName;

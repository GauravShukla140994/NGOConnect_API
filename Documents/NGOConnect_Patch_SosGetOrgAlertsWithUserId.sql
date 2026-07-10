-- =============================================================================
-- NGOConnect_Patch_SosGetOrgAlertsWithUserId.sql
--
-- Purpose : Replaces Sos_GetOrgAlerts with an upgraded version that accepts
--           p_UserId and returns MyApprovalStatus per incident.
--
--           MyApprovalStatus = ValueCode from LookupValues (SOS_RESPONDER_STATUS):
--             NULL     — current user has not responded to this incident
--             PENDING  — user clicked "I Can Assist", awaiting victim approval
--             APPROVED — victim approved; "View Map" button shown
--             REJECTED — victim declined; button hidden/muted
--
-- SP name    : Sos_GetOrgAlerts
-- Parameters : p_OrgId  INT UNSIGNED — the organisation to query
--              p_UserId INT UNSIGNED — current viewer (for per-incident status)
--              p_Limit  INT UNSIGNED — max rows (default usage: 20–30)
--
-- Returns    : One row per incident with MyApprovalStatus column appended.
--
-- Safe to re-run: DROP PROCEDURE IF EXISTS before CREATE.
-- =============================================================================

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_GetOrgAlerts //
CREATE PROCEDURE Sos_GetOrgAlerts(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED,
    IN p_Limit  INT UNSIGNED
)
BEGIN
    -- Resolve the 'ACTIVE' status LookupValueId so frontend can distinguish
    DECLARE v_ActiveLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE'
    LIMIT  1;

    -- All incidents for this org, newest first, with per-user responder status
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
        si.CreatedAt,
        -- Current viewer's responder status for this incident
        -- NULL  → not responded yet (show "I Can Assist")
        -- PENDING  → responded, awaiting victim approval
        -- APPROVED → victim approved (show "View Map")
        -- REJECTED → victim declined (show muted Declined)
        arv.ValueCode  AS MyApprovalStatus
    FROM   SosIncidents si
    LEFT   JOIN UserProfiles up  ON si.UserId         = up.UserId AND up.IsDeleted = 0
    LEFT   JOIN LookupValues atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT   JOIN LookupValues sv  ON si.StatusLkpId    = sv.LookupValueId
    -- Current user's own responder row (if any) — use most recent if multiple rows exist
    LEFT   JOIN SosResponders sr ON sr.SosIncidentId  = si.SosIncidentId
                                 AND sr.UserId         = p_UserId
    LEFT   JOIN LookupValues arv ON sr.ApprovalStatusLkpId = arv.LookupValueId
    WHERE  si.OrgId     = p_OrgId
      AND  si.IsDeleted = 0
    ORDER  BY si.CreatedAt DESC
    LIMIT  p_Limit;
END //

DELIMITER ;

-- Sanity check: how many SOS incidents exist per org?
SELECT
    o.OrgName,
    COUNT(*)                                                  AS TotalIncidents,
    SUM(CASE WHEN sv.ValueCode = 'ACTIVE'    THEN 1 ELSE 0 END) AS Active,
    SUM(CASE WHEN sv.ValueCode = 'RESOLVED'  THEN 1 ELSE 0 END) AS Resolved,
    SUM(CASE WHEN sv.ValueCode = 'CANCELLED' THEN 1 ELSE 0 END) AS Cancelled
FROM SosIncidents si
LEFT JOIN Organisations o  ON si.OrgId       = o.OrgId
LEFT JOIN LookupValues  sv ON si.StatusLkpId = sv.LookupValueId
WHERE si.IsDeleted = 0
GROUP BY si.OrgId, o.OrgName;

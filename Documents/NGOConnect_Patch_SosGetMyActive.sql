-- =============================================================================
-- Patch: Add Sos_GetMyActive stored procedure
--
-- Purpose: Returns the current user's own active SOS incident + responders.
--          Used by the s-sos-active screen (victim view) via GET /api/v1/sos/my-active
--
-- Returns 2 result sets:
--   #1: Incident details (1 row, or 0 if no active SOS)
--   #2: Responders list (0-N rows)
--
-- Safe to re-run: uses DROP PROCEDURE IF EXISTS
-- =============================================================================

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_GetMyActive //
CREATE PROCEDURE Sos_GetMyActive(
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_ActiveLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve the 'ACTIVE' status LookupValueId
    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'SOS_STATUS' AND lv.ValueCode = 'ACTIVE'
    LIMIT  1;

    -- Result set 1: victim's own active incident
    SELECT
        si.SosIncidentId,
        si.OrgId,
        o.OrgName,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CreatedAt,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName
    FROM  SosIncidents si
    LEFT  JOIN Organisations o    ON si.OrgId          = o.OrgId
    LEFT  JOIN LookupValues  atv  ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT  JOIN LookupValues  sv   ON si.StatusLkpId    = sv.LookupValueId
    WHERE si.UserId    = p_UserId
      AND si.StatusLkpId = v_ActiveLkpId
      AND si.IsDeleted = 0
    ORDER BY si.CreatedAt DESC
    LIMIT 1;

    -- Result set 2: responders for that incident
    SELECT
        sr.SosResponderId,
        sr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS ResponderName,
        up.ProfilePhoto,
        rv.ValueCode  AS ApprovalStatus,
        rv.ValueName  AS ApprovalStatusName,
        sr.RespondedAt,
        sr.CanViewLocation
    FROM  SosResponders sr
    JOIN  SosIncidents  si2  ON sr.SosIncidentId = si2.SosIncidentId
    JOIN  UserProfiles  up   ON sr.UserId        = up.UserId AND up.IsDeleted = 0
    LEFT  JOIN LookupValues rv ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE si2.UserId       = p_UserId
      AND si2.StatusLkpId  = v_ActiveLkpId
      AND si2.IsDeleted    = 0;
END //

DELIMITER ;

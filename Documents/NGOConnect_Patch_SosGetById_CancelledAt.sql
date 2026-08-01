-- ── Patch: Sos_GetById — add CancelledAt to result set ──────────────────────
-- Problem : CancelledAt column exists on SosIncidents but was not returned by
--           Sos_GetById. The client needs it to freeze the SOS timer at the
--           correct time when status = CANCELLED.
-- Fix     : Add si.CancelledAt to the SELECT in both result sets of Sos_GetById.
-- Apply to: Railway staging → Railway production
-- Date    : 2026-08-01
-- ──────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS Sos_GetById //
CREATE PROCEDURE Sos_GetById(
    IN p_SosIncidentId INT UNSIGNED,
    IN p_UserId        INT UNSIGNED
)
BEGIN
    -- Result set 1: incident details
    SELECT
        si.SosIncidentId,
        si.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS UserName,
        up.ProfilePhoto,
        atv.ValueCode  AS AlertType,
        atv.ValueName  AS AlertTypeName,
        sv.ValueCode   AS Status,
        sv.ValueName   AS StatusName,
        si.Description,
        si.ApproxLocation,
        si.Latitude,
        si.Longitude,
        si.CancelReason,
        si.ResolvedAt,
        si.CancelledAt,
        si.CreatedAt,
        si.OrgId,
        o.OrgName
    FROM  SosIncidents si
    LEFT  JOIN UserProfiles  up  ON si.UserId         = up.UserId AND up.IsDeleted = 0
    LEFT  JOIN Organisations o   ON si.OrgId          = o.OrgId
    LEFT  JOIN LookupValues  atv ON si.AlertTypeLkpId = atv.LookupValueId
    LEFT  JOIN LookupValues  sv  ON si.StatusLkpId    = sv.LookupValueId
    WHERE  si.SosIncidentId = p_SosIncidentId
      AND  si.IsDeleted     = 0;

    -- Result set 2: responders
    SELECT
        sr.SosResponderId,
        sr.UserId,
        CONCAT(COALESCE(up2.FirstName,''), ' ', COALESCE(up2.LastName,'')) AS ResponderName,
        up2.ProfilePhoto,
        rv.ValueCode   AS ApprovalStatus,
        rv.ValueName   AS ApprovalStatusName,
        sr.RespondedAt,
        sr.CanViewLocation
    FROM  SosResponders  sr
    LEFT  JOIN UserProfiles  up2 ON sr.UserId              = up2.UserId AND up2.IsDeleted = 0
    LEFT  JOIN LookupValues  rv  ON sr.ApprovalStatusLkpId = rv.LookupValueId
    WHERE  sr.SosIncidentId = p_SosIncidentId
    ORDER  BY sr.RespondedAt ASC;
END //

DELIMITER ;

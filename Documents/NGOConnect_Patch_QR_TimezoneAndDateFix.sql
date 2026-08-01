-- ============================================================
-- NGOConnect Patch: QR Timezone Fix + Project_GetById DATE_FORMAT
-- Date:    2026-07-29
-- Problems fixed:
--   1. Project_GetSessionQr: Railway MySQL server runs UTC, but session
--      times are stored in IST (as entered by admin). The previous patch
--      compared NOW() (UTC) against IST-stored DATETIME values, causing
--      QR generation to be rejected during active IST sessions.
--      Fix: use CONVERT_TZ(NOW(), '+00:00', '+05:30') for window checks.
--      QrExpiresAt is kept UTC (DATE_ADD(NOW(),...)) — Project_CheckIn
--      also uses NOW() for that check, so both sides are UTC = consistent.
--   2. Project_GetById: DATE/DATETIME columns (OneTimeDate, RecurStart,
--      RecurEnd, FlexFromDate, FlexToDate) returned as raw MySQL DATE.
--      Pomelo/C# serialises DATE as DateTime, producing "T00:00:00" suffix
--      in JSON. Fix: DATE_FORMAT wraps them in '%Y-%m-%d' so the C# value
--      is a plain string, not DateTime.
--
-- Apply to: Railway Staging, then Railway Production
-- SAFE to re-apply (DROP + CREATE pattern)
-- ============================================================

DELIMITER //

-- ─── 1. Project_GetSessionQr — UTC → IST timezone fix ─────────────────────

DROP PROCEDURE IF EXISTS Project_GetSessionQr //

CREATE PROCEDURE Project_GetSessionQr(
    IN p_SessionId INT UNSIGNED,
    IN p_UserId    INT UNSIGNED
)
BEGIN
    DECLARE v_QrCode      VARCHAR(100);
    DECLARE v_ProjectId   INT UNSIGNED;
    DECLARE v_SessionDate DATE;
    DECLARE v_StartTime   TIME;
    DECLARE v_EndTime     TIME;
    DECLARE v_Expiry      INT DEFAULT 60;
    DECLARE v_Buffer      INT DEFAULT 15;
    DECLARE v_WindowStart DATETIME;
    DECLARE v_WindowEnd   DATETIME;
    DECLARE v_NowIST      DATETIME;   -- Railway server is UTC; session times are IST
    DECLARE v_RowsHit     INT DEFAULT 0;

    SELECT ProjectId, SessionDate, StartTime, EndTime
    INTO   v_ProjectId, v_SessionDate, v_StartTime, v_EndTime
    FROM   ProjectSessions WHERE SessionId = p_SessionId AND IsDeleted = 0 LIMIT 1;

    IF v_SessionDate IS NULL THEN
        SELECT 0 AS IsSuccess, 'Session not found or already deleted.' AS Message, NULL AS QrToken;
    ELSE
        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Expiry
        FROM Settings WHERE SettingKey = 'QR_EXPIRY_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Expiry IS NULL OR v_Expiry = 0 THEN SET v_Expiry = 60; END IF;

        SELECT CAST(SettingValue AS UNSIGNED) INTO v_Buffer
        FROM Settings WHERE SettingKey = 'QR_BUFFER_MINUTES' AND IsDeleted = 0 LIMIT 1;
        IF v_Buffer IS NULL THEN SET v_Buffer = 15; END IF;

        -- Session times are stored in IST (as entered by admin).
        -- Railway MySQL server runs UTC. Convert NOW() to IST for apples-to-apples comparison.
        -- QrExpiresAt is intentionally kept as UTC (DATE_ADD(NOW(),...)) because
        -- Project_CheckIn validates it with NOW() — both UTC, internally consistent.
        SET v_NowIST      = CONVERT_TZ(NOW(), '+00:00', '+05:30');
        SET v_WindowStart = DATE_SUB(TIMESTAMP(v_SessionDate, v_StartTime), INTERVAL v_Buffer MINUTE);
        SET v_WindowEnd   = TIMESTAMP(v_SessionDate, v_EndTime);

        IF v_NowIST < v_WindowStart THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('QR not yet available. Session starts at ', TIME_FORMAT(v_StartTime, '%h:%i %p'),
                          '. QR opens ', v_Buffer, ' min before start.') AS Message,
                   NULL AS QrToken;
        ELSEIF v_NowIST > v_WindowEnd THEN
            SELECT 0 AS IsSuccess,
                   CONCAT('Session ended at ', TIME_FORMAT(v_EndTime, '%h:%i %p'), '. QR is no longer active.') AS Message,
                   NULL AS QrToken;
        ELSE
            SET v_QrCode = REPLACE(UUID(), '-', '');

            UPDATE ProjectSessions
            SET    QrCode = v_QrCode, QrExpiresAt = DATE_ADD(NOW(), INTERVAL v_Expiry MINUTE),
                   UpdatedBy = p_UserId, UpdatedAt = NOW()
            WHERE  SessionId = p_SessionId AND IsDeleted = 0;

            SET v_RowsHit = ROW_COUNT();

            IF v_RowsHit = 0 THEN
                SELECT 0 AS IsSuccess, 'Failed to stamp QR on session.' AS Message, NULL AS QrToken;
            ELSE
                SELECT 1 AS IsSuccess, 'QR generated.' AS Message, v_QrCode AS QrToken;
            END IF;
        END IF;
    END IF;
END //

-- ─── 2. Project_GetById — DATE_FORMAT for date columns ────────────────────

DROP PROCEDURE IF EXISTS Project_GetById //

CREATE PROCEDURE Project_GetById(IN p_ProjectId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        p.ProjectId, p.OrgId, o.OrgName, o.LogoUrl AS OrgLogo,
        p.ProjectName, p.Category, p.Description,
        ptv.ValueCode AS ProjectTypeCode, ptv.ValueName AS ProjectType,
        stv.ValueCode AS ScheduleTypeCode, stv.ValueName AS ScheduleType,
        DATE_FORMAT(p.RecurStart,    '%Y-%m-%d') AS RecurStart,
        DATE_FORMAT(p.RecurEnd,      '%Y-%m-%d') AS RecurEnd,
        p.RecurDays,
        p.SessionStartTime, p.SessionEndTime,
        DATE_FORMAT(p.OneTimeDate,   '%Y-%m-%d') AS OneTimeDate,
        DATE_FORMAT(p.FlexFromDate,  '%Y-%m-%d') AS FlexFromDate,
        DATE_FORMAT(p.FlexToDate,    '%Y-%m-%d') AS FlexToDate,
        p.MinHoursRequired,
        ltv.ValueCode AS LocationTypeCode, ltv.ValueName AS LocationType,
        p.AddressLine, p.Landmark, p.City, p.State,
        p.Latitude, p.Longitude, p.GoogleMapsUrl,
        p.MaxVolunteers, p.IsPublic,
        p.AgeRestriction, p.IdVerRequired, p.MinReliability,
        jtv.ValueCode AS JoinTypeCode, jtv.ValueName AS JoinType,
        sv.ValueCode AS StatusCode, sv.ValueName AS Status,
        p.ImpactSummary, p.BeneficiaryCount,
        p.CompletedAt, p.CreatedAt,
        (SELECT COUNT(*) FROM ProjectApplications WHERE ProjectId = p.ProjectId
            AND StatusLkpId = (SELECT LookupValueId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId=lt.LookupTypeId WHERE lt.TypeCode='APPLICATION_STATUS' AND lv.ValueCode='APPROVED')
            AND IsDeleted = 0) AS ApprovedCount,
        (SELECT lv2.ValueCode FROM ProjectApplications pa2
            JOIN LookupValues lv2 ON pa2.StatusLkpId = lv2.LookupValueId
            WHERE pa2.ProjectId = p.ProjectId AND pa2.UserId = p_UserId AND pa2.IsDeleted = 0
            LIMIT 1) AS ApplicationStatusCode
    FROM Projects p
    JOIN Organisations o ON p.OrgId = o.OrgId
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues stv ON p.ScheduleTypeLkpId = stv.LookupValueId
    LEFT JOIN LookupValues ltv ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues jtv ON p.JoinTypeLkpId     = jtv.LookupValueId
    LEFT JOIN LookupValues sv  ON p.StatusLkpId       = sv.LookupValueId
    WHERE p.ProjectId = p_ProjectId AND p.IsDeleted = 0;
END //

DELIMITER ;

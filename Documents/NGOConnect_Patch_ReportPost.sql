-- ============================================================
-- NGO Connect — Patch: Post_Report (accept ReasonCode string)
-- Version : v4.3 patch
-- Date    : 2026-07-08
-- Problem : Old SP took p_ReasonLkpId (INT) — required frontend
--           to call lookup API to get the ID, which was fragile.
-- Fix     : SP now takes p_ReasonCode (VARCHAR) and resolves the
--           LookupValueId internally — same pattern as all other SPs.
-- Apply   : Run against NGOConnect database.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Post_Report //
CREATE PROCEDURE Post_Report(
    IN p_PostId      INT UNSIGNED,
    IN p_UserId      INT UNSIGNED,
    IN p_ReasonCode  VARCHAR(50),   -- e.g. SPAM, HATE, INAPPROPRIATE, SCAM, OTHER
    IN p_Details     TEXT
)
BEGIN
    DECLARE v_Exists          INT DEFAULT 0;
    DECLARE v_ReasonLkpId     INT UNSIGNED DEFAULT 0;
    DECLARE v_PendingStatusId INT UNSIGNED DEFAULT 0;

    -- Resolve reason code → LookupValueId
    SELECT lv.LookupValueId INTO v_ReasonLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'REPORT_REASON' AND lv.ValueCode = p_ReasonCode
    LIMIT  1;

    IF v_ReasonLkpId = 0 THEN
        SELECT 0 AS IsSuccess, 'Invalid report reason.' AS Message;
    ELSE
        -- Prevent duplicate reports from same user on same post
        SELECT COUNT(*) INTO v_Exists
        FROM   PostReports
        WHERE  PostId = p_PostId AND ReportedByUserId = p_UserId;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reported this post.' AS Message;
        ELSE
            -- Resolve PENDING status for PostReports
            SELECT lv.LookupValueId INTO v_PendingStatusId
            FROM   LookupValues lv
            JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'REPORT_STATUS' AND lv.ValueCode = 'PENDING'
            LIMIT  1;

            -- Fallback if REPORT_STATUS lookup not seeded
            IF v_PendingStatusId = 0 THEN
                SELECT lv.LookupValueId INTO v_PendingStatusId
                FROM   LookupValues lv
                JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE  lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING'
                LIMIT  1;
            END IF;

            INSERT INTO PostReports (PostId, ReportedByUserId, ReasonLkpId, Details, StatusLkpId)
            VALUES (p_PostId, p_UserId, v_ReasonLkpId, p_Details, v_PendingStatusId);

            SELECT 1 AS IsSuccess, 'Post reported. Our team will review it.' AS Message;
        END IF;
    END IF;
END //

DELIMITER ;

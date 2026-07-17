-- ============================================================
-- NGOConnect Patch: FCM Notification SP Outputs
-- Version:   v4.8
-- Created:   2026-07-17
-- Purpose:   Update 6 SPs to return extra columns needed for
--            fire-and-forget FCM push notifications in DAL layer.
--            No table structure changes — SP logic only.
-- ============================================================
--
-- SPs updated:
--   1. Org_UpdateMemberRole    → returns UserId
--   2. Attendance_ExcuseNoShow → returns UserId, ProjectId
--   3. Project_CheckIn         → returns ProjectId
--   4. Project_ManualAttendance→ returns UserId, ProjectId
--   5. Withdrawal_AdminReview  → returns OrgId
--   6. Sos_Respond             → returns VictimUserId
-- ============================================================

DELIMITER //

-- ── 1. Org_UpdateMemberRole ────────────────────────────────
DROP PROCEDURE IF EXISTS Org_UpdateMemberRole //
CREATE PROCEDURE Org_UpdateMemberRole(
    IN p_OrgId     INT,
    IN p_MemberId  INT,
    IN p_RoleCode  VARCHAR(50),
    IN p_UpdatedBy INT
)
BEGIN
    DECLARE v_RoleLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_RoleLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = p_RoleCode
    LIMIT  1;

    IF v_RoleLkpId = 0 THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown role: ', p_RoleCode) AS Message;
    ELSE
        UPDATE OrgMembers
        SET RoleLkpId = v_RoleLkpId,
            UpdatedAt = NOW(),
            UpdatedBy = p_UpdatedBy
        WHERE OrgMemberId = p_MemberId
          AND OrgId       = p_OrgId
          AND IsDeleted   = 0;

        IF ROW_COUNT() = 0 THEN
            SELECT 0 AS IsSuccess, 'Member not found or already deleted.' AS Message, NULL AS UserId;
        ELSE
            SELECT 1 AS IsSuccess, 'Member role updated.' AS Message,
                   (SELECT UserId FROM OrgMembers WHERE OrgMemberId = p_MemberId LIMIT 1) AS UserId;
        END IF;
    END IF;
END //

-- ── 2. Attendance_ExcuseNoShow ────────────────────────────
DROP PROCEDURE IF EXISTS Attendance_ExcuseNoShow //
CREATE PROCEDURE Attendance_ExcuseNoShow(
    IN p_AttendanceId INT,
    IN p_OrgId        INT,
    IN p_ExcusedBy    INT
)
BEGIN
    DECLARE v_UserId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectId INT UNSIGNED DEFAULT NULL;

    SELECT pa.UserId, ps.ProjectId
    INTO   v_UserId, v_ProjectId
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions ps ON pa.SessionId = ps.SessionId
    WHERE  pa.AttendanceId = p_AttendanceId
    LIMIT  1;

    UPDATE ProjectAttendance pa
    JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
    JOIN Projects p         ON ps.ProjectId = p.ProjectId
    SET pa.AttendanceStatus = 'EXCUSED',
        pa.UpdatedAt        = NOW()
    WHERE pa.AttendanceId = p_AttendanceId
      AND pa.AttendanceStatus = 'NO_SHOW'
      AND p.OrgId = p_OrgId;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or not a no-show in this org.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show excused. Reliability score will adjust.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //

-- ── 3. Project_CheckIn ────────────────────────────────────
DROP PROCEDURE IF EXISTS Project_CheckIn //
CREATE PROCEDURE Project_CheckIn(IN p_QrCode VARCHAR(100), IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_SessionId INT UNSIGNED;
    DECLARE v_StatusLkpId INT UNSIGNED;

    SELECT SessionId INTO v_SessionId FROM ProjectSessions
    WHERE QrCode = p_QrCode AND QrExpiresAt > NOW() AND IsDeleted = 0 LIMIT 1;

    IF v_SessionId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Invalid or expired QR code.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

        INSERT INTO ProjectAttendance (SessionId, UserId, CheckInTime, AttendStatusLkpId, CreatedBy)
        VALUES (v_SessionId, p_UserId, NOW(), v_StatusLkpId, p_UserId)
        ON DUPLICATE KEY UPDATE CheckInTime = NOW(), AttendStatusLkpId = v_StatusLkpId;
        SELECT 1 AS IsSuccess, 'Check-in successful.' AS Message, v_SessionId AS SessionId,
               (SELECT ProjectId FROM ProjectSessions WHERE SessionId = v_SessionId LIMIT 1) AS ProjectId;
    END IF;
END //

-- ── 4. Project_ManualAttendance ───────────────────────────
DROP PROCEDURE IF EXISTS Project_ManualAttendance //
CREATE PROCEDURE Project_ManualAttendance(
    IN p_ApplicationId INT UNSIGNED,
    IN p_MarkedBy      INT UNSIGNED
)
BEGIN
    DECLARE v_UserId        INT UNSIGNED;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_CurrentStatus VARCHAR(50);
    DECLARE v_SessionId     INT UNSIGNED;
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_HoursLogged   DECIMAL(4,2);

    SELECT pa.UserId, pa.ProjectId, sv.ValueCode
    INTO   v_UserId, v_ProjectId, v_CurrentStatus
    FROM   ProjectApplications pa
    JOIN   LookupValues sv ON pa.StatusLkpId = sv.LookupValueId
    WHERE  pa.ApplicationId = p_ApplicationId AND pa.IsDeleted = 0 LIMIT 1;

    IF v_UserId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Application not found.' AS Message;
    ELSEIF v_CurrentStatus NOT IN ('APPROVED', 'NO_SHOW') THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Cannot mark as attended: current status is ', v_CurrentStatus, '.') AS Message;
    ELSE
        SELECT ps.SessionId,
               ROUND(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime) / 60.0, 2)
        INTO   v_SessionId, v_HoursLogged
        FROM   ProjectSessions ps
        WHERE  ps.ProjectId = v_ProjectId AND ps.SessionDate <= CURDATE() AND ps.IsDeleted = 0
        ORDER BY ps.SessionDate DESC LIMIT 1;

        IF v_SessionId IS NULL THEN
            SELECT 0 AS IsSuccess, 'No past session found for this project.' AS Message;
        ELSE
            SELECT lv.LookupValueId INTO v_AttendedLkpId
            FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE  lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

            INSERT INTO ProjectAttendance
                (SessionId, UserId, CheckInTime, HoursLogged, QrScannedAt,
                 AttendStatusLkpId, AdminNote, CreatedBy)
            VALUES
                (v_SessionId, v_UserId, NOW(), v_HoursLogged, NULL,
                 v_AttendedLkpId, 'Manually marked as attended by admin.', p_MarkedBy)
            ON DUPLICATE KEY UPDATE
                AttendStatusLkpId = v_AttendedLkpId,
                CheckInTime       = NOW(),
                HoursLogged       = v_HoursLogged,
                QrScannedAt       = NULL,
                AdminNote         = 'Manually marked as attended by admin.',
                UpdatedBy         = p_MarkedBy,
                UpdatedAt         = NOW();

            SELECT 1 AS IsSuccess, 'Volunteer marked as attended.' AS Message,
                   v_UserId AS UserId, v_ProjectId AS ProjectId;
        END IF;
    END IF;
END //

-- ── 5. Withdrawal_AdminReview ─────────────────────────────
DROP PROCEDURE IF EXISTS Withdrawal_AdminReview //
CREATE PROCEDURE Withdrawal_AdminReview(IN p_WithdrawalRequestId INT UNSIGNED, IN p_StatusCode VARCHAR(50), IN p_AdminNotes TEXT, IN p_ReviewedBy INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;
    DECLARE v_Amount       DECIMAL(15,2);
    DECLARE v_CampaignId   INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'WITHDRAWAL_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;

    SELECT Amount, CampaignId, OrgId INTO v_Amount, v_CampaignId, v_OrgId
    FROM WithdrawalRequests WHERE WithdrawalRequestId = p_WithdrawalRequestId LIMIT 1;

    UPDATE WithdrawalRequests SET StatusLkpId = v_StatusLkpId, AdminNotes = p_AdminNotes,
        ReviewedBy = p_ReviewedBy, ProcessedAt = NOW()
    WHERE WithdrawalRequestId = p_WithdrawalRequestId;

    -- Deduct from campaign raised amount only if approved
    IF p_StatusCode = 'APPROVED' THEN
        UPDATE DonationCampaigns SET RaisedAmount = RaisedAmount - v_Amount WHERE CampaignId = v_CampaignId;
    END IF;

    SELECT 1 AS IsSuccess, CONCAT('Withdrawal ', p_StatusCode, '.') AS Message, v_OrgId AS OrgId;
END //

-- ── 6. Sos_Respond ────────────────────────────────────────
DROP PROCEDURE IF EXISTS Sos_Respond //
CREATE PROCEDURE Sos_Respond(IN p_SosIncidentId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_VictimUserId INT UNSIGNED;

    SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'RESPONDER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

    SELECT UserId INTO v_VictimUserId FROM SosIncidents WHERE SosIncidentId = p_SosIncidentId LIMIT 1;

    INSERT IGNORE INTO SosResponders (SosIncidentId, UserId, ApprovalStatusLkpId)
    VALUES (p_SosIncidentId, p_UserId, v_StatusLkpId);

    SELECT 1 AS IsSuccess, 'Response registered, awaiting approval.' AS Message,
           v_VictimUserId AS VictimUserId;
END //


DELIMITER ;

-- ============================================================
-- Patch: Confirm No Show
-- Date: 2026-08-21
-- Changes:
--   1. Application_GetByProject — add IsNoShowConfirmed column
--   2. Attendance_ConfirmNoShow — new SP
-- Apply to: local → Railway staging → Railway production
-- ============================================================

-- 1. Application_GetByProject (add IsNoShowConfirmed flag)
DROP PROCEDURE IF EXISTS Application_GetByProject;
DELIMITER //
-- (Copy corrected SP from NGOConnect_Complete_Setup_v5.0.sql)
-- The only change vs current: adds this line after IsExcused:
--   IF(att.NoShowReason = 'ADMIN_CONFIRMED', 1, 0) AS IsNoShowConfirmed,
-- Run the full SP block from the setup SQL.
DELIMITER ;

-- 2. New SP: Attendance_ConfirmNoShow
DELIMITER //
DROP PROCEDURE IF EXISTS Attendance_ConfirmNoShow //
CREATE PROCEDURE Attendance_ConfirmNoShow(
    IN p_AttendanceId INT,
    IN p_ConfirmedBy  INT
)
BEGIN
    DECLARE v_UserId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ProjectId INT UNSIGNED DEFAULT NULL;

    SELECT pa.UserId, ps.ProjectId
    INTO   v_UserId, v_ProjectId
    FROM   ProjectAttendance pa
    JOIN   ProjectSessions   ps ON pa.SessionId = ps.SessionId
    WHERE  pa.AttendanceId     = p_AttendanceId
    LIMIT  1;

    UPDATE ProjectAttendance pa
    SET pa.NoShowReason = 'ADMIN_CONFIRMED',
        pa.UpdatedAt   = NOW()
    WHERE pa.AttendanceId     = p_AttendanceId
      AND pa.AttendanceStatus = 'NO_SHOW'
      AND pa.IsNoShowExcused  = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Record not found or already excused/confirmed.' AS Message,
               NULL AS UserId, NULL AS ProjectId;
    ELSE
        SELECT 1 AS IsSuccess, 'No-show confirmed. Reliability score will be affected.' AS Message,
               v_UserId AS UserId, v_ProjectId AS ProjectId;
    END IF;
END //
DELIMITER ;

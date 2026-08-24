-- ── patch_recurring_flexible_job_sps.sql ─────────────────────────────────────
-- PURPOSE: Create 5 SPs required by the v5.1 Hangfire background jobs.
--
-- RENAME INCLUDED:
--   The per-project session-seeding SP was previously named Project_GenerateSessions
--   (signature: p_ProjectId, p_CreatedBy). It conflicts with the Hangfire job SP
--   which uses the same name but signature: p_DaysAhead.
--   This patch:
--     1. Creates Project_CreateInitialSessions (the renamed per-project init SP)
--     2. Updates Project_AutoActivate to CALL Project_CreateInitialSessions
--     3. Creates the 5 Hangfire job SPs (Project_GenerateSessions now owns p_DaysAhead)
--
-- Apply to: Railway staging → production
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── Step 1: Create Project_CreateInitialSessions (renamed per-project init SP) ──
DROP PROCEDURE IF EXISTS Project_CreateInitialSessions //
CREATE PROCEDURE Project_CreateInitialSessions(IN p_ProjectId INT UNSIGNED, IN p_CreatedBy INT UNSIGNED)
BEGIN
    DECLARE v_TypeCode      VARCHAR(20);
    DECLARE v_RecurStart    DATE;
    DECLARE v_RecurEnd      DATE;
    DECLARE v_RecurDays     VARCHAR(100);
    DECLARE v_FlexFrom      DATE;
    DECLARE v_FlexTo        DATE;
    DECLARE v_StartTime     TIME;
    DECLARE v_EndTime       TIME;
    DECLARE v_MaxVol        INT UNSIGNED;
    DECLARE v_CurrDate      DATE;
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_Count         INT DEFAULT 0;
    DECLARE v_DayAbbr       VARCHAR(3);

    SELECT ptv.ValueCode, p.RecurStart, p.RecurEnd, p.RecurDays,
           p.FlexFromDate, p.FlexToDate, p.SessionStartTime, p.SessionEndTime, p.MaxVolunteers
    INTO   v_TypeCode, v_RecurStart, v_RecurEnd, v_RecurDays,
           v_FlexFrom, v_FlexTo, v_StartTime, v_EndTime, v_MaxVol
    FROM   Projects p
    JOIN   LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.ProjectId = p_ProjectId AND p.IsDeleted = 0;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    IF EXISTS (SELECT 1 FROM ProjectSessions WHERE ProjectId = p_ProjectId AND IsDeleted = 0 LIMIT 1) THEN
        SELECT 1 AS IsSuccess, 'Sessions already generated.' AS Message, 0 AS SessionCount;
    ELSEIF v_TypeCode = 'RECURRING' AND v_RecurStart IS NOT NULL AND v_RecurEnd IS NOT NULL THEN
        SET v_CurrDate = v_RecurStart;
        WHILE v_CurrDate <= v_RecurEnd DO
            SET v_DayAbbr = LEFT(UPPER(DAYNAME(v_CurrDate)), 3);
            IF FIND_IN_SET(v_DayAbbr, UPPER(REPLACE(COALESCE(v_RecurDays, ''), ' ', ''))) > 0 THEN
                INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, QrCode, SessionStatusLkpId, CreatedBy)
                VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, UUID(), v_UpcomingLkpId, p_CreatedBy);
                SET v_Count = v_Count + 1;
            END IF;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' recurring sessions.') AS Message, v_Count AS SessionCount;
    ELSEIF v_TypeCode = 'FLEXIBLE' AND v_FlexFrom IS NOT NULL AND v_FlexTo IS NOT NULL THEN
        SET v_CurrDate = v_FlexFrom;
        WHILE v_CurrDate <= v_FlexTo DO
            INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, MaxVolunteers, SessionStatusLkpId, CreatedBy)
            VALUES (p_ProjectId, v_CurrDate, v_StartTime, v_EndTime, v_MaxVol, v_UpcomingLkpId, p_CreatedBy);
            SET v_Count = v_Count + 1;
            SET v_CurrDate = DATE_ADD(v_CurrDate, INTERVAL 1 DAY);
        END WHILE;
        SELECT 1 AS IsSuccess, CONCAT('Generated ', v_Count, ' flexible sessions.') AS Message, v_Count AS SessionCount;
    ELSE
        SELECT 0 AS IsSuccess, 'Project type does not support session generation or missing schedule data.' AS Message, 0 AS SessionCount;
    END IF;
END //


-- ── Step 2: Update Project_AutoActivate — call renamed SP ────────────────────
DROP PROCEDURE IF EXISTS Project_AutoActivate //
CREATE PROCEDURE Project_AutoActivate()
BEGIN
    DECLARE v_UpcomingLkpId INT UNSIGNED;
    DECLARE v_ActiveLkpId   INT UNSIGNED;
    DECLARE v_LeadDays      INT DEFAULT 0;
    DECLARE v_Count         INT DEFAULT 0;
    DECLARE v_ProjectId     INT UNSIGNED;
    DECLARE v_Done          INT DEFAULT 0;

    SELECT COALESCE(CAST(SettingValue AS SIGNED), 0) INTO v_LeadDays
    FROM Settings WHERE SettingKey = 'AUTO_ACTIVATE_LEAD_DAYS' AND IsDeleted = 0 LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    BEGIN
        DECLARE proj_cursor CURSOR FOR
            SELECT p.ProjectId FROM Projects p
            JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
            WHERE p.StatusLkpId = v_UpcomingLkpId AND p.IsDeleted = 0
              AND ptv.ValueCode IN ('RECURRING', 'FLEXIBLE')
              AND (
                  (ptv.ValueCode = 'RECURRING' AND p.RecurStart IS NOT NULL
                   AND DATE_SUB(p.RecurStart,  INTERVAL v_LeadDays DAY) <= CURDATE())
               OR (ptv.ValueCode = 'FLEXIBLE'  AND p.FlexFromDate IS NOT NULL
                   AND DATE_SUB(p.FlexFromDate, INTERVAL v_LeadDays DAY) <= CURDATE())
              );
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN proj_cursor;
        read_loop: LOOP
            FETCH proj_cursor INTO v_ProjectId;
            IF v_Done THEN LEAVE read_loop; END IF;
            UPDATE Projects SET StatusLkpId = v_ActiveLkpId, UpdatedAt = NOW()
            WHERE ProjectId = v_ProjectId AND IsDeleted = 0;
            CALL Project_CreateInitialSessions(v_ProjectId, 1);  -- renamed from Project_GenerateSessions
            SET v_Count = v_Count + 1;
        END LOOP;
        CLOSE proj_cursor;
    END;

    SELECT 1 AS IsSuccess, CONCAT('Activated ', v_Count, ' project(s).') AS Message, v_Count AS ActivatedCount;
END //


-- ── Step 3: Drop old per-project Project_GenerateSessions (safe — renamed above) ─
DROP PROCEDURE IF EXISTS Project_GenerateSessions //


-- ── Step 4: Five Hangfire Job SPs ────────────────────────────────────────────

-- 4a. Project_GenerateSessions (daily rolling — called by GenerateRecurringSessionsJob)
CREATE PROCEDURE Project_GenerateSessions(IN p_DaysAhead INT)
BEGIN
    DECLARE v_RecurringTypeId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId      INT UNSIGNED DEFAULT NULL;
    DECLARE v_UpcomingLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_ScheduledLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_Done             TINYINT(1)   DEFAULT 0;
    DECLARE v_ProjectId        INT UNSIGNED;
    DECLARE v_TypeCode         VARCHAR(50);
    DECLARE v_RecurDays        VARCHAR(50);
    DECLARE v_StartDate        DATE;
    DECLARE v_EndDate          DATE;
    DECLARE v_StartTime        TIME;
    DECLARE v_EndTime          TIME;
    DECLARE v_CheckDate        DATE;
    DECLARE v_DayName          VARCHAR(10);
    DECLARE v_MaxDate          DATE;

    SELECT lv.LookupValueId INTO v_RecurringTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'RECURRING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_UpcomingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ScheduledLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'SCHEDULED' LIMIT 1;

    SET v_MaxDate = DATE_ADD(CURDATE(), INTERVAL p_DaysAhead DAY);

    BEGIN
        DECLARE cur CURSOR FOR
            SELECT p.ProjectId, sv.ValueCode, p.RecurDays,
                   COALESCE(p.RecurStart, CURDATE()) AS StartDate,
                   COALESCE(p.RecurEnd,   v_MaxDate) AS EndDate,
                   p.SessionStartTime, p.SessionEndTime
            FROM   Projects p
            JOIN   LookupValues sv ON p.ProjectTypeLkpId = sv.LookupValueId
            WHERE  p.IsDeleted = 0
              AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
              AND  p.ProjectTypeLkpId IN (v_RecurringTypeId, v_FlexibleTypeId);

        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = 1;

        OPEN cur;
        project_loop: LOOP
            FETCH cur INTO v_ProjectId, v_TypeCode, v_RecurDays,
                           v_StartDate, v_EndDate, v_StartTime, v_EndTime;
            IF v_Done THEN LEAVE project_loop; END IF;

            SET v_CheckDate = GREATEST(v_StartDate, CURDATE());
            WHILE v_CheckDate <= LEAST(v_MaxDate, v_EndDate) DO
                SET v_DayName = UPPER(DAYNAME(v_CheckDate));
                IF v_TypeCode = 'FLEXIBLE'
                   OR (v_TypeCode = 'RECURRING' AND FIND_IN_SET(v_DayName, UPPER(REPLACE(v_RecurDays, ' ', ''))) > 0)
                THEN
                    IF NOT EXISTS (
                        SELECT 1 FROM ProjectSessions ps
                        WHERE ps.ProjectId = v_ProjectId AND ps.SessionDate = v_CheckDate AND ps.IsDeleted = 0
                    ) THEN
                        INSERT INTO ProjectSessions (ProjectId, SessionDate, StartTime, EndTime, StatusLkpId, CreatedBy)
                        VALUES (v_ProjectId, v_CheckDate, v_StartTime, v_EndTime, v_ScheduledLkpId, 0);
                    END IF;
                END IF;
                SET v_CheckDate = DATE_ADD(v_CheckDate, INTERVAL 1 DAY);
            END WHILE;
        END LOOP;
        CLOSE cur;
    END;

    SELECT 1 AS IsSuccess, 'Sessions generated.' AS Message;
END //


-- 4b. Project_AutoCompleteSessions (every 30 min — AutoCompleteSessionsJob)
DROP PROCEDURE IF EXISTS Project_AutoCompleteSessions //
CREATE PROCEDURE Project_AutoCompleteSessions()
BEGIN
    DECLARE v_ScheduledLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ScheduledLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'SCHEDULED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CompletedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'SESSION_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE ProjectSessions ps
    SET    ps.StatusLkpId = v_CompletedLkpId, ps.UpdatedAt = NOW()
    WHERE  ps.IsDeleted   = 0
      AND  ps.StatusLkpId IN (v_ScheduledLkpId, v_ActiveLkpId)
      AND  CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00') < NOW();

    SELECT 1 AS IsSuccess, CONCAT('Auto-completed ', ROW_COUNT(), ' sessions.') AS Message;
END //


-- 4c. Project_GetCheckoutReminderTargets (every 5 min — CheckoutReminderJob)
DROP PROCEDURE IF EXISTS Project_GetCheckoutReminderTargets //
CREATE PROCEDURE Project_GetCheckoutReminderTargets(IN p_MinutesBefore INT)
BEGIN
    DECLARE v_CheckedInLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_CheckedInLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'CHECKED_IN' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT att.UserId, p.ProjectId, p.ProjectName, ud.FcmToken,
           TIME_FORMAT(ps.EndTime, '%H:%i') AS EndTime
    FROM   ProjectAttendance att
    JOIN   ProjectSessions   ps ON ps.SessionId = att.SessionId AND ps.IsDeleted = 0
    JOIN   Projects          p  ON p.ProjectId  = ps.ProjectId  AND p.IsDeleted  = 0
    JOIN   Users             u  ON u.UserId     = att.UserId
    LEFT JOIN UserDevices    ud ON ud.UserId     = att.UserId    AND ud.IsActive  = 1
    WHERE  att.AttendStatusLkpId = v_CheckedInLkpId
      AND  att.CheckOutTime      IS NULL
      AND  att.IsDeleted         = 0
      AND  p.ProjectTypeLkpId    = v_FlexibleTypeId
      AND  ps.SessionDate        = CURDATE()
      AND  TIMESTAMPDIFF(MINUTE, NOW(),
               CONVERT_TZ(CONCAT(ps.SessionDate, ' ', ps.EndTime), '+05:30', '+00:00'))
           BETWEEN (p_MinutesBefore - 1) AND (p_MinutesBefore + 1);
END //


-- 4d. Project_CheckMilestoneNotifications (daily 3 AM — MilestoneNotificationJob)
DROP PROCEDURE IF EXISTS Project_CheckMilestoneNotifications //
CREATE PROCEDURE Project_CheckMilestoneNotifications()
BEGIN
    DECLARE v_RecurringTypeId INT UNSIGNED DEFAULT NULL;
    DECLARE v_FlexibleTypeId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_ActiveLkpId     INT UNSIGNED DEFAULT NULL;
    DECLARE v_ClosingLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_NotifLkpId      INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_RecurringTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'RECURRING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_FlexibleTypeId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_SCHEDULE_TYPE' AND lv.ValueCode = 'FLEXIBLE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_NotifLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'NOTIF_TYPE' AND lv.ValueCode = 'MILESTONE_REACHED' LIMIT 1;

    INSERT INTO Notifications (UserId, Title, Body, NotifTypeLkpId, RefId, RefType, CreatedAt)
    SELECT pa.UserId,
           'Milestone Reached! 🎉' AS Title,
           CONCAT('You''ve reached ', m.milestone, '% progress on "', p.ProjectName, '"!') AS Body,
           v_NotifLkpId, p.ProjectId, 'PROJECT', NOW()
    FROM ProjectApplications pa
    JOIN Projects p ON p.ProjectId = pa.ProjectId AND p.IsDeleted = 0
    JOIN LookupValues appSv ON pa.StatusLkpId = appSv.LookupValueId
    JOIN (SELECT 25 AS milestone UNION ALL SELECT 50 UNION ALL SELECT 75) m
    WHERE pa.IsDeleted = 0
      AND appSv.ValueCode = 'APPROVED'
      AND p.ProjectTypeLkpId IN (v_RecurringTypeId, v_FlexibleTypeId)
      AND p.StatusLkpId IN (v_ActiveLkpId, v_ClosingLkpId)
      AND (
          (p.ProjectTypeLkpId = v_RecurringTypeId AND p.MinAttendPct IS NOT NULL
           AND (SELECT COUNT(*) FROM ProjectAttendance att2
                JOIN ProjectSessions ps2 ON att2.SessionId = ps2.SessionId
                JOIN LookupValues av ON att2.AttendStatusLkpId = av.LookupValueId
                WHERE att2.UserId = pa.UserId AND ps2.ProjectId = p.ProjectId
                  AND att2.IsDeleted = 0 AND av.ValueCode = 'ATTENDED') * 100.0 /
           NULLIF((SELECT COUNT(*) FROM ProjectSessions ps3
                   WHERE ps3.ProjectId = p.ProjectId AND ps3.IsDeleted = 0), 0) >= m.milestone)
          OR
          (p.ProjectTypeLkpId = v_FlexibleTypeId AND p.MinSessionHours IS NOT NULL
           AND (SELECT COALESCE(SUM(att3.HoursLogged), 0)
                FROM ProjectAttendance att3
                JOIN ProjectSessions ps4 ON att3.SessionId = ps4.SessionId
                WHERE att3.UserId = pa.UserId AND ps4.ProjectId = p.ProjectId
                  AND att3.IsDeleted = 0) * 100.0 /
           NULLIF(p.MinSessionHours, 0) >= m.milestone)
      )
      AND NOT EXISTS (
          SELECT 1 FROM Notifications n2
          WHERE n2.UserId = pa.UserId AND n2.RefId = p.ProjectId
            AND n2.NotifTypeLkpId = v_NotifLkpId
            AND n2.Body LIKE CONCAT('%', m.milestone, '%')
      );

    SELECT 1 AS IsSuccess, CONCAT('Milestone notifications inserted: ', ROW_COUNT()) AS Message;
END //


-- 4e. Project_AutoFinalizeStaleClosing (daily 4 AM — AutoFinalizeStaleClosingJob)
DROP PROCEDURE IF EXISTS Project_AutoFinalizeStaleClosing //
CREATE PROCEDURE Project_AutoFinalizeStaleClosing(IN p_DaysThreshold INT)
BEGIN
    DECLARE v_ClosingLkpId   INT UNSIGNED DEFAULT NULL;
    DECLARE v_CompletedLkpId INT UNSIGNED DEFAULT NULL;

    SELECT lv.LookupValueId INTO v_ClosingLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CLOSING' LIMIT 1;

    SELECT lv.LookupValueId INTO v_CompletedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1;

    UPDATE Projects p
    SET    p.StatusLkpId   = v_CompletedLkpId, p.UpdatedAt = NOW(), p.UpdatedBy = 0,
           p.ImpactSummary = COALESCE(p.ImpactSummary, 'Auto-finalized by system.')
    WHERE  p.IsDeleted     = 0
      AND  p.StatusLkpId   = v_ClosingLkpId
      AND  p.StatusUpdatedAt IS NOT NULL
      AND  DATEDIFF(NOW(), p.StatusUpdatedAt) >= p_DaysThreshold;

    SELECT 1 AS IsSuccess,
           CONCAT('Auto-finalized ', ROW_COUNT(), ' stale CLOSING projects.') AS Message;
END //

DELIMITER ;

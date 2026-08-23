-- ─────────────────────────────────────────────────────────────────────────────
-- patch_profile_update_notification_fix.sql
--
-- Fixes 3 reported bugs in the "Request update" (Super Admin → member profile) flow:
--
-- 1. Tapping the "Action required: update your profile" notification in the app
--    did nothing. Root cause: SuperAdmin_User_RequestUpdate inserted a Notifications
--    row with NotifType='PROFILE_UPDATE_REQUESTED', but the mobile app's navigation
--    switch statements only ever handled 'PROFILE_UPDATE_REQUIRED' — a string that
--    row never used. Fixed by standardising the SP's NotifType to
--    'PROFILE_UPDATE_REQUIRED' (the C# DAL layer's now-removed duplicate insert used
--    to write this type; see SuperAdminDal.cs changes, no SP change needed there).
--
-- 2. Users.ProfileVerificationLkpId was being set to the 'PENDING' lookup value
--    ("Not Reviewed") instead of 'NEEDS_UPDATE' — a distinct status that already
--    existed in the PROFILE_VERIFICATION_STATUS lookup seed but was never used by
--    this SP. Fixed so the app can distinguish "never reviewed" from "admin flagged
--    for resubmission".
--
-- 3. There was nowhere in the app for the user to see the Super Admin's actual
--    remarks — User_GetProfile never returned verification status or reason at all.
--    Added ProfileVerificationStatusCode + ProfileUpdateReason (latest
--    PROFILE_UPDATE_REQUIRED Notifications.Body for this user) so ProfileScreen can
--    show an "action required" banner with the real reason text.
--
-- Companion C# change (not in this SQL file): SuperAdminDal.cs's
-- RequestMemberUpdateAsync/VerifyMemberProfileAsync/SuspendMemberAsync/ApproveOrgAsync
-- no longer insert a second duplicate Notifications row — the SP's own insert is now
-- the single source of truth; C# only sends the FCM push.
--
-- Apply: local DB first → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

-- ── SuperAdmin_User_RequestUpdate ────────────────────────────────────────────
DROP PROCEDURE IF EXISTS SuperAdmin_User_RequestUpdate //
CREATE PROCEDURE SuperAdmin_User_RequestUpdate(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_Exists TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_Exists FROM Users
    WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'User not found.' AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required.' AS Message;
    ELSE
        -- Set profile to NEEDS_UPDATE (distinct from PENDING/not-yet-reviewed) so the
        -- app can show a dedicated "action required" banner with the admin's reason.
        UPDATE Users
        SET ProfileVerificationLkpId = (
            SELECT lv.LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv.ValueCode = 'NEEDS_UPDATE'
            LIMIT 1
        ),
        UpdatedAt = NOW()
        WHERE UserId = p_UserId;

        -- NotifType standardised to PROFILE_UPDATE_REQUIRED (matches mobile app's
        -- RootNavigator/NotificationsScreen deep-link switch — was previously
        -- PROFILE_UPDATE_REQUESTED, a string the app never handled, so tapping the
        -- notification did nothing). This is the single canonical write for this
        -- event; the C# DAL layer no longer inserts a duplicate row.
        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'PROFILE_UPDATE_REQUIRED', 'Profile update required',
                p_Reason, p_UserId, 'USER');

        SELECT 1 AS IsSuccess, 'Profile update requested.' AS Message;
    END IF;
END //

-- ── User_GetProfile ──────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetProfile //
CREATE PROCEDURE User_GetProfile(IN p_UserId INT UNSIGNED, IN p_RequestingUserId INT UNSIGNED)
BEGIN
    SELECT
        u.UserId, u.Mobile, u.Email, u.CountryCode, u.IsVerified,
        up.FirstName, up.LastName, up.Bio, up.ProfilePhoto,
        up.DateOfBirth, up.Occupation, up.Organisation, up.VolunteerExp,
        up.GenderLkpId,
        gv.ValueName AS Gender,    gv.ValueCode AS GenderCode,
        up.EducationLkpId,
        ev.ValueName AS Education, ev.ValueCode AS EducationCode,
        up.FieldOfStudy,
        up.WorkExpLkpId,
        wv.ValueName AS WorkExperience, wv.ValueCode AS WorkExpCode,
        up.AddressLine1, up.AddressLine2, up.City, up.State, up.Pincode, up.Country,
        up.ImpactScore, up.ReliabilityPct,
        u.CreatedAt AS MemberSince,
        up.UpdatedAt,
        -- v5.1: expose profile verification state + the Super Admin's remarks so the
        -- app can show an "action required" banner instead of burying the reason in
        -- notification history only (ProfileScreen reads these two fields).
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode,
        (
            SELECT n.Body FROM Notifications n
            WHERE n.UserId = u.UserId AND n.NotifType = 'PROFILE_UPDATE_REQUIRED'
            ORDER BY n.CreatedAt DESC LIMIT 1
        ) AS ProfileUpdateReason,
        CASE
            WHEN up.FirstName IS NOT NULL AND TRIM(up.FirstName) != ''
             AND up.LastName  IS NOT NULL AND TRIM(up.LastName)  != ''
            THEN 1 ELSE 0
        END AS IsProfileComplete,
        -- ── Impact stats (same logic as User_GetImpact) ──────────────────────
        ROUND(IFNULL((
            SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps  ON pa2.SessionId       = ps.SessionId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId    = lta.LookupTypeId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
        ), 0), 1) AS TotalHours,
        IFNULL((
            SELECT COUNT(DISTINCT ps2.ProjectId)
            FROM   ProjectAttendance pa2
            JOIN   ProjectSessions   ps2 ON pa2.SessionId        = ps2.SessionId
            JOIN   Projects          pr  ON ps2.ProjectId        = pr.ProjectId
            JOIN   LookupValues      lva ON pa2.AttendStatusLkpId = lva.LookupValueId
            JOIN   LookupTypes       lta ON lva.LookupTypeId     = lta.LookupTypeId
            JOIN   LookupValues      lpv ON pr.StatusLkpId       = lpv.LookupValueId
            WHERE  pa2.UserId = p_UserId
              AND  lta.TypeCode = 'ATTENDANCE_STATUS' AND lva.ValueCode = 'ATTENDED'
              AND  lpv.ValueCode IN ('COMPLETED', 'EXPIRED')
        ), 0) AS ProjectsCount,
        IFNULL((
            SELECT COUNT(*)
            FROM   OrgMembers   om2
            JOIN   LookupValues lvo ON om2.StatusLkpId = lvo.LookupValueId
            WHERE  om2.UserId = p_UserId AND om2.IsDeleted = 0
              AND  lvo.ValueCode = 'APPROVED'
        ), 0) AS NgosJoined
    FROM Users u
    JOIN UserProfiles up ON u.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues gv ON up.GenderLkpId    = gv.LookupValueId
    LEFT JOIN LookupValues ev ON up.EducationLkpId = ev.LookupValueId
    LEFT JOIN LookupValues wv ON up.WorkExpLkpId   = wv.LookupValueId
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //

DELIMITER ;

-- Verify
SELECT 'patch_profile_update_notification_fix applied successfully.' AS Status;

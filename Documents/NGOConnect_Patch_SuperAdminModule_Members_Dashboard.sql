-- ============================================================
-- NGO Connect — Patch: Super Admin Members + Dashboard module
-- Apply directly to Railway staging/prod (or local) without
-- re-running the full setup script. Extracted verbatim from
-- NGOConnect_Complete_Setup_v4.4.sql — "v4.5 ADDITIONS (CONTINUED)".
--
-- New column + new lookup type + brand-new SPs only. Zero changes
-- to any existing table, SP, or the mobile/NGO-admin auth flow.
--
-- NOTE — flagged for the user, not auto-fixed (needs explicit sign-off,
-- see feedback_superadmin_isolation rule): SuperAdmin_User_Suspend below
-- sets Users.IsActive = 0 and revokes all RefreshTokens, which blocks a
-- suspended member from silently continuing an existing session and
-- from refreshing to a new access token. It does NOT stop a suspended
-- member from starting a brand-new login (AuthDal never checks
-- Users.IsActive today — confirmed by grep, zero matches). Closing that
-- gap means editing AuthDal, an existing file used by every real user's
-- login — out of scope for this isolated module without explicit
-- approval to touch existing auth code.
--
-- Safe to re-run: ALTER TABLE / INSERT guarded, SPs dropped first.
-- ============================================================

-- Skip the ALTER + seed block if this patch was already applied once.
SET @col_exists := (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Users' AND COLUMN_NAME = 'ProfileVerificationLkpId'
);

SET @alter_sql := IF(@col_exists = 0,
    'ALTER TABLE Users ADD COLUMN ProfileVerificationLkpId INT UNSIGNED NULL AFTER IsActive',
    'SELECT 1');
PREPARE stmt FROM @alter_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @fk_exists := (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Users' AND CONSTRAINT_NAME = 'fk_users_profileverification'
);

SET @fk_sql := IF(@fk_exists = 0,
    'ALTER TABLE Users ADD CONSTRAINT fk_users_profileverification FOREIGN KEY (ProfileVerificationLkpId) REFERENCES LookupValues(LookupValueId)',
    'SELECT 1');
PREPARE stmt FROM @fk_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
SELECT 'PROFILE_VERIFICATION_STATUS', 'Profile Verification Status', 'Super Admin document/profile verification state for a member', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM LookupTypes WHERE TypeCode = 'PROFILE_VERIFICATION_STATUS');

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'PENDING' AS ValueCode, 'Not Reviewed' AS ValueName, 1 AS OrderNo UNION ALL
    SELECT 'VERIFIED', 'Verified', 2 UNION ALL
    SELECT 'NEEDS_UPDATE', 'Needs Update', 3
) v ON 1=1
WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS'
  AND NOT EXISTS (
    SELECT 1 FROM LookupValues lv WHERE lv.LookupTypeId = lt.LookupTypeId AND lv.ValueCode = v.ValueCode
  );

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetDetail;
DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetList;
DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetStatusHistory;
DROP PROCEDURE IF EXISTS SuperAdmin_User_GetList;
DROP PROCEDURE IF EXISTS SuperAdmin_User_GetFullProfile;
DROP PROCEDURE IF EXISTS SuperAdmin_User_GetDocuments;
DROP PROCEDURE IF EXISTS SuperAdmin_UserDocument_Verify;
DROP PROCEDURE IF EXISTS SuperAdmin_User_VerifyProfile;
DROP PROCEDURE IF EXISTS SuperAdmin_User_RequestUpdate;
DROP PROCEDURE IF EXISTS SuperAdmin_User_Suspend;
DROP PROCEDURE IF EXISTS SuperAdmin_User_Reactivate;
DROP PROCEDURE IF EXISTS SuperAdmin_Dashboard_GetKpis;
DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetRecent;

DELIMITER //

-- ── Org detail — re-created to add MemberCount (frontend needs it) ──

CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        founder.UserId AS FounderUserId,
        CONCAT(fp.FirstName, ' ', fp.LastName) AS FounderName,
        u.Email AS FounderEmail, u.Mobile AS FounderMobile,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason,
        (SELECT COUNT(*) FROM OrgMembers om2
          JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
          WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0 AND sv2.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    LEFT JOIN OrgMembers founder ON founder.OrgId = o.OrgId AND founder.IsDeleted = 0
        AND founder.RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
    LEFT JOIN Users u ON founder.UserId = u.UserId
    LEFT JOIN UserProfiles fp ON founder.UserId = fp.UserId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

-- ── Org list — re-created to add OrgType (frontend Type column needs it) ──

CREATE PROCEDURE SuperAdmin_Org_GetList(
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.City, o.State, o.LogoUrl,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode
    ORDER BY o.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.IsDeleted = 0 AND sv.ValueCode = p_StatusCode;
END //

-- ── Org status history (drawer timeline) ────────────────────────

CREATE PROCEDURE SuperAdmin_Org_GetStatusHistory(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        h.OrgStatusHistoryId,
        oldv.ValueCode AS OldStatus, oldv.ValueName AS OldStatusName,
        newv.ValueCode AS NewStatus, newv.ValueName AS NewStatusName,
        h.Reason, h.ChangedByType, h.ChangedBy, h.CreatedAt
    FROM OrgStatusHistory h
    LEFT JOIN LookupValues oldv ON h.OldStatusLkpId = oldv.LookupValueId
    JOIN LookupValues newv ON h.NewStatusLkpId = newv.LookupValueId
    WHERE h.OrgId = p_OrgId
    ORDER BY h.CreatedAt DESC;
END //

-- ── Members admin (cross-NGO oversight) ─────────────────────────

CREATE PROCEDURE SuperAdmin_User_GetList(
    IN p_OrgIds     TEXT,
    IN p_Search     VARCHAR(150),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT o.OrgName ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS Role,
        (SELECT sv.ValueCode FROM OrgMembers om2
            JOIN LookupValues sv ON om2.StatusLkpId = sv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS MembershipStatus,
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        MIN(om.JoinedAt) AS JoinedAt
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
        AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
    JOIN Organisations o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.IsDeleted = 0
      AND (p_Search IS NULL OR p_Search = ''
           OR CONCAT(up.FirstName,' ',up.LastName) LIKE CONCAT('%', p_Search, '%')
           OR u.Email LIKE CONCAT('%', p_Search, '%')
           OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
    GROUP BY u.UserId, up.FirstName, up.LastName, u.Email, u.Mobile, up.ProfilePhoto, u.IsActive, pv.ValueCode
    ORDER BY JoinedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM (
        SELECT u.UserId
        FROM Users u
        JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
        WHERE u.IsDeleted = 0
          AND (p_Search IS NULL OR p_Search = ''
               OR CONCAT(up.FirstName,' ',up.LastName) LIKE CONCAT('%', p_Search, '%')
               OR u.Email LIKE CONCAT('%', p_Search, '%')
               OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
        GROUP BY u.UserId
    ) t;
END //

CREATE PROCEDURE SuperAdmin_User_GetFullProfile(IN p_UserId INT UNSIGNED)
BEGIN
    -- Result set 1: core profile
    SELECT
        u.UserId, CONCAT(up.FirstName,' ',up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT o.OrgName ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS Role,
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        up.ReliabilityPct AS Reliability,
        (SELECT ROUND(SUM(pa.HoursLogged),1) FROM ProjectAttendance pa
            JOIN LookupValues av ON pa.AttendStatusLkpId = av.LookupValueId
            WHERE pa.UserId = u.UserId AND av.ValueCode = 'ATTENDED') AS Hours,
        (SELECT COUNT(DISTINCT ps.ProjectId) FROM ProjectAttendance pa
            JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
            JOIN Projects p ON ps.ProjectId = p.ProjectId
            JOIN LookupValues av ON pa.AttendStatusLkpId = av.LookupValueId
            WHERE pa.UserId = u.UserId AND av.ValueCode = 'ATTENDED'
              AND p.StatusLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'COMPLETED' LIMIT 1)
        ) AS Projects
    FROM Users u
    JOIN UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
    LEFT JOIN Organisations o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0
    GROUP BY u.UserId, up.FirstName, up.LastName, u.Email, u.Mobile, up.ProfilePhoto, u.IsActive, pv.ValueCode, up.ReliabilityPct;

    -- Result set 2: skills
    SELECT SkillName FROM UserSkills WHERE UserId = p_UserId AND IsDeleted = 0 ORDER BY SkillName;

    -- Result set 3: interests
    SELECT iv.ValueName FROM UserInterests ui
    JOIN LookupValues iv ON ui.InterestLkpId = iv.LookupValueId
    WHERE ui.UserId = p_UserId ORDER BY iv.ValueName;

    -- Result set 4: badges
    SELECT BadgeType FROM UserBadges WHERE UserId = p_UserId AND IsDeleted = 0 ORDER BY AwardedAt DESC;

    -- Result set 5: other organisations (role + status per org)
    SELECT o.OrgName, rv.ValueName AS Role, sv.ValueName AS Status
    FROM OrgMembers om
    JOIN Organisations o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
    JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
    WHERE om.UserId = p_UserId AND om.IsDeleted = 0
    ORDER BY o.OrgName;
END //

CREATE PROCEDURE SuperAdmin_User_GetDocuments(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT ud.UserDocumentId, ud.DocumentTypeLkpId, dt.ValueName AS DocumentType,
           ud.FileUrl, ud.FileName, ud.IsVerified, ud.VerifiedAt, ud.VerifiedBy, ud.CreatedAt
    FROM UserDocuments ud
    LEFT JOIN LookupValues dt ON ud.DocumentTypeLkpId = dt.LookupValueId
    WHERE ud.UserId = p_UserId AND ud.IsDeleted = 0
    ORDER BY ud.CreatedAt ASC;
END //

CREATE PROCEDURE SuperAdmin_UserDocument_Verify(
    IN p_UserDocumentId   INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsVerified       TINYINT(1)
)
BEGIN
    UPDATE UserDocuments
    SET IsVerified = p_IsVerified, VerifiedAt = NOW(), VerifiedBy = p_SuperAdminUserId
    WHERE UserDocumentId = p_UserDocumentId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document verification updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_User_VerifyProfile(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists     INT DEFAULT 0;
    DECLARE v_VerifiedId INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM Users WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'Member not found.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_VerifiedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv.ValueCode = 'VERIFIED' LIMIT 1;

        UPDATE Users SET ProfileVerificationLkpId = v_VerifiedId, UpdatedBy = p_SuperAdminUserId
        WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'PROFILE_VERIFIED', 'Your profile has been verified',
                'Your profile and documents have been reviewed and verified by the NGO Connect team.', p_UserId, 'USER_PROFILE');

        SELECT 1 AS IsSuccess, 'Profile marked as verified.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_User_RequestUpdate(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_Exists        INT DEFAULT 0;
    DECLARE v_NeedsUpdateId INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM Users WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_Exists = 0 THEN
        SELECT 0 AS IsSuccess, 'Member not found.' AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required so the member knows what to fix.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_NeedsUpdateId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv.ValueCode = 'NEEDS_UPDATE' LIMIT 1;

        UPDATE Users SET ProfileVerificationLkpId = v_NeedsUpdateId, UpdatedBy = p_SuperAdminUserId
        WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'PROFILE_NEEDS_UPDATE', 'Your profile needs an update', p_Reason, p_UserId, 'USER_PROFILE');

        SELECT 1 AS IsSuccess, 'Update request sent to member.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_User_Suspend(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentActive TINYINT(1);

    SELECT IsActive INTO v_CurrentActive FROM Users WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_CurrentActive IS NULL THEN
        SELECT 0 AS IsSuccess, 'Member not found.' AS Message;
    ELSEIF v_CurrentActive = 0 THEN
        SELECT 0 AS IsSuccess, 'Account is already suspended.' AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required to suspend an account.' AS Message;
    ELSE
        UPDATE Users SET IsActive = 0, UpdatedBy = p_SuperAdminUserId WHERE UserId = p_UserId;

        -- Revoke all active refresh tokens so a suspended member cannot silently
        -- keep a session alive or refresh to a new access token. Does NOT block a
        -- brand-new login attempt — see the note at the top of this file.
        UPDATE RefreshTokens SET IsRevoked = 1, RevokedAt = NOW()
        WHERE UserId = p_UserId AND IsRevoked = 0;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'ACCOUNT_SUSPENDED', 'Your account has been suspended', p_Reason, p_UserId, 'USER_ACCOUNT');

        SELECT 1 AS IsSuccess, 'Account suspended.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_User_Reactivate(
    IN p_UserId           INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentActive TINYINT(1);

    SELECT IsActive INTO v_CurrentActive FROM Users WHERE UserId = p_UserId AND IsDeleted = 0;

    IF v_CurrentActive IS NULL THEN
        SELECT 0 AS IsSuccess, 'Member not found.' AS Message;
    ELSEIF v_CurrentActive = 1 THEN
        SELECT 0 AS IsSuccess, 'Account is already active.' AS Message;
    ELSE
        UPDATE Users SET IsActive = 1, UpdatedBy = p_SuperAdminUserId WHERE UserId = p_UserId;

        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        VALUES (p_UserId, 'ACCOUNT_REACTIVATED', 'Your account has been reactivated',
                'You can now log in to NGO Connect again.', p_UserId, 'USER_ACCOUNT');

        SELECT 1 AS IsSuccess, 'Account reactivated.' AS Message;
    END IF;
END //

-- ── Dashboard / Overview KPIs ────────────────────────────────────

CREATE PROCEDURE SuperAdmin_Dashboard_GetKpis()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS TotalOrgs,
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode IN ('PENDING', 'UNDER_REVIEW')) AS PendingOrgs,
        (SELECT COUNT(DISTINCT u.UserId) FROM Users u
            JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND sv.ValueCode = 'APPROVED') AS TotalVolunteers,
        (SELECT COUNT(DISTINCT u.UserId) FROM Users u
            JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND sv.ValueCode = 'APPROVED'
              AND u.LastLoginAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS ActiveVolunteersLast30Days,
        (SELECT COALESCE(SUM(dt.DonationAmount), 0) FROM DonationTransactions dt
            JOIN LookupValues sv ON dt.PayStatusLkpId = sv.LookupValueId
            WHERE dt.IsDeleted = 0 AND sv.ValueCode = 'SUCCESS') AS TotalDonationsAmount;
END //

CREATE PROCEDURE SuperAdmin_Org_GetRecent(IN p_Limit INT)
BEGIN
    SELECT o.OrgId, o.OrgName, o.LogoUrl, sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
           o.CreatedAt AS SubmittedAt
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.IsDeleted = 0
    ORDER BY o.CreatedAt DESC
    LIMIT p_Limit;
END //

DELIMITER ;

-- ============================================================
-- END OF PATCH
-- ============================================================

-- ============================================================
-- PATCH: SUPER ADMIN MODULE (v4.5)
-- Apply to Railway staging / production after the setup SQL has
-- already been run once. This patch is idempotent-safe to the
-- extent MySQL allows (CREATE TABLE will fail if it already
-- exists — that's intentional, it means the patch already ran).
--
-- New tables + brand-new SPs only. Zero changes to any existing
-- table or SP.
--
-- This patch is a straight copy of the "v4.5 ADDITIONS" block in
-- NGOConnect_Complete_Setup_v4.4.sql — that file remains the
-- single source of truth. If they ever drift, the setup SQL wins.
-- ============================================================

-- ── GROUP 11: SUPER ADMIN (2 tables) ─────────────────────────

CREATE TABLE SuperAdminUsers (
    SuperAdminUserId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Username         VARCHAR(100)  NOT NULL,
    PasswordHash     VARCHAR(255)  NOT NULL,
    FullName         VARCHAR(150)  NOT NULL,
    Email            VARCHAR(150)  NULL,
    IsActive         TINYINT(1)    NOT NULL DEFAULT 1,
    LastLoginAt      DATETIME      NULL,
    CreatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SuperAdminUserId),
    UNIQUE KEY uq_superadmin_username (Username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgStatusHistory (
    OrgStatusHistoryId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId              INT UNSIGNED  NOT NULL,
    OldStatusLkpId     INT UNSIGNED  NULL,
    NewStatusLkpId     INT UNSIGNED  NOT NULL,
    Reason             TEXT          NULL,
    ChangedByType      VARCHAR(20)   NOT NULL COMMENT 'SUPER_ADMIN or FOUNDER',
    ChangedBy          INT UNSIGNED  NOT NULL COMMENT 'SuperAdminUserId or UserId depending on ChangedByType',
    CreatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (OrgStatusHistoryId),
    INDEX idx_orgstatushist_org (OrgId, CreatedAt DESC),
    CONSTRAINT fk_orgstatushist_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed one default Super Admin.
--   Username: gaurav.admin
--   Password: NgoConnect@2026   <-- CHANGE IMMEDIATELY AFTER FIRST LOGIN
INSERT INTO SuperAdminUsers (Username, PasswordHash, FullName, Email, IsActive)
VALUES ('gaurav.admin', '$2b$11$bL6esk4WXdAWUxFp7H56PeGqxyXoIQO0CgVyt98K.1rwSJEH3Es5S', 'Gaurav Shukla', 'gauravshukla1409@gmail.com', 1);

DELIMITER //

CREATE PROCEDURE SuperAdmin_GetByUsername(IN p_Username VARCHAR(100))
BEGIN
    SELECT SuperAdminUserId, Username, PasswordHash, FullName, Email, IsActive
    FROM SuperAdminUsers
    WHERE Username = p_Username
    LIMIT 1;
END //

CREATE PROCEDURE SuperAdmin_UpdateLastLogin(IN p_SuperAdminUserId INT UNSIGNED)
BEGIN
    UPDATE SuperAdminUsers SET LastLoginAt = NOW() WHERE SuperAdminUserId = p_SuperAdminUserId;
    SELECT 1 AS IsSuccess, 'Login recorded.' AS Message;
END //

CREATE PROCEDURE SuperAdmin_Org_GetList(
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.City, o.State, o.LogoUrl,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode
    ORDER BY o.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode;
END //

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
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
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

CREATE PROCEDURE SuperAdmin_Org_GetDocuments(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT od.OrgDocumentId, od.DocumentTypeLkpId, dt.ValueName AS DocumentType,
           od.FileUrl, od.FileName, od.IsVerified, od.VerifiedAt, od.VerifiedBy,
           od.CreatedAt
    FROM OrgDocuments od
    LEFT JOIN LookupValues dt ON od.DocumentTypeLkpId = dt.LookupValueId
    WHERE od.OrgId = p_OrgId AND od.IsDeleted = 0
    ORDER BY od.CreatedAt ASC;
END //

CREATE PROCEDURE SuperAdmin_OrgDocument_Verify(
    IN p_OrgDocumentId  INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsVerified     TINYINT(1)
)
BEGIN
    UPDATE OrgDocuments
    SET IsVerified = p_IsVerified,
        VerifiedAt = NOW(),
        VerifiedBy = p_SuperAdminUserId
    WHERE OrgDocumentId = p_OrgDocumentId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document verification updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved',
                    'Congratulations — your organisation is now live on NGO Connect.', p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reject(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_RejectedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reject — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A rejection reason is required.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_RejectedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'REJECTED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_RejectedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_RejectedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_REJECTED', 'Your NGO registration needs changes',
                    p_Reason, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation rejected.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Suspend(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_SuspendedId     INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'APPROVED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot suspend — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_SuspendedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'SUSPENDED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_SuspendedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_SuspendedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation suspended.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reactivate(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'SUSPENDED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reactivate — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation reactivated.' AS Message;
    END IF;
END //

CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId         INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_OrgName       VARCHAR(200),
    IN p_Category      VARCHAR(100),
    IN p_ContactPerson VARCHAR(100),
    IN p_About         TEXT,
    IN p_Mission       TEXT,
    IN p_Vision        TEXT,
    IN p_LogoUrl       VARCHAR(500),
    IN p_ContactEmail  VARCHAR(150),
    IN p_ContactPhone  VARCHAR(20),
    IN p_Website       VARCHAR(255),
    IN p_AddressLine1  VARCHAR(200),
    IN p_AddressLine2  VARCHAR(200),
    IN p_City          VARCHAR(100),
    IN p_State         VARCHAR(100),
    IN p_Pincode       VARCHAR(20),
    IN p_Country       VARCHAR(100)
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_PendingId       INT UNSIGNED;
    DECLARE v_IsFounder       INT DEFAULT 0;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsFounder FROM OrgMembers om
        JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
        WHERE om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0 AND rv.ValueCode = 'FOUNDER';

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_IsFounder = 0 THEN
        SELECT 0 AS IsSuccess, 'Only the founder can resubmit this organisation.' AS Message;
    ELSEIF v_CurrentCode <> 'REJECTED' THEN
        SELECT 0 AS IsSuccess, 'Only a rejected organisation can be resubmitted.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_PendingId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        UPDATE Organisations SET
            OrgName = p_OrgName, Category = p_Category, ContactPerson = p_ContactPerson,
            About = p_About, Mission = p_Mission, Vision = p_Vision, LogoUrl = p_LogoUrl,
            ContactEmail = p_ContactEmail, ContactPhone = p_ContactPhone, Website = p_Website,
            AddressLine1 = p_AddressLine1, AddressLine2 = p_AddressLine2, City = p_City,
            State = p_State, Pincode = p_Pincode, Country = p_Country,
            StatusLkpId = v_PendingId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_GetList()
BEGIN
    SELECT lt.LookupTypeId, lt.TypeCode, lt.TypeName, lt.Description, lt.IsSystemType,
        (SELECT COUNT(*) FROM LookupValues lv WHERE lv.LookupTypeId = lt.LookupTypeId AND lv.IsDeleted = 0) AS ValueCount
    FROM LookupTypes lt
    WHERE lt.IsDeleted = 0
    ORDER BY lt.TypeName;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_GetByType(IN p_LookupTypeId INT UNSIGNED)
BEGIN
    SELECT LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, IsDeleted
    FROM LookupValues
    WHERE LookupTypeId = p_LookupTypeId
    ORDER BY OrderNo, ValueName;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Add(
    IN p_TypeCode         VARCHAR(50),
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupTypes WHERE TypeCode = p_TypeCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A lookup type with this code already exists.' AS Message, NULL AS LookupTypeId;
    ELSE
        INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
        VALUES (p_TypeCode, p_TypeName, p_Description, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup type created.' AS Message, LAST_INSERT_ID() AS LookupTypeId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Update(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    UPDATE LookupTypes
    SET TypeName = p_TypeName, Description = p_Description, UpdatedBy = p_SuperAdminUserId
    WHERE LookupTypeId = p_LookupTypeId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Lookup type not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Lookup type updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Add(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_ValueCode        VARCHAR(50),
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupValues
        WHERE LookupTypeId = p_LookupTypeId AND ValueCode = p_ValueCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A value with this code already exists for this type.' AS Message, NULL AS LookupValueId;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = p_LookupTypeId;
        END IF;

        INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, CreatedBy)
        VALUES (p_LookupTypeId, p_ValueCode, p_ValueName, p_Description, p_OrderNo, p_IsDefault, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup value created.' AS Message, LAST_INSERT_ID() AS LookupValueId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Update(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_LookupTypeId INT UNSIGNED;
    SELECT LookupTypeId INTO v_LookupTypeId FROM LookupValues WHERE LookupValueId = p_LookupValueId AND IsDeleted = 0;

    IF v_LookupTypeId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = v_LookupTypeId;
        END IF;

        UPDATE LookupValues
        SET ValueName = p_ValueName, Description = p_Description, OrderNo = p_OrderNo,
            IsDefault = p_IsDefault, UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, 'Lookup value updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_SetActive(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_IsActive         TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsSystemValue TINYINT(1);
    SELECT IsSystemValue INTO v_IsSystemValue FROM LookupValues WHERE LookupValueId = p_LookupValueId;

    IF v_IsSystemValue IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSEIF v_IsSystemValue = 1 AND p_IsActive = 0 THEN
        SELECT 0 AS IsSuccess, 'System values cannot be deactivated — they are referenced by platform logic.' AS Message;
    ELSE
        UPDATE LookupValues
        SET IsDeleted = IF(p_IsActive = 1, 0, 1),
            DeletedAt = IF(p_IsActive = 1, NULL, NOW()),
            DeletedBy = IF(p_IsActive = 1, NULL, p_SuperAdminUserId),
            UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, IF(p_IsActive = 1, 'Lookup value reactivated.', 'Lookup value deactivated.') AS Message;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- END OF PATCH
-- ============================================================

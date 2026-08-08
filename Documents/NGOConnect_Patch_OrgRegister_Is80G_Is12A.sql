-- ============================================================
-- NGOConnect Patch: Org_Register — add Is80GEligible / Is12AEligible
-- Created : 2026-07-18
-- Apply to: local DB → Railway staging → Railway production
-- Safe    : DROP + CREATE is idempotent
-- ============================================================

DROP PROCEDURE IF EXISTS Org_Register;

DELIMITER //

CREATE PROCEDURE Org_Register(
    IN p_UserId            INT UNSIGNED,
    IN p_OrgName           VARCHAR(200),
    IN p_RegistrationNo    VARCHAR(100),
    IN p_OrgTypeLkpId      INT UNSIGNED,
    IN p_Category          VARCHAR(100),
    IN p_ContactPerson     VARCHAR(100),
    IN p_About             TEXT,
    IN p_Mission           TEXT,
    IN p_Vision            TEXT,
    IN p_LogoUrl           VARCHAR(500),
    IN p_ContactEmail      VARCHAR(150),
    IN p_ContactPhone      VARCHAR(20),
    IN p_Website           VARCHAR(255),
    IN p_AddressLine1      VARCHAR(200),
    IN p_AddressLine2      VARCHAR(200),
    IN p_City              VARCHAR(100),
    IN p_State             VARCHAR(100),
    IN p_Pincode           VARCHAR(20),
    IN p_Country           VARCHAR(100),
    IN p_Is80GEligible     TINYINT(1),
    IN p_Is12AEligible     TINYINT(1)
)
BEGIN
    DECLARE v_Exists       INT DEFAULT 0;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_RoleLkpId    INT UNSIGNED;
    DECLARE v_MemStatLkpId INT UNSIGNED;
    DECLARE v_OrgId        INT UNSIGNED;

    SELECT COUNT(*) INTO v_Exists FROM Organisations WHERE RegNumber = p_RegistrationNo AND IsDeleted = 0;
    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'Registration number already exists.' AS Message, NULL AS OrgId;
    ELSE
        SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;
        SELECT LookupValueId INTO v_RoleLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1;
        SELECT LookupValueId INTO v_MemStatLkpId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        INSERT INTO Organisations
            (OrgName, ContactPerson, OrgTypeLkpId, RegNumber, Category, About, Mission, Vision,
             LogoUrl, ContactEmail, ContactPhone, Website,
             AddressLine1, AddressLine2, City, State, Pincode, Country,
             Is80GEligible, Is12AEligible, StatusLkpId, CreatedBy)
        VALUES
            (p_OrgName, p_ContactPerson, p_OrgTypeLkpId, p_RegistrationNo, p_Category,
             p_About, p_Mission, p_Vision, p_LogoUrl, p_ContactEmail, p_ContactPhone, p_Website,
             p_AddressLine1, p_AddressLine2, p_City, p_State, p_Pincode,
             COALESCE(p_Country, 'India'),
             IFNULL(p_Is80GEligible, 0), IFNULL(p_Is12AEligible, 0),
             v_StatusLkpId, p_UserId);

        SET v_OrgId = LAST_INSERT_ID();

        INSERT INTO OrgMembers
            (OrgId, UserId, RoleLkpId, StatusLkpId, CanPost, CanComment, CanCommunityPost, MaxPostsPerDay, JoinedAt, CreatedBy)
        VALUES
            (v_OrgId, p_UserId, v_RoleLkpId, v_MemStatLkpId, 1, 1, 1, 50, NOW(), p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation registered successfully.' AS Message, v_OrgId AS OrgId;
    END IF;
END //

DELIMITER ;

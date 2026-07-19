-- ============================================================================
-- Patch: Org_Update + Org_Resubmit — add Is80GEligible / Is12AEligible
-- Date: 2026-07-19
-- Apply to: local DB → Railway staging → Railway production
--
-- Context: Org_Register already accepts p_Is80GEligible/p_Is12AEligible (added
-- 2026-07-18). Org_Update (Edit Organisation) and Org_Resubmit (founder resubmits
-- after rejection) did not — so a founder could set these flags at registration
-- but never change them afterward. This patch closes that gap on both SPs.
--
-- Org_Update: uses the existing COALESCE pattern — passing NULL leaves the
-- current DB value untouched (partial-update semantics, matches every other
-- field on this SP).
--
-- Org_Resubmit: full re-declaration on every call (no COALESCE), matching how
-- every other field on this SP already behaves — resubmission replaces the
-- entire org profile snapshot, not a partial patch.
--
-- Requires: Organisations.Is80GEligible / Is12AEligible columns must already
-- exist. If NGOConnect_Patch_SuperAdminOrgDetail_TaxEligibility.sql (2026-07-19)
-- has already been run on this DB, they do. If not, run that patch first — it
-- adds the columns idempotently via the _ngo_add_col helper.
-- ============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Org_Update //

CREATE PROCEDURE Org_Update(
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
    IN p_Country       VARCHAR(100),
    IN p_Is80GEligible TINYINT(1),
    IN p_Is12AEligible TINYINT(1)
)
BEGIN
    UPDATE Organisations SET
        OrgName       = COALESCE(p_OrgName,       OrgName),
        Category      = COALESCE(p_Category,      Category),
        ContactPerson = COALESCE(p_ContactPerson, ContactPerson),
        About         = COALESCE(p_About,         About),
        Mission       = COALESCE(p_Mission,       Mission),
        Vision        = COALESCE(p_Vision,        Vision),
        LogoUrl       = COALESCE(p_LogoUrl,       LogoUrl),
        ContactEmail  = COALESCE(p_ContactEmail,  ContactEmail),
        ContactPhone  = COALESCE(p_ContactPhone,  ContactPhone),
        Website       = COALESCE(p_Website,       Website),
        AddressLine1  = COALESCE(p_AddressLine1,  AddressLine1),
        AddressLine2  = COALESCE(p_AddressLine2,  AddressLine2),
        City          = COALESCE(p_City,          City),
        State         = COALESCE(p_State,         State),
        Pincode       = COALESCE(p_Pincode,       Pincode),
        Country       = COALESCE(p_Country,       Country),
        Is80GEligible = COALESCE(p_Is80GEligible, Is80GEligible),
        Is12AEligible = COALESCE(p_Is12AEligible, Is12AEligible),
        UpdatedBy     = p_UserId,
        UpdatedAt     = NOW()
    WHERE OrgId = p_OrgId AND IsDeleted = 0;
    SELECT 1 AS IsSuccess, 'Organisation updated.' AS Message;
END //

DROP PROCEDURE IF EXISTS Org_Resubmit //

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
    IN p_Country       VARCHAR(100),
    IN p_Is80GEligible TINYINT(1),
    IN p_Is12AEligible TINYINT(1)
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
            Is80GEligible = p_Is80GEligible, Is12AEligible = p_Is12AEligible,
            StatusLkpId = v_PendingId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

DELIMITER ;

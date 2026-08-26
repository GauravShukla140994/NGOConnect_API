-- ============================================================
-- Patch: Org RegistrationDate exposure
-- Adds SuperAdmin_Org_GetDetail.RegistrationDate to the SELECT list
-- and a new p_RegistrationDate param + SET clause to
-- SuperAdmin_Org_UpdateProfile.
--
-- Organisations.RegistrationDate (DATE NULL) already exists on the
-- table — this patch only changes the two stored procedures.
-- Safe to re-run.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetDetail //
CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.IsNonRegistered, o.RegistrationDate, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.Is80GEligible, o.Is12AEligible,
        o.CanCreateRecurring, o.CanCreateFlexible, o.OrgMaxVolunteers,
        -- v5.5: OrgTypeLkpId added — needed so the Super Admin website can
        -- pre-select the org type dropdown when editing an org's profile
        -- (only the resolved name, tv.ValueName, was returned before).
        o.OrgTypeLkpId,
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
          WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
            AND sv2.ValueCode = 'APPROVED') AS MemberCount
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    LEFT JOIN OrgMembers founder ON founder.OrgId = o.OrgId AND founder.IsDeleted = 0
        AND founder.RoleLkpId = (
            SELECT LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
    LEFT JOIN Users u ON founder.UserId = u.UserId
    LEFT JOIN UserProfiles fp ON founder.UserId = fp.UserId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_UpdateProfile //
CREATE PROCEDURE SuperAdmin_Org_UpdateProfile(
    IN p_OrgId           INT UNSIGNED,
    IN p_OrgName         VARCHAR(200),
    IN p_OrgTypeLkpId    INT UNSIGNED,
    IN p_RegNumber       VARCHAR(100),
    IN p_RegistrationDate DATE,          -- v5.1: date org was officially registered with govt (nullable)
    IN p_Category        VARCHAR(100),
    IN p_ContactPerson   VARCHAR(100),
    IN p_About           TEXT,
    IN p_Mission         TEXT,
    IN p_Vision          TEXT,
    IN p_LogoUrl         VARCHAR(500),
    IN p_ContactEmail    VARCHAR(150),
    IN p_ContactPhone    VARCHAR(20),
    IN p_Website         VARCHAR(255),
    IN p_AddressLine1    VARCHAR(200),
    IN p_AddressLine2    VARCHAR(200),
    IN p_City            VARCHAR(100),
    IN p_State           VARCHAR(100),
    IN p_Pincode         VARCHAR(20),
    IN p_Country         VARCHAR(100),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Error VARCHAR(500) DEFAULT NULL;

    IF NOT EXISTS (SELECT 1 FROM Organisations WHERE OrgId = p_OrgId AND IsDeleted = 0) THEN
        SET v_Error = 'Organisation not found.';
    ELSEIF p_OrgName IS NULL OR p_OrgName = '' THEN
        SET v_Error = 'Organisation name is required.';
    ELSEIF p_RegNumber IS NULL OR p_RegNumber = '' THEN
        SET v_Error = 'Organisation registration number is required.';
    ELSEIF p_OrgTypeLkpId IS NULL THEN
        SET v_Error = 'Organisation type is required.';
    ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE RegNumber = p_RegNumber AND IsDeleted = 0 AND OrgId != p_OrgId) THEN
        SET v_Error = 'Another organisation is already using this registration number.';
    ELSEIF EXISTS (SELECT 1 FROM Organisations WHERE LOWER(TRIM(OrgName)) = LOWER(TRIM(p_OrgName)) AND IsDeleted = 0 AND OrgId != p_OrgId) THEN
        SET v_Error = 'Another organisation is already using this name.';
    END IF;

    IF v_Error IS NOT NULL THEN
        SELECT 0 AS IsSuccess, v_Error AS Message, NULL AS OrgId;
    ELSE
        UPDATE Organisations
        SET OrgName       = p_OrgName,
            OrgTypeLkpId   = p_OrgTypeLkpId,
            RegNumber      = p_RegNumber,
            RegistrationDate = p_RegistrationDate,
            Category       = IFNULL(NULLIF(p_Category, ''), 'General'),
            ContactPerson  = p_ContactPerson,
            About          = p_About,
            Mission        = p_Mission,
            Vision         = p_Vision,
            LogoUrl        = p_LogoUrl,
            ContactEmail   = p_ContactEmail,
            ContactPhone   = p_ContactPhone,
            Website        = p_Website,
            AddressLine1   = p_AddressLine1,
            AddressLine2   = p_AddressLine2,
            City           = p_City,
            State          = p_State,
            Pincode        = p_Pincode,
            Country        = IFNULL(NULLIF(p_Country, ''), 'India'),
            UpdatedBy      = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Organisation profile updated.' AS Message, p_OrgId AS OrgId;
    END IF;
END //

DELIMITER ;

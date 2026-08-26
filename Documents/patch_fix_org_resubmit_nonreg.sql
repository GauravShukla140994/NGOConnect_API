-- ============================================================
-- Patch: Fix Org_Resubmit — add IsNonRegistered + RegNumber
-- Problem: Org_Resubmit SP did not include p_IsNonRegistered
--          or p_RegistrationNo, so founders could never correct
--          registration status when fixing a rejected org.
-- Affected SP: Org_Resubmit (modified)
-- Author : NGO Connect
-- Date   : 2026-08-26
-- ============================================================

USE ngoconnect;
DELIMITER //

DROP PROCEDURE IF EXISTS Org_Resubmit //

-- v5.1 MODIFIED: +p_RegistrationNo, +p_IsNonRegistered so founder can
--                correct non-registered status during Fix & Resubmit.
CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId           INT UNSIGNED,
    IN p_UserId          INT UNSIGNED,
    IN p_OrgName         VARCHAR(200),
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
    IN p_RegistrationNo  VARCHAR(100),
    IN p_IsNonRegistered TINYINT(1),
    IN p_Is80GEligible   TINYINT(1),
    IN p_Is12AEligible   TINYINT(1)
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
            OrgName        = p_OrgName,
            Category       = p_Category,
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
            Country        = p_Country,
            -- Allow founder to correct registration status on resubmit
            IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            RegNumber       = IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL,
                                 NULLIF(TRIM(COALESCE(p_RegistrationNo, '')), '')),
            Is80GEligible  = p_Is80GEligible,
            Is12AEligible  = p_Is12AEligible,
            StatusLkpId    = v_PendingId,
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

        -- Notify Super Admins
        INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
        SELECT u.UserId, 'ORG_RESUBMIT',
               CONCAT('Organisation resubmitted: ', p_OrgName),
               'A rejected organisation has been updated and resubmitted for review.',
               p_OrgId, 'ORGANISATION'
        FROM Users u WHERE u.Role = 'SUPER_ADMIN' AND u.IsDeleted = 0;

        SELECT 1 AS IsSuccess, 'Organisation resubmitted successfully.' AS Message;
    END IF;
END //

DELIMITER ;

INSERT INTO SchemaVersions (Version, Description, AppliedAt)
VALUES ('5.1.9', 'Fix Org_Resubmit — add p_RegistrationNo + p_IsNonRegistered', NOW());

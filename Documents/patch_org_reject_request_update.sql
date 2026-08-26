-- ============================================================
-- Patch: Reject / Request-Update on already-APPROVED orgs
-- - Adds ORG_STATUS lookup values NEEDS_UPDATE, RESUBMITTED
-- - SuperAdmin_Org_Approve: now also allows re-approving RESUBMITTED
-- - SuperAdmin_Org_Reject: now also allows APPROVED/NEEDS_UPDATE/RESUBMITTED,
--   cascade-cancels live projects when rejecting from APPROVED
-- - NEW SuperAdmin_Org_RequestUpdate: soft alternative to Reject for an
--   APPROVED org (org -> NEEDS_UPDATE, projects untouched)
-- - Org_Resubmit: now also allows resubmitting from NEEDS_UPDATE -> RESUBMITTED
--   (previously REJECTED -> PENDING only)
-- Safe to re-run.
-- ============================================================

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'NEEDS_UPDATE', 'Needs Update', 6, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS';
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'RESUBMITTED', 'Resubmitted', 7, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_STATUS';

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_Approve //
CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsNonRegistered  TINYINT(1),    -- 0 = registered, 1 = non-registered
    IN p_Remarks          VARCHAR(1000)  -- optional admin remarks shown to org admins
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;
    DECLARE v_Reason          VARCHAR(1100);
    DECLARE v_NotifBody       VARCHAR(1200);

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW', 'RESUBMITTED') THEN
        -- v5.2: RESUBMITTED added — org resubmitted after a Request-Update on an
        -- already-approved org (see SuperAdmin_Org_RequestUpdate / Org_Resubmit).
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        -- Build history reason: combine non-registered flag + optional remarks
        SET v_Reason = IF(v_CurrentCode = 'RESUBMITTED',
                           'Re-approved after resubmission',
                           IF(p_IsNonRegistered = 1, 'Approved as non-registered organisation', 'Approved'));
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_Reason = CONCAT(v_Reason, '. ', TRIM(p_Remarks));
        END IF;

        -- Build notification body
        SET v_NotifBody = 'Congratulations — your organisation is now live on Ripple Hub.';
        IF p_Remarks IS NOT NULL AND TRIM(p_Remarks) != '' THEN
            SET v_NotifBody = CONCAT(v_NotifBody, ' Note from admin: ', TRIM(p_Remarks));
        END IF;

        UPDATE Organisations
        SET StatusLkpId     = v_ApprovedId,
            IsNonRegistered = IFNULL(p_IsNonRegistered, 0),
            StatusUpdatedAt = NOW(),
            StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, v_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved', v_NotifBody, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_Reject //
CREATE PROCEDURE SuperAdmin_Org_Reject(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_RejectedId      INT UNSIGNED;
    DECLARE v_CancelledId     INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    -- v5.2: rejection is now also allowed from APPROVED (previously blocked) so
    -- Super Admin can revoke an already-live org. When coming from APPROVED, the
    -- org's active/upcoming/draft projects are cascade-cancelled below — see
    -- DOCUMENTATION_GUIDELINES.md 2026-08-26 "Reject an approved org" entry.
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW', 'APPROVED', 'NEEDS_UPDATE', 'RESUBMITTED') THEN
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

        -- v5.2: cascade-cancel this org's live projects when it was previously
        -- APPROVED (a PENDING/UNDER_REVIEW/NEEDS_UPDATE/RESUBMITTED org cannot
        -- have had approved projects, since project creation is gated on
        -- ORG_STATUS = APPROVED).
        IF v_CurrentCode = 'APPROVED' THEN
            SELECT LookupValueId INTO v_CancelledId FROM LookupValues lv
                JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'CANCELLED' LIMIT 1;

            UPDATE Projects p
            JOIN LookupValues sv2 ON p.StatusLkpId = sv2.LookupValueId
            SET p.StatusLkpId  = v_CancelledId,
                p.CancelledAt  = NOW(),
                p.CancelledBy  = p_SuperAdminUserId,
                p.CancelReason = 'Organisation rejected by Super Admin'
            WHERE p.OrgId = p_OrgId AND p.IsDeleted = 0
              AND sv2.ValueCode IN ('DRAFT', 'ACTIVE', 'UPCOMING');
        END IF;

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

-- v5.2 NEW: soft version of Reject for an already-APPROVED org — asks the founder
-- to fix something without a full reject/re-review cycle. Org drops out of public
-- listings while NEEDS_UPDATE (StatusLkpId gates visibility for orgs), same as
-- REJECTED, but Org_Resubmit routes it to RESUBMITTED (not back through PENDING)
-- so Super Admin can re-approve directly via SuperAdmin_Org_Approve.
DROP PROCEDURE IF EXISTS SuperAdmin_Org_RequestUpdate //
CREATE PROCEDURE SuperAdmin_Org_RequestUpdate(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_NeedsUpdateId   INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'APPROVED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot request update — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A reason is required.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_NeedsUpdateId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'NEEDS_UPDATE' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_NeedsUpdateId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_NeedsUpdateId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_UPDATE_REQUIRED', 'Update required for your organisation',
                    p_Reason, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Update requested from organisation.' AS Message;
    END IF;
END //


DROP PROCEDURE IF EXISTS Org_Resubmit //
CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId          INT UNSIGNED,
    IN p_UserId         INT UNSIGNED,
    IN p_OrgName        VARCHAR(200),
    IN p_Category       VARCHAR(100),
    IN p_ContactPerson  VARCHAR(100),
    IN p_About          TEXT,
    IN p_Mission        TEXT,
    IN p_Vision         TEXT,
    IN p_LogoUrl        VARCHAR(500),
    IN p_ContactEmail   VARCHAR(150),
    IN p_ContactPhone   VARCHAR(20),
    IN p_Website        VARCHAR(255),
    IN p_AddressLine1   VARCHAR(200),
    IN p_AddressLine2   VARCHAR(200),
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Pincode        VARCHAR(20),
    IN p_Country        VARCHAR(100),
    IN p_RegistrationNo VARCHAR(100),
    IN p_IsNonRegistered  TINYINT(1),
    IN p_Is80GEligible    TINYINT(1),
    IN p_Is12AEligible    TINYINT(1),
    IN p_RegistrationDate DATE                                    -- NULL when IsNonRegistered = 1
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_TargetId        INT UNSIGNED;
    DECLARE v_TargetCode      VARCHAR(50);
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
    ELSEIF v_CurrentCode NOT IN ('REJECTED', 'NEEDS_UPDATE') THEN
        SELECT 0 AS IsSuccess, 'Only a rejected organisation, or one flagged as needing an update, can be resubmitted.' AS Message;
    ELSE
        -- v5.2: REJECTED goes back through full review (PENDING); NEEDS_UPDATE
        -- (raised via SuperAdmin_Org_RequestUpdate on an already-approved org)
        -- goes to RESUBMITTED so Super Admin can re-approve directly without
        -- re-running the full PENDING/UNDER_REVIEW review flow.
        SET v_TargetCode = IF(v_CurrentCode = 'NEEDS_UPDATE', 'RESUBMITTED', 'PENDING');

        SELECT LookupValueId INTO v_TargetId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = v_TargetCode LIMIT 1;

        UPDATE Organisations SET
            OrgName = p_OrgName, Category = p_Category, ContactPerson = p_ContactPerson,
            About = p_About, Mission = p_Mission, Vision = p_Vision, LogoUrl = p_LogoUrl,
            ContactEmail = p_ContactEmail, ContactPhone = p_ContactPhone, Website = p_Website,
            AddressLine1 = p_AddressLine1, AddressLine2 = p_AddressLine2, City = p_City,
            State = p_State, Pincode = p_Pincode, Country = p_Country,
            -- Allow founder to correct registration status on resubmit
            IsNonRegistered  = IFNULL(p_IsNonRegistered, 0),
            RegNumber        = IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL,
                                  NULLIF(TRIM(COALESCE(p_RegistrationNo, '')), '')),
            RegistrationDate = IF(IFNULL(p_IsNonRegistered, 0) = 1, NULL, p_RegistrationDate),
            Is80GEligible = p_Is80GEligible, Is12AEligible = p_Is12AEligible,
            StatusLkpId = v_TargetId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_TargetId,
                IF(v_CurrentCode = 'NEEDS_UPDATE', 'Resubmitted by founder after update request', 'Resubmitted by founder after rejection'),
                'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

DELIMITER ;

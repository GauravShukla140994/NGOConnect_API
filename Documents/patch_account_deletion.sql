-- ─────────────────────────────────────────────────────────────────────────────
-- patch_account_deletion.sql
-- Feature: Account Deletion (Google Play + App Store compliance)
--
-- SP: User_RequestAccountDeletion(p_UserId)
--
-- Logic:
--   1. Block if user is the SOLE FOUNDER of any APPROVED, non-deleted org.
--      (Must transfer/close the org before deleting account.)
--   2. Otherwise: soft-delete the Users row + revoke all RefreshTokens.
--
-- No table/column changes — uses existing IsDeleted/DeletedAt/DeletedBy on Users
-- and IsRevoked/RevokedAt on RefreshTokens.
--
-- Safe to re-run (DROP + CREATE is idempotent).
-- Apply to: local → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS User_RequestAccountDeletion //
CREATE PROCEDURE User_RequestAccountDeletion(IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_SoleFounderOrgName VARCHAR(200) DEFAULT NULL;

    -- Block deletion if the user is the ONLY FOUNDER of any active (APPROVED) org.
    -- If they have co-founders, the org continues fine — only block when they're the last one.
    SELECT o.OrgName INTO v_SoleFounderOrgName
    FROM OrgMembers om
    JOIN LookupValues rv ON om.RoleLkpId    = rv.LookupValueId
    JOIN LookupTypes  rt ON rv.LookupTypeId = rt.LookupTypeId
    JOIN Organisations o ON om.OrgId        = o.OrgId
    JOIN LookupValues sv ON o.StatusLkpId   = sv.LookupValueId
    WHERE om.UserId     = p_UserId
      AND om.IsDeleted  = 0
      AND rt.TypeCode   = 'MEMBER_ROLE'
      AND rv.ValueCode  = 'FOUNDER'
      AND o.IsDeleted   = 0
      AND sv.ValueCode  = 'APPROVED'
      -- Only block if there is NO other active FOUNDER in this org
      AND NOT EXISTS (
          SELECT 1
          FROM OrgMembers om2
          JOIN LookupValues rv2 ON om2.RoleLkpId    = rv2.LookupValueId
          JOIN LookupTypes  rt2 ON rv2.LookupTypeId = rt2.LookupTypeId
          WHERE om2.OrgId    = om.OrgId
            AND om2.UserId  != p_UserId
            AND om2.IsDeleted = 0
            AND rt2.TypeCode  = 'MEMBER_ROLE'
            AND rv2.ValueCode = 'FOUNDER'
      )
    LIMIT 1;

    IF v_SoleFounderOrgName IS NOT NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('You are the only Founder of "', v_SoleFounderOrgName,
                      '". Please transfer ownership or close the organisation before deleting your account.') AS Message,
               'SOLE_FOUNDER' AS ErrorCode;
    ELSE
        -- Soft-delete the user account
        UPDATE Users
        SET IsDeleted = 1,
            DeletedAt = NOW(),
            DeletedBy = p_UserId
        WHERE UserId    = p_UserId
          AND IsDeleted = 0;

        -- Revoke all active refresh tokens so existing sessions are immediately invalidated
        UPDATE RefreshTokens
        SET IsRevoked = 1,
            RevokedAt = NOW()
        WHERE UserId    = p_UserId
          AND IsRevoked = 0;

        SELECT 1 AS IsSuccess,
               'Your account has been deleted. We hope to see you again someday.' AS Message,
               NULL AS ErrorCode;
    END IF;
END //

DELIMITER ;

SELECT 'patch_account_deletion applied successfully.' AS Status;

-- Verify:
-- CALL User_RequestAccountDeletion(<userId_with_no_sole_founder_org>);
-- Expected: IsSuccess=1, account soft-deleted, tokens revoked.
-- CALL User_RequestAccountDeletion(<sole_founder_userId>);
-- Expected: IsSuccess=0, ErrorCode=SOLE_FOUNDER.

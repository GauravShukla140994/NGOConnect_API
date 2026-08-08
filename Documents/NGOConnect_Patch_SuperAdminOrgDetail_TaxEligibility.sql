-- ============================================================================
-- Patch: Organisations.Is80GEligible/Is12AEligible columns + SuperAdmin_Org_GetDetail
-- Date: 2026-07-19
--
-- Root cause (2-part):
-- 1. Organisations.Is80GEligible / Is12AEligible have been in the setup SQL's
--    CREATE TABLE definition since v4.0, so any DB built fresh from setup SQL
--    has them. But no ALTER TABLE patch was ever written to retrofit them onto
--    an already-running DB — so on a DB created before that column was added,
--    the columns simply don't exist, even though Org_Register (INSERT) and
--    now SuperAdmin_Org_GetDetail (SELECT) both reference them. Confirmed via
--    `CALL SuperAdmin_Org_GetDetail(55)` -> Error 1054: Unknown column
--    'o.Is80GEligible' in 'field list'.
--    This means Org_Register's INSERT has likely also been silently failing
--    with the same "Unknown column" error on this DB for any org registration
--    since that SP was updated to include these columns.
-- 2. SuperAdmin_Org_GetDetail never selected these two columns even where they
--    DO exist — so the Super Admin Organisations drawer had no data to show
--    for 80G/12A status regardless of what the founder submitted.
--
-- Fix: idempotent ALTER TABLE (checks INFORMATION_SCHEMA first, safe to re-run
-- and safe on DBs that already have the columns) + SELECT the two columns in
-- SuperAdmin_Org_GetDetail.
-- ============================================================================

-- ── 1. Add missing columns if not already present (idempotent) ──────────────
DROP PROCEDURE IF EXISTS _ngo_add_col;
DELIMITER //
CREATE PROCEDURE _ngo_add_col(IN p_tbl VARCHAR(64), IN p_col VARCHAR(64), IN p_def TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = p_tbl
          AND COLUMN_NAME  = p_col
    ) THEN
        SET @_sql = CONCAT('ALTER TABLE `', p_tbl, '` ADD COLUMN `', p_col, '` ', p_def);
        PREPARE _st FROM @_sql;
        EXECUTE _st;
        DEALLOCATE PREPARE _st;
    END IF;
END //
DELIMITER ;

CALL _ngo_add_col('Organisations', 'Is80GEligible', 'TINYINT(1) NOT NULL DEFAULT 0');
CALL _ngo_add_col('Organisations', 'Is12AEligible', 'TINYINT(1) NOT NULL DEFAULT 0');

DROP PROCEDURE IF EXISTS _ngo_add_col;

-- ── 2. SuperAdmin_Org_GetDetail — add Is80GEligible / Is12AEligible to SELECT ─

DELIMITER //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_GetDetail //

CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.Is80GEligible, o.Is12AEligible,
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

DELIMITER ;

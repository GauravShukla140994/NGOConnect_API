-- ============================================================
-- NGO Connect — Patch: User Document Management SPs
-- Version : v4.3 patch
-- Date    : 2026-07-08
-- Purpose : User_UploadDocument  — save doc metadata to UserDocuments
--           User_GetDocuments    — fetch user's saved documents
--           User_DeleteDocument  — soft-delete a document
-- Apply   : Run against NGOConnect database.
-- ============================================================

-- ── Update DOCUMENT_TYPE_USER lookup values to universal categories ─────────
-- Replaces India-specific types (Aadhaar, PAN, Voter ID) with globally
-- applicable categories: Photo ID, Address Proof, Passport, Driving License.
--
-- Safe to run on fresh DBs (INSERT ... ON DUPLICATE KEY UPDATE) and on DBs
-- that have already run the old seeds (it will overwrite the rows in-place).
-- No FK violations because UserDocuments rows inherit the LookupValueId — the
-- ID values themselves do not change, only ValueCode/ValueName/OrderNo.
--
-- Steps:
--   1. Remove India-specific entries (AADHAAR, PAN, VOTER_ID) — set IsActive=0
--      so existing rows are preserved for FK integrity but hidden from dropdowns.
--   2. Upsert the five universal entries.

SET @DocTypeId = (SELECT LookupTypeId FROM LookupTypes WHERE TypeCode = 'DOCUMENT_TYPE_USER' LIMIT 1);

-- Soft-delete India-specific types (preserves FK integrity, hides from UI)
UPDATE LookupValues
SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = 1
WHERE  LookupTypeId = @DocTypeId
  AND  ValueCode IN ('AADHAAR', 'PAN', 'VOTER_ID')
  AND  IsDeleted = 0;

-- Upsert universal types
-- UNIQUE KEY is on (LookupTypeId, ValueCode, IsDeleted) so ON DUPLICATE KEY fires
-- only when the same TypeCode+ValueCode+IsDeleted=0 already exists.
INSERT INTO LookupValues
    (LookupTypeId, ValueCode,     ValueName,                Description,                                                              IsDefault, IsSystemValue, OrderNo, CreatedBy)
VALUES
    (@DocTypeId,  'PHOTO_ID',    'Government Photo ID',    'Any govt-issued photo ID — national card, passport or driver licence',   1, 1, 1, 1),
    (@DocTypeId,  'ADDR_PROOF',  'Address Proof',          'Utility bill, bank statement, or government letter showing your address', 0, 1, 2, 1),
    (@DocTypeId,  'PASSPORT',    'Passport',               'International travel document',                                          0, 1, 3, 1),
    (@DocTypeId,  'DRIVING_LIC', 'Driving License',        'Government-issued driving licence',                                      0, 1, 4, 1),
    (@DocTypeId,  'OTHER',       'Other Document',         'Any other supporting document',                                          0, 1, 5, 1)
ON DUPLICATE KEY UPDATE
    ValueName     = VALUES(ValueName),
    Description   = VALUES(Description),
    IsDefault     = VALUES(IsDefault),
    IsDeleted     = 0,
    DeletedAt     = NULL,
    OrderNo       = VALUES(OrderNo);

DELIMITER //

-- ── User_UploadDocument ─────────────────────────────────────────────────────
-- Upserts: if a doc of the same type already exists for the user,
-- replace it (soft-delete old + insert new). Keeps only one doc per type.
DROP PROCEDURE IF EXISTS User_UploadDocument //
CREATE PROCEDURE User_UploadDocument(
    IN p_UserId            INT UNSIGNED,
    IN p_DocumentTypeLkpId INT UNSIGNED,
    IN p_FileUrl           VARCHAR(500),
    IN p_FileName          VARCHAR(255),
    IN p_FileSizeKb        INT UNSIGNED
)
BEGIN
    -- Soft-delete any existing doc of the same type for this user
    UPDATE UserDocuments
    SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId, UpdatedBy = p_UserId
    WHERE  UserId = p_UserId
      AND  DocumentTypeLkpId = p_DocumentTypeLkpId
      AND  IsDeleted = 0;

    -- Insert new document
    INSERT INTO UserDocuments
        (UserId, DocumentTypeLkpId, FileUrl, FileName, FileSizeKb, CreatedBy, UpdatedBy)
    VALUES
        (p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb, p_UserId, p_UserId);

    SELECT 1 AS IsSuccess, 'Document saved.' AS Message, LAST_INSERT_ID() AS UserDocumentId;
END //

-- ── User_GetDocuments ───────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetDocuments //
CREATE PROCEDURE User_GetDocuments(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ud.UserDocumentId,
        ud.UserId,
        ud.DocumentTypeLkpId,
        lv.ValueCode   AS DocTypeCode,
        lv.ValueName   AS DocTypeName,
        ud.FileUrl,
        ud.FileName,
        ud.FileSizeKb,
        ud.IsVerified,
        ud.CreatedAt   AS UploadedAt
    FROM UserDocuments ud
    JOIN LookupValues  lv ON ud.DocumentTypeLkpId = lv.LookupValueId
    WHERE ud.UserId    = p_UserId
      AND ud.IsDeleted = 0
    ORDER BY lv.OrderNo ASC;
END //

-- ── User_DeleteDocument ─────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_DeleteDocument //
CREATE PROCEDURE User_DeleteDocument(
    IN p_UserDocumentId INT UNSIGNED,
    IN p_UserId         INT UNSIGNED
)
BEGIN
    UPDATE UserDocuments
    SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId, UpdatedBy = p_UserId
    WHERE  UserDocumentId = p_UserDocumentId
      AND  UserId = p_UserId   -- security: user can only delete own docs
      AND  IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document removed.' AS Message;
    END IF;
END //

DELIMITER ;

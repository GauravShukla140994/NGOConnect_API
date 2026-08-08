-- ─────────────────────────────────────────────────────────────────────────────
-- NGOConnect Patch: Add PHOTO_ID to DOCUMENT_TYPE_USER lookup
-- Date   : 2026-07-17
-- Reason : DocumentUploadSection uses code 'PHOTO_ID' for the "Government Photo
--          ID" upload slot. This code was missing from the DOCUMENT_TYPE_USER
--          LookupValues, causing getLkpId('PHOTO_ID') to return 0, which blocked
--          every Government Photo ID upload with "Could not resolve document type".
-- Apply  : Run once on Railway staging, then Railway production.
--          Safe to run on an already-patched DB — INSERT IGNORE skips duplicates.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault, CreatedBy)
SELECT LookupTypeId, 'PHOTO_ID', 'Government Photo ID', 0, 1, 0, 1
FROM   LookupTypes
WHERE  TypeCode = 'DOCUMENT_TYPE_USER'
LIMIT  1;

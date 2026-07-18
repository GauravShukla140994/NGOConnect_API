-- ============================================================
-- NGOConnect Patch: Add Org_GetDocuments SP
-- Created : 2026-07-18
-- Apply to: local DB → Railway staging → Railway production
-- Safe    : DROP + CREATE is idempotent
-- Purpose : Allows org admins (founder/admin role) to list
--           their own organisation's uploaded documents.
--           Endpoint: GET /api/v1/org/{orgId}/documents
-- ============================================================

DROP PROCEDURE IF EXISTS Org_GetDocuments;

DELIMITER //

CREATE PROCEDURE Org_GetDocuments(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT od.OrgDocumentId, od.DocumentTypeLkpId, dt.ValueName AS DocumentType,
           od.FileUrl, od.FileName, od.IsVerified, od.VerifiedAt, od.CreatedAt
    FROM OrgDocuments od
    LEFT JOIN LookupValues dt ON od.DocumentTypeLkpId = dt.LookupValueId
    WHERE od.OrgId = p_OrgId AND od.IsDeleted = 0
    ORDER BY od.CreatedAt ASC;
END //

DELIMITER ;

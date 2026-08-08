-- ============================================================
-- NGOConnect Diagnostic: Check Projects table + SPs
-- Run each section separately in MySQL Workbench.
-- ============================================================

-- SECTION 1: Check which columns exist in Projects table
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME   = 'Projects'
ORDER BY ORDINAL_POSITION;

-- SECTION 2: Check which of the 3 new columns are missing
SELECT
    MAX(CASE WHEN COLUMN_NAME = 'RequiresApproval' THEN 'EXISTS' ELSE NULL END) AS RequiresApproval,
    MAX(CASE WHEN COLUMN_NAME = 'GenderRestriction' THEN 'EXISTS' ELSE NULL END) AS GenderRestriction,
    MAX(CASE WHEN COLUMN_NAME = 'CoverImageUrl' THEN 'EXISTS' ELSE NULL END)     AS CoverImageUrl
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME   = 'Projects';

-- SECTION 3: Check that the SP was recreated (should show the new params)
SHOW CREATE PROCEDURE Project_Create;

-- SECTION 4: Check lookup seeds are present
SELECT lt.TypeCode, lv.ValueCode, lv.LookupValueId
FROM LookupValues lv
JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
WHERE lt.TypeCode IN ('PROJECT_TYPE', 'PROJECT_STATUS', 'PROJECT_JOIN_TYPE', 'LOCATION_TYPE')
ORDER BY lt.TypeCode, lv.OrderNo;

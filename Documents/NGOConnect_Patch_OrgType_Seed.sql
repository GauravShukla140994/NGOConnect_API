-- ============================================================
-- NGOConnect: Seed missing ORG_TYPE lookup values
-- Adds all 8 legal entity types for NGO registration.
-- Safe to run multiple times — INSERT IGNORE skips duplicates.
--
-- RUN IN MYSQL WORKBENCH:
--   Query → Run SQL Script  (NOT the lightning bolt ⚡)
-- ============================================================

-- Existing: TRUST (1), SOCIETY (2), SECTION_8 (3)
-- Adding:   NGO (4), FOUNDATION (5), CHARITABLE_INSTITUTION (6),
--           RELIGIOUS_TRUST (7), CSR_FOUNDATION (8), EDUCATIONAL_TRUST (9)

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, v.ValueCode, v.ValueName, v.OrderNo, 1, 1
FROM LookupTypes lt
JOIN (
    SELECT 'NGO'                     AS ValueCode, 'NGO'                      AS ValueName, 4  AS OrderNo UNION ALL
    SELECT 'FOUNDATION',                           'Foundation',                              5           UNION ALL
    SELECT 'CHARITABLE_INSTITUTION',               'Charitable Institution',                  6           UNION ALL
    SELECT 'RELIGIOUS_TRUST',                      'Religious Trust',                         7           UNION ALL
    SELECT 'CSR_FOUNDATION',                       'CSR Foundation',                          8           UNION ALL
    SELECT 'EDUCATIONAL_TRUST',                    'Educational Trust',                        9
) v ON 1=1
WHERE lt.TypeCode = 'ORG_TYPE';

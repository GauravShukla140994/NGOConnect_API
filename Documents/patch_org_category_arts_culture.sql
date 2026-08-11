-- ============================================================
-- Patch: Add ARTS_CULTURE to ORG_CATEGORY LookupValues
-- NGOs belonging to the "Arts & Culture" category already
-- exist in the DB; the matching LookupValue was missing.
-- No SP / C# / mobile DAL changes needed.
-- Apply to: local → Railway staging → Railway production
-- ============================================================

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'ARTS_CULTURE', 'Arts & Culture', 11, 1, 1
FROM LookupTypes
WHERE TypeCode = 'ORG_CATEGORY';

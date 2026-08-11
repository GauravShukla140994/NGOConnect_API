-- ── patch_fix_org_category_codes.sql ─────────────────────────────────────────
-- Problem : Organisations.Category stores ValueName strings (e.g. 'Animal Welfare',
--           'Education') for every test-seeded NGO. The Org_List SP filter is:
--               AND (p_Category IS NULL OR o.Category = p_Category)
--           The mobile sends p_Category = 'ANIMAL_WELFARE' (the ValueCode).
--           Exact mismatch → every category chip returns 0 rows.
--
-- Root cause: TestSeed_ExploreNGOs.sql and TestSeed_BulkData_v1.sql hard-coded
--             display names instead of ValueCodes when inserting Category.
--             NGOs registered via the app (CreateOrgScreen) are unaffected —
--             the form correctly sends cat.valueCode.
--
-- Fix:
--   Step 1  JOIN-based auto-fix for all rows where Category = any ORG_CATEGORY ValueName.
--           Covers: Education, Environment, Healthcare, Animal Welfare,
--                   Women Empowerment, Community Service, Disaster Relief,
--                   Rural Development, Child Welfare, Senior Citizens.
--   Step 2  Manual alias fix: 'Community Dev' → 'COMMUNITY'
--           (seed used this label; no matching ValueName in LookupValues).
--
-- Safe to re-run — no-ops on rows already storing the correct code.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

-- Step 1: Normalise ValueName → ValueCode via LookupValues JOIN
UPDATE Organisations o
JOIN  LookupValues lv ON lv.ValueName = o.Category
JOIN  LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
                      AND lt.TypeCode = 'ORG_CATEGORY'
SET   o.Category = lv.ValueCode
WHERE o.Category != lv.ValueCode;   -- skip already-correct rows

-- Step 2: Fix the 'Community Dev' alias used in TestSeed_ExploreNGOs.sql
UPDATE Organisations
SET    Category = 'COMMUNITY'
WHERE  Category = 'Community Dev';

-- ── Verification ──────────────────────────────────────────────────────────────
-- Expected output: every Category value is an uppercase ValueCode
-- (EDUCATION, ENVIRONMENT, HEALTHCARE, ANIMAL_WELFARE, WOMEN_EMP, COMMUNITY,
--  DISASTER, RURAL_DEV, CHILD_WELFARE, SENIOR, or NULL for any uncategorised rows)
SELECT Category, COUNT(*) AS OrgCount
FROM   Organisations
WHERE  IsDeleted = 0
GROUP  BY Category
ORDER  BY Category;

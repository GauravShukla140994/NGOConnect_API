-- ─────────────────────────────────────────────────────────────────────────────
-- query_find_likely_nonregistered_orgs.sql
-- READ-ONLY — no data is changed by this query.
--
-- Lists all APPROVED organisations that currently show IsNonRegistered = 0
-- ("Registered" badge) but have a blank/missing RegNumber — these are the
-- most likely candidates for orgs that are actually non-registered in real
-- life but were approved before the IsNonRegistered flow existed (2026-08-25),
-- so the flag defaulted to 0 regardless of the real situation.
--
-- Review this list, then for each org that's genuinely non-registered, open
-- it in the Super Admin website (Organisations → find it → Approved tab →
-- click it) and use "Change Registration Status" to correct it.
--
-- Run on: whichever DB you're checking (local / staging / production).
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    o.OrgId,
    o.OrgName,
    o.RegNumber,
    o.IsNonRegistered,
    sv.ValueCode        AS StatusCode,
    o.CreatedAt          AS SubmittedAt,
    o.StatusUpdatedAt    AS ApprovedAt,
    fp.FirstName,
    fp.LastName,
    u.Email              AS FounderEmail,
    u.Mobile             AS FounderMobile
FROM Organisations o
JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
LEFT JOIN OrgMembers om
       ON om.OrgId = o.OrgId AND om.IsDeleted = 0
      AND om.RoleLkpId = (
          SELECT LookupValueId FROM LookupValues lv
          JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
          WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1
      )
LEFT JOIN UserProfiles fp ON fp.UserId = om.UserId
LEFT JOIN Users u         ON u.UserId  = om.UserId
WHERE o.IsDeleted = 0
  AND sv.ValueCode = 'APPROVED'
  AND o.IsNonRegistered = 0
  AND (o.RegNumber IS NULL OR TRIM(o.RegNumber) = '')
ORDER BY o.StatusUpdatedAt ASC;

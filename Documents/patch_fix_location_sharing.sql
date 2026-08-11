-- ── patch_fix_location_sharing.sql ───────────────────────────────────────────
-- Bug   : Location Sharing toggle on Admin → Volunteer → Member Details screen
--         never persisted / always showed unticked on re-open.
--
-- Root causes (4 layers — all fixed):
--   1. Mobile saveAll() omitted locationSharing from the API payload entirely.
--   2. Backend model had LocationSharingLkpId (int?) — no JSON mapping from
--      the mobile's boolean field → always deserialised as null.
--   3. Org_UpdateMemberPermissions SP used COALESCE(p_LocationSharingLkpId, ...):
--      null → silently kept old value, so nothing ever changed.
--   4. Org_GetMembers CASE condition: lsv.ValueCode != 'DISABLED' — this means
--      'NEVER' also returns 1 (ticked). Fix: only 'ALWAYS'/'DURING_SOS' → 1.
--      Also: MySQL CASE expression returns INT64, not TINYINT(1) bool, so React
--      Native Switch received 1 (number) instead of true (bool) → showed as off.
--      Fix: mobile wraps all permission values in Boolean() on init.
--
-- SP changes (2 SPs):
--   Org_UpdateMemberPermissions : p_LocationSharingLkpId INT UNSIGNED
--                                 → p_LocationSharing TINYINT(1).
--                                 Resolves ALWAYS/NEVER LkpId internally.
--   Org_GetMembers              : CASE condition fixed to
--                                 ValueCode = 'ALWAYS' OR 'DURING_SOS'
--                                 (NEVER now correctly returns 0).
--
-- No table or column changes. Safe to re-run.
-- Run: local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

-- ── 1. Fix write SP ──────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_UpdateMemberPermissions //

CREATE PROCEDURE Org_UpdateMemberPermissions(
    IN p_OrgMemberId      INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_UpdatedBy        INT UNSIGNED,
    IN p_CanPost          TINYINT(1),
    IN p_CanComment       TINYINT(1),
    IN p_CanCommunityPost TINYINT(1),
    IN p_MaxPostsPerDay   TINYINT,
    IN p_LocationSharing  TINYINT(1)
)
BEGIN
    DECLARE v_LocLkpId INT UNSIGNED DEFAULT NULL;

    -- Resolve boolean → LookupValueId for LOCATION_SHARING (ALWAYS / NEVER)
    IF p_LocationSharing IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_LocLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode  = 'LOCATION_SHARING'
          AND  lv.ValueCode = IF(p_LocationSharing = 1, 'ALWAYS', 'NEVER')
        LIMIT 1;
    END IF;

    UPDATE OrgMembers SET
        CanPost              = COALESCE(p_CanPost,          CanPost),
        CanComment           = COALESCE(p_CanComment,       CanComment),
        CanCommunityPost     = COALESCE(p_CanCommunityPost, CanCommunityPost),
        MaxPostsPerDay       = COALESCE(p_MaxPostsPerDay,   MaxPostsPerDay),
        LocationSharingLkpId = COALESCE(v_LocLkpId, LocationSharingLkpId),
        UpdatedBy            = p_UpdatedBy,
        UpdatedAt            = NOW()
    WHERE OrgMemberId = p_OrgMemberId AND OrgId = p_OrgId AND IsDeleted = 0;

    SELECT 1 AS IsSuccess, 'Permissions updated.' AS Message;
END //

-- ── 2. Fix read SP — correct CASE condition + column alias ───────────────────
DROP PROCEDURE IF EXISTS Org_GetMembers //

CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId                                     AS MemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)             AS FullName,
        u.Email,
        u.Mobile                                           AS Phone,
        up.ProfilePhoto,
        up.Occupation,
        rv.ValueCode                                       AS RoleCode,
        rv.ValueName                                       AS RoleName,
        sv.ValueCode                                       AS StatusCode,
        sv.ValueName                                       AS StatusName,
        om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay,
        -- ALWAYS or DURING_SOS = 1 (ticked); NEVER or NULL = 0 (unticked)
        CASE WHEN lsv.ValueCode = 'ALWAYS' OR lsv.ValueCode = 'DURING_SOS'
             THEN 1 ELSE 0
        END                                                AS LocationSharing,
        om.JoinedAt,
        u.IsActive,
        u.LastLoginAt                                      AS LastActiveAt,
        COALESCE(pv.ValueCode, 'PENDING')                  AS ProfileVerificationStatusCode
    FROM OrgMembers om
    JOIN Users        u  ON om.UserId = u.UserId  AND u.IsDeleted  = 0
    JOIN UserProfiles up ON om.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv  ON om.RoleLkpId               = rv.LookupValueId
    LEFT JOIN LookupValues sv  ON om.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues lsv ON om.LocationSharingLkpId    = lsv.LookupValueId
    LEFT JOIN LookupValues pv  ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt ASC;
END //

DELIMITER ;

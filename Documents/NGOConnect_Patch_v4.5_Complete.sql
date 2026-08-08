-- ============================================================
-- NGO Connect — Comprehensive Patch: v4.4 → v4.5
-- Date    : 2026-07-11
-- Author  : Generated from session audit + SuperAdmin module
--
-- WHAT THIS PATCH COVERS (apply in order — all sections are
-- idempotent: safe to run even if some parts already applied):
--
--   Section 1 — SP Column-Name Fixes (v4.4 bug fixes)
--     • Certificate_GetByUser  — p.Title → p.ProjectName
--     • User_GetBadges         — p.Title → p.ProjectName
--     • Project_List           — 10+ wrong column aliases fixed
--     • Application_GetByUser  — wrong column aliases fixed
--     • Post_Create            — 7-param → 6-param (auto-detect VIDEO/IMAGE)
--     • Post_GetFeed           — 3-param → 4-param (added p_OrgId filter)
--
--   Section 2 — User_GetMyOrgs Fix
--     • UNION pattern to return both APPROVED and PENDING memberships
--
--   Section 3 — Super Admin Module (v4.5 NEW)
--     • CREATE TABLE IF NOT EXISTS SuperAdminUsers
--     • CREATE TABLE IF NOT EXISTS OrgStatusHistory
--     • 18 brand-new SPs (SuperAdmin_* prefix + Org_Resubmit)
--     • Seed: 1 default SuperAdmin row (gaurav.admin)
--
-- PRE-REQUISITES:
--   • NGOConnect_Patch_FixProjectTitle.sql was ALREADY run on
--     Railway staging (fixed p.Title on FixProjectTitle session).
--     This patch supersedes and corrects that partial fix.
--   • MySqlConnector 2.3.7 must be in use in the API project
--     (replaces MySql.Data 9.1.0 — already done in codebase).
--
-- HOW TO APPLY:
--   1. Take a DB snapshot/backup on Railway before running
--   2. Run in MySQL Workbench connected to the target environment
--   3. Verify with the SELECT checks at the bottom of each section
-- ============================================================

USE NGOConnect;


-- ============================================================
-- SECTION 1: SP Column-Name Fixes (v4.4 corrections)
-- ============================================================

-- Date: 2026-07-11
-- Covers all SP fixes applied in this session.
-- SAFE TO RUN MULTIPLE TIMES (DROP IF EXISTS pattern).
--
-- STATUS:
--   Already on Railway staging:
--     ✅ Certificate_GetByUser (FixProjectTitle patch)
--     ✅ User_GetBadges (FixProjectTitle patch)
--     ✅ Post_Create 6-param (PostFeed_VideoSupport patch)
--     ✅ Post_GetFeed 4-param (PostFeed_OrgFilter patch)
--
--   ❌ STILL NEEDS TO BE RUN on Railway staging:
--     → Project_List (FixProjectColumns)
--     → Application_GetByUser (FixProjectColumns)
--
-- Root causes fixed:
--   1. p.Title → p.ProjectName (4 SPs: Certificate_GetByUser, User_GetBadges,
--      Application_GetByUser, Project_List)
--   2. Wrong column aliases in Project_List and Application_GetByUser:
--      p.LocationName  → p.Landmark AS LocationName
--      p.Address       → p.AddressLine AS Address
--      p.StartDate     → removed (use OneTimeDate/RecurStart/FlexFromDate)
--      p.EndDate       → removed (use RecurEnd/FlexToDate)
--      p.StartTime     → p.SessionStartTime
--      p.EndTime       → p.SessionEndTime
--      p.ScheduleType  → ptv.ValueCode via JOIN on ProjectTypeLkpId
--      p.RecurrenceDays→ p.RecurDays
--      p.CoverImageUrl → removed (column does not exist on Projects table)
--   3. Post_Create 7-param (with p_MediaType) → 6-param auto-detect IMAGE/VIDEO
--   4. Post_GetFeed 3-param → 4-param (added p_OrgId filter)
-- ============================================================

USE ngoconnect;
DELIMITER //


-- ── 1. Certificate_GetByUser ─────────────────────────────────
DROP PROCEDURE IF EXISTS Certificate_GetByUser //
CREATE PROCEDURE Certificate_GetByUser(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT vc.CertificateId, vc.ProjectId, p.ProjectName AS ProjectTitle,
           vc.OrgId, o.OrgName, o.LogoUrl AS OrgLogoUrl,
           vc.CertificateUrl, vc.IssuedAt, vc.TotalHours
    FROM VolunteerCertificates vc
    JOIN Projects p ON vc.ProjectId = p.ProjectId
    JOIN Organisations o ON vc.OrgId = o.OrgId
    WHERE vc.UserId = p_UserId AND vc.IsDeleted = 0
    ORDER BY vc.IssuedAt DESC;
END //


-- ── 2. User_GetBadges ────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_GetBadges //
CREATE PROCEDURE User_GetBadges(IN p_UserId INT UNSIGNED)
BEGIN
    SELECT
        ub.UserBadgeId,
        ub.BadgeLkpId,
        lv.ValueName AS BadgeName,
        lv.ValueCode AS BadgeCode,
        o.OrgName,
        p.ProjectName,
        ub.AwardedAt
    FROM UserBadges ub
    JOIN LookupValues lv  ON ub.BadgeLkpId = lv.LookupValueId
    LEFT JOIN Organisations o ON ub.AwardedByOrgId = o.OrgId
    LEFT JOIN Projects p      ON ub.ProjectId = p.ProjectId
    WHERE ub.UserId = p_UserId AND ub.IsDeleted = 0
    ORDER BY ub.AwardedAt DESC;
END //


-- ── 3. Project_List (v4.3 correct columns + Haversine distance) ──
DROP PROCEDURE IF EXISTS Project_List //
CREATE PROCEDURE Project_List(
    IN p_OrgId      INT UNSIGNED,
    IN p_Category   VARCHAR(100),
    IN p_City       VARCHAR(100),
    IN p_StatusCode VARCHAR(50),
    IN p_TypeCode   VARCHAR(50),
    IN p_PageNumber INT,
    IN p_PageSize   INT,
    IN p_UserLat    DECIMAL(10,7),
    IN p_UserLon    DECIMAL(10,7)
)
BEGIN
    DECLARE v_Offset       INT;
    DECLARE v_StatusLkpId  INT UNSIGNED DEFAULT NULL;
    DECLARE v_TypeLkpId    INT UNSIGNED DEFAULT NULL;

    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    IF p_StatusCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_StatusLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = p_StatusCode LIMIT 1;
    END IF;

    IF p_TypeCode IS NOT NULL THEN
        SELECT lv.LookupValueId INTO v_TypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE  lt.TypeCode = 'PROJECT_TYPE' AND lv.ValueCode = p_TypeCode LIMIT 1;
    END IF;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        p.ProjectName,
        p.Category,
        ptv.ValueCode    AS ScheduleType,
        ptv.ValueCode    AS ProjectTypeCode,
        ptv.ValueName    AS ProjectType,
        ltv.ValueCode    AS LocationTypeCode,
        ltv.ValueName    AS LocationType,
        p.Landmark       AS LocationName,
        p.AddressLine    AS Address,
        sv.ValueCode     AS StatusCode,
        sv.ValueName     AS Status,
        p.City,
        p.State,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.IsPublic,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.MinHoursRequired,
        p.CancelReason,
        p.CancelledAt,
        p.ImpactSummary,
        p.BeneficiaryCount,
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv ON pa2.StatusLkpId = alv.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv.ValueCode = 'APPROVED'
           AND pa2.IsDeleted = 0) AS ApprovedCount,
        p.CreatedAt,
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
                 AND p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
            )), 2)
            ELSE NULL
        END AS DistanceKm
    FROM   Projects p
    JOIN   Organisations o       ON p.OrgId             = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues ptv   ON p.ProjectTypeLkpId  = ptv.LookupValueId
    LEFT JOIN LookupValues ltv   ON p.LocationTypeLkpId = ltv.LookupValueId
    LEFT JOIN LookupValues sv    ON p.StatusLkpId       = sv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId            = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category         = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId     = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId)
    ORDER BY
        CASE WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL THEN
            CASE WHEN p.Latitude IS NOT NULL AND p.Longitude IS NOT NULL THEN
                6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))))
            ELSE 999999 END
        ELSE NULL END ASC,
        p.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    LEFT JOIN LookupValues ptv ON p.ProjectTypeLkpId = ptv.LookupValueId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NOT NULL OR p.IsPublic = 1)
      AND  (p_OrgId      IS NULL OR p.OrgId            = p_OrgId)
      AND  (p_Category   IS NULL OR p.Category         = p_Category OR ptv.ValueCode = p_Category)
      AND  (p_City       IS NULL OR p.City LIKE CONCAT('%', p_City, '%'))
      AND  (v_StatusLkpId IS NULL OR p.StatusLkpId     = v_StatusLkpId)
      AND  (v_TypeLkpId   IS NULL OR p.ProjectTypeLkpId = v_TypeLkpId);
END //


-- ── 4. Application_GetByUser (correct column names) ──────────
DROP PROCEDURE IF EXISTS Application_GetByUser //
CREATE PROCEDURE Application_GetByUser(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        pa.ApplicationId,
        pa.ProjectId,
        p.ProjectName,
        o.OrgName,
        o.LogoUrl        AS OrgLogoUrl,
        appSv.ValueCode  AS StatusCode,
        appSv.ValueName  AS Status,
        pa.CreatedAt,
        pa.StatusUpdatedAt,
        ptv.ValueCode    AS ScheduleTypeCode,
        ptv.ValueName    AS ScheduleTypeName,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.OneTimeDate,
        p.FlexFromDate,
        p.FlexToDate,
        p.Landmark       AS LocationName,
        p.City,
        projSv.ValueCode AS ProjectStatusCode,
        projSv.ValueName AS ProjectStatus
    FROM   ProjectApplications pa
    JOIN   Projects      p     ON pa.ProjectId   = p.ProjectId
    JOIN   Organisations o     ON p.OrgId        = o.OrgId
    LEFT JOIN LookupValues appSv  ON pa.StatusLkpId        = appSv.LookupValueId
    LEFT JOIN LookupValues projSv ON p.StatusLkpId         = projSv.LookupValueId
    LEFT JOIN LookupValues ptv    ON p.ProjectTypeLkpId    = ptv.LookupValueId
    WHERE  pa.UserId    = p_UserId
      AND  pa.IsDeleted = 0
    ORDER BY pa.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   ProjectApplications
    WHERE  UserId = p_UserId AND IsDeleted = 0;
END //


-- ── 5. Post_Create (6-param, auto-detect IMAGE/VIDEO from extension) ──
DROP PROCEDURE IF EXISTS Post_Create //
CREATE PROCEDURE Post_Create(
    IN p_UserId          INT UNSIGNED,
    IN p_OrgId           INT UNSIGNED,
    IN p_Content         TEXT,
    IN p_MediaUrls       TEXT,           -- comma-separated remote URLs
    IN p_PostTypeLkpId   INT UNSIGNED,
    IN p_VisibilityLkpId INT UNSIGNED
)
BEGIN
    DECLARE v_ImageTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_VideoTypeLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_DefaultTypeLkpId INT UNSIGNED DEFAULT 0;

    IF p_PostTypeLkpId IS NULL THEN
        SELECT lv.LookupValueId INTO v_DefaultTypeLkpId
        FROM   LookupValues lv
        JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_FEED' AND lv.ValueCode = 'GENERAL' LIMIT 1;
        SET p_PostTypeLkpId = COALESCE(v_DefaultTypeLkpId, 1);
    END IF;

    INSERT INTO Posts (UserId, OrgId, Content, PostTypeLkpId, VisibilityLkpId, LikeCount, CommentCount, CreatedBy)
    VALUES (p_UserId, p_OrgId, p_Content, p_PostTypeLkpId, p_VisibilityLkpId, 0, 0, p_UserId);

    SET @NewPostId = LAST_INSERT_ID();

    IF p_MediaUrls IS NOT NULL AND p_MediaUrls != '' THEN

        SELECT lv.LookupValueId INTO v_ImageTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'IMAGE' LIMIT 1;

        SELECT lv.LookupValueId INTO v_VideoTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'MEDIA_TYPE' AND lv.ValueCode = 'VIDEO' LIMIT 1;

        IF v_ImageTypeLkpId = 0 THEN SET v_ImageTypeLkpId = 1; END IF;
        IF v_VideoTypeLkpId = 0 THEN SET v_VideoTypeLkpId = v_ImageTypeLkpId; END IF;

        INSERT INTO PostMedia (PostId, FileUrl, MediaTypeLkpId, SortOrder)
        SELECT
            @NewPostId,
            TRIM(j.val),
            CASE
                WHEN LOWER(TRIM(j.val)) REGEXP '\\.(mp4|mov|avi|mkv|webm|m4v|3gp|wmv)$'
                     THEN v_VideoTypeLkpId
                ELSE v_ImageTypeLkpId
            END,
            j.rn
        FROM JSON_TABLE(
            CONCAT('["', REPLACE(p_MediaUrls, ',', '","'), '"]'),
            '$[*]' COLUMNS (rn FOR ORDINALITY, val VARCHAR(500) PATH '$')
        ) AS j
        WHERE TRIM(j.val) != '';

    END IF;

    SELECT 1 AS IsSuccess, 'Post created successfully.' AS Message, @NewPostId AS PostId;
END //


-- ── 6. Post_GetFeed (4-param with OrgId filter + grouped media) ──
DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_OrgId      INT UNSIGNED,   -- NULL = all orgs | non-null = filter to one org
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId,
        p.Content,
        p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode,
        lv_type.ValueName AS PostType,
        p.LikeCount,
        p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up         ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o      ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm         ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
    GROUP BY
        p.PostId, p.Content, p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId, up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId, o.OrgName,
        p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId);
END //


DELIMITER ;

SELECT 'Comprehensive patch applied: Certificate_GetByUser, User_GetBadges, Project_List, Application_GetByUser, Post_Create (6-param), Post_GetFeed (4-param)' AS Result;

-- ============================================================
-- SECTION 2: User_GetMyOrgs — UNION fix (APPROVED + PENDING)
-- ============================================================

-- Date    : 2026-07-09
--
-- ROOT CAUSE OF BUG:
--   The database was running the original User_GetMyOrgs SP (from
--   NGOConnect_Complete_Setup_v4.3.sql) which does NOT return the
--   MemberStatusCode or OrgStatusCode columns.
--
--   BaseDal.Col<T> safely handles missing columns (returns default/"")
--   so no exception is thrown — but UserOrgModel gets:
--       MemberStatusCode = ""
--       OrgStatusCode    = ""
--
--   MyOrgsScreen.tsx then filters:
--       activeOrgs:  o.memberStatusCode === 'APPROVED'  → "" === 'APPROVED'  → false ❌
--       pendingOrgs: o.memberStatusCode === 'PENDING'   → "" === 'PENDING'   → false ❌
--
--   Result: org never appears in either section even though the user IS
--   a member (Org_GetProfile correctly shows "✓ Member" because its
--   patch was applied separately).
--
-- FIX:
--   UNION of two parts:
--     Part 1 — APPROVED rows from OrgMembers
--     Part 2 — PENDING rows from OrgMembershipRequests
--
--   Key hardening vs. previous patch:
--     • rv (role) and ot (org type) are LEFT JOINs — NULL RoleLkpId or
--       OrgTypeLkpId no longer silently drops the row
--     • os (org status) is LEFT JOIN — NULL org StatusLkpId handled
--       gracefully (frontend defaults orgStatusCode → 'ACTIVE')
--
-- Apply: Run against NGOConnect database.
-- Safe to run multiple times.
-- ============================================================

USE NGOConnect;

DROP PROCEDURE IF EXISTS User_GetMyOrgs;

DELIMITER //

CREATE PROCEDURE User_GetMyOrgs(IN p_UserId INT UNSIGNED)
BEGIN
    -- ── Part 1: Approved memberships via OrgMembers ───────────────────────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName  AS OrgType,
        o.City,
        o.State,
        COALESCE(rv.ValueName, 'Member')  AS Role,
        COALESCE(rv.ValueCode, 'MEMBER')  AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
             JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
             JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
             WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
               AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        om.CreatedAt  AS JoinedAt,
        sv.ValueCode  AS MemberStatusCode,   -- always 'APPROVED' here
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
    FROM OrgMembers om
    JOIN  Organisations o  ON om.OrgId       = o.OrgId              AND o.IsDeleted  = 0
    JOIN  LookupValues  sv ON om.StatusLkpId = sv.LookupValueId     -- MEMBER_STATUS
    LEFT JOIN LookupValues  rv ON om.RoleLkpId   = rv.LookupValueId -- MEMBER_ROLE (nullable-safe)
    LEFT JOIN LookupValues  os ON o.StatusLkpId  = os.LookupValueId -- ORG_STATUS  (nullable-safe)
    LEFT JOIN LookupValues  ot ON o.OrgTypeLkpId = ot.LookupValueId -- ORG_TYPE    (nullable-safe)
    WHERE om.UserId    = p_UserId
      AND om.IsDeleted = 0
      AND sv.ValueCode = 'APPROVED'

    UNION ALL

    -- ── Part 2: Pending join requests via OrgMembershipRequests ──────────────
    SELECT
        o.OrgId,
        o.OrgName,
        o.LogoUrl,
        ot.ValueName           AS OrgType,
        o.City,
        o.State,
        'Member'               AS Role,
        'MEMBER'               AS RoleCode,
        (SELECT COUNT(*) FROM OrgMembers om2
             JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
             JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
             WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
               AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        mr.CreatedAt           AS JoinedAt,
        'PENDING'              AS MemberStatusCode,
        COALESCE(os.ValueCode, 'ACTIVE') AS OrgStatusCode
    FROM OrgMembershipRequests mr
    JOIN  Organisations o  ON mr.OrgId       = o.OrgId              AND o.IsDeleted  = 0
    JOIN  LookupValues  ms ON mr.StatusLkpId = ms.LookupValueId     -- MEMBER_STATUS
    LEFT JOIN LookupValues  os ON o.StatusLkpId  = os.LookupValueId -- ORG_STATUS  (nullable-safe)
    LEFT JOIN LookupValues  ot ON o.OrgTypeLkpId = ot.LookupValueId -- ORG_TYPE    (nullable-safe)
    WHERE mr.UserId    = p_UserId
      AND mr.IsDeleted = 0
      AND ms.ValueCode = 'PENDING'

    ORDER BY JoinedAt DESC;

END //

DELIMITER ;

-- ── Verify: replace 4 with the affected UserId ───────────────────────────────
-- CALL User_GetMyOrgs(4);

-- ============================================================
-- SECTION 3: Super Admin Module (v4.5 NEW)
-- ============================================================

-- Apply to Railway staging / production after the setup SQL has
-- already been run once. This patch is idempotent-safe to the
-- extent MySQL allows (CREATE TABLE will fail if it already
-- exists — that's intentional, it means the patch already ran).
--
-- New tables + brand-new SPs only. Zero changes to any existing
-- table or SP.
--
-- This patch is a straight copy of the "v4.5 ADDITIONS" block in
-- NGOConnect_Complete_Setup_v4.4.sql — that file remains the
-- single source of truth. If they ever drift, the setup SQL wins.
-- ============================================================

-- ── GROUP 11: SUPER ADMIN (2 tables) ─────────────────────────

CREATE TABLE SuperAdminUsers (
    SuperAdminUserId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Username         VARCHAR(100)  NOT NULL,
    PasswordHash     VARCHAR(255)  NOT NULL,
    FullName         VARCHAR(150)  NOT NULL,
    Email            VARCHAR(150)  NULL,
    IsActive         TINYINT(1)    NOT NULL DEFAULT 1,
    LastLoginAt      DATETIME      NULL,
    CreatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (SuperAdminUserId),
    UNIQUE KEY uq_superadmin_username (Username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE OrgStatusHistory (
    OrgStatusHistoryId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    OrgId              INT UNSIGNED  NOT NULL,
    OldStatusLkpId     INT UNSIGNED  NULL,
    NewStatusLkpId     INT UNSIGNED  NOT NULL,
    Reason             TEXT          NULL,
    ChangedByType      VARCHAR(20)   NOT NULL COMMENT 'SUPER_ADMIN or FOUNDER',
    ChangedBy          INT UNSIGNED  NOT NULL COMMENT 'SuperAdminUserId or UserId depending on ChangedByType',
    CreatedAt          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (OrgStatusHistoryId),
    INDEX idx_orgstatushist_org (OrgId, CreatedAt DESC),
    CONSTRAINT fk_orgstatushist_org FOREIGN KEY (OrgId) REFERENCES Organisations(OrgId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed one default Super Admin.
--   Username: gaurav.admin
--   Password: NgoConnect@2026   <-- CHANGE IMMEDIATELY AFTER FIRST LOGIN
INSERT INTO SuperAdminUsers (Username, PasswordHash, FullName, Email, IsActive)
VALUES ('gaurav.admin', '$2b$11$bL6esk4WXdAWUxFp7H56PeGqxyXoIQO0CgVyt98K.1rwSJEH3Es5S', 'Gaurav Shukla', 'gauravshukla1409@gmail.com', 1);

DELIMITER //

CREATE PROCEDURE SuperAdmin_GetByUsername(IN p_Username VARCHAR(100))
BEGIN
    SELECT SuperAdminUserId, Username, PasswordHash, FullName, Email, IsActive
    FROM SuperAdminUsers
    WHERE Username = p_Username
    LIMIT 1;
END //

CREATE PROCEDURE SuperAdmin_UpdateLastLogin(IN p_SuperAdminUserId INT UNSIGNED)
BEGIN
    UPDATE SuperAdminUsers SET LastLoginAt = NOW() WHERE SuperAdminUserId = p_SuperAdminUserId;
    SELECT 1 AS IsSuccess, 'Login recorded.' AS Message;
END //

CREATE PROCEDURE SuperAdmin_Org_GetList(
    IN p_StatusCode VARCHAR(20),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.City, o.State, o.LogoUrl,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode
    ORDER BY o.CreatedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    JOIN LookupTypes  st ON sv.LookupTypeId = st.LookupTypeId AND st.TypeCode = 'ORG_STATUS'
    WHERE o.IsDeleted = 0
      AND sv.ValueCode = p_StatusCode;
END //

CREATE PROCEDURE SuperAdmin_Org_GetDetail(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        tv.ValueName AS OrgType,
        sv.ValueCode AS StatusCode, sv.ValueName AS StatusName,
        o.CreatedAt AS SubmittedAt, o.StatusUpdatedAt,
        founder.UserId AS FounderUserId,
        CONCAT(fp.FirstName, ' ', fp.LastName) AS FounderName,
        u.Email AS FounderEmail, u.Mobile AS FounderMobile,
        (SELECT h.Reason FROM OrgStatusHistory h
          WHERE h.OrgId = o.OrgId AND h.NewStatusLkpId = o.StatusLkpId
          ORDER BY h.CreatedAt DESC LIMIT 1) AS LastReason
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    LEFT JOIN OrgMembers founder ON founder.OrgId = o.OrgId AND founder.IsDeleted = 0
        AND founder.RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
    LEFT JOIN Users u ON founder.UserId = u.UserId
    LEFT JOIN UserProfiles fp ON founder.UserId = fp.UserId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

CREATE PROCEDURE SuperAdmin_Org_GetDocuments(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT od.OrgDocumentId, od.DocumentTypeLkpId, dt.ValueName AS DocumentType,
           od.FileUrl, od.FileName, od.IsVerified, od.VerifiedAt, od.VerifiedBy,
           od.CreatedAt
    FROM OrgDocuments od
    LEFT JOIN LookupValues dt ON od.DocumentTypeLkpId = dt.LookupValueId
    WHERE od.OrgId = p_OrgId AND od.IsDeleted = 0
    ORDER BY od.CreatedAt ASC;
END //

CREATE PROCEDURE SuperAdmin_OrgDocument_Verify(
    IN p_OrgDocumentId  INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_IsVerified     TINYINT(1)
)
BEGIN
    UPDATE OrgDocuments
    SET IsVerified = p_IsVerified,
        VerifiedAt = NOW(),
        VerifiedBy = p_SuperAdminUserId
    WHERE OrgDocumentId = p_OrgDocumentId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Document not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Document verification updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Approve(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot approve — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_APPROVED', 'Your NGO has been approved',
                    'Congratulations — your organisation is now live on NGO Connect.', p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation approved.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reject(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_RejectedId      INT UNSIGNED;
    DECLARE v_FounderUserId   INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reject — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSEIF p_Reason IS NULL OR TRIM(p_Reason) = '' THEN
        SELECT 0 AS IsSuccess, 'A rejection reason is required.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_RejectedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'REJECTED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_RejectedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_RejectedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT UserId INTO v_FounderUserId FROM OrgMembers
            WHERE OrgId = p_OrgId AND IsDeleted = 0
              AND RoleLkpId = (SELECT LookupValueId FROM LookupValues lv
                  JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE lt.TypeCode = 'MEMBER_ROLE' AND lv.ValueCode = 'FOUNDER' LIMIT 1)
            LIMIT 1;

        IF v_FounderUserId IS NOT NULL THEN
            INSERT INTO Notifications (UserId, NotifType, Title, Body, RefId, RefType)
            VALUES (v_FounderUserId, 'ORG_REJECTED', 'Your NGO registration needs changes',
                    p_Reason, p_OrgId, 'ORGANISATION');
        END IF;

        SELECT 1 AS IsSuccess, 'Organisation rejected.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Suspend(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED,
    IN p_Reason           TEXT
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_SuspendedId     INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'APPROVED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot suspend — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_SuspendedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'SUSPENDED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_SuspendedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_SuspendedId, p_Reason, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation suspended.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_Org_Reactivate(
    IN p_OrgId            INT UNSIGNED,
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_ApprovedId      INT UNSIGNED;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_CurrentCode <> 'SUSPENDED' THEN
        SELECT 0 AS IsSuccess, CONCAT('Cannot reactivate — organisation is currently ', v_CurrentCode, '.') AS Message;
    ELSE
        SELECT LookupValueId INTO v_ApprovedId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

        UPDATE Organisations
        SET StatusLkpId = v_ApprovedId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_SuperAdminUserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_ApprovedId, NULL, 'SUPER_ADMIN', p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Organisation reactivated.' AS Message;
    END IF;
END //

CREATE PROCEDURE Org_Resubmit(
    IN p_OrgId         INT UNSIGNED,
    IN p_UserId        INT UNSIGNED,
    IN p_OrgName       VARCHAR(200),
    IN p_Category      VARCHAR(100),
    IN p_ContactPerson VARCHAR(100),
    IN p_About         TEXT,
    IN p_Mission       TEXT,
    IN p_Vision        TEXT,
    IN p_LogoUrl       VARCHAR(500),
    IN p_ContactEmail  VARCHAR(150),
    IN p_ContactPhone  VARCHAR(20),
    IN p_Website       VARCHAR(255),
    IN p_AddressLine1  VARCHAR(200),
    IN p_AddressLine2  VARCHAR(200),
    IN p_City          VARCHAR(100),
    IN p_State         VARCHAR(100),
    IN p_Pincode       VARCHAR(20),
    IN p_Country       VARCHAR(100)
)
BEGIN
    DECLARE v_CurrentStatusId INT UNSIGNED;
    DECLARE v_CurrentCode     VARCHAR(50);
    DECLARE v_PendingId       INT UNSIGNED;
    DECLARE v_IsFounder       INT DEFAULT 0;

    SELECT o.StatusLkpId, sv.ValueCode INTO v_CurrentStatusId, v_CurrentCode
    FROM Organisations o JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;

    SELECT COUNT(*) INTO v_IsFounder FROM OrgMembers om
        JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId
        WHERE om.OrgId = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0 AND rv.ValueCode = 'FOUNDER';

    IF v_CurrentStatusId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Organisation not found.' AS Message;
    ELSEIF v_IsFounder = 0 THEN
        SELECT 0 AS IsSuccess, 'Only the founder can resubmit this organisation.' AS Message;
    ELSEIF v_CurrentCode <> 'REJECTED' THEN
        SELECT 0 AS IsSuccess, 'Only a rejected organisation can be resubmitted.' AS Message;
    ELSE
        SELECT LookupValueId INTO v_PendingId FROM LookupValues lv
            JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

        UPDATE Organisations SET
            OrgName = p_OrgName, Category = p_Category, ContactPerson = p_ContactPerson,
            About = p_About, Mission = p_Mission, Vision = p_Vision, LogoUrl = p_LogoUrl,
            ContactEmail = p_ContactEmail, ContactPhone = p_ContactPhone, Website = p_Website,
            AddressLine1 = p_AddressLine1, AddressLine2 = p_AddressLine2, City = p_City,
            State = p_State, Pincode = p_Pincode, Country = p_Country,
            StatusLkpId = v_PendingId, StatusUpdatedAt = NOW(), StatusUpdatedBy = p_UserId
        WHERE OrgId = p_OrgId;

        INSERT INTO OrgStatusHistory (OrgId, OldStatusLkpId, NewStatusLkpId, Reason, ChangedByType, ChangedBy)
        VALUES (p_OrgId, v_CurrentStatusId, v_PendingId, 'Resubmitted by founder after rejection', 'FOUNDER', p_UserId);

        SELECT 1 AS IsSuccess, 'Organisation resubmitted for review.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_GetList()
BEGIN
    SELECT lt.LookupTypeId, lt.TypeCode, lt.TypeName, lt.Description, lt.IsSystemType,
        (SELECT COUNT(*) FROM LookupValues lv WHERE lv.LookupTypeId = lt.LookupTypeId AND lv.IsDeleted = 0) AS ValueCount
    FROM LookupTypes lt
    WHERE lt.IsDeleted = 0
    ORDER BY lt.TypeName;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_GetByType(IN p_LookupTypeId INT UNSIGNED)
BEGIN
    SELECT LookupValueId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, IsDeleted
    FROM LookupValues
    WHERE LookupTypeId = p_LookupTypeId
    ORDER BY OrderNo, ValueName;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Add(
    IN p_TypeCode         VARCHAR(50),
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupTypes WHERE TypeCode = p_TypeCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A lookup type with this code already exists.' AS Message, NULL AS LookupTypeId;
    ELSE
        INSERT INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy)
        VALUES (p_TypeCode, p_TypeName, p_Description, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup type created.' AS Message, LAST_INSERT_ID() AS LookupTypeId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupType_Update(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_TypeName         VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    UPDATE LookupTypes
    SET TypeName = p_TypeName, Description = p_Description, UpdatedBy = p_SuperAdminUserId
    WHERE LookupTypeId = p_LookupTypeId AND IsDeleted = 0;

    IF ROW_COUNT() = 0 THEN
        SELECT 0 AS IsSuccess, 'Lookup type not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Lookup type updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Add(
    IN p_LookupTypeId     INT UNSIGNED,
    IN p_ValueCode        VARCHAR(50),
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_Exists FROM LookupValues
        WHERE LookupTypeId = p_LookupTypeId AND ValueCode = p_ValueCode AND IsDeleted = 0;

    IF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'A value with this code already exists for this type.' AS Message, NULL AS LookupValueId;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = p_LookupTypeId;
        END IF;

        INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, Description, OrderNo, IsDefault, IsSystemValue, CreatedBy)
        VALUES (p_LookupTypeId, p_ValueCode, p_ValueName, p_Description, p_OrderNo, p_IsDefault, 0, p_SuperAdminUserId);

        SELECT 1 AS IsSuccess, 'Lookup value created.' AS Message, LAST_INSERT_ID() AS LookupValueId;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_Update(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_ValueName        VARCHAR(100),
    IN p_Description      VARCHAR(300),
    IN p_OrderNo          SMALLINT,
    IN p_IsDefault        TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_LookupTypeId INT UNSIGNED;
    SELECT LookupTypeId INTO v_LookupTypeId FROM LookupValues WHERE LookupValueId = p_LookupValueId AND IsDeleted = 0;

    IF v_LookupTypeId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSE
        IF p_IsDefault = 1 THEN
            UPDATE LookupValues SET IsDefault = 0 WHERE LookupTypeId = v_LookupTypeId;
        END IF;

        UPDATE LookupValues
        SET ValueName = p_ValueName, Description = p_Description, OrderNo = p_OrderNo,
            IsDefault = p_IsDefault, UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, 'Lookup value updated.' AS Message;
    END IF;
END //

CREATE PROCEDURE SuperAdmin_LookupValue_SetActive(
    IN p_LookupValueId    INT UNSIGNED,
    IN p_IsActive         TINYINT(1),
    IN p_SuperAdminUserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsSystemValue TINYINT(1);
    SELECT IsSystemValue INTO v_IsSystemValue FROM LookupValues WHERE LookupValueId = p_LookupValueId;

    IF v_IsSystemValue IS NULL THEN
        SELECT 0 AS IsSuccess, 'Lookup value not found.' AS Message;
    ELSEIF v_IsSystemValue = 1 AND p_IsActive = 0 THEN
        SELECT 0 AS IsSuccess, 'System values cannot be deactivated — they are referenced by platform logic.' AS Message;
    ELSE
        UPDATE LookupValues
        SET IsDeleted = IF(p_IsActive = 1, 0, 1),
            DeletedAt = IF(p_IsActive = 1, NULL, NOW()),
            DeletedBy = IF(p_IsActive = 1, NULL, p_SuperAdminUserId),
            UpdatedBy = p_SuperAdminUserId
        WHERE LookupValueId = p_LookupValueId;

        SELECT 1 AS IsSuccess, IF(p_IsActive = 1, 'Lookup value reactivated.', 'Lookup value deactivated.') AS Message;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- END OF PATCH
-- ============================================================

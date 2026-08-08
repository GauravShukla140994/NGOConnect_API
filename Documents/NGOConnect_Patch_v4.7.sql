-- ============================================================
-- NGO Connect — Patch v4.6 → v4.7
-- Date   : 2026-07-12
-- Author : NGO Connect Dev
--
-- Prerequisites
-- ──────────────────────────────────────────────────────────
--   Patch v4.6 must already be applied to the target DB.
--
-- Scope
-- ──────────────────────────────────────────────────────────
-- DDL (2 changes)
--   1. NEW TABLE   OrgFollowers           — soft-unfollow pattern
--   2. NEW COLUMN  Organisations.FollowerCount — denormalized counter
--
-- SPs — New (3)
--   3.  Org_Follow
--   4.  Org_Unfollow
--   5.  Post_GetPermissions
--
-- SPs — Updated / Fixed (8)
--   6.  Org_GetPendingMembers    FIX: MembershipRequestId alias + IFNULL pagination
--   7.  Org_GetProfile           + FollowerCount + IsFollowing
--   8.  Org_RequestMembership    + auto-follow on join request
--   9.  Org_List                 + FollowerCount
--  10.  Post_GetFeed             + p_OrgId filter + IsFollowing  (MERGED final version)
--  11.  Org_GetDashboard         + FollowerCount KPI
--  12.  Org_GetVolunteerProfile   FIX: AttendStatusLkpId + session routing
--  13.  SuperAdmin_User_GetList   FIX: LEFT JOIN + new users + APPROVED-only filter
--                                 (v4.6 addendum — safe to re-run if already applied)
--
-- How to apply
-- ──────────────────────────────────────────────────────────
--   Run this entire file against Railway staging in MySQL Workbench.
--   All DDL changes are idempotent (IF NOT EXISTS / INFORMATION_SCHEMA guard).
--   All SP changes use DROP IF EXISTS → CREATE, safe to re-run.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- SECTION 1 — DDL CHANGES
-- ════════════════════════════════════════════════════════════

-- ── 1. New table: OrgFollowers ─────────────────────────────
--
-- One row per (OrgId, UserId) pair — UNIQUE KEY prevents duplicates.
-- Soft-unfollow: flip IsFollowing=0 + set UnfollowedAt=NOW() instead of deleting.
-- Re-follow:     UPDATE IsFollowing=1, FollowedAt=NOW(), UnfollowedAt=NULL.
--
CREATE TABLE IF NOT EXISTS OrgFollowers (
    OrgFollowerId  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    OrgId          INT UNSIGNED NOT NULL,
    UserId         INT UNSIGNED NOT NULL,
    IsFollowing    TINYINT(1)   NOT NULL DEFAULT 1
        COMMENT '1 = currently following, 0 = unfollowed',
    FollowedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
        COMMENT 'Last follow timestamp',
    UnfollowedAt   DATETIME     NULL
        COMMENT 'Last unfollow timestamp; NULL if currently following',
    PRIMARY KEY (OrgFollowerId),
    UNIQUE KEY uq_org_user         (OrgId, UserId),
    KEY idx_orgfollowers_org       (OrgId,  IsFollowing),
    KEY idx_orgfollowers_user      (UserId, IsFollowing),
    CONSTRAINT fk_orgfollowers_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orgfollowers_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── 2. New column: Organisations.FollowerCount ─────────────
--
-- Denormalized counter maintained by Org_Follow / Org_Unfollow.
-- MySQL 8 does not support ADD COLUMN IF NOT EXISTS (MariaDB only);
-- use an INFORMATION_SCHEMA guard for idempotency.
--
SET @_fc = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'Organisations'
      AND COLUMN_NAME  = 'FollowerCount'
);
SET @_sql = IF(@_fc = 0,
    'ALTER TABLE Organisations ADD COLUMN FollowerCount INT UNSIGNED NOT NULL DEFAULT 0 COMMENT ''Denormalized follower count — maintained by Org_Follow / Org_Unfollow SPs''',
    'SELECT ''FollowerCount column already exists — skipped'' AS Info'
);
PREPARE _stmt FROM @_sql;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;


-- ════════════════════════════════════════════════════════════
-- SECTION 2 — STORED PROCEDURES
-- ════════════════════════════════════════════════════════════

DELIMITER //


-- ── 3. Org_Follow (NEW) ─────────────────────────────────────
--
-- Follow an NGO. Idempotent: returns success if already following.
-- INSERT ... ON DUPLICATE KEY UPDATE handles first-follow vs re-follow.
-- Increments Organisations.FollowerCount only when state changes 0→1.
--
DROP PROCEDURE IF EXISTS Org_Follow //
CREATE PROCEDURE Org_Follow(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsFollowing TINYINT DEFAULT 0;

    SELECT IFNULL(IsFollowing, 0) INTO v_IsFollowing
    FROM OrgFollowers
    WHERE OrgId = p_OrgId AND UserId = p_UserId;

    IF v_IsFollowing = 1 THEN
        SELECT 1 AS IsSuccess, 'Already following.' AS Message;
    ELSE
        INSERT INTO OrgFollowers (OrgId, UserId, IsFollowing, FollowedAt, UnfollowedAt)
        VALUES (p_OrgId, p_UserId, 1, NOW(), NULL)
        ON DUPLICATE KEY UPDATE
            IsFollowing  = 1,
            FollowedAt   = NOW(),
            UnfollowedAt = NULL;

        UPDATE Organisations
        SET FollowerCount = FollowerCount + 1
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Now following.' AS Message;
    END IF;
END //


-- ── 4. Org_Unfollow (NEW) ────────────────────────────────────
--
-- Soft-unfollow: keep the row, flip IsFollowing=0. Idempotent.
-- Decrements FollowerCount with GREATEST floor at 0.
--
DROP PROCEDURE IF EXISTS Org_Unfollow //
CREATE PROCEDURE Org_Unfollow(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsFollowing TINYINT DEFAULT 0;

    SELECT IFNULL(IsFollowing, 0) INTO v_IsFollowing
    FROM OrgFollowers
    WHERE OrgId = p_OrgId AND UserId = p_UserId;

    IF v_IsFollowing = 0 THEN
        SELECT 1 AS IsSuccess, 'Not currently following.' AS Message;
    ELSE
        UPDATE OrgFollowers
        SET IsFollowing  = 0,
            UnfollowedAt = NOW()
        WHERE OrgId = p_OrgId AND UserId = p_UserId;

        UPDATE Organisations
        SET FollowerCount = GREATEST(FollowerCount - 1, 0)
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Unfollowed.' AS Message;
    END IF;
END //


-- ── 5. Post_GetPermissions (NEW) ─────────────────────────────
--
-- Returns exactly one row. DECLARE defaults cover the non-member case
-- (IsMember=0, CanPost=0, MaxPostsPerDay=10, TodayPostCount=0).
-- Called by mobile HomeScreen before opening Create Post modal.
--
DROP PROCEDURE IF EXISTS Post_GetPermissions //
CREATE PROCEDURE Post_GetPermissions(IN p_OrgId INT UNSIGNED, IN p_UserId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_IsMember      TINYINT(1)  DEFAULT 0;
    DECLARE v_CanPost       TINYINT(1)  DEFAULT 0;
    DECLARE v_MaxPerDay     INT         DEFAULT 10;
    DECLARE v_TodayCount    INT         DEFAULT 0;

    -- Resolve APPROVED status LookupValueId
    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    -- Load member permissions (only if APPROVED member)
    SELECT 1, om.CanPost, om.MaxPostsPerDay
    INTO   v_IsMember, v_CanPost, v_MaxPerDay
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    -- Count posts created today by this user for this org
    SELECT COUNT(*) INTO v_TodayCount
    FROM   Posts
    WHERE  UserId = p_UserId AND OrgId = p_OrgId
      AND  DATE(CreatedAt) = CURDATE() AND IsDeleted = 0;

    SELECT
        v_IsMember   AS IsMember,
        v_CanPost    AS CanPost,
        v_MaxPerDay  AS MaxPostsPerDay,
        v_TodayCount AS TodayPostCount;
END //


-- ── 6. Org_GetPendingMembers (FIXED) ─────────────────────────
--
-- Fix 1: mr.RequestId aliased as MembershipRequestId so the mobile
--        OrgMember.membershipRequestId is populated → Approve button works.
-- Fix 2: IFNULL defaults for p_PageNumber / p_PageSize prevent
--        LIMIT NULL OFFSET NULL when DAL passes 0 params.
--
DROP PROCEDURE IF EXISTS Org_GetPendingMembers //
CREATE PROCEDURE Org_GetPendingMembers(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset      INT;
    DECLARE v_PageSize    INT;
    DECLARE v_PageNumber  INT;
    DECLARE v_PendingLkpId INT UNSIGNED;

    SET v_PageNumber = IFNULL(p_PageNumber, 1);
    SET v_PageSize   = IFNULL(p_PageSize,   100);
    SET v_Offset     = (v_PageNumber - 1) * v_PageSize;

    SELECT LookupValueId INTO v_PendingLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    SELECT
        mr.RequestId   AS MembershipRequestId,
        mr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        up.City,
        up.State,
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.WhyJoin,
        mr.CreatedAt AS RequestedAt
    FROM OrgMembershipRequests mr
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    WHERE mr.OrgId = p_OrgId
      AND mr.StatusLkpId = v_PendingLkpId
      AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC
    LIMIT v_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM OrgMembershipRequests
    WHERE OrgId = p_OrgId
      AND StatusLkpId = v_PendingLkpId
      AND IsDeleted = 0;
END //


-- ── 7. Org_GetProfile (UPDATED) ──────────────────────────────
--
-- Adds: FollowerCount (denormalized), IsFollowing (0|1 for p_UserId).
--
DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED     -- 0 if called by unauthenticated client
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        o.AvgRating, o.RatingCount, o.Latitude, o.Longitude, o.CreatedAt,
        o.FollowerCount,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = o.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        (SELECT COUNT(*)
         FROM OrgMembers   om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        COALESCE(
            (SELECT lv3.ValueCode FROM OrgMembers om3
             JOIN LookupValues lv3 ON om3.StatusLkpId = lv3.LookupValueId
             WHERE om3.OrgId = o.OrgId AND om3.UserId = p_UserId AND om3.IsDeleted = 0 LIMIT 1),
            (SELECT lv4.ValueCode FROM OrgMembershipRequests mr4
             JOIN LookupValues lv4 ON mr4.StatusLkpId = lv4.LookupValueId
             WHERE mr4.OrgId = o.OrgId AND mr4.UserId = p_UserId AND mr4.IsDeleted = 0
               AND lv4.ValueCode = 'PENDING' LIMIT 1)
        ) AS MemberStatusCode
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId  = sv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //


-- ── 8. Org_RequestMembership (UPDATED) ───────────────────────
--
-- Auto-follows on join request. Follow persists even if request is
-- later rejected — only an explicit Unfollow removes it.
-- Handles: first-follow / re-follow / already-following (idempotent counter).
--
DROP PROCEDURE IF EXISTS Org_RequestMembership //
CREATE PROCEDURE Org_RequestMembership(
    IN p_OrgId             INT UNSIGNED,
    IN p_UserId            INT UNSIGNED,
    IN p_PrevNgoExperience TEXT,
    IN p_VolunteerSkills   TEXT,
    IN p_AreasOfInterest   TEXT,
    IN p_WhyJoin           TEXT
)
BEGIN
    DECLARE v_Exists       INT DEFAULT 0;
    DECLARE v_IsMember     INT DEFAULT 0;
    DECLARE v_StatusLkpId  INT UNSIGNED;
    DECLARE v_WasFollowing TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_IsMember FROM OrgMembers
    WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

    IF v_IsMember > 0 THEN
        SELECT 0 AS IsSuccess, 'Already a member of this organisation.' AS Message, NULL AS RequestId;
    ELSE
        SELECT COUNT(*) INTO v_Exists FROM OrgMembershipRequests
        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess, 'Request already submitted.' AS Message, NULL AS RequestId;
        ELSE
            SELECT LookupValueId INTO v_StatusLkpId
            FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            INSERT INTO OrgMembershipRequests
                (OrgId, UserId, PrevNgoExperience, VolunteerSkills, AreasOfInterest, WhyJoin, StatusLkpId)
            VALUES
                (p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin, v_StatusLkpId);

            SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message, LAST_INSERT_ID() AS RequestId;

            -- Auto-follow: capture state first to know whether counter needs increment
            SELECT IFNULL(IsFollowing, 0) INTO v_WasFollowing
            FROM OrgFollowers WHERE OrgId = p_OrgId AND UserId = p_UserId;

            INSERT INTO OrgFollowers (OrgId, UserId, IsFollowing, FollowedAt, UnfollowedAt)
            VALUES (p_OrgId, p_UserId, 1, NOW(), NULL)
            ON DUPLICATE KEY UPDATE
                IsFollowing  = 1,
                FollowedAt   = NOW(),
                UnfollowedAt = NULL;

            IF v_WasFollowing = 0 THEN
                UPDATE Organisations SET FollowerCount = FollowerCount + 1 WHERE OrgId = p_OrgId;
            END IF;
        END IF;
    END IF;
END //


-- ── 9. Org_List (UPDATED) ────────────────────────────────────
--
-- Adds: FollowerCount from denormalized column.
--
DROP PROCEDURE IF EXISTS Org_List //
CREATE PROCEDURE Org_List(
    IN p_Keyword    VARCHAR(200),
    IN p_Category   VARCHAR(100),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset     INT DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        o.FollowerCount,
        IFNULL((SELECT COUNT(*)
                FROM OrgMembers om2
                JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
                JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating,
        o.Latitude,
        o.Longitude
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category)
    ORDER BY o.OrgName
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //


-- ── 10. Post_GetFeed (MERGED FINAL VERSION) ───────────────────
--
-- This is the definitive version merging two prior patches:
--   • OrgFilter patch  : added p_OrgId (4th param, NULL = all orgs)
--   • OrgFollow patch  : added IsFollowing per post
-- Both features are now combined. DAL passes 4 params in this order:
--   p_UserId, p_OrgId (null), p_PageNumber, p_PageSize
--
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
        (SELECT COUNT(*) FROM PostLikes
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto,
        p.OrgId,
        o.OrgName,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
        GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,
        p.CreatedAt,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1
                THEN 'Just now'
            WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
            WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30
                THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), ' days ago')
            ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
        END AS TimeAgo
    FROM   Posts p
    JOIN   UserProfiles up          ON up.UserId           = p.UserId    AND up.IsDeleted = 0
    LEFT JOIN Organisations o       ON o.OrgId             = p.OrgId
    LEFT JOIN LookupValues lv_type  ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm           ON pm.PostId           = p.PostId
    LEFT JOIN LookupValues lv_mt    ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
    GROUP BY
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,   p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId);
END //


-- ── 11. Org_GetDashboard (UPDATED) ───────────────────────────
--
-- Adds: FollowerCount KPI (reads from denormalized column — no COUNT query).
-- Prerequisite: OrgFollowers table + Organisations.FollowerCount must exist (DDL above).
--
DROP PROCEDURE IF EXISTS Org_GetDashboard //
CREATE PROCEDURE Org_GetDashboard(IN p_OrgId INT UNSIGNED)
BEGIN
    DECLARE v_ApprovedMemberStatusId INT UNSIGNED;
    DECLARE v_ActiveProjectStatusId  INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_ApprovedMemberStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT lv.LookupValueId INTO v_ActiveProjectStatusId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE' LIMIT 1;

    SELECT
        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
        ) AS TotalMembers,

        (SELECT COUNT(*) FROM OrgMembers
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0
           AND YEAR(JoinedAt) = YEAR(NOW()) AND MONTH(JoinedAt) = MONTH(NOW())
        ) AS NewMembersThisMonth,

        (SELECT COUNT(DISTINCT pa.UserId)
         FROM ProjectAttendance pa
         JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
         JOIN Projects           p ON ps.ProjectId = p.ProjectId
         JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
         JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId
           AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
           AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ) AS ActiveVolunteers,

        ROUND(CASE
            WHEN (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                  AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0) = 0 THEN 0
            ELSE (SELECT COUNT(DISTINCT pa.UserId)
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW()))
                 * 100.0
                 / (SELECT COUNT(*) FROM OrgMembers WHERE OrgId = p_OrgId
                    AND StatusLkpId = v_ApprovedMemberStatusId AND IsDeleted = 0)
        END, 1) AS ActiveRatePct,

        COALESCE((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                  FROM ProjectAttendance pa
                  JOIN ProjectSessions   ps ON pa.SessionId = ps.SessionId
                  JOIN Projects           p ON ps.ProjectId = p.ProjectId
                  JOIN LookupValues      lv ON pa.AttendStatusLkpId = lv.LookupValueId
                  JOIN LookupTypes       lt ON lv.LookupTypeId = lt.LookupTypeId
                  WHERE p.OrgId = p_OrgId
                    AND lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED'
                    AND YEAR(pa.CreatedAt) = YEAR(NOW()) AND MONTH(pa.CreatedAt) = MONTH(NOW())
        ), 0) AS VolunteerHoursMonth,

        (SELECT COUNT(*) FROM Projects
         WHERE OrgId = p_OrgId AND StatusLkpId = v_ActiveProjectStatusId AND IsDeleted = 0
        ) AS ActiveProjects,

        (SELECT COUNT(*)
         FROM OrgMembershipRequests mr
         JOIN LookupValues lv ON mr.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE mr.OrgId = p_OrgId AND mr.IsDeleted = 0
           AND lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingApplications,

        (SELECT COUNT(*)
         FROM ProjectApplications pa
         JOIN Projects    p  ON pa.ProjectId = p.ProjectId
         JOIN LookupValues lv ON pa.StatusLkpId = lv.LookupValueId
         JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
         WHERE p.OrgId = p_OrgId AND pa.IsDeleted = 0
           AND lt.TypeCode = 'APPLICATION_STATUS' AND lv.ValueCode = 'PENDING'
        ) AS PendingProjectApplications,

        (SELECT FollowerCount FROM Organisations WHERE OrgId = p_OrgId) AS FollowerCount;
END //


-- ── 12. Org_GetVolunteerProfile (FIXED) ──────────────────────
--
-- Fix 1: AttendanceStatus column does not exist →
--        use AttendStatusLkpId via DECLARE'd LookupValueId variables.
-- Fix 2: pa.ProjectId does not exist on ProjectAttendance →
--        route pa → ps (ProjectSessions) → p (Projects).
-- Fix 3: ReliabilityPct inline subquery rewired as HAVING aggregate.
--
DROP PROCEDURE IF EXISTS Org_GetVolunteerProfile //
CREATE PROCEDURE Org_GetVolunteerProfile(IN p_OrgId INT, IN p_UserId INT)
BEGIN
    DECLARE v_AttendedLkpId INT UNSIGNED;
    DECLARE v_ExcusedLkpId  INT UNSIGNED;
    DECLARE v_NoShowLkpId   INT UNSIGNED;

    SELECT LookupValueId INTO v_AttendedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'ATTENDED' LIMIT 1;

    SELECT LookupValueId INTO v_ExcusedLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'EXCUSED' LIMIT 1;

    SELECT LookupValueId INTO v_NoShowLkpId
    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ATTENDANCE_STATUS' AND lv.ValueCode = 'NO_SHOW' LIMIT 1;

    SELECT
        u.UserId,
        CONCAT(COALESCE(up.FirstName,''), ' ', COALESCE(up.LastName,'')) AS FullName,
        up.City, up.State, up.Occupation, up.ProfilePhoto, up.Bio, up.VolunteerExp,
        IFNULL((SELECT SUM(TIMESTAMPDIFF(MINUTE, ps.StartTime, ps.EndTime)) / 60.0
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS TotalHours,
        IFNULL((SELECT COUNT(DISTINCT ps.ProjectId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS ProjectCount,
        IFNULL((SELECT COUNT(DISTINCT p.OrgId)
                FROM ProjectAttendance pa
                JOIN ProjectSessions ps ON pa.SessionId = ps.SessionId
                JOIN Projects p ON ps.ProjectId = p.ProjectId
                WHERE pa.UserId = p_UserId AND pa.AttendStatusLkpId = v_AttendedLkpId), 0) AS OrgCount,
        ROUND(IFNULL((SELECT SUM(CASE WHEN pa.AttendStatusLkpId IN (v_AttendedLkpId, v_ExcusedLkpId) THEN 1 ELSE 0 END)
                            / COUNT(*) * 100
                      FROM ProjectAttendance pa
                      WHERE pa.UserId = p_UserId
                      HAVING COUNT(*) > 0), 100), 2) AS ReliabilityPct,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance
                WHERE UserId = p_UserId AND AttendStatusLkpId = v_NoShowLkpId), 0) AS NoShowCount,
        IFNULL((SELECT COUNT(*) FROM ProjectAttendance
                WHERE UserId = p_UserId AND AttendStatusLkpId = v_ExcusedLkpId), 0) AS ExcusedCount,
        IFNULL((SELECT COUNT(*) FROM PostReports pr
                JOIN Posts po ON pr.PostId = po.PostId
                WHERE po.UserId = p_UserId), 0) AS ComplaintCount,
        lv_role.ValueCode   AS RoleCode,   lv_role.ValueName   AS RoleName,
        lv_status.ValueCode AS StatusCode, lv_status.ValueName AS StatusName,
        om.CreatedAt AS JoinedAt,
        mr.PrevNgoExperience, mr.VolunteerSkills, mr.AreasOfInterest, mr.WhyJoin,
        mr.CreatedAt AS RequestedAt
    FROM Users u
    JOIN  UserProfiles     up       ON up.UserId  = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers   om       ON om.OrgId   = p_OrgId AND om.UserId = p_UserId AND om.IsDeleted = 0
    LEFT JOIN LookupValues lv_role   ON lv_role.LookupValueId   = om.RoleLkpId
    LEFT JOIN LookupValues lv_status ON lv_status.LookupValueId = om.StatusLkpId
    LEFT JOIN OrgMembershipRequests mr ON mr.RequestId = (
        SELECT RequestId FROM OrgMembershipRequests
        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0
        ORDER BY CreatedAt DESC LIMIT 1
    )
    WHERE u.UserId = p_UserId AND u.IsDeleted = 0;
END //


-- ── 13. SuperAdmin_User_GetList (FIXED) ──────────────────────
--
-- v4.6 addendum — safe to re-run if already applied.
-- Fix: JOIN → LEFT JOIN OrgMembers so new users with no org appear.
--      HAVING clause: show users with no membership OR at least one APPROVED membership.
--      OrgNames: APPROVED orgs only.
--      JoinedAt: falls back to u.CreatedAt for new users.
--
DROP PROCEDURE IF EXISTS SuperAdmin_User_GetList //
CREATE PROCEDURE SuperAdmin_User_GetList(
    IN p_OrgIds     TEXT,
    IN p_Search     VARCHAR(150),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        u.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        u.Email, u.Mobile, up.ProfilePhoto,
        GROUP_CONCAT(DISTINCT CASE WHEN sv.ValueCode = 'APPROVED' THEN o.OrgName END
                     ORDER BY o.OrgName SEPARATOR ', ') AS OrgNames,
        (SELECT rv.ValueName FROM OrgMembers om2
            JOIN LookupValues rv ON om2.RoleLkpId = rv.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS Role,
        (SELECT sv2.ValueCode FROM OrgMembers om2
            JOIN LookupValues sv2 ON om2.StatusLkpId = sv2.LookupValueId
            WHERE om2.UserId = u.UserId AND om2.IsDeleted = 0
            ORDER BY om2.JoinedAt DESC LIMIT 1) AS MembershipStatus,
        IF(u.IsActive = 1, 'ACTIVE', 'SUSPENDED') AS AccountStatus,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatus,
        COALESCE(
            MIN(CASE WHEN sv.ValueCode = 'APPROVED' THEN om.JoinedAt END),
            u.CreatedAt
        ) AS JoinedAt
    FROM Users u
    JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
    LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
        AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
    LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
    LEFT JOIN Organisations  o ON om.OrgId = o.OrgId AND o.IsDeleted = 0
    LEFT JOIN LookupValues  pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE u.IsDeleted = 0
      AND (p_Search IS NULL OR p_Search = ''
           OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
           OR u.Email  LIKE CONCAT('%', p_Search, '%')
           OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
    GROUP BY
        u.UserId, up.FirstName, up.LastName, u.Email, u.Mobile,
        up.ProfilePhoto, u.IsActive, pv.ValueCode, u.CreatedAt
    HAVING
        (COUNT(om.OrgMemberId) = 0 AND (p_OrgIds IS NULL OR p_OrgIds = ''))
        OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ORDER BY JoinedAt DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM (
        SELECT u.UserId
        FROM Users u
        JOIN  UserProfiles up ON up.UserId = u.UserId AND up.IsDeleted = 0
        LEFT JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            AND (p_OrgIds IS NULL OR p_OrgIds = '' OR FIND_IN_SET(om.OrgId, p_OrgIds) > 0)
        LEFT JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
        WHERE u.IsDeleted = 0
          AND (p_Search IS NULL OR p_Search = ''
               OR CONCAT(up.FirstName, ' ', up.LastName) LIKE CONCAT('%', p_Search, '%')
               OR u.Email  LIKE CONCAT('%', p_Search, '%')
               OR u.Mobile LIKE CONCAT('%', p_Search, '%'))
        GROUP BY u.UserId
        HAVING
            (COUNT(om.OrgMemberId) = 0 AND (p_OrgIds IS NULL OR p_OrgIds = ''))
            OR SUM(CASE WHEN sv.ValueCode = 'APPROVED' THEN 1 ELSE 0 END) > 0
    ) t;
END //


DELIMITER ;

-- ============================================================
-- END OF PATCH v4.7
-- ──────────────────────────────────────────────────────────
-- New tables   : 1  (OrgFollowers)
-- New columns  : 1  (Organisations.FollowerCount)
-- New SPs      : 3  (Org_Follow, Org_Unfollow, Post_GetPermissions)
-- Updated SPs  : 8  (Org_GetPendingMembers, Org_GetProfile,
--                    Org_RequestMembership, Org_List, Post_GetFeed,
--                    Org_GetDashboard, Org_GetVolunteerProfile,
--                    SuperAdmin_User_GetList)
-- ============================================================

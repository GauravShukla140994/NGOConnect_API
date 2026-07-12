-- ============================================================
-- Patch: NGO Follow Feature
-- Version: v4.6 patch
--
-- Changes applied:
--   1. NEW TABLE   OrgFollowers           — soft-unfollow pattern (IsFollowing + UnfollowedAt)
--   2. NEW COLUMN  Organisations.FollowerCount — denormalized; maintained by SPs below
--   3. NEW SP      Org_Follow             — follow / re-follow (INSERT ... ON DUPLICATE KEY UPDATE)
--   4. NEW SP      Org_Unfollow           — soft unfollow (UPDATE IsFollowing=0, UnfollowedAt=NOW())
--   5. UPDATED SP  Org_GetProfile         — adds FollowerCount + IsFollowing
--   6. UPDATED SP  Post_GetFeed           — adds IsFollowing per post (for post menu toggle)
--   7. UPDATED SP  Org_List               — adds FollowerCount from denormalized column
--   8. UPDATED SP  Org_RequestMembership  — auto-follows on join request; follow persists
--                                           even if request rejected; only explicit unfollow removes it
--
-- How to apply:
--   Run this file in MySQL Workbench against Railway staging, then production.
-- ============================================================

USE ngoconnect;

-- ── 1. New table: OrgFollowers ──────────────────────────────────────────────────
--
-- Design: one row per (OrgId, UserId) pair — UNIQUE KEY ensures no duplicates.
-- Soft-unfollow: IsFollowing=0 + UnfollowedAt=NOW() instead of deleting the row.
-- Re-follow: UPDATE IsFollowing=1, FollowedAt=NOW(), UnfollowedAt=NULL on the same row.
-- History: FollowedAt = last follow timestamp, UnfollowedAt = last unfollow timestamp.
--
CREATE TABLE IF NOT EXISTS OrgFollowers (
    OrgFollowerId  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    OrgId          INT UNSIGNED NOT NULL,
    UserId         INT UNSIGNED NOT NULL,
    IsFollowing    TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '1 = currently following, 0 = unfollowed',
    FollowedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Last follow timestamp',
    UnfollowedAt   DATETIME     NULL     COMMENT 'Last unfollow timestamp; NULL if currently following',
    PRIMARY KEY (OrgFollowerId),
    UNIQUE KEY uq_org_user        (OrgId, UserId),
    KEY idx_orgfollowers_org      (OrgId,  IsFollowing),
    KEY idx_orgfollowers_user     (UserId, IsFollowing),
    CONSTRAINT fk_orgfollowers_org  FOREIGN KEY (OrgId)  REFERENCES Organisations(OrgId),
    CONSTRAINT fk_orgfollowers_user FOREIGN KEY (UserId) REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── 2. New column: Organisations.FollowerCount ──────────────────────────────────
--
-- Denormalized counter — incremented by Org_Follow, decremented by Org_Unfollow.
-- Never run COUNT(*) on OrgFollowers on the hot read path; always read this column.
--
-- MySQL 8 does not support ADD COLUMN IF NOT EXISTS (MariaDB-only syntax).
-- Use a prepared statement against INFORMATION_SCHEMA for idempotency.
SET @_fc = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'Organisations'
      AND COLUMN_NAME  = 'FollowerCount'
);
SET @_sql = IF(@_fc = 0,
    'ALTER TABLE Organisations ADD COLUMN FollowerCount INT UNSIGNED NOT NULL DEFAULT 0 COMMENT ''Denormalized follower count - maintained by Org_Follow / Org_Unfollow SPs''',
    'SELECT ''FollowerCount column already exists - skipped'' AS Info'
);
PREPARE _stmt FROM @_sql;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;


-- ── 3–7. Stored Procedures ──────────────────────────────────────────────────────

DELIMITER //

-- ── 3. Org_Follow ───────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Org_Follow //
CREATE PROCEDURE Org_Follow(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    DECLARE v_IsFollowing TINYINT DEFAULT 0;

    -- Check current state (NULL if no row yet)
    SELECT IFNULL(IsFollowing, 0) INTO v_IsFollowing
    FROM OrgFollowers
    WHERE OrgId = p_OrgId AND UserId = p_UserId;

    IF v_IsFollowing = 1 THEN
        -- Already following — idempotent, return success with no changes
        SELECT 1 AS IsSuccess, 'Already following.' AS Message;
    ELSE
        -- New follow (INSERT) or re-follow (ON DUPLICATE KEY UPDATE)
        INSERT INTO OrgFollowers (OrgId, UserId, IsFollowing, FollowedAt, UnfollowedAt)
        VALUES (p_OrgId, p_UserId, 1, NOW(), NULL)
        ON DUPLICATE KEY UPDATE
            IsFollowing  = 1,
            FollowedAt   = NOW(),
            UnfollowedAt = NULL;

        -- Increment denormalized counter
        UPDATE Organisations
        SET FollowerCount = FollowerCount + 1
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Now following.' AS Message;
    END IF;
END //


-- ── 4. Org_Unfollow ─────────────────────────────────────────────────────────────
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
        -- Not currently following — idempotent
        SELECT 1 AS IsSuccess, 'Not currently following.' AS Message;
    ELSE
        -- Soft-unfollow: keep the row, flip the flag
        UPDATE OrgFollowers
        SET IsFollowing  = 0,
            UnfollowedAt = NOW()
        WHERE OrgId = p_OrgId AND UserId = p_UserId;

        -- Decrement denormalized counter (floor at 0 to prevent negative)
        UPDATE Organisations
        SET FollowerCount = GREATEST(FollowerCount - 1, 0)
        WHERE OrgId = p_OrgId;

        SELECT 1 AS IsSuccess, 'Unfollowed.' AS Message;
    END IF;
END //


-- ── 5. Org_GetProfile — adds FollowerCount + IsFollowing ───────────────────────
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


-- ── 6. Post_GetFeed — adds IsFollowing per post ─────────────────────────────────
-- IsFollowing: 1 if the requesting user follows this post's org, else 0.
-- For posts with no OrgId (personal posts), IsFollowing = 0.
DROP PROCEDURE IF EXISTS Post_GetFeed //
CREATE PROCEDURE Post_GetFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT DEFAULT (p_PageNumber - 1) * p_PageSize;

    SELECT
        p.PostId, p.Content, p.IsPinned,
        lv_type.ValueCode AS PostTypeLkpCode, lv_type.ValueName AS PostType,
        p.LikeCount, p.CommentCount,
        (SELECT COUNT(*) FROM PostLikes WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLikedByMe,
        p.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        up.ProfilePhoto, p.OrgId, o.OrgName,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
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
    JOIN   UserProfiles up          ON up.UserId = p.UserId AND up.IsDeleted = 0
    LEFT JOIN Organisations o       ON o.OrgId   = p.OrgId
    LEFT JOIN LookupValues lv_type  ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm           ON pm.PostId = p.PostId
    LEFT JOIN LookupValues lv_mt    ON lv_mt.LookupValueId   = pm.MediaTypeLkpId
    WHERE  p.IsDeleted = 0
    GROUP BY p.PostId, p.Content, p.IsPinned, lv_type.ValueCode, lv_type.ValueName,
             p.LikeCount, p.CommentCount, p.UserId, up.FirstName, up.LastName,
             up.ProfilePhoto, p.OrgId, o.OrgName, p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM Posts WHERE IsDeleted = 0;
END //


-- ── 7. Org_List — adds FollowerCount ────────────────────────────────────────────
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

    -- Result set 1: page
    SELECT
        o.OrgId,
        o.OrgName,
        o.Category,
        o.LogoUrl,
        o.City,
        o.State,
        o.FollowerCount,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
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

    -- Result set 2: total count
    SELECT COUNT(*) AS TotalCount
    FROM Organisations o
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND (p_Keyword IS NULL  OR o.OrgName LIKE CONCAT('%', p_Keyword, '%')
                              OR o.City    LIKE CONCAT('%', p_Keyword, '%'))
      AND (p_Category IS NULL OR o.Category = p_Category);
END //

-- ── 8. Org_RequestMembership — auto-follow on join request ─────────────────────
-- Business rule: requesting to join = implicit follow.
-- The follow persists even if the request is later rejected or never approved.
-- Only an explicit "Unfollow" (DELETE /org/{orgId}/follow) removes the follow.
-- Handles all cases:
--   • First-time follower: new row INSERT → counter +1
--   • Previously unfollowed, now re-joining: UPDATE IsFollowing=1 → counter +1
--   • Already following: ON DUPLICATE KEY no-change → counter unchanged
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

            -- Auto-follow: capture state before upsert so we know whether to increment
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

DELIMITER ;

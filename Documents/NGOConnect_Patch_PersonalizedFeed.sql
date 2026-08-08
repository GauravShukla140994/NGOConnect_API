-- ============================================================
-- NGOConnect Patch — Phase 1 Personalised Feed Algorithm
-- Apply to: Railway staging + production
-- Date: 2026-07-12
-- Scope:
--   1. ALTER TABLE Posts     — ShareCount, SaveCount, IsEmergency, IsEvergreen
--   2. CREATE TABLE PostSaves        — user saves a post
--   3. CREATE TABLE FeedInteractions — analytics: impressions, hides, clicks
--   4. Settings seeds                — configurable scoring weights
--   5. Feed_GetPersonalized SP       — multi-source scored ranked feed
--   6. Post_Save / Post_Unsave SPs   — save/unsave a post
--   7. Feed_TrackInteraction SP      — record feed interaction for analytics
-- Does NOT touch: Post_GetFeed, PostController, any existing SP
-- ============================================================

-- ── 1. ALTER TABLE Posts (idempotent — MySQL 8.0 compatible) ─────────────────
-- MySQL 8.0 does not support ADD COLUMN IF NOT EXISTS.
-- Use a helper procedure that checks INFORMATION_SCHEMA before each ALTER.
DROP PROCEDURE IF EXISTS _ngo_add_col;
DELIMITER //
CREATE PROCEDURE _ngo_add_col(IN p_tbl VARCHAR(64), IN p_col VARCHAR(64), IN p_def TEXT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = p_tbl
          AND COLUMN_NAME  = p_col
    ) THEN
        SET @_sql = CONCAT('ALTER TABLE `', p_tbl, '` ADD COLUMN `', p_col, '` ', p_def);
        PREPARE _st FROM @_sql;
        EXECUTE _st;
        DEALLOCATE PREPARE _st;
    END IF;
END //
DELIMITER ;

CALL _ngo_add_col('Posts', 'ShareCount',  'INT UNSIGNED NOT NULL DEFAULT 0 AFTER CommentCount');
CALL _ngo_add_col('Posts', 'SaveCount',   'INT UNSIGNED NOT NULL DEFAULT 0 AFTER ShareCount');
CALL _ngo_add_col('Posts', 'IsEmergency', 'TINYINT(1)  NOT NULL DEFAULT 0 AFTER IsPinned');
CALL _ngo_add_col('Posts', 'IsEvergreen', 'TINYINT(1)  NOT NULL DEFAULT 0 AFTER IsEmergency');

DROP PROCEDURE IF EXISTS _ngo_add_col;

-- ── 2. CREATE TABLE PostSaves ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS PostSaves (
    PostSaveId  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    PostId      INT UNSIGNED    NOT NULL,
    UserId      INT UNSIGNED    NOT NULL,
    CreatedAt   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PostSaveId),
    UNIQUE KEY  uq_postsave_post_user (PostId, UserId),
    INDEX       idx_postsave_user     (UserId),
    CONSTRAINT  fk_postsave_post FOREIGN KEY (PostId)  REFERENCES Posts(PostId),
    CONSTRAINT  fk_postsave_user FOREIGN KEY (UserId)  REFERENCES Users(UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 3. CREATE TABLE FeedInteractions ─────────────────────────────────────────
-- Every user action on a feed post is recorded here for future AI training.
CREATE TABLE IF NOT EXISTS FeedInteractions (
    InteractionId   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    UserId          INT UNSIGNED    NOT NULL,
    PostId          INT UNSIGNED    NOT NULL,
    -- InteractionType: IMPRESSION | VIEW | LIKE | COMMENT | SHARE | SAVE
    --                  VOLUNTEER_CLICK | DONATION_CLICK | NGO_VISIT | HIDE | REPORT
    InteractionType VARCHAR(30)     NOT NULL,
    DurationMs      INT UNSIGNED    NULL COMMENT 'Read duration in milliseconds (VIEW only)',
    CreatedAt       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (InteractionId),
    INDEX idx_feedint_user    (UserId, CreatedAt),
    INDEX idx_feedint_post    (PostId, InteractionType),
    CONSTRAINT fk_feedint_user FOREIGN KEY (UserId) REFERENCES Users(UserId),
    CONSTRAINT fk_feedint_post FOREIGN KEY (PostId) REFERENCES Posts(PostId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── 4. Settings seeds — feed scoring weights ──────────────────────────────────
-- All weights are configurable from the Settings table; no code redeploy needed.
INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES
    ('FEED', 'FEED_W_RELATIONSHIP',   '50',  'NUMBER', 'Feed score: weight for member/follower of same org (max)',           0),
    ('FEED', 'FEED_W_FOLLOW_ORG',     '30',  'NUMBER', 'Feed score: weight when user follows the org (not member)',          0),
    ('FEED', 'FEED_W_INTEREST',       '30',  'NUMBER', 'Feed score: weight when post type matches user interests',          0),
    ('FEED', 'FEED_W_SKILL',          '10',  'NUMBER', 'Feed score: weight per skill keyword match in post content (max 20)',0),
    ('FEED', 'FEED_W_FRESHNESS_1H',   '25',  'NUMBER', 'Feed score: freshness — post < 1 hour old',                         0),
    ('FEED', 'FEED_W_FRESHNESS_6H',   '20',  'NUMBER', 'Feed score: freshness — post < 6 hours old',                        0),
    ('FEED', 'FEED_W_FRESHNESS_24H',  '15',  'NUMBER', 'Feed score: freshness — post < 24 hours old',                       0),
    ('FEED', 'FEED_W_FRESHNESS_3D',   '10',  'NUMBER', 'Feed score: freshness — post 1–3 days old',                         0),
    ('FEED', 'FEED_W_FRESHNESS_7D',   '5',   'NUMBER', 'Feed score: freshness — post 3–7 days old',                         0),
    ('FEED', 'FEED_W_FRESHNESS_OLD',  '2',   'NUMBER', 'Feed score: freshness — post > 7 days (evergreen only)',             0),
    ('FEED', 'FEED_W_ENGAGEMENT_MAX', '15',  'NUMBER', 'Feed score: engagement score cap',                                  0),
    ('FEED', 'FEED_W_TRUST',          '10',  'NUMBER', 'Feed score: org is APPROVED (trust bonus)',                         0),
    ('FEED', 'FEED_W_QUALITY_MEDIA',  '5',   'NUMBER', 'Feed score: post has media attachment',                             0),
    ('FEED', 'FEED_W_QUALITY_LENGTH', '5',   'NUMBER', 'Feed score: post content > 100 chars',                              0),
    ('FEED', 'FEED_W_SPAM_PER_RPT',   '5',   'NUMBER', 'Feed score: penalty per report on this post',                       0),
    ('FEED', 'FEED_W_EMERGENCY',      '1000','NUMBER', 'Feed score: emergency override boost',                              0),
    ('FEED', 'FEED_CANDIDATE_MY_ORG', '200', 'NUMBER', 'Candidate pool: max posts from user member orgs (days=30)',         0),
    ('FEED', 'FEED_CANDIDATE_FOLLOW', '200', 'NUMBER', 'Candidate pool: max posts from followed orgs (days=30)',            0),
    ('FEED', 'FEED_CANDIDATE_TREND',  '100', 'NUMBER', 'Candidate pool: max trending posts (days=7)',                       0),
    ('FEED', 'FEED_CANDIDATE_EMERG',  '50',  'NUMBER', 'Candidate pool: max emergency posts (hours=48)',                    0),
    ('FEED', 'FEED_CANDIDATE_INTST',  '100', 'NUMBER', 'Candidate pool: max interest-matched posts (days=14)',              0),
    ('FEED', 'FEED_CANDIDATE_RECENT', '100', 'NUMBER', 'Candidate pool: recent public fallback (days=7)',                   0);

-- ── 5. Feed_GetPersonalized ───────────────────────────────────────────────────
DELIMITER //

DROP PROCEDURE IF EXISTS Feed_GetPersonalized //
CREATE PROCEDURE Feed_GetPersonalized(
    IN p_UserId       INT UNSIGNED,
    IN p_CursorPostId INT UNSIGNED,    -- NULL = first page
    IN p_CursorScore  DECIMAL(10,4),   -- NULL = first page
    IN p_PageSize     INT              -- items per page (default 20); SP returns 3x for diversity buffer
)
BEGIN
    -- Return 3× pageSize so the C# diversity engine has enough candidates
    -- to fill a full page after interleaving.
    DECLARE v_FetchSize INT DEFAULT p_PageSize * 3;

    -- ── Outer cursor filter wraps the scored subquery ─────────────────────────
    SELECT sf.* FROM (

        -- ── Scored candidates ─────────────────────────────────────────────────
        SELECT
            p.PostId,
            p.Content,
            p.IsPinned,
            p.IsEmergency,
            p.IsEvergreen,
            p.LikeCount,
            p.CommentCount,
            p.ShareCount,
            p.SaveCount,
            lv_type.ValueCode  AS PostTypeCode,
            lv_type.ValueName  AS PostType,
            p.UserId,
            CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
            up.ProfilePhoto,
            p.OrgId,
            o.OrgName,
            o.LogoUrl          AS OrgLogoUrl,
            cands.FeedSource,

            -- IsLiked
            (SELECT COUNT(*) FROM PostLikes pl
             WHERE pl.PostId = p.PostId AND pl.UserId = p_UserId)  AS IsLiked,

            -- IsSaved
            (SELECT COUNT(*) FROM PostSaves ps
             WHERE ps.PostId = p.PostId AND ps.UserId = p_UserId)  AS IsSaved,

            -- IsFollowing org
            IFNULL((SELECT of2.IsFollowing FROM OrgFollowers of2
                    WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId LIMIT 1), 0) AS IsFollowing,

            -- Media
            GROUP_CONCAT(pm.FileUrl      ORDER BY pm.SortOrder SEPARATOR ',') AS MediaUrls,
            GROUP_CONCAT(lv_mt.ValueCode ORDER BY pm.SortOrder SEPARATOR ',') AS MediaTypes,

            p.CreatedAt,
            CASE
                WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 1   THEN 'Just now'
                WHEN TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()) < 60  THEN CONCAT(TIMESTAMPDIFF(MINUTE, p.CreatedAt, NOW()), 'm ago')
                WHEN TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()) < 24  THEN CONCAT(TIMESTAMPDIFF(HOUR,   p.CreatedAt, NOW()), 'h ago')
                WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 7   THEN CONCAT(TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()), 'd ago')
                WHEN TIMESTAMPDIFF(DAY,    p.CreatedAt, NOW()) < 30  THEN CONCAT(FLOOR(TIMESTAMPDIFF(DAY, p.CreatedAt, NOW()) / 7), 'w ago')
                ELSE DATE_FORMAT(p.CreatedAt, '%d %b %Y')
            END AS TimeAgo,

            -- ── Feed Score ────────────────────────────────────────────────────
            (
                -- Relationship Score (0–50)
                -- +50 if user is an approved member of the post's org
                -- +30 if user follows the org (not a member)
                CASE
                    WHEN EXISTS(
                        SELECT 1 FROM OrgMembers om
                        JOIN LookupValues lvm ON om.StatusLkpId = lvm.LookupValueId
                        WHERE om.OrgId = p.OrgId AND om.UserId = p_UserId
                          AND om.IsDeleted = 0 AND lvm.ValueCode = 'APPROVED'
                    ) THEN 50
                    WHEN EXISTS(
                        SELECT 1 FROM OrgFollowers of3
                        WHERE of3.OrgId = p.OrgId AND of3.UserId = p_UserId AND of3.IsFollowing = 1
                    ) THEN 30
                    ELSE 0
                END

                -- Interest Score (0–30): post type name or content matches a user interest
                + CASE WHEN EXISTS(
                    SELECT 1 FROM UserInterests ui
                    JOIN LookupValues li ON ui.InterestLkpId = li.LookupValueId
                    WHERE ui.UserId = p_UserId
                      AND (
                          LOWER(li.ValueName) LIKE CONCAT('%', LOWER(COALESCE(lv_type.ValueName, '')), '%')
                       OR LOWER(COALESCE(lv_type.ValueName, '')) LIKE CONCAT('%', LOWER(li.ValueName), '%')
                       OR LOWER(COALESCE(p.Content, ''))         LIKE CONCAT('%', LOWER(li.ValueName), '%')
                      )
                ) THEN 30 ELSE 0 END

                -- Skill Match Score (0–20): up to 2 skill keywords found in post content
                + LEAST(20, (
                    SELECT COUNT(*) * 10
                    FROM UserSkills us
                    WHERE us.UserId = p_UserId AND us.IsDeleted = 0
                      AND LOWER(COALESCE(p.Content, '')) LIKE CONCAT('%', LOWER(us.SkillName), '%')
                ))

                -- Freshness Score (0–25)
                + CASE
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 1   THEN 25
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 6   THEN 20
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 24  THEN 15
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 3   THEN 10
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 7   THEN 5
                    ELSE 2
                  END

                -- Engagement Score (0–15): weighted combination of reactions
                + LEAST(15, FLOOR(
                    (p.LikeCount * 0.5 + p.CommentCount * 1.0 + p.ShareCount * 2.0 + p.SaveCount * 1.5)
                    / 10.0
                  ))

                -- Trust Score (0–10): org has APPROVED platform status
                + CASE WHEN EXISTS(
                    SELECT 1 FROM Organisations o2
                    JOIN LookupValues lv_os ON o2.StatusLkpId = lv_os.LookupValueId
                    WHERE o2.OrgId = p.OrgId AND lv_os.ValueCode = 'APPROVED'
                ) THEN 10 ELSE 0 END

                -- Quality Score (0–10)
                + CASE WHEN LENGTH(COALESCE(p.Content, '')) > 100 THEN 5 ELSE 0 END
                + CASE WHEN EXISTS(
                    SELECT 1 FROM PostMedia pm2 WHERE pm2.PostId = p.PostId
                ) THEN 5 ELSE 0 END

                -- Spam Penalty (–5 per report, capped at –20)
                - LEAST(20, COALESCE(
                    (SELECT COUNT(*) * 5 FROM PostReports pr WHERE pr.PostId = p.PostId),
                    0
                  ))

                -- Emergency Override: always floats to top of feed
                + CASE WHEN p.IsEmergency = 1 THEN 1000 ELSE 0 END

            ) AS FeedScore

        FROM Posts p

        -- ── Candidate pool: union of all sources, deduplicated by PostId ──────
        JOIN (
            SELECT PostId, MIN(FeedSource) AS FeedSource
            FROM (
                -- Source 1: Posts from orgs the user is an approved member of (last 30 days)
                (SELECT p1.PostId, 'MY_ORG' AS FeedSource
                FROM Posts p1
                INNER JOIN OrgMembers om1
                       ON om1.OrgId = p1.OrgId AND om1.UserId = p_UserId AND om1.IsDeleted = 0
                INNER JOIN LookupValues lv1
                       ON lv1.LookupValueId = om1.StatusLkpId AND lv1.ValueCode = 'APPROVED'
                WHERE p1.IsDeleted = 0
                  AND p1.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                ORDER BY p1.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- Source 2: Posts from orgs the user follows (last 30 days)
                (SELECT p2.PostId, 'FOLLOWED_ORG' AS FeedSource
                FROM Posts p2
                INNER JOIN OrgFollowers of1
                       ON of1.OrgId = p2.OrgId AND of1.UserId = p_UserId AND of1.IsFollowing = 1
                WHERE p2.IsDeleted = 0
                  AND p2.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                ORDER BY p2.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- Source 3: Trending posts — high weighted engagement (last 7 days)
                (SELECT p3.PostId, 'TRENDING' AS FeedSource
                FROM Posts p3
                WHERE p3.IsDeleted = 0
                  AND p3.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                ORDER BY (p3.LikeCount * 1 + p3.CommentCount * 2 + p3.ShareCount * 3 + p3.SaveCount * 2) DESC
                LIMIT 100)

                UNION ALL

                -- Source 4: Emergency posts (last 48 hours) — bypass normal ranking
                (SELECT p4.PostId, 'EMERGENCY' AS FeedSource
                FROM Posts p4
                WHERE p4.IsDeleted = 0
                  AND p4.IsEmergency = 1
                  AND p4.CreatedAt >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
                ORDER BY p4.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- Source 5: Interest-matched posts (PostType name matches user interest, last 14 days)
                (SELECT p5.PostId, 'INTEREST' AS FeedSource
                FROM Posts p5
                INNER JOIN LookupValues pt5 ON pt5.LookupValueId = p5.PostTypeLkpId
                WHERE p5.IsDeleted = 0
                  AND p5.CreatedAt >= DATE_SUB(NOW(), INTERVAL 14 DAY)
                  AND EXISTS(
                      SELECT 1 FROM UserInterests ui5
                      JOIN LookupValues li5 ON ui5.InterestLkpId = li5.LookupValueId
                      WHERE ui5.UserId = p_UserId
                        AND (LOWER(li5.ValueName) LIKE CONCAT('%', LOWER(pt5.ValueName), '%')
                          OR LOWER(pt5.ValueName) LIKE CONCAT('%', LOWER(li5.ValueName), '%'))
                  )
                ORDER BY p5.CreatedAt DESC LIMIT 100)

                UNION ALL

                -- Source 6: Recent public posts — discovery fallback (last 7 days)
                (SELECT p6.PostId, 'RECENT' AS FeedSource
                FROM Posts p6
                WHERE p6.IsDeleted = 0
                  AND p6.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                ORDER BY p6.CreatedAt DESC LIMIT 100)

            ) all_sources
            GROUP BY PostId   -- deduplicate; MIN(FeedSource) picks the highest-priority label
        ) cands ON cands.PostId = p.PostId

        JOIN   UserProfiles up      ON up.UserId             = p.UserId AND up.IsDeleted = 0
        LEFT JOIN Organisations o   ON o.OrgId               = p.OrgId
        LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
        LEFT JOIN PostMedia pm      ON pm.PostId             = p.PostId
        LEFT JOIN LookupValues lv_mt ON lv_mt.LookupValueId  = pm.MediaTypeLkpId

        WHERE p.IsDeleted = 0

        GROUP BY
            p.PostId,      p.Content,    p.IsPinned,   p.IsEmergency, p.IsEvergreen,
            p.LikeCount,   p.CommentCount, p.ShareCount, p.SaveCount,
            lv_type.ValueCode, lv_type.ValueName,
            p.UserId,      up.FirstName, up.LastName,  up.ProfilePhoto,
            p.OrgId,       o.OrgName,   o.LogoUrl,    cands.FeedSource,
            p.CreatedAt

    ) sf  -- end scored subquery

    -- ── Cursor filter (skip already-seen items) ───────────────────────────────
    -- p_CursorScore now carries UNIX_TIMESTAMP(CreatedAt) of the last seen post.
    -- This gives a strict chronological cursor: newest posts always appear first.
    WHERE  p_CursorScore IS NULL
        OR UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore
        OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)

    ORDER BY sf.CreatedAt DESC, sf.PostId DESC
    LIMIT  v_FetchSize;

END //

-- ── 6. Post_Save ──────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_Save //
CREATE PROCEDURE Post_Save(
    IN p_UserId INT UNSIGNED,
    IN p_PostId INT UNSIGNED
)
BEGIN
    INSERT IGNORE INTO PostSaves (PostId, UserId) VALUES (p_PostId, p_UserId);
    IF ROW_COUNT() > 0 THEN
        UPDATE Posts SET SaveCount = SaveCount + 1 WHERE PostId = p_PostId;
        INSERT INTO FeedInteractions (UserId, PostId, InteractionType) VALUES (p_UserId, p_PostId, 'SAVE');
        SELECT 1 AS IsSuccess, 'Post saved.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Already saved.' AS Message;
    END IF;
END //

-- ── 7. Post_Unsave ────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Post_Unsave //
CREATE PROCEDURE Post_Unsave(
    IN p_UserId INT UNSIGNED,
    IN p_PostId INT UNSIGNED
)
BEGIN
    DELETE FROM PostSaves WHERE PostId = p_PostId AND UserId = p_UserId;
    IF ROW_COUNT() > 0 THEN
        UPDATE Posts SET SaveCount = GREATEST(0, SaveCount - 1) WHERE PostId = p_PostId;
        SELECT 1 AS IsSuccess, 'Post unsaved.' AS Message;
    ELSE
        SELECT 0 AS IsSuccess, 'Not saved.' AS Message;
    END IF;
END //

-- ── 8. Feed_TrackInteraction ──────────────────────────────────────────────────
-- Fire-and-forget analytics recording. Called by mobile on scroll/click events.
-- InteractionType: IMPRESSION | VIEW | LIKE | COMMENT | SHARE | SAVE
--                  VOLUNTEER_CLICK | DONATION_CLICK | NGO_VISIT | HIDE | REPORT
DROP PROCEDURE IF EXISTS Feed_TrackInteraction //
CREATE PROCEDURE Feed_TrackInteraction(
    IN p_UserId          INT UNSIGNED,
    IN p_PostId          INT UNSIGNED,
    IN p_InteractionType VARCHAR(30),
    IN p_DurationMs      INT UNSIGNED   -- NULL for non-VIEW interactions
)
BEGIN
    INSERT INTO FeedInteractions (UserId, PostId, InteractionType, DurationMs)
    VALUES (p_UserId, p_PostId, p_InteractionType, p_DurationMs);
    SELECT 1 AS IsSuccess, 'Tracked.' AS Message;
END //

DELIMITER ;

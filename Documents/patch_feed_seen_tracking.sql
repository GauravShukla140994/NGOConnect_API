-- ============================================================
-- PATCH: Feed Seen-Post Tracking
-- Date       : 2026-08-09
-- Applies to : ngoconnect (Railway Staging + Production)
-- Changes    :
--   1. Feed_GetPersonalized — adds p_SeenExpiryDays param, seen filter,
--      PINNED_EVERGREEN + DISCOVERY buckets, extended time windows.
--   2. Feed_BulkMarkViewed  — new SP: bulk INSERT IGNORE VIEW rows via JSON_TABLE.
--   3. Settings seed        — FEED / FEED_SEEN_EXPIRY_DAYS = 30
--
-- Run order: apply this patch to each running DB (staging then prod).
--            The full NGOConnect_Complete_Setup_v5.0.sql already includes
--            all changes below for fresh installs.
-- ============================================================

USE ngoconnect;

DELIMITER //

-- ── Feed_GetPersonalized ──────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Feed_GetPersonalized //
CREATE PROCEDURE Feed_GetPersonalized(
    IN p_UserId          INT UNSIGNED,
    IN p_CursorPostId    INT UNSIGNED,
    IN p_CursorScore     DECIMAL(10,4),
    IN p_PageSize        INT,
    IN p_SeenExpiryDays  INT          -- how many days to remember a viewed post (default 30)
)
BEGIN
    DECLARE v_FetchSize   INT          DEFAULT p_PageSize * 3;
    DECLARE v_PublicLkpId INT UNSIGNED DEFAULT 0;

    -- Default seen expiry if caller passes NULL
    IF p_SeenExpiryDays IS NULL OR p_SeenExpiryDays <= 0 THEN
        SET p_SeenExpiryDays = 30;
    END IF;

    -- Resolve the 'PUBLIC' visibility LkpId once — used to pre-filter candidate
    -- sources (TRENDING / RECENT / INTEREST / DISCOVERY) so ORG_MEMBERS posts
    -- never enter the global-discovery buckets in the first place.
    SELECT lv.LookupValueId INTO v_PublicLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'POST_VISIBILITY' AND lv.ValueCode = 'PUBLIC'
    LIMIT  1;

    SELECT sf.* FROM (

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

            (SELECT COUNT(*) FROM PostLikes pl
             WHERE pl.PostId = p.PostId AND pl.UserId = p_UserId)  AS IsLiked,

            (SELECT COUNT(*) FROM PostSaves ps
             WHERE ps.PostId = p.PostId AND ps.UserId = p_UserId)  AS IsSaved,

            IFNULL((SELECT of2.IsFollowing FROM OrgFollowers of2
                    WHERE of2.OrgId = p.OrgId AND of2.UserId = p_UserId LIMIT 1), 0) AS IsFollowing,

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

            (
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

                + LEAST(20, (
                    SELECT COUNT(*) * 10
                    FROM UserSkills us
                    WHERE us.UserId = p_UserId AND us.IsDeleted = 0
                      AND LOWER(COALESCE(p.Content, '')) LIKE CONCAT('%', LOWER(us.SkillName), '%')
                ))

                + CASE
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 1   THEN 25
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 6   THEN 20
                    WHEN TIMESTAMPDIFF(HOUR, p.CreatedAt, NOW()) < 24  THEN 15
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 3   THEN 10
                    WHEN TIMESTAMPDIFF(DAY,  p.CreatedAt, NOW()) < 7   THEN 5
                    ELSE 2
                  END

                + LEAST(15, FLOOR(
                    (p.LikeCount * 0.5 + p.CommentCount * 1.0 + p.ShareCount * 2.0 + p.SaveCount * 1.5)
                    / 10.0
                  ))

                + CASE WHEN EXISTS(
                    SELECT 1 FROM Organisations o2
                    JOIN LookupValues lv_os ON o2.StatusLkpId = lv_os.LookupValueId
                    WHERE o2.OrgId = p.OrgId AND lv_os.ValueCode = 'APPROVED'
                ) THEN 10 ELSE 0 END

                + CASE WHEN LENGTH(COALESCE(p.Content, '')) > 100 THEN 5 ELSE 0 END
                + CASE WHEN EXISTS(
                    SELECT 1 FROM PostMedia pm2 WHERE pm2.PostId = p.PostId
                ) THEN 5 ELSE 0 END

                - LEAST(20, COALESCE(
                    (SELECT COUNT(*) * 5 FROM PostReports pr WHERE pr.PostId = p.PostId),
                    0
                  ))

                + CASE WHEN p.IsEmergency = 1 THEN 1000 ELSE 0 END

            ) AS FeedScore

        FROM Posts p

        JOIN (
            SELECT PostId, MIN(FeedSource) AS FeedSource
            FROM (
                -- MY_ORG: all posts from NGOs the user is an approved member of.
                -- No time limit — member posts are always highest priority.
                (SELECT p1.PostId, 'MY_ORG' AS FeedSource
                FROM Posts p1
                INNER JOIN OrgMembers om1
                       ON om1.OrgId = p1.OrgId AND om1.UserId = p_UserId AND om1.IsDeleted = 0
                INNER JOIN LookupValues lv1
                       ON lv1.LookupValueId = om1.StatusLkpId AND lv1.ValueCode = 'APPROVED'
                WHERE p1.IsDeleted = 0
                ORDER BY p1.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- FOLLOWED_ORG: posts from NGOs the user follows.
                -- No time limit — followed org posts should always surface.
                (SELECT p2.PostId, 'FOLLOWED_ORG' AS FeedSource
                FROM Posts p2
                INNER JOIN OrgFollowers of1
                       ON of1.OrgId = p2.OrgId AND of1.UserId = p_UserId AND of1.IsFollowing = 1
                WHERE p2.IsDeleted = 0
                ORDER BY p2.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- TRENDING: top public posts by engagement. Extended to 30 days.
                (SELECT p3.PostId, 'TRENDING' AS FeedSource
                FROM Posts p3
                WHERE p3.IsDeleted = 0
                  AND p3.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                  AND p3.VisibilityLkpId = v_PublicLkpId
                ORDER BY (p3.LikeCount * 1 + p3.CommentCount * 2 + p3.ShareCount * 3 + p3.SaveCount * 2) DESC
                LIMIT 100)

                UNION ALL

                -- EMERGENCY: always show active emergency posts regardless of seen status.
                -- The seen filter in the outer WHERE exempts IsEmergency=1 posts.
                (SELECT p4.PostId, 'EMERGENCY' AS FeedSource
                FROM Posts p4
                WHERE p4.IsDeleted = 0
                  AND p4.IsEmergency = 1
                  AND p4.CreatedAt >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
                ORDER BY p4.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- INTEREST: public posts matching user's interest tags. Extended to 45 days.
                (SELECT p5.PostId, 'INTEREST' AS FeedSource
                FROM Posts p5
                INNER JOIN LookupValues pt5 ON pt5.LookupValueId = p5.PostTypeLkpId
                WHERE p5.IsDeleted = 0
                  AND p5.CreatedAt >= DATE_SUB(NOW(), INTERVAL 45 DAY)
                  AND p5.VisibilityLkpId = v_PublicLkpId
                  AND EXISTS(
                      SELECT 1 FROM UserInterests ui5
                      JOIN LookupValues li5 ON ui5.InterestLkpId = li5.LookupValueId
                      WHERE ui5.UserId = p_UserId
                        AND (LOWER(li5.ValueName) LIKE CONCAT('%', LOWER(pt5.ValueName), '%')
                          OR LOWER(pt5.ValueName) LIKE CONCAT('%', LOWER(li5.ValueName), '%'))
                  )
                ORDER BY p5.CreatedAt DESC LIMIT 100)

                UNION ALL

                -- RECENT: latest public posts from anyone. Keeps feed fresh.
                (SELECT p6.PostId, 'RECENT' AS FeedSource
                FROM Posts p6
                WHERE p6.IsDeleted = 0
                  AND p6.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                  AND p6.VisibilityLkpId = v_PublicLkpId
                ORDER BY p6.CreatedAt DESC LIMIT 100)

                UNION ALL

                -- PINNED_EVERGREEN: pinned or evergreen posts from the user's own NGOs.
                -- No time limit — these are explicitly marked as always-relevant.
                (SELECT p7.PostId, 'PINNED_EVERGREEN' AS FeedSource
                FROM Posts p7
                INNER JOIN OrgMembers om7
                       ON om7.OrgId = p7.OrgId AND om7.UserId = p_UserId AND om7.IsDeleted = 0
                INNER JOIN LookupValues lv7
                       ON lv7.LookupValueId = om7.StatusLkpId AND lv7.ValueCode = 'APPROVED'
                WHERE p7.IsDeleted = 0
                  AND (p7.IsPinned = 1 OR p7.IsEvergreen = 1)
                ORDER BY p7.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- DISCOVERY: top public posts of all time by engagement score.
                -- Safety net — surfaces when all personalised buckets are exhausted.
                (SELECT p8.PostId, 'DISCOVERY' AS FeedSource
                FROM Posts p8
                WHERE p8.IsDeleted = 0
                  AND p8.VisibilityLkpId = v_PublicLkpId
                ORDER BY (p8.LikeCount * 1 + p8.CommentCount * 2 + p8.ShareCount * 3 + p8.SaveCount * 2) DESC
                LIMIT 100)

            ) all_sources
            GROUP BY PostId
        ) cands ON cands.PostId = p.PostId

        JOIN   UserProfiles up      ON up.UserId             = p.UserId AND up.IsDeleted = 0
        LEFT JOIN Organisations o   ON o.OrgId               = p.OrgId
        LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
        LEFT JOIN PostMedia pm      ON pm.PostId             = p.PostId
        LEFT JOIN LookupValues lv_mt ON lv_mt.LookupValueId  = pm.MediaTypeLkpId
        LEFT JOIN LookupValues lv_vis ON lv_vis.LookupValueId = p.VisibilityLkpId

        WHERE p.IsDeleted = 0
          -- Visibility enforcement: PUBLIC = everyone; ORG_MEMBERS = approved members only;
          -- FOLLOWERS = org followers only; NULL/unknown = treat as PUBLIC.
          AND (
              lv_vis.ValueCode IS NULL OR lv_vis.ValueCode = 'PUBLIC'
              OR (lv_vis.ValueCode = 'ORG_MEMBERS'
                  AND EXISTS (
                      SELECT 1 FROM OrgMembers om_v
                      JOIN LookupValues lv_s ON om_v.StatusLkpId = lv_s.LookupValueId
                      WHERE om_v.OrgId = p.OrgId AND om_v.UserId = p_UserId
                        AND om_v.IsDeleted = 0 AND lv_s.ValueCode = 'APPROVED'
                  ))
              OR (lv_vis.ValueCode = 'FOLLOWERS'
                  AND EXISTS (
                      SELECT 1 FROM OrgFollowers of_v
                      WHERE of_v.OrgId = p.OrgId AND of_v.UserId = p_UserId AND of_v.IsFollowing = 1
                  ))
          )

        GROUP BY
            p.PostId,      p.Content,    p.IsPinned,   p.IsEmergency, p.IsEvergreen,
            p.LikeCount,   p.CommentCount, p.ShareCount, p.SaveCount,
            lv_type.ValueCode, lv_type.ValueName,
            p.UserId,      up.FirstName, up.LastName,  up.ProfilePhoto,
            p.OrgId,       o.OrgName,   o.LogoUrl,    cands.FeedSource,
            lv_vis.ValueCode,
            p.CreatedAt

    ) sf

    -- Cursor: newest-first chronological pagination.
    -- Seen filter: exclude posts the user already viewed within the expiry window.
    -- Exception: IsEmergency=1 posts always bypass the seen filter.
    WHERE (
        p_CursorScore IS NULL
        OR UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore
        OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)
    )
    AND (
        sf.IsEmergency = 1   -- emergency posts always show regardless of seen status
        OR NOT EXISTS (
            SELECT 1 FROM FeedInteractions fi
            WHERE fi.PostId          = sf.PostId
              AND fi.UserId          = p_UserId
              AND fi.InteractionType = 'VIEW'
              AND fi.CreatedAt       >= DATE_SUB(NOW(), INTERVAL p_SeenExpiryDays DAY)
        )
    )

    ORDER BY sf.CreatedAt DESC, sf.PostId DESC
    LIMIT  v_FetchSize;

END //

-- ── Feed_BulkMarkViewed ────────────────────────────────────────────────────────
-- Bulk-inserts VIEW rows into FeedInteractions for all postIds in the JSON array.
-- Called by the mobile app when flushing its seen-post buffer (batch every ~10s).
-- Uses INSERT IGNORE so duplicate views (same user+post within a session) are safe.
-- Uses JSON_TABLE (MySQL 8.0+) to unpack the array server-side — one SP call for
-- up to ~50 postIds instead of N individual Feed_TrackInteraction calls.
DROP PROCEDURE IF EXISTS Feed_BulkMarkViewed //
CREATE PROCEDURE Feed_BulkMarkViewed(
    IN p_UserId  INT UNSIGNED,
    IN p_PostIds JSON          -- e.g. [1, 2, 3, 4, 5]
)
BEGIN
    INSERT IGNORE INTO FeedInteractions (UserId, PostId, InteractionType)
    SELECT p_UserId, jt.PostId, 'VIEW'
    FROM   JSON_TABLE(p_PostIds, '$[*]' COLUMNS (PostId INT PATH '$')) AS jt
    WHERE  EXISTS (
        SELECT 1 FROM Posts WHERE PostId = jt.PostId AND IsDeleted = 0
    );

    SELECT 1 AS IsSuccess, 'Marked.' AS Message;
END //

DELIMITER ;

-- ── Settings seed ─────────────────────────────────────────────────────────────
-- Skip if already exists (idempotent re-run safety).
INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES ('FEED', 'FEED_SEEN_EXPIRY_DAYS', '30', 'NUMBER',
        'Days to remember a post as seen by a user. After expiry the post becomes eligible to reappear in the feed as a last-resort fallback.',
        0);

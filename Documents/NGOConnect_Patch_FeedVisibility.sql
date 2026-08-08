-- ============================================================
-- NGO Connect — Patch: Feed_GetPersonalized visibility fix
-- Version : v5.0 patch
-- Date    : 2026-08-07
-- Apply to: Railway staging → Railway production
-- ============================================================
--
-- Problem
-- -------
-- Posts created with "Members Only" (ORG_MEMBERS) visibility were visible
-- in the Home feed of users who are NOT members of that NGO.
--
-- Root cause
-- ----------
-- Feed_GetPersonalized uses 6 candidate sources to build the feed.
-- Three of them (TRENDING, RECENT, INTEREST) select posts from ALL orgs
-- with no visibility filter — these are global-discovery buckets.
-- A Members-Only post would enter these buckets as a candidate and,
-- on the previous SP version deployed to Railway, there was no
-- outer-query visibility gate to remove it before returning results.
--
-- Fix (two layers)
-- ----------------
-- Layer 1 — Candidate-source filtering:
--   TRENDING, RECENT, INTEREST sources now only accept PUBLIC posts.
--   A single v_PublicLkpId lookup at SP start makes this a fast integer
--   comparison in every sub-SELECT (no extra JOIN per row).
--   MY_ORG and FOLLOWED_ORG are left unrestricted because the outer
--   visibility gate handles member/follower checks for those sources.
--
-- Layer 2 — Outer WHERE visibility gate (kept from previous patch):
--   Safety net for FOLLOWED_ORG posts with ORG_MEMBERS visibility, and
--   any future candidate source that might be added without visibility filtering.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Feed_GetPersonalized //
CREATE PROCEDURE Feed_GetPersonalized(
    IN p_UserId       INT UNSIGNED,
    IN p_CursorPostId INT UNSIGNED,
    IN p_CursorScore  DECIMAL(10,4),
    IN p_PageSize     INT
)
BEGIN
    DECLARE v_FetchSize   INT          DEFAULT p_PageSize * 3;
    DECLARE v_PublicLkpId INT UNSIGNED DEFAULT 0;

    -- Resolve the 'PUBLIC' visibility LkpId once — used to pre-filter candidate
    -- sources (TRENDING / RECENT / INTEREST) so ORG_MEMBERS posts never enter
    -- the global-discovery buckets in the first place.
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
                -- MY_ORG: all visibility levels — user is a member, outer WHERE enforces ORG_MEMBERS check
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

                -- FOLLOWED_ORG: all visibility levels — outer WHERE enforces FOLLOWERS/ORG_MEMBERS check
                (SELECT p2.PostId, 'FOLLOWED_ORG' AS FeedSource
                FROM Posts p2
                INNER JOIN OrgFollowers of1
                       ON of1.OrgId = p2.OrgId AND of1.UserId = p_UserId AND of1.IsFollowing = 1
                WHERE p2.IsDeleted = 0
                  AND p2.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                ORDER BY p2.CreatedAt DESC LIMIT 200)

                UNION ALL

                -- TRENDING: PUBLIC only — global bucket, must never surface restricted posts
                (SELECT p3.PostId, 'TRENDING' AS FeedSource
                FROM Posts p3
                WHERE p3.IsDeleted = 0
                  AND p3.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                  AND p3.VisibilityLkpId = v_PublicLkpId
                ORDER BY (p3.LikeCount * 1 + p3.CommentCount * 2 + p3.ShareCount * 3 + p3.SaveCount * 2) DESC
                LIMIT 100)

                UNION ALL

                -- EMERGENCY: all (emergency posts should always be PUBLIC; outer WHERE is safety net)
                (SELECT p4.PostId, 'EMERGENCY' AS FeedSource
                FROM Posts p4
                WHERE p4.IsDeleted = 0
                  AND p4.IsEmergency = 1
                  AND p4.CreatedAt >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
                ORDER BY p4.CreatedAt DESC LIMIT 50)

                UNION ALL

                -- INTEREST: PUBLIC only — global interest matching, must never surface restricted posts
                (SELECT p5.PostId, 'INTEREST' AS FeedSource
                FROM Posts p5
                INNER JOIN LookupValues pt5 ON pt5.LookupValueId = p5.PostTypeLkpId
                WHERE p5.IsDeleted = 0
                  AND p5.CreatedAt >= DATE_SUB(NOW(), INTERVAL 14 DAY)
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

                -- RECENT: PUBLIC only — global recent posts, must never surface restricted posts
                (SELECT p6.PostId, 'RECENT' AS FeedSource
                FROM Posts p6
                WHERE p6.IsDeleted = 0
                  AND p6.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                  AND p6.VisibilityLkpId = v_PublicLkpId
                ORDER BY p6.CreatedAt DESC LIMIT 100)

            ) all_sources
            GROUP BY PostId
        ) cands ON cands.PostId = p.PostId

        JOIN   UserProfiles up         ON up.UserId             = p.UserId AND up.IsDeleted = 0
        LEFT JOIN Organisations o      ON o.OrgId               = p.OrgId
        LEFT JOIN LookupValues lv_type ON lv_type.LookupValueId = p.PostTypeLkpId
        LEFT JOIN PostMedia pm          ON pm.PostId             = p.PostId
        LEFT JOIN LookupValues lv_mt   ON lv_mt.LookupValueId   = pm.MediaTypeLkpId
        LEFT JOIN LookupValues lv_vis  ON lv_vis.LookupValueId  = p.VisibilityLkpId

        WHERE p.IsDeleted = 0
          -- Layer 2: outer visibility gate — handles MY_ORG (ORG_MEMBERS check for members),
          -- FOLLOWED_ORG (FOLLOWERS check for followers), and any future sources.
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

    WHERE  p_CursorScore IS NULL
        OR UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore
        OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)

    ORDER BY sf.CreatedAt DESC, sf.PostId DESC
    LIMIT  v_FetchSize;

END //

DELIMITER ;

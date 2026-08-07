-- ============================================================
-- NGO Connect — Patch: Visibility & Audience Enforcement
-- ============================================================
-- Purpose : Enforce post visibility and community audience rules
--           that were previously not checked in the SPs.
--
--   Post_GetFeed        — ORG_MEMBERS and FOLLOWERS posts now filtered
--   Feed_GetPersonalized — same visibility filter on personalized feed
--   Community_GetFeed   — ADMINS_ONLY posts restricted to FOUNDER/ADMIN roles
--   Community_CreatePost — returns AudienceCode so the DAL can scope notifications
--
-- Apply order: run all 4 DROP/CREATE blocks against staging and production.
-- No table schema changes — SP-only patch.
-- ============================================================

DELIMITER //

-- ── 1. Post_GetFeed ───────────────────────────────────────────────────────────
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
         WHERE PostId = p.PostId AND UserId = p_UserId) AS IsLiked,
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
    JOIN   UserProfiles up          ON up.UserId             = p.UserId  AND up.IsDeleted = 0
    LEFT JOIN Organisations o       ON o.OrgId               = p.OrgId
    LEFT JOIN LookupValues lv_type  ON lv_type.LookupValueId = p.PostTypeLkpId
    LEFT JOIN PostMedia pm           ON pm.PostId             = p.PostId
    LEFT JOIN LookupValues lv_mt    ON lv_mt.LookupValueId   = pm.MediaTypeLkpId
    LEFT JOIN LookupValues lv_vis   ON lv_vis.LookupValueId  = p.VisibilityLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
      -- Visibility enforcement
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
        p.PostId,    p.Content,    p.IsPinned,
        lv_type.ValueCode, lv_type.ValueName,
        p.LikeCount, p.CommentCount,
        p.UserId,    up.FirstName, up.LastName, up.ProfilePhoto,
        p.OrgId,     o.OrgName,   lv_vis.ValueCode, p.CreatedAt
    ORDER BY p.IsPinned DESC, p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   Posts p
    LEFT JOIN LookupValues lv_vis ON lv_vis.LookupValueId = p.VisibilityLkpId
    WHERE  p.IsDeleted = 0
      AND  (p_OrgId IS NULL OR p.OrgId = p_OrgId)
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
      );
END //


-- ── 2. Feed_GetPersonalized ───────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Feed_GetPersonalized //
CREATE PROCEDURE Feed_GetPersonalized(
    IN p_UserId       INT UNSIGNED,
    IN p_CursorPostId INT UNSIGNED,
    IN p_CursorScore  DECIMAL(10,4),
    IN p_PageSize     INT
)
BEGIN
    DECLARE v_FetchSize INT DEFAULT p_PageSize * 3;

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

                (SELECT p2.PostId, 'FOLLOWED_ORG' AS FeedSource
                FROM Posts p2
                INNER JOIN OrgFollowers of1
                       ON of1.OrgId = p2.OrgId AND of1.UserId = p_UserId AND of1.IsFollowing = 1
                WHERE p2.IsDeleted = 0
                  AND p2.CreatedAt >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                ORDER BY p2.CreatedAt DESC LIMIT 200)

                UNION ALL

                (SELECT p3.PostId, 'TRENDING' AS FeedSource
                FROM Posts p3
                WHERE p3.IsDeleted = 0
                  AND p3.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                ORDER BY (p3.LikeCount * 1 + p3.CommentCount * 2 + p3.ShareCount * 3 + p3.SaveCount * 2) DESC
                LIMIT 100)

                UNION ALL

                (SELECT p4.PostId, 'EMERGENCY' AS FeedSource
                FROM Posts p4
                WHERE p4.IsDeleted = 0
                  AND p4.IsEmergency = 1
                  AND p4.CreatedAt >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
                ORDER BY p4.CreatedAt DESC LIMIT 50)

                UNION ALL

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

                (SELECT p6.PostId, 'RECENT' AS FeedSource
                FROM Posts p6
                WHERE p6.IsDeleted = 0
                  AND p6.CreatedAt >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                ORDER BY p6.CreatedAt DESC LIMIT 100)

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

    -- p_CursorScore carries UNIX_TIMESTAMP(CreatedAt) of the last seen post.
    WHERE  p_CursorScore IS NULL
        OR UNIX_TIMESTAMP(sf.CreatedAt) < p_CursorScore
        OR (UNIX_TIMESTAMP(sf.CreatedAt) = p_CursorScore AND sf.PostId < p_CursorPostId)

    ORDER BY sf.CreatedAt DESC, sf.PostId DESC
    LIMIT  v_FetchSize;

END //


-- ── 3. Community_GetFeed ──────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS Community_GetFeed //
CREATE PROCEDURE Community_GetFeed(
    IN p_OrgId      INT UNSIGNED,
    IN p_UserId     INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset INT;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;

    SELECT
        cp.CommunityPostId,
        cp.Title,
        cp.Content,
        ptv.ValueCode  AS PostType,
        ptv.ValueCode  AS PostTypeLkpCode,
        ptv.ValueName  AS PostTypeName,
        av.ValueCode   AS AudienceCode,
        cp.IsPinned,
        cp.AcknowledgeCount,
        cp.LikeCount,
        cp.CommentCount,
        cp.AssignedToUserId,
        CONCAT(aup.FirstName, ' ', aup.LastName) AS AssignedToName,
        cp.DueDate,
        tsv.ValueCode  AS TaskStatus,
        cp.PollEndsAt,
        cp.PollIsMultiChoice,
        cp.VolunteersNeeded,
        cp.ResourceFileUrl,
        cp.EventRef,
        cp.CreatedAt,
        cp.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS AuthorName,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledged,
        IF(cpa.CommunityPostId IS NOT NULL, 1, 0) AS IsAcknowledgedByMe,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLiked,
        IF(cpl.CommunityPostLikeId IS NOT NULL, 1, 0) AS IsLikedByMe,
        rv.ValueName AS RoleName,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()) < 60
                THEN CONCAT(TIMESTAMPDIFF(MINUTE, cp.CreatedAt, NOW()), 'm ago')
            WHEN TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()) < 24
                THEN CONCAT(TIMESTAMPDIFF(HOUR,   cp.CreatedAt, NOW()), 'h ago')
            WHEN TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()) < 7
                THEN CONCAT(TIMESTAMPDIFF(DAY,    cp.CreatedAt, NOW()), 'd ago')
            ELSE DATE_FORMAT(cp.CreatedAt, '%d %b')
        END AS TimeAgo,
        (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'pollOptionId', po.PollOptionId,
                    'optionText',   po.OptionText,
                    'voteCount',    po.VoteCount,
                    'isVoted',      IF(pv.PollVoteId IS NOT NULL, 1, 0)
                )
            )
            FROM   PollOptions po
            LEFT   JOIN PollVotes pv
                       ON po.PollOptionId = pv.PollOptionId
                      AND pv.UserId       = p_UserId
            WHERE  po.CommunityPostId = cp.CommunityPostId
        ) AS PollOptionsJson

    FROM   CommunityPosts cp
    JOIN   UserProfiles up   ON cp.UserId           = up.UserId  AND up.IsDeleted  = 0
    LEFT   JOIN UserProfiles aup
                             ON cp.AssignedToUserId = aup.UserId AND aup.IsDeleted = 0
    LEFT   JOIN LookupValues ptv ON cp.PostTypeLkpId   = ptv.LookupValueId
    LEFT   JOIN LookupValues av  ON cp.AudienceLkpId   = av.LookupValueId
    LEFT   JOIN LookupValues tsv ON cp.TaskStatusLkpId = tsv.LookupValueId
    LEFT   JOIN CommunityPostAcknowledgements cpa
                             ON cp.CommunityPostId = cpa.CommunityPostId
                            AND cpa.UserId         = p_UserId
    LEFT   JOIN CommunityPostLikes cpl
                             ON cp.CommunityPostId = cpl.CommunityPostId
                            AND cpl.UserId         = p_UserId
    LEFT   JOIN OrgMembers om ON om.OrgId    = cp.OrgId
                             AND om.UserId   = cp.UserId
                             AND om.IsDeleted = 0
    LEFT   JOIN LookupValues rv ON om.RoleLkpId = rv.LookupValueId

    WHERE  cp.OrgId    = p_OrgId
      AND  cp.IsDeleted = 0
      -- Audience enforcement: ALL_MEMBERS/VOLUNTEERS = any approved member;
      -- ADMINS_ONLY = FOUNDER or ADMIN role only; NULL/unknown = treat as ALL_MEMBERS.
      AND (
          av.ValueCode IS NULL OR av.ValueCode IN ('ALL_MEMBERS', 'VOLUNTEERS')
          OR (av.ValueCode = 'ADMINS_ONLY'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_a
                  JOIN LookupValues lv_ms ON om_a.StatusLkpId = lv_ms.LookupValueId
                  JOIN LookupValues lv_mr ON om_a.RoleLkpId   = lv_mr.LookupValueId
                  WHERE om_a.OrgId     = cp.OrgId
                    AND om_a.UserId    = p_UserId
                    AND om_a.IsDeleted = 0
                    AND lv_ms.ValueCode = 'APPROVED'
                    AND lv_mr.ValueCode IN ('FOUNDER', 'ADMIN')
              ))
      )
    ORDER  BY cp.IsPinned DESC, cp.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM   CommunityPosts cp2
    LEFT   JOIN LookupValues av2 ON av2.LookupValueId = cp2.AudienceLkpId
    WHERE  cp2.OrgId     = p_OrgId
      AND  cp2.IsDeleted = 0
      AND (
          av2.ValueCode IS NULL OR av2.ValueCode IN ('ALL_MEMBERS', 'VOLUNTEERS')
          OR (av2.ValueCode = 'ADMINS_ONLY'
              AND EXISTS (
                  SELECT 1 FROM OrgMembers om_a
                  JOIN LookupValues lv_ms ON om_a.StatusLkpId = lv_ms.LookupValueId
                  JOIN LookupValues lv_mr ON om_a.RoleLkpId   = lv_mr.LookupValueId
                  WHERE om_a.OrgId     = cp2.OrgId
                    AND om_a.UserId    = p_UserId
                    AND om_a.IsDeleted = 0
                    AND lv_ms.ValueCode = 'APPROVED'
                    AND lv_mr.ValueCode IN ('FOUNDER', 'ADMIN')
              ))
      );
END //


-- ── 4. Community_CreatePost ───────────────────────────────────────────────────
-- Returns AudienceCode alongside CommunityPostId so the DAL can scope
-- notification fan-out to admins-only when audience = ADMINS_ONLY.
DROP PROCEDURE IF EXISTS Community_CreatePost //
CREATE PROCEDURE Community_CreatePost(
    IN p_UserId           INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_Title            VARCHAR(300),
    IN p_Content          TEXT,
    IN p_PostTypeLkpId    INT UNSIGNED,
    IN p_AudienceLkpId    INT UNSIGNED,
    IN p_ResourceFileUrl  VARCHAR(500),
    IN p_IsPinned         TINYINT(1),
    IN p_VolunteersNeeded INT UNSIGNED,
    IN p_EventRef         VARCHAR(200)
)
BEGIN
    DECLARE v_ApprovedLkpId        INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost     TINYINT(1)  DEFAULT 0;
    DECLARE v_DefaultAudienceLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_ApprovedLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'APPROVED' LIMIT 1;

    SELECT om.CanCommunityPost INTO v_CanCommunityPost
    FROM   OrgMembers om
    WHERE  om.OrgId = p_OrgId AND om.UserId = p_UserId
      AND  om.StatusLkpId = v_ApprovedLkpId AND om.IsDeleted = 0
    LIMIT 1;

    IF v_CanCommunityPost = 0 THEN
        SELECT 0    AS IsSuccess,
               'You do not have permission to post in this community.' AS Message,
               NULL AS CommunityPostId,
               NULL AS AudienceCode;
    ELSE
        IF p_AudienceLkpId IS NULL OR p_AudienceLkpId = 0 THEN
            SELECT lv.LookupValueId INTO v_DefaultAudienceLkpId
            FROM   LookupValues lv
            JOIN   LookupTypes  lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS'
            LIMIT  1;
            SET p_AudienceLkpId = COALESCE(v_DefaultAudienceLkpId, 1);
        END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, Content, AudienceLkpId,
             IsPinned, VolunteersNeeded, EventRef, ResourceFileUrl, CreatedBy)
        VALUES
            (p_OrgId, p_UserId, p_PostTypeLkpId, p_Title, p_Content, p_AudienceLkpId,
             COALESCE(p_IsPinned, 0), p_VolunteersNeeded, p_EventRef, p_ResourceFileUrl, p_UserId);

        SELECT 1                    AS IsSuccess,
               'Post created.'      AS Message,
               LAST_INSERT_ID()     AS CommunityPostId,
               (SELECT lv.ValueCode FROM LookupValues lv
                WHERE lv.LookupValueId = p_AudienceLkpId LIMIT 1) AS AudienceCode;
    END IF;
END //

DELIMITER ;

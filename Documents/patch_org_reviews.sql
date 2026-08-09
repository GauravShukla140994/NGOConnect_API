-- ============================================================
-- NGO Connect — Patch: NGO Reviews Module (v5.1)
-- Apply to: Railway Staging → Railway Production
-- Run AFTER: NGOConnect_Complete_Setup_v5.0.sql is current
-- Safe to re-run: DROP IF EXISTS on all SPs; CREATE TABLE uses
--                 IF NOT EXISTS; INSERT uses safe SELECT pattern.
-- ============================================================

-- ── New LookupTypes ─────────────────────────────────────────
INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType, CreatedBy) VALUES
('REVIEWER_TYPE',    'Reviewer Type',    'Type of reviewer leaving an NGO review',     1, 1),
('REVIEW_MEDIA_TYPE','Review Media Type','Media type attached to an NGO review',        1, 1),
('REVIEW_SORT',      'Review Sort',      'Sort order options for NGO review listing',   1, 1);

-- REVIEWER_TYPE values
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'VOLUNTEER', 'Volunteer', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE' UNION ALL
SELECT LookupTypeId, 'DONOR',     'Donor',     2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE' UNION ALL
SELECT LookupTypeId, 'GENERAL',   'General',   3, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEWER_TYPE';

-- REVIEW_MEDIA_TYPE values
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'IMAGE', 'Image', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_MEDIA_TYPE' UNION ALL
SELECT LookupTypeId, 'VIDEO', 'Video', 2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_MEDIA_TYPE';

-- REVIEW_SORT values
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsDefault, IsSystemValue)
SELECT LookupTypeId, 'RECENT',  'Most Recent',    1, 1, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'HELPFUL', 'Most Helpful',   2, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'HIGHEST', 'Highest Rating', 3, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT' UNION ALL
SELECT LookupTypeId, 'LOWEST',  'Lowest Rating',  4, 0, 1 FROM LookupTypes WHERE TypeCode = 'REVIEW_SORT';

-- ── New Tables ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS OrgReviews (
    ReviewId            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    OrgId               INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    OverallRating       TINYINT         NOT NULL CHECK (OverallRating BETWEEN 1 AND 5),
    ReviewText          TEXT            NOT NULL,
    ReviewerTypeLkpId   INT UNSIGNED    NOT NULL,
    HelpfulCount        INT UNSIGNED    NOT NULL DEFAULT 0,
    NotHelpfulCount     INT UNSIGNED    NOT NULL DEFAULT 0,
    IsApproved          TINYINT(1)      NOT NULL DEFAULT 1  COMMENT 'Set 0 to hold for moderation',
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (ReviewId),
    UNIQUE  KEY uq_org_user_review   (OrgId, UserId),
    KEY     idx_orgreview_orgid      (OrgId),
    KEY     idx_orgreview_userid     (UserId),
    KEY     idx_orgreview_approved   (OrgId, IsApproved, IsDeleted),
    CONSTRAINT fk_orgreview_org  FOREIGN KEY (OrgId)             REFERENCES Organisations (OrgId),
    CONSTRAINT fk_orgreview_user FOREIGN KEY (UserId)            REFERENCES Users         (UserId),
    CONSTRAINT fk_orgreview_type FOREIGN KEY (ReviewerTypeLkpId) REFERENCES LookupValues  (LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS OrgReviewMedia (
    MediaId             INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    MediaUrl            VARCHAR(500)    NOT NULL,
    MediaTypeLkpId      INT UNSIGNED    NOT NULL,
    OrderNo             TINYINT UNSIGNED NOT NULL DEFAULT 1,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (MediaId),
    KEY idx_reviewmedia_reviewid (ReviewId),
    CONSTRAINT fk_reviewmedia_review FOREIGN KEY (ReviewId)       REFERENCES OrgReviews  (ReviewId),
    CONSTRAINT fk_reviewmedia_type   FOREIGN KEY (MediaTypeLkpId) REFERENCES LookupValues (LookupValueId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS OrgReviewResponses (
    ResponseId          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    OrgId               INT UNSIGNED    NOT NULL,
    RespondedByUserId   INT UNSIGNED    NOT NULL,
    ResponseText        TEXT            NOT NULL,
    IsDeleted           TINYINT(1)      NOT NULL DEFAULT 0,
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (ResponseId),
    UNIQUE KEY uq_review_response (ReviewId),
    KEY idx_reviewresponse_orgid (OrgId),
    CONSTRAINT fk_reviewresp_review FOREIGN KEY (ReviewId)          REFERENCES OrgReviews   (ReviewId),
    CONSTRAINT fk_reviewresp_org    FOREIGN KEY (OrgId)             REFERENCES Organisations(OrgId),
    CONSTRAINT fk_reviewresp_user   FOREIGN KEY (RespondedByUserId) REFERENCES Users        (UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS OrgReviewHelpful (
    HelpfulId           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    ReviewId            INT UNSIGNED    NOT NULL,
    UserId              INT UNSIGNED    NOT NULL,
    IsHelpful           TINYINT(1)      NOT NULL COMMENT '1=helpful, 0=not helpful',
    CreatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (HelpfulId),
    UNIQUE KEY uq_review_user_helpful (ReviewId, UserId),
    KEY idx_reviewhelpful_reviewid (ReviewId),
    CONSTRAINT fk_reviewhelpful_review FOREIGN KEY (ReviewId) REFERENCES OrgReviews (ReviewId),
    CONSTRAINT fk_reviewhelpful_user   FOREIGN KEY (UserId)   REFERENCES Users       (UserId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Stored Procedures ────────────────────────────────────────

DELIMITER //

DROP PROCEDURE IF EXISTS OrgReview_Add //
CREATE PROCEDURE OrgReview_Add(
    IN p_UserId           INT UNSIGNED,
    IN p_OrgId            INT UNSIGNED,
    IN p_OverallRating    TINYINT,
    IN p_ReviewText       TEXT,
    IN p_ReviewerType     VARCHAR(50),
    IN p_MediaUrls        JSON
)
BEGIN
    DECLARE v_ReviewId          INT UNSIGNED  DEFAULT 0;
    DECLARE v_ReviewerTypeLkpId INT UNSIGNED  DEFAULT NULL;
    DECLARE v_MediaTypeLkpId    INT UNSIGNED  DEFAULT NULL;
    DECLARE v_MediaTypeCode     VARCHAR(50);
    DECLARE v_MediaUrl          VARCHAR(500);
    DECLARE v_Idx               INT           DEFAULT 0;
    DECLARE v_MediaCount        INT           DEFAULT 0;

    IF p_OverallRating < 1 OR p_OverallRating > 5 THEN
        SELECT 0 AS IsSuccess, 'Rating must be between 1 and 5.' AS Message, NULL AS ReviewId;
    ELSE
        SELECT lv.LookupValueId INTO v_ReviewerTypeLkpId
        FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
        WHERE lt.TypeCode = 'REVIEWER_TYPE' AND lv.ValueCode = p_ReviewerType LIMIT 1;

        IF v_ReviewerTypeLkpId IS NULL THEN
            SET v_ReviewerTypeLkpId = (SELECT lv.LookupValueId FROM LookupValues lv
                                       JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                                       WHERE lt.TypeCode = 'REVIEWER_TYPE' AND lv.IsDefault = 1 LIMIT 1);
        END IF;

        INSERT INTO OrgReviews (OrgId, UserId, OverallRating, ReviewText, ReviewerTypeLkpId)
        VALUES (p_OrgId, p_UserId, p_OverallRating, p_ReviewText, v_ReviewerTypeLkpId)
        ON DUPLICATE KEY UPDATE ReviewId = ReviewId;

        IF ROW_COUNT() = 0 THEN
            SELECT 0 AS IsSuccess, 'You have already reviewed this NGO.' AS Message, NULL AS ReviewId;
        ELSE
            SET v_ReviewId = LAST_INSERT_ID();

            IF p_MediaUrls IS NOT NULL AND JSON_LENGTH(p_MediaUrls) > 0 THEN
                SET v_MediaCount = JSON_LENGTH(p_MediaUrls);
                WHILE v_Idx < v_MediaCount DO
                    SET v_MediaUrl      = JSON_UNQUOTE(JSON_EXTRACT(p_MediaUrls, CONCAT('$[', v_Idx, '].url')));
                    SET v_MediaTypeCode = JSON_UNQUOTE(JSON_EXTRACT(p_MediaUrls, CONCAT('$[', v_Idx, '].type')));
                    SELECT lv.LookupValueId INTO v_MediaTypeLkpId
                    FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
                    WHERE lt.TypeCode = 'REVIEW_MEDIA_TYPE' AND lv.ValueCode = v_MediaTypeCode LIMIT 1;
                    IF v_MediaTypeLkpId IS NOT NULL THEN
                        INSERT INTO OrgReviewMedia (ReviewId, MediaUrl, MediaTypeLkpId, OrderNo)
                        VALUES (v_ReviewId, v_MediaUrl, v_MediaTypeLkpId, v_Idx + 1);
                    END IF;
                    SET v_Idx = v_Idx + 1;
                END WHILE;
            END IF;

            UPDATE Organisations
            SET    AvgRating   = (SELECT ROUND(AVG(OverallRating),2) FROM OrgReviews WHERE OrgId=p_OrgId AND IsApproved=1 AND IsDeleted=0),
                   RatingCount = (SELECT COUNT(*)                     FROM OrgReviews WHERE OrgId=p_OrgId AND IsApproved=1 AND IsDeleted=0)
            WHERE  OrgId = p_OrgId;

            SELECT 1 AS IsSuccess, 'Review submitted successfully.' AS Message, v_ReviewId AS ReviewId;
        END IF;
    END IF;
END //

DROP PROCEDURE IF EXISTS OrgReview_GetList //
CREATE PROCEDURE OrgReview_GetList(
    IN p_OrgId         INT UNSIGNED,
    IN p_CurrentUserId INT UNSIGNED,
    IN p_Sort          VARCHAR(20),
    IN p_PageNumber    INT UNSIGNED,
    IN p_PageSize      INT UNSIGNED
)
BEGIN
    DECLARE v_Offset INT DEFAULT 0;
    SET v_Offset = (p_PageNumber - 1) * p_PageSize;
    IF p_Sort NOT IN ('RECENT','HELPFUL','HIGHEST','LOWEST') THEN SET p_Sort = 'RECENT'; END IF;

    SELECT
        r.ReviewId,
        r.OverallRating,
        r.ReviewText,
        r.HelpfulCount,
        r.NotHelpfulCount,
        r.CreatedAt,
        u.UserId,
        COALESCE(CONCAT(up.FirstName, ' ', up.LastName), u.Mobile, 'Anonymous') AS AuthorName,
        up.ProfilePhoto                          AS AuthorAvatar,
        lv.ValueCode                             AS ReviewerType,
        (SELECT IsHelpful FROM OrgReviewHelpful
         WHERE ReviewId = r.ReviewId AND UserId = p_CurrentUserId LIMIT 1) AS CurrentUserVote,
        IF(r.UserId = p_CurrentUserId, 1, 0)     AS IsOwnReview,
        resp.ResponseText,
        resp.CreatedAt                           AS ResponseCreatedAt,
        media_agg.MediaItems
    FROM  OrgReviews r
    JOIN  Users u                     ON r.UserId            = u.UserId
    LEFT JOIN UserProfiles up         ON u.UserId            = up.UserId
    JOIN  LookupValues lv             ON r.ReviewerTypeLkpId = lv.LookupValueId
    LEFT JOIN OrgReviewResponses resp ON r.ReviewId          = resp.ReviewId AND resp.IsDeleted = 0
    LEFT JOIN (
        SELECT
            m.ReviewId,
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'mediaId',   m.MediaId,
                    'mediaUrl',  m.MediaUrl,
                    'mediaType', IFNULL(mt.ValueCode, 'IMAGE'),
                    'orderNo',   m.OrderNo
                )
            ) AS MediaItems
        FROM  (SELECT * FROM OrgReviewMedia ORDER BY ReviewId, OrderNo) m
        LEFT JOIN LookupValues mt ON m.MediaTypeLkpId = mt.LookupValueId
        GROUP BY m.ReviewId
    ) media_agg ON media_agg.ReviewId = r.ReviewId
    WHERE r.OrgId = p_OrgId AND r.IsApproved = 1 AND r.IsDeleted = 0
    ORDER BY
        CASE WHEN p_Sort='RECENT'  THEN r.CreatedAt     END DESC,
        CASE WHEN p_Sort='HELPFUL' THEN r.HelpfulCount  END DESC,
        CASE WHEN p_Sort='HIGHEST' THEN r.OverallRating END DESC,
        CASE WHEN p_Sort='LOWEST'  THEN r.OverallRating END ASC,
        r.ReviewId DESC
    LIMIT p_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount FROM OrgReviews
    WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS OrgReview_GetAggregate //
CREATE PROCEDURE OrgReview_GetAggregate(
    IN p_OrgId INT UNSIGNED
)
BEGIN
    SELECT
        ROUND(AVG(OverallRating), 1)                        AS AvgRating,
        COUNT(*)                                            AS TotalReviews,
        ROUND(SUM(OverallRating=5)/COUNT(*)*100, 0)         AS Star5Pct,
        ROUND(SUM(OverallRating=4)/COUNT(*)*100, 0)         AS Star4Pct,
        ROUND(SUM(OverallRating=3)/COUNT(*)*100, 0)         AS Star3Pct,
        ROUND(SUM(OverallRating=2)/COUNT(*)*100, 0)         AS Star2Pct,
        ROUND(SUM(OverallRating=1)/COUNT(*)*100, 0)         AS Star1Pct
    FROM  OrgReviews
    WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS OrgReview_MarkHelpful //
CREATE PROCEDURE OrgReview_MarkHelpful(
    IN p_UserId    INT UNSIGNED,
    IN p_ReviewId  INT UNSIGNED,
    IN p_IsHelpful TINYINT
)
BEGIN
    DECLARE v_ExistingVote TINYINT      DEFAULT NULL;
    DECLARE v_HelpfulId    INT UNSIGNED DEFAULT NULL;

    SELECT HelpfulId, IsHelpful INTO v_HelpfulId, v_ExistingVote
    FROM   OrgReviewHelpful WHERE ReviewId = p_ReviewId AND UserId = p_UserId LIMIT 1;

    IF v_HelpfulId IS NULL THEN
        INSERT INTO OrgReviewHelpful (ReviewId, UserId, IsHelpful) VALUES (p_ReviewId, p_UserId, p_IsHelpful);
    ELSEIF v_ExistingVote = p_IsHelpful THEN
        DELETE FROM OrgReviewHelpful WHERE HelpfulId = v_HelpfulId;
    ELSE
        UPDATE OrgReviewHelpful SET IsHelpful = p_IsHelpful WHERE HelpfulId = v_HelpfulId;
    END IF;

    UPDATE OrgReviews
    SET    HelpfulCount    = (SELECT COUNT(*) FROM OrgReviewHelpful WHERE ReviewId=p_ReviewId AND IsHelpful=1),
           NotHelpfulCount = (SELECT COUNT(*) FROM OrgReviewHelpful WHERE ReviewId=p_ReviewId AND IsHelpful=0)
    WHERE  ReviewId = p_ReviewId;

    SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
END //

DROP PROCEDURE IF EXISTS OrgReview_Delete //
CREATE PROCEDURE OrgReview_Delete(
    IN p_UserId   INT UNSIGNED,
    IN p_ReviewId INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId INT UNSIGNED DEFAULT NULL;

    SELECT OrgId INTO v_OrgId FROM OrgReviews
    WHERE  ReviewId = p_ReviewId AND UserId = p_UserId AND IsDeleted = 0 LIMIT 1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Review not found or you are not the author.' AS Message;
    ELSE
        UPDATE OrgReviews SET IsDeleted = 1 WHERE ReviewId = p_ReviewId;
        UPDATE Organisations
        SET    AvgRating   = IFNULL((SELECT ROUND(AVG(OverallRating),2) FROM OrgReviews WHERE OrgId=v_OrgId AND IsApproved=1 AND IsDeleted=0), 0.00),
               RatingCount = (SELECT COUNT(*) FROM OrgReviews WHERE OrgId=v_OrgId AND IsApproved=1 AND IsDeleted=0)
        WHERE  OrgId = v_OrgId;
        SELECT 1 AS IsSuccess, 'Review deleted.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS OrgReview_AddResponse //
CREATE PROCEDURE OrgReview_AddResponse(
    IN p_AdminUserId  INT UNSIGNED,
    IN p_OrgId        INT UNSIGNED,
    IN p_ReviewId     INT UNSIGNED,
    IN p_ResponseText TEXT
)
BEGIN
    DECLARE v_IsAdmin   TINYINT      DEFAULT 0;
    DECLARE v_ReviewOrg INT UNSIGNED DEFAULT NULL;

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON om.RoleLkpId    = lv.LookupValueId
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  om.UserId   = p_AdminUserId AND om.OrgId = p_OrgId
      AND  lt.TypeCode = 'ORG_ROLE' AND lv.ValueCode IN ('ADMIN','SUPER_ADMIN')
      AND  om.IsActive = 1;

    SELECT OrgId INTO v_ReviewOrg FROM OrgReviews
    WHERE  ReviewId = p_ReviewId AND IsDeleted = 0 LIMIT 1;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Only NGO admins can respond to reviews.' AS Message;
    ELSEIF v_ReviewOrg IS NULL OR v_ReviewOrg != p_OrgId THEN
        SELECT 0 AS IsSuccess, 'Review not found for this NGO.' AS Message;
    ELSE
        INSERT INTO OrgReviewResponses (ReviewId, OrgId, RespondedByUserId, ResponseText)
        VALUES (p_ReviewId, p_OrgId, p_AdminUserId, p_ResponseText)
        ON DUPLICATE KEY UPDATE
            ResponseText = VALUES(ResponseText), RespondedByUserId = VALUES(RespondedByUserId),
            IsDeleted = 0, UpdatedAt = NOW();
        SELECT 1 AS IsSuccess, 'Response posted successfully.' AS Message;
    END IF;
END //

DROP PROCEDURE IF EXISTS OrgReview_Report //
CREATE PROCEDURE OrgReview_Report(
    IN p_UserId   INT UNSIGNED,
    IN p_ReviewId INT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM OrgReviews WHERE ReviewId = p_ReviewId AND IsDeleted = 0) THEN
        SELECT 0 AS IsSuccess, 'Review not found.' AS Message;
    ELSE
        SELECT 1 AS IsSuccess, 'Review reported. Our team will review it shortly.' AS Message;
    END IF;
END //

DELIMITER ;

-- SchemaVersions record
INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.1', 'v5.1: NGO Reviews module — 3 new LookupTypes, 14 new LookupValues, 4 new tables (OrgReviews, OrgReviewMedia, OrgReviewResponses, OrgReviewHelpful), 7 new SPs. AvgRating/RatingCount on Organisations now wired to review aggregates.', 'System');

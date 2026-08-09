-- ============================================================
-- patch_review_notifications.sql
-- v5.2: Review Notification support
--
-- Changes:
--   1. NOTIFICATION_TYPE lookup — 3 new values:
--        REVIEW_NEW, REVIEW_RESPONSE, REVIEW_DELETED
--   2. OrgReview_Add      — returns AuthorName, OrgName, ReviewerUserId
--   3. OrgReview_Delete   — returns ReviewerUserId, AuthorName,
--                           OverallRating, OrgName, OrgId
--   4. OrgReview_AddResponse — returns ReviewerUserId, OrgName
--
-- Apply to: local DB first, then Railway staging.
-- ============================================================

-- ── 1. New NOTIFICATION_TYPE lookup values ───────────────────
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, 'REVIEW_NEW',      'New Review',     9,  1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2
                  WHERE lv2.LookupTypeId = lt.LookupTypeId AND lv2.ValueCode = 'REVIEW_NEW');

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, 'REVIEW_RESPONSE', 'Review Response', 10, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2
                  WHERE lv2.LookupTypeId = lt.LookupTypeId AND lv2.ValueCode = 'REVIEW_RESPONSE');

INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT lt.LookupTypeId, 'REVIEW_DELETED',  'Review Deleted',  11, 1, 1
FROM   LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2
                  WHERE lv2.LookupTypeId = lt.LookupTypeId AND lv2.ValueCode = 'REVIEW_DELETED');

-- ── 2. OrgReview_Add — return notification fields ────────────
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
    DECLARE v_ReviewId          INT UNSIGNED DEFAULT 0;
    DECLARE v_ReviewerTypeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_MediaTypeLkpId    INT UNSIGNED DEFAULT NULL;
    DECLARE v_MediaTypeCode     VARCHAR(50);
    DECLARE v_MediaUrl          VARCHAR(500);
    DECLARE v_Idx               INT DEFAULT 0;
    DECLARE v_MediaCount        INT DEFAULT 0;
    DECLARE v_AuthorName        VARCHAR(200) DEFAULT '';
    DECLARE v_OrgName           VARCHAR(200) DEFAULT '';

    IF p_OverallRating < 1 OR p_OverallRating > 5 THEN
        SELECT 0 AS IsSuccess, 'Rating must be between 1 and 5.' AS Message, NULL AS ReviewId,
               NULL AS ReviewerUserId, NULL AS AuthorName, NULL AS OrgName;
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
            SELECT 0 AS IsSuccess, 'You have already reviewed this NGO.' AS Message, NULL AS ReviewId,
                   NULL AS ReviewerUserId, NULL AS AuthorName, NULL AS OrgName;
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
            SET    AvgRating   = (SELECT ROUND(AVG(OverallRating), 2) FROM OrgReviews WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0),
                   RatingCount = (SELECT COUNT(*)                      FROM OrgReviews WHERE OrgId = p_OrgId AND IsApproved = 1 AND IsDeleted = 0)
            WHERE  OrgId = p_OrgId;

            SELECT TRIM(CONCAT(IFNULL(up.FirstName,''), ' ', IFNULL(up.LastName,'')))
            INTO   v_AuthorName
            FROM   UserProfiles up WHERE up.UserId = p_UserId LIMIT 1;

            SELECT o.OrgName INTO v_OrgName FROM Organisations o WHERE o.OrgId = p_OrgId LIMIT 1;

            SELECT 1 AS IsSuccess, 'Review submitted successfully.' AS Message,
                   v_ReviewId   AS ReviewId,
                   p_UserId     AS ReviewerUserId,
                   v_AuthorName AS AuthorName,
                   v_OrgName    AS OrgName;
        END IF;
    END IF;
END //

-- ── 3. OrgReview_Delete — return notification fields ─────────
DROP PROCEDURE IF EXISTS OrgReview_Delete //
CREATE PROCEDURE OrgReview_Delete(
    IN p_UserId    INT UNSIGNED,
    IN p_ReviewId  INT UNSIGNED
)
BEGIN
    DECLARE v_OrgId          INT UNSIGNED DEFAULT NULL;
    DECLARE v_ReviewerUserId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OverallRating  TINYINT      DEFAULT 0;
    DECLARE v_AuthorName     VARCHAR(200) DEFAULT '';
    DECLARE v_OrgName        VARCHAR(200) DEFAULT '';

    SELECT OrgId, UserId, OverallRating
    INTO   v_OrgId, v_ReviewerUserId, v_OverallRating
    FROM   OrgReviews
    WHERE  ReviewId = p_ReviewId AND UserId = p_UserId AND IsDeleted = 0
    LIMIT  1;

    IF v_OrgId IS NULL THEN
        SELECT 0 AS IsSuccess, 'Review not found or you are not the author.' AS Message,
               NULL AS ReviewerUserId, NULL AS AuthorName, NULL AS OverallRating,
               NULL AS OrgName, NULL AS OrgId;
    ELSE
        SELECT TRIM(CONCAT(IFNULL(up.FirstName,''), ' ', IFNULL(up.LastName,'')))
        INTO   v_AuthorName
        FROM   UserProfiles up WHERE up.UserId = v_ReviewerUserId LIMIT 1;

        SELECT o.OrgName INTO v_OrgName FROM Organisations o WHERE o.OrgId = v_OrgId LIMIT 1;

        UPDATE OrgReviews SET IsDeleted = 1 WHERE ReviewId = p_ReviewId;

        UPDATE Organisations
        SET    AvgRating   = IFNULL((SELECT ROUND(AVG(OverallRating),2) FROM OrgReviews WHERE OrgId = v_OrgId AND IsApproved=1 AND IsDeleted=0), 0.00),
               RatingCount = (SELECT COUNT(*) FROM OrgReviews WHERE OrgId = v_OrgId AND IsApproved=1 AND IsDeleted=0)
        WHERE  OrgId = v_OrgId;

        SELECT 1 AS IsSuccess, 'Review deleted.' AS Message,
               v_ReviewerUserId AS ReviewerUserId,
               v_AuthorName     AS AuthorName,
               v_OverallRating  AS OverallRating,
               v_OrgName        AS OrgName,
               v_OrgId          AS OrgId;
    END IF;
END //

-- ── 4. OrgReview_AddResponse — return notification fields ────
DROP PROCEDURE IF EXISTS OrgReview_AddResponse //
CREATE PROCEDURE OrgReview_AddResponse(
    IN p_AdminUserId   INT UNSIGNED,
    IN p_OrgId         INT UNSIGNED,
    IN p_ReviewId      INT UNSIGNED,
    IN p_ResponseText  TEXT
)
BEGIN
    DECLARE v_IsAdmin        TINYINT      DEFAULT 0;
    DECLARE v_ReviewOrg      INT UNSIGNED DEFAULT NULL;
    DECLARE v_ReviewerUserId INT UNSIGNED DEFAULT NULL;
    DECLARE v_OrgName        VARCHAR(200) DEFAULT '';

    SELECT COUNT(*) INTO v_IsAdmin
    FROM   OrgMembers om
    JOIN   LookupValues lv ON om.RoleLkpId = lv.LookupValueId
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  om.UserId   = p_AdminUserId
      AND  om.OrgId    = p_OrgId
      AND  lt.TypeCode = 'ORG_ROLE'
      AND  lv.ValueCode IN ('ADMIN','SUPER_ADMIN')
      AND  om.IsActive = 1;

    SELECT OrgId, UserId INTO v_ReviewOrg, v_ReviewerUserId
    FROM   OrgReviews WHERE ReviewId = p_ReviewId AND IsDeleted = 0 LIMIT 1;

    IF v_IsAdmin = 0 THEN
        SELECT 0 AS IsSuccess, 'Only NGO admins can respond to reviews.' AS Message,
               NULL AS ReviewerUserId, NULL AS OrgName;
    ELSEIF v_ReviewOrg IS NULL OR v_ReviewOrg != p_OrgId THEN
        SELECT 0 AS IsSuccess, 'Review not found for this NGO.' AS Message,
               NULL AS ReviewerUserId, NULL AS OrgName;
    ELSE
        SELECT OrgName INTO v_OrgName FROM Organisations WHERE OrgId = p_OrgId LIMIT 1;

        INSERT INTO OrgReviewResponses (ReviewId, OrgId, RespondedByUserId, ResponseText)
        VALUES (p_ReviewId, p_OrgId, p_AdminUserId, p_ResponseText)
        ON DUPLICATE KEY UPDATE
            ResponseText      = VALUES(ResponseText),
            RespondedByUserId = VALUES(RespondedByUserId),
            IsDeleted         = 0,
            UpdatedAt         = NOW();

        SELECT 1 AS IsSuccess, 'Response posted successfully.' AS Message,
               v_ReviewerUserId AS ReviewerUserId,
               v_OrgName        AS OrgName;
    END IF;
END //

DELIMITER ;

-- ── Schema version ────────────────────────────────────────────
INSERT IGNORE INTO SchemaVersions (Version, Description, AppliedBy)
VALUES ('v5.2', 'v5.2: Review notifications — 3 new NOTIFICATION_TYPE lookup values (REVIEW_NEW, REVIEW_RESPONSE, REVIEW_DELETED); OrgReview_Add, OrgReview_Delete, OrgReview_AddResponse updated to return notification fields.', 'System');

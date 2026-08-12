-- ── patch_fix_badge_award_code.sql ───────────────────────────────────────────
-- Change : UserBadge_Award SP accepts p_BadgeCode VARCHAR(50) (ValueCode string)
--          instead of p_BadgeLkpId INT UNSIGNED.
--          The SP now resolves the LookupValueId internally from BADGE_TYPE.
--
-- Why    : Mobile BADGE_DEFS uses ValueCode strings (STAR_VOL, TEAM_PLAYER, etc.).
--          Passing a LookupValueId from the client required the client to know DB
--          internal IDs — violates the Core Mandate (Dynamic / Efficient).
--          Accepting the ValueCode string is cleaner and future-proof.
--
-- Impact : OrgDal.AwardBadgeAsync + BadgeDal.AwardAsync updated in same session.
--          No table schema changes. Safe to re-run.
-- Run    : local → Railway staging → production.
-- ─────────────────────────────────────────────────────────────────────────────

USE ngoconnect;

DELIMITER //

DROP PROCEDURE IF EXISTS UserBadge_Award //
CREATE PROCEDURE UserBadge_Award(
    IN p_UserId    INT UNSIGNED,
    IN p_BadgeCode VARCHAR(50),
    IN p_AwardedBy INT UNSIGNED,
    IN p_OrgId     INT UNSIGNED,
    IN p_ProjectId INT UNSIGNED
)
BEGIN
    DECLARE v_BadgeLkpId INT UNSIGNED DEFAULT NULL;
    DECLARE v_BadgeName  VARCHAR(100) DEFAULT 'Badge';
    DECLARE v_Exists     INT DEFAULT 0;

    -- Resolve LookupValueId from ValueCode
    SELECT lv.LookupValueId INTO v_BadgeLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'BADGE_TYPE' AND lv.ValueCode = p_BadgeCode LIMIT 1;

    IF v_BadgeLkpId IS NULL THEN
        SELECT 0 AS IsSuccess,
               CONCAT('Unknown badge code: ', p_BadgeCode) AS Message,
               NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
    ELSE
        -- Prevent double-awarding the same badge on the same project
        SELECT COUNT(*) INTO v_Exists
        FROM   UserBadges
        WHERE  UserId     = p_UserId
          AND  BadgeLkpId = v_BadgeLkpId
          AND  (p_ProjectId IS NULL OR ProjectId = p_ProjectId)
          AND  IsDeleted   = 0;

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess,
                   'This badge has already been awarded to this volunteer.' AS Message,
                   NULL AS BadgeId, NULL AS BadgeName, NULL AS UserId;
        ELSE
            SELECT ValueName INTO v_BadgeName
            FROM   LookupValues WHERE LookupValueId = v_BadgeLkpId LIMIT 1;

            INSERT INTO UserBadges
                (UserId, BadgeLkpId, AwardedBy, AwardedByOrgId, ProjectId, IsDeleted, CreatedAt)
            VALUES
                (p_UserId, v_BadgeLkpId, p_AwardedBy, p_OrgId, p_ProjectId, 0, NOW());

            SELECT 1 AS IsSuccess,
                   'Badge awarded successfully.' AS Message,
                   LAST_INSERT_ID() AS BadgeId,
                   v_BadgeName      AS BadgeName,
                   p_UserId         AS UserId;
        END IF;
    END IF;
END //

DELIMITER ;

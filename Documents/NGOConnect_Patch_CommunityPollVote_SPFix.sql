-- =============================================================================
-- Patch: Community_CreatePoll + Community_Vote — replace v4.1 2-param versions
--        with the correct multi-param versions that match CommunityDal.cs
--
-- Problem: NGOConnect_Complete_Setup_v4.1.sql had simplified versions:
--   Community_CreatePoll(p_CommunityPostId, p_Options TEXT)   ← 2 params
--   Community_Vote(p_PollOptionId, p_UserId)                  ← 2 params
-- DAL calls them with 5 and 3 params respectively → "Parameter not found" error
--
-- Run once in MySQL Workbench against ngoconnect DB.
-- =============================================================================

USE ngoconnect;

DELIMITER //

-- ── Community_CreatePoll ─────────────────────────────────────────────────────
-- Creates the CommunityPost (type=POLL) + inserts all poll options in one call.
DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT
)
BEGIN
    DECLARE v_PollTypeLkpId INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId INT UNSIGNED DEFAULT 0;

    SELECT lv.LookupValueId INTO v_PollTypeLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

    SELECT lv.LookupValueId INTO v_AudienceLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
    WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;

    IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
    IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

    INSERT INTO CommunityPosts
        (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, CreatedBy)
    VALUES (
        p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
        v_AudienceLkpId,
        CASE WHEN p_ExpiresInHours > 0
             THEN DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR)
             ELSE NULL END,
        p_UserId
    );

    SET @PollId = LAST_INSERT_ID();

    INSERT INTO PollOptions (CommunityPostId, OptionText, SortOrder)
    SELECT @PollId, jt.opt, jt.rn
    FROM JSON_TABLE(p_OptionsJson, '$[*]' COLUMNS (
        rn   FOR ORDINALITY,
        opt  VARCHAR(200) PATH '$'
    )) AS jt
    WHERE TRIM(jt.opt) != '';

    SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId;
END //

-- ── Community_Vote ───────────────────────────────────────────────────────────
-- Records a vote; prevents double-voting and voting on expired polls.
DROP PROCEDURE IF EXISTS Community_Vote //
CREATE PROCEDURE Community_Vote(
    IN p_PollId       INT UNSIGNED,
    IN p_UserId       INT UNSIGNED,
    IN p_PollOptionId INT UNSIGNED
)
BEGIN
    DECLARE v_Exists  INT DEFAULT 0;
    DECLARE v_Expired INT DEFAULT 0;

    SELECT COUNT(*) INTO v_Expired FROM CommunityPosts
    WHERE  CommunityPostId = p_PollId
      AND  PollEndsAt IS NOT NULL AND PollEndsAt < NOW();

    SELECT COUNT(*) INTO v_Exists FROM PollVotes
    WHERE  CommunityPostId = p_PollId AND UserId = p_UserId;

    IF v_Expired > 0 THEN
        SELECT 0 AS IsSuccess, 'This poll has expired.' AS Message;
    ELSEIF v_Exists > 0 THEN
        SELECT 0 AS IsSuccess, 'You have already voted on this poll.' AS Message;
    ELSE
        INSERT INTO PollVotes (PollOptionId, CommunityPostId, UserId)
        VALUES (p_PollOptionId, p_PollId, p_UserId);

        UPDATE PollOptions SET VoteCount = VoteCount + 1
        WHERE  PollOptionId = p_PollOptionId;

        SELECT 1 AS IsSuccess, 'Vote recorded.' AS Message;
    END IF;
END //

DELIMITER ;

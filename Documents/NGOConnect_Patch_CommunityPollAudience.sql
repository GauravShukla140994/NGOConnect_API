-- ============================================================
-- NGO Connect — Patch: Community_CreatePoll audience support
-- Version : v5.1 patch
-- Date    : 2026-08-08
-- Apply to: Railway staging → Railway production
-- ============================================================
--
-- Problem
-- -------
-- Polls created with "Only Admins" or "Volunteers" audience were
-- always saved as ALL_MEMBERS because Community_CreatePoll had no
-- p_AudienceLkpId parameter — it hardcoded ALL_MEMBERS every time.
-- The mobile app was sending audienceLkpId in the request body,
-- but the SP silently discarded it.
--
-- Additionally, the notification fan-out in CommunityDal always
-- notified ALL members regardless of audience — ADMINS_ONLY polls
-- would alert regular members about a poll they cannot see.
--
-- Fix
-- ---
-- 1. SP: Added p_AudienceLkpId parameter (INT UNSIGNED, NULL/0 = ALL_MEMBERS).
--    Validates the supplied ID against AUDIENCE_TYPE; falls back to ALL_MEMBERS
--    if not found or not supplied. Returns AudienceCode in the result row so
--    the DAL can scope notification fan-out without a second DB trip.
-- 2. DAL (CommunityDal.CreatePollAsync): Now passes p_AudienceLkpId and reads
--    AudienceCode from the result to send notifications only to the correct
--    audience (GetAdminsWithTokensAsync for ADMINS_ONLY, GetMembersWithTokensAsync
--    for everything else).
-- 3. Model (CreatePollRequest): Added AudienceLkpId int? — the mobile was already
--    sending it; now it is accepted and passed through.
--
-- NOTE: If NGOConnect_Patch_VisibilityAudienceFilter.sql was NOT yet applied to
-- Railway, apply it FIRST — it contains the Community_GetFeed SP that enforces
-- the ADMINS_ONLY read filter. Without it, the save-side fix here is not enough:
-- posts will be saved correctly but still returned to all members on read.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Community_CreatePoll //
CREATE PROCEDURE Community_CreatePoll(
    IN p_UserId         INT UNSIGNED,
    IN p_OrgId          INT UNSIGNED,
    IN p_Question       VARCHAR(300),
    IN p_OptionsJson    JSON,
    IN p_ExpiresInHours INT,
    IN p_IsMultiChoice  TINYINT(1),
    IN p_AudienceLkpId  INT UNSIGNED   -- NULL/0 = default to ALL_MEMBERS
)
BEGIN
    DECLARE v_ApprovedLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_CanCommunityPost TINYINT(1)  DEFAULT 0;
    DECLARE v_PollTypeLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceLkpId    INT UNSIGNED DEFAULT 0;
    DECLARE v_AudienceCode     VARCHAR(50)  DEFAULT 'ALL_MEMBERS';

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
               'You do not have permission to create polls in this community.' AS Message,
               NULL AS PollId,
               NULL AS AudienceCode;
    ELSE
        SELECT lv.LookupValueId INTO v_PollTypeLkpId
        FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
        WHERE  lt.TypeCode = 'POST_TYPE_COMMUNITY' AND lv.ValueCode = 'POLL' LIMIT 1;

        -- Use caller-supplied audience if it resolves to a valid AUDIENCE_TYPE entry;
        -- otherwise fall back to ALL_MEMBERS.
        IF p_AudienceLkpId IS NOT NULL AND p_AudienceLkpId > 0 THEN
            SELECT lv.LookupValueId, lv.ValueCode
            INTO   v_AudienceLkpId, v_AudienceCode
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.LookupValueId = p_AudienceLkpId LIMIT 1;
        END IF;

        -- If nothing was resolved (NULL/0 input OR supplied ID not found), default to ALL_MEMBERS
        IF v_AudienceLkpId = 0 THEN
            SELECT lv.LookupValueId, lv.ValueCode
            INTO   v_AudienceLkpId, v_AudienceCode
            FROM   LookupValues lv JOIN LookupTypes lt ON lt.LookupTypeId = lv.LookupTypeId
            WHERE  lt.TypeCode = 'AUDIENCE_TYPE' AND lv.ValueCode = 'ALL_MEMBERS' LIMIT 1;
        END IF;

        IF v_PollTypeLkpId = 0 THEN SET v_PollTypeLkpId = 1; END IF;
        IF v_AudienceLkpId = 0 THEN SET v_AudienceLkpId = 1; END IF;

        INSERT INTO CommunityPosts
            (OrgId, UserId, PostTypeLkpId, Title, AudienceLkpId, PollEndsAt, PollIsMultiChoice, CreatedBy)
        VALUES (
            p_OrgId, p_UserId, v_PollTypeLkpId, p_Question,
            v_AudienceLkpId,
            CASE WHEN p_ExpiresInHours > 0
                 THEN DATE_ADD(NOW(), INTERVAL p_ExpiresInHours HOUR)
                 ELSE NULL END,
            COALESCE(p_IsMultiChoice, 0),
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

        SELECT 1 AS IsSuccess, 'Poll created successfully.' AS Message, @PollId AS PollId, v_AudienceCode AS AudienceCode;
    END IF;
END //

DELIMITER ;

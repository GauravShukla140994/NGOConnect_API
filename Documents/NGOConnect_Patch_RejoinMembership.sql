-- ============================================================
-- NGOConnect Patch: Org_RequestMembership — allow re-join after deactivation
-- Date:    2026-07-28
-- Version: v2 (supersedes original patch applied to Railway)
--
-- Problem 1 — "Request already submitted" on re-join:
--   When a member is deactivated (OrgMembers.IsDeleted = 1), the
--   original OrgMembershipRequests row is NOT deleted — it keeps
--   IsDeleted = 0 with status APPROVED.
--   The original duplicate check was status-agnostic and matched the
--   old APPROVED row → "Request already submitted."
--
-- Fix 1 — PENDING-only duplicate check:
--   Change the duplicate check to only block on an active PENDING
--   request. APPROVED / REJECTED rows are historical records, not blockers.
--
-- Problem 2 — "An error occurred" after Fix 1:
--   OrgMembershipRequests has a UNIQUE KEY on (OrgId, UserId, IsDeleted).
--   After Fix 1 passes the duplicate check, the plain INSERT tries to
--   insert a new row with (OrgId, UserId, IsDeleted=0) — which collides
--   with the existing APPROVED row that also has IsDeleted=0.
--   MySQL throws a duplicate-key error → "An error occurred."
--
-- Fix 2 — UPDATE-first, INSERT only when no existing row:
--   Instead of a plain INSERT, first try to UPDATE the existing
--   non-deleted row back to PENDING with the fresh form data.
--   Only INSERT if no such row exists (first-time join scenario).
--
-- Apply to: Railway Staging, then Railway Production
-- ============================================================

DELIMITER //

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
        -- Fix 1: Only block on an active PENDING request.
        -- APPROVED / REJECTED rows are historical — a user who was a member
        -- and later deactivated (or was previously rejected) must be allowed to re-apply.
        SELECT COUNT(*) INTO v_Exists
        FROM   OrgMembershipRequests omr
        JOIN   LookupValues lv ON lv.LookupValueId = omr.StatusLkpId
        JOIN   LookupTypes  lt ON lt.LookupTypeId  = lv.LookupTypeId
        WHERE  omr.OrgId = p_OrgId AND omr.UserId = p_UserId
          AND  omr.IsDeleted = 0
          AND  lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING';

        IF v_Exists > 0 THEN
            SELECT 0 AS IsSuccess, 'Request already submitted.' AS Message, NULL AS RequestId;
        ELSE
            SELECT LookupValueId INTO v_StatusLkpId FROM LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
            WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING' LIMIT 1;

            -- Fix 2: OrgMembershipRequests has UNIQUE KEY (OrgId, UserId, IsDeleted).
            -- A re-joining user may have an old APPROVED/REJECTED row with IsDeleted=0
            -- that would cause a duplicate-key error on plain INSERT.
            -- UPDATE the existing non-deleted row to PENDING (re-use it with fresh form data).
            -- Only INSERT if no such row exists (first-time join).
            UPDATE OrgMembershipRequests
            SET    StatusLkpId       = v_StatusLkpId,
                   PrevNgoExperience = p_PrevNgoExperience,
                   VolunteerSkills   = p_VolunteerSkills,
                   AreasOfInterest   = p_AreasOfInterest,
                   WhyJoin           = p_WhyJoin,
                   ReviewedBy        = NULL,
                   ReviewedAt        = NULL,
                   ReviewNote        = NULL
            WHERE  OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0;

            IF ROW_COUNT() > 0 THEN
                -- Re-join: existing APPROVED/REJECTED row reset to PENDING
                SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message,
                       (SELECT RequestId FROM OrgMembershipRequests
                        WHERE OrgId = p_OrgId AND UserId = p_UserId AND IsDeleted = 0 LIMIT 1) AS RequestId;
            ELSE
                -- First-time join: no existing row, safe to INSERT
                INSERT INTO OrgMembershipRequests
                    (OrgId, UserId, PrevNgoExperience, VolunteerSkills, AreasOfInterest, WhyJoin, StatusLkpId)
                VALUES
                    (p_OrgId, p_UserId, p_PrevNgoExperience, p_VolunteerSkills, p_AreasOfInterest, p_WhyJoin, v_StatusLkpId);
                SELECT 1 AS IsSuccess, 'Membership request submitted.' AS Message, LAST_INSERT_ID() AS RequestId;
            END IF;

            -- ── Auto-follow on join request ────────────────────────────────────
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

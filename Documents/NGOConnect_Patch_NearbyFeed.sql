-- ============================================================
-- NGOConnect Patch — Project_GetNearbyFeed (Personalised home-screen feed)
-- Apply to: Railway staging + production
-- Date: 2026-07-12
-- Context:
--   Home screen "Nearby Opportunities" section previously used the generic
--   Project_List SP (no personalization, basic distance sort only).
--   This SP replaces that with a personalised, distance-banded feed that
--   weighs NGO membership, NGO following, skill matches, and interest matches.
-- Algorithm:
--   Sort key 1: FLOOR(DistanceKm / 10) ASC   — 10 km bands
--   Sort key 2: RelevanceScore DESC            — most relevant within band
--   Sort key 3: DistanceKm ASC                — nearest tie-break
--   Sort key 4: CreatedAt DESC                 — newest tie-break
-- RelevanceScore:
--   +5  user is an approved member of the project's NGO
--   +3  user is actively following the project's NGO
--   +2  per skill match (UserSkills ↔ ProjectSkills, case-insensitive), capped at 3
--   +3  any UserInterest name partially matches the project's Category
-- Filters:
--   Status = ACTIVE or UPCOMING
--   IsPublic = 1
--   User has no application for the project (ANY status — PENDING/APPROVED/REJECTED etc.)
--   DistanceKm ≤ 1000 km (projects without GPS sort last at band 999999)
-- No table changes — SP only.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Project_GetNearbyFeed //
CREATE PROCEDURE Project_GetNearbyFeed(
    IN p_UserId     INT UNSIGNED,
    IN p_UserLat    DECIMAL(10,7),   -- NULL = no GPS (distance skipped)
    IN p_UserLon    DECIMAL(10,7),
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset        INT         DEFAULT (p_PageNumber - 1) * p_PageSize;
    DECLARE v_ActiveLkpId   INT UNSIGNED DEFAULT 0;
    DECLARE v_UpcomingLkpId INT UNSIGNED DEFAULT 0;

    SELECT LookupValueId INTO v_ActiveLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'ACTIVE'   LIMIT 1;

    SELECT LookupValueId INTO v_UpcomingLkpId
    FROM   LookupValues lv JOIN LookupTypes lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'PROJECT_STATUS' AND lv.ValueCode = 'UPCOMING' LIMIT 1;

    SELECT
        p.ProjectId,
        p.OrgId,
        o.OrgName,
        o.LogoUrl           AS OrgLogoUrl,
        p.ProjectName,
        p.Description,
        p.Category          AS CategoryName,
        ptv.ValueCode       AS ProjectTypeCode,
        ptv.ValueName       AS ProjectType,
        ltv.ValueCode       AS LocationTypeCode,
        p.Landmark          AS LocationName,
        p.AddressLine       AS Address,
        p.City,
        p.State,
        sv.ValueCode        AS StatusCode,
        sv.ValueName        AS Status,
        p.Latitude,
        p.Longitude,
        p.MaxVolunteers,
        p.OneTimeDate,
        p.RecurStart,
        p.RecurEnd,
        p.RecurDays,
        p.SessionStartTime,
        p.SessionEndTime,
        p.FlexFromDate,
        p.FlexToDate,
        p.CreatedAt,
        -- Approved volunteer count (for "X / Y spots" display)
        (SELECT COUNT(*) FROM ProjectApplications pa2
         JOIN LookupValues alv2 ON pa2.StatusLkpId = alv2.LookupValueId
         WHERE pa2.ProjectId = p.ProjectId
           AND alv2.ValueCode = 'APPROVED'
           AND pa2.IsDeleted  = 0
        ) AS ApprovedCount,
        -- Haversine distance (km); NULL only when user has no GPS.
        -- Project GPS is guaranteed non-null by WHERE clause below.
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN ROUND(6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 )), 2)
            ELSE NULL
        END AS DistanceKm,
        -- Personalisation relevance score
        (
            -- +5: user is an approved member of this NGO (strongest signal)
            CASE WHEN EXISTS(
                SELECT 1 FROM OrgMembers om
                JOIN LookupValues lvm ON om.StatusLkpId = lvm.LookupValueId
                WHERE om.OrgId     = p.OrgId
                  AND om.UserId    = p_UserId
                  AND om.IsDeleted = 0
                  AND lvm.ValueCode = 'APPROVED'
            ) THEN 5 ELSE 0 END
            -- +3: user is actively following this NGO
            + CASE WHEN EXISTS(
                SELECT 1 FROM OrgFollowers of2
                WHERE of2.OrgId      = p.OrgId
                  AND of2.UserId     = p_UserId
                  AND of2.IsFollowing = 1
            ) THEN 3 ELSE 0 END
            -- +2 per skill match (case-insensitive), capped at 3 matches
            + LEAST(
                (SELECT COUNT(*)
                 FROM ProjectSkills ps
                 JOIN UserSkills us
                   ON LOWER(TRIM(ps.SkillName)) = LOWER(TRIM(us.SkillName))
                 WHERE ps.ProjectId = p.ProjectId
                   AND us.UserId    = p_UserId
                   AND us.IsDeleted = 0)
              , 3) * 2
            -- +3: any user interest name matches the project category (partial)
            + CASE WHEN EXISTS(
                SELECT 1 FROM UserInterests ui
                JOIN LookupValues lvi ON ui.InterestLkpId = lvi.LookupValueId
                WHERE ui.UserId = p_UserId
                  AND (LOWER(lvi.ValueName) LIKE CONCAT('%', LOWER(p.Category), '%')
                    OR LOWER(p.Category)    LIKE CONCAT('%', LOWER(lvi.ValueName), '%'))
            ) THEN 3 ELSE 0 END
        ) AS RelevanceScore
    FROM   Projects p
    JOIN   Organisations o       ON o.OrgId               = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv      ON sv.LookupValueId       = p.StatusLkpId
    LEFT JOIN LookupValues ptv   ON ptv.LookupValueId      = p.ProjectTypeLkpId
    LEFT JOIN LookupValues ltv   ON ltv.LookupValueId      = p.LocationTypeLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      -- Only projects with a map pin — no pin = not a nearby opportunity
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      -- Exclude projects the user has ever applied to (any status).
      -- Hidden until the project completes and is re-activated as a new cycle.
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      -- Distance guard: only within 1000 km when user GPS is available
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          )
    ORDER BY
        -- Band (10 km slices); when user has no GPS all share band 0 → sort by relevance
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN FLOOR(6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 )) / 10)
            ELSE 0
        END ASC,
        -- Within each band: most relevant first
        RelevanceScore DESC,
        -- Same relevance: nearest first
        CASE
            WHEN p_UserLat IS NOT NULL AND p_UserLon IS NOT NULL
            THEN 6371 * ACOS(LEAST(1.0,
                    COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                    * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                    + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
                 ))
            ELSE NULL
        END ASC,
        p.CreatedAt DESC
    LIMIT  p_PageSize OFFSET v_Offset;

    -- TotalCount for pagination (same filters, no pagination)
    SELECT COUNT(*) AS TotalCount
    FROM   Projects p
    JOIN   Organisations o  ON o.OrgId = p.OrgId AND o.IsDeleted = 0
    JOIN   LookupValues  sv ON sv.LookupValueId = p.StatusLkpId
    WHERE  p.IsDeleted = 0
      AND  p.IsPublic  = 1
      AND  p.StatusLkpId IN (v_ActiveLkpId, v_UpcomingLkpId)
      AND  p.Latitude  IS NOT NULL
      AND  p.Longitude IS NOT NULL
      AND  NOT EXISTS(
               SELECT 1 FROM ProjectApplications pa
               WHERE pa.ProjectId = p.ProjectId
                 AND pa.UserId    = p_UserId
                 AND pa.IsDeleted = 0
           )
      AND (
            p_UserLat IS NULL OR p_UserLon IS NULL
            OR 6371 * ACOS(LEAST(1.0,
                   COS(RADIANS(p_UserLat)) * COS(RADIANS(p.Latitude))
                   * COS(RADIANS(p.Longitude) - RADIANS(p_UserLon))
                   + SIN(RADIANS(p_UserLat)) * SIN(RADIANS(p.Latitude))
               )) <= 1000
          );
END //

DELIMITER ;

-- ── Covering index on ProjectSkills ──────────────────────────────────────────
-- The skill-match correlated subquery in Project_GetNearbyFeed does:
--   FROM ProjectSkills ps JOIN UserSkills us ON LOWER(TRIM(ps.SkillName)) = ...
--   WHERE ps.ProjectId = p.ProjectId
-- With (ProjectId, SkillName) as a covering index, MySQL can resolve the
-- entire subquery from the index without touching the actual row data.
-- Safe to run on live DB — online DDL, no data change.
ALTER TABLE ProjectSkills
    DROP INDEX   idx_projskill_project,
    ADD  INDEX   idx_projskill_project (ProjectId, SkillName);

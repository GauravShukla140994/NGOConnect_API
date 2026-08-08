-- ============================================================
-- NGO Connect — Patch: Verification Badges
-- Changes:
--   1. ORG_VERIFICATION_STATUS LookupType + values
--   2. REJECTED added to PROFILE_VERIFICATION_STATUS
--   3. ALTER Organisations — add VerificationStatusLkpId column
--   4. Org_GetMembers — add ProfileVerificationStatusCode
--   5. Org_GetPendingMembers — add ProfileVerificationStatusCode
--   6. Org_GetProfile — add VerificationStatusCode
--   7. Org_ListRecommended — add VerificationStatusCode
--   8. SuperAdmin_Org_VerifyProfile — new SP
-- Apply to: Railway staging + production
-- Date: 2026-07-14
-- ============================================================

-- ── 1. Seed ORG_VERIFICATION_STATUS LookupType ───────────────────────────────
INSERT IGNORE INTO LookupTypes (TypeCode, TypeName, Description, IsSystemType)
VALUES ('ORG_VERIFICATION_STATUS', 'Org Verification Status',
        'Super Admin legal document verification state for an organisation', 1);

INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT LookupTypeId, 'PENDING',  'Pending Review', 1, 1, 1 FROM LookupTypes WHERE TypeCode = 'ORG_VERIFICATION_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv2.ValueCode = 'PENDING')
UNION ALL
SELECT LookupTypeId, 'VERIFIED', 'Verified',       2, 1, 0 FROM LookupTypes WHERE TypeCode = 'ORG_VERIFICATION_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv2.ValueCode = 'VERIFIED')
UNION ALL
SELECT LookupTypeId, 'REJECTED', 'Rejected',       3, 1, 0 FROM LookupTypes WHERE TypeCode = 'ORG_VERIFICATION_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv2.ValueCode = 'REJECTED');

-- ── 2. Add REJECTED to PROFILE_VERIFICATION_STATUS ───────────────────────────
INSERT INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, IsDefault)
SELECT LookupTypeId, 'REJECTED', 'Rejected', 4, 1, 0 FROM LookupTypes WHERE TypeCode = 'PROFILE_VERIFICATION_STATUS'
  AND NOT EXISTS (SELECT 1 FROM LookupValues lv2 JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                  WHERE lt2.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv2.ValueCode = 'REJECTED');

-- ── 3. ALTER Organisations — add VerificationStatusLkpId ─────────────────────
ALTER TABLE Organisations
    ADD COLUMN VerificationStatusLkpId INT UNSIGNED NULL
        COMMENT 'Super Admin legal document verification state — FK to ORG_VERIFICATION_STATUS';

ALTER TABLE Organisations
    ADD INDEX idx_org_verification (VerificationStatusLkpId);

ALTER TABLE Organisations
    ADD CONSTRAINT fk_orgs_verificationstatus
        FOREIGN KEY (VerificationStatusLkpId) REFERENCES LookupValues(LookupValueId);

-- ── 4–8. Re-create SPs ───────────────────────────────────────────────────────
DELIMITER //

DROP PROCEDURE IF EXISTS Org_GetMembers //
CREATE PROCEDURE Org_GetMembers(IN p_OrgId INT UNSIGNED)
BEGIN
    SELECT
        om.OrgMemberId                                     AS MemberId,
        om.UserId,
        CONCAT(up.FirstName, ' ', up.LastName)             AS FullName,
        u.Email,
        u.Mobile                                           AS Phone,
        up.ProfilePhoto,
        up.Occupation,
        rv.ValueCode                                       AS RoleCode,
        rv.ValueName                                       AS RoleName,
        sv.ValueCode                                       AS StatusCode,
        sv.ValueName                                       AS StatusName,
        om.CanPost, om.CanComment, om.CanCommunityPost, om.MaxPostsPerDay,
        CASE WHEN lsv.ValueCode IS NOT NULL AND lsv.ValueCode != 'DISABLED' THEN 1 ELSE 0 END AS LocationSharing,
        om.JoinedAt,
        u.IsActive,
        u.LastLoginAt                                      AS LastActiveAt,
        COALESCE(pv.ValueCode, 'PENDING')                  AS ProfileVerificationStatusCode
    FROM OrgMembers om
    JOIN Users        u  ON om.UserId = u.UserId  AND u.IsDeleted  = 0
    JOIN UserProfiles up ON om.UserId = up.UserId AND up.IsDeleted = 0
    LEFT JOIN LookupValues rv  ON om.RoleLkpId               = rv.LookupValueId
    LEFT JOIN LookupValues sv  ON om.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues lsv ON om.LocationSharingLkpId    = lsv.LookupValueId
    LEFT JOIN LookupValues pv  ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE om.OrgId = p_OrgId AND om.IsDeleted = 0
    ORDER BY om.JoinedAt ASC;
END //

DROP PROCEDURE IF EXISTS Org_GetPendingMembers //
CREATE PROCEDURE Org_GetPendingMembers(
    IN p_OrgId      INT UNSIGNED,
    IN p_PageNumber INT,
    IN p_PageSize   INT
)
BEGIN
    DECLARE v_Offset       INT;
    DECLARE v_PageSize     INT;
    DECLARE v_PageNumber   INT;
    DECLARE v_PendingLkpId INT UNSIGNED;

    SET v_PageNumber = IFNULL(p_PageNumber, 1);
    SET v_PageSize   = IFNULL(p_PageSize,   100);
    SET v_Offset     = (v_PageNumber - 1) * v_PageSize;

    SELECT LookupValueId INTO v_PendingLkpId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'MEMBER_STATUS' AND lv.ValueCode = 'PENDING'
    LIMIT 1;

    SELECT
        mr.RequestId   AS MembershipRequestId,
        mr.UserId,
        CONCAT(up.FirstName, ' ', up.LastName) AS FullName,
        up.ProfilePhoto,
        up.City,
        up.State,
        mr.PrevNgoExperience,
        mr.VolunteerSkills,
        mr.AreasOfInterest,
        mr.WhyJoin,
        mr.CreatedAt AS RequestedAt,
        COALESCE(pv.ValueCode, 'PENDING') AS ProfileVerificationStatusCode
    FROM OrgMembershipRequests mr
    JOIN UserProfiles up ON mr.UserId = up.UserId AND up.IsDeleted = 0
    JOIN Users        u  ON mr.UserId = u.UserId  AND u.IsDeleted  = 0
    LEFT JOIN LookupValues pv ON u.ProfileVerificationLkpId = pv.LookupValueId
    WHERE mr.OrgId = p_OrgId
      AND mr.StatusLkpId = v_PendingLkpId
      AND mr.IsDeleted = 0
    ORDER BY mr.CreatedAt ASC
    LIMIT v_PageSize OFFSET v_Offset;

    SELECT COUNT(*) AS TotalCount
    FROM OrgMembershipRequests
    WHERE OrgId = p_OrgId AND StatusLkpId = v_PendingLkpId AND IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Org_GetProfile //
CREATE PROCEDURE Org_GetProfile(
    IN p_OrgId  INT UNSIGNED,
    IN p_UserId INT UNSIGNED
)
BEGIN
    SELECT
        o.OrgId, o.OrgName, o.RegNumber, o.Category, o.ContactPerson,
        o.LogoUrl, o.About, o.Mission, o.Vision,
        o.ContactEmail, o.ContactPhone, o.Website,
        o.AddressLine1, o.AddressLine2, o.City, o.State, o.Pincode, o.Country,
        o.OrgTypeLkpId,
        tv.ValueName AS OrgType,
        o.StatusLkpId,
        sv.ValueName AS OrgStatus,
        sv.ValueCode AS OrgStatusCode,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        o.AvgRating, o.RatingCount, o.Latitude, o.Longitude, o.CreatedAt,
        o.FollowerCount,
        IFNULL((SELECT of2.IsFollowing
                FROM OrgFollowers of2
                WHERE of2.OrgId = o.OrgId AND of2.UserId = p_UserId
                LIMIT 1), 0) AS IsFollowing,
        (SELECT COUNT(*)
         FROM OrgMembers   om2
         JOIN LookupValues lv2 ON om2.StatusLkpId  = lv2.LookupValueId
         JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
         WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
           AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'
        ) AS MemberCount,
        COALESCE(
            (SELECT lv3.ValueCode FROM OrgMembers om3
             JOIN LookupValues lv3 ON om3.StatusLkpId = lv3.LookupValueId
             WHERE om3.OrgId = o.OrgId AND om3.UserId = p_UserId AND om3.IsDeleted = 0 LIMIT 1),
            (SELECT lv4.ValueCode FROM OrgMembershipRequests mr4
             JOIN LookupValues lv4 ON mr4.StatusLkpId = lv4.LookupValueId
             WHERE mr4.OrgId = o.OrgId AND mr4.UserId = p_UserId AND mr4.IsDeleted = 0
               AND lv4.ValueCode = 'PENDING' LIMIT 1)
        ) AS MemberStatusCode
    FROM Organisations o
    LEFT JOIN LookupValues tv ON o.OrgTypeLkpId            = tv.LookupValueId
    LEFT JOIN LookupValues sv ON o.StatusLkpId             = sv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    WHERE o.OrgId = p_OrgId AND o.IsDeleted = 0;
END //

DROP PROCEDURE IF EXISTS Org_ListRecommended //
CREATE PROCEDURE Org_ListRecommended(IN p_UserId INT)
BEGIN
    DECLARE v_ApprovedId INT;

    SELECT lv.LookupValueId INTO v_ApprovedId
    FROM LookupValues lv
    JOIN LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE lt.TypeCode = 'ORG_STATUS' AND lv.ValueCode = 'APPROVED'
    LIMIT 1;

    SELECT
        o.OrgId, o.OrgName, o.Category, o.LogoUrl, o.City, o.State,
        IFNULL((SELECT COUNT(*) FROM OrgMembers om2
                 JOIN LookupValues lv2 ON om2.StatusLkpId = lv2.LookupValueId
                 JOIN LookupTypes  lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
                WHERE om2.OrgId = o.OrgId AND om2.IsDeleted = 0
                  AND lt2.TypeCode = 'MEMBER_STATUS' AND lv2.ValueCode = 'APPROVED'), 0) AS MemberCount,
        o.AvgRating, o.Latitude, o.Longitude,
        COALESCE(vv.ValueCode, 'PENDING') AS VerificationStatusCode,
        COUNT(ui.UserInterestId) AS MatchScore
    FROM Organisations o
    JOIN UserInterests ui ON ui.UserId = p_UserId
    JOIN LookupValues  lv ON ui.InterestLkpId = lv.LookupValueId
    LEFT JOIN LookupValues vv ON o.VerificationStatusLkpId = vv.LookupValueId
    WHERE o.IsDeleted = 0
      AND o.StatusLkpId = v_ApprovedId
      AND lv.ValueCode = o.Category
    GROUP BY o.OrgId, vv.ValueCode
    ORDER BY MatchScore DESC, o.AvgRating DESC
    LIMIT 20;
END //

DROP PROCEDURE IF EXISTS SuperAdmin_Org_VerifyProfile //
CREATE PROCEDURE SuperAdmin_Org_VerifyProfile(
    IN p_OrgId        INT UNSIGNED,
    IN p_StatusCode   VARCHAR(50),   -- PENDING | VERIFIED | REJECTED
    IN p_SuperAdminId INT UNSIGNED
)
BEGIN
    DECLARE v_StatusLkpId INT UNSIGNED;

    SELECT lv.LookupValueId INTO v_StatusLkpId
    FROM   LookupValues lv
    JOIN   LookupTypes  lt ON lv.LookupTypeId = lt.LookupTypeId
    WHERE  lt.TypeCode = 'ORG_VERIFICATION_STATUS' AND lv.ValueCode = p_StatusCode
    LIMIT  1;

    IF v_StatusLkpId IS NULL THEN
        SELECT 0 AS IsSuccess, CONCAT('Unknown status code: ', p_StatusCode) AS Message;
    ELSE
        UPDATE Organisations
        SET    VerificationStatusLkpId = v_StatusLkpId,
               UpdatedBy               = p_SuperAdminId
        WHERE  OrgId = p_OrgId AND IsDeleted = 0;

        SELECT 1 AS IsSuccess,
               CONCAT('Organisation verification status set to ', p_StatusCode, '.') AS Message;
    END IF;
END //

DELIMITER ;

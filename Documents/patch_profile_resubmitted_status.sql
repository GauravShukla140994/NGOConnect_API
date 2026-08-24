-- ─────────────────────────────────────────────────────────────────────────────
-- patch_profile_resubmitted_status.sql
--
-- Adds a new PROFILE_VERIFICATION_STATUS value, RESUBMITTED, and wires it into
-- the two SPs a member's own edits go through, so the Super Admin members list
-- can tell "flagged, member hasn't acted yet" (NEEDS_UPDATE) apart from
-- "member responded to the feedback, take another look" (RESUBMITTED) — before
-- this patch, nothing ever moved a member off NEEDS_UPDATE except an explicit
-- Super Admin "Mark as verified" click, even after the member fixed everything.
--
-- Covers:
--   1. New lookup value: PROFILE_VERIFICATION_STATUS / RESUBMITTED / OrderNo 5
--   2. User_UpdateProfile — flips NEEDS_UPDATE -> RESUBMITTED on profile edit
--   3. User_UploadDocument — flips NEEDS_UPDATE -> RESUBMITTED on doc re-upload
--
-- Companion Website change (not in this SQL file): StatusPill.jsx — added
-- RESUBMITTED -> orange pill, label "Resubmitted". No change needed to the
-- "Mark as verified" / "Request update" buttons — both already render
-- unconditionally regardless of current status.
--
-- Apply: local DB first → Railway staging → Railway production.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Step 1: new lookup value ─────────────────────────────────────────────────
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsSystemValue, CreatedBy)
SELECT LookupTypeId, 'RESUBMITTED', 'Resubmitted', 5, 1, 1
FROM LookupTypes WHERE TypeCode = 'PROFILE_VERIFICATION_STATUS';

DELIMITER //

-- ── Step 2: User_UpdateProfile ───────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_UpdateProfile //
CREATE PROCEDURE User_UpdateProfile(
    IN p_UserId         INT UNSIGNED,
    IN p_FirstName      VARCHAR(80),
    IN p_LastName       VARCHAR(80),
    IN p_Bio            TEXT,
    IN p_ProfilePhoto   VARCHAR(500),
    IN p_GenderLkpId    INT UNSIGNED,
    IN p_DateOfBirth    DATE,
    IN p_Occupation     VARCHAR(150),
    IN p_Organisation   VARCHAR(150),
    IN p_VolunteerExp   TEXT,
    IN p_EducationLkpId INT UNSIGNED,
    IN p_FieldOfStudy   VARCHAR(150),
    IN p_WorkExpLkpId   INT UNSIGNED,
    IN p_AddressLine1   VARCHAR(200),
    IN p_AddressLine2   VARCHAR(200),
    IN p_City           VARCHAR(100),
    IN p_State          VARCHAR(100),
    IN p_Pincode        VARCHAR(20),
    IN p_Country        VARCHAR(100)
)
BEGIN
    UPDATE UserProfiles SET
        FirstName      = COALESCE(p_FirstName,      FirstName),
        LastName       = COALESCE(p_LastName,       LastName),
        Bio            = COALESCE(p_Bio,            Bio),
        ProfilePhoto   = COALESCE(p_ProfilePhoto,   ProfilePhoto),
        GenderLkpId    = COALESCE(p_GenderLkpId,    GenderLkpId),
        DateOfBirth    = COALESCE(p_DateOfBirth,    DateOfBirth),
        Occupation     = COALESCE(p_Occupation,     Occupation),
        Organisation   = COALESCE(p_Organisation,   Organisation),
        VolunteerExp   = COALESCE(p_VolunteerExp,   VolunteerExp),
        EducationLkpId = COALESCE(p_EducationLkpId, EducationLkpId),
        FieldOfStudy   = COALESCE(p_FieldOfStudy,   FieldOfStudy),
        WorkExpLkpId   = COALESCE(p_WorkExpLkpId,   WorkExpLkpId),
        AddressLine1   = COALESCE(p_AddressLine1,   AddressLine1),
        AddressLine2   = COALESCE(p_AddressLine2,   AddressLine2),
        City           = COALESCE(p_City,           City),
        State          = COALESCE(p_State,          State),
        Pincode        = COALESCE(p_Pincode,        Pincode),
        Country        = COALESCE(p_Country,        Country),
        UpdatedAt      = NOW()
    WHERE UserId = p_UserId AND IsDeleted = 0;

    -- v5.1: if a Super Admin had flagged this profile NEEDS_UPDATE, editing the
    -- profile now flips it to RESUBMITTED so the Super Admin's member list shows
    -- this member needs a fresh look — distinct from NEEDS_UPDATE (nothing done
    -- yet) and from PENDING (never reviewed at all).
    UPDATE Users u
    JOIN LookupValues lv ON u.ProfileVerificationLkpId = lv.LookupValueId
    SET u.ProfileVerificationLkpId = (
            SELECT lv2.LookupValueId FROM LookupValues lv2
            JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE lt2.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv2.ValueCode = 'RESUBMITTED'
            LIMIT 1
        ),
        u.UpdatedAt = NOW()
    WHERE u.UserId = p_UserId AND lv.ValueCode = 'NEEDS_UPDATE';

    SELECT 1 AS IsSuccess, 'Profile updated.' AS Message;
END //

-- ── Step 3: User_UploadDocument ──────────────────────────────────────────────
DROP PROCEDURE IF EXISTS User_UploadDocument //
CREATE PROCEDURE User_UploadDocument(
    IN p_UserId            INT UNSIGNED,
    IN p_DocumentTypeLkpId INT UNSIGNED,
    IN p_FileUrl           VARCHAR(500),
    IN p_FileName          VARCHAR(255),
    IN p_FileSizeKb        INT UNSIGNED
)
BEGIN
    UPDATE UserDocuments
    SET    IsDeleted = 1, DeletedAt = NOW(), DeletedBy = p_UserId, UpdatedBy = p_UserId
    WHERE  UserId = p_UserId AND DocumentTypeLkpId = p_DocumentTypeLkpId AND IsDeleted = 0;

    INSERT INTO UserDocuments (UserId, DocumentTypeLkpId, FileUrl, FileName, FileSizeKb, CreatedBy, UpdatedBy)
    VALUES (p_UserId, p_DocumentTypeLkpId, p_FileUrl, p_FileName, p_FileSizeKb, p_UserId, p_UserId);

    -- v5.1: same RESUBMITTED flip as User_UpdateProfile — re-uploading a document
    -- after being flagged NEEDS_UPDATE signals the Super Admin should take another look.
    UPDATE Users u
    JOIN LookupValues lv ON u.ProfileVerificationLkpId = lv.LookupValueId
    SET u.ProfileVerificationLkpId = (
            SELECT lv2.LookupValueId FROM LookupValues lv2
            JOIN LookupTypes lt2 ON lv2.LookupTypeId = lt2.LookupTypeId
            WHERE lt2.TypeCode = 'PROFILE_VERIFICATION_STATUS' AND lv2.ValueCode = 'RESUBMITTED'
            LIMIT 1
        ),
        u.UpdatedAt = NOW()
    WHERE u.UserId = p_UserId AND lv.ValueCode = 'NEEDS_UPDATE';

    SELECT 1 AS IsSuccess, 'Document saved.' AS Message, LAST_INSERT_ID() AS UserDocumentId;
END //

DELIMITER ;

-- Verify
SELECT 'patch_profile_resubmitted_status applied successfully.' AS Status;

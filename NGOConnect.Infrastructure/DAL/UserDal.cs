using System.Data;
using System.Text.Json;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class UserDal : BaseDal, IUserDal
    {
        public UserDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<UserProfileModel>> GetProfileAsync(int userId)
        {
            try
            {
                var profile = await ExecuteGetAsync("User_GetProfile", MapProfile,
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_UserId",           userId);
                        _db.AddParameter(cmd, "p_RequestingUserId", 0);
                    });
                return profile is null
                    ? ApiResponse<UserProfileModel>.Failure("Profile not found.", "NOT_FOUND")
                    : ApiResponse<UserProfileModel>.Success(profile);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetProfileAsync failed UserId={UserId}", userId);
                return ApiResponse<UserProfileModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetPublicProfileAsync(int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("User_GetPublicProfile",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("User not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPublicProfileAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateProfileAsync(int userId, UpdateProfileRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_UpdateProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_FirstName",      request.FirstName);
                    _db.AddParameter(cmd, "p_LastName",       request.LastName);
                    _db.AddParameter(cmd, "p_Bio",            request.Bio);
                    _db.AddParameter(cmd, "p_ProfilePhoto",   request.ProfilePhoto);
                    _db.AddParameter(cmd, "p_GenderLkpId",    request.GenderLkpId);
                    _db.AddParameter(cmd, "p_DateOfBirth",    request.DateOfBirth);
                    _db.AddParameter(cmd, "p_Occupation",     request.Occupation);
                    _db.AddParameter(cmd, "p_Organisation",   request.Organisation);
                    _db.AddParameter(cmd, "p_VolunteerExp",   request.VolunteerExp);
                    _db.AddParameter(cmd, "p_EducationLkpId", request.EducationLkpId);
                    _db.AddParameter(cmd, "p_FieldOfStudy",   request.FieldOfStudy);
                    _db.AddParameter(cmd, "p_WorkExpLkpId",   request.WorkExpLkpId);
                    _db.AddParameter(cmd, "p_AddressLine1",   request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",   request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",           request.City);
                    _db.AddParameter(cmd, "p_State",          request.State);
                    _db.AddParameter(cmd, "p_Pincode",        request.Pincode);
                    _db.AddParameter(cmd, "p_Country",        request.Country);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateProfileAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateSafetyPrefsAsync(int userId, UpdateSafetyPrefsRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_UpdateSafetyPrefs", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",                   userId);
                    _db.AddParameter(cmd, "p_EmergVisibilityLkpId",     request.EmergVisibilityLkpId);
                    _db.AddParameter(cmd, "p_AutoShareDurLkpId",        request.AutoShareDurLkpId);
                    _db.AddParameter(cmd, "p_AllowLocDuringSos",        request.AllowLocDuringSos);
                    _db.AddParameter(cmd, "p_AllowLocDuringProj",       request.AllowLocDuringProj);
                    _db.AddParameter(cmd, "p_EmergencyContactName",     request.EmergencyContactName);
                    _db.AddParameter(cmd, "p_EmergencyContactPhone",    request.EmergencyContactPhone);
                    _db.AddParameter(cmd, "p_EmergencyContactRelation", request.EmergencyContactRelation);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateSafetyPrefsAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SaveInterestsAsync(int userId, SaveInterestsRequest request)
        {
            try
            {
                // SP expects JSON int array e.g. [1,2,3] — LookupValueIds from INTEREST_TYPE
                var idsJson = JsonSerializer.Serialize(request.InterestLkpIds);
                var result = await ExecuteWriteAsync("User_SaveInterests", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_InterestLkpIds", idsJson);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SaveInterestsAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UploadDocumentAsync(int userId, UploadDocumentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_UploadDocument", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",            userId);
                    _db.AddParameter(cmd, "p_DocumentTypeLkpId", request.DocumentTypeLkpId);
                    _db.AddParameter(cmd, "p_FileUrl",           request.FileUrl);
                    _db.AddParameter(cmd, "p_FileName",          request.FileName);
                    _db.AddParameter(cmd, "p_FileSizeKb",        request.FileSizeKb);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UploadDocumentAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<UserDocumentModel>>> GetDocumentsAsync(int userId)
        {
            try
            {
                var docs = await ExecuteReaderListAsync("User_GetDocuments", MapDocument,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<UserDocumentModel>>.Success(docs);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDocumentsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<UserDocumentModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> DeleteDocumentAsync(int userId, int userDocumentId)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_DeleteDocument", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserDocumentId", userDocumentId);
                    _db.AddParameter(cmd, "p_UserId",         userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeleteDocumentAsync failed UserId={UserId} DocId={DocId}", userId, userDocumentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        private static UserDocumentModel MapDocument(IDataReader r) => new()
        {
            UserDocumentId    = Convert.ToInt32(r["UserDocumentId"]),
            DocumentTypeLkpId = Convert.ToInt32(r["DocumentTypeLkpId"]),
            DocTypeCode       = r["DocTypeCode"]?.ToString() ?? string.Empty,
            DocTypeName       = r["DocTypeName"]?.ToString() ?? string.Empty,
            FileUrl           = r["FileUrl"]?.ToString()     ?? string.Empty,
            FileName          = r["FileName"]?.ToString()    ?? string.Empty,
            FileSizeKb        = r["FileSizeKb"] == DBNull.Value ? null : Convert.ToInt32(r["FileSizeKb"]),
            IsVerified        = r["IsVerified"]  != DBNull.Value && Convert.ToBoolean(r["IsVerified"]),
            UploadedAt        = r["UploadedAt"]  == DBNull.Value ? DateTime.MinValue : Convert.ToDateTime(r["UploadedAt"]),
        };

        public async Task<ApiResponse<List<UserSkillModel>>> GetSkillsAsync(int userId)
        {
            try
            {
                var skills = await ExecuteReaderListAsync("User_GetSkills", MapSkill,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<UserSkillModel>>.Success(skills);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSkillsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<UserSkillModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AddSkillAsync(int userId, AddSkillRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_AddSkill", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",    userId);
                    _db.AddParameter(cmd, "p_SkillName", request.SkillName);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddSkillAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RemoveSkillAsync(int userId, int userSkillId)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_RemoveSkill", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",      userId);
                    _db.AddParameter(cmd, "p_UserSkillId", userSkillId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RemoveSkillAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Safety Prefs ─────────────────────────────────────────────────────────

        public async Task<ApiResponse<UserSafetyPrefsModel>> GetSafetyPrefsAsync(int userId)
        {
            try
            {
                var row = await ExecuteGetAsync("User_GetSafetyPrefs", MapSafetyPrefs,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return row is null
                    ? ApiResponse<UserSafetyPrefsModel>.Failure("Safety preferences not found.", "NOT_FOUND")
                    : ApiResponse<UserSafetyPrefsModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSafetyPrefsAsync failed UserId={UserId}", userId);
                return ApiResponse<UserSafetyPrefsModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Interests ─────────────────────────────────────────────────────────────

        public async Task<ApiResponse<List<UserInterestModel>>> GetInterestsAsync(int userId)
        {
            try
            {
                var rows = await ExecuteListAsync("User_GetInterests",
                    r => new UserInterestModel
                    {
                        InterestLkpId = Col<int>(r,    "InterestLkpId"),
                        InterestName  = Col<string>(r, "InterestName")  ?? string.Empty,
                        InterestCode  = Col<string>(r, "InterestCode")  ?? string.Empty,
                    },
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<UserInterestModel>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetInterestsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<UserInterestModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── My Organisations ──────────────────────────────────────────────────────

        public async Task<ApiResponse<List<UserOrgModel>>> GetMyOrgsAsync(int userId)
        {
            try
            {
                var rows = await ExecuteListAsync("User_GetMyOrgs",
                    r => new UserOrgModel
                    {
                        OrgId            = Col<int>(r,      "OrgId"),
                        OrgName          = Col<string>(r,   "OrgName")          ?? string.Empty,
                        LogoUrl          = Col<string>(r,   "LogoUrl"),
                        OrgType          = Col<string>(r,   "OrgType"),
                        City             = Col<string>(r,   "City"),
                        State            = Col<string>(r,   "State"),
                        Role             = Col<string>(r,   "Role")             ?? string.Empty,
                        RoleCode         = Col<string>(r,   "RoleCode")         ?? string.Empty,
                        MemberStatusCode = Col<string>(r,   "MemberStatusCode") ?? string.Empty,
                        OrgStatusCode    = Col<string>(r,   "OrgStatusCode")    ?? string.Empty,
                        MemberCount      = Col<int>(r,      "MemberCount"),
                        JoinedAt         = Col<DateTime>(r, "JoinedAt"),
                    },
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<UserOrgModel>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMyOrgsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<UserOrgModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Badges ────────────────────────────────────────────────────────────────

        public async Task<ApiResponse<List<UserBadgeModel>>> GetBadgesAsync(int userId)
        {
            try
            {
                var rows = await ExecuteListAsync("User_GetBadges",
                    r => new UserBadgeModel
                    {
                        UserBadgeId = Col<int>(r,      "UserBadgeId"),
                        BadgeLkpId  = Col<int>(r,      "BadgeLkpId"),
                        BadgeName   = Col<string>(r,   "BadgeName")   ?? string.Empty,
                        BadgeCode   = Col<string>(r,   "BadgeCode")   ?? string.Empty,
                        OrgName     = Col<string>(r,   "OrgName"),
                        ProjectName = Col<string>(r,   "ProjectName"),
                        AwardedAt   = Col<DateTime>(r, "AwardedAt"),
                    },
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<UserBadgeModel>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetBadgesAsync failed UserId={UserId}", userId);
                return ApiResponse<List<UserBadgeModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Impact Dashboard ──────────────────────────────────────────────────────

        public async Task<ApiResponse<UserImpactModel>> GetImpactAsync(int userId)
        {
            try
            {
                var row = await ExecuteGetAsync("User_GetImpact", MapImpact,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return row is null
                    ? ApiResponse<UserImpactModel>.Failure("Impact data not found.", "NOT_FOUND")
                    : ApiResponse<UserImpactModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetImpactAsync failed UserId={UserId}", userId);
                return ApiResponse<UserImpactModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Mappers ──────────────────────────────────────────────────────────────

        private static UserProfileModel MapProfile(DataRow row) => new()
        {
            UserId            = Col<int>(row,      "UserId"),
            Mobile            = Col<string>(row,   "Mobile"),
            Email             = Col<string>(row,   "Email"),
            CountryCode       = Col<string>(row,   "CountryCode") ?? "+91",
            IsVerified        = Col<bool>(row,     "IsVerified"),
            FirstName         = Col<string>(row,   "FirstName"),
            LastName          = Col<string>(row,   "LastName"),
            Bio               = Col<string>(row,   "Bio"),
            GenderLkpId       = ColNullable<int>(row,    "GenderLkpId"),
            Gender            = Col<string>(row,   "Gender"),           // ValueName e.g. "Male"
            GenderCode        = Col<string>(row,   "GenderCode"),       // ValueCode e.g. "MALE"
            DateOfBirth       = ColNullable<DateTime>(row, "DateOfBirth"),
            ProfilePhoto      = Col<string>(row,   "ProfilePhoto"),
            Occupation        = Col<string>(row,   "Occupation"),
            Organisation      = Col<string>(row,   "Organisation"),
            VolunteerExp      = Col<string>(row,   "VolunteerExp"),
            EducationLkpId    = ColNullable<int>(row,    "EducationLkpId"),
            Education         = Col<string>(row,   "Education"),        // ValueName
            EducationCode     = Col<string>(row,   "EducationCode"),    // ValueCode
            FieldOfStudy      = Col<string>(row,   "FieldOfStudy"),
            WorkExpLkpId      = ColNullable<int>(row,    "WorkExpLkpId"),
            WorkExperience    = Col<string>(row,   "WorkExperience"),   // ValueName
            WorkExpCode       = Col<string>(row,   "WorkExpCode"),      // ValueCode
            AddressLine1      = Col<string>(row,   "AddressLine1"),
            AddressLine2      = Col<string>(row,   "AddressLine2"),
            Pincode           = Col<string>(row,   "Pincode"),
            City              = Col<string>(row,   "City"),
            State             = Col<string>(row,   "State"),
            Country           = Col<string>(row,   "Country"),
            ImpactScore       = Col<int>(row,      "ImpactScore"),
            ReliabilityPct    = Col<decimal>(row,  "ReliabilityPct"),
            MemberSince       = Col<DateTime>(row, "MemberSince"),      // u.CreatedAt aliased in SP
            UpdatedAt         = ColNullable<DateTime>(row, "UpdatedAt"),
            IsProfileComplete = Col<bool>(row,     "IsProfileComplete")
        };

        private static UserSkillModel MapSkill(IDataReader r) => new()
        {
            UserSkillId = Convert.ToInt32(r["UserSkillId"]),
            SkillName   = r["SkillName"]?.ToString() ?? string.Empty,
            AvgRating   = r["AvgRating"]  == DBNull.Value ? 0m : Convert.ToDecimal(r["AvgRating"]),
            RatingCount = r["RatingCount"] == DBNull.Value ? 0  : Convert.ToInt32(r["RatingCount"])
        };

        private static UserSafetyPrefsModel MapSafetyPrefs(DataRow row) => new()
        {
            EmergVisibilityLkpId     = ColNullable<int>(row,    "EmergVisibilityLkpId"),
            EmergVisibility          = Col<string>(row,         "EmergVisibility"),
            AutoShareDurLkpId        = ColNullable<int>(row,    "AutoShareDurLkpId"),
            AutoShareDuration        = Col<string>(row,         "AutoShareDuration"),
            AllowLocDuringSos        = Col<bool>(row,           "AllowLocDuringSos"),
            AllowLocDuringProj       = Col<bool>(row,           "AllowLocDuringProj"),
            EmergencyContactName     = Col<string>(row,         "EmergencyContactName"),
            EmergencyContactPhone    = Col<string>(row,         "EmergencyContactPhone"),
            EmergencyContactRelation = Col<string>(row,         "EmergencyContactRelation"),
        };

        private static UserImpactModel MapImpact(DataRow row) => new()
        {
            ImpactScore          = Col<int>(row,      "ImpactScore"),
            ReliabilityPct       = Col<decimal>(row,  "ReliabilityPct"),
            ProjectsCompleted    = Col<int>(row,      "ProjectsCompleted"),
            TotalHours           = Col<decimal>(row,  "TotalHours"),
            BadgeCount           = Col<int>(row,      "BadgeCount"),
            SkillCount           = Col<int>(row,      "SkillCount"),
            ProjectsApplied      = Col<int>(row,      "ProjectsApplied"),
            CertificateCount     = Col<int>(row,      "CertificateCount"),
            MemberSince          = Col<DateTime>(row, "MemberSince"),
            RankName             = Col<string>(row,   "RankName")  ?? "Newcomer",
            RankNumber           = Col<int>(row,      "RankNumber"),
            TotalRanked          = Col<int>(row,      "TotalRanked"),
            NgosJoined           = Col<int>(row,      "NgosJoined"),
            PendingApplications  = Col<int>(row,      "PendingApplications"),
            ApprovedApplications = Col<int>(row,      "ApprovedApplications"),
            FirstName            = Col<string>(row,   "FirstName"),
            LastName             = Col<string>(row,   "LastName"),
            ProfilePhoto         = Col<string>(row,   "ProfilePhoto"),
            Bio                  = Col<string>(row,   "Bio"),
        };
    }
}

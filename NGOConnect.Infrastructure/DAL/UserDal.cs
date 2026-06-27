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
                    cmd => { _db.AddParameter(cmd, "p_UserId", userId); _db.AddParameter(cmd, "p_RequestingUserId", 0); });
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
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_FirstName",       request.FirstName);
                    _db.AddParameter(cmd, "p_LastName",        request.LastName);
                    _db.AddParameter(cmd, "p_About",           request.About);
                    _db.AddParameter(cmd, "p_GenderLkpId",     request.GenderLkpId);
                    _db.AddParameter(cmd, "p_DateOfBirth",     request.DateOfBirth);
                    _db.AddParameter(cmd, "p_ProfilePhoto",    request.ProfilePhoto);
                    _db.AddParameter(cmd, "p_Occupation",      request.Occupation);
                    _db.AddParameter(cmd, "p_Organisation",    request.Organisation);
                    _db.AddParameter(cmd, "p_EducationLkpId",  request.EducationLkpId);
                    _db.AddParameter(cmd, "p_FieldOfStudy",    request.FieldOfStudy);
                    _db.AddParameter(cmd, "p_WorkExpLkpId",    request.WorkExpLkpId);
                    _db.AddParameter(cmd, "p_AddressLine1",    request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",    request.AddressLine2);
                    _db.AddParameter(cmd, "p_Pincode",         request.Pincode);
                    _db.AddParameter(cmd, "p_City",            request.City);
                    _db.AddParameter(cmd, "p_State",           request.State);
                    _db.AddParameter(cmd, "p_Country",         request.Country);
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
                    _db.AddParameter(cmd, "p_UserId",                    userId);
                    _db.AddParameter(cmd, "p_SosAlertTypeLkpId",         request.SosAlertTypeLkpId);
                    _db.AddParameter(cmd, "p_EmergencyContactName",      request.EmergencyContactName);
                    _db.AddParameter(cmd, "p_EmergencyContactPhone",     request.EmergencyContactPhone);
                    _db.AddParameter(cmd, "p_EmergencyContactRelation",  request.EmergencyContactRelation);
                    _db.AddParameter(cmd, "p_ShareLocationDuringSos",    request.ShareLocationDuringSos);
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
                var idsJson = JsonSerializer.Serialize(request.InterestLkpIds);
                var result = await ExecuteWriteAsync("User_SaveInterests", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_InterestLkpIds",  idsJson);
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
                    _db.AddParameter(cmd, "p_UserId",             userId);
                    _db.AddParameter(cmd, "p_DocumentTypeLkpId",  request.DocumentTypeLkpId);
                    _db.AddParameter(cmd, "p_DocumentUrl",        request.DocumentUrl);
                    _db.AddParameter(cmd, "p_ExpiryDate",         request.ExpiryDate);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UploadDocumentAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

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
                Log.Error(ex, "RemoveSkillAsync failed", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        private static UserProfileModel MapProfile(DataRow row) => new()
        {
            UserId             = Col<int>(row,      "UserId"),
            Mobile             = Col<string>(row,   "Mobile"),
            Email              = Col<string>(row,   "Email"),
            CountryCode        = Col<string>(row,   "CountryCode") ?? "+91",
            FirstName          = Col<string>(row,   "FirstName"),
            LastName           = Col<string>(row,   "LastName"),
            Bio                = Col<string>(row,   "Bio"),
            GenderValueCode    = Col<string>(row,   "GenderValueCode"),
            DateOfBirth        = ColNullable<DateTime>(row, "DateOfBirth"),
            ProfilePhoto       = Col<string>(row,   "ProfilePhoto"),
            Occupation         = Col<string>(row,   "Occupation"),
            Organisation       = Col<string>(row,   "Organisation"),
            EducationCode      = Col<string>(row,   "EducationCode"),
            FieldOfStudy       = Col<string>(row,   "FieldOfStudy"),
            WorkExpCode        = Col<string>(row,   "WorkExpCode"),
            AddressLine1       = Col<string>(row,   "AddressLine1"),
            AddressLine2       = Col<string>(row,   "AddressLine2"),
            Pincode            = Col<string>(row,   "Pincode"),
            City               = Col<string>(row,   "City"),
            State              = Col<string>(row,   "State"),
            Country            = Col<string>(row,   "Country"),
            ImpactScore        = Col<int>(row,      "ImpactScore"),
            ReliabilityPct     = Col<decimal>(row,  "ReliabilityPct"),
            CreatedAt          = Col<DateTime>(row, "CreatedAt"),
            UpdatedAt          = ColNullable<DateTime>(row, "UpdatedAt"),
            IsProfileComplete  = Col<bool>(row,     "IsProfileComplete")
        };

        private static UserSkillModel MapSkill(IDataReader r) => new()
        {
            UserSkillId = Convert.ToInt32(r["UserSkillId"]),
            SkillName   = r["SkillName"]?.ToString() ?? string.Empty,
            AvgRating   = r["AvgRating"]  == DBNull.Value ? 0m : Convert.ToDecimal(r["AvgRating"]),
            RatingCount = r["RatingCount"] == DBNull.Value ? 0  : Convert.ToInt32(r["RatingCount"])
        };
    }
}

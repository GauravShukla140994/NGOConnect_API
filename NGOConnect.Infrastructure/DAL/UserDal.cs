using System.Data;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// User DAL — Controller → IUserDal → UserDal → Stored Procedures → MySQL
    ///
    /// Inherits BaseDal for all SP execution patterns.
    /// 30/70 Rule:
    ///   GetProfile    → typed  (core entity, PII, C# code references fields)
    ///   GetPublicProfile → DynamicRow (display query, SP drives shape)
    ///   GetSkills     → typed  (referenced in C# — skill list)
    ///   UpdateProfile → write (ExecuteWriteAsync)
    /// </summary>
    public class UserDal : BaseDal, IUserDal
    {
        public UserDal(IDbProvider db) : base(db) { }

        // ── GET Own Profile (typed — core entity) ───────────────────────────────
        public async Task<ApiResponse<UserProfileModel>> GetProfileAsync(int userId)
        {
            try
            {
                var profile = await ExecuteGetAsync(
                    "User_GetProfile",
                    MapProfile,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));

                return profile is null
                    ? ApiResponse<UserProfileModel>.Failure("Profile not found.", "NOT_FOUND")
                    : ApiResponse<UserProfileModel>.Success(profile);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetProfileAsync failed. UserId={UserId}", userId);
                return ApiResponse<UserProfileModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── GET Public Profile (DynamicRow — display query) ─────────────────────
        public async Task<ApiResponse<DynamicRow>> GetPublicProfileAsync(int userId)
        {
            try
            {
                // DynamicRow: SP column OrgName → JSON key orgName, auto-camelCase, zero C# changes on SP update
                var row = await ExecuteDynamicGetAsync(
                    "User_GetPublicProfile",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));

                return row is null
                    ? ApiResponse<DynamicRow>.Failure("User not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPublicProfileAsync failed. UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── UPDATE Profile ──────────────────────────────────────────────────────
        public async Task<ApiResponse> UpdateProfileAsync(int userId, UpdateProfileRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_UpdateProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",      userId);
                    _db.AddParameter(cmd, "p_FirstName",   request.FirstName);
                    _db.AddParameter(cmd, "p_LastName",    request.LastName);
                    _db.AddParameter(cmd, "p_DisplayName", request.DisplayName);
                    _db.AddParameter(cmd, "p_About",       request.About);
                    _db.AddParameter(cmd, "p_GenderLkpId", request.GenderLkpId);
                    _db.AddParameter(cmd, "p_DateOfBirth", request.DateOfBirth);
                    _db.AddParameter(cmd, "p_City",        request.City);
                    _db.AddParameter(cmd, "p_State",       request.State);
                    _db.AddParameter(cmd, "p_Country",     request.Country);
                    _db.AddParameter(cmd, "p_LinkedInUrl", request.LinkedInUrl);
                    _db.AddParameter(cmd, "p_WebsiteUrl",  request.WebsiteUrl);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateProfileAsync failed. UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── GET Skills (DataReader — frequent call, typed) ──────────────────────
        public async Task<ApiResponse<List<UserSkillModel>>> GetSkillsAsync(int userId)
        {
            try
            {
                // DataReader: streams rows — 2-5x faster for frequently called endpoints
                var skills = await ExecuteReaderListAsync(
                    "User_GetSkills",
                    MapSkill,
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));

                return ApiResponse<List<UserSkillModel>>.Success(skills);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSkillsAsync failed. UserId={UserId}", userId);
                return ApiResponse<List<UserSkillModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── ADD Skill (upsert — updates proficiency if skill already exists) ────
        public async Task<ApiResponse> AddSkillAsync(int userId, AddSkillRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("User_AddSkill", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           userId);
                    _db.AddParameter(cmd, "p_SkillLkpId",       request.SkillLkpId);
                    _db.AddParameter(cmd, "p_ProficiencyLkpId", request.ProficiencyLkpId);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddSkillAsync failed. UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── REMOVE Skill ────────────────────────────────────────────────────────
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
                Log.Error(ex, "RemoveSkillAsync failed. UserId={UserId} UserSkillId={UserSkillId}",
                    userId, userSkillId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Mappers ─────────────────────────────────────────────────────────────

        /// <summary>Map DataRow to UserProfileModel using Col&lt;T&gt; safe helpers.</summary>
        private static UserProfileModel MapProfile(DataRow row) => new()
        {
            UserId            = Col<int>(row,      "UserId"),
            MobileNumber      = Col<string>(row,   "MobileNumber"),
            Email             = Col<string>(row,   "Email"),
            CountryCode       = Col<string>(row,   "CountryCode"),
            FirstName         = Col<string>(row,   "FirstName"),
            LastName          = Col<string>(row,   "LastName"),
            DisplayName       = Col<string>(row,   "DisplayName"),
            About             = Col<string>(row,   "About"),
            GenderValueCode   = Col<string>(row,   "GenderValueCode"),
            DateOfBirth       = ColNullable<DateTime>(row, "DateOfBirth"),
            ProfilePhotoUrl   = Col<string>(row,   "ProfilePhotoUrl"),
            City              = Col<string>(row,   "City"),
            State             = Col<string>(row,   "State"),
            Country           = Col<string>(row,   "Country"),
            LinkedInUrl       = Col<string>(row,   "LinkedInUrl"),
            WebsiteUrl        = Col<string>(row,   "WebsiteUrl"),
            CreatedAt         = Col<DateTime>(row, "CreatedAt"),
            UpdatedAt         = ColNullable<DateTime>(row, "UpdatedAt"),
            IsProfileComplete = Col<bool>(row,     "IsProfileComplete")
        };

        /// <summary>Map DataReader row to UserSkillModel (DataReader — no DataRow).</summary>
        private static UserSkillModel MapSkill(IDataReader r) => new()
        {
            UserSkillId      = Convert.ToInt32(r["UserSkillId"]),
            SkillLkpId       = Convert.ToInt32(r["SkillLkpId"]),
            SkillName        = r["SkillName"]?.ToString()       ?? string.Empty,
            ProficiencyLkpId = Convert.ToInt32(r["ProficiencyLkpId"]),
            ProficiencyName  = r["ProficiencyName"]?.ToString() ?? string.Empty
        };
    }
}

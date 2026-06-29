using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/[controller]")]
    [Produces("application/json")]
    public class UserController : ControllerBase
    {
        private readonly IUserDal _userDal;
        public UserController(IUserDal userDal) => _userDal = userDal;

        [HttpGet("profile")] [Authorize]
        public async Task<ApiResponse<UserProfileModel>> GetProfile()
            => await _userDal.GetProfileAsync(GetUserId());

        [HttpPut("profile")] [Authorize]
        public async Task<ApiResponse> UpdateProfile([FromBody] UpdateProfileRequest request)
            => await _userDal.UpdateProfileAsync(GetUserId(), request);

        [HttpGet("profile/{userId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetPublicProfile(int userId)
            => await _userDal.GetPublicProfileAsync(userId);

        [HttpGet("safety-prefs")] [Authorize]
        public async Task<ApiResponse<UserSafetyPrefsModel>> GetSafetyPrefs()
            => await _userDal.GetSafetyPrefsAsync(GetUserId());

        [HttpPut("safety-prefs")] [Authorize]
        public async Task<ApiResponse> UpdateSafetyPrefs([FromBody] UpdateSafetyPrefsRequest request)
            => await _userDal.UpdateSafetyPrefsAsync(GetUserId(), request);

        [HttpGet("interests")] [Authorize]
        public async Task<ApiResponse<List<UserInterestModel>>> GetInterests()
            => await _userDal.GetInterestsAsync(GetUserId());

        [HttpPost("interests")] [Authorize]
        public async Task<ApiResponse> SaveInterests([FromBody] SaveInterestsRequest request)
            => await _userDal.SaveInterestsAsync(GetUserId(), request);

        [HttpPost("documents")] [Authorize]
        public async Task<ApiResponse> UploadDocument([FromBody] UploadDocumentRequest request)
            => await _userDal.UploadDocumentAsync(GetUserId(), request);

        [HttpGet("skills")] [Authorize]
        public async Task<ApiResponse<List<UserSkillModel>>> GetSkills()
            => await _userDal.GetSkillsAsync(GetUserId());

        [HttpPost("skills")] [Authorize]
        public async Task<ApiResponse> AddSkill([FromBody] AddSkillRequest request)
            => await _userDal.AddSkillAsync(GetUserId(), request);

        [HttpDelete("skills/{userSkillId:int}")] [Authorize]
        public async Task<ApiResponse> RemoveSkill(int userSkillId)
            => await _userDal.RemoveSkillAsync(GetUserId(), userSkillId);

        // ── My Organisations (s-my-orgs screen) ──────────────────────────────────
        [HttpGet("orgs")] [Authorize]
        public async Task<ApiResponse<List<UserOrgModel>>> GetMyOrgs()
            => await _userDal.GetMyOrgsAsync(GetUserId());

        // ── Badges (s-impact screen) ──────────────────────────────────────────────
        [HttpGet("badges")] [Authorize]
        public async Task<ApiResponse<List<UserBadgeModel>>> GetBadges()
            => await _userDal.GetBadgesAsync(GetUserId());

        // ── Impact Dashboard (s-impact screen) ───────────────────────────────────
        [HttpGet("impact")] [Authorize]
        public async Task<ApiResponse<UserImpactModel>> GetImpact()
            => await _userDal.GetImpactAsync(GetUserId());

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

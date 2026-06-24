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

        // ── Own Profile ─────────────────────────────────────────────────────────

        /// <summary>
        /// Get own full profile (authenticated).
        /// Returns PII — mobile, email — only visible to the authenticated user.
        /// </summary>
        [HttpGet("profile")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<UserProfileModel>), 200)]
        public async Task<ApiResponse<UserProfileModel>> GetProfile()
            => await _userDal.GetProfileAsync(GetCurrentUserId());

        /// <summary>
        /// Update own profile (authenticated).
        /// All fields optional — only sends what changed (PATCH semantics).
        /// </summary>
        [HttpPut("profile")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse), 200)]
        public async Task<ApiResponse> UpdateProfile([FromBody] UpdateProfileRequest request)
            => await _userDal.UpdateProfileAsync(GetCurrentUserId(), request);

        // ── Public Profile ──────────────────────────────────────────────────────

        /// <summary>
        /// Get public profile of any user by UserId.
        /// Returns only publicly visible fields — no PII.
        /// Response shape is driven by SP (DynamicRow) — can evolve without code change.
        /// </summary>
        [HttpGet("profile/{userId:int}")]
        [ProducesResponseType(typeof(ApiResponse<DynamicRow>), 200)]
        public async Task<ApiResponse<DynamicRow>> GetPublicProfile(int userId)
            => await _userDal.GetPublicProfileAsync(userId);

        // ── Skills ──────────────────────────────────────────────────────────────

        /// <summary>
        /// Get own skills list (authenticated).
        /// </summary>
        [HttpGet("skills")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<List<UserSkillModel>>), 200)]
        public async Task<ApiResponse<List<UserSkillModel>>> GetSkills()
            => await _userDal.GetSkillsAsync(GetCurrentUserId());

        /// <summary>
        /// Add a skill to own profile (authenticated).
        /// If skill already exists, updates the proficiency level.
        /// SkillLkpId: lookup value from TypeCode = 'SKILL'
        /// ProficiencyLkpId: lookup value from TypeCode = 'SKILL_PROFICIENCY'
        /// </summary>
        [HttpPost("skills")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse), 200)]
        public async Task<ApiResponse> AddSkill([FromBody] AddSkillRequest request)
            => await _userDal.AddSkillAsync(GetCurrentUserId(), request);

        /// <summary>
        /// Remove a skill from own profile (authenticated).
        /// UserSkillId must belong to the authenticated user (enforced in SP).
        /// </summary>
        [HttpDelete("skills/{userSkillId:int}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse), 200)]
        public async Task<ApiResponse> RemoveSkill(int userSkillId)
            => await _userDal.RemoveSkillAsync(GetCurrentUserId(), userSkillId);

        // ── Helper ──────────────────────────────────────────────────────────────

        /// <summary>
        /// Extract UserId from JWT claims.
        /// JWT payload contains claim "uid" set during GenerateJwt in AuthDal.
        /// </summary>
        private int GetCurrentUserId()
        {
            var claim = User.FindFirst("uid")
                     ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1")]
    [Authorize]
    [Produces("application/json")]
    public class CertificateController : ControllerBase
    {
        private readonly ICertificateDal  _certificate;
        private readonly ISkillRatingDal  _skillRating;
        private readonly IBadgeDal        _badge;

        public CertificateController(
            ICertificateDal certificate,
            ISkillRatingDal skillRating,
            IBadgeDal       badge)
        {
            _certificate = certificate;
            _skillRating = skillRating;
            _badge       = badge;
        }

        [HttpGet("certificates")]
        public async Task<ApiResponse<List<DynamicRow>>> GetMyCertificates()
            => await _certificate.GetByUserAsync(GetUserId());

        [HttpGet("users/{userId:int}/certificates")]
        public async Task<ApiResponse<List<DynamicRow>>> GetUserCertificates(int userId)
            => await _certificate.GetByUserAsync(userId);

        /// <summary>Used by ripplehub.app/verify/{certCode} — no auth required.</summary>
        [HttpGet("certificates/{certCode}")]
        [AllowAnonymous]
        public async Task<ApiResponse<DynamicRow>> GetCertificate(string certCode)
            => await _certificate.GetDataAsync(certCode);

        /// <summary>Admin issues a certificate after a project is completed.</summary>
        [HttpPost("certificates/issue")]
        public async Task<ApiResponse<DynamicRow>> IssueCertificate([FromBody] IssueCertificateRequest request)
            => await _certificate.IssueAsync(GetUserId(), request);

        [HttpPost("skills/rate")]
        public async Task<ApiResponse> RateSkill([FromBody] AddSkillRatingRequest request)
            => await _skillRating.AddRatingAsync(GetUserId(), request);

        [HttpPost("badges/award")]
        public async Task<ApiResponse> AwardBadge([FromBody] AwardBadgeRequest request)
            => await _badge.AwardAsync(GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

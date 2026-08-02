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
        private readonly IUrlTokenService _tokens;

        public CertificateController(
            ICertificateDal certificate,
            ISkillRatingDal skillRating,
            IBadgeDal       badge,
            IUrlTokenService tokens)
        {
            _certificate = certificate;
            _skillRating = skillRating;
            _badge       = badge;
            _tokens      = tokens;
        }

        [HttpGet("certificates")]
        public async Task<ApiResponse<List<DynamicRow>>> GetMyCertificates()
            => await _certificate.GetByUserAsync(GetUserId());

        [HttpGet("users/{userId:int}/certificates")]
        public async Task<ApiResponse<List<DynamicRow>>> GetUserCertificates(int userId)
            => await _certificate.GetByUserAsync(userId);

        /// <summary>
        /// Auth-required lookup by the raw CertCode — used by the logged-in mobile app to
        /// view a volunteer's own certificate detail (CertificateModal.tsx). NOT public —
        /// CertCode is a sequential incrementing counter (CERT-2026-000001, 000002, ...),
        /// not a sparse/opaque identifier, so exposing this anonymously would let anyone
        /// enumerate every certificate on the platform (name, photo, org, hours) just by
        /// walking the number. Public verification goes through GetCertificateByToken below.
        /// </summary>
        [HttpGet("certificates/{certCode}")]
        public async Task<ApiResponse<DynamicRow>> GetCertificate(string certCode)
            => await _certificate.GetDataAsync(certCode);

        /// <summary>
        /// Used by ripplehub.app/verify/{token} — no auth required. `token` is an
        /// AES-256-GCM encrypted payload (IUrlTokenService, entityType "CERT") produced by
        /// CertificateDal.AttachVerifyLink, never a raw CertCode or CertificateId. A bad,
        /// tampered, or foreign-entity-type token returns NOT_FOUND — same "don't leak
        /// whether something exists" posture as the /ngo and /opportunity share tokens.
        /// </summary>
        [HttpGet("certificates/verify/{token}")]
        [AllowAnonymous]
        public async Task<ApiResponse<DynamicRow>> GetCertificateByToken(string token)
        {
            var decrypted = _tokens.Decrypt(token);
            if (decrypted is null || !string.Equals(decrypted.Value.EntityType, "CERT", StringComparison.OrdinalIgnoreCase))
                return ApiResponse<DynamicRow>.Failure("Certificate not found.", "NOT_FOUND");

            return await _certificate.GetDataByIdAsync(decrypted.Value.Id);
        }

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

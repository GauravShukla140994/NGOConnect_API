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
        private readonly ICertificateDal       _certificate;
        private readonly ISkillRatingDal       _skillRating;
        private readonly IBadgeDal             _badge;
        private readonly IUrlTokenService      _tokens;
        private readonly ICertificateHtmlService _htmlService;

        public CertificateController(
            ICertificateDal        certificate,
            ISkillRatingDal        skillRating,
            IBadgeDal              badge,
            IUrlTokenService       tokens,
            ICertificateHtmlService htmlService)
        {
            _certificate = certificate;
            _skillRating = skillRating;
            _badge       = badge;
            _tokens      = tokens;
            _htmlService = htmlService;
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

        /// <summary>
        /// Returns the fully-rendered certificate HTML for the mobile app WebView.
        /// Auth-required — same enumeration-attack reasons as GetCertificate above.
        /// Mobile replaces its local buildCertHtml() with a call to this endpoint.
        /// </summary>
        [HttpGet("certificates/{certCode}/html")]
        public async Task<ApiResponse<string>> GetCertificateHtml(string certCode)
        {
            var res = await _certificate.GetDataAsync(certCode);
            if (res.IsSuccess == 0 || res.Data == null)
                return ApiResponse<string>.Failure(res.Message, res.ErrorCode);

            var row = res.Data;
            if (row.Get<int>("isDeleted") == 1)
                return ApiResponse<string>.Failure("This certificate has been revoked.", "CERT_REVOKED");

            return ApiResponse<string>.Success(_htmlService.Render(row));
        }

        /// <summary>
        /// Returns the fully-rendered certificate HTML for the website verify page.
        /// AllowAnonymous — token is AES-256-GCM encrypted, same as GetCertificateByToken.
        /// Website replaces its local template file with a call to this endpoint and renders
        /// the returned HTML via dangerouslySetInnerHTML / srcdoc.
        /// </summary>
        [HttpGet("certificates/verify/{token}/html")]
        [AllowAnonymous]
        public async Task<ApiResponse<string>> GetCertificateHtmlByToken(string token)
        {
            var decrypted = _tokens.Decrypt(token);
            if (decrypted is null || !string.Equals(decrypted.Value.EntityType, "CERT", StringComparison.OrdinalIgnoreCase))
                return ApiResponse<string>.Failure("Certificate not found.", "NOT_FOUND");

            var res = await _certificate.GetDataByIdAsync(decrypted.Value.Id);
            if (res.IsSuccess == 0 || res.Data == null)
                return ApiResponse<string>.Failure(res.Message, res.ErrorCode);

            var row = res.Data;
            if (row.Get<int>("isDeleted") == 1)
                return ApiResponse<string>.Failure("This certificate has been revoked.", "CERT_REVOKED");

            return ApiResponse<string>.Success(_htmlService.Render(row));
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

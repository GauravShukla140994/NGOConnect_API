using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// No-auth public endpoints used by the website and mobile deep-link resolver.
    ///
    /// All routes accept an encrypted token produced by ShareController / IUrlTokenService.
    /// Raw numeric IDs are never accepted here — the token is the only entry point.
    ///
    /// Endpoints:
    ///   GET /api/v1/public/resolve/{token}        → entity type + ID (mobile deep-link helper)
    ///   GET /api/v1/public/org/{token}            → full NGO public profile (website)
    ///   GET /api/v1/public/opportunity/{token}    → full project / opportunity details (website)
    /// </summary>
    [ApiController]
    [Route("api/v1/public")]
    [Produces("application/json")]
    public class PublicController : ControllerBase
    {
        private readonly IUrlTokenService _tokens;
        private readonly IOrgDal          _org;
        private readonly IProjectDal      _project;

        public PublicController(IUrlTokenService tokens, IOrgDal org, IProjectDal project)
        {
            _tokens  = tokens;
            _org     = org;
            _project = project;
        }

        // ── GET /api/v1/public/resolve/{token} ──────────────────────────────────
        /// <summary>
        /// Decrypts a share token and returns the entity type + ID.
        /// Used by the mobile app when a deep link arrives — the app resolves the token,
        /// then navigates to the correct screen using its normal authenticated API.
        /// No entity data is returned; this endpoint is intentionally lightweight.
        /// </summary>
        [HttpGet("resolve/{token}")]
        public ActionResult<ApiResponse<object>> Resolve(string token)
        {
            var result = _tokens.Decrypt(token);

            if (result is null)
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "Invalid or expired share link.",
                    ErrorCode = "INVALID_SHARE_TOKEN",
                });

            return Ok(new ApiResponse<object>
            {
                IsSuccess = 1,
                Message   = "Token resolved.",
                Data      = new { entityType = result.Value.EntityType, entityId = result.Value.Id },
            });
        }

        // ── GET /api/v1/public/org/{token} ──────────────────────────────────────
        /// <summary>
        /// Decrypts the token, validates it is an ORG token, then returns the NGO's
        /// public profile via the same SP used by the authenticated app.
        /// Intended for the RippleHub website's /ngo/{token} page.
        /// </summary>
        [HttpGet("org/{token}")]
        public async Task<ActionResult<ApiResponse<object>>> GetOrgPreview(string token)
        {
            var resolved = _tokens.Decrypt(token);

            if (resolved is null)
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "Invalid or expired share link.",
                    ErrorCode = "INVALID_SHARE_TOKEN",
                });

            if (!string.Equals(resolved.Value.EntityType, "ORG", StringComparison.OrdinalIgnoreCase))
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "This link does not point to an organisation.",
                    ErrorCode = "WRONG_ENTITY_TYPE",
                });

            var orgResult = await _org.GetPublicPreviewAsync(resolved.Value.Id);

            // Augment response with the resolved orgId so the website/app doesn't need to call /resolve separately
            if (orgResult.IsSuccess == 1)
                return Ok(new ApiResponse<object>
                {
                    IsSuccess = 1,
                    Message   = orgResult.Message,
                    Data      = new { orgId = resolved.Value.Id, profile = orgResult.Data },
                });

            return Ok(orgResult);
        }

        // ── GET /api/v1/public/opportunity/{token} ───────────────────────────────
        /// <summary>
        /// Decrypts the token, validates it is an OPP token, then returns the
        /// project/opportunity details for the RippleHub website's /opportunity/{token} page.
        /// Uses GetByIdAsync with userId=0 (unauthenticated — SP returns public fields only).
        /// </summary>
        [HttpGet("opportunity/{token}")]
        public async Task<ActionResult<ApiResponse<object>>> GetOpportunityPreview(string token)
        {
            var resolved = _tokens.Decrypt(token);

            if (resolved is null)
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "Invalid or expired share link.",
                    ErrorCode = "INVALID_SHARE_TOKEN",
                });

            if (!string.Equals(resolved.Value.EntityType, "OPP", StringComparison.OrdinalIgnoreCase))
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "This link does not point to a volunteer opportunity.",
                    ErrorCode = "WRONG_ENTITY_TYPE",
                });

            // userId = 0 → SP returns public-facing fields only (no application status, etc.)
            var projectResult = await _project.GetByIdAsync(resolved.Value.Id, userId: 0);

            if (projectResult.IsSuccess == 1)
                return Ok(new ApiResponse<object>
                {
                    IsSuccess = 1,
                    Message   = projectResult.Message,
                    Data      = new { projectId = resolved.Value.Id, project = projectResult.Data },
                });

            return Ok(projectResult);
        }
    }
}

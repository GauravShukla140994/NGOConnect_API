using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Generates encrypted share-link tokens for public entities.
    /// Requires authentication — only logged-in users can create share links.
    ///
    /// Token encodes: EntityType + EntityId using AES-256-GCM (IUrlTokenService).
    /// The resulting URL is safe to share publicly — no raw numeric IDs exposed.
    ///
    /// Entity types:
    ///   ORG  — Organisation profile   → https://ripplehub.app/organisation/{token}
    ///   OPP  — Volunteer opportunity   → https://ripplehub.app/opportunity/{token}
    /// </summary>
    [ApiController]
    [Route("api/v1/share")]
    [Produces("application/json")]
    [Authorize]
    public class ShareController : ControllerBase
    {
        private static readonly HashSet<string> ValidTypes =
            new(StringComparer.OrdinalIgnoreCase) { "ORG", "OPP" };

        private static readonly Dictionary<string, string> TypeToPath = new(StringComparer.OrdinalIgnoreCase)
        {
            ["ORG"] = "organisation",
            ["OPP"] = "opportunity",
        };

        private const string BaseUrl = "https://ripplehub.app";

        private readonly IUrlTokenService _tokens;

        public ShareController(IUrlTokenService tokens) => _tokens = tokens;

        // ── GET /api/v1/share/token?type=ORG&id=55 ──────────────────────────────
        /// <summary>
        /// Returns an encrypted token + full shareable URL for an entity.
        /// </summary>
        [HttpGet("token")]
        public ActionResult<ApiResponse<object>> GetToken(
            [FromQuery] string type,
            [FromQuery] int    id)
        {
            if (string.IsNullOrWhiteSpace(type) || !ValidTypes.Contains(type))
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = $"Invalid entity type '{type}'. Accepted: {string.Join(", ", ValidTypes)}.",
                    ErrorCode = "INVALID_ENTITY_TYPE",
                });

            if (id <= 0)
                return BadRequest(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = "Entity ID must be a positive integer.",
                    ErrorCode = "INVALID_ID",
                });

            var upperType = type.ToUpperInvariant();
            var token     = _tokens.Encrypt(upperType, id);
            var path      = TypeToPath[upperType];
            var url       = $"{BaseUrl}/{path}/{token}";

            return Ok(new ApiResponse<object>
            {
                IsSuccess = 1,
                Message   = "Share token generated.",
                Data      = new { token, url, entityType = upperType, entityId = id },
            });
        }
    }
}

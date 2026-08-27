using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// No-auth public endpoints used by the website and mobile deep-link resolver.
    ///
    /// Most routes accept an encrypted token produced by ShareController / IUrlTokenService.
    /// Raw numeric IDs are never accepted here — the token is the only entry point.
    ///
    /// Endpoints:
    ///   GET /api/v1/public/resolve/{token}        → entity type + ID (mobile deep-link helper)
    ///   GET /api/v1/public/org/{token}            → thin NGO preview card (website)
    ///   GET /api/v1/public/org/{token}/full       → rich NGO public profile: about/mission/
    ///                                                stats/verification + review aggregate +
    ///                                                first page of projects (website /organisation page)
    ///   GET /api/v1/public/org/{token}/projects   → paginated ACTIVE/UPCOMING/COMPLETED projects
    ///   GET /api/v1/public/org/{token}/reviews    → paginated reviews for the same org token
    ///   GET /api/v1/public/opportunity/{token}    → full project / opportunity details (website)
    ///   GET /api/v1/public/global-stats           → aggregate platform counts (website Global exploration section)
    /// </summary>
    [ApiController]
    [Route("api/v1/public")]
    [Produces("application/json")]
    public class PublicController : ControllerBase
    {
        private readonly IUrlTokenService _tokens;
        private readonly IOrgDal          _org;
        private readonly IProjectDal      _project;
        private readonly IPublicStatsDal  _stats;
        private readonly IOrgReviewDal    _reviews;

        public PublicController(
            IUrlTokenService tokens, IOrgDal org, IProjectDal project,
            IPublicStatsDal stats, IOrgReviewDal reviews)
        {
            _tokens  = tokens;
            _org     = org;
            _project = project;
            _stats   = stats;
            _reviews = reviews;
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
        /// Intended for the RippleHub website's /organisation/{token} page.
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

        // ── GET /api/v1/public/org/{token}/full ──────────────────────────────────
        /// <summary>
        /// Rich public organisation profile for the RippleHub website's /organisation/{token}
        /// page: about/mission/vision/stats/verification (Org_GetPublicProfile),
        /// review rating aggregate, and the first page of active/completed projects.
        /// Use GET /public/org/{token}/reviews separately for paginated review scrolling.
        /// </summary>
        [HttpGet("org/{token}/full")]
        public async Task<ActionResult<ApiResponse<object>>> GetOrgFullProfile(string token)
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

            var orgId = resolved.Value.Id;

            var profileResult = await _org.GetPublicProfileAsync(orgId);
            if (profileResult.IsSuccess != 1)
                return Ok(profileResult); // NOT_FOUND / ORG_UNAVAILABLE — let the page branch on ErrorCode

            // Review aggregate + a light first page of projects — best-effort, a
            // failure here shouldn't take down the whole profile page.
            var aggregateTask = _reviews.GetAggregateAsync(orgId);
            // NOTE: Project_List's built-in "public browse" whitelist (ACTIVE/UPCOMING
            // only, IsPublic=1) is SKIPPED whenever p_OrgId is supplied — that branch is
            // meant for an org's own admin viewing everything, including DRAFT/CANCELLED/
            // private projects. Since this endpoint is anonymous, we filter the results
            // ourselves below rather than touching that shared SP.
            var projectsTask = _project.ListAsync(pageNumber: 1, pageSize: 20, orgId: orgId, userId: 0);
            await Task.WhenAll(aggregateTask, projectsTask);

            List<DynamicRow>? publicProjects = null;
            if (projectsTask.Result.IsSuccess == 1)
            {
                var allowedStatus = new HashSet<string> { "ACTIVE", "UPCOMING", "COMPLETED" };
                publicProjects = projectsTask.Result.Data.Items
                    .Where(p => allowedStatus.Contains(p.Get<string>("statusCode") ?? string.Empty)
                             && p.Get<int?>("isPublic") != 0)
                    .Take(6)
                    .ToList();
                // projectToken lets the website's "Expand" action call GET /public/opportunity/{token}
                // for the full project detail without exposing the raw numeric ProjectId.
                foreach (var p in publicProjects)
                    p["projectToken"] = _tokens.Encrypt("OPP", p.Get<int>("projectId"));
            }

            return Ok(new ApiResponse<object>
            {
                IsSuccess = 1,
                Message   = profileResult.Message,
                Data      = new
                {
                    orgId,
                    profile  = profileResult.Data,
                    ratings  = aggregateTask.Result.IsSuccess == 1 ? aggregateTask.Result.Data : null,
                    projects = publicProjects,
                },
            });
        }

        // ── GET /api/v1/public/org/{token}/projects ──────────────────────────────
        /// <summary>
        /// Paginated ACTIVE/UPCOMING/COMPLETED public projects for the org behind this
        /// token — separate from /full so the website's Projects section can "Load more"
        /// beyond the first-page preview embedded in /full, mirroring the /reviews pattern.
        /// Same public-safe filtering as /full (see note there): Project_List's IsPublic/
        /// status whitelist is skipped when p_OrgId is supplied, so we filter here instead
        /// of touching that shared SP. pageSize is capped since this is unauthenticated.
        /// </summary>
        [HttpGet("org/{token}/projects")]
        public async Task<ActionResult<ApiResponse<object>>> GetOrgProjects(
            string token, [FromQuery] int pageNumber = 1, [FromQuery] int pageSize = 6)
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

            pageNumber = Math.Max(pageNumber, 1);
            pageSize   = Math.Clamp(pageSize, 1, 24);

            // Pull a generous single page from Project_List and filter/paginate here in
            // C# — same approach as /full, just with real Skip/Take instead of Take(6).
            // Fine for the realistic scale of a single NGO's project list; if an org ever
            // has hundreds of projects, this should move server-side into the SP.
            var projectsResult = await _project.ListAsync(pageNumber: 1, pageSize: 200, orgId: resolved.Value.Id, userId: 0);
            if (projectsResult.IsSuccess != 1)
                return Ok(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = projectsResult.Message,
                    ErrorCode = projectsResult.ErrorCode,
                });

            var allowedStatus = new HashSet<string> { "ACTIVE", "UPCOMING", "COMPLETED" };
            var filtered = projectsResult.Data.Items
                .Where(p => allowedStatus.Contains(p.Get<string>("statusCode") ?? string.Empty)
                         && p.Get<int?>("isPublic") != 0)
                .ToList();

            var pageItems = filtered
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .ToList();
            foreach (var p in pageItems)
                p["projectToken"] = _tokens.Encrypt("OPP", p.Get<int>("projectId"));

            return Ok(new ApiResponse<object>
            {
                IsSuccess = 1,
                Message   = "Success",
                Data      = new PagedResult<DynamicRow>
                {
                    Items      = pageItems,
                    TotalCount = filtered.Count,
                    PageNumber = pageNumber,
                    PageSize   = pageSize,
                },
            });
        }

        // ── GET /api/v1/public/org/{token}/reviews ───────────────────────────────
        /// <summary>
        /// Paginated, latest-approved reviews for the org behind this token —
        /// separate from /full so the website can infinite-scroll without
        /// re-fetching the whole profile. sort: RECENT | HELPFUL | HIGHEST | LOWEST.
        /// </summary>
        [HttpGet("org/{token}/reviews")]
        public async Task<ActionResult<ApiResponse<object>>> GetOrgReviews(
            string token, [FromQuery] string sort = "RECENT",
            [FromQuery] int pageNumber = 1, [FromQuery] int pageSize = 20)
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

            // pageSize capped — this is an unauthenticated endpoint, no reason to let
            // a caller request an unbounded page.
            pageSize = Math.Clamp(pageSize, 1, 50);

            var result = await _reviews.GetListAsync(resolved.Value.Id, currentUserId: 0, sort, pageNumber, pageSize);
            return Ok(result);
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

        // ── GET /api/v1/public/global-stats ──────────────────────────────────────
        /// <summary>
        /// Aggregate, non-identifying platform counts for the website's "Global
        /// exploration" section. No auth, no parameters, cached server-side —
        /// see PublicStatsDal for the caching/security rationale.
        /// </summary>
        [HttpGet("global-stats")]
        public async Task<ApiResponse<DynamicRow>> GetGlobalStats()
            => await _stats.GetGlobalStatsAsync();
    }
}

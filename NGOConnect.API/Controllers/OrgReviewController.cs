using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.OrgReview;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// NGO Reviews — Google/Amazon-style public review system.
    ///
    /// Route convention: /api/v1/orgs/{orgId}/reviews/...
    ///
    /// Auth rules:
    ///   GET  list + aggregate — optional auth (unauthenticated users see reviews,
    ///        authenticated users additionally see their own helpful-vote state).
    ///   POST add              — required (any logged-in user, one review per NGO).
    ///   DELETE own review     — required (author only, enforced in SP).
    ///   POST helpful          — required (any logged-in user).
    ///   POST response         — required (NGO admin only, enforced in SP via OrgMembers).
    ///   POST report           — required (any logged-in user).
    /// </summary>
    [ApiController]
    [Route("api/v1/orgs/{orgId:int}/reviews")]
    [Produces("application/json")]
    public class OrgReviewController : ControllerBase
    {
        private readonly IOrgReviewDal _reviews;

        public OrgReviewController(IOrgReviewDal reviews) => _reviews = reviews;

        // ── GET /api/v1/orgs/{orgId}/reviews ─────────────────────────────────
        /// <summary>
        /// Paged list of approved reviews for the NGO.
        /// Optional auth: when authenticated, returns current user's helpful-vote state.
        /// sort: RECENT | HELPFUL | HIGHEST | LOWEST  (default: RECENT)
        /// </summary>
        [HttpGet]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetList(
            int orgId,
            [FromQuery] string sort       = "RECENT",
            [FromQuery] int    pageNumber = 1,
            [FromQuery] int    pageSize   = 10)
        {
            var currentUserId = GetOptionalUserId();
            return await _reviews.GetListAsync(orgId, currentUserId, sort, pageNumber, pageSize);
        }

        // ── GET /api/v1/orgs/{orgId}/reviews/aggregate ────────────────────────
        /// <summary>
        /// Aggregate rating summary: AvgRating, TotalReviews, Star5Pct … Star1Pct.
        /// Used to render the histogram block at the top of the Reviews tab.
        /// </summary>
        [HttpGet("aggregate")]
        public async Task<ApiResponse<DynamicRow>> GetAggregate(int orgId)
            => await _reviews.GetAggregateAsync(orgId);

        // ── POST /api/v1/orgs/{orgId}/reviews ────────────────────────────────
        /// <summary>
        /// Submit a new review. One review per user per NGO (enforced by DB unique key + SP).
        /// Media must be pre-uploaded to blob storage; pass back the URLs in MediaItems.
        /// </summary>
        [HttpPost]
        [Authorize]
        public async Task<ApiResponse> Add(int orgId, [FromBody] AddReviewRequest request)
        {
            if (!ModelState.IsValid)
                return ApiResponse.Fail("Invalid request.", "VALIDATION_ERROR");

            return await _reviews.AddAsync(GetUserId(), orgId, request);
        }

        // ── DELETE /api/v1/orgs/{orgId}/reviews/{reviewId} ───────────────────
        /// <summary>
        /// Soft-delete the caller's own review. SP validates ownership.
        /// Recalculates AvgRating + RatingCount on Organisations.
        /// </summary>
        [HttpDelete("{reviewId:int}")]
        [Authorize]
        public async Task<ApiResponse> Delete(int orgId, int reviewId)
            => await _reviews.DeleteAsync(GetUserId(), reviewId);

        // ── POST /api/v1/orgs/{orgId}/reviews/{reviewId}/helpful ─────────────
        /// <summary>
        /// Toggle a helpful / not-helpful vote on a review.
        /// Sending the same IsHelpful value a second time removes the vote.
        /// </summary>
        [HttpPost("{reviewId:int}/helpful")]
        [Authorize]
        public async Task<ApiResponse> MarkHelpful(
            int orgId, int reviewId, [FromBody] MarkHelpfulRequest request)
        {
            if (!ModelState.IsValid)
                return ApiResponse.Fail("Invalid request.", "VALIDATION_ERROR");

            return await _reviews.MarkHelpfulAsync(GetUserId(), reviewId, request.IsHelpful);
        }

        // ── POST /api/v1/orgs/{orgId}/reviews/{reviewId}/response ────────────
        /// <summary>
        /// NGO admin posts (or updates) the official response to a review.
        /// SP validates admin role via OrgMembers. Only one response per review.
        /// </summary>
        [HttpPost("{reviewId:int}/response")]
        [Authorize]
        public async Task<ApiResponse> AddResponse(
            int orgId, int reviewId, [FromBody] AddReviewResponseRequest request)
        {
            if (!ModelState.IsValid)
                return ApiResponse.Fail("Invalid request.", "VALIDATION_ERROR");

            return await _reviews.AddResponseAsync(GetUserId(), orgId, reviewId, request.ResponseText);
        }

        // ── POST /api/v1/orgs/{orgId}/reviews/{reviewId}/report ──────────────
        /// <summary>
        /// Flag a review for moderation. MVP: returns friendly confirmation only.
        /// </summary>
        [HttpPost("{reviewId:int}/report")]
        [Authorize]
        public async Task<ApiResponse> Report(int orgId, int reviewId)
            => await _reviews.ReportAsync(GetUserId(), reviewId);

        // ── Helpers ───────────────────────────────────────────────────────────

        private int GetUserId()
            => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

        /// <summary>
        /// Returns 0 when the caller is not authenticated (anonymous browse).
        /// SP handles 0 safely — no helpful-vote row returned for userId=0.
        /// </summary>
        private int GetOptionalUserId()
        {
            var claim = User.FindFirstValue(ClaimTypes.NameIdentifier);
            return claim != null ? int.Parse(claim) : 0;
        }
    }
}

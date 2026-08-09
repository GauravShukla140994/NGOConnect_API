using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Feed;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/feed")]
    [Produces("application/json")]
    public class FeedController : ControllerBase
    {
        private readonly IFeedDal _feed;
        public FeedController(IFeedDal feed) => _feed = feed;

        /// <summary>
        /// Phase 1 personalised feed — multi-source, scored, diversity-filtered.
        /// Cursor-based pagination: pass cursorPostId + cursorScore from the previous
        /// response's NextCursorPostId / NextCursorScore for subsequent pages.
        /// First page: omit both cursor params (or pass null).
        /// </summary>
        [HttpGet("personalized")] [Authorize]
        public async Task<ApiResponse<FeedPageResult>> GetPersonalized(
            [FromQuery] int?     cursorPostId = null,
            [FromQuery] decimal? cursorScore  = null,
            [FromQuery] int      pageSize     = 20)
            => await _feed.GetPersonalizedAsync(GetUserId(), cursorPostId, cursorScore, pageSize);

        /// <summary>Save a post to the user's saved collection.</summary>
        [HttpPost("post/{postId:int}/save")] [Authorize]
        public async Task<ApiResponse> SavePost(int postId)
            => await _feed.SavePostAsync(GetUserId(), postId);

        /// <summary>Remove a post from the user's saved collection.</summary>
        [HttpDelete("post/{postId:int}/save")] [Authorize]
        public async Task<ApiResponse> UnsavePost(int postId)
            => await _feed.UnsavePostAsync(GetUserId(), postId);

        /// <summary>Get the current user's saved posts, most-recently-saved first.</summary>
        [HttpGet("saved")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetSaved(
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 30)
            => await _feed.GetSavedPostsAsync(GetUserId(), pageNumber, pageSize);

        /// <summary>
        /// Record a feed interaction for analytics (impression, view, click, etc.).
        /// Fire-and-forget from the mobile client; errors are logged but not surfaced.
        /// InteractionType: IMPRESSION | VIEW | LIKE | COMMENT | SHARE | SAVE
        ///                  VOLUNTEER_CLICK | DONATION_CLICK | NGO_VISIT | HIDE | REPORT
        /// </summary>
        [HttpPost("interaction")] [Authorize]
        public async Task<ApiResponse> TrackInteraction([FromBody] TrackInteractionRequest request)
            => await _feed.TrackInteractionAsync(
                GetUserId(),
                request.PostId,
                request.InteractionType,
                request.DurationMs);

        /// <summary>
        /// Bulk-mark a batch of posts as viewed by the current user.
        /// Called by the mobile client every ~10 s to flush its seen-post buffer.
        /// Posts are excluded from the personalised feed for the configured seen-expiry window (default 30 days).
        /// </summary>
        [HttpPost("viewed")] [Authorize]
        public async Task<ApiResponse> MarkViewed([FromBody] MarkViewedRequest req)
            => await _feed.BulkMarkViewedAsync(GetUserId(), req.PostIds);

        // ── Helper ────────────────────────────────────────────────────────────
        private int GetUserId()
        {
            var claim = User.FindFirst(ClaimTypes.NameIdentifier)
                     ?? User.FindFirst("sub")
                     ?? User.FindFirst("userId");
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }

    public class TrackInteractionRequest
    {
        public int    PostId          { get; set; }
        public string InteractionType { get; set; } = "";
        public int?   DurationMs      { get; set; }
    }

    public class MarkViewedRequest
    {
        /// <summary>List of PostIds the user has scrolled past (viewport-visible for ≥1 s).</summary>
        public List<int> PostIds { get; set; } = [];
    }
}

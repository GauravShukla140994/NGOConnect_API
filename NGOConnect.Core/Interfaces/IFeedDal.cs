using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Feed;

namespace NGOConnect.Core.Interfaces
{
    public interface IFeedDal
    {
        /// <summary>
        /// Returns a personalised, scored, diversity-filtered feed page.
        /// Pass null cursors for the first page; use NextCursorPostId + NextCursorScore for subsequent pages.
        /// </summary>
        Task<ApiResponse<FeedPageResult>> GetPersonalizedAsync(
            int      userId,
            int?     cursorPostId,
            decimal? cursorScore,
            int      pageSize);

        Task<ApiResponse> SavePostAsync(int userId, int postId);
        Task<ApiResponse> UnsavePostAsync(int userId, int postId);
        Task<ApiResponse> TrackInteractionAsync(int userId, int postId, string interactionType, int? durationMs);

        /// <summary>
        /// Bulk-marks a list of posts as viewed by the user.
        /// Called when the mobile app flushes its seen-post buffer (~every 10 s).
        /// Inserts VIEW rows into FeedInteractions; the feed SP excludes these posts
        /// until the seen-expiry window (default 30 days) elapses.
        /// </summary>
        Task<ApiResponse> BulkMarkViewedAsync(int userId, List<int> postIds);

        /// <summary>
        /// Returns the paginated list of posts the user has saved, most-recently-saved first.
        /// </summary>
        Task<ApiResponse<PagedResult<DynamicRow>>> GetSavedPostsAsync(int userId, int pageNumber, int pageSize);
    }
}

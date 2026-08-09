using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.OrgReview;

namespace NGOConnect.Core.Interfaces
{
    public interface IOrgReviewDal
    {
        /// <summary>Submit a new review for an NGO. One review per user per NGO.</summary>
        Task<ApiResponse> AddAsync(int userId, int orgId, AddReviewRequest request);

        /// <summary>
        /// Paged list of approved reviews for an NGO.
        /// Includes author info, media, NGO response, and current user's helpful vote state.
        /// </summary>
        Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(
            int orgId, int currentUserId, string sort, int pageNumber, int pageSize);

        /// <summary>
        /// Aggregate rating data for the Reviews tab header:
        /// AvgRating, TotalReviews, Star5Pct … Star1Pct.
        /// </summary>
        Task<ApiResponse<DynamicRow>> GetAggregateAsync(int orgId);

        /// <summary>
        /// Toggle a helpful / not-helpful vote on a review.
        /// Sending the same value twice removes the vote.
        /// </summary>
        Task<ApiResponse> MarkHelpfulAsync(int userId, int reviewId, bool isHelpful);

        /// <summary>Soft-delete the caller's own review. Recalculates org aggregate.</summary>
        Task<ApiResponse> DeleteAsync(int userId, int reviewId);

        /// <summary>
        /// NGO admin posts (or updates) the official response to a review.
        /// Validates admin role via OrgMembers before inserting.
        /// </summary>
        Task<ApiResponse> AddResponseAsync(int adminUserId, int orgId, int reviewId, string responseText);

        /// <summary>Report a review for moderation. MVP: no-op persist, returns friendly message.</summary>
        Task<ApiResponse> ReportAsync(int userId, int reviewId);
    }
}

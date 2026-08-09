using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.OrgReview;
using Serilog;
using System.Text.Json;

namespace NGOConnect.Infrastructure.DAL
{
    public class OrgReviewDal : BaseDal, IOrgReviewDal
    {
        public OrgReviewDal(IDbProvider db) : base(db) { }

        // ── AddAsync ─────────────────────────────────────────────────────────
        public async Task<ApiResponse> AddAsync(int userId, int orgId, AddReviewRequest request)
        {
            try
            {
                // Validate media count constraints
                var images = request.MediaItems.Count(m => m.Type == "IMAGE");
                var videos = request.MediaItems.Count(m => m.Type == "VIDEO");
                if (images > 5)
                    return ApiResponse.Fail("You can attach a maximum of 5 photos.", "MEDIA_LIMIT");
                if (videos > 1)
                    return ApiResponse.Fail("You can attach a maximum of 1 video.", "MEDIA_LIMIT");

                // Serialise media list as JSON for the SP
                string? mediaJson = request.MediaItems.Count > 0
                    ? JsonSerializer.Serialize(request.MediaItems.Select(m => new { url = m.Url, type = m.Type }))
                    : null;

                var result = await ExecuteWriteAsync("OrgReview_Add", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_OrgId",         orgId);
                    _db.AddParameter(cmd, "p_OverallRating", request.OverallRating);
                    _db.AddParameter(cmd, "p_ReviewText",    request.ReviewText);
                    _db.AddParameter(cmd, "p_ReviewerType",  request.ReviewerType);
                    _db.AddParameter(cmd, "p_MediaUrls",     mediaJson != null ? (object)mediaJson : DBNull.Value);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.AddAsync failed UserId={UserId} OrgId={OrgId}", userId, orgId);
                return ApiResponse.Fail("Could not submit review.", "INTERNAL_ERROR");
            }
        }

        // ── GetListAsync ──────────────────────────────────────────────────────
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(
            int orgId, int currentUserId, string sort, int pageNumber, int pageSize)
        {
            try
            {
                var result = await ExecuteDynamicPagedListAsync("OrgReview_GetList", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",         orgId);
                    _db.AddParameter(cmd, "p_CurrentUserId", currentUserId);
                    _db.AddParameter(cmd, "p_Sort",          sort.ToUpperInvariant());
                    _db.AddParameter(cmd, "p_PageNumber",    pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",      pageSize);
                });

                return ApiResponse<PagedResult<DynamicRow>>.Success(result);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.GetListAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("Could not load reviews.", "INTERNAL_ERROR");
            }
        }

        // ── GetAggregateAsync ─────────────────────────────────────────────────
        public async Task<ApiResponse<DynamicRow>> GetAggregateAsync(int orgId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("OrgReview_GetAggregate", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });

                return ApiResponse<DynamicRow>.Success(row!);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.GetAggregateAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("Could not load review summary.", "INTERNAL_ERROR");
            }
        }

        // ── MarkHelpfulAsync ──────────────────────────────────────────────────
        public async Task<ApiResponse> MarkHelpfulAsync(int userId, int reviewId, bool isHelpful)
        {
            try
            {
                var result = await ExecuteWriteAsync("OrgReview_MarkHelpful", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",    userId);
                    _db.AddParameter(cmd, "p_ReviewId",  reviewId);
                    _db.AddParameter(cmd, "p_IsHelpful", isHelpful ? 1 : 0);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.MarkHelpfulAsync failed UserId={UserId} ReviewId={ReviewId}", userId, reviewId);
                return ApiResponse.Fail("Could not record vote.", "INTERNAL_ERROR");
            }
        }

        // ── DeleteAsync ───────────────────────────────────────────────────────
        public async Task<ApiResponse> DeleteAsync(int userId, int reviewId)
        {
            try
            {
                var result = await ExecuteWriteAsync("OrgReview_Delete", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",   userId);
                    _db.AddParameter(cmd, "p_ReviewId", reviewId);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.DeleteAsync failed UserId={UserId} ReviewId={ReviewId}", userId, reviewId);
                return ApiResponse.Fail("Could not delete review.", "INTERNAL_ERROR");
            }
        }

        // ── AddResponseAsync ──────────────────────────────────────────────────
        public async Task<ApiResponse> AddResponseAsync(
            int adminUserId, int orgId, int reviewId, string responseText)
        {
            try
            {
                var result = await ExecuteWriteAsync("OrgReview_AddResponse", cmd =>
                {
                    _db.AddParameter(cmd, "p_AdminUserId",  adminUserId);
                    _db.AddParameter(cmd, "p_OrgId",        orgId);
                    _db.AddParameter(cmd, "p_ReviewId",     reviewId);
                    _db.AddParameter(cmd, "p_ResponseText", responseText);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.AddResponseAsync failed AdminUserId={AdminUserId} ReviewId={ReviewId}", adminUserId, reviewId);
                return ApiResponse.Fail("Could not post response.", "INTERNAL_ERROR");
            }
        }

        // ── ReportAsync ───────────────────────────────────────────────────────
        public async Task<ApiResponse> ReportAsync(int userId, int reviewId)
        {
            try
            {
                var result = await ExecuteWriteAsync("OrgReview_Report", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",   userId);
                    _db.AddParameter(cmd, "p_ReviewId", reviewId);
                });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgReviewDal.ReportAsync failed UserId={UserId} ReviewId={ReviewId}", userId, reviewId);
                return ApiResponse.Fail("Could not report review.", "INTERNAL_ERROR");
            }
        }
    }
}

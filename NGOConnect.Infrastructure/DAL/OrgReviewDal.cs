using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.OrgReview;
using Serilog;
using System.Text.Json;

namespace NGOConnect.Infrastructure.DAL
{
    public class OrgReviewDal : BaseDal, IOrgReviewDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public OrgReviewDal(IDbProvider db, INotificationDal notif, IFCMService fcm) : base(db)
        {
            _notif = notif;
            _fcm   = fcm;
        }

        // ── AddAsync ─────────────────────────────────────────────────────────
        public async Task<ApiResponse> AddAsync(int userId, int orgId, AddReviewRequest request)
        {
            try
            {
                var images = request.MediaItems.Count(m => m.Type == "IMAGE");
                var videos = request.MediaItems.Count(m => m.Type == "VIDEO");
                if (images > 5)
                    return ApiResponse.Fail("You can attach a maximum of 5 photos.", "MEDIA_LIMIT");
                if (videos > 1)
                    return ApiResponse.Fail("You can attach a maximum of 1 video.", "MEDIA_LIMIT");

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

                if (result.Succeeded)
                {
                    // Fire REVIEW_NEW to all NGO admins (fire-and-forget)
                    var reviewId   = Col<int>(result.Row!, "ReviewId");
                    var authorName = Col<string>(result.Row!, "AuthorName") ?? "Someone";
                    var orgName    = Col<string>(result.Row!, "OrgName")    ?? "your NGO";
                    var rating     = request.OverallRating;
                    var capturedOrgId = orgId;

                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var title = $"New {rating}★ review on {orgName}";
                            var body  = $"{authorName} left a review: “{TruncateText(request.ReviewText, 80)}”";

                            var admins = await _notif.GetAdminsWithTokensAsync(capturedOrgId);
                            var tasks  = admins.Select(a =>
                                _notif.CreateAsync(a.UserId, title, body, "REVIEW_NEW",
                                    refId: reviewId, refType: "Review", orgId: capturedOrgId));
                            await Task.WhenAll(tasks);

                            var tokens = admins.Select(a => a.Token)
                                               .Where(t => !string.IsNullOrEmpty(t)).ToList();
                            if (tokens.Count > 0)
                                await _fcm.SendMulticastAsync(tokens, title, body, "REVIEW_NEW",
                                    refId: reviewId, refType: "Review");
                        }
                        catch (Exception ex)
                        {
                            Log.Warning(ex, "REVIEW_NEW notification failed OrgId={OrgId}", capturedOrgId);
                        }
                    });
                }

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

                if (result.Succeeded)
                {
                    // Fire REVIEW_DELETED to all NGO admins (fire-and-forget)
                    var orgId      = Col<int>(result.Row!, "OrgId");
                    var authorName = Col<string>(result.Row!, "AuthorName") ?? "A user";
                    var orgName    = Col<string>(result.Row!, "OrgName")    ?? "your NGO";
                    var rating     = Col<int>(result.Row!, "OverallRating");
                    var capturedReviewId = reviewId;

                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var title = $"Review removed from {orgName}";
                            var body  = $"{authorName} removed their {rating}★ review.";

                            var admins = await _notif.GetAdminsWithTokensAsync(orgId);
                            var tasks  = admins.Select(a =>
                                _notif.CreateAsync(a.UserId, title, body, "REVIEW_DELETED",
                                    refId: orgId, refType: "Org", orgId: orgId));
                            await Task.WhenAll(tasks);

                            var tokens = admins.Select(a => a.Token)
                                               .Where(t => !string.IsNullOrEmpty(t)).ToList();
                            if (tokens.Count > 0)
                                await _fcm.SendMulticastAsync(tokens, title, body, "REVIEW_DELETED",
                                    refId: orgId, refType: "Org");
                        }
                        catch (Exception ex)
                        {
                            Log.Warning(ex, "REVIEW_DELETED notification failed ReviewId={ReviewId}", capturedReviewId);
                        }
                    });
                }

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

                if (result.Succeeded)
                {
                    // Fire REVIEW_RESPONSE to the original reviewer (fire-and-forget)
                    var reviewerUserId   = Col<int>(result.Row!, "ReviewerUserId");
                    var orgName          = Col<string>(result.Row!, "OrgName") ?? "The organisation";
                    var capturedReviewId = reviewId;
                    var capturedOrgId    = orgId;

                    if (reviewerUserId > 0)
                    {
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                var title = $"{orgName} responded to your review";
                                var body  = $"“{TruncateText(responseText, 100)}”";

                                await _notif.CreateAsync(reviewerUserId, title, body, "REVIEW_RESPONSE",
                                    refId: capturedReviewId, refType: "Review", orgId: capturedOrgId);

                                var tokens = await _notif.GetTokensByUserIdAsync(reviewerUserId);
                                if (tokens.Count > 0)
                                    await _fcm.SendAsync(tokens[0], title, body, "REVIEW_RESPONSE",
                                        refId: capturedReviewId, refType: "Review");
                            }
                            catch (Exception ex)
                            {
                                Log.Warning(ex, "REVIEW_RESPONSE notification failed ReviewId={ReviewId}", capturedReviewId);
                            }
                        });
                    }
                }

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

        // ── Helpers ───────────────────────────────────────────────────────────
        private static string TruncateText(string text, int maxLen) =>
            text.Length <= maxLen ? text : text[..maxLen].TrimEnd() + "…";
    }
}

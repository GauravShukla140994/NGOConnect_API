using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Post;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class PostDal : BaseDal, IPostDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;
        private readonly IEmailService    _email;
        private readonly IConfiguration   _config;

        public PostDal(IDbProvider db, INotificationDal notif, IFCMService fcm, IEmailService email, IConfiguration config) : base(db)
        {
            _notif  = notif;
            _fcm    = fcm;
            _email  = email;
            _config = config;
        }

        public async Task<ApiResponse<PostPermissionsModel>> GetPermissionsAsync(int orgId, int userId)
        {
            try
            {
                var model = await ExecuteGetAsync("Post_GetPermissions",
                    r => new PostPermissionsModel
                    {
                        IsMember         = Col<bool>(r, "IsMember"),
                        CanPost          = Col<bool>(r, "CanPost"),
                        CanComment       = Col<bool>(r, "CanComment"),
                        CanCommunityPost = Col<bool>(r, "CanCommunityPost"),
                        MaxPostsPerDay   = Col<int>(r,  "MaxPostsPerDay"),
                        TodayPostCount   = Col<int>(r,  "TodayPostCount"),
                    },
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",  orgId);
                        _db.AddParameter(cmd, "p_UserId", userId);
                    });

                if (model is null)
                    return ApiResponse<PostPermissionsModel>.Failure("Could not load permissions.", "NOT_FOUND");

                return ApiResponse<PostPermissionsModel>.Success(model);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPermissionsAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse<PostPermissionsModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> CreateAsync(int userId, CreatePostRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Create", cmd =>
                {
                    // Order must match SP: p_UserId, p_OrgId, p_Content, p_MediaUrls, p_PostTypeLkpId, p_VisibilityLkpId
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_OrgId",           request.OrgId);
                    _db.AddParameter(cmd, "p_Content",         request.Content);
                    _db.AddParameter(cmd, "p_MediaUrls",       request.MediaUrls?.Count > 0
                                                                       ? string.Join(",", request.MediaUrls)
                                                                       : null);
                    _db.AddParameter(cmd, "p_PostTypeLkpId",   request.PostTypeLkpId);   // SP defaults to GENERAL if null
                    _db.AddParameter(cmd, "p_VisibilityLkpId", request.VisibilityLkpId); // SP defaults to PUBLIC if null
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "POST_CREATE_FAILED");

                var postId = Col<int>(result.Row!, "PostId");
                var row = await ExecuteDynamicGetAsync("Post_GetById", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });

                // Fire-and-forget: notify all approved org members about the new post.
                // Only fired when the post is associated with an organisation.
                // Non-blocking — post creation returns immediately.
                if (request.OrgId is > 0)
                {
                    var capturedPostId = postId;
                    var capturedOrgId  = request.OrgId.Value;
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var notif = await _notif.BulkNotifyFeedPostAsync(capturedPostId, capturedOrgId, userId);
                            if (notif.Tokens.Count > 0)
                            {
                                await _fcm.SendMulticastAsync(
                                    notif.Tokens,
                                    notif.Title,
                                    notif.Body,
                                    "NEW_FEED_POST",
                                    capturedPostId,
                                    "POST");
                            }
                        }
                        catch (Exception ex)
                        {
                            Log.Error(ex, "Post feed notification failed PostId={PostId} OrgId={OrgId}",
                                capturedPostId, capturedOrgId);
                        }
                    });
                }

                return ApiResponse<DynamicRow>.Success(row!, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreateAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int userId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Post_GetFeed", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_OrgId",      (object?)null);  // null = show all orgs
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetFeedAsync failed UserId={UserId}", userId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int postId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Post_GetById", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Post not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByIdAsync failed PostId={PostId}", postId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> DeleteAsync(int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Delete", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeleteAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> PinAsync(int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Pin", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_Pin",    true);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "PinAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> LikeAsync(int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Like", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });

                if (result.Succeeded && result.Row != null)
                {
                    var authorUserId = Col<int>(result.Row, "PostAuthorUserId");
                    var actorName    = Col<string>(result.Row, "ActorName")?.Trim() ?? "Someone";
                    // Only notify the author — never notify if you liked your own post
                    if (authorUserId > 0 && authorUserId != userId)
                    {
                        var capturedAuthor    = authorUserId;
                        var capturedActor     = actorName;
                        var capturedPostId    = postId;
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                await _notif.CreateAsync(capturedAuthor,
                                    "❤️ New Like",
                                    $"{capturedActor} liked your post.",
                                    "POST_LIKED",
                                    refId: capturedPostId);

                                var tokens = await _notif.GetTokensByUserIdAsync(capturedAuthor);
                                if (tokens.Count > 0)
                                    await _fcm.SendAsync(tokens[0],
                                        "❤️ New Like",
                                        $"{capturedActor} liked your post.",
                                        "POST_LIKED",
                                        refId: capturedPostId);
                            }
                            catch (Exception ex)
                            {
                                Log.Warning(ex, "LikeAsync notification failed PostId={PostId}", capturedPostId);
                            }
                        });
                    }
                }

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "LikeAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UnlikeAsync(int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Unlike", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId", postId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UnlikeAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AddCommentAsync(int postId, int userId, AddCommentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_AddComment", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",          postId);
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_Content",         request.Content);
                    _db.AddParameter(cmd, "p_ParentCommentId", request.ParentCommentId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "COMMENT_FAILED");

                var commentId    = Col<int>(result.Row!, "CommentId");
                var authorUserId = Col<int>(result.Row!, "PostAuthorUserId");
                var actorName    = Col<string>(result.Row!, "ActorName")?.Trim() ?? "Someone";

                // Notify post author — skip self-comment
                if (authorUserId > 0 && authorUserId != userId)
                {
                    var capturedAuthor  = authorUserId;
                    var capturedActor   = actorName;
                    var capturedPostId  = postId;
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            await _notif.CreateAsync(capturedAuthor,
                                "💬 New Comment",
                                $"{capturedActor} commented on your post.",
                                "POST_COMMENTED",
                                refId: capturedPostId);

                            var tokens = await _notif.GetTokensByUserIdAsync(capturedAuthor);
                            if (tokens.Count > 0)
                                await _fcm.SendAsync(tokens[0],
                                    "💬 New Comment",
                                    $"{capturedActor} commented on your post.",
                                    "POST_COMMENTED",
                                    refId: capturedPostId);
                        }
                        catch (Exception ex)
                        {
                            Log.Warning(ex, "AddCommentAsync notification failed PostId={PostId}", capturedPostId);
                        }
                    });
                }

                var data = new DynamicRow();
                data["commentId"] = commentId;
                data["message"]   = result.Message;
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddCommentAsync failed PostId={PostId}", postId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetCommentsAsync(int postId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Post_GetComments", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",     postId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetCommentsAsync failed PostId={PostId}", postId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReportAsync(int postId, int userId, ReportPostRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Report", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",      postId);
                    _db.AddParameter(cmd, "p_UserId",      userId);
                    _db.AddParameter(cmd, "p_ReasonCode",  request.ReasonCode);
                    _db.AddParameter(cmd, "p_Details",     request.Details);
                });

                if (result.Succeeded && result.Row != null)
                {
                    var reportCount   = ColNullable<int>(result.Row, "ReportCount")      ?? 0;
                    var authorUserId  = ColNullable<int>(result.Row, "PostAuthorUserId") ?? 0;
                    var orgId         = ColNullable<int>(result.Row, "OrgId");

                    // Fire notifications on 1st report and every 5th thereafter (5, 10, 15 …)
                    if (reportCount == 1 || (reportCount > 0 && reportCount % 5 == 0))
                    {
                        _ = FirePostReportNotificationsAsync(postId, authorUserId, orgId, reportCount, userId);
                    }
                }

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReportAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Private notification helpers ─────────────────────────────────────────

        private async Task FirePostReportNotificationsAsync(
            int postId, int authorUserId, int? orgId, int reportCount, int reporterUserId)
        {
            try
            {
                var countLabel = reportCount == 1 ? "reported for the first time"
                                                  : $"reported {reportCount} times";

                // 1. Notify the post author
                if (authorUserId > 0)
                {
                    var authorTokens = await _notif.GetTokensByUserIdAsync(authorUserId);
                    await _notif.CreateAsync(
                        authorUserId,
                        "⚠️ Your post has been reported",
                        $"Your post has been {countLabel}. Our team will review it shortly.",
                        "POST_REPORTED", postId, "POST");
                    if (authorTokens.Count > 0)
                        await _fcm.SendMulticastAsync(
                            authorTokens,
                            "⚠️ Your post has been reported",
                            $"Your post has been {countLabel}. Our team will review it.",
                            "POST_REPORTED", postId, "POST");
                }

                // 2. Notify org admins (if post is linked to an org)
                if (orgId.HasValue && orgId.Value > 0)
                {
                    var admins = await _notif.GetAdminsWithTokensAsync(orgId.Value);
                    if (admins.Count > 0)
                    {
                        var adminTitle = "🚨 Post reported in your organisation";
                        var adminBody  = $"A post has been {countLabel}. Review it in Admin → Posts tab.";
                        await Task.WhenAll(admins.Select(a =>
                            _notif.CreateAsync(a.UserId, adminTitle, adminBody,
                                "POST_REPORTED_ADMIN", postId, "POST", orgId.Value)));
                        var adminTokens = admins.Select(a => a.Token).Where(t => !string.IsNullOrEmpty(t)).ToList();
                        if (adminTokens.Count > 0)
                            await _fcm.SendMulticastAsync(
                                adminTokens, adminTitle, adminBody,
                                "POST_REPORTED_ADMIN", postId, "POST");
                    }
                }

                // 3. Email all active super admins
                _ = EmailSuperAdminsPostReportAsync(postId, orgId, reportCount, countLabel, reporterUserId);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FirePostReportNotificationsAsync failed PostId={PostId}", postId);
            }
        }

        private async Task EmailSuperAdminsPostReportAsync(
            int postId, int? orgId, int reportCount, string countLabel, int reporterUserId)
        {
            try
            {
                var supportAddress = _config["Email:SupportAddress"] ?? "support@ripplehub.app";
                var subject = $"[Ripple Hub] Post Report Alert — {reportCount} report(s) on Post #{postId}";

                // Fetch enriched details from DB
                string orgName        = orgId.HasValue ? orgId.Value.ToString() : "Not linked";
                string orgIdStr       = orgId.HasValue ? orgId.Value.ToString() : "—";
                string postAuthorId   = "—";
                string postAuthorName = "—";
                string postCreatedAt  = "—";
                string reporterIdStr  = reporterUserId > 0 ? reporterUserId.ToString() : "—";
                string reporterName   = "—";
                string reportedAt     = "—";

                try
                {
                    var details = await ExecuteDynamicGetAsync("Post_GetReportDetails",
                        cmd => _db.AddParameter(cmd, "p_PostId", postId));

                    if (details != null)
                    {
                        orgIdStr       = details.Get<int?>("OrgId")?.ToString()            ?? "—";
                        orgName        = details.Get<string>("OrgName")                    ?? "Not linked";
                        postAuthorId   = details.Get<int?>("PostAuthorUserId")?.ToString() ?? "—";
                        postAuthorName = details.Get<string>("PostAuthorName")             ?? "—";
                        postCreatedAt  = details.Get<string>("PostCreatedAt")              ?? "—";
                        reporterIdStr  = details.Get<int?>("ReportedByUserId")?.ToString() ?? "—";
                        reporterName   = details.Get<string>("ReporterName")               ?? "—";
                        reportedAt     = details.Get<string>("ReportedAt")                 ?? "—";
                    }
                }
                catch (Exception detailEx)
                {
                    Log.Warning(detailEx, "Post_GetReportDetails failed for PostId={PostId} — sending basic email", postId);
                }

                var td1 = @"style=""padding:8px;background:#F3F4F6;font-weight:bold;width:160px;border:1px solid #E5E7EB""";
                var td2 = @"style=""padding:8px;border:1px solid #E5E7EB""";

                var html = $@"
<div style=""font-family:Arial,sans-serif;max-width:620px;margin:0 auto;padding:20px"">
  <h2 style=""color:#DC2626"">⚠️ Post Report Alert</h2>
  <p>A feed post has been <strong>{countLabel}</strong> and requires your review.</p>

  <h4 style=""margin:20px 0 6px;color:#374151"">📄 Post Details</h4>
  <table style=""width:100%;border-collapse:collapse;margin-bottom:16px"">
    <tr><td {td1}>Post ID</td>          <td {td2}>#{postId}</td></tr>
    <tr><td {td1}>Post Author</td>       <td {td2}>{postAuthorName} (ID: {postAuthorId})</td></tr>
    <tr><td {td1}>Post Uploaded At</td>  <td {td2}>{postCreatedAt}</td></tr>
    <tr><td {td1}>Total Reports</td>     <td {td2}>{reportCount}</td></tr>
  </table>

  <h4 style=""margin:20px 0 6px;color:#374151"">🏢 Organisation</h4>
  <table style=""width:100%;border-collapse:collapse;margin-bottom:16px"">
    <tr><td {td1}>Organisation ID</td>   <td {td2}>{orgIdStr}</td></tr>
    <tr><td {td1}>Organisation Name</td> <td {td2}>{orgName}</td></tr>
  </table>

  <h4 style=""margin:20px 0 6px;color:#374151"">🚩 Report Details</h4>
  <table style=""width:100%;border-collapse:collapse;margin-bottom:16px"">
    <tr><td {td1}>Reported By</td>       <td {td2}>{reporterName} (ID: {reporterIdStr})</td></tr>
    <tr><td {td1}>Reported At</td>       <td {td2}>{reportedAt}</td></tr>
  </table>

  <p style=""color:#6B7280;font-size:13px"">Log in to the Super Admin portal to review and take action (remove the post if it violates community guidelines).</p>
  <p style=""color:#9CA3AF;font-size:12px;margin-top:24px"">This is an automated alert from Ripple Hub.</p>
</div>";

                await _email.SendCampaignEmailAsync(supportAddress, subject, html);
                Log.Information("Post report email sent to support inbox <{Email}> PostId={PostId} Count={Count}",
                    supportAddress, postId, reportCount);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "EmailSuperAdminsPostReportAsync failed PostId={PostId}", postId);
            }
        }
    }
}

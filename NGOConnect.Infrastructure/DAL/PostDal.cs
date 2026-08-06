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

        public PostDal(IDbProvider db, INotificationDal notif, IFCMService fcm) : base(db)
        {
            _notif = notif;
            _fcm   = fcm;
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
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReportAsync failed PostId={PostId}", postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

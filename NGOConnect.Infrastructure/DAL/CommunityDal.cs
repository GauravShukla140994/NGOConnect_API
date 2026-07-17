using System.Text.Json;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Community;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CommunityDal : BaseDal, ICommunityDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public CommunityDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse<DynamicRow>> CreatePostAsync(int userId, CreateCommunityPostRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_CreatePost", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_OrgId",         request.OrgId);
                    _db.AddParameter(cmd, "p_Title",         request.Title);
                    _db.AddParameter(cmd, "p_Content",       request.Content);
                    _db.AddParameter(cmd, "p_PostTypeLkpId", request.PostTypeLkpId);
                    _db.AddParameter(cmd, "p_AudienceLkpId", request.AudienceLkpId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "COMMUNITY_POST_FAILED");

                var postId = Col<int>(result.Row!, "CommunityPostId");
                var data = new DynamicRow();
                data["communityPostId"] = postId;
                data["message"]         = result.Message;

                // Fan-out to org members (exclude author) — DB record + FCM push
                if (request.OrgId > 0)
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var members = await _notif.GetMembersWithTokensAsync(request.OrgId, userId);
                            const string title = "📢 New Community Post";
                            const string body  = "A new post has been shared in your community.";
                            foreach (var m in members)
                                await _notif.CreateAsync(m.UserId, title, body, "COMMUNITY_POST", postId, "COMMUNITY_POST", request.OrgId);
                            await _fcm.SendMulticastAsync(members.Select(m => m.Token), title, body, "COMMUNITY_POST", postId, "COMMUNITY_POST");
                        }
                        catch (Exception ex) { Log.Error(ex, "CommunityDal.CreatePostAsync notify failed"); }
                    });

                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreatePostAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int userId, int? orgId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Community_GetFeed", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_PageNumber",  pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",    pageSize);
                });

                // Community_GetFeed returns PollOptionsJson as a raw JSON string for POLL posts.
                // Parse it here into a typed list so the frontend receives a proper array.
                foreach (var row in paged.Items)
                {
                    var raw = row["pollOptionsJson"];
                    if (raw is string json && !string.IsNullOrWhiteSpace(json))
                    {
                        try
                        {
                            var parsed = JsonSerializer.Deserialize<List<Dictionary<string, JsonElement>>>(json);
                            if (parsed != null && parsed.Count > 0)
                            {
                                var totalVotes = parsed.Sum(o =>
                                    o.TryGetValue("voteCount", out var vc) ? vc.GetInt32() : 0);

                                row["pollOptions"] = parsed.Select(o =>
                                {
                                    var voteCount = o.TryGetValue("voteCount", out var vc2) ? vc2.GetInt32() : 0;
                                    var optRow = new DynamicRow();
                                    optRow["pollOptionId"] = o.TryGetValue("pollOptionId", out var id) ? id.GetInt32() : 0;
                                    optRow["optionText"]   = o.TryGetValue("optionText",   out var txt) ? txt.GetString() : string.Empty;
                                    optRow["voteCount"]    = voteCount;
                                    optRow["votePct"]      = totalVotes > 0 ? Math.Round(voteCount * 100.0 / totalVotes, 1) : 0.0;
                                    optRow["isVoted"]      = o.TryGetValue("isVoted",      out var iv) && iv.GetInt32() == 1;
                                    return optRow;
                                }).ToList();
                            }
                        }
                        catch (Exception parseEx)
                        {
                            Log.Warning(parseEx, "GetFeedAsync: failed to parse PollOptionsJson for post");
                        }
                    }

                    // Strip the raw JSON string — client only needs the parsed pollOptions array
                    row.Remove("pollOptionsJson");
                }

                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetFeedAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AcknowledgePostAsync(int communityPostId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_AcknowledgePost", cmd =>
                {
                    _db.AddParameter(cmd, "p_CommunityPostId", communityPostId);
                    _db.AddParameter(cmd, "p_UserId",          userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AcknowledgePostAsync failed CommunityPostId={Id}", communityPostId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> CreatePollAsync(int userId, CreatePollRequest request)
        {
            try
            {
                var optionsJson = JsonSerializer.Serialize(request.Options);
                var result = await ExecuteWriteAsync("Community_CreatePoll", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgId",          request.OrgId);
                    _db.AddParameter(cmd, "p_Question",       request.Question);
                    _db.AddParameter(cmd, "p_OptionsJson",    optionsJson);
                    _db.AddParameter(cmd, "p_ExpiresInHours", request.ExpiresInHours);
                    _db.AddParameter(cmd, "p_IsMultiChoice",  request.IsMultiChoice ? 1 : 0);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "POLL_CREATE_FAILED");

                var pollId = Col<int>(result.Row!, "PollId");
                var data = new DynamicRow();
                data["pollId"]  = pollId;
                data["message"] = result.Message;

                if (request.OrgId > 0)
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var members = await _notif.GetMembersWithTokensAsync(request.OrgId, userId);
                            const string title = "📊 New Poll";
                            const string body  = "A new poll has been posted in your community. Cast your vote!";
                            foreach (var m in members)
                                await _notif.CreateAsync(m.UserId, title, body, "NEW_POLL", pollId, "POLL", request.OrgId);
                            await _fcm.SendMulticastAsync(members.Select(m => m.Token), title, body, "NEW_POLL", pollId, "POLL");
                        }
                        catch (Exception ex) { Log.Error(ex, "CommunityDal.CreatePollAsync notify failed"); }
                    });

                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreatePollAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VoteAsync(int pollId, int userId, VoteRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_Vote", cmd =>
                {
                    _db.AddParameter(cmd, "p_PollId",       pollId);
                    _db.AddParameter(cmd, "p_UserId",       userId);
                    _db.AddParameter(cmd, "p_PollOptionId", request.PollOptionId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VoteAsync failed PollId={PollId}", pollId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> LikePostAsync(int communityPostId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_LikePost", cmd =>
                {
                    _db.AddParameter(cmd, "p_CommunityPostId", communityPostId);
                    _db.AddParameter(cmd, "p_UserId",          userId);
                });
                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "LIKE_FAILED");

                var data = new DynamicRow();
                data["isLiked"]   = Col<int>(result.Row!, "IsLiked") == 1;
                data["likeCount"] = Col<int>(result.Row!, "LikeCount");
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "LikePostAsync failed CommunityPostId={Id}", communityPostId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AddCommentAsync(int communityPostId, int userId, AddCommentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_AddComment", cmd =>
                {
                    _db.AddParameter(cmd, "p_CommunityPostId", communityPostId);
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_Content",         request.Content);
                });
                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "COMMENT_FAILED");

                var data = new DynamicRow();
                data["communityCommentId"] = Col<int>(result.Row!, "CommunityCommentId");
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddCommentAsync failed CommunityPostId={Id}", communityPostId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetCommentsAsync(int communityPostId, int userId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("Community_GetComments", cmd =>
                {
                    _db.AddParameter(cmd, "p_CommunityPostId", communityPostId);
                    _db.AddParameter(cmd, "p_UserId",          userId);
                });
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetCommentsAsync failed CommunityPostId={Id}", communityPostId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> LikeCommentAsync(int communityCommentId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Community_LikeComment", cmd =>
                {
                    _db.AddParameter(cmd, "p_CommunityCommentId", communityCommentId);
                    _db.AddParameter(cmd, "p_UserId",             userId);
                });
                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "COMMENT_LIKE_FAILED");

                var data = new DynamicRow();
                data["isLiked"]   = Col<int>(result.Row!, "IsLiked") == 1;
                data["likeCount"] = Col<int>(result.Row!, "LikeCount");
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "LikeCommentAsync failed CommentId={Id}", communityCommentId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

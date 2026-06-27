using System.Text.Json;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Community;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CommunityDal : BaseDal, ICommunityDal
    {
        public CommunityDal(IDbProvider db) : base(db) { }

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
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreatePostAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int? orgId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Community_GetFeed", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_PageNumber",  pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",    pageSize);
                });
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
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "POLL_CREATE_FAILED");

                var pollId = Col<int>(result.Row!, "PollId");
                var data = new DynamicRow();
                data["pollId"]  = pollId;
                data["message"] = result.Message;
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
    }
}

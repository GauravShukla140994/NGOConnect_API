using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Community;

namespace NGOConnect.Core.Interfaces
{
    public interface ICommunityDal
    {
        Task<ApiResponse<DynamicRow>>              CreatePostAsync(int userId, CreateCommunityPostRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int? orgId, int pageNumber, int pageSize);
        Task<ApiResponse>                          AcknowledgePostAsync(int communityPostId, int userId);
        Task<ApiResponse<DynamicRow>>              CreatePollAsync(int userId, CreatePollRequest request);
        Task<ApiResponse>                          VoteAsync(int pollId, int userId, VoteRequest request);
    }
}

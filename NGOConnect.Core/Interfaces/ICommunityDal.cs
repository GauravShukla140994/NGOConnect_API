using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Community;

namespace NGOConnect.Core.Interfaces
{
    public interface ICommunityDal
    {
        Task<ApiResponse<DynamicRow>>              CreatePostAsync(int userId, CreateCommunityPostRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int userId, int? orgId, int pageNumber, int pageSize);
        Task<ApiResponse>                          AcknowledgePostAsync(int communityPostId, int userId);
        Task<ApiResponse<DynamicRow>>              CreatePollAsync(int userId, CreatePollRequest request);
        Task<ApiResponse>                          VoteAsync(int pollId, int userId, VoteRequest request);

        Task<ApiResponse>                          DeletePostAsync(int communityPostId, int userId);

        // Likes + Comments
        Task<ApiResponse<DynamicRow>>              LikePostAsync(int communityPostId, int userId);
        Task<ApiResponse<DynamicRow>>              AddCommentAsync(int communityPostId, int userId, AddCommentRequest request);
        Task<ApiResponse<List<DynamicRow>>>        GetCommentsAsync(int communityPostId, int userId);
        Task<ApiResponse<DynamicRow>>              LikeCommentAsync(int communityCommentId, int userId);
    }
}

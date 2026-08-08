using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Post;

namespace NGOConnect.Core.Interfaces
{
    public interface IPostDal
    {
        Task<ApiResponse<PostPermissionsModel>>    GetPermissionsAsync(int orgId, int userId);
        Task<ApiResponse<DynamicRow>>              CreateAsync(int userId, CreatePostRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetFeedAsync(int userId, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>>              GetByIdAsync(int postId, int userId);
        Task<ApiResponse>                          DeleteAsync(int postId, int userId);
        Task<ApiResponse>                          PinAsync(int postId, int userId);
        Task<ApiResponse>                          LikeAsync(int postId, int userId);
        Task<ApiResponse>                          UnlikeAsync(int postId, int userId);
        Task<ApiResponse<DynamicRow>>              AddCommentAsync(int postId, int userId, AddCommentRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetCommentsAsync(int postId, int pageNumber, int pageSize);
        Task<ApiResponse>                          ReportAsync(int postId, int userId, ReportPostRequest request);
    }
}

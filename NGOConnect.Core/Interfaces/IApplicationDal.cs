using NGOConnect.Core.Models.Application;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    public interface IApplicationDal
    {
        Task<ApiResponse> ApplyAsync(int projectId, int userId, ApplyRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetByProjectAsync(int projectId, int? statusLkpId, int pageNumber, int pageSize);
        Task<ApiResponse> ReviewAsync(int applicationId, int reviewedBy, ReviewApplicationRequest request);
        Task<ApiResponse<List<DynamicRow>>> GetMyApplicationsAsync(int userId);
    }
}

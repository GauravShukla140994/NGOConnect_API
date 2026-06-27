using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;

namespace NGOConnect.Core.Interfaces
{
    public interface IProjectDal
    {
        Task<ApiResponse<DynamicRow>>              CreateAsync(int userId, CreateProjectRequest request);
        Task<ApiResponse<DynamicRow>>              GetByIdAsync(int projectId);
        Task<ApiResponse>                          UpdateAsync(int projectId, int userId, UpdateProjectRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(int pageNumber, int pageSize, int? orgId = null, string? keyword = null, int? projectTypeLkpId = null);
        Task<ApiResponse>                          AddSkillAsync(int projectId, int userId, AddProjectSkillRequest request);

        // Sessions
        Task<ApiResponse<DynamicRow>>              AddSessionAsync(int projectId, int userId, CreateSessionRequest request);
        Task<ApiResponse<List<DynamicRow>>>        GetSessionsAsync(int projectId);
        Task<ApiResponse<DynamicRow>>              GetSessionQrAsync(int sessionId, int userId);
        Task<ApiResponse>                          CheckInAsync(int userId, CheckInRequest request);

        // Applications
        Task<ApiResponse>                          ApplyAsync(int projectId, int userId);
        Task<ApiResponse>                          ReviewApplicationAsync(int reviewedBy, ReviewApplicationRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetApplicationsAsync(int projectId, int pageNumber, int pageSize, string? statusCode = null);

        // Complete
        Task<ApiResponse>                          CompleteAsync(int projectId, int userId, CompleteProjectRequest request);
    }
}

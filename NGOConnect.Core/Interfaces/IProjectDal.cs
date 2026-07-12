using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;

namespace NGOConnect.Core.Interfaces
{
    public interface IProjectDal
    {
        Task<ApiResponse<DynamicRow>>              CreateAsync(int userId, CreateProjectRequest request);
        Task<ApiResponse<DynamicRow>>              GetByIdAsync(int projectId, int userId = 0);
        Task<ApiResponse>                          UpdateAsync(int projectId, int userId, UpdateProjectRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(int pageNumber, int pageSize, int? orgId = null, string? category = null, string? city = null, string? statusCode = null, string? typeCode = null, decimal? userLat = null, decimal? userLon = null);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetNearbyFeedAsync(int userId, decimal? userLat, decimal? userLon, int pageNumber, int pageSize);
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

        // Cancel
        Task<ApiResponse>                          CancelAsync(int projectId, int userId, CancelProjectRequest request);

        // Manual attendance override (admin)
        Task<ApiResponse>                          ManualAttendanceAsync(int markedBy, ManualAttendanceRequest request);
    }
}

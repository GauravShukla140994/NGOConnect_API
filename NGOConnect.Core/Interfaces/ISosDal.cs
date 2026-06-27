using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Sos;

namespace NGOConnect.Core.Interfaces
{
    public interface ISosDal
    {
        Task<ApiResponse<DynamicRow>>       TriggerAsync(int userId, TriggerSosRequest request);
        Task<ApiResponse<List<DynamicRow>>> GetActiveAsync(int userId, int? orgId = null);
        Task<ApiResponse<DynamicRow>>       GetByIdAsync(int sosIncidentId, int userId);
        Task<ApiResponse>                   ResolveAsync(int sosIncidentId, int userId, ResolveSosRequest request);
        Task<ApiResponse>                   CancelAsync(int sosIncidentId, int userId, CancelSosRequest request);
        Task<ApiResponse>                   RespondAsync(int sosIncidentId, int userId);
        Task<ApiResponse>                   ApproveResponderAsync(int sosIncidentId, int userId, ApproveResponderRequest request);
        Task<ApiResponse<DynamicRow>>       GetLatestLocationAsync(int sosIncidentId, int userId);
        Task<ApiResponse>                   UpdateLocationAsync(int sosIncidentId, int userId, UpdateLocationRequest request);
    }
}

using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Sos;

namespace NGOConnect.Core.Interfaces
{
    public interface ISosDal
    {
        Task<ApiResponse<DynamicRow>>       TriggerAsync(int userId, TriggerSosRequest request);
        Task<ApiResponse<List<DynamicRow>>> GetActiveAsync(int userId, int? orgId = null);

        /// <summary>All SOS incidents for an org (active + resolved + cancelled) ordered newest first.
        /// Includes MyApprovalStatus for the calling user so the UI can show correct button state.</summary>
        Task<ApiResponse<List<DynamicRow>>> GetOrgAlertsAsync(int orgId, int userId, int limit = 20);
        Task<ApiResponse<DynamicRow>>       GetByIdAsync(int sosIncidentId, int userId);
        Task<ApiResponse<DynamicRow>>       GetMyActiveAsync(int userId);

        // Victim actions
        Task<ApiResponse>  ResolveAsync(int sosIncidentId, int userId);           // no request body
        Task<ApiResponse>  CancelAsync(int sosIncidentId, int userId, CancelSosRequest request);

        // Responder actions
        Task<ApiResponse>  RespondAsync(int sosIncidentId, int userId);
        Task<ApiResponse>  ApproveResponderAsync(int sosIncidentId, int userId, ApproveResponderRequest request);
        Task<ApiResponse>  DeclineResponderAsync(int sosIncidentId, int userId, DeclineResponderRequest request);

        // Location
        Task<ApiResponse<DynamicRow>> GetLatestLocationAsync(int sosIncidentId, int userId);
        Task<ApiResponse>             UpdateLocationAsync(int sosIncidentId, int userId, UpdateLocationRequest request);
    }
}

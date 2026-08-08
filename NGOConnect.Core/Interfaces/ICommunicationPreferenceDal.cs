using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Self-service opt-in/opt-out preferences — any authenticated user, not Super Admin only.
    /// Checked by ICampaignDispatchService before every promotional send; never consulted
    /// for transactional messages (OTP, password reset, critical account alerts).
    /// </summary>
    public interface ICommunicationPreferenceDal
    {
        Task<ApiResponse<DynamicRow>> GetAsync(int userId);
        Task<ApiResponse> UpdateAsync(int userId, UpdateCommunicationPreferencesRequest request);
    }
}

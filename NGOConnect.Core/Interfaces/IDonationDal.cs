using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Donation;

namespace NGOConnect.Core.Interfaces
{
    public interface IDonationDal
    {
        // Campaigns
        Task<ApiResponse<DynamicRow>>              CreateCampaignAsync(int userId, CreateCampaignRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetCampaignsAsync(int? orgId, string? keyword, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>>              GetCampaignByIdAsync(int campaignId);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetDonorsAsync(int campaignId, int pageNumber, int pageSize);

        // Donation flow
        Task<ApiResponse<DynamicRow>>              InitiateDonationAsync(int userId, InitiateDonationRequest request);
        Task<ApiResponse>                          ConfirmPaymentAsync(int userId, ConfirmPaymentRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetHistoryAsync(int userId, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>>              GetReceiptAsync(int donationId, int userId);

        // Recurring
        Task<ApiResponse<DynamicRow>>              SetupRecurringAsync(int userId, SetupRecurringRequest request);
        Task<ApiResponse>                          PauseRecurringAsync(int recurringId, int userId);
        Task<ApiResponse>                          ResumeRecurringAsync(int recurringId, int userId);
        Task<ApiResponse>                          CancelRecurringAsync(int recurringId, int userId);

        // Analytics
        Task<ApiResponse<DynamicRow>>              GetAnnualSummaryAsync(int userId, int year);
        Task<ApiResponse<List<DynamicRow>>>        GetSupportedNGOsAsync(int userId);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgTransactionsAsync(int orgId, int pageNumber, int pageSize);
    }
}

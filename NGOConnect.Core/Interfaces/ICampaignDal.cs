using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Marketing & Communication Center — Phase 0 + Phase 1 (Push + Email only).
    /// See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    public interface ICampaignDal
    {
        // ── CRUD ──────────────────────────────────────────────────
        Task<ApiResponse<int>> CreateAsync(CreateCampaignRequest request, int userId);
        Task<ApiResponse> UpdateAsync(int campaignId, UpdateCampaignRequest request, int userId);
        Task<ApiResponse> SetStatusAsync(int campaignId, string statusCode, string? hangfireJobId, int userId);

        // ── Channels ──────────────────────────────────────────────
        Task<ApiResponse> SaveChannelAsync(int campaignId, SaveCampaignChannelRequest request);
        Task<ApiResponse> DeleteChannelAsync(int campaignId, string channelCode);

        // ── Audience ──────────────────────────────────────────────
        Task<ApiResponse> SaveAudienceRuleAsync(int campaignId, SaveAudienceRuleRequest request);
        Task<ApiResponse<DynamicRow>> EstimateAudienceAsync(int campaignId);
        Task<ApiResponse<DynamicRow>> ResolveRecipientsAsync(int campaignId);

        // ── Reads (Dynamic — display-shaped, 70% side of the 30/70 rule) ──
        Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(string? statusCode, string? search, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>> GetByIdAsync(int campaignId);
        Task<ApiResponse<DynamicRow>> GetHistoryDetailAsync(int campaignId);
        Task<ApiResponse<DynamicRow>> GetDashboardStatsAsync();

        /// <summary>Per-recipient drill-down (phone/email/name + individual status) — Super Admin only.</summary>
        Task<ApiResponse<PagedResult<DynamicRow>>> GetRecipientListAsync(int campaignId, string? statusCode, int pageNumber, int pageSize);

        /// <summary>
        /// Real device-side delivery acknowledgment — called by the mobile app itself
        /// the moment it actually renders a campaign push. Ownership-checked in the SP
        /// (userId must match the recipient row's UserId); always reports success to
        /// the caller regardless of match, so this never leaks whether a given
        /// campaignRecipientId exists or belongs to someone else.
        /// </summary>
        Task<ApiResponse> AckDeliveredAsync(long campaignRecipientId, int userId);

        // ── Dispatch support (called by ICampaignDispatchService, not controllers) ──
        Task<List<DynamicRow>> GetQueuedRecipientsAsync(int campaignId, string channelCode, int batchSize);
        Task MarkRecipientStatusAsync(long campaignRecipientId, string statusCode, string? providerMessageId, string? failReason);
        Task<long> CreateQueueJobAsync(int campaignId, int batchNumber, string channelCode, int batchSize);
        Task MarkQueueJobStatusAsync(long queueJobId, string status, string? errorMessage);

        /// <summary>Lightweight Email lookup for the /test-send preview action — never touches CampaignRecipients.</summary>
        Task<List<DynamicRow>> GetUserContactsAsync(List<int> userIds);
    }
}

using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Marketing & Communication Center — Phase 1 dispatch worker.
    /// Invoked by Hangfire (BackgroundJob.Enqueue / Schedule from CampaignController),
    /// never called directly from a request. Push + Email only — see
    /// Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    public interface ICampaignDispatchService
    {
        /// <summary>
        /// Resolves the campaign's audience (if not already resolved), then sends to
        /// every QUEUED recipient across its selected channels in batches, respecting
        /// Settings.COMMUNICATION.CAMPAIGN_BATCH_SIZE / CAMPAIGN_RETRY_MAX_ATTEMPTS.
        /// Marks the campaign RUNNING at the start and COMPLETED (or FAILED if every
        /// batch failed) at the end.
        /// </summary>
        Task DispatchAsync(int campaignId);

        /// <summary>
        /// Sends the campaign's current channel content to a specific, small list of
        /// users (admin/internal testers) — a preview action. Deliberately bypasses
        /// CampaignRecipients entirely so test sends never pollute real delivery metrics.
        /// </summary>
        Task<ApiResponse> TestSendAsync(int campaignId, List<int> userIds);
    }
}

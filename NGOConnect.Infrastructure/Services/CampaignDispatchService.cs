using System.Text.Json;
using System.Text.Json.Serialization;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Marketing & Communication Center — Phase 1 dispatch worker (Push + Email only).
    /// Runs on a Hangfire background thread — see Program.cs / ServiceCollectionExtensions
    /// for the Hangfire wiring, and CampaignController for where jobs are enqueued.
    /// See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    public class CampaignDispatchService : ICampaignDispatchService
    {
        private readonly ICampaignDal    _campaigns;
        private readonly INotificationDal _notifications;
        private readonly IFCMService      _fcm;
        private readonly IEmailService    _email;
        private readonly ISettingsCache   _settings;

        public CampaignDispatchService(
            ICampaignDal campaigns,
            INotificationDal notifications,
            IFCMService fcm,
            IEmailService email,
            ISettingsCache settings)
        {
            _campaigns     = campaigns;
            _notifications = notifications;
            _fcm           = fcm;
            _email         = email;
            _settings      = settings;
        }

        public async Task DispatchAsync(int campaignId)
        {
            var batchSize  = _settings.GetValue("CAMPAIGN_BATCH_SIZE", 500);
            var maxRetries = _settings.GetValue("CAMPAIGN_RETRY_MAX_ATTEMPTS", 3);

            try
            {
                // Idempotent — safe even if /send already resolved recipients.
                await _campaigns.ResolveRecipientsAsync(campaignId);
                await _campaigns.SetStatusAsync(campaignId, "RUNNING", null, 0);

                var pushSent  = await DispatchChannelAsync(campaignId, "PUSH",  batchSize, maxRetries);
                var emailSent = await DispatchChannelAsync(campaignId, "EMAIL", batchSize, maxRetries);

                await _campaigns.SetStatusAsync(campaignId, "COMPLETED", null, 0);
                Log.Information("Campaign {CampaignId} dispatch completed. Push={Push} Email={Email}",
                    campaignId, pushSent, emailSent);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign {CampaignId} dispatch failed", campaignId);
                await _campaigns.SetStatusAsync(campaignId, "FAILED", null, 0);
            }
        }

        /// <summary>Drains every QUEUED recipient for one channel, batch by batch.</summary>
        private async Task<int> DispatchChannelAsync(int campaignId, string channelCode, int batchSize, int maxRetries)
        {
            var totalSent   = 0;
            var batchNumber = 0;

            while (true)
            {
                var batch = await _campaigns.GetQueuedRecipientsAsync(campaignId, channelCode, batchSize);
                if (batch.Count == 0) break;

                batchNumber++;
                var queueJobId = await _campaigns.CreateQueueJobAsync(campaignId, batchNumber, channelCode, batch.Count);

                foreach (var recipient in batch)
                {
                    var recipientId = recipient.Get<long>("campaignRecipientId");
                    var userId      = recipient.Get<int>("userId");

                    var sent = channelCode switch
                    {
                        "PUSH"  => await SendPushAsync(campaignId, userId, recipient),
                        "EMAIL" => await SendEmailAsync(recipient),
                        _       => false
                    };

                    if (sent)
                    {
                        await _campaigns.MarkRecipientStatusAsync(recipientId, "SENT", null, null);
                        totalSent++;
                    }
                    else
                    {
                        await _campaigns.MarkRecipientStatusAsync(recipientId, "FAILED", null,
                            "Delivery failed — see application logs for provider response.");
                    }
                }

                await _campaigns.MarkQueueJobStatusAsync(queueJobId, "COMPLETED", null);
            }

            return totalSent;
        }

        private async Task<bool> SendPushAsync(int campaignId, int userId, DynamicRow recipient)
        {
            var tokens = await _notifications.GetTokensByUserIdAsync(userId);
            if (tokens.Count == 0) return false;

            var title        = recipient.Get<string>("pushTitle")       ?? "RippleHub";
            var body         = recipient.Get<string>("pushBody")        ?? "";
            var imageUrl     = recipient.Get<string>("pushImageUrl");
            var deepLink     = recipient.Get<string>("pushDeepLink");
            var actionLabel  = recipient.Get<string>("pushActionLabel");
            var recipientId  = recipient.Get<long>("campaignRecipientId");

            // campaignRecipientId lets the device ack real delivery back to
            // CampaignRecipient_AckDelivered the moment it actually renders this push —
            // that's what makes "Delivered" mean something more than "FCM accepted it".
            var extraData = new Dictionary<string, string> { ["campaignRecipientId"] = recipientId.ToString() };

            return await _fcm.SendMulticastAsync(tokens, title, body, "CAMPAIGN", refId: campaignId, refType: "Campaign",
                imageUrl: imageUrl, deepLink: deepLink, actionLabel: actionLabel, extraData: extraData);
        }

        private async Task<bool> SendEmailAsync(DynamicRow recipient)
        {
            var email = recipient.Get<string>("email");
            if (string.IsNullOrWhiteSpace(email)) return false;

            var subject = recipient.Get<string>("emailSubject")  ?? "An update from RippleHub";
            var body    = recipient.Get<string>("emailHtmlBody") ?? "";

            return await _email.SendCampaignEmailAsync(email, subject, body);
        }

        // ── Test Send (preview — never touches CampaignRecipients) ────────

        public async Task<ApiResponse> TestSendAsync(int campaignId, List<int> userIds)
        {
            if (userIds.Count == 0) return ApiResponse.Fail("No test recipients selected.");

            var campaignResp = await _campaigns.GetByIdAsync(campaignId);
            if (campaignResp.IsSuccess != 1 || campaignResp.Data is null)
                return ApiResponse.Fail("Campaign not found.", "NOT_FOUND");

            var channelsJson = campaignResp.Data.Get<string>("channelsJson");
            if (string.IsNullOrWhiteSpace(channelsJson))
                return ApiResponse.Fail("No channels configured for this campaign yet.");

            List<ChannelPreview>? channels;
            try
            {
                channels = JsonSerializer.Deserialize<List<ChannelPreview>>(channelsJson,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "TestSendAsync: could not parse ChannelsJson for Campaign {CampaignId}", campaignId);
                return ApiResponse.Fail("Could not read this campaign's channel content.");
            }

            if (channels is null || channels.Count == 0)
                return ApiResponse.Fail("No channels configured for this campaign yet.");

            var contacts  = await _campaigns.GetUserContactsAsync(userIds);
            var anySent   = false;

            foreach (var userId in userIds)
            {
                foreach (var channel in channels)
                {
                    if (channel.ChannelCode == "PUSH")
                    {
                        var tokens = await _notifications.GetTokensByUserIdAsync(userId);
                        if (tokens.Count == 0) continue;
                        anySent |= await _fcm.SendMulticastAsync(
                            tokens, $"[TEST] {channel.PushTitle ?? "RippleHub"}", channel.PushBody ?? "",
                            "CAMPAIGN_TEST", refId: campaignId, refType: "Campaign",
                            imageUrl: channel.PushImageUrl, deepLink: channel.PushDeepLink, actionLabel: channel.PushActionLabel);
                    }
                    else if (channel.ChannelCode == "EMAIL")
                    {
                        var email = contacts.FirstOrDefault(c => c.Get<int>("userId") == userId)?.Get<string>("email");
                        if (string.IsNullOrWhiteSpace(email)) continue;
                        anySent |= await _email.SendCampaignEmailAsync(
                            email, $"[TEST] {channel.EmailSubject ?? "RippleHub"}", channel.EmailHtmlBody ?? "");
                    }
                }
            }

            return anySent
                ? ApiResponse.Ok("Test send completed.")
                : ApiResponse.Fail("Could not deliver — the selected user(s) have no device token / email on file for these channels.");
        }

        private class ChannelPreview
        {
            [JsonPropertyName("channelCode")]     public string? ChannelCode     { get; set; }
            [JsonPropertyName("pushTitle")]       public string? PushTitle       { get; set; }
            [JsonPropertyName("pushBody")]        public string? PushBody        { get; set; }
            [JsonPropertyName("pushImageUrl")]    public string? PushImageUrl    { get; set; }
            [JsonPropertyName("pushDeepLink")]    public string? PushDeepLink    { get; set; }
            [JsonPropertyName("pushActionLabel")] public string? PushActionLabel { get; set; }
            [JsonPropertyName("emailSubject")]    public string? EmailSubject    { get; set; }
            [JsonPropertyName("emailHtmlBody")]   public string? EmailHtmlBody   { get; set; }
        }
    }
}

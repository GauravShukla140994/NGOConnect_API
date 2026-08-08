namespace NGOConnect.Core.Models.Campaign
{
    // ── Marketing & Communication Center — Phase 0 + Phase 1 ──────────────
    // Push + Email only. See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    // Core entities here are Typed models (30% side of the 30/70 rule) — display
    // queries (list/detail/history/dashboard) return DynamicRow instead, see
    // ICampaignDal.

    public class CreateCampaignRequest
    {
        public string  CampaignName     { get; set; } = string.Empty;
        public string?  InternalNotes    { get; set; }
        public string  CampaignTypeCode { get; set; } = string.Empty; // MKTG_CAMPAIGN_TYPE
        public string  PriorityCode     { get; set; } = "NORMAL";     // MKTG_CAMPAIGN_PRIORITY
    }

    public class UpdateCampaignRequest
    {
        public string?   CampaignName     { get; set; }
        public string?   InternalNotes    { get; set; }
        public string?   CampaignTypeCode { get; set; }
        public string?   PriorityCode     { get; set; }
        public string?   ScheduleType     { get; set; } // NOW | SCHEDULED
        public DateTime? ScheduledAt      { get; set; }
        public string?   TimezoneName     { get; set; }
    }

    /// <summary>
    /// One channel's compose payload. ChannelCode must be PUSH or EMAIL in Phase 1 —
    /// SMS/WHATSAPP are rejected by CampaignChannel_Save itself (defense in depth
    /// alongside the Settings.COMMUNICATION.CAMPAIGN_SMS_ENABLED toggle).
    /// </summary>
    public class SaveCampaignChannelRequest
    {
        public string  ChannelCode     { get; set; } = string.Empty;
        // Push
        public string? PushTitle       { get; set; }
        public string? PushBody        { get; set; }
        public string? PushImageUrl    { get; set; }
        public string? PushDeepLink    { get; set; }
        public string? PushActionLabel { get; set; }
        // Email
        public string? EmailSubject    { get; set; }
        public string? EmailHtmlBody   { get; set; }
    }

    /// <summary>
    /// Phase 1 supports exactly one audience rule per campaign.
    /// RuleType: ALL | ACTIVE | INACTIVE | NEW | BY_ORG | BY_ROLE
    /// RuleValue shapes (serialized to RuleValueJson):
    ///   ACTIVE/INACTIVE/NEW → {"days": 7}
    ///   BY_ORG              → {"orgIds": [1,2,3]}
    ///   BY_ROLE              → {"roleCodes": ["FOUNDER","ADMIN","MEMBER","DONOR"]}
    /// </summary>
    public class SaveAudienceRuleRequest
    {
        public string                  RuleType  { get; set; } = "ALL";
        public Dictionary<string, object>? RuleValue { get; set; }
    }

    public class TestSendRequest
    {
        public List<int> UserIds { get; set; } = new();
    }

    public class ScheduleCampaignRequest
    {
        public DateTime ScheduledAt  { get; set; }
        public string   TimezoneName { get; set; } = "Asia/Kolkata";
    }

    public class UpdateCommunicationPreferencesRequest
    {
        public bool? ReceivePushNotifications      { get; set; }
        public bool? ReceivePromotionalEmails      { get; set; }
        public bool? ReceivePromotionalSms         { get; set; }
        public bool? ReceiveNgoUpdates             { get; set; }
        public bool? ReceiveDonationAlerts         { get; set; }
        public bool? ReceiveVolunteerOpportunities { get; set; }
    }
}

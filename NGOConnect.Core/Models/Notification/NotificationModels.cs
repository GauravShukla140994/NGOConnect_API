namespace NGOConnect.Core.Models.Notification
{
    public class SaveDeviceTokenRequest
    {
        public string Token    { get; set; } = string.Empty;
        public string Platform { get; set; } = "ANDROID";  // ANDROID, IOS, WEB
    }

    /// <summary>
    /// Returned by NotificationDal.BulkNotifyFeedPostAsync.
    /// Contains the FCM tokens to multicast and the notification text built by the SP.
    /// </summary>
    public class FeedPostNotifData
    {
        public string       Title  { get; set; } = string.Empty;
        public string       Body   { get; set; } = string.Empty;
        public List<string> Tokens { get; set; } = [];
    }

    public class SendTestNotificationRequest
    {
        public string  Token       { get; set; } = string.Empty;  // FCM device token
        public string  Title       { get; set; } = "Test Push";
        public string  Body        { get; set; } = "This is a test notification from Ripple Hub.";
        public string? NotifType   { get; set; } = "TEST";        // maps to deep-link handler on mobile
        public int?    RefId       { get; set; }
        public string? RefType     { get; set; }
        // CAMPAIGN extras — only used when NotifType = "CAMPAIGN"
        public string? DeepLink    { get; set; }                  // ngoconnect:// or https:// URL
        public string? ActionLabel { get; set; }                  // CTA text shown in-app after tap
        public string? ImageUrl    { get; set; }                  // optional large icon URL
    }
}

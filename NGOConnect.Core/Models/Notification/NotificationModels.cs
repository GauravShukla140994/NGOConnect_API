namespace NGOConnect.Core.Models.Notification
{
    public class SaveDeviceTokenRequest
    {
        public string Token    { get; set; } = string.Empty;
        public string Platform { get; set; } = "ANDROID";  // ANDROID, IOS, WEB
    }

    public class SendTestNotificationRequest
    {
        public string  Token     { get; set; } = string.Empty;  // FCM device token
        public string  Title     { get; set; } = "Test Push";
        public string  Body      { get; set; } = "This is a test notification from NGO Connect.";
        public string? NotifType { get; set; } = "TEST";        // maps to deep-link handler on mobile
        public int?    RefId     { get; set; }
        public string? RefType   { get; set; }
    }
}

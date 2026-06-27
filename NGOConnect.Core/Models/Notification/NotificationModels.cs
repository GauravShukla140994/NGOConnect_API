namespace NGOConnect.Core.Models.Notification
{
    public class SaveDeviceTokenRequest
    {
        public string Token    { get; set; } = string.Empty;
        public string Platform { get; set; } = "ANDROID";  // ANDROID, IOS, WEB
    }
}

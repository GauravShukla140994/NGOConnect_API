namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Firebase Cloud Messaging — sends push notifications to devices.
    /// Methods never throw; failures are logged and return false.
    /// </summary>
    public interface IFCMService
    {
        /// <summary>Send a push to a single FCM token.</summary>
        Task<bool> SendAsync(
            string token,
            string title,
            string body,
            string notifType,
            int?    refId       = null,
            string? refType     = null,
            string? imageUrl    = null,
            string? deepLink    = null,
            string? actionLabel = null,
            IReadOnlyDictionary<string, string>? extraData = null);

        /// <summary>Send the same push to multiple FCM tokens (fan-out, max 500 per call).</summary>
        Task<bool> SendMulticastAsync(
            IEnumerable<string> tokens,
            string title,
            string body,
            string notifType,
            int?    refId       = null,
            string? refType     = null,
            string? imageUrl    = null,
            string? deepLink    = null,
            string? actionLabel = null,
            IReadOnlyDictionary<string, string>? extraData = null);
    }
}

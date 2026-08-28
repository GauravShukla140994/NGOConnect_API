namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Transactional SMS service — OTP delivery via SMS gateway.
    /// Implementation: Fast2SmsService (Fast2SMS India).
    /// Configured via appsettings.json → "Sms" section.
    /// </summary>
    public interface ISmsService
    {
        /// <summary>
        /// Send a 6-digit OTP to the given mobile number.
        /// </summary>
        /// <param name="mobile">Mobile number without country code (e.g. "9876543210")</param>
        /// <param name="countryCode">Country code (e.g. "+91"). Used for non-Indian numbers.</param>
        /// <param name="otpCode">6-digit OTP string</param>
        /// <param name="expiryMinutes">OTP validity in minutes (shown in message)</param>
        /// <returns>True if SMS was accepted by the gateway</returns>
        Task<bool> SendOtpAsync(string mobile, string countryCode, string otpCode, int expiryMinutes);

        /// <summary>
        /// Send a custom transactional SMS (e.g. org invite link).
        /// </summary>
        /// <param name="mobile">Mobile number without country code</param>
        /// <param name="countryCode">Country code (e.g. "+91")</param>
        /// <param name="message">Full message text (max 160 chars for single SMS)</param>
        Task<bool> SendAsync(string mobile, string countryCode, string message);

        /// <summary>
        /// Send an SMS using a DLT-registered template with variable substitution.
        /// On the DLT route: fires Fast2SMS bulkV2 with route=dlt, sender_id, message=templateId,
        /// and pipe-separated variable values matching each {#VAR#} placeholder in the template.
        /// On the quick route (dev/staging): builds a human-readable fallback and sends via quick route.
        /// </summary>
        /// <param name="mobile">Mobile number without country code</param>
        /// <param name="countryCode">Country code (e.g. "+91")</param>
        /// <param name="templateId">DLT Message ID registered in Fast2SMS (e.g. "223944")</param>
        /// <param name="senderId">Registered sender ID / header (e.g. "AJIEPL")</param>
        /// <param name="variablesValues">Pipe-separated values matching each {#VAR#} in the template</param>
        /// <param name="fallbackMessage">Plain-text fallback used on the quick route (dev/staging)</param>
        Task<bool> SendTemplateAsync(
            string mobile, string countryCode,
            string templateId, string senderId,
            string variablesValues, string fallbackMessage);
    }
}

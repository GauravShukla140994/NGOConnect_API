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
    }
}

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Transactional email service — OTP delivery, notifications.
    /// Implementation: SmtpEmailService (MailKit).
    /// Configured via appsettings.json → "Email" section.
    /// </summary>
    public interface IEmailService
    {
        /// <summary>
        /// Send a 6-digit OTP to the given email address.
        /// Returns true if the email was accepted by the SMTP server.
        /// </summary>
        Task<bool> SendOtpAsync(string toEmail, string otpCode, int expiryMinutes);
    }
}

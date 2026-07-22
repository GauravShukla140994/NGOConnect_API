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

        /// <summary>
        /// Send an org member invitation email with an accept link.
        /// Returns true if the email was accepted by the gateway.
        /// </summary>
        Task<bool> SendInviteAsync(string toEmail, string inviterName, string orgName, string inviteLink);
    }
}

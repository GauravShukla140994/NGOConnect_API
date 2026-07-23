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

        /// <summary>
        /// Forward a user's Help &amp; Support submission to the support inbox.
        /// Email goes TO Email:SupportAddress (default: support@ripplehub.app).
        /// Reply-To is set to contactEmail so the team can reply directly to the user.
        /// Returns true if the email was accepted by the gateway.
        /// </summary>
        Task<bool> SendSupportEmailAsync(
            string contactName,
            string categoryLabel,
            string subject,
            string description,
            string contactEmail,
            string? attachmentUrl = null);

        /// <summary>
        /// Send an arbitrary marketing/communication campaign email (Marketing &amp;
        /// Communication Center, Phase 1). Unlike the methods above, subject and HTML
        /// body are fully caller-supplied — the campaign's own compose step, not a
        /// fixed template. Returns true if the email was accepted by the gateway.
        /// </summary>
        Task<bool> SendCampaignEmailAsync(string toEmail, string subject, string htmlBody);
    }
}

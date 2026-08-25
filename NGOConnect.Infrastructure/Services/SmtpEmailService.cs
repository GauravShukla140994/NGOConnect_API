using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Configuration;
using MimeKit;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Sends transactional emails via SMTP using MailKit.
    ///
    /// Config keys (appsettings.json → "Email" section):
    ///   Email:SmtpHost        — SMTP server hostname
    ///   Email:SmtpPort        — Port (587 = STARTTLS, 465 = SSL)
    ///   Email:SmtpUsername    — Auth username (usually same as FromAddress)
    ///   Email:SmtpPassword    — Auth password  ← SECRET: keep in appsettings.Development.json / Railway env var
    ///   Email:FromAddress     — Sender address  e.g. no-reply@ripplehub.app
    ///   Email:FromName        — Display name    e.g. RippleHub
    ///   Email:UseSsl          — true = implicit SSL (port 465); false = STARTTLS (port 587)
    /// </summary>
    public class SmtpEmailService : IEmailService
    {
        private readonly IConfiguration _config;

        public SmtpEmailService(IConfiguration config)
        {
            _config = config;
        }

        public async Task<bool> SendOtpAsync(string toEmail, string otpCode, int expiryMinutes, string purpose = "verification")
        {
            try
            {
                var host        = _config["Email:SmtpHost"]     ?? throw new InvalidOperationException("Email:SmtpHost not configured");
                var port        = int.Parse(_config["Email:SmtpPort"] ?? "587");
                var username    = _config["Email:SmtpUsername"] ?? throw new InvalidOperationException("Email:SmtpUsername not configured");
                var password    = _config["Email:SmtpPassword"] ?? throw new InvalidOperationException("Email:SmtpPassword not configured");
                var fromAddress = _config["Email:FromAddress"]  ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]     ?? "RippleHub";
                var useSsl      = bool.Parse(_config["Email:UseSsl"] ?? "false");

                var message = new MimeMessage();
                message.From.Add(new MailboxAddress(fromName, fromAddress));
                message.To.Add(MailboxAddress.Parse(toEmail));
                message.Subject = $"{otpCode} is your RippleHub verification code";

                var bodyBuilder = new BodyBuilder
                {
                    HtmlBody = BuildOtpHtml(otpCode, expiryMinutes, purpose),
                    TextBody = $"{otpCode} is your OTP for RippleHub {purpose}. It is valid for {expiryMinutes} minutes. Do not share this OTP with anyone."
                };
                message.Body = bodyBuilder.ToMessageBody();

                using var client = new SmtpClient();
                client.Timeout = 8_000; // 8 s — prevents Railway from hanging when SMTP host is unreachable

                var socketOptions = useSsl
                    ? SecureSocketOptions.SslOnConnect    // port 465
                    : SecureSocketOptions.StartTls;       // port 587

                await client.ConnectAsync(host, port, socketOptions);
                await client.AuthenticateAsync(username, password);
                await client.SendAsync(message);
                await client.DisconnectAsync(true);

                Log.Information("OTP email sent to {Email}", MaskEmail(toEmail));
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SmtpEmailService failed to send OTP to {Email}", MaskEmail(toEmail));
                return false;
            }
        }

        // ── HTML Email Template ──────────────────────────────────
        // Internal so ResendEmailService can reuse the same templates without duplication.
        internal static string BuildOtpHtmlInternal(string otpCode, int expiryMinutes, string purpose = "verification") =>
            BuildOtpHtml(otpCode, expiryMinutes, purpose);

        internal static string BuildInviteHtmlInternal(string inviterName, string orgName, string inviteLink) =>
            BuildInviteHtml(inviterName, orgName, inviteLink);

        internal static string BuildSupportHtmlInternal(
            string contactName, string categoryLabel, string subject,
            string description, string contactEmail, string? attachmentUrl = null) =>
            BuildSupportHtml(contactName, categoryLabel, subject, description, contactEmail, attachmentUrl);

        private static string BuildOtpHtml(string otpCode, int expiryMinutes, string purpose = "verification") => $"""
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0" />
              <title>Your RippleHub OTP</title>
            </head>
            <body style="margin:0;padding:0;background:#f0f4f8;font-family:Arial,Helvetica,sans-serif;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f0f4f8;padding:40px 0;">
                <tr>
                  <td align="center">
                    <table width="560" cellpadding="0" cellspacing="0" border="0"
                           style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

                      <!-- Header -->
                      <tr>
                        <td style="background:#0A1628;padding:28px 40px 24px;text-align:center;">
                          <img src="https://ripplehub-public.s3.ap-south-1.amazonaws.com/ripplehub-logo/apple-touch-icon+png.png" alt="RippleHub" width="64" height="64" style="display:block;margin:0 auto 12px;border-radius:14px;" />
                          <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.5px;">RippleHub</h1>
                          <p style="margin:6px 0 0;color:#93c5fd;font-size:13px;">Global Social Impact Platform</p>
                        </td>
                      </tr>

                      <!-- Body -->
                      <tr>
                        <td style="padding:40px 40px 32px;">
                          <p style="margin:0 0 8px;color:#111827;font-size:15px;">Hello,</p>
                          <p style="margin:0 0 28px;color:#4b5563;font-size:14px;line-height:1.6;">
                            Use the verification code below to complete your <strong>{purpose}</strong>.
                            This code is valid for <strong>{expiryMinutes} minutes</strong>.
                          </p>

                          <!-- OTP Box -->
                          <table width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                              <td align="center" style="padding:20px 0;">
                                <div style="display:inline-block;background:#eff6ff;border:2px solid #1a56db;
                                            border-radius:10px;padding:18px 48px;">
                                  <span style="font-size:38px;font-weight:700;color:#1a56db;
                                               letter-spacing:12px;font-family:monospace;">
                                    {otpCode}
                                  </span>
                                </div>
                              </td>
                            </tr>
                          </table>

                          <p style="margin:24px 0 0;color:#9ca3af;font-size:12px;line-height:1.8;">
                            ⏱️ This code expires in <strong>{expiryMinutes} minutes</strong>.<br/>
                            🔒 Never share this code with anyone — RippleHub will never ask for it.<br/>
                            ❓ If you didn't request this, you can safely ignore this email.
                          </p>
                        </td>
                      </tr>

                      <!-- Footer -->
                      <tr>
                        <td style="background:#f9fafb;padding:20px 40px;border-top:1px solid #e5e7eb;text-align:center;">
                          <p style="margin:0;color:#9ca3af;font-size:11px;line-height:1.6;">
                            © {DateTime.UtcNow.Year} RippleHub — RippleHub Pvt. Ltd.<br/>
                            This is an automated message. Please do not reply to this email.
                          </p>
                        </td>
                      </tr>

                    </table>
                  </td>
                </tr>
              </table>
            </body>
            </html>
            """;

        public async Task<bool> SendInviteAsync(
            string toEmail, string inviterName, string orgName, string inviteLink)
        {
            try
            {
                var host        = _config["Email:SmtpHost"]     ?? throw new InvalidOperationException("Email:SmtpHost not configured");
                var port        = int.Parse(_config["Email:SmtpPort"] ?? "587");
                var username    = _config["Email:SmtpUsername"] ?? throw new InvalidOperationException("Email:SmtpUsername not configured");
                var password    = _config["Email:SmtpPassword"] ?? throw new InvalidOperationException("Email:SmtpPassword not configured");
                var fromAddress = _config["Email:FromAddress"]  ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]     ?? "RippleHub";
                var useSsl      = bool.Parse(_config["Email:UseSsl"] ?? "false");

                var message = new MimeMessage();
                message.From.Add(new MailboxAddress(fromName, fromAddress));
                message.To.Add(MailboxAddress.Parse(toEmail));
                message.Subject = $"{inviterName} invited you to join {orgName} on RippleHub";

                var bodyBuilder = new BodyBuilder
                {
                    HtmlBody = BuildInviteHtml(inviterName, orgName, inviteLink),
                    TextBody = $"{inviterName} has invited you to join {orgName} on RippleHub.\n\nAccept invitation: {inviteLink}\n\nThis link expires in 30 days."
                };
                message.Body = bodyBuilder.ToMessageBody();

                using var client = new SmtpClient();
                client.Timeout = 8_000;
                var socketOptions = useSsl ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
                await client.ConnectAsync(host, port, socketOptions);
                await client.AuthenticateAsync(username, password);
                await client.SendAsync(message);
                await client.DisconnectAsync(true);

                Log.Information("Invite email sent to {Email} for Org={OrgName}", MaskEmail(toEmail), orgName);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SmtpEmailService failed to send invite to {Email}", MaskEmail(toEmail));
                return false;
            }
        }

        private static string BuildInviteHtml(string inviterName, string orgName, string inviteLink) => $"""
            <!DOCTYPE html>
            <html lang="en">
            <head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/>
            <title>You're invited to {orgName}</title></head>
            <body style="margin:0;padding:0;background:#f0f4f8;font-family:Arial,Helvetica,sans-serif;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f0f4f8;padding:40px 0;">
                <tr><td align="center">
                  <table width="560" cellpadding="0" cellspacing="0" border="0"
                         style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
                    <tr>
                      <td style="background:#1a56db;padding:32px 40px;text-align:center;">
                        <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700;">RippleHub</h1>
                        <p style="margin:6px 0 0;color:#bfdbfe;font-size:13px;">Global Social Impact Platform</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:40px;">
                        <p style="margin:0 0 16px;color:#111827;font-size:16px;font-weight:600;">
                          You've been invited to join {orgName}!
                        </p>
                        <p style="margin:0 0 28px;color:#4b5563;font-size:14px;line-height:1.6;">
                          <strong>{inviterName}</strong> has invited you to become a member of <strong>{orgName}</strong> on RippleHub.
                        </p>
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                          <tr>
                            <td align="center" style="padding:8px 0 28px;">
                              <a href="{inviteLink}" target="_blank"
                                 style="display:inline-block;background:#1a56db;color:#ffffff;text-decoration:none;
                                        font-size:15px;font-weight:600;padding:14px 36px;border-radius:8px;">
                                Accept Invitation
                              </a>
                            </td>
                          </tr>
                        </table>
                        <p style="margin:0;color:#6b7280;font-size:12px;">
                          Or copy this link: <a href="{inviteLink}" style="color:#1a56db;">{inviteLink}</a>
                        </p>
                        <p style="margin:16px 0 0;color:#9ca3af;font-size:12px;">This invitation expires in 30 days.</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="background:#f9fafb;padding:20px 40px;border-top:1px solid #e5e7eb;text-align:center;">
                        <p style="margin:0;color:#9ca3af;font-size:11px;">
                          © {DateTime.UtcNow.Year} RippleHub — This is an automated message. Do not reply.
                        </p>
                      </td>
                    </tr>
                  </table>
                </td></tr>
              </table>
            </body>
            </html>
            """;

        public async Task<bool> SendSupportEmailAsync(
            string contactName,
            string categoryLabel,
            string subject,
            string description,
            string contactEmail,
            string? attachmentUrl = null)
        {
            try
            {
                var host           = _config["Email:SmtpHost"]       ?? throw new InvalidOperationException("Email:SmtpHost not configured");
                var port           = int.Parse(_config["Email:SmtpPort"] ?? "587");
                var username       = _config["Email:SmtpUsername"]   ?? throw new InvalidOperationException("Email:SmtpUsername not configured");
                var password       = _config["Email:SmtpPassword"]   ?? throw new InvalidOperationException("Email:SmtpPassword not configured");
                var fromAddress    = _config["Email:FromAddress"]    ?? "no-reply@ripplehub.app";
                var fromName       = _config["Email:FromName"]       ?? "RippleHub";
                var supportAddress = _config["Email:SupportAddress"] ?? "support@ripplehub.app";
                var useSsl         = bool.Parse(_config["Email:UseSsl"] ?? "false");

                var message = new MimeMessage();
                message.From.Add(new MailboxAddress(fromName, fromAddress));
                message.To.Add(MailboxAddress.Parse(supportAddress));
                message.ReplyTo.Add(new MailboxAddress(contactName, contactEmail));
                message.Subject = $"[Support] [{categoryLabel}] {subject}";

                var bodyBuilder = new BodyBuilder
                {
                    HtmlBody = BuildSupportHtml(contactName, categoryLabel, subject, description, contactEmail, attachmentUrl),
                    TextBody = $"Support Request\n\nFrom: {contactName} <{contactEmail}>\nCategory: {categoryLabel}\nSubject: {subject}\n\n{description}"
                             + (attachmentUrl is not null ? $"\n\nAttachment: {attachmentUrl}" : "")
                };
                message.Body = bodyBuilder.ToMessageBody();

                using var client = new SmtpClient();
                client.Timeout = 8_000;
                var socketOptions = useSsl ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
                await client.ConnectAsync(host, port, socketOptions);
                await client.AuthenticateAsync(username, password);
                await client.SendAsync(message);
                await client.DisconnectAsync(true);

                Log.Information("Support email sent from {Email}, Category={Category}", MaskEmail(contactEmail), categoryLabel);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SmtpEmailService failed to send support email from {Email}", MaskEmail(contactEmail));
                return false;
            }
        }

        private static string BuildSupportHtml(
            string contactName, string categoryLabel, string subject,
            string description, string contactEmail, string? attachmentUrl = null) => $"""
            <!DOCTYPE html>
            <html lang="en">
            <head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/>
            <title>Support Request — {subject}</title></head>
            <body style="margin:0;padding:0;background:#f0f4f8;font-family:Arial,Helvetica,sans-serif;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f0f4f8;padding:40px 0;">
                <tr><td align="center">
                  <table width="560" cellpadding="0" cellspacing="0" border="0"
                         style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
                    <tr>
                      <td style="background:#1a56db;padding:28px 40px;text-align:center;">
                        <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:700;">RippleHub — Support Request</h1>
                        <p style="margin:6px 0 0;color:#bfdbfe;font-size:12px;">Incoming from the RippleHub app</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:32px 40px;">
                        <!-- Category badge -->
                        <div style="display:inline-block;background:#eff6ff;border:1px solid #bfdbfe;
                                    border-radius:20px;padding:4px 14px;margin-bottom:20px;">
                          <span style="color:#1a56db;font-size:12px;font-weight:600;">{categoryLabel}</span>
                        </div>
                        <h2 style="margin:0 0 20px;color:#111827;font-size:17px;font-weight:700;">{subject}</h2>
                        <!-- Details table -->
                        <table width="100%" cellpadding="0" cellspacing="0" border="0"
                               style="background:#f9fafb;border-radius:8px;padding:0;margin-bottom:24px;">
                          <tr>
                            <td style="padding:12px 16px;border-bottom:1px solid #e5e7eb;">
                              <span style="color:#6b7280;font-size:12px;font-weight:600;">FROM</span><br/>
                              <span style="color:#111827;font-size:14px;">{contactName}</span>
                            </td>
                          </tr>
                          <tr>
                            <td style="padding:12px 16px;">
                              <span style="color:#6b7280;font-size:12px;font-weight:600;">EMAIL</span><br/>
                              <a href="mailto:{contactEmail}" style="color:#1a56db;font-size:14px;text-decoration:none;">{contactEmail}</a>
                            </td>
                          </tr>
                        </table>
                        <!-- Description -->
                        <p style="margin:0 0 8px;color:#6b7280;font-size:12px;font-weight:600;">MESSAGE</p>
                        <div style="background:#f9fafb;border-left:4px solid #1a56db;border-radius:4px;
                                    padding:16px;color:#374151;font-size:14px;line-height:1.7;white-space:pre-wrap;">{description}</div>
                        {(attachmentUrl is not null ? $@"<div style=""margin:20px 0 0;padding:14px 16px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;"">
                          <p style=""margin:0 0 6px;color:#6b7280;font-size:12px;font-weight:600;"">📎 ATTACHMENT</p>
                          <a href=""{attachmentUrl}"" target=""_blank"" style=""color:#1a56db;font-size:13px;word-break:break-all;text-decoration:none;"">{attachmentUrl}</a>
                        </div>" : "")}
                        <p style="margin:24px 0 0;color:#9ca3af;font-size:12px;">
                          💡 Hit Reply to respond directly to <strong>{contactName}</strong> at {contactEmail}
                        </p>
                      </td>
                    </tr>
                    <tr>
                      <td style="background:#f9fafb;padding:16px 40px;border-top:1px solid #e5e7eb;text-align:center;">
                        <p style="margin:0;color:#9ca3af;font-size:11px;">
                          © {DateTime.UtcNow.Year} RippleHub — Internal support notification
                        </p>
                      </td>
                    </tr>
                  </table>
                </td></tr>
              </table>
            </body>
            </html>
            """;

        // v5.0 NEW: Marketing & Communication Center, Phase 1 — arbitrary campaign email
        public async Task<bool> SendCampaignEmailAsync(string toEmail, string subject, string htmlBody)
        {
            try
            {
                var host        = _config["Email:SmtpHost"]     ?? throw new InvalidOperationException("Email:SmtpHost not configured");
                var port        = int.Parse(_config["Email:SmtpPort"] ?? "587");
                var username    = _config["Email:SmtpUsername"] ?? throw new InvalidOperationException("Email:SmtpUsername not configured");
                var password    = _config["Email:SmtpPassword"] ?? throw new InvalidOperationException("Email:SmtpPassword not configured");
                var fromAddress = _config["Email:FromAddress"]  ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]     ?? "RippleHub";
                var useSsl      = bool.Parse(_config["Email:UseSsl"] ?? "false");

                var message = new MimeMessage();
                message.From.Add(new MailboxAddress(fromName, fromAddress));
                message.To.Add(MailboxAddress.Parse(toEmail));
                message.Subject = subject;
                message.Body = new BodyBuilder { HtmlBody = htmlBody }.ToMessageBody();

                using var client = new SmtpClient();
                client.Timeout = 8_000;
                var socketOptions = useSsl ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
                await client.ConnectAsync(host, port, socketOptions);
                await client.AuthenticateAsync(username, password);
                await client.SendAsync(message);
                await client.DisconnectAsync(true);

                Log.Information("Campaign email sent to {Email}", MaskEmail(toEmail));
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SmtpEmailService failed to send campaign email to {Email}", MaskEmail(toEmail));
                return false;
            }
        }

        private static string MaskEmail(string email)
        {
            var parts = email.Split('@');
            if (parts.Length != 2) return "****";
            var masked = parts[0].Length > 2 ? parts[0][..2] + "****" : "****";
            return $"{masked}@{parts[1]}";
        }
    }
}

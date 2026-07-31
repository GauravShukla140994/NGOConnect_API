using Amazon;
using Amazon.Runtime;
using Amazon.SimpleEmailV2;
using Amazon.SimpleEmailV2.Model;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Sends transactional emails via AWS SES v2 SDK.
    /// Reuses the same AWS credentials (AccessKeyId / SecretAccessKey / Region)
    /// already configured for S3 — no separate SMTP credentials needed.
    ///
    /// Config keys (shared with S3):
    ///   AWS:Region           — e.g. ap-south-1
    ///   AWS:AccessKeyId      — IAM key (must have ses:SendEmail permission)
    ///   AWS:SecretAccessKey  — IAM secret
    ///   Email:FromAddress    — e.g. no-reply@ripplehub.app  (must be SES-verified)
    ///   Email:FromName       — Display name e.g. RippleHub
    ///
    /// Railway env vars (double underscore = colon in ASP.NET Core):
    ///   AWS__AccessKeyId / AWS__SecretAccessKey / AWS__Region
    ///   Email__FromAddress  / Email__FromName
    /// </summary>
    public class AwsSesEmailService : IEmailService
    {
        private readonly IConfiguration _config;

        public AwsSesEmailService(IConfiguration config)
        {
            _config = config;
        }

        public async Task<bool> SendOtpAsync(string toEmail, string otpCode, int expiryMinutes)
        {
            try
            {
                var region      = _config["AWS:Region"]          ?? "ap-south-1";
                var accessKey   = _config["AWS:AccessKeyId"]     ?? throw new InvalidOperationException("AWS:AccessKeyId not configured");
                var secretKey   = _config["AWS:SecretAccessKey"] ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured");
                var fromAddress = _config["Email:FromAddress"]   ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]      ?? "RippleHub";

                var credentials = new BasicAWSCredentials(accessKey, secretKey);
                var sesRegion   = RegionEndpoint.GetBySystemName(region);

                using var client = new AmazonSimpleEmailServiceV2Client(credentials, sesRegion);

                var request = new SendEmailRequest
                {
                    FromEmailAddress = $"{fromName} <{fromAddress}>",
                    Destination = new Destination
                    {
                        ToAddresses = new List<string> { toEmail }
                    },
                    Content = new EmailContent
                    {
                        Simple = new Message
                        {
                            Subject = new Content
                            {
                                Data    = $"{otpCode} is your RippleHub verification code",
                                Charset = "UTF-8"
                            },
                            Body = new Body
                            {
                                Html = new Content
                                {
                                    Data    = BuildOtpHtml(otpCode, expiryMinutes),
                                    Charset = "UTF-8"
                                },
                                Text = new Content
                                {
                                    Data    = $"Your RippleHub verification code is: {otpCode}\n\nThis code expires in {expiryMinutes} minutes.\n\nIf you did not request this, please ignore this email.",
                                    Charset = "UTF-8"
                                }
                            }
                        }
                    }
                };

                await client.SendEmailAsync(request);
                Log.Information("OTP email sent via AWS SES to {Email}", MaskEmail(toEmail));
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsSesEmailService failed to send OTP to {Email}", MaskEmail(toEmail));
                return false;
            }
        }

        // ── HTML Email Template (identical to SmtpEmailService) ──────────────
        private static string BuildOtpHtml(string otpCode, int expiryMinutes) => $"""
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
                          <img src="data:image/png;base64,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" alt="RippleHub" width="64" height="64" style="display:block;margin:0 auto 12px;border-radius:14px;" />
                          <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.5px;">RippleHub</h1>
                          <p style="margin:6px 0 0;color:#93c5fd;font-size:13px;">The LinkedIn of Social Impact</p>
                        </td>
                      </tr>

                      <!-- Body -->
                      <tr>
                        <td style="padding:40px 40px 32px;">
                          <p style="margin:0 0 8px;color:#111827;font-size:15px;">Hello,</p>
                          <p style="margin:0 0 28px;color:#4b5563;font-size:14px;line-height:1.6;">
                            Use the verification code below to complete your sign-in.
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
                var region      = _config["AWS:Region"]          ?? "ap-south-1";
                var accessKey   = _config["AWS:AccessKeyId"]     ?? throw new InvalidOperationException("AWS:AccessKeyId not configured");
                var secretKey   = _config["AWS:SecretAccessKey"] ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured");
                var fromAddress = _config["Email:FromAddress"]   ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]      ?? "RippleHub";

                var credentials = new BasicAWSCredentials(accessKey, secretKey);
                var sesRegion   = RegionEndpoint.GetBySystemName(region);
                using var client = new AmazonSimpleEmailServiceV2Client(credentials, sesRegion);

                var request = new SendEmailRequest
                {
                    FromEmailAddress = $"{fromName} <{fromAddress}>",
                    Destination = new Destination { ToAddresses = new List<string> { toEmail } },
                    Content = new EmailContent
                    {
                        Simple = new Message
                        {
                            Subject = new Content
                            {
                                Data    = $"{inviterName} invited you to join {orgName} on RippleHub",
                                Charset = "UTF-8"
                            },
                            Body = new Body
                            {
                                Html = new Content { Data = BuildInviteHtml(inviterName, orgName, inviteLink), Charset = "UTF-8" },
                                Text = new Content
                                {
                                    Data    = $"{inviterName} has invited you to join {orgName} on RippleHub.\n\nAccept the invitation: {inviteLink}\n\nThis link expires in 30 days.",
                                    Charset = "UTF-8"
                                }
                            }
                        }
                    }
                };

                await client.SendEmailAsync(request);
                Log.Information("Invite email sent via AWS SES to {Email} for Org={OrgName}", MaskEmail(toEmail), orgName);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsSesEmailService failed to send invite to {Email}", MaskEmail(toEmail));
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
                        <p style="margin:6px 0 0;color:#bfdbfe;font-size:13px;">The LinkedIn of Social Impact</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:40px;">
                        <p style="margin:0 0 16px;color:#111827;font-size:16px;font-weight:600;">
                          You've been invited to join {orgName}!
                        </p>
                        <p style="margin:0 0 28px;color:#4b5563;font-size:14px;line-height:1.6;">
                          <strong>{inviterName}</strong> has invited you to become a member of <strong>{orgName}</strong> on RippleHub.
                          Click the button below to view the organisation and accept the invitation.
                        </p>
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                          <tr>
                            <td align="center" style="padding:8px 0 32px;">
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
                        <p style="margin:0;color:#9ca3af;font-size:11px;line-height:1.6;">
                          © {DateTime.UtcNow.Year} RippleHub — RippleHub Pvt. Ltd.<br/>
                          This is an automated message. Please do not reply to this email.
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
                var region         = _config["AWS:Region"]           ?? "ap-south-1";
                var accessKey      = _config["AWS:AccessKeyId"]      ?? throw new InvalidOperationException("AWS:AccessKeyId not configured");
                var secretKey      = _config["AWS:SecretAccessKey"]  ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured");
                var fromAddress    = _config["Email:FromAddress"]    ?? "no-reply@ripplehub.app";
                var fromName       = _config["Email:FromName"]       ?? "RippleHub";
                var supportAddress = _config["Email:SupportAddress"] ?? "support@ripplehub.app";

                var credentials = new BasicAWSCredentials(accessKey, secretKey);
                var sesRegion   = RegionEndpoint.GetBySystemName(region);
                using var client = new AmazonSimpleEmailServiceV2Client(credentials, sesRegion);

                var request = new SendEmailRequest
                {
                    FromEmailAddress    = $"{fromName} <{fromAddress}>",
                    ReplyToAddresses    = new List<string> { $"{contactName} <{contactEmail}>" },
                    Destination         = new Destination { ToAddresses = new List<string> { supportAddress } },
                    Content = new EmailContent
                    {
                        Simple = new Message
                        {
                            Subject = new Content
                            {
                                Data    = $"[Support] [{categoryLabel}] {subject}",
                                Charset = "UTF-8"
                            },
                            Body = new Body
                            {
                                Html = new Content { Data = BuildSupportHtml(contactName, categoryLabel, subject, description, contactEmail, attachmentUrl), Charset = "UTF-8" },
                                Text = new Content
                                {
                                    Data    = $"Support Request\n\nFrom: {contactName} <{contactEmail}>\nCategory: {categoryLabel}\nSubject: {subject}\n\n{description}"
                                           + (attachmentUrl is not null ? $"\n\nAttachment: {attachmentUrl}" : ""),
                                    Charset = "UTF-8"
                                }
                            }
                        }
                    }
                };

                await client.SendEmailAsync(request);
                Log.Information("Support email sent via AWS SES from {Email}, Category={Category}", MaskEmail(contactEmail), categoryLabel);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsSesEmailService failed to send support email from {Email}", MaskEmail(contactEmail));
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
                        <div style="display:inline-block;background:#eff6ff;border:1px solid #bfdbfe;
                                    border-radius:20px;padding:4px 14px;margin-bottom:20px;">
                          <span style="color:#1a56db;font-size:12px;font-weight:600;">{categoryLabel}</span>
                        </div>
                        <h2 style="margin:0 0 20px;color:#111827;font-size:17px;font-weight:700;">{subject}</h2>
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
                var region      = _config["AWS:Region"]          ?? "ap-south-1";
                var accessKey   = _config["AWS:AccessKeyId"]     ?? throw new InvalidOperationException("AWS:AccessKeyId not configured");
                var secretKey   = _config["AWS:SecretAccessKey"] ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured");
                var fromAddress = _config["Email:FromAddress"]   ?? "no-reply@ripplehub.app";
                var fromName    = _config["Email:FromName"]      ?? "RippleHub";

                var credentials = new BasicAWSCredentials(accessKey, secretKey);
                var sesRegion   = RegionEndpoint.GetBySystemName(region);
                using var client = new AmazonSimpleEmailServiceV2Client(credentials, sesRegion);

                var request = new SendEmailRequest
                {
                    FromEmailAddress = $"{fromName} <{fromAddress}>",
                    Destination = new Destination { ToAddresses = new List<string> { toEmail } },
                    Content = new EmailContent
                    {
                        Simple = new Message
                        {
                            Subject = new Content { Data = subject, Charset = "UTF-8" },
                            Body = new Body
                            {
                                Html = new Content { Data = htmlBody, Charset = "UTF-8" }
                            }
                        }
                    }
                };

                await client.SendEmailAsync(request);
                Log.Information("Campaign email sent via AWS SES to {Email}", MaskEmail(toEmail));
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsSesEmailService failed to send campaign email to {Email}", MaskEmail(toEmail));
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

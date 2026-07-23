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
                        <td style="background:#1a56db;padding:32px 40px;text-align:center;">
                          <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700;letter-spacing:0.5px;">
                            RippleHub
                          </h1>
                          <p style="margin:6px 0 0;color:#bfdbfe;font-size:13px;">The LinkedIn of Social Impact</p>
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

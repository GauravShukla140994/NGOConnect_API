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

        private static string MaskEmail(string email)
        {
            var parts = email.Split('@');
            if (parts.Length != 2) return "****";
            var masked = parts[0].Length > 2 ? parts[0][..2] + "****" : "****";
            return $"{masked}@{parts[1]}";
        }
    }
}

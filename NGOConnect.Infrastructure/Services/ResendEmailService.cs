using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Sends transactional emails via the Resend HTTP API (https://resend.com).
    ///
    /// Why Resend instead of SMTP:
    ///   Railway (and most PaaS platforms) block outbound SMTP ports (25, 465, 587).
    ///   Resend uses HTTPS so it is never blocked. Deliverability is production-grade.
    ///
    /// Config keys:
    ///   Resend:ApiKey        — API key from resend.com dashboard  ← SECRET: gitignored / Railway env var
    ///   Email:FromAddress    — Sender address  e.g. no-reply@ripplehub.app
    ///   Email:FromName       — Display name    e.g. RippleHub
    ///   Email:SupportAddress — Support inbox   e.g. support@ripplehub.app
    ///
    /// Railway env vars:
    ///   Resend__ApiKey        (double underscore = nested section)
    ///   EmailProvider = resend
    /// </summary>
    public class ResendEmailService : IEmailService
    {
        private readonly HttpClient      _http;
        private readonly IConfiguration _config;

        private const string ApiUrl = "https://api.resend.com/emails";

        public ResendEmailService(HttpClient http, IConfiguration config)
        {
            _http   = http;
            _config = config;

            var apiKey = config["Resend:ApiKey"]
                ?? throw new InvalidOperationException("Resend:ApiKey not configured. Set it in appsettings.Development.json or Railway env var Resend__ApiKey.");

            _http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", apiKey);
        }

        // ── IEmailService ────────────────────────────────────────────────────────

        public Task<bool> SendOtpAsync(string toEmail, string otpCode, int expiryMinutes, string purpose = "verification")
        {
            var from    = BuildFrom();
            var subject = $"{otpCode} is your RippleHub verification code";

            return SendAsync(
                from:    from,
                to:      [toEmail],
                subject: subject,
                html:    SmtpEmailService.BuildOtpHtmlInternal(otpCode, expiryMinutes, purpose),
                text:    $"{otpCode} is your OTP for RippleHub {purpose}. It is valid for {expiryMinutes} minutes. Do not share this OTP with anyone.",
                context: $"OTP to {MaskEmail(toEmail)}");
        }

        public Task<bool> SendInviteAsync(
            string toEmail, string inviterName, string orgName, string inviteLink)
        {
            var from    = BuildFrom();
            var subject = $"{inviterName} invited you to join {orgName} on RippleHub";

            var logoUrl = _config["Platform:LogoUrl"];
            return SendAsync(
                from:    from,
                to:      [toEmail],
                subject: subject,
                html:    SmtpEmailService.BuildInviteHtmlInternal(inviterName, orgName, inviteLink, logoUrl),
                text:    $"{inviterName} invited you to join {orgName} on RippleHub.\n\nAccept: {inviteLink}",
                context: $"Invite to {MaskEmail(toEmail)} for {orgName}");
        }

        public Task<bool> SendSupportEmailAsync(
            string contactName, string categoryLabel, string subject,
            string description, string contactEmail, string? attachmentUrl = null)
        {
            var from           = BuildFrom();
            var supportAddress = _config["Email:SupportAddress"] ?? "support@ripplehub.app";

            return SendAsync(
                from:     from,
                to:       [supportAddress],
                subject:  $"[Support] [{categoryLabel}] {subject}",
                html:     SmtpEmailService.BuildSupportHtmlInternal(contactName, categoryLabel, subject, description, contactEmail, attachmentUrl),
                text:     $"Support Request\n\nFrom: {contactName} <{contactEmail}>\nCategory: {categoryLabel}\nSubject: {subject}\n\n{description}",
                replyTo:  contactEmail,
                context:  $"Support from {MaskEmail(contactEmail)}");
        }

        public Task<bool> SendCampaignEmailAsync(string toEmail, string subject, string htmlBody)
        {
            return SendAsync(
                from:    BuildFrom(),
                to:      [toEmail],
                subject: subject,
                html:    htmlBody,
                context: $"Campaign to {MaskEmail(toEmail)}");
        }

        // ── Core HTTP send ───────────────────────────────────────────────────────

        private async Task<bool> SendAsync(
            string   from,
            string[] to,
            string   subject,
            string   html,
            string?  text    = null,
            string?  replyTo = null,
            string   context = "email")
        {
            try
            {
                var payload = new Dictionary<string, object?>
                {
                    ["from"]    = from,
                    ["to"]      = to,
                    ["subject"] = subject,
                    ["html"]    = html
                };

                if (text    is not null) payload["text"]     = text;
                if (replyTo is not null) payload["reply_to"] = replyTo;

                var json    = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var response = await _http.PostAsync(ApiUrl, content);
                var body     = await response.Content.ReadAsStringAsync();

                if (response.IsSuccessStatusCode)
                {
                    Log.Information("ResendEmailService: sent {Context}", context);
                    return true;
                }

                Log.Error("ResendEmailService: API error {Status} for {Context} — {Body}",
                    (int)response.StatusCode, context, body);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ResendEmailService: exception sending {Context}", context);
                return false;
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────────────

        private string BuildFrom()
        {
            var address = _config["Email:FromAddress"] ?? "no-reply@ripplehub.app";
            var name    = _config["Email:FromName"]    ?? "RippleHub";
            return $"{name} <{address}>";
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

using System.Text.Json;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Fast2SMS gateway — implements ISmsService for India SMS delivery.
    /// Uses the Quick route (no DLT registration required for testing).
    ///
    /// Docs: https://docs.fast2sms.com
    /// Route: Quick ("q") — works immediately, no sender ID / template needed.
    ///        Switch to DLT route before going to production (TRAI mandate).
    ///
    /// Config keys (appsettings.json → "Sms" section):
    ///   Sms:ApiKey       — Fast2SMS API key (never commit; use env var / gitignored file)
    ///   Sms:Route        — "q" (quick/test) | "dlt" (production)
    ///   Sms:SenderId     — Required only for DLT route (registered sender ID)
    ///   Sms:TemplateId   — Required only for DLT route (TRAI-registered template ID)
    ///
    /// Railway env var: Sms__ApiKey
    /// </summary>
    public class Fast2SmsService : ISmsService
    {
        private readonly HttpClient _http;
        private readonly string     _apiKey;
        private readonly string     _route;
        private readonly string?    _senderId;
        private readonly string?    _templateId;

        private const string ApiUrl = "https://www.fast2sms.com/dev/bulkV2";

        public Fast2SmsService(HttpClient http, IConfiguration config)
        {
            _http       = http;
            _apiKey     = config["Sms:ApiKey"]
                ?? throw new InvalidOperationException("Sms:ApiKey not configured.");
            _route      = (config["Sms:Route"] ?? "q").Trim().ToLowerInvariant();
            _senderId   = config["Sms:SenderId"];
            _templateId = config["Sms:TemplateId"];
        }

        public async Task<bool> SendOtpAsync(
            string mobile, string countryCode, string otpCode, int expiryMinutes)
        {
            try
            {
                // Strip leading zeros, spaces, and country code prefix if included
                var cleanMobile = CleanMobile(mobile, countryCode);

                var formData = BuildFormData(cleanMobile, otpCode, expiryMinutes);

                using var request = new HttpRequestMessage(HttpMethod.Post, ApiUrl)
                {
                    Content = new FormUrlEncodedContent(formData)
                };
                request.Headers.TryAddWithoutValidation("authorization", _apiKey);
                request.Headers.TryAddWithoutValidation("cache-control", "no-cache");

                var response = await _http.SendAsync(request);
                var body     = await response.Content.ReadAsStringAsync();

                Log.Debug("Fast2SMS response: Status={Status} Body={Body}",
                    response.StatusCode, body);

                var result = JsonDocument.Parse(body).RootElement;

                if (result.TryGetProperty("return", out var ret) && ret.GetBoolean())
                {
                    Log.Information("SMS OTP sent via Fast2SMS: Mobile={Mobile} Route={Route}",
                        MaskMobile(cleanMobile), _route);
                    return true;
                }

                // Log the gateway error message for debugging
                var errorMsg = result.TryGetProperty("message", out var msg)
                    ? msg.ToString()
                    : "Unknown gateway error";

                Log.Warning("Fast2SMS rejected OTP delivery: Mobile={Mobile} Error={Error}",
                    MaskMobile(cleanMobile), errorMsg);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Fast2SmsService.SendOtpAsync failed for Mobile={Mobile}",
                    MaskMobile(mobile));
                return false;
            }
        }

        // ── Helpers ───────────────────────────────────────────────

        private Dictionary<string, string> BuildFormData(
            string mobile, string otpCode, int expiryMinutes)
        {
            if (_route == "dlt")
            {
                // DLT route — production, requires registered sender + template
                if (string.IsNullOrWhiteSpace(_senderId) || string.IsNullOrWhiteSpace(_templateId))
                    throw new InvalidOperationException(
                        "Sms:SenderId and Sms:TemplateId are required for DLT route.");

                return new Dictionary<string, string>
                {
                    ["route"]            = "dlt",
                    ["sender_id"]        = _senderId!,
                    ["message"]          = _templateId!,   // template ID for DLT
                    ["variables_values"] = otpCode,        // replaces {#var#} in template
                    ["flash"]            = "0",
                    ["numbers"]          = mobile
                };
            }
            else
            {
                // Quick route — testing / staging (no DLT registration needed)
                // Same wording as the DLT template so the user experience is consistent
                var message =
                    $"Your OTP for RippleHub is {otpCode}. Valid for {expiryMinutes} minutes. Do not share. - RPPLHB";

                return new Dictionary<string, string>
                {
                    ["route"]    = "q",
                    ["message"]  = message,
                    ["language"] = "english",
                    ["flash"]    = "0",
                    ["numbers"]  = mobile
                };
            }
        }

        private static string CleanMobile(string mobile, string countryCode)
        {
            // Remove spaces, dashes
            var clean = mobile.Replace(" ", "").Replace("-", "").Trim();

            // If number starts with country code (+91 or 91), strip it
            var code = countryCode.TrimStart('+');
            if (clean.StartsWith('+'))
                clean = clean[1..];
            if (clean.StartsWith(code))
                clean = clean[code.Length..];

            return clean;
        }

        public async Task<bool> SendAsync(string mobile, string countryCode, string message)
        {
            try
            {
                var cleanMobile = CleanMobile(mobile, countryCode);

                var formData = new Dictionary<string, string>
                {
                    ["route"]    = "q",
                    ["message"]  = message,
                    ["language"] = "english",
                    ["flash"]    = "0",
                    ["numbers"]  = cleanMobile
                };

                using var request = new HttpRequestMessage(HttpMethod.Post, ApiUrl)
                {
                    Content = new FormUrlEncodedContent(formData)
                };
                request.Headers.TryAddWithoutValidation("authorization", _apiKey);
                request.Headers.TryAddWithoutValidation("cache-control", "no-cache");

                var response = await _http.SendAsync(request);
                var body     = await response.Content.ReadAsStringAsync();
                var result   = System.Text.Json.JsonDocument.Parse(body).RootElement;

                if (result.TryGetProperty("return", out var ret) && ret.GetBoolean())
                {
                    Log.Information("SMS sent via Fast2SMS: Mobile={Mobile}", MaskMobile(cleanMobile));
                    return true;
                }

                var errorMsg = result.TryGetProperty("message", out var msg) ? msg.ToString() : "Unknown error";
                Log.Warning("Fast2SMS rejected SMS: Mobile={Mobile} Error={Error}", MaskMobile(cleanMobile), errorMsg);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Fast2SmsService.SendAsync failed for Mobile={Mobile}", MaskMobile(mobile));
                return false;
            }
        }

        private static string MaskMobile(string mobile) =>
            mobile.Length > 4
                ? new string('*', mobile.Length - 4) + mobile[^4..]
                : "****";
    }
}

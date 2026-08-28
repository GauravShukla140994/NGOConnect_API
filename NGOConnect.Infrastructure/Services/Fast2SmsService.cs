using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Fast2SMS gateway — implements ISmsService for India SMS delivery.
    ///
    /// Two delivery paths, selected by Sms:Route:
    ///   "q"   → Quick route (bulkV2, plain text message) — testing only, no DLT needed.
    ///   "dlt" → Dedicated OTP API (/dev/otp/send) — production, TRAI-compliant.
    ///           This is Fast2SMS's purpose-built OTP endpoint (separate from the
    ///           generic DLT bulk/"message=templateId" approach this file used
    ///           before 2026-08-18) — it handles OTP length/expiry natively and is
    ///           what Fast2SMS's own docs recommend for an approved OTP template.
    ///
    /// Docs: https://docs.fast2sms.com/reference/send-otp
    ///
    /// Config keys (appsettings.json → "Sms" section):
    ///   Sms:ApiKey        — Fast2SMS API key (never commit; use env var / gitignored file)
    ///   Sms:Route         — "q" (quick/test) | "dlt" (production)
    ///   Sms:SenderId        — Required for DLT route (registered sender ID / header, e.g. "AJIEPL")
    ///   Sms:OtpTemplateId   — DLT route only — Fast2SMS's OTP Template ID ("otp_id" in their
    ///                         API, a short hash e.g. "f7c2df256e"). Find this under Fast2SMS → OTP
    ///                         for your approved template, NOT the DLT Manager numeric Message ID.
    ///   Sms:InviteTemplateId — DLT Message ID for the org-invite template (e.g. "223944").
    ///                         Used by SendTemplateAsync when sending invitation SMS.
    ///   Sms:TemplateId      — Reserved for future generic/bulk DLT SMS; not used by any
    ///                         current method.
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
        private readonly string?    _otpTemplateId;
        private readonly string?    _inviteTemplateId;

        private const string BulkApiUrl = "https://www.fast2sms.com/dev/bulkV2";
        private const string OtpApiUrl  = "https://www.fast2sms.com/dev/otp/send";

        public Fast2SmsService(HttpClient http, IConfiguration config)
        {
            _http              = http;
            _apiKey            = config["Sms:ApiKey"]
                ?? throw new InvalidOperationException("Sms:ApiKey not configured.");
            _route             = (config["Sms:Route"] ?? "q").Trim().ToLowerInvariant();
            _senderId          = config["Sms:SenderId"];
            _templateId        = config["Sms:TemplateId"];
            _otpTemplateId     = config["Sms:OtpTemplateId"];
            _inviteTemplateId  = config["Sms:InviteTemplateId"];
        }

        public async Task<bool> SendOtpAsync(
            string mobile, string countryCode, string otpCode, int expiryMinutes)
        {
            // Strip leading zeros, spaces, and country code prefix if included
            var cleanMobile = CleanMobile(mobile, countryCode);

            // Fast2SMS's OTP API requires exactly a 10-digit Indian number (^[0-9]{10}$).
            // Catch a malformed number here with a clear log line instead of letting
            // Fast2SMS reject it with a less obvious error.
            if (cleanMobile.Length != 10 || !cleanMobile.All(char.IsDigit))
                Log.Warning("Fast2SmsService.SendOtpAsync: mobile did not clean to a 10-digit " +
                    "number (Mobile={Mobile} CountryCode={CountryCode}) — Fast2SMS will likely reject this.",
                    MaskMobile(cleanMobile), countryCode);

            return _route == "dlt"
                ? await SendOtpViaDedicatedApiAsync(cleanMobile, otpCode, expiryMinutes)
                : await SendOtpViaQuickRouteAsync(cleanMobile, otpCode, expiryMinutes);
        }

        // ── DLT route — dedicated OTP API (production) ──────────────

        private async Task<bool> SendOtpViaDedicatedApiAsync(
            string mobile, string otpCode, int expiryMinutes)
        {
            if (string.IsNullOrWhiteSpace(_otpTemplateId))
                throw new InvalidOperationException(
                    "Sms:OtpTemplateId is required for the DLT route (Fast2SMS OTP Template ID / otp_id).");

            try
            {
                var payload = new
                {
                    mobile,
                    otp_id           = _otpTemplateId,
                    otp_expiry       = expiryMinutes,
                    otp_length       = otpCode.Length,
                    otp              = otpCode,       // we generate/verify our own OTP — Fast2SMS just delivers it
                    variables_values = otpCode,        // single {#var#} in the approved template
                };

                using var request = new HttpRequestMessage(HttpMethod.Post, OtpApiUrl)
                {
                    Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json")
                };
                request.Headers.TryAddWithoutValidation("authorization", _apiKey);

                var response = await _http.SendAsync(request);
                var body     = await response.Content.ReadAsStringAsync();

                Log.Debug("Fast2SMS OTP API response: Status={Status} Body={Body}",
                    response.StatusCode, body);

                var result = JsonDocument.Parse(body).RootElement;

                if (result.TryGetProperty("return", out var ret) && ret.GetBoolean())
                {
                    Log.Information("SMS OTP sent via Fast2SMS (DLT/OTP API): Mobile={Mobile}",
                        MaskMobile(mobile));
                    return true;
                }

                var errorMsg = result.TryGetProperty("message", out var msg)
                    ? msg.ToString()
                    : "Unknown gateway error";

                Log.Warning("Fast2SMS rejected OTP delivery (DLT/OTP API): Mobile={Mobile} Error={Error}",
                    MaskMobile(mobile), errorMsg);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Fast2SmsService.SendOtpViaDedicatedApiAsync failed for Mobile={Mobile}",
                    MaskMobile(mobile));
                return false;
            }
        }

        // ── Quick route — testing / staging (no DLT registration needed) ─────

        private async Task<bool> SendOtpViaQuickRouteAsync(
            string mobile, string otpCode, int expiryMinutes)
        {
            try
            {
                // Same wording as the DLT template so the user experience is consistent
                var message =
                    $"Your OTP for RippleHub is {otpCode}. Valid for {expiryMinutes} minutes. Do not share. - RPPLHB";

                var formData = new Dictionary<string, string>
                {
                    ["route"]    = "q",
                    ["message"]  = message,
                    ["language"] = "english",
                    ["flash"]    = "0",
                    ["numbers"]  = mobile
                };

                using var request = new HttpRequestMessage(HttpMethod.Post, BulkApiUrl)
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
                    Log.Information("SMS OTP sent via Fast2SMS (Quick route): Mobile={Mobile}",
                        MaskMobile(mobile));
                    return true;
                }

                var errorMsg = result.TryGetProperty("message", out var msg)
                    ? msg.ToString()
                    : "Unknown gateway error";

                Log.Warning("Fast2SMS rejected OTP delivery (Quick route): Mobile={Mobile} Error={Error}",
                    MaskMobile(mobile), errorMsg);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Fast2SmsService.SendOtpViaQuickRouteAsync failed for Mobile={Mobile}",
                    MaskMobile(mobile));
                return false;
            }
        }

        // ── Helpers ───────────────────────────────────────────────

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

                using var request = new HttpRequestMessage(HttpMethod.Post, BulkApiUrl)
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

        // ── DLT template SMS ──────────────────────────────────────────

        /// <summary>
        /// Send an SMS using a DLT-registered template (Fast2SMS bulkV2 with route=dlt).
        /// Falls back to a plain-text quick-route message on non-DLT configurations (dev/staging).
        /// </summary>
        public async Task<bool> SendTemplateAsync(
            string mobile, string countryCode,
            string templateId, string senderId,
            string variablesValues, string fallbackMessage)
        {
            try
            {
                var cleanMobile = CleanMobile(mobile, countryCode);

                if (_route == "dlt")
                {
                    // Production path — DLT template via Fast2SMS bulkV2
                    var formData = new Dictionary<string, string>
                    {
                        ["route"]            = "dlt",
                        ["sender_id"]        = senderId,
                        ["message"]          = templateId,      // DLT Message ID (not the body text)
                        ["variables_values"] = variablesValues, // pipe-separated, one per {#VAR#}
                        ["flash"]            = "0",
                        ["numbers"]          = cleanMobile
                    };

                    using var request = new HttpRequestMessage(HttpMethod.Post, BulkApiUrl)
                    {
                        Content = new FormUrlEncodedContent(formData)
                    };
                    request.Headers.TryAddWithoutValidation("authorization", _apiKey);
                    request.Headers.TryAddWithoutValidation("cache-control", "no-cache");

                    var response = await _http.SendAsync(request);
                    var body     = await response.Content.ReadAsStringAsync();

                    Log.Debug("Fast2SMS DLT template response: Status={Status} Body={Body}",
                        response.StatusCode, body);

                    var result = JsonDocument.Parse(body).RootElement;

                    if (result.TryGetProperty("return", out var ret) && ret.GetBoolean())
                    {
                        Log.Information(
                            "SMS template sent via Fast2SMS (DLT): Mobile={Mobile} TemplateId={TemplateId}",
                            MaskMobile(cleanMobile), templateId);
                        return true;
                    }

                    var errorMsg = result.TryGetProperty("message", out var msg)
                        ? msg.ToString()
                        : "Unknown gateway error";

                    Log.Warning(
                        "Fast2SMS rejected DLT template SMS: Mobile={Mobile} TemplateId={TemplateId} Error={Error}",
                        MaskMobile(cleanMobile), templateId, errorMsg);
                    return false;
                }
                else
                {
                    // Dev/staging quick-route fallback — plain text, no DLT registration needed
                    Log.Debug("SendTemplateAsync: quick route active — using fallback plain-text message");
                    return await SendAsync(mobile, countryCode, fallbackMessage);
                }
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Fast2SmsService.SendTemplateAsync failed for Mobile={Mobile}", MaskMobile(mobile));
                return false;
            }
        }

        private static string MaskMobile(string mobile) =>
            mobile.Length > 4
                ? new string('*', mobile.Length - 4) + mobile[^4..]
                : "****";
    }
}

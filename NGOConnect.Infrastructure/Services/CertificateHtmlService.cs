using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using QRCoder;
using System.Net;
using System.Text;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Reads CertificateTemplate.html once at startup, then substitutes
    /// {{PLACEHOLDER}} tokens from the certificate DynamicRow.
    ///
    /// Registered as a Singleton — template is read from disk once, then kept in memory.
    /// All substituted values are HTML-encoded via WebUtility.HtmlEncode to prevent XSS.
    ///
    /// Placeholders in the template:
    ///   {{CERTIFICATE_ID}}      — certCode e.g. CERT-2026-000147
    ///   {{ISSUE_DATE}}          — formatted full date e.g. 1 August 2026
    ///   {{NGO_NAME}}            — organisation name (used twice in template)
    ///   {{VOLUNTEER_NAME}}      — volunteer full name (used twice in template)
    ///   {{PROJECT_NAME}}        — project name
    ///   {{HOURS_CONTRIBUTED}}   — e.g. "16 hrs" or "—" if zero
    ///   {{COMPLETION_DATE}}     — month + year e.g. "Aug 2026"
    ///   {{COORDINATOR_NAME}}    — admin who issued the certificate
    ///   {{SKILL_CHIPS_HTML}}    — pre-built <div class="skill">…</div> fragments
    ///   {{SKILL_CHIPS_STYLE}}   — "" (visible) or "display:none" (no skills)
    ///   {{VERIFY_URL}}          — raw encrypted verify URL (used in href + text)
    ///   {{VERIFY_URL_DISPLAY}}  — verify URL without the https:// scheme prefix
    ///   {{VERIFY_URL_ENCODED}}  — URI-encoded verify URL (kept for legacy refs, no longer in src)
    ///   {{QR_DATA_URI}}         — self-contained PNG data URI for QR code (no external request needed)
    /// </summary>
    public class CertificateHtmlService : ICertificateHtmlService
    {
        private readonly string _template;

        /// <param name="contentRootPath">
        /// Pass IWebHostEnvironment.ContentRootPath from the DI factory registration.
        /// The template is expected at {contentRootPath}/Templates/CertificateTemplate.html.
        /// </param>
        public CertificateHtmlService(string contentRootPath)
        {
            var path = Path.Combine(contentRootPath, "Templates", "CertificateTemplate.html");
            _template = File.ReadAllText(path);
        }

        public string Render(DynamicRow row)
        {
            var certCode        = row.Get<string>("certCode")        ?? "";
            var volunteerName   = row.Get<string>("volunteerName")   ?? "";
            var orgName         = row.Get<string>("orgName")         ?? "";
            var projectName     = row.Get<string>("projectName")     ?? "";
            var coordinatorName = row.Get<string>("coordinatorName") ?? "";
            var skillRatings    = row.Get<string>("skillRatings")    ?? "";
            var verifyUrl       = row.Get<string>("verifyUrl")       ?? "";

            var totalHours = row.Get<decimal>("totalHours");
            var issuedAt   = row.Get<DateTime>("issuedAt");

            var issueDateStr      = issuedAt == default ? "" : issuedAt.ToString("d MMMM yyyy");
            var completionDateStr = issuedAt == default ? "" : issuedAt.ToString("MMM yyyy");
            var hoursStr          = totalHours > 0 ? $"{totalHours} hrs" : "—";

            var verifyDisplay  = verifyUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                                 ? verifyUrl[8..] : verifyUrl;
            var verifyEncoded  = Uri.EscapeDataString(verifyUrl);

            // Generate QR code as self-contained PNG data URI — no external HTTP request needed.
            // PngByteQRCode is platform-independent (no GDI+), safe on Linux/Railway.
            var qrDataUri = BuildQrDataUri(verifyUrl);

            var skillChipsHtml  = BuildSkillChips(skillRatings);
            var skillChipsStyle = string.IsNullOrEmpty(skillChipsHtml) ? "display:none" : "";

            return _template
                .Replace("{{CERTIFICATE_ID}}",    Enc(certCode))
                .Replace("{{ISSUE_DATE}}",         Enc(issueDateStr))
                .Replace("{{NGO_NAME}}",           Enc(orgName))
                .Replace("{{VOLUNTEER_NAME}}",     Enc(volunteerName))
                .Replace("{{PROJECT_NAME}}",       Enc(projectName))
                .Replace("{{HOURS_CONTRIBUTED}}",  Enc(hoursStr))
                .Replace("{{COMPLETION_DATE}}",    Enc(completionDateStr))
                .Replace("{{COORDINATOR_NAME}}",   Enc(coordinatorName))
                .Replace("{{SKILL_CHIPS_HTML}}",   skillChipsHtml)   // already safe HTML built below
                .Replace("{{SKILL_CHIPS_STYLE}}",  skillChipsStyle)
                .Replace("{{VERIFY_URL}}",         Enc(verifyUrl))
                .Replace("{{VERIFY_URL_DISPLAY}}", Enc(verifyDisplay))
                .Replace("{{VERIFY_URL_ENCODED}}", verifyEncoded)
                .Replace("{{QR_DATA_URI}}",        qrDataUri);       // inline PNG, no external requests
        }

        // Generates a self-contained PNG data URI for the given URL.
        // PngByteQRCode uses no GDI+ / System.Drawing — safe on Linux and Railway.
        private static string BuildQrDataUri(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return "";
            using var generator = new QRCodeGenerator();
            var data    = generator.CreateQrCode(url, QRCodeGenerator.ECCLevel.Q);
            var qrCode  = new PngByteQRCode(data);
            // 4 px per module, dark = navy #223b9b, light = white #FFFFFF
            var pngBytes = qrCode.GetGraphic(4,
                darkColorRgba:  [0x22, 0x3B, 0x9B, 0xFF],
                lightColorRgba: [0xFF, 0xFF, 0xFF, 0xFF]);
            return $"data:image/png;base64,{Convert.ToBase64String(pngBytes)}";
        }

        // Builds <div class="skill"> chips from pipe-separated "SkillName:Rating" string.
        // Returns empty string if skillRatings is blank.
        private static string BuildSkillChips(string skillRatings)
        {
            if (string.IsNullOrWhiteSpace(skillRatings)) return "";
            var sb = new StringBuilder();
            foreach (var pair in skillRatings.Split('|'))
            {
                var parts = pair.Split(':', 2);
                if (parts.Length == 2 && decimal.TryParse(parts[1].Trim(),
                        System.Globalization.NumberStyles.Any,
                        System.Globalization.CultureInfo.InvariantCulture,
                        out var rating))
                {
                    sb.Append($"<div class=\"skill\">{Enc(parts[0].Trim())} <b>{rating:0.0} &#9733;</b></div>");
                }
            }
            return sb.ToString();
        }

        private static string Enc(string s) => WebUtility.HtmlEncode(s);
    }
}

using Hangfire.Dashboard;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.API.Hangfire
{
    /// <summary>
    /// Gates access to the /hangfire dashboard (Marketing & Communication Center's
    /// Message Queue view — Phase 0 foundation).
    ///
    /// Always allowed in Development. Outside Development, requires a shared key
    /// (Settings.COMMUNICATION.HANGFIRE_DASHBOARD_KEY) via ?key= query string or an
    /// X-Hangfire-Key header — fails closed (blocks everyone) if that Setting is
    /// still empty, which is the shipped default.
    ///
    /// KNOWN LIMITATION: this is a lightweight shared-secret gate, not a full
    /// SUPER_ADMIN JWT check — Hangfire's dashboard is a non-MVC middleware endpoint
    /// that a browser hits directly, and this API's JWT bearer tokens aren't
    /// something a browser attaches automatically the way a cookie would. Treat the
    /// dashboard key like any other internal-ops credential (share it only with the
    /// platform team) until a fuller auth story is built in Phase 3 (Message Queue
    /// console). See MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    public class HangfireDashboardAuthFilter : IDashboardAuthorizationFilter
    {
        public bool Authorize(DashboardContext context)
        {
            var httpContext = context.GetHttpContext();
            var env = httpContext.RequestServices.GetService<IWebHostEnvironment>();
            if (env is not null && env.IsDevelopment()) return true;

            var settingsCache = httpContext.RequestServices.GetService<ISettingsCache>();
            var configuredKey = settingsCache?.GetValue("HANGFIRE_DASHBOARD_KEY", "") ?? "";
            if (string.IsNullOrEmpty(configuredKey)) return false; // fail closed until an ops key is set

            var providedKey = httpContext.Request.Query["key"].ToString();
            if (string.IsNullOrEmpty(providedKey))
                providedKey = httpContext.Request.Headers["X-Hangfire-Key"].ToString();

            return !string.IsNullOrEmpty(providedKey) && providedKey == configuredKey;
        }
    }
}

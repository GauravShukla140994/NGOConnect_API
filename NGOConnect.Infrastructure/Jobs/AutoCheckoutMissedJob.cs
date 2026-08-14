using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Jobs
{
    /// <summary>
    /// Hangfire recurring job — every N minutes per HANGFIRE.AUTO_CHECKOUT_MISSED_CRON setting (default 30 min).
    /// For FLEXIBLE projects: finds volunteers still in CHECKED_IN state after session end +
    /// FLEX_CHECKOUT_BUFFER_MINUTES and transitions them to CHECKOUT_MISSED (HoursLogged = 0).
    /// </summary>
    public class AutoCheckoutMissedJob
    {
        private readonly IProjectDal _project;

        public AutoCheckoutMissedJob(IProjectDal project)
        {
            _project = project;
        }

        public async Task ExecuteAsync()
        {
            Log.Debug("[AutoCheckoutMissedJob] Running checkout-missed scan");
            var result = await _project.AutoCheckoutMissedAsync();
            if (result.IsSuccess == 1)
                Log.Information("[AutoCheckoutMissedJob] {Message}", result.Message);
            else
                Log.Warning("[AutoCheckoutMissedJob] Completed with issues: {Message}", result.Message);
        }
    }
}

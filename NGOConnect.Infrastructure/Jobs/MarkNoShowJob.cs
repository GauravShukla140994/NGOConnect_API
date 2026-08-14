using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Jobs
{
    /// <summary>
    /// Hangfire recurring job — every N minutes per HANGFIRE.MARK_NOSHOW_CRON setting (default 30 min).
    /// Scans today's RECURRING sessions that ended more than RECURRING_NOSHOW_GRACE_MINUTES ago
    /// and inserts NO_SHOW attendance rows for approved volunteers who haven't checked in and
    /// haven't opted out.
    /// FLEXIBLE projects are intentionally excluded — they get CHECKOUT_MISSED, not NO_SHOW.
    /// </summary>
    public class MarkNoShowJob
    {
        private readonly IProjectDal _project;

        public MarkNoShowJob(IProjectDal project)
        {
            _project = project;
        }

        public async Task ExecuteAsync()
        {
            Log.Debug("[MarkNoShowJob] Running no-show scan");
            var result = await _project.MarkNoShowsAsync();
            if (result.IsSuccess == 1)
                Log.Information("[MarkNoShowJob] {Message}", result.Message);
            else
                Log.Warning("[MarkNoShowJob] Completed with issues: {Message}", result.Message);
        }
    }
}

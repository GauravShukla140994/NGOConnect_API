using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Jobs
{
    /// <summary>
    /// Hangfire recurring job — daily at time set by HANGFIRE.TRANSITION_CLOSING_CRON setting.
    /// Moves ACTIVE RECURRING/FLEXIBLE projects past their end date (+ CLOSING_TRIGGER_OFFSET_DAYS)
    /// to CLOSING status. Admin then reviews and calls /finalize to mark COMPLETED.
    /// </summary>
    public class TransitionToClosingJob
    {
        private readonly IProjectDal _project;

        public TransitionToClosingJob(IProjectDal project)
        {
            _project = project;
        }

        public async Task ExecuteAsync()
        {
            Log.Information("[TransitionToClosingJob] Starting closing-transition run");
            var result = await _project.TransitionToClosingAsync();
            if (result.IsSuccess == 1)
                Log.Information("[TransitionToClosingJob] {Message}", result.Message);
            else
                Log.Warning("[TransitionToClosingJob] Completed with issues: {Message}", result.Message);
        }
    }
}

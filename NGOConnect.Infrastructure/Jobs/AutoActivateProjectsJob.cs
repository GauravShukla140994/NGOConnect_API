using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Jobs
{
    /// <summary>
    /// Hangfire recurring job — daily at time set by HANGFIRE.AUTO_ACTIVATE_CRON setting.
    /// Transitions UPCOMING RECURRING/FLEXIBLE projects whose start date has arrived to ACTIVE
    /// and generates all ProjectSessions inline (Project_GenerateSessions is called inside
    /// Project_AutoActivate SP).
    /// </summary>
    public class AutoActivateProjectsJob
    {
        private readonly IProjectDal _project;

        public AutoActivateProjectsJob(IProjectDal project)
        {
            _project = project;
        }

        public async Task ExecuteAsync()
        {
            Log.Information("[AutoActivateProjectsJob] Starting auto-activation run");
            var result = await _project.AutoActivateAsync();
            if (result.IsSuccess == 1)
                Log.Information("[AutoActivateProjectsJob] {Message}", result.Message);
            else
                Log.Warning("[AutoActivateProjectsJob] Completed with issues: {Message}", result.Message);
        }
    }
}

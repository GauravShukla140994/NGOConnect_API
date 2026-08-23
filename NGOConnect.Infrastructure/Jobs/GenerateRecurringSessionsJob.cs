using Microsoft.Extensions.Logging;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.Jobs;

/// <summary>
/// Daily midnight job — generates ProjectSessions for the next N days for all
/// ACTIVE / UPCOMING RECURRING and FLEXIBLE projects, so QR codes and session
/// records always exist ahead of time.
///
/// SP: Project_GenerateSessions(p_DaysAhead)
/// Setting: RECURRING_SESSION_LOOKAHEAD_DAYS (default 14)
/// </summary>
public class GenerateRecurringSessionsJob
{
    private readonly IProjectDal _projectDal;
    private readonly ISettingsCache _settings;
    private readonly ILogger<GenerateRecurringSessionsJob> _log;

    public GenerateRecurringSessionsJob(
        IProjectDal projectDal,
        ISettingsCache settings,
        ILogger<GenerateRecurringSessionsJob> log)
    {
        _projectDal = projectDal;
        _settings   = settings;
        _log        = log;
    }

    public async Task ExecuteAsync()
    {
        int daysAhead = _settings.GetValue<int>("RECURRING_SESSION_LOOKAHEAD_DAYS", 14);
        _log.LogInformation("[GenerateRecurringSessions] Generating sessions for next {Days} days", daysAhead);

        var result = await _projectDal.GenerateSessionsAsync(daysAhead);
        if (result.Succeeded)
            _log.LogInformation("[GenerateRecurringSessions] Done — {Msg}", result.Message);
        else
            _log.LogWarning("[GenerateRecurringSessions] SP returned failure — {Msg}", result.Message);
    }
}

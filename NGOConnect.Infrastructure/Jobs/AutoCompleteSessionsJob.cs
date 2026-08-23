using Microsoft.Extensions.Logging;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.Jobs;

/// <summary>
/// Runs every 30 minutes — transitions ProjectSessions whose EndTime has passed
/// from ACTIVE → COMPLETED status, so the system can detect missed attendance.
///
/// SP: Project_AutoCompleteSessions()
/// No settings required — runs on a fixed schedule set in Program.cs.
/// </summary>
public class AutoCompleteSessionsJob
{
    private readonly IProjectDal _projectDal;
    private readonly ILogger<AutoCompleteSessionsJob> _log;

    public AutoCompleteSessionsJob(IProjectDal projectDal, ILogger<AutoCompleteSessionsJob> log)
    {
        _projectDal = projectDal;
        _log        = log;
    }

    public async Task ExecuteAsync()
    {
        _log.LogInformation("[AutoCompleteSessions] Marking past sessions as COMPLETED");
        var result = await _projectDal.AutoCompleteSessionsAsync();
        if (result.Succeeded)
            _log.LogInformation("[AutoCompleteSessions] Done — {Msg}", result.Message);
        else
            _log.LogWarning("[AutoCompleteSessions] SP returned failure — {Msg}", result.Message);
    }
}

using Microsoft.Extensions.Logging;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.Jobs;

/// <summary>
/// Daily 3 AM job — checks attendance milestones (25 %, 50 %, 75 %) for all
/// RECURRING / FLEXIBLE volunteers and fires in-app notifications for newly
/// crossed thresholds so volunteers stay engaged.
///
/// SP: Project_CheckMilestoneNotifications()
///     — internally marks processed rows so each milestone fires only once.
/// </summary>
public class MilestoneNotificationJob
{
    private readonly IProjectDal _projectDal;
    private readonly ILogger<MilestoneNotificationJob> _log;

    public MilestoneNotificationJob(IProjectDal projectDal, ILogger<MilestoneNotificationJob> log)
    {
        _projectDal = projectDal;
        _log        = log;
    }

    public async Task ExecuteAsync()
    {
        _log.LogInformation("[MilestoneNotification] Checking attendance milestones");
        var result = await _projectDal.CheckMilestoneNotificationsAsync();
        if (result.Succeeded)
            _log.LogInformation("[MilestoneNotification] Done — {Msg}", result.Message);
        else
            _log.LogWarning("[MilestoneNotification] SP returned failure — {Msg}", result.Message);
    }
}

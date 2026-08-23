using Microsoft.Extensions.Logging;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.Jobs;

/// <summary>
/// Runs every 5 minutes — finds FLEXIBLE volunteers who are currently CHECKED_IN
/// and whose session ends in 14–16 minutes, then sends an FCM push reminder to
/// check out before their hours are auto-credited (or auto-forfeited).
///
/// SP:      Project_GetCheckoutReminderTargets()   (returns UserId, FcmToken, ProjectName, EndTime)
/// Setting: CHECKOUT_REMINDER_MINUTES_BEFORE (default 15)
/// </summary>
public class CheckoutReminderJob
{
    private readonly IProjectDal              _projectDal;
    private readonly IFCMService              _fcm;
    private readonly ISettingsCache           _settings;
    private readonly ILogger<CheckoutReminderJob> _log;

    public CheckoutReminderJob(
        IProjectDal projectDal,
        IFCMService fcm,
        ISettingsCache settings,
        ILogger<CheckoutReminderJob> log)
    {
        _projectDal = projectDal;
        _fcm        = fcm;
        _settings   = settings;
        _log        = log;
    }

    public async Task ExecuteAsync()
    {
        int minutesBefore = _settings.GetValue<int>("CHECKOUT_REMINDER_MINUTES_BEFORE", 15);
        var targets = await _projectDal.GetCheckoutReminderTargetsAsync(minutesBefore);

        if (targets.Count == 0) return;

        _log.LogInformation("[CheckoutReminder] Sending {Count} checkout reminders", targets.Count);

        foreach (var t in targets)
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(t.FcmToken))
                {
                    await _fcm.SendMulticastAsync(
                        [t.FcmToken],
                        "⏰ Session ending soon!",
                        $"Don't forget to check out of '{t.ProjectName}' — session ends in ~{minutesBefore} min.",
                        "CHECKOUT_REMINDER",
                        t.ProjectId,
                        "PROJECT");
                }
            }
            catch (Exception ex)
            {
                _log.LogError(ex, "[CheckoutReminder] Failed to notify UserId={UserId}", t.UserId);
            }
        }
    }
}

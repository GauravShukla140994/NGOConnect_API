using Microsoft.Extensions.Logging;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.Jobs;

/// <summary>
/// Daily 4 AM safety-net job — finds CLOSING projects that have been in the
/// CLOSING state for more than CERT_AUTO_CLOSE_DAYS (default 7) without the
/// NGO admin manually finalising them, and auto-completes them so they don't
/// stay stuck forever.
///
/// SP: Project_AutoFinalizeStaleClosing(p_DaysThreshold)
/// Setting: CERT_AUTO_CLOSE_DAYS (default 7)
/// </summary>
public class AutoFinalizeStaleClosingJob
{
    private readonly IProjectDal _projectDal;
    private readonly ISettingsCache _settings;
    private readonly ILogger<AutoFinalizeStaleClosingJob> _log;

    public AutoFinalizeStaleClosingJob(
        IProjectDal projectDal,
        ISettingsCache settings,
        ILogger<AutoFinalizeStaleClosingJob> log)
    {
        _projectDal = projectDal;
        _settings   = settings;
        _log        = log;
    }

    public async Task ExecuteAsync()
    {
        int threshold = _settings.GetValue<int>("CERT_AUTO_CLOSE_DAYS", 7);
        _log.LogInformation("[AutoFinalizeStaleClosing] Auto-finalizing CLOSING projects older than {Days} days", threshold);

        var result = await _projectDal.AutoFinalizeStaleClosingAsync(threshold);
        if (result.Succeeded)
            _log.LogInformation("[AutoFinalizeStaleClosing] Done — {Msg}", result.Message);
        else
            _log.LogWarning("[AutoFinalizeStaleClosing] SP returned failure — {Msg}", result.Message);
    }
}

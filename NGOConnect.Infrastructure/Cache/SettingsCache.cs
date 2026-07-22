using Microsoft.Extensions.DependencyInjection;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Settings;
using Serilog;

namespace NGOConnect.Infrastructure.Cache
{
    /// <summary>
    /// Singleton in-memory settings cache.
    /// Loaded at startup via IHostedService. All reads are from memory — zero DB calls.
    /// RefreshAsync() creates a short-lived DI scope to resolve the scoped ISettingsDal,
    /// which is the correct pattern for a singleton consuming a scoped service.
    /// </summary>
    public class SettingsCache : ISettingsCache
    {
        private readonly IServiceScopeFactory      _scopeFactory;
        private Dictionary<string, string>         _all     = new(StringComparer.OrdinalIgnoreCase);
        private Dictionary<string, bool>           _public  = new(StringComparer.OrdinalIgnoreCase);
        private Dictionary<string, string>         _groups  = new(StringComparer.OrdinalIgnoreCase);
        private readonly SemaphoreSlim             _lock    = new(1, 1);

        public SettingsCache(IServiceScopeFactory scopeFactory)
        {
            _scopeFactory = scopeFactory;
        }

        public string? GetValue(string key)
            => _all.TryGetValue(key, out var v) ? v : null;

        public T GetValue<T>(string key, T defaultValue = default!)
        {
            if (!_all.TryGetValue(key, out var raw) || string.IsNullOrEmpty(raw))
                return defaultValue;
            try { return (T)Convert.ChangeType(raw, typeof(T)); }
            catch { return defaultValue; }
        }

        public Dictionary<string, string> GetPublicSettings()
            => _public.ToDictionary(k => k.Key, k => _all.GetValueOrDefault(k.Key, ""), StringComparer.OrdinalIgnoreCase);

        public Dictionary<string, string> GetGroupSettings(string group)
        {
            return _all
                .Where(kv => _groups.TryGetValue(kv.Key, out var g) && g.Equals(group, StringComparison.OrdinalIgnoreCase))
                .ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.OrdinalIgnoreCase);
        }

        public async Task RefreshAsync()
        {
            Log.Information("SettingsCache.RefreshAsync: acquiring lock...");
            await _lock.WaitAsync();
            try
            {
                Log.Information("SettingsCache.RefreshAsync: creating DI scope...");
                await using var scope = _scopeFactory.CreateAsyncScope();

                Log.Information("SettingsCache.RefreshAsync: resolving ISettingsDal...");
                ISettingsDal settingsDal;
                try
                {
                    settingsDal = scope.ServiceProvider.GetRequiredService<ISettingsDal>();
                    Log.Information("SettingsCache.RefreshAsync: ISettingsDal resolved OK.");
                }
                catch (Exception ex)
                {
                    Log.Error(ex, "SettingsCache.RefreshAsync: failed to resolve ISettingsDal — {Message}", ex.Message);
                    throw;
                }

                Log.Information("SettingsCache.RefreshAsync: calling GetAllAsync...");
                List<SettingModel> settings;
                try
                {
                    settings = await settingsDal.GetAllAsync();
                    Log.Information("SettingsCache.RefreshAsync: GetAllAsync returned {Count} rows.", settings?.Count ?? -1);
                }
                catch (Exception ex)
                {
                    Log.Error(ex, "SettingsCache.RefreshAsync: GetAllAsync threw — {Message}", ex.Message);
                    throw;
                }

                var all = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                var pub = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                var grp = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                foreach (var s in settings)
                {
                    try
                    {
                        all[s.SettingKey]  = s.SettingValue;
                        grp[s.SettingKey]  = s.SettingGroup;
                        if (s.IsPublic) pub[s.SettingKey] = true;
                    }
                    catch (Exception ex)
                    {
                        Log.Warning(ex, "SettingsCache.RefreshAsync: failed to map row — {Message}", ex.Message);
                    }
                }

                _all    = all;
                _public = pub;
                _groups = grp;

                Log.Information("SettingsCache.RefreshAsync: complete. {Total} keys loaded, {Public} public.",
                    _all.Count, _public.Count);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SettingsCache.RefreshAsync: unhandled exception — {Type}: {Message}",
                    ex.GetType().Name, ex.Message);
                throw;
            }
            finally
            {
                _lock.Release();
                Log.Information("SettingsCache.RefreshAsync: lock released.");
            }
        }
    }
}

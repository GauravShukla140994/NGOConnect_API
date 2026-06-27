using Microsoft.Extensions.DependencyInjection;
using NGOConnect.Core.Interfaces;

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
            var prefix = group.ToUpperInvariant() + ":";
            return _all
                .Where(kv => _groups.TryGetValue(kv.Key, out var g) && g.Equals(group, StringComparison.OrdinalIgnoreCase))
                .ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.OrdinalIgnoreCase);
        }

        public async Task RefreshAsync()
        {
            await _lock.WaitAsync();
            try
            {
                // Create a transient scope so the scoped ISettingsDal is properly managed.
                // The scope (and the DbConnection it holds) is disposed as soon as we exit this block.
                await using var scope   = _scopeFactory.CreateAsyncScope();
                var settingsDal         = scope.ServiceProvider.GetRequiredService<ISettingsDal>();
                var settings            = await settingsDal.GetAllAsync();
                var all     = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                var pub     = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                var grp     = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                foreach (var s in settings)
                {
                    all[s.SettingKey]  = s.SettingValue;
                    grp[s.SettingKey]  = s.SettingGroup;
                    if (s.IsPublic) pub[s.SettingKey] = true;
                }

                _all    = all;
                _public = pub;
                _groups = grp;
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}

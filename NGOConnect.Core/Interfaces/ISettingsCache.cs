namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// In-memory singleton cache for all platform settings.
    /// Loaded at startup — ALL reads are from memory, zero DB calls.
    /// Admin updates → RefreshAsync() reloads from DB, no restart needed.
    /// </summary>
    public interface ISettingsCache
    {
        /// <summary>Get a setting value by key. Returns null if not found.</summary>
        string? GetValue(string key);

        /// <summary>Get a setting value cast to T. Returns default(T) if not found.</summary>
        T GetValue<T>(string key, T defaultValue = default!);

        /// <summary>Get all public settings (IsPublic=1) as key-value dictionary.</summary>
        Dictionary<string, string> GetPublicSettings();

        /// <summary>Get all settings for a group as key-value dictionary.</summary>
        Dictionary<string, string> GetGroupSettings(string group);

        /// <summary>Reload all settings from DB. Called after admin update.</summary>
        Task RefreshAsync();
    }
}

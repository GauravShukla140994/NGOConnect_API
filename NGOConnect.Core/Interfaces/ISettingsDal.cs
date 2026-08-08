using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Settings;

namespace NGOConnect.Core.Interfaces
{
    public interface ISettingsDal
    {
        /// <summary>Returns all public settings for frontend consumption.</summary>
        Task<List<SettingModel>> GetPublicSettingsAsync();

        /// <summary>Returns all settings in a given group (admin use).</summary>
        Task<List<SettingModel>> GetByGroupAsync(string group);

        /// <summary>Updates a single setting value. Admin only.</summary>
        Task<ApiResponse> UpdateAsync(string key, string value, int updatedBy);

        /// <summary>Loads ALL settings (public + private). Used by SettingsCache at startup.</summary>
        Task<List<SettingModel>> GetAllAsync();
    }
}

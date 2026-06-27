using System.Data;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Settings;

namespace NGOConnect.Infrastructure.DAL
{
    public class SettingsDal : BaseDal, ISettingsDal
    {
        public SettingsDal(IDbProvider db) : base(db) { }

        public async Task<List<SettingModel>> GetPublicSettingsAsync()
            => await ExecuteListAsync("Settings_GetPublic", MapSetting);

        public async Task<List<SettingModel>> GetByGroupAsync(string group)
            => await ExecuteListAsync("Settings_GetByGroup", MapSetting, cmd =>
                _db.AddParameter(cmd, "p_SettingGroup", group));

        public async Task<List<SettingModel>> GetAllAsync()
            => await ExecuteListAsync("Settings_GetAll", MapSetting);

        public async Task<ApiResponse> UpdateAsync(string key, string value, int updatedBy)
        {
            var result = await ExecuteWriteAsync("Settings_Update", cmd =>
            {
                _db.AddParameter(cmd, "p_SettingKey",   key);
                _db.AddParameter(cmd, "p_SettingValue", value);
                _db.AddParameter(cmd, "p_UpdatedBy",    updatedBy);
            });
            return result.ToApiResponse();
        }

        private static SettingModel MapSetting(DataRow r) => new()
        {
            SettingId    = Col<int>(r, "SettingId"),
            SettingGroup = Col<string>(r, "SettingGroup")!,
            SettingKey   = Col<string>(r, "SettingKey")!,
            SettingValue = Col<string>(r, "SettingValue")!,
            DataType     = Col<string>(r, "DataType")!,
            Description  = Col<string>(r, "Description"),
            IsPublic     = Col<bool>(r, "IsPublic")
        };
    }
}

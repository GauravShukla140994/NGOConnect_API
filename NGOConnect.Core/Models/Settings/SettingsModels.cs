namespace NGOConnect.Core.Models.Settings
{
    public class SettingModel
    {
        public int    SettingId    { get; set; }
        public string SettingGroup { get; set; } = string.Empty;
        public string SettingKey   { get; set; } = string.Empty;
        public string SettingValue { get; set; } = string.Empty;
        public string DataType     { get; set; } = string.Empty;
        public string? Description { get; set; }
        public bool   IsPublic     { get; set; }
    }

    public class UpdateSettingRequest
    {
        public string SettingValue { get; set; } = string.Empty;
    }
}

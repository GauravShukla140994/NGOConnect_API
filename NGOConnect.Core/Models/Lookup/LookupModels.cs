namespace NGOConnect.Core.Models.Lookup
{
    public class LookupTypeModel
    {
        public int LookupTypeId { get; set; }
        public string TypeCode { get; set; } = string.Empty;
        public string TypeName { get; set; } = string.Empty;
        public string? Description { get; set; }
    }

    public class LookupValueModel
    {
        public int LookupValueId { get; set; }
        public int LookupTypeId { get; set; }
        public string ValueCode { get; set; } = string.Empty;
        public string ValueName { get; set; } = string.Empty;
        public string? Description { get; set; }
        public int OrderNo { get; set; }
        public bool IsDefault { get; set; }
    }
}

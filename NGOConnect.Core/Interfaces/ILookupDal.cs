using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Lookup;

namespace NGOConnect.Core.Interfaces
{
    public interface ILookupDal
    {
        Task<ApiResponse<List<LookupTypeModel>>>  GetAllTypesAsync();
        Task<ApiResponse<List<LookupValueModel>>> GetValuesByTypeCodeAsync(string typeCode);
        Task<ApiResponse<LookupValueModel>>       GetValueByCodeAsync(string typeCode, string valueCode);
    }
}

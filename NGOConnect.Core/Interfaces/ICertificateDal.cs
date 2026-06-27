using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    public interface ICertificateDal
    {
        Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId);
    }
}

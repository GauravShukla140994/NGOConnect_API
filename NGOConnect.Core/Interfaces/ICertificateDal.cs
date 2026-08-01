using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;

namespace NGOConnect.Core.Interfaces
{
    public interface ICertificateDal
    {
        Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId);
        Task<ApiResponse<DynamicRow>>       GetDataAsync(string certCode);
        Task<ApiResponse<DynamicRow>>       IssueAsync(int issuedBy, IssueCertificateRequest request);
    }
}

using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;

namespace NGOConnect.Core.Interfaces
{
    public interface ICertificateDal
    {
        Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId);
        Task<ApiResponse<DynamicRow>>       GetDataAsync(string certCode);

        /// <summary>Public verify-page lookup by encrypted token payload (see IUrlTokenService) — never by raw CertCode.</summary>
        Task<ApiResponse<DynamicRow>>       GetDataByIdAsync(int certificateId);
        Task<ApiResponse<DynamicRow>>       IssueAsync(int issuedBy, IssueCertificateRequest request);
    }
}

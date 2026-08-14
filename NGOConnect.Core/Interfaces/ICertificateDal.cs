using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;
using NGOConnect.Core.Models.Skill;

namespace NGOConnect.Core.Interfaces
{
    public interface ICertificateDal
    {
        Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId);
        Task<ApiResponse<DynamicRow>>       GetDataAsync(string certCode);

        /// <summary>Public verify-page lookup by encrypted token payload (see IUrlTokenService) — never by raw CertCode.</summary>
        Task<ApiResponse<DynamicRow>>       GetDataByIdAsync(int certificateId);

        /// <summary>Issue cert to a single volunteer. SP now computes TotalHours from DB (v5.1: p_TotalHours removed).</summary>
        Task<ApiResponse<DynamicRow>>       IssueAsync(int issuedBy, IssueCertificateRequest request);

        /// <summary>v5.1: Bulk-issue certs to all eligible volunteers for a CLOSING/COMPLETED project. Message carries "Issued X. Skipped Y."</summary>
        Task<ApiResponse>                   IssueBulkAsync(int issuedBy, IssueBulkCertificateRequest request);
    }
}

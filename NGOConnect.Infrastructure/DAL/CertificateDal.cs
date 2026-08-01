using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CertificateDal : BaseDal, ICertificateDal
    {
        public CertificateDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Certificate_GetByUser",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByUserAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetDataAsync(string certCode)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Certificate_GetData",
                    cmd => _db.AddParameter(cmd, "p_CertCode", certCode));
                if (row == null)
                    return ApiResponse<DynamicRow>.Failure("Certificate not found.", "NOT_FOUND");
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDataAsync failed CertCode={CertCode}", certCode);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> IssueAsync(int issuedBy, IssueCertificateRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Certificate_Issue", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",  request.ProjectId);
                    _db.AddParameter(cmd, "p_UserId",     request.UserId);
                    _db.AddParameter(cmd, "p_OrgId",      request.OrgId);
                    _db.AddParameter(cmd, "p_IssuedBy",   issuedBy);
                    _db.AddParameter(cmd, "p_TotalHours", (object?)request.TotalHours);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "ISSUE_FAILED");

                // Return the issued cert data so frontend gets CertCode immediately
                var certCode = Col<string>(result.Row!, "CertCode")!;
                var certRow  = await ExecuteDynamicGetAsync("Certificate_GetData",
                    cmd => _db.AddParameter(cmd, "p_CertCode", certCode));
                return ApiResponse<DynamicRow>.Success(certRow, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "IssueAsync failed ProjectId={ProjectId} UserId={UserId}", request.ProjectId, request.UserId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

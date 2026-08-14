using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CertificateDal : BaseDal, ICertificateDal
    {
        // Matches ShareController's BaseUrl — both hardcode the production domain rather
        // than reading from Settings. Fine for now (consistent with the existing pattern),
        // worth moving to Settings (PLATFORM group) if a staging-specific verify link is
        // ever needed.
        private const string BaseUrl = "https://www.ripplehub.app";

        private readonly IUrlTokenService _tokens;

        public CertificateDal(IDbProvider db, IUrlTokenService tokens) : base(db)
        {
            _tokens = tokens;
        }

        // Attaches an AES-256-GCM encrypted verify token/URL to a certificate row —
        // same mechanism ShareController uses for /ngo and /opportunity (entityType "CERT").
        // This is what the public /verify page and every "share my certificate" button
        // (mobile CertificateModal, website) must use instead of the raw, sequential,
        // guessable CertCode (CERT-2026-000001 — a plain incrementing counter, NOT sparse).
        private DynamicRow AttachVerifyLink(DynamicRow row)
        {
            var certificateId = row.Get<int>("certificateId");
            var token = _tokens.Encrypt("CERT", certificateId);
            row["verifyToken"] = token;
            row["verifyUrl"]   = $"{BaseUrl}/verify/{token}";
            return row;
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Certificate_GetByUser",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                foreach (var row in rows) AttachVerifyLink(row);
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
                return ApiResponse<DynamicRow>.Success(AttachVerifyLink(row));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDataAsync failed CertCode={CertCode}", certCode);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // Public verify-page path — looked up by the numeric CertificateId decrypted from
        // an opaque token, never by the guessable CertCode. Deliberately does NOT filter
        // WHERE IsDeleted = 0 — the caller needs to see IsDeleted to render the "Revoked"
        // state rather than a generic "not found" (same as GetDataAsync).
        public async Task<ApiResponse<DynamicRow>> GetDataByIdAsync(int certificateId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Certificate_GetDataById",
                    cmd => _db.AddParameter(cmd, "p_CertificateId", certificateId));
                if (row == null)
                    return ApiResponse<DynamicRow>.Failure("Certificate not found.", "NOT_FOUND");
                return ApiResponse<DynamicRow>.Success(AttachVerifyLink(row));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDataByIdAsync failed CertificateId={CertificateId}", certificateId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // v5.1: p_TotalHours removed — SP now computes from ProjectAttendance SUM(HoursLogged)
        public async Task<ApiResponse<DynamicRow>> IssueAsync(int issuedBy, IssueCertificateRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Certificate_Issue", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                    _db.AddParameter(cmd, "p_UserId",    request.UserId);
                    _db.AddParameter(cmd, "p_OrgId",     request.OrgId);
                    _db.AddParameter(cmd, "p_IssuedBy",  issuedBy);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "ISSUE_FAILED");

                var certCode = Col<string>(result.Row!, "CertCode")!;
                var certRow  = await ExecuteDynamicGetAsync("Certificate_GetData",
                    cmd => _db.AddParameter(cmd, "p_CertCode", certCode));
                if (certRow != null) AttachVerifyLink(certRow);
                return ApiResponse<DynamicRow>.Success(certRow, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "IssueAsync failed ProjectId={ProjectId} UserId={UserId}", request.ProjectId, request.UserId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // v5.1: Bulk-issue certs to all eligible volunteers (checks MinAttendPct per volunteer)
        public async Task<ApiResponse> IssueBulkAsync(int issuedBy, IssueBulkCertificateRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Certificate_IssueBulk", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                    _db.AddParameter(cmd, "p_IssuedBy",  issuedBy);
                    _db.AddParameter(cmd, "p_OrgId",     request.OrgId);
                });
                return result.ToApiResponse();  // message = "Issued X certificate(s). Skipped Y."
            }
            catch (Exception ex)
            {
                Log.Error(ex, "IssueBulkAsync failed ProjectId={ProjectId}", request.ProjectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

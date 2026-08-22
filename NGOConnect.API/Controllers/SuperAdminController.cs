using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.SuperAdmin;
using Serilog;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Super Admin — internal platform team only (NGO approval, document verification,
    /// lookup type/value management). Every action below except Login requires a JWT
    /// carrying the SUPER_ADMIN role claim, issued only by SuperAdmin_Login — a normal
    /// volunteer/NGO-admin token can never satisfy [Authorize(Roles = "SUPER_ADMIN")].
    ///
    /// All SPs behind this controller are new (SuperAdmin_* prefix) — isolated on
    /// purpose so this module can never regress mobile/NGO-admin flows.
    /// </summary>
    [ApiController]
    [Route("api/v1/superadmin")]
    [Produces("application/json")]
    [Authorize(Roles = "SUPER_ADMIN")]
    public class SuperAdminController : ControllerBase
    {
        private readonly ISuperAdminDal _superAdmin;
        private readonly IPrivateBlobService _privateBlob;
        public SuperAdminController(ISuperAdminDal superAdmin, IPrivateBlobService privateBlob)
        {
            _superAdmin = superAdmin;
            _privateBlob = privateBlob;
        }

        // ── Auth ──────────────────────────────────────────────────────────────

        [HttpPost("login")]
        [AllowAnonymous]
        // Stricter than the 100/min global limiter — this is a password endpoint
        // guarding platform-wide access, deserves its own tighter ceiling.
        // Policy defined in Program.cs → AddRateLimiter → AddPolicy("superadmin-login").
        [EnableRateLimiting("superadmin-login")]
        [ProducesResponseType(typeof(ApiResponse<SuperAdminLoginResponse>), 200)]
        public async Task<ApiResponse<SuperAdminLoginResponse>> Login([FromBody] SuperAdminLoginRequest request)
        {
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            return await _superAdmin.LoginAsync(request, ipAddress);
        }

        // ── Organisation review ──────────────────────────────────────────────

        // statusCode: PENDING | UNDER_REVIEW | APPROVED | REJECTED | SUSPENDED
        [HttpGet("orgs")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgList(
            [FromQuery] string  statusCode,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 20)
            => await _superAdmin.GetOrgListAsync(statusCode, pageNumber, pageSize);

        [HttpGet("orgs/{orgId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetOrgDetail(int orgId)
            => await _superAdmin.GetOrgDetailAsync(orgId);

        [HttpGet("orgs/{orgId:int}/documents")]
        public async Task<ApiResponse<List<DynamicRow>>> GetOrgDocuments(int orgId)
            => await _superAdmin.GetOrgDocumentsAsync(orgId);

        [HttpPut("orgs/documents/verify")]
        public async Task<ApiResponse> VerifyOrgDocument([FromBody] VerifyOrgDocumentRequest request)
            => await _superAdmin.VerifyOrgDocumentAsync(request, GetSuperAdminUserId());

        // statusCode: PENDING | VERIFIED | REJECTED  (ORG_VERIFICATION_STATUS lookup)
        [HttpPut("orgs/{orgId:int}/verify-profile")]
        public async Task<ApiResponse> VerifyOrgProfile(int orgId, [FromQuery] string statusCode = "VERIFIED")
            => await _superAdmin.VerifyOrgProfileAsync(orgId, statusCode, GetSuperAdminUserId());

        [HttpPut("orgs/{orgId:int}/approve")]
        public async Task<ApiResponse> ApproveOrg(int orgId)
            => await _superAdmin.ApproveOrgAsync(orgId, GetSuperAdminUserId());

        [HttpPut("orgs/reject")]
        public async Task<ApiResponse> RejectOrg([FromBody] RejectOrgRequest request)
            => await _superAdmin.RejectOrgAsync(request, GetSuperAdminUserId());

        [HttpPut("orgs/suspend")]
        public async Task<ApiResponse> SuspendOrg([FromBody] SuspendOrgRequest request)
            => await _superAdmin.SuspendOrgAsync(request, GetSuperAdminUserId());

        [HttpPut("orgs/{orgId:int}/reactivate")]
        public async Task<ApiResponse> ReactivateOrg(int orgId)
            => await _superAdmin.ReactivateOrgAsync(orgId, GetSuperAdminUserId());

        [HttpGet("orgs/{orgId:int}/history")]
        public async Task<ApiResponse<List<DynamicRow>>> GetOrgStatusHistory(int orgId)
            => await _superAdmin.GetOrgStatusHistoryAsync(orgId);

        // ── Members review (cross-NGO oversight) ─────────────────────────────

        [HttpGet("members")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetMemberList(
            [FromQuery] string? orgIds,
            [FromQuery] string? search,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 100)
            => await _superAdmin.GetMemberListAsync(orgIds, search, pageNumber, pageSize);

        [HttpGet("members/{userId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetMemberProfile(int userId)
            => await _superAdmin.GetMemberProfileAsync(userId);

        [HttpGet("members/{userId:int}/documents")]
        public async Task<ApiResponse<List<DynamicRow>>> GetMemberDocuments(int userId)
            => await _superAdmin.GetMemberDocumentsAsync(userId);

        [HttpPut("members/documents/verify")]
        public async Task<ApiResponse> VerifyMemberDocument([FromBody] VerifyMemberDocumentRequest request)
            => await _superAdmin.VerifyMemberDocumentAsync(request, GetSuperAdminUserId());

        [HttpPut("members/{userId:int}/verify-profile")]
        public async Task<ApiResponse> VerifyMemberProfile(int userId)
            => await _superAdmin.VerifyMemberProfileAsync(userId, GetSuperAdminUserId());

        [HttpPut("members/request-update")]
        public async Task<ApiResponse> RequestMemberUpdate([FromBody] RequestMemberUpdateRequest request)
            => await _superAdmin.RequestMemberUpdateAsync(request, GetSuperAdminUserId());

        [HttpPut("members/{userId:int}/suspend")]
        public async Task<ApiResponse> SuspendMember(int userId, [FromBody] SuspendMemberRequest request)
            => await _superAdmin.SuspendMemberAsync(userId, request, GetSuperAdminUserId());

        [HttpPut("members/{userId:int}/reactivate")]
        public async Task<ApiResponse> ReactivateMember(int userId)
            => await _superAdmin.ReactivateMemberAsync(userId, GetSuperAdminUserId());

        // ── Dashboard ─────────────────────────────────────────────────────────

        [HttpGet("dashboard")]
        public async Task<ApiResponse<DynamicRow>> GetDashboard()
            => await _superAdmin.GetDashboardAsync();

        // ── Documents (signed URLs for private S3 files) ─────────────────────

        // fileKey: the raw value stored in OrgDocuments.FileUrl / UserDocuments.FileUrl.
        // Since the switch to AWS S3 private storage (2026-07-18), that column holds a
        // bare S3 object key (e.g. "org-documents/17/xxx_cert.pdf"), not a browsable URL —
        // the private bucket has no public access, so a link only works for a short signed
        // window. IPrivateBlobService.GetSignedUrlAsync transparently handles older
        // documents too (local/cloudinary fallback just returns the stored URL as-is), so
        // the admin panel should always call this instead of using fileUrl directly.
        [HttpGet("documents/signed-url")]
        public async Task<ApiResponse<string>> GetDocumentSignedUrl(
            [FromQuery] string fileKey,
            [FromQuery] int    expiryMinutes = 15)
        {
            if (string.IsNullOrWhiteSpace(fileKey))
                return ApiResponse<string>.Failure("fileKey is required.", "VALIDATION_ERROR");

            try
            {
                var url = await _privateBlob.GetSignedUrlAsync(fileKey, expiryMinutes);
                return ApiResponse<string>.Success(url);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDocumentSignedUrl failed FileKey={Key}", fileKey);
                return ApiResponse<string>.Failure("Could not generate a document link.", "INTERNAL_ERROR");
            }
        }

        // ── Lookup management ────────────────────────────────────────────────

        [HttpGet("lookup-types")]
        public async Task<ApiResponse<List<DynamicRow>>> GetLookupTypes()
            => await _superAdmin.GetLookupTypesAsync();

        [HttpGet("lookup-types/{lookupTypeId:int}/values")]
        public async Task<ApiResponse<List<DynamicRow>>> GetLookupValues(int lookupTypeId)
            => await _superAdmin.GetLookupValuesAsync(lookupTypeId);

        [HttpPost("lookup-types")]
        public async Task<ApiResponse<DynamicRow>> AddLookupType([FromBody] AddLookupTypeRequest request)
            => await _superAdmin.AddLookupTypeAsync(request, GetSuperAdminUserId());

        [HttpPut("lookup-types")]
        public async Task<ApiResponse> UpdateLookupType([FromBody] UpdateLookupTypeRequest request)
            => await _superAdmin.UpdateLookupTypeAsync(request, GetSuperAdminUserId());

        [HttpPost("lookup-values")]
        public async Task<ApiResponse<DynamicRow>> AddLookupValue([FromBody] AddLookupValueRequest request)
            => await _superAdmin.AddLookupValueAsync(request, GetSuperAdminUserId());

        [HttpPut("lookup-values")]
        public async Task<ApiResponse> UpdateLookupValue([FromBody] UpdateLookupValueRequest request)
            => await _superAdmin.UpdateLookupValueAsync(request, GetSuperAdminUserId());

        [HttpPut("lookup-values/active")]
        public async Task<ApiResponse> SetLookupValueActive([FromBody] SetLookupValueActiveRequest request)
            => await _superAdmin.SetLookupValueActiveAsync(request, GetSuperAdminUserId());

        // ── Org project permissions ───────────────────────────────────────────

        [HttpPatch("orgs/{orgId:int}/project-permissions")]
        public async Task<ApiResponse> UpdateOrgProjectPermissions(
            int orgId, [FromBody] UpdateOrgProjectPermissionsRequest request)
            => await _superAdmin.UpdateOrgProjectPermissionsAsync(orgId, request, GetSuperAdminUserId());

        // ── Proactive Member + Organisation onboarding ───────────────────────

        // Creates a User + UserProfile + (new or existing) Organisation + OrgMembers
        // association in one atomic call, before the person has ever logged in.
        // Returns the new UserId/OrgId plus the encrypted org share link (same
        // mechanism as ShareController) ready to copy/share immediately.
        [HttpPost("members")]
        public async Task<ApiResponse<DynamicRow>> CreateMemberWithOrg(
            [FromBody] CreateMemberWithOrgRequest request)
            => await _superAdmin.CreateMemberWithOrgAsync(request, GetSuperAdminUserId());

        // ── Helpers ───────────────────────────────────────────────────────────

        private int GetSuperAdminUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

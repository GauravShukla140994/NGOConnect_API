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
        private readonly IUrlTokenService _tokens;
        public SuperAdminController(ISuperAdminDal superAdmin, IPrivateBlobService privateBlob, IUrlTokenService tokens)
        {
            _superAdmin = superAdmin;
            _privateBlob = privateBlob;
            _tokens = tokens;
        }

        // ── Token-based ID resolution ─────────────────────────────────────────
        // Every org/member/document ID in this controller's URLs and request
        // bodies is an encrypted IUrlTokenService token (same AES-256-GCM
        // mechanism as the public /organisation/{token} share links), NOT a
        // raw numeric ID — 2026-08-24: raw sequential OrgId/UserId values were
        // visible in the Super Admin website's Network tab (e.g. GET
        // /superadmin/orgs/64), leaking org/member counts and growth rate to
        // anyone with eyes on that authenticated session. Auth is still
        // enforced entirely by the [Authorize(Roles = "SUPER_ADMIN")] JWT, not
        // by token secrecy — this is defense-in-depth / info-leak hardening,
        // not an access-control fix. Every SP/DAL call below the controller is
        // completely unchanged — only resolves the real int ID here, once.
        private ApiResponse<T>? TryResolveId<T>(string entityType, string? token, out int id)
        {
            id = 0;
            var resolved = string.IsNullOrWhiteSpace(token) ? null : _tokens.Decrypt(token);
            if (resolved is null || !string.Equals(resolved.Value.EntityType, entityType, StringComparison.OrdinalIgnoreCase))
            {
                return ApiResponse<T>.Failure("Invalid or expired reference.", "INVALID_TOKEN");
            }
            id = resolved.Value.Id;
            return null;
        }
        private ApiResponse? TryResolveId(string entityType, string? token, out int id)
        {
            id = 0;
            var resolved = string.IsNullOrWhiteSpace(token) ? null : _tokens.Decrypt(token);
            if (resolved is null || !string.Equals(resolved.Value.EntityType, entityType, StringComparison.OrdinalIgnoreCase))
            {
                return ApiResponse.Fail("Invalid or expired reference.", "INVALID_TOKEN");
            }
            id = resolved.Value.Id;
            return null;
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

        [HttpGet("orgs/{orgToken}")]
        public async Task<ApiResponse<DynamicRow>> GetOrgDetail(string orgToken)
        {
            var err = TryResolveId<DynamicRow>("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.GetOrgDetailAsync(orgId);
        }

        [HttpGet("orgs/{orgToken}/documents")]
        public async Task<ApiResponse<List<DynamicRow>>> GetOrgDocuments(string orgToken)
        {
            var err = TryResolveId<List<DynamicRow>>("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.GetOrgDocumentsAsync(orgId);
        }

        [HttpPut("orgs/documents/verify")]
        public async Task<ApiResponse> VerifyOrgDocument([FromBody] VerifyOrgDocumentRequest request)
        {
            var err = TryResolveId("ORGDOC", request.OrgDocumentToken, out var orgDocumentId);
            if (err is not null) return err;
            return await _superAdmin.VerifyOrgDocumentAsync(orgDocumentId, request.IsVerified, GetSuperAdminUserId());
        }

        // statusCode: PENDING | VERIFIED | REJECTED  (ORG_VERIFICATION_STATUS lookup)
        [HttpPut("orgs/{orgToken}/verify-profile")]
        public async Task<ApiResponse> VerifyOrgProfile(string orgToken, [FromQuery] string statusCode = "VERIFIED")
        {
            var err = TryResolveId("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.VerifyOrgProfileAsync(orgId, statusCode, GetSuperAdminUserId());
        }

        [HttpPut("orgs/approve")]
        public async Task<ApiResponse> ApproveOrg([FromBody] ApproveOrgRequest request)
        {
            var err = TryResolveId("ORG", request.OrgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.ApproveOrgAsync(orgId, request.IsNonRegistered, request.Remarks, GetSuperAdminUserId());
        }

        [HttpPut("orgs/set-non-registered")]
        public async Task<ApiResponse> SetOrgNonRegistered([FromBody] SetNonRegisteredRequest request)
        {
            var err = TryResolveId("ORG", request.OrgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.SetOrgNonRegisteredAsync(orgId, request.IsNonRegistered, request.Remarks, GetSuperAdminUserId());
        }

        [HttpPut("orgs/reject")]
        public async Task<ApiResponse> RejectOrg([FromBody] RejectOrgRequest request)
        {
            var err = TryResolveId("ORG", request.OrgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.RejectOrgAsync(orgId, request.Reason, GetSuperAdminUserId());
        }

        [HttpPut("orgs/suspend")]
        public async Task<ApiResponse> SuspendOrg([FromBody] SuspendOrgRequest request)
        {
            var err = TryResolveId("ORG", request.OrgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.SuspendOrgAsync(orgId, request.Reason, GetSuperAdminUserId());
        }

        [HttpPut("orgs/{orgToken}/reactivate")]
        public async Task<ApiResponse> ReactivateOrg(string orgToken)
        {
            var err = TryResolveId("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.ReactivateOrgAsync(orgId, GetSuperAdminUserId());
        }

        [HttpGet("orgs/{orgToken}/history")]
        public async Task<ApiResponse<List<DynamicRow>>> GetOrgStatusHistory(string orgToken)
        {
            var err = TryResolveId<List<DynamicRow>>("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.GetOrgStatusHistoryAsync(orgId);
        }

        // ── Members review (cross-NGO oversight) ─────────────────────────────

        [HttpGet("members")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetMemberList(
            [FromQuery] string? orgIds,
            [FromQuery] string? search,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 100)
            => await _superAdmin.GetMemberListAsync(orgIds, search, pageNumber, pageSize);

        [HttpGet("members/{userToken}")]
        public async Task<ApiResponse<DynamicRow>> GetMemberProfile(string userToken)
        {
            var err = TryResolveId<DynamicRow>("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.GetMemberProfileAsync(userId);
        }

        [HttpGet("members/{userToken}/documents")]
        public async Task<ApiResponse<List<DynamicRow>>> GetMemberDocuments(string userToken)
        {
            var err = TryResolveId<List<DynamicRow>>("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.GetMemberDocumentsAsync(userId);
        }

        [HttpPut("members/documents/verify")]
        public async Task<ApiResponse> VerifyMemberDocument([FromBody] VerifyMemberDocumentRequest request)
        {
            var err = TryResolveId("USERDOC", request.UserDocumentToken, out var userDocumentId);
            if (err is not null) return err;
            return await _superAdmin.VerifyMemberDocumentAsync(userDocumentId, request.IsVerified, GetSuperAdminUserId());
        }

        [HttpPut("members/{userToken}/verify-profile")]
        public async Task<ApiResponse> VerifyMemberProfile(string userToken)
        {
            var err = TryResolveId("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.VerifyMemberProfileAsync(userId, GetSuperAdminUserId());
        }

        [HttpPut("members/request-update")]
        public async Task<ApiResponse> RequestMemberUpdate([FromBody] RequestMemberUpdateRequest request)
        {
            var err = TryResolveId("USER", request.UserToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.RequestMemberUpdateAsync(userId, request.Reason, GetSuperAdminUserId());
        }

        [HttpPut("members/{userToken}/suspend")]
        public async Task<ApiResponse> SuspendMember(string userToken, [FromBody] SuspendMemberRequest request)
        {
            var err = TryResolveId("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.SuspendMemberAsync(userId, request, GetSuperAdminUserId());
        }

        [HttpPut("members/{userToken}/reactivate")]
        public async Task<ApiResponse> ReactivateMember(string userToken)
        {
            var err = TryResolveId("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.ReactivateMemberAsync(userId, GetSuperAdminUserId());
        }

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

        [HttpPatch("orgs/{orgToken}/project-permissions")]
        public async Task<ApiResponse> UpdateOrgProjectPermissions(
            string orgToken, [FromBody] UpdateOrgProjectPermissionsRequest request)
        {
            var err = TryResolveId("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.UpdateOrgProjectPermissionsAsync(orgId, request, GetSuperAdminUserId());
        }

        // ── Proactive Member + Organisation onboarding ───────────────────────

        // Creates a User + UserProfile + (new or existing) Organisation + OrgMembers
        // association in one atomic call, before the person has ever logged in.
        // Returns the new UserId/OrgId plus the encrypted org share link (same
        // mechanism as ShareController) ready to copy/share immediately.
        [HttpPost("members")]
        public async Task<ApiResponse<DynamicRow>> CreateMemberWithOrg(
            [FromBody] CreateMemberWithOrgRequest request)
            => await _superAdmin.CreateMemberWithOrgAsync(request, GetSuperAdminUserId());

        // ── Post-creation profile correction ─────────────────────────────────

        // Full-profile overwrite for a Super-Admin-onboarded (or any) organisation.
        // Re-validates OrgName/RegNumber uniqueness excluding this OrgId.
        [HttpPut("orgs/{orgToken}/profile")]
        public async Task<ApiResponse<DynamicRow>> UpdateOrgProfile(
            string orgToken, [FromBody] UpdateOrgProfileRequest request)
        {
            var err = TryResolveId<DynamicRow>("ORG", orgToken, out var orgId);
            if (err is not null) return err;
            return await _superAdmin.UpdateOrgProfileAsync(orgId, request, GetSuperAdminUserId());
        }

        // Full-profile overwrite for a member. Email/Mobile are only actually
        // applied while the member has never logged in (Users.IsVerified = 0) —
        // enforced server-side in SuperAdmin_User_UpdateProfile regardless of
        // what's sent here. Response's emailMobileLocked flag tells the caller
        // whether those two fields were skipped.
        [HttpPut("members/{userToken}/profile")]
        public async Task<ApiResponse<DynamicRow>> UpdateMemberProfile(
            string userToken, [FromBody] UpdateMemberProfileRequest request)
        {
            var err = TryResolveId<DynamicRow>("USER", userToken, out var userId);
            if (err is not null) return err;
            return await _superAdmin.UpdateMemberProfileAsync(userId, request, GetSuperAdminUserId());
        }

        // ── Helpers ───────────────────────────────────────────────────────────

        private int GetSuperAdminUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

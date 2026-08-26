using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.SuperAdmin;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Super Admin DAL — Controller → ISuperAdminDal → SuperAdminDal → Stored Procedures → MySQL.
    /// Every SP called here is new (SuperAdmin_* prefix, plus Org_Resubmit for the founder-side
    /// counterpart). None of these overlap with or modify any existing SP.
    /// </summary>
    public interface ISuperAdminDal
    {
        // ── Auth ──────────────────────────────────────────────────────────────
        Task<ApiResponse<SuperAdminLoginResponse>> LoginAsync(SuperAdminLoginRequest request, string ipAddress);

        // ── Organisation review ──────────────────────────────────────────────
        Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgListAsync(string statusCode, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>>              GetOrgDetailAsync(int orgId);
        Task<ApiResponse<List<DynamicRow>>>        GetOrgDocumentsAsync(int orgId);
        Task<ApiResponse>                          VerifyOrgDocumentAsync(int orgDocumentId, bool isVerified, int superAdminUserId);
        Task<ApiResponse>                          VerifyOrgProfileAsync(int orgId, string statusCode, int superAdminUserId);
        Task<ApiResponse>                          ApproveOrgAsync(int orgId, bool isNonRegistered, string? remarks, int superAdminUserId);
        Task<ApiResponse>                          SetOrgNonRegisteredAsync(int orgId, bool isNonRegistered, string? remarks, int superAdminUserId);
        Task<ApiResponse>                          RejectOrgAsync(int orgId, string reason, int superAdminUserId);
        Task<ApiResponse>                          SuspendOrgAsync(int orgId, string? reason, int superAdminUserId);
        Task<ApiResponse>                          ReactivateOrgAsync(int orgId, int superAdminUserId);
        Task<ApiResponse<List<DynamicRow>>>        GetOrgStatusHistoryAsync(int orgId);

        // ── Members review (cross-NGO oversight) ─────────────────────────────
        Task<ApiResponse<PagedResult<DynamicRow>>> GetMemberListAsync(string? orgIds, string? search, int pageNumber, int pageSize);
        Task<ApiResponse<DynamicRow>>              GetMemberProfileAsync(int userId);
        Task<ApiResponse<List<DynamicRow>>>        GetMemberDocumentsAsync(int userId);
        Task<ApiResponse>                          VerifyMemberDocumentAsync(int userDocumentId, bool isVerified, int superAdminUserId);
        Task<ApiResponse>                          VerifyMemberProfileAsync(int userId, int superAdminUserId);
        Task<ApiResponse>                          RequestMemberUpdateAsync(int userId, string reason, int superAdminUserId);
        Task<ApiResponse>                          SuspendMemberAsync(int userId, SuspendMemberRequest request, int superAdminUserId);
        Task<ApiResponse>                          ReactivateMemberAsync(int userId, int superAdminUserId);

        // ── Dashboard ─────────────────────────────────────────────────────────
        Task<ApiResponse<DynamicRow>> GetDashboardAsync();

        // ── Lookup management ────────────────────────────────────────────────
        Task<ApiResponse<List<DynamicRow>>> GetLookupTypesAsync();
        Task<ApiResponse<List<DynamicRow>>> GetLookupValuesAsync(int lookupTypeId);
        Task<ApiResponse<DynamicRow>>       AddLookupTypeAsync(AddLookupTypeRequest request, int superAdminUserId);
        Task<ApiResponse>                   UpdateLookupTypeAsync(UpdateLookupTypeRequest request, int superAdminUserId);
        Task<ApiResponse<DynamicRow>>       AddLookupValueAsync(AddLookupValueRequest request, int superAdminUserId);
        Task<ApiResponse>                   UpdateLookupValueAsync(UpdateLookupValueRequest request, int superAdminUserId);
        Task<ApiResponse>                   SetLookupValueActiveAsync(SetLookupValueActiveRequest request, int superAdminUserId);

        // ── Org project permissions ───────────────────────────────────────────
        Task<ApiResponse> UpdateOrgProjectPermissionsAsync(int orgId, UpdateOrgProjectPermissionsRequest request, int superAdminUserId);

        // ── Proactive Member + Organisation onboarding ───────────────────────
        Task<ApiResponse<DynamicRow>> CreateMemberWithOrgAsync(CreateMemberWithOrgRequest request, int superAdminUserId);

        // ── Post-creation profile correction ─────────────────────────────────
        Task<ApiResponse<DynamicRow>> UpdateOrgProfileAsync(int orgId, UpdateOrgProfileRequest request, int superAdminUserId);
        Task<ApiResponse<DynamicRow>> UpdateMemberProfileAsync(int userId, UpdateMemberProfileRequest request, int superAdminUserId);
    }
}

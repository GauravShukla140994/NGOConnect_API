using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Org;

namespace NGOConnect.Core.Interfaces
{
    public interface IOrgDal
    {
        // ── Core CRUD ───────────────────────────────────────────────────────────
        Task<ApiResponse<DynamicRow>>                      RegisterAsync(int userId, RegisterOrgRequest request);
        Task<ApiResponse<DynamicRow>>                      GetProfileAsync(int orgId);
        Task<ApiResponse>                                  UpdateAsync(int orgId, int userId, UpdateOrgRequest request);
        // ── Explore (s-explore screen) ──────────────────────────────────────────
        Task<ApiResponse<PagedResult<OrgListItemModel>>>   ListAsync(int pageNumber, int pageSize, string? keyword = null, string? category = null, decimal? lat = null, decimal? lng = null);
        Task<ApiResponse<List<RecommendedOrgModel>>>       GetRecommendedAsync(int userId);
        Task<ApiResponse<List<TrendingCampaignModel>>>     GetTrendingCampaignsAsync(int pageSize);
        // ── Admin Dashboard ─────────────────────────────────────────────────────
        Task<ApiResponse<OrgDashboardModel>>               GetDashboardAsync(int orgId);
        Task<ApiResponse<OrgDonationDashboardModel>>       GetDonationDashboardAsync(int orgId);
        // ── Members ─────────────────────────────────────────────────────────────
        Task<ApiResponse<List<DynamicRow>>>                GetMembersAsync(int orgId);
        Task<ApiResponse>                                  AddMemberAsync(int orgId, int requestedBy, AddMemberRequest request);
        Task<ApiResponse>                                  RemoveMemberAsync(int orgId, int userId, int requestedBy);
        Task<ApiResponse>                                  RequestMembershipAsync(int orgId, int userId, RequestMembershipRequest request);
        Task<ApiResponse>                                  ReviewMembershipAsync(int reviewedBy, ReviewMembershipRequest request);
        Task<ApiResponse<List<DynamicRow>>>                GetPendingMembersAsync(int orgId);
        Task<ApiResponse>                                  UpdateMemberPermissionsAsync(int orgId, int updatedBy, UpdateMemberPermissionsRequest request);
        Task<ApiResponse>                                  UpdateMemberRoleAsync(int orgId, int updatedBy, UpdateMemberRoleRequest request);
        // ── Volunteer admin views (s-vol-profile, s-member-impact) ─────────────
        Task<ApiResponse<OrgVolunteerProfileModel>>        GetVolunteerProfileAsync(int orgId, int userId);
        Task<ApiResponse<OrgMemberImpactModel>>            GetMemberImpactAsync(int orgId, int userId);
        Task<ApiResponse>                                  AwardBadgeAsync(int orgId, int awardedBy, AwardBadgeRequest request);
        Task<ApiResponse>                                  ExcuseNoShowAsync(int orgId, int adminUserId, ExcuseNoShowRequest request);
        // ── Donors & Transactions (s-admin-donors, s-admin-transactions) ────────
        Task<ApiResponse<PagedResult<OrgDonorModel>>>      GetDonorsAsync(int orgId, string tab, int pageNumber, int pageSize);
        Task<ApiResponse<PagedResult<OrgTransactionModel>>>GetTransactionsAsync(int orgId, string? statusCode, int pageNumber, int pageSize);
        // ── Documents ───────────────────────────────────────────────────────────
        Task<ApiResponse>                                  UploadDocumentAsync(int orgId, int userId, UploadOrgDocumentRequest request);
    }
}

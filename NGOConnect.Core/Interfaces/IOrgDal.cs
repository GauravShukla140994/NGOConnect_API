using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Org;

namespace NGOConnect.Core.Interfaces
{
    public interface IOrgDal
    {
        Task<ApiResponse<DynamicRow>>              RegisterAsync(int userId, RegisterOrgRequest request);
        Task<ApiResponse<DynamicRow>>              GetProfileAsync(int orgId);
        Task<ApiResponse>                          UpdateAsync(int orgId, int userId, UpdateOrgRequest request);
        Task<ApiResponse<OrgDashboardModel>>       GetDashboardAsync(int orgId);
        Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(int pageNumber, int pageSize, string? keyword = null, int? orgTypeLkpId = null);
        Task<ApiResponse<List<DynamicRow>>>        GetMembersAsync(int orgId);
        Task<ApiResponse>                          AddMemberAsync(int orgId, int requestedBy, AddMemberRequest request);
        Task<ApiResponse>                          RemoveMemberAsync(int orgId, int userId, int requestedBy);
        Task<ApiResponse>                          RequestMembershipAsync(int orgId, int userId, RequestMembershipRequest request);
        Task<ApiResponse>                          ReviewMembershipAsync(int reviewedBy, ReviewMembershipRequest request);
        Task<ApiResponse<List<DynamicRow>>>        GetPendingMembersAsync(int orgId);
        Task<ApiResponse>                          UpdateMemberPermissionsAsync(int orgId, int updatedBy, UpdateMemberPermissionsRequest request);
        Task<ApiResponse>                          UploadDocumentAsync(int orgId, int userId, UploadOrgDocumentRequest request);
    }
}

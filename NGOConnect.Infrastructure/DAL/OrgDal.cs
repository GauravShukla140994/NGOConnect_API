using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Org;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class OrgDal : BaseDal, IOrgDal
    {
        public OrgDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<DynamicRow>> RegisterAsync(int userId, RegisterOrgRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Register", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgName",        request.OrgName);
                    _db.AddParameter(cmd, "p_RegistrationNo", request.RegistrationNumber);   // SP uses p_RegistrationNo
                    _db.AddParameter(cmd, "p_OrgTypeLkpId",   request.OrgTypeLkpId);
                    _db.AddParameter(cmd, "p_Category",       request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson",  request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",          request.About);
                    _db.AddParameter(cmd, "p_Mission",        request.Mission);
                    _db.AddParameter(cmd, "p_Vision",         request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",        request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",   request.Email);
                    _db.AddParameter(cmd, "p_ContactPhone",   request.Phone);
                    _db.AddParameter(cmd, "p_Website",        request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",   request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",   request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",           request.City);
                    _db.AddParameter(cmd, "p_State",          request.State);
                    _db.AddParameter(cmd, "p_Pincode",        request.Pincode);
                    _db.AddParameter(cmd, "p_Country",        request.Country);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "ORG_REGISTER_FAILED");

                var orgId = Col<int>(result.Row!, "OrgId");
                var row = await ExecuteDynamicGetAsync("Org_GetProfile",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));

                return ApiResponse<DynamicRow>.Success(row!, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RegisterAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetProfileAsync(int orgId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Org_GetProfile",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetProfileAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateAsync(int orgId, int userId, UpdateOrgRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",         orgId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_OrgName",       request.OrgName);
                    _db.AddParameter(cmd, "p_Category",      request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson", request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",         request.About);
                    _db.AddParameter(cmd, "p_Mission",       request.Mission);
                    _db.AddParameter(cmd, "p_Vision",        request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",       request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",  request.Email);
                    _db.AddParameter(cmd, "p_ContactPhone",  request.Phone);
                    _db.AddParameter(cmd, "p_Website",       request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",  request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",  request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",          request.City);
                    _db.AddParameter(cmd, "p_State",         request.State);
                    _db.AddParameter(cmd, "p_Pincode",       request.Pincode);
                    _db.AddParameter(cmd, "p_Country",       request.Country);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<OrgDashboardModel>> GetDashboardAsync(int orgId)
        {
            try
            {
                var row = await ExecuteGetAsync("Org_GetDashboard",
                    r => new OrgDashboardModel
                    {
                        TotalMembers        = Col<int>(r,     "TotalMembers"),
                        NewMembersThisMonth = Col<int>(r,     "NewMembersThisMonth"),
                        ActiveVolunteers    = Col<int>(r,     "ActiveVolunteers"),
                        ActiveRatePct       = Col<decimal>(r, "ActiveRatePct"),
                        VolunteerHoursMonth = Col<decimal>(r, "VolunteerHoursMonth"),
                        ActiveProjects      = Col<int>(r,     "ActiveProjects"),
                        PendingApplications = Col<int>(r,     "PendingApplications"),
                    },
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));

                return row is null
                    ? ApiResponse<OrgDashboardModel>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<OrgDashboardModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDashboardAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<OrgDashboardModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(
            int pageNumber, int pageSize, string? keyword = null, int? orgTypeLkpId = null)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Org_List", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_Keyword",      keyword);
                    _db.AddParameter(cmd, "p_OrgTypeLkpId", orgTypeLkpId);
                    _db.AddParameter(cmd, "p_PageNumber",   pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",     pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ListAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetMembersAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_GetMembers",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMembersAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AddMemberAsync(int orgId, int requestedBy, AddMemberRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_AddMember", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_RequestedBy", requestedBy);
                    _db.AddParameter(cmd, "p_UserId",     request.UserId);
                    _db.AddParameter(cmd, "p_RoleLkpId",  request.RoleLkpId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddMemberAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RemoveMemberAsync(int orgId, int userId, int requestedBy)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_RemoveMember", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_RequestedBy", requestedBy);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RemoveMemberAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RequestMembershipAsync(int orgId, int userId, RequestMembershipRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_RequestMembership", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",   orgId);
                    _db.AddParameter(cmd, "p_UserId",  userId);
                    _db.AddParameter(cmd, "p_Message", request.Message);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RequestMembershipAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReviewMembershipAsync(int reviewedBy, ReviewMembershipRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_ReviewMembership", cmd =>
                {
                    _db.AddParameter(cmd, "p_MembershipRequestId", request.RequestId);
                    _db.AddParameter(cmd, "p_ReviewedBy",          reviewedBy);
                    _db.AddParameter(cmd, "p_StatusCode",          request.StatusCode);
                    _db.AddParameter(cmd, "p_AdminNotes",          request.AdminNotes);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReviewMembershipAsync failed ReviewedBy={ReviewedBy}", reviewedBy);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetPendingMembersAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_GetPendingMembers",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPendingMembersAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateMemberPermissionsAsync(int orgId, int updatedBy, UpdateMemberPermissionsRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_UpdateMemberPermissions", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",                orgId);
                    _db.AddParameter(cmd, "p_UpdatedBy",            updatedBy);
                    _db.AddParameter(cmd, "p_MemberId",             request.MemberId);
                    _db.AddParameter(cmd, "p_CanPost",              request.CanPost);
                    _db.AddParameter(cmd, "p_CanComment",           request.CanComment);
                    _db.AddParameter(cmd, "p_CanCommunityPost",     request.CanCommunityPost);
                    _db.AddParameter(cmd, "p_MaxPostsPerDay",       request.MaxPostsPerDay);
                    _db.AddParameter(cmd, "p_LocationSharingLkpId", request.LocationSharingLkpId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateMemberPermissionsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UploadDocumentAsync(int orgId, int userId, UploadOrgDocumentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_UploadDocument", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",             orgId);
                    _db.AddParameter(cmd, "p_UploadedBy",        userId);
                    _db.AddParameter(cmd, "p_DocumentTypeLkpId", request.DocumentTypeLkpId);
                    _db.AddParameter(cmd, "p_FileUrl",           request.FileUrl);
                    _db.AddParameter(cmd, "p_FileName",          request.FileName);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UploadDocumentAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

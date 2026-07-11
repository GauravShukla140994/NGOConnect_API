using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Org;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/org")]
    [Produces("application/json")]
    public class OrgController : ControllerBase
    {
        private readonly IOrgDal _org;
        public OrgController(IOrgDal org) => _org = org;

        [HttpPost] [Authorize]
        public async Task<ApiResponse<DynamicRow>> Register([FromBody] RegisterOrgRequest request)
            => await _org.RegisterAsync(GetUserId(), request);

        [HttpGet("{orgId:int}")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> GetProfile(int orgId)
            => await _org.GetProfileAsync(orgId, GetUserId());

        // Admin dashboard KPIs — Total Members, Active Volunteers, Hours, Active Projects, Pending
        [HttpGet("{orgId:int}/dashboard")] [Authorize]
        public async Task<ApiResponse<OrgDashboardModel>> GetDashboard(int orgId)
            => await _org.GetDashboardAsync(orgId);

        [HttpPut("{orgId:int}")] [Authorize]
        public async Task<ApiResponse> Update(int orgId, [FromBody] UpdateOrgRequest request)
            => await _org.UpdateAsync(orgId, GetUserId(), request);

        // v4.5 — founder resubmits after Super Admin rejection. Only works when the
        // org is currently REJECTED and the caller is the founder (enforced in Org_Resubmit).
        [HttpPut("{orgId:int}/resubmit")] [Authorize]
        public async Task<ApiResponse> Resubmit(int orgId, [FromBody] ResubmitOrgRequest request)
            => await _org.ResubmitAsync(orgId, GetUserId(), request);

        // s-explore → All NGOs tab (paginated, filterable by keyword + category)
        // lat/lng optional — when provided, SP sorts nearest-first via server-side Haversine
        [HttpGet("list")]
        public async Task<ApiResponse<PagedResult<OrgListItemModel>>> List(
            [FromQuery] string?  keyword    = null,
            [FromQuery] string?  category   = null,
            [FromQuery] int      pageNumber = 1,
            [FromQuery] int      pageSize   = 20,
            [FromQuery] decimal? lat        = null,
            [FromQuery] decimal? lng        = null)
            => await _org.ListAsync(pageNumber, pageSize, keyword, category, lat, lng);

        // s-explore → Recommended tab (matched to user's interests)
        [HttpGet("recommended")] [Authorize]
        public async Task<ApiResponse<List<RecommendedOrgModel>>> GetRecommended()
            => await _org.GetRecommendedAsync(GetUserId());

        // s-explore → Trending Campaigns tab
        [HttpGet("trending-campaigns")]
        public async Task<ApiResponse<List<TrendingCampaignModel>>> GetTrendingCampaigns(
            [FromQuery] int pageSize = 10)
            => await _org.GetTrendingCampaignsAsync(pageSize);

        [HttpGet("{orgId:int}/members")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetMembers(int orgId)
            => await _org.GetMembersAsync(orgId);

        [HttpPost("{orgId:int}/members")] [Authorize]
        public async Task<ApiResponse> AddMember(int orgId, [FromBody] AddMemberRequest request)
            => await _org.AddMemberAsync(orgId, GetUserId(), request);

        [HttpDelete("{orgId:int}/members/{userId:int}")] [Authorize]
        public async Task<ApiResponse> RemoveMember(int orgId, int userId)
            => await _org.RemoveMemberAsync(orgId, userId, GetUserId());

        // v4.0 — membership request flow
        [HttpPost("{orgId:int}/membership-request")] [Authorize]
        public async Task<ApiResponse> RequestMembership(int orgId, [FromBody] RequestMembershipRequest request)
            => await _org.RequestMembershipAsync(orgId, GetUserId(), request);

        [HttpPut("{orgId:int}/membership-request/review")] [Authorize]
        public async Task<ApiResponse> ReviewMembership(int orgId, [FromBody] ReviewMembershipRequest request)
            => await _org.ReviewMembershipAsync(GetUserId(), request);

        [HttpGet("{orgId:int}/members/pending")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetPendingMembers(int orgId)
            => await _org.GetPendingMembersAsync(orgId);

        [HttpPut("{orgId:int}/members/permissions")] [Authorize]
        public async Task<ApiResponse> UpdateMemberPermissions(int orgId, [FromBody] UpdateMemberPermissionsRequest request)
            => await _org.UpdateMemberPermissionsAsync(orgId, GetUserId(), request);

        // s-admin-vols → change a member's role (VOLUNTEER / COORDINATOR / ADMIN)
        [HttpPut("{orgId:int}/members/role")] [Authorize]
        public async Task<ApiResponse> UpdateMemberRole(int orgId, [FromBody] UpdateMemberRoleRequest request)
            => await _org.UpdateMemberRoleAsync(orgId, GetUserId(), request);

        // s-vol-profile → admin view of a specific volunteer (includes reliability score)
        [HttpGet("{orgId:int}/volunteers/{userId:int}")] [Authorize]
        public async Task<ApiResponse<OrgVolunteerProfileModel>> GetVolunteerProfile(int orgId, int userId)
            => await _org.GetVolunteerProfileAsync(orgId, userId);

        // s-member-impact → admin view of a member's full impact stats
        [HttpGet("{orgId:int}/members/{userId:int}/impact")] [Authorize]
        public async Task<ApiResponse<OrgMemberImpactModel>> GetMemberImpact(int orgId, int userId)
            => await _org.GetMemberImpactAsync(orgId, userId);

        // s-vol-profile / s-participants → award a badge to a volunteer
        [HttpPost("{orgId:int}/badges")] [Authorize]
        public async Task<ApiResponse> AwardBadge(int orgId, [FromBody] AwardBadgeRequest request)
            => await _org.AwardBadgeAsync(orgId, GetUserId(), request);

        // s-participants → excuse a no-show so it doesn't penalise reliability score
        [HttpPost("{orgId:int}/attendance/excuse")] [Authorize]
        public async Task<ApiResponse> ExcuseNoShow(int orgId, [FromBody] ExcuseNoShowRequest request)
            => await _org.ExcuseNoShowAsync(orgId, GetUserId(), request);

        // s-admin-donations → donation dashboard KPIs
        [HttpGet("{orgId:int}/donation-dashboard")] [Authorize]
        public async Task<ApiResponse<OrgDonationDashboardModel>> GetDonationDashboard(int orgId)
            => await _org.GetDonationDashboardAsync(orgId);

        // s-admin-donors → paginated donor list (tab: ALL | RECURRING | TOP)
        [HttpGet("{orgId:int}/donors")] [Authorize]
        public async Task<ApiResponse<PagedResult<OrgDonorModel>>> GetDonors(
            int orgId,
            [FromQuery] string tab        = "ALL",
            [FromQuery] int    pageNumber = 1,
            [FromQuery] int    pageSize   = 20)
            => await _org.GetDonorsAsync(orgId, tab, pageNumber, pageSize);

        // s-admin-transactions → paginated transaction list (filter by statusCode)
        [HttpGet("{orgId:int}/transactions")] [Authorize]
        public async Task<ApiResponse<PagedResult<OrgTransactionModel>>> GetTransactions(
            int orgId,
            [FromQuery] string? statusCode = null,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 20)
            => await _org.GetTransactionsAsync(orgId, statusCode, pageNumber, pageSize);

        [HttpPost("{orgId:int}/documents")] [Authorize]
        public async Task<ApiResponse> UploadDocument(int orgId, [FromBody] UploadOrgDocumentRequest request)
            => await _org.UploadDocumentAsync(orgId, GetUserId(), request);

        // ── Admin Posts (s-admin-vols Posts tab) ──────────────────────────────────

        [HttpGet("{orgId:int}/community-posts/admin")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetAdminPosts(int orgId)
            => await _org.GetAdminPostsAsync(orgId);

        [HttpPost("{orgId:int}/community-posts/{postId:int}/pin")] [Authorize]
        public async Task<ApiResponse> PinPost(int orgId, int postId)
            => await _org.PinPostAsync(orgId, postId, GetUserId());

        [HttpDelete("{orgId:int}/community-posts/{postId:int}")] [Authorize]
        public async Task<ApiResponse> DeletePost(int orgId, int postId)
            => await _org.DeletePostAsync(orgId, postId, GetUserId());

        [HttpPost("{orgId:int}/community-posts/{postId:int}/moderate")] [Authorize]
        public async Task<ApiResponse> ModeratePost(int orgId, int postId, [FromBody] ModeratePostRequest request)
            => await _org.ModeratePostAsync(orgId, postId, GetUserId(), request.Action);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

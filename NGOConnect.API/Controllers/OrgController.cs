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

        [HttpGet("{orgId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetProfile(int orgId)
            => await _org.GetProfileAsync(orgId);

        [HttpPut("{orgId:int}")] [Authorize]
        public async Task<ApiResponse> Update(int orgId, [FromBody] UpdateOrgRequest request)
            => await _org.UpdateAsync(orgId, GetUserId(), request);

        [HttpGet("list")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> List(
            [FromQuery] string? keyword      = null,
            [FromQuery] int?    orgTypeLkpId = null,
            [FromQuery] int     pageNumber   = 1,
            [FromQuery] int     pageSize     = 20)
            => await _org.ListAsync(pageNumber, pageSize, keyword, orgTypeLkpId);

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

        [HttpPost("{orgId:int}/documents")] [Authorize]
        public async Task<ApiResponse> UploadDocument(int orgId, [FromBody] UploadOrgDocumentRequest request)
            => await _org.UploadDocumentAsync(orgId, GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Withdrawal;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/withdrawal")]
    [Authorize]
    [Produces("application/json")]
    public class WithdrawalController : ControllerBase
    {
        private readonly IWithdrawalDal _withdrawal;
        public WithdrawalController(IWithdrawalDal withdrawal) => _withdrawal = withdrawal;

        [HttpPost("org/{orgId:int}")]
        public async Task<ApiResponse<DynamicRow>> Create(int orgId, [FromBody] CreateWithdrawalRequest request)
            => await _withdrawal.CreateAsync(orgId, GetUserId(), request);

        [HttpGet("org/{orgId:int}")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetByOrg(
            int orgId,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _withdrawal.GetByOrgAsync(orgId, pageNumber, pageSize);

        [HttpPut("admin-review")]
        public async Task<ApiResponse> AdminReview([FromBody] AdminReviewWithdrawalRequest request)
        {
            request.ReviewedBy = GetUserId();
            return await _withdrawal.AdminReviewAsync(request);
        }

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

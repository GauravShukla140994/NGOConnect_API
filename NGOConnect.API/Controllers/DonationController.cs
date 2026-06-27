using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Donation;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/donation")]
    [Produces("application/json")]
    public class DonationController : ControllerBase
    {
        private readonly IDonationDal _donation;
        public DonationController(IDonationDal donation) => _donation = donation;

        // Campaigns
        [HttpPost("campaigns")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> CreateCampaign([FromBody] CreateCampaignRequest request)
            => await _donation.CreateCampaignAsync(GetUserId(), request);

        [HttpGet("campaigns")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetCampaigns(
            [FromQuery] int?    orgId      = null,
            [FromQuery] string? keyword    = null,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 20)
            => await _donation.GetCampaignsAsync(orgId, keyword, pageNumber, pageSize);

        [HttpGet("campaigns/{campaignId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetCampaignById(int campaignId)
            => await _donation.GetCampaignByIdAsync(campaignId);

        [HttpGet("campaigns/{campaignId:int}/donors")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetDonors(
            int campaignId,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _donation.GetDonorsAsync(campaignId, pageNumber, pageSize);

        // Donation flow
        [HttpPost("donate")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> Initiate([FromBody] InitiateDonationRequest request)
            => await _donation.InitiateDonationAsync(GetUserId(), request);

        [HttpPost("confirm-payment")] [Authorize]
        public async Task<ApiResponse> ConfirmPayment([FromBody] ConfirmPaymentRequest request)
            => await _donation.ConfirmPaymentAsync(GetUserId(), request);

        [HttpGet("history")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetHistory(
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _donation.GetHistoryAsync(GetUserId(), pageNumber, pageSize);

        [HttpGet("receipts/{donationId:int}")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> GetReceipt(int donationId)
            => await _donation.GetReceiptAsync(donationId, GetUserId());

        // Recurring
        [HttpPost("recurring")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> SetupRecurring([FromBody] SetupRecurringRequest request)
            => await _donation.SetupRecurringAsync(GetUserId(), request);

        [HttpPut("recurring/{recurringId:int}/pause")] [Authorize]
        public async Task<ApiResponse> PauseRecurring(int recurringId)
            => await _donation.PauseRecurringAsync(recurringId, GetUserId());

        [HttpPut("recurring/{recurringId:int}/resume")] [Authorize]
        public async Task<ApiResponse> ResumeRecurring(int recurringId)
            => await _donation.ResumeRecurringAsync(recurringId, GetUserId());

        [HttpDelete("recurring/{recurringId:int}")] [Authorize]
        public async Task<ApiResponse> CancelRecurring(int recurringId)
            => await _donation.CancelRecurringAsync(recurringId, GetUserId());

        // Analytics
        [HttpGet("annual-summary")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> GetAnnualSummary([FromQuery] int year = 0)
            => await _donation.GetAnnualSummaryAsync(GetUserId(), year == 0 ? DateTime.Now.Year : year);

        [HttpGet("supported-ngos")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetSupportedNGOs()
            => await _donation.GetSupportedNGOsAsync(GetUserId());

        [HttpGet("org/{orgId:int}/transactions")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgTransactions(
            int orgId,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _donation.GetOrgTransactionsAsync(orgId, pageNumber, pageSize);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

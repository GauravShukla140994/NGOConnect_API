using System.Security.Claims;
using Hangfire;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Marketing & Communication Center — Phase 0 + Phase 1 (Push + Email only).
    /// Super Admin only, per the platform's own Communication Center spec: only
    /// Super Admin can create/edit/approve/send/cancel campaigns.
    /// See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    [ApiController]
    [Route("api/v1/superadmin")]
    [Produces("application/json")]
    [Authorize(Roles = "SUPER_ADMIN")]
    public class CampaignController : ControllerBase
    {
        private readonly ICampaignDal _campaigns;
        private readonly ICampaignDispatchService _dispatch;
        private readonly IBackgroundJobClient _jobs;

        public CampaignController(ICampaignDal campaigns, ICampaignDispatchService dispatch, IBackgroundJobClient jobs)
        {
            _campaigns = campaigns;
            _dispatch  = dispatch;
            _jobs      = jobs;
        }

        // ── Dashboard ─────────────────────────────────────────────

        [HttpGet("communication/dashboard")]
        public async Task<ApiResponse<DynamicRow>> GetDashboard()
            => await _campaigns.GetDashboardStatsAsync();

        // ── Campaign CRUD ─────────────────────────────────────────

        [HttpGet("campaigns")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetList(
            [FromQuery] string? statusCode = null,
            [FromQuery] string? search     = null,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 20)
            => await _campaigns.GetListAsync(statusCode, search, pageNumber, pageSize);

        [HttpGet("campaigns/{campaignId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetById(int campaignId)
            => await _campaigns.GetByIdAsync(campaignId);

        [HttpPost("campaigns")]
        public async Task<ApiResponse<int>> Create([FromBody] CreateCampaignRequest request)
            => await _campaigns.CreateAsync(request, GetSuperAdminUserId());

        [HttpPut("campaigns/{campaignId:int}")]
        public async Task<ApiResponse> Update(int campaignId, [FromBody] UpdateCampaignRequest request)
            => await _campaigns.UpdateAsync(campaignId, request, GetSuperAdminUserId());

        // ── Channels (Push + Email only in Phase 1) ──────────────

        [HttpPost("campaigns/{campaignId:int}/channels")]
        public async Task<ApiResponse> SaveChannel(int campaignId, [FromBody] SaveCampaignChannelRequest request)
            => await _campaigns.SaveChannelAsync(campaignId, request);

        [HttpDelete("campaigns/{campaignId:int}/channels/{channelCode}")]
        public async Task<ApiResponse> DeleteChannel(int campaignId, string channelCode)
            => await _campaigns.DeleteChannelAsync(campaignId, channelCode);

        // ── Audience ──────────────────────────────────────────────

        [HttpPost("campaigns/{campaignId:int}/audience")]
        public async Task<ApiResponse> SaveAudience(int campaignId, [FromBody] SaveAudienceRuleRequest request)
            => await _campaigns.SaveAudienceRuleAsync(campaignId, request);

        [HttpPost("campaigns/{campaignId:int}/estimate-audience")]
        public async Task<ApiResponse<DynamicRow>> EstimateAudience(int campaignId)
            => await _campaigns.EstimateAudienceAsync(campaignId);

        // ── Test Send ─────────────────────────────────────────────

        [HttpPost("campaigns/{campaignId:int}/test-send")]
        public async Task<ApiResponse> TestSend(int campaignId, [FromBody] TestSendRequest request)
            => await _dispatch.TestSendAsync(campaignId, request.UserIds);

        // ── Send / Schedule / Cancel ──────────────────────────────

        // Enqueues the Hangfire dispatch job immediately. The job itself resolves
        // recipients, sends in batches, and marks the campaign RUNNING → COMPLETED.
        [HttpPost("campaigns/{campaignId:int}/send")]
        public async Task<ApiResponse> Send(int campaignId)
        {
            var jobId  = _jobs.Enqueue<ICampaignDispatchService>(x => x.DispatchAsync(campaignId));
            var result = await _campaigns.SetStatusAsync(campaignId, "SCHEDULED", jobId, GetSuperAdminUserId());

            if (result.IsSuccess != 1)
                Log.Warning("Campaign {CampaignId} send: status transition rejected ({Message}) but job {JobId} was already enqueued",
                    campaignId, result.Message, jobId);

            Log.Information("Campaign {CampaignId} enqueued for immediate send. HangfireJobId={JobId}", campaignId, jobId);
            return ApiResponse.Ok("Campaign queued for sending.");
        }

        [HttpPost("campaigns/{campaignId:int}/schedule")]
        public async Task<ApiResponse> Schedule(int campaignId, [FromBody] ScheduleCampaignRequest request)
        {
            var update = await _campaigns.UpdateAsync(campaignId, new UpdateCampaignRequest
            {
                ScheduleType = "SCHEDULED",
                ScheduledAt  = request.ScheduledAt,
                TimezoneName = request.TimezoneName
            }, GetSuperAdminUserId());
            if (update.IsSuccess != 1) return update;

            var delay = request.ScheduledAt - DateTime.UtcNow;
            if (delay < TimeSpan.Zero) delay = TimeSpan.Zero;

            var jobId = _jobs.Schedule<ICampaignDispatchService>(x => x.DispatchAsync(campaignId), delay);
            await _campaigns.SetStatusAsync(campaignId, "SCHEDULED", jobId, GetSuperAdminUserId());

            Log.Information("Campaign {CampaignId} scheduled for {ScheduledAt}. HangfireJobId={JobId}", campaignId, request.ScheduledAt, jobId);
            return ApiResponse.Ok("Campaign scheduled.");
        }

        [HttpPost("campaigns/{campaignId:int}/cancel")]
        public async Task<ApiResponse> Cancel(int campaignId)
            => await _campaigns.SetStatusAsync(campaignId, "CANCELLED", null, GetSuperAdminUserId());

        // ── History ───────────────────────────────────────────────

        [HttpGet("campaigns/{campaignId:int}/history")]
        public async Task<ApiResponse<DynamicRow>> GetHistoryDetail(int campaignId)
            => await _campaigns.GetHistoryDetailAsync(campaignId);

        // Per-recipient drill-down (phone/email/name + individual status) for a
        // campaign — lets Super Admin see exactly who got delivered/failed and why,
        // not just aggregate counts.
        [HttpGet("campaigns/{campaignId:int}/recipients")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetRecipients(
            int campaignId,
            [FromQuery] string? statusCode = null,
            [FromQuery] int     pageNumber = 1,
            [FromQuery] int     pageSize   = 20)
            => await _campaigns.GetRecipientListAsync(campaignId, statusCode, pageNumber, pageSize);

        // ── Helpers ───────────────────────────────────────────────

        private int GetSuperAdminUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

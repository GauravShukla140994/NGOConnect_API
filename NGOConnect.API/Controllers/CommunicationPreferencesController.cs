using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Self-service opt-in/opt-out preferences — any authenticated user (volunteer,
    /// NGO admin, donor…), NOT restricted to Super Admin. Checked by the Communication
    /// Center dispatcher before every promotional send; transactional messages (OTP,
    /// password reset, critical account alerts) never consult this.
    /// </summary>
    [ApiController]
    [Route("api/v1/communication-preferences")]
    [Produces("application/json")]
    [Authorize]
    public class CommunicationPreferencesController : ControllerBase
    {
        private readonly ICommunicationPreferenceDal _preferences;
        private readonly ICampaignDal                _campaigns;

        public CommunicationPreferencesController(ICommunicationPreferenceDal preferences, ICampaignDal campaigns)
        {
            _preferences = preferences;
            _campaigns   = campaigns;
        }

        [HttpGet]
        public async Task<ApiResponse<DynamicRow>> Get()
            => await _preferences.GetAsync(GetUserId());

        [HttpPut]
        public async Task<ApiResponse> Update([FromBody] UpdateCommunicationPreferencesRequest request)
            => await _preferences.UpdateAsync(GetUserId(), request);

        // ── Real delivery acknowledgment ──────────────────────────
        // Called by the mobile app itself the moment it actually renders a campaign
        // push (not by our own dispatch worker) — this is what makes "Delivered"
        // mean the device really got it, instead of just "FCM accepted the send
        // request". Absolute route (not nested under communication-preferences)
        // since this isn't really a preference — kept in this controller because
        // it's the existing "any authenticated user, communication-domain" home,
        // rather than adding a whole new controller for one endpoint.
        [HttpPost("/api/v1/campaign-recipients/{campaignRecipientId:long}/delivered")]
        public async Task<ApiResponse> AckDelivered(long campaignRecipientId)
            => await _campaigns.AckDeliveredAsync(campaignRecipientId, GetUserId());

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier) ?? User.FindFirst("sub");
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Sos;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/sos")]
    [Authorize]
    [Produces("application/json")]
    public class SosController : ControllerBase
    {
        private readonly ISosDal _sos;
        public SosController(ISosDal sos) => _sos = sos;

        /// <summary>Trigger a new SOS incident.</summary>
        [HttpPost]
        public async Task<ApiResponse<DynamicRow>> Trigger([FromBody] TriggerSosRequest request)
            => await _sos.TriggerAsync(GetUserId(), request);

        /// <summary>Get all active SOS incidents visible to the current user for their org.</summary>
        [HttpGet("active")]
        public async Task<ApiResponse<List<DynamicRow>>> GetActive([FromQuery] int? orgId = null)
            => await _sos.GetActiveAsync(GetUserId(), orgId);

        /// <summary>All SOS incidents for an org — active + resolved + cancelled, newest first (community history).
        /// Includes MyApprovalStatus for the calling user so the UI knows which button to show.</summary>
        [HttpGet("org-alerts")]
        public async Task<ApiResponse<List<DynamicRow>>> GetOrgAlerts([FromQuery] int orgId, [FromQuery] int limit = 20)
            => await _sos.GetOrgAlertsAsync(orgId, GetUserId(), limit);

        /// <summary>Get the current user's own active SOS incident (victim view — s-sos-active screen).</summary>
        [HttpGet("my-active")]
        public async Task<ApiResponse<DynamicRow>> GetMyActive()
            => await _sos.GetMyActiveAsync(GetUserId());

        /// <summary>Get SOS incident details + responders list (view-details button).</summary>
        [HttpGet("{sosIncidentId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetById(int sosIncidentId)
            => await _sos.GetByIdAsync(sosIncidentId, GetUserId());

        /// <summary>Respond to an active SOS — "I Can Assist".</summary>
        [HttpPost("{sosIncidentId:int}/respond")]
        public async Task<ApiResponse> Respond(int sosIncidentId)
            => await _sos.RespondAsync(sosIncidentId, GetUserId());

        /// <summary>Victim approves a responder and optionally grants location access.</summary>
        [HttpPut("{sosIncidentId:int}/approve-responder")]
        public async Task<ApiResponse> ApproveResponder(int sosIncidentId, [FromBody] ApproveResponderRequest request)
            => await _sos.ApproveResponderAsync(sosIncidentId, GetUserId(), request);

        /// <summary>Victim declines a responder request.</summary>
        [HttpPut("{sosIncidentId:int}/decline-responder")]
        public async Task<ApiResponse> DeclineResponder(int sosIncidentId, [FromBody] DeclineResponderRequest request)
            => await _sos.DeclineResponderAsync(sosIncidentId, GetUserId(), request);

        /// <summary>Mark SOS as resolved — no request body needed.</summary>
        [HttpPut("{sosIncidentId:int}/resolve")]
        public async Task<ApiResponse> Resolve(int sosIncidentId)
            => await _sos.ResolveAsync(sosIncidentId, GetUserId());

        /// <summary>Cancel SOS alert with optional reason.</summary>
        [HttpPut("{sosIncidentId:int}/cancel")]
        public async Task<ApiResponse> Cancel(int sosIncidentId, [FromBody] CancelSosRequest request)
            => await _sos.CancelAsync(sosIncidentId, GetUserId(), request);

        /// <summary>Get latest location of victim (approved responders only).</summary>
        [HttpGet("{sosIncidentId:int}/location")]
        public async Task<ApiResponse<DynamicRow>> GetLatestLocation(int sosIncidentId)
            => await _sos.GetLatestLocationAsync(sosIncidentId, GetUserId());

        /// <summary>Victim pushes their current GPS location (called every ~10 sec).</summary>
        [HttpPost("{sosIncidentId:int}/location")]
        public async Task<ApiResponse> UpdateLocation(int sosIncidentId, [FromBody] UpdateLocationRequest request)
            => await _sos.UpdateLocationAsync(sosIncidentId, GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

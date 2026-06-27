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

        [HttpPost]
        public async Task<ApiResponse<DynamicRow>> Trigger([FromBody] TriggerSosRequest request)
            => await _sos.TriggerAsync(GetUserId(), request);

        [HttpGet("active")]
        public async Task<ApiResponse<List<DynamicRow>>> GetActive([FromQuery] int? orgId = null)
            => await _sos.GetActiveAsync(GetUserId(), orgId);

        [HttpGet("{sosIncidentId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetById(int sosIncidentId)
            => await _sos.GetByIdAsync(sosIncidentId, GetUserId());

        [HttpPost("{sosIncidentId:int}/respond")]
        public async Task<ApiResponse> Respond(int sosIncidentId)
            => await _sos.RespondAsync(sosIncidentId, GetUserId());

        [HttpPut("{sosIncidentId:int}/approve-responder")]
        public async Task<ApiResponse> ApproveResponder(int sosIncidentId, [FromBody] ApproveResponderRequest request)
            => await _sos.ApproveResponderAsync(sosIncidentId, GetUserId(), request);

        [HttpPut("{sosIncidentId:int}/resolve")]
        public async Task<ApiResponse> Resolve(int sosIncidentId, [FromBody] ResolveSosRequest request)
            => await _sos.ResolveAsync(sosIncidentId, GetUserId(), request);

        [HttpPut("{sosIncidentId:int}/cancel")]
        public async Task<ApiResponse> Cancel(int sosIncidentId, [FromBody] CancelSosRequest request)
            => await _sos.CancelAsync(sosIncidentId, GetUserId(), request);

        [HttpGet("{sosIncidentId:int}/location")]
        public async Task<ApiResponse<DynamicRow>> GetLatestLocation(int sosIncidentId)
            => await _sos.GetLatestLocationAsync(sosIncidentId, GetUserId());

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

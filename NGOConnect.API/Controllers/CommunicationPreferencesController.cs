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

        public CommunicationPreferencesController(ICommunicationPreferenceDal preferences)
        {
            _preferences = preferences;
        }

        [HttpGet]
        public async Task<ApiResponse<DynamicRow>> Get()
            => await _preferences.GetAsync(GetUserId());

        [HttpPut]
        public async Task<ApiResponse> Update([FromBody] UpdateCommunicationPreferencesRequest request)
            => await _preferences.UpdateAsync(GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier) ?? User.FindFirst("sub");
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

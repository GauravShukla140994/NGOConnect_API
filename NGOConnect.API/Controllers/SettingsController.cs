using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Settings;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/settings")]
    public class SettingsController : ControllerBase
    {
        private readonly ISettingsDal    _settings;
        private readonly ISettingsCache  _cache;

        public SettingsController(ISettingsDal settings, ISettingsCache cache)
        {
            _settings = settings;
            _cache    = cache;
        }

        /// <summary>Get all public platform settings. No auth required. Frontend uses this for config.</summary>
        [HttpGet("public")]
        [AllowAnonymous]
        public async Task<IActionResult> GetPublic()
        {
            var list = await _settings.GetPublicSettingsAsync();
            return Ok(ApiResponse<List<SettingModel>>.Success(list, "Public settings retrieved."));
        }

        /// <summary>Get all settings in a group. Admin only.</summary>
        [HttpGet("{group}")]
        [Authorize]
        public async Task<IActionResult> GetByGroup(string group)
        {
            var list = await _settings.GetByGroupAsync(group);
            return Ok(ApiResponse<List<SettingModel>>.Success(list, $"Settings for group '{group}' retrieved."));
        }

        /// <summary>Update a setting value. Admin only. Auto-refreshes in-memory cache.</summary>
        [HttpPut("{key}")]
        [Authorize]
        public async Task<IActionResult> Update(string key, [FromBody] UpdateSettingRequest request)
        {
            var userId = GetCurrentUserId();
            var result = await _settings.UpdateAsync(key, request.SettingValue, userId);
            if (result.IsSuccess == 1)
                await _cache.RefreshAsync();  // keep memory in sync
            return Ok(result);
        }

        private int GetCurrentUserId()
            => int.TryParse(User.FindFirst("uid")?.Value, out var id) ? id : 0;
    }
}

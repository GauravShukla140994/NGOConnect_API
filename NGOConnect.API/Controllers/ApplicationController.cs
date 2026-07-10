using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Application;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1")]
    [Authorize]
    public class ApplicationController : ControllerBase
    {
        private readonly IApplicationDal _app;
        public ApplicationController(IApplicationDal app) => _app = app;

        /// <summary>Apply to a volunteer project.</summary>
        [HttpPost("project/{projectId:int}/apply")]
        public async Task<IActionResult> Apply(int projectId, [FromBody] ApplyRequest request)
            => Ok(await _app.ApplyAsync(projectId, GetCurrentUserId(), request));

        /// <summary>Approve or reject an application.</summary>
        [HttpPut("applications/{applicationId:int}")]
        public async Task<IActionResult> Review(int applicationId, [FromBody] ReviewApplicationRequest request)
            => Ok(await _app.ReviewAsync(applicationId, GetCurrentUserId(), request));

        /// <summary>Get my own applications across all projects.</summary>
        [HttpGet("user/applications")]
        public async Task<IActionResult> GetMyApplications()
            => Ok(await _app.GetMyApplicationsAsync(GetCurrentUserId()));

        private int GetCurrentUserId()
            => int.TryParse(User.FindFirst("uid")?.Value, out var id) ? id : 0;
    }
}

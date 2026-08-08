using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/project")]
    [Produces("application/json")]
    public class ProjectController : ControllerBase
    {
        private readonly IProjectDal _project;
        public ProjectController(IProjectDal project) => _project = project;

        [HttpPost] [Authorize]
        public async Task<ApiResponse<DynamicRow>> Create([FromBody] CreateProjectRequest request)
            => await _project.CreateAsync(GetUserId(), request);

        [HttpGet("{projectId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetById(int projectId)
            => await _project.GetByIdAsync(projectId, GetUserId());

        [HttpPut("{projectId:int}")] [Authorize]
        public async Task<ApiResponse> Update(int projectId, [FromBody] UpdateProjectRequest request)
            => await _project.UpdateAsync(projectId, GetUserId(), request);

        [HttpGet("list")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> List(
            [FromQuery] int?     orgId      = null,
            [FromQuery] string?  category   = null,
            [FromQuery] string?  city       = null,
            [FromQuery] string?  statusCode = null,
            [FromQuery] string?  typeCode   = null,
            [FromQuery] string?  keyword    = null,
            [FromQuery] int      pageNumber = 1,
            [FromQuery] int      pageSize   = 20,
            [FromQuery] decimal? userLat    = null,
            [FromQuery] decimal? userLon    = null)
            => await _project.ListAsync(pageNumber, pageSize, orgId, category, city, statusCode, typeCode, keyword, userLat, userLon);

        [HttpGet("nearby-feed")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetNearbyFeed(
            [FromQuery] decimal? userLat    = null,
            [FromQuery] decimal? userLon    = null,
            [FromQuery] int      pageNumber = 1,
            [FromQuery] int      pageSize   = 10)
            => await _project.GetNearbyFeedAsync(GetUserId(), userLat, userLon, pageNumber, pageSize);

        [HttpPost("{projectId:int}/skills")] [Authorize]
        public async Task<ApiResponse> AddSkill(int projectId, [FromBody] AddProjectSkillRequest request)
            => await _project.AddSkillAsync(projectId, GetUserId(), request);

        [HttpGet("{projectId:int}/skills")]
        public async Task<ApiResponse<List<DynamicRow>>> GetSkills(int projectId)
            => await _project.GetSkillsAsync(projectId);

        [HttpGet("{projectId:int}/skill-ratings/{userId:int}")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetSkillRatings(int projectId, int userId)
            => await _project.GetSkillRatingsAsync(projectId, userId);

        // Sessions
        [HttpPost("{projectId:int}/sessions")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> AddSession(int projectId, [FromBody] CreateSessionRequest request)
            => await _project.AddSessionAsync(projectId, GetUserId(), request);

        [HttpGet("{projectId:int}/sessions")]
        public async Task<ApiResponse<List<DynamicRow>>> GetSessions(int projectId)
            => await _project.GetSessionsAsync(projectId);

        [HttpGet("{projectId:int}/sessions/{sessionId:int}/qr")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> GetSessionQr(int projectId, int sessionId)
            => await _project.GetSessionQrAsync(sessionId, GetUserId());

        [HttpPost("{projectId:int}/sessions/checkin")] [Authorize]
        public async Task<ApiResponse> CheckIn(int projectId, [FromBody] CheckInRequest request)
            => await _project.CheckInAsync(GetUserId(), request);

        [HttpPost("{projectId:int}/self-checkin")] [Authorize]
        public async Task<ApiResponse> SelfCheckIn(int projectId)
            => await _project.SelfCheckInAsync(projectId, GetUserId());

        // Applications — Apply is handled by ApplicationController (POST api/v1/project/{projectId}/apply)
        [HttpPut("{projectId:int}/applications/review")] [Authorize]
        public async Task<ApiResponse> ReviewApplication(int projectId, [FromBody] ReviewApplicationRequest request)
            => await _project.ReviewApplicationAsync(GetUserId(), request);

        [HttpGet("{projectId:int}/applications")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetApplications(
            int projectId,
            [FromQuery] string? statusCode = null,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _project.GetApplicationsAsync(projectId, pageNumber, pageSize, statusCode);

        // Complete
        [HttpPost("{projectId:int}/complete")] [Authorize]
        public async Task<ApiResponse> Complete(int projectId, [FromBody] CompleteProjectRequest request)
            => await _project.CompleteAsync(projectId, GetUserId(), request);

        // Cancel
        [HttpPost("{projectId:int}/cancel")] [Authorize]
        public async Task<ApiResponse> Cancel(int projectId, [FromBody] CancelProjectRequest request)
            => await _project.CancelAsync(projectId, GetUserId(), request);

        // Manual attendance override (admin marks a volunteer as attended)
        [HttpPost("{projectId:int}/attendance/manual")] [Authorize]
        public async Task<ApiResponse> ManualAttendance(int projectId, [FromBody] ManualAttendanceRequest request)
            => await _project.ManualAttendanceAsync(GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

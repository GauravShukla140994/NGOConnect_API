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
            => await _project.ListAsync(pageNumber, pageSize, orgId, category, city, statusCode, typeCode, keyword, userLat, userLon, GetUserId());

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

        // Admin remove volunteer (sets application WITHDRAWN, frees slot)
        // Using POST instead of DELETE: Railway's Nginx proxy drops DELETE response bodies,
        // causing the mobile client to receive a connection reset even when the SP succeeds.
        [HttpPost("{projectId:int}/participants/{userId:int}/remove")] [Authorize]
        public async Task<ApiResponse> AdminRemoveVolunteer(int projectId, int userId)
            => await _project.AdminRemoveVolunteerAsync(projectId, userId, GetUserId());

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

        // ── v5.1: FLEXIBLE check-in / check-out ─────────────────────────────────────
        [HttpPost("{projectId:int}/flex-checkin")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> FlexCheckIn(int projectId)
            => await _project.FlexCheckInAsync(projectId, GetUserId());

        [HttpPost("{projectId:int}/flex-checkout")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> FlexCheckOut(int projectId)
            => await _project.FlexCheckOutAsync(projectId, GetUserId());

        // ── v5.1: Finalize Closing → COMPLETED (admin) ──────────────────────────────
        [HttpPost("{projectId:int}/finalize")] [Authorize]
        public async Task<ApiResponse> FinalizeClosing(int projectId, [FromBody] FinalizeClosingRequest request)
            => await _project.FinalizeClosingAsync(projectId, GetUserId(), request);

        // ── v5.1: Session management ─────────────────────────────────────────────────
        [HttpPost("{projectId:int}/sessions/{sessionId:int}/cancel")] [Authorize]
        public async Task<ApiResponse> CancelSession(int projectId, int sessionId, [FromBody] CancelSessionRequest request)
            => await _project.CancelSessionAsync(sessionId, GetUserId(), request);

        [HttpPost("{projectId:int}/sessions/optout")] [Authorize]
        public async Task<ApiResponse> SessionOptOut(int projectId, [FromBody] SessionOptOutRequest request)
            => await _project.SessionOptOutAsync(GetUserId(), request);

        // ── v5.1: Session-level skill rating (admin) ─────────────────────────────────
        [HttpPost("{projectId:int}/sessions/skill-rating")] [Authorize]
        public async Task<ApiResponse> AddSessionSkillRating(int projectId, [FromBody] SessionSkillRatingRequest request)
            => await _project.AddSessionSkillRatingAsync(GetUserId(), request);

        // ── v5.1: Per-session breakdown for a volunteer ───────────────────────────────
        [HttpGet("{projectId:int}/my-sessions/{userId:int}")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetMySessionList(int projectId, int userId)
            => await _project.GetMySessionListAsync(projectId, userId);

        // ── v5.1: Volunteer eligibility (attendance % + cert eligibility) ─────────────
        [HttpGet("{projectId:int}/eligibility/{userId:int}")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> GetVolunteerEligibility(int projectId, int userId)
            => await _project.GetVolunteerEligibilityAsync(projectId, userId);

        // ── v5.1: Milestone check ─────────────────────────────────────────────────────
        [HttpGet("{projectId:int}/milestone/{userId:int}")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> CheckMilestone(int projectId, int userId)
            => await _project.CheckMilestoneAsync(projectId, userId);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

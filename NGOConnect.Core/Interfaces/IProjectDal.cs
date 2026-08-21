using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;

namespace NGOConnect.Core.Interfaces
{
    public interface IProjectDal
    {
        Task<ApiResponse<DynamicRow>>              CreateAsync(int userId, CreateProjectRequest request);
        Task<ApiResponse<DynamicRow>>              GetByIdAsync(int projectId, int userId = 0);
        Task<ApiResponse>                          UpdateAsync(int projectId, int userId, UpdateProjectRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(int pageNumber, int pageSize, int? orgId = null, string? category = null, string? city = null, string? statusCode = null, string? typeCode = null, string? keyword = null, decimal? userLat = null, decimal? userLon = null, int userId = 0);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetNearbyFeedAsync(int userId, decimal? userLat, decimal? userLon, int pageNumber, int pageSize);
        Task<ApiResponse>                          AddSkillAsync(int projectId, int userId, AddProjectSkillRequest request);
        Task<ApiResponse<List<DynamicRow>>>        GetSkillsAsync(int projectId);
        Task<ApiResponse<List<DynamicRow>>>        GetSkillRatingsAsync(int projectId, int userId);

        // Sessions
        Task<ApiResponse<DynamicRow>>              AddSessionAsync(int projectId, int userId, CreateSessionRequest request);
        Task<ApiResponse<List<DynamicRow>>>        GetSessionsAsync(int projectId);
        Task<ApiResponse<DynamicRow>>              GetSessionQrAsync(int sessionId, int userId);
        Task<ApiResponse>                          CheckInAsync(int userId, CheckInRequest request);
        Task<ApiResponse>                          SelfCheckInAsync(int projectId, int userId);

        // Applications
        Task<ApiResponse>                          ApplyAsync(int projectId, int userId);
        Task<ApiResponse>                          ReviewApplicationAsync(int reviewedBy, ReviewApplicationRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetApplicationsAsync(int projectId, int pageNumber, int pageSize, string? statusCode = null);

        /// <summary>Admin removes an APPROVED volunteer — sets application to WITHDRAWN and frees the slot.</summary>
        Task<ApiResponse>                          AdminRemoveVolunteerAsync(int projectId, int userId, int removedBy);

        // Complete / Cancel
        Task<ApiResponse>                          CompleteAsync(int projectId, int userId, CompleteProjectRequest request);
        Task<ApiResponse>                          CancelAsync(int projectId, int userId, CancelProjectRequest request);

        // Manual attendance override (admin)
        Task<ApiResponse>                          ManualAttendanceAsync(int markedBy, ManualAttendanceRequest request);

        // Excuse a no-show (admin — marks IsNoShowExcused = 1, excludes from reliability penalty)
        Task<ApiResponse>                          ExcuseNoShowAsync(int attendanceId, int excusedBy);
        Task<ApiResponse>                          ConfirmNoShowAsync(int attendanceId, int confirmedBy);

        // ── v5.1: RECURRING + FLEXIBLE flow ─────────────────────────────────────────

        /// <summary>FLEXIBLE self check-in within the session window. SP validates type + window + APPROVED status.</summary>
        Task<ApiResponse<DynamicRow>>              FlexCheckInAsync(int projectId, int userId);

        /// <summary>FLEXIBLE self check-out. Computes hours, applies MaxDailyHours cap.</summary>
        Task<ApiResponse<DynamicRow>>              FlexCheckOutAsync(int projectId, int userId);

        /// <summary>Admin finalises a CLOSING project → COMPLETED + aggregates session skill ratings.</summary>
        Task<ApiResponse>                          FinalizeClosingAsync(int projectId, int completedBy, FinalizeClosingRequest request);

        /// <summary>Admin cancels a single session.</summary>
        Task<ApiResponse>                          CancelSessionAsync(int sessionId, int cancelledBy, CancelSessionRequest request);

        /// <summary>Volunteer (or admin) opts out of a specific session.</summary>
        Task<ApiResponse>                          SessionOptOutAsync(int requestedBy, SessionOptOutRequest request);

        /// <summary>Admin rates a volunteer's skill for a specific session.</summary>
        Task<ApiResponse>                          AddSessionSkillRatingAsync(int ratedBy, SessionSkillRatingRequest request);

        /// <summary>Returns per-session breakdown for a volunteer in a RECURRING/FLEXIBLE project.</summary>
        Task<ApiResponse<List<DynamicRow>>>        GetMySessionListAsync(int projectId, int userId);

        /// <summary>Returns attendance % + cert eligibility for a volunteer.</summary>
        Task<ApiResponse<DynamicRow>>              GetVolunteerEligibilityAsync(int projectId, int userId);

        /// <summary>Checks current attendance milestone (25/50/75) — C# caller fires push if enabled.</summary>
        Task<ApiResponse<DynamicRow>>              CheckMilestoneAsync(int projectId, int userId);

        // ── v5.1: Hangfire background job entry points ─────────────────────────────

        /// <summary>Called by AutoActivateProjectsJob — UPCOMING → ACTIVE + generates sessions.</summary>
        Task<ApiResponse<DynamicRow>>              AutoActivateAsync();

        /// <summary>Called by TransitionToClosingJob — ACTIVE → CLOSING for ended RECURRING/FLEXIBLE projects.</summary>
        Task<ApiResponse<DynamicRow>>              TransitionToClosingAsync();

        /// <summary>Called by MarkNoShowJob — inserts NO_SHOW rows for absent RECURRING session volunteers.</summary>
        Task<ApiResponse<DynamicRow>>              MarkNoShowsAsync();

        /// <summary>Called by AutoCheckoutMissedJob — marks FLEXIBLE CHECKED_IN records as CHECKOUT_MISSED after buffer.</summary>
        Task<ApiResponse<DynamicRow>>              AutoCheckoutMissedAsync();
    }
}

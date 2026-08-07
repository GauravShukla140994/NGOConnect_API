using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Project;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class ProjectDal : BaseDal, IProjectDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public ProjectDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse<DynamicRow>> CreateAsync(int userId, CreateProjectRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_Create", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",             userId);
                    _db.AddParameter(cmd, "p_OrgId",              request.OrgId);
                    _db.AddParameter(cmd, "p_Title",              request.Title);
                    _db.AddParameter(cmd, "p_Description",        request.Description);
                    _db.AddParameter(cmd, "p_Category",           request.Category);
                    _db.AddParameter(cmd, "p_ProjectTypeLkpId",   request.ProjectTypeLkpId);
                    _db.AddParameter(cmd, "p_JoinTypeLkpId",      request.JoinTypeLkpId);
                    _db.AddParameter(cmd, "p_StatusLkpId",        request.StatusLkpId);
                    _db.AddParameter(cmd, "p_MaxVolunteers",      request.MaxVolunteers);
                    _db.AddParameter(cmd, "p_MinAge",             request.MinAge);
                    _db.AddParameter(cmd, "p_MaxAge",             request.MaxAge);
                    _db.AddParameter(cmd, "p_IsPublic",           request.IsPublic);
                    _db.AddParameter(cmd, "p_StartDate",          request.StartDate);
                    _db.AddParameter(cmd, "p_EndDate",            request.EndDate);
                    _db.AddParameter(cmd, "p_ScheduleType",       request.ScheduleType);
                    _db.AddParameter(cmd, "p_RecurrenceDays",     request.RecurrenceDays);
                    _db.AddParameter(cmd, "p_StartTime",          request.StartTime);
                    _db.AddParameter(cmd, "p_EndTime",            request.EndTime);
                    _db.AddParameter(cmd, "p_DurationMinutes",    request.DurationMinutes);
                    _db.AddParameter(cmd, "p_LocationTypeLkpId",  request.LocationTypeLkpId);
                    _db.AddParameter(cmd, "p_LocationTypeCode",   request.LocationTypeCode);
                    _db.AddParameter(cmd, "p_LocationName",       request.LocationName);
                    _db.AddParameter(cmd, "p_Address",            request.Address);
                    _db.AddParameter(cmd, "p_Latitude",           request.Latitude);
                    _db.AddParameter(cmd, "p_Longitude",          request.Longitude);
                    _db.AddParameter(cmd, "p_GoogleMapsUrl",      request.GoogleMapsUrl);
                    _db.AddParameter(cmd, "p_GenderRestriction",  request.GenderRestriction);
                    _db.AddParameter(cmd, "p_RequiresApproval",   request.RequiresApproval);
                    _db.AddParameter(cmd, "p_CoverImageUrl",      request.CoverImageUrl);
                    _db.AddParameter(cmd, "p_City",               request.City);
                    _db.AddParameter(cmd, "p_State",              request.State);
                    _db.AddParameter(cmd, "p_IsDraft",            request.IsDraft);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "PROJECT_CREATE_FAILED");

                var projectId = Col<int>(result.Row!, "ProjectId");
                var row = await ExecuteDynamicGetAsync("Project_GetById", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });

                // #27 — notify all org members about the new project (exclude the creator)
                _ = FireOrgNotifAsync(request.OrgId, userId,
                    "New Project Posted",
                    "A new volunteer project has been posted by your organisation.",
                    "NEW_PROJECT", projectId, "PROJECT");

                return ApiResponse<DynamicRow>.Success(row!, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreateAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int projectId, int userId = 0)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_GetById", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Project not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByIdAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateAsync(int projectId, int userId, UpdateProjectRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",          projectId);
                    _db.AddParameter(cmd, "p_UserId",             userId);
                    _db.AddParameter(cmd, "p_Title",              request.Title);
                    _db.AddParameter(cmd, "p_Description",        request.Description);
                    _db.AddParameter(cmd, "p_Category",           request.Category);
                    _db.AddParameter(cmd, "p_ProjectTypeLkpId",   request.ProjectTypeLkpId);
                    _db.AddParameter(cmd, "p_JoinTypeLkpId",      request.JoinTypeLkpId);
                    _db.AddParameter(cmd, "p_StatusLkpId",        request.StatusLkpId);
                    _db.AddParameter(cmd, "p_MaxVolunteers",      request.MaxVolunteers);
                    _db.AddParameter(cmd, "p_MinAge",             request.MinAge);
                    _db.AddParameter(cmd, "p_MaxAge",             request.MaxAge);
                    _db.AddParameter(cmd, "p_IsPublic",           request.IsPublic);
                    _db.AddParameter(cmd, "p_StartDate",          request.StartDate);
                    _db.AddParameter(cmd, "p_EndDate",            request.EndDate);
                    _db.AddParameter(cmd, "p_ScheduleType",       request.ScheduleType);
                    _db.AddParameter(cmd, "p_RecurrenceDays",     request.RecurrenceDays);
                    _db.AddParameter(cmd, "p_StartTime",          request.StartTime);
                    _db.AddParameter(cmd, "p_EndTime",            request.EndTime);
                    _db.AddParameter(cmd, "p_DurationMinutes",    request.DurationMinutes);
                    _db.AddParameter(cmd, "p_LocationTypeLkpId",  request.LocationTypeLkpId);
                    _db.AddParameter(cmd, "p_LocationTypeCode",   request.LocationTypeCode);
                    _db.AddParameter(cmd, "p_LocationName",       request.LocationName);
                    _db.AddParameter(cmd, "p_Address",            request.Address);
                    _db.AddParameter(cmd, "p_Latitude",           request.Latitude);
                    _db.AddParameter(cmd, "p_Longitude",          request.Longitude);
                    _db.AddParameter(cmd, "p_GoogleMapsUrl",      request.GoogleMapsUrl);
                    _db.AddParameter(cmd, "p_GenderRestriction",  request.GenderRestriction);
                    _db.AddParameter(cmd, "p_RequiresApproval",   request.RequiresApproval);
                    _db.AddParameter(cmd, "p_CoverImageUrl",      request.CoverImageUrl);
                    _db.AddParameter(cmd, "p_City",               request.City);
                    _db.AddParameter(cmd, "p_State",              request.State);
                    _db.AddParameter(cmd, "p_IsDraft",            request.IsDraft);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(
            int pageNumber, int pageSize, int? orgId = null, string? category = null,
            string? city = null, string? statusCode = null, string? typeCode = null,
            string? keyword = null, decimal? userLat = null, decimal? userLon = null)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Project_List", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_Category",   category);
                    _db.AddParameter(cmd, "p_City",       city);
                    _db.AddParameter(cmd, "p_StatusCode", statusCode);
                    _db.AddParameter(cmd, "p_TypeCode",   typeCode);
                    _db.AddParameter(cmd, "p_Keyword",    keyword);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                    _db.AddParameter(cmd, "p_UserLat",    userLat);
                    _db.AddParameter(cmd, "p_UserLon",    userLon);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ListAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetNearbyFeedAsync(
            int userId, decimal? userLat, decimal? userLon, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Project_GetNearbyFeed", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_UserLat",    userLat);
                    _db.AddParameter(cmd, "p_UserLon",    userLon);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetNearbyFeedAsync failed UserId={UserId}", userId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AddSkillAsync(int projectId, int userId, AddProjectSkillRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_AddSkill", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_SkillName", request.SkillName);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddSkillAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetSkillsAsync(int projectId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Project_GetSkills",
                    cmd => _db.AddParameter(cmd, "p_ProjectId", projectId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSkillsAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetSkillRatingsAsync(int projectId, int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Project_GetSkillRatings", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSkillRatingsAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AddSessionAsync(int projectId, int userId, CreateSessionRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_AddSession", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",     projectId);
                    _db.AddParameter(cmd, "p_CreatedBy",     userId);
                    _db.AddParameter(cmd, "p_SessionDate",   request.SessionDate);
                    _db.AddParameter(cmd, "p_StartTime",     request.StartTime);
                    _db.AddParameter(cmd, "p_EndTime",       request.EndTime);
                    _db.AddParameter(cmd, "p_MaxVolunteers", request.MaxVolunteers);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "SESSION_CREATE_FAILED");

                var sessionId = Col<int>(result.Row!, "SessionId");
                var row = await ExecuteDynamicGetAsync("Project_GetSessionQr", cmd =>
                {
                    _db.AddParameter(cmd, "p_SessionId", sessionId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return ApiResponse<DynamicRow>.Success(row!, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddSessionAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetSessionsAsync(int projectId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Project_GetSessions", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",  projectId);
                    _db.AddParameter(cmd, "p_PageNumber", 1);
                    _db.AddParameter(cmd, "p_PageSize",   100);
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSessionsAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetSessionQrAsync(int sessionId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_GetSessionQr", cmd =>
                {
                    _db.AddParameter(cmd, "p_SessionId", sessionId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Session not found or access denied.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSessionQrAsync failed SessionId={SessionId}", sessionId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CheckInAsync(int userId, CheckInRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_CheckIn", cmd =>
                {
                    _db.AddParameter(cmd, "p_QrCode", request.QrToken);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                // #21 — confirm attendance to the volunteer who just scanned
                if (result.Succeeded)
                {
                    // Col<int?> cannot cast MySQL INT UNSIGNED (UInt32) to Nullable<Int32> via Convert.ChangeType.
                    // Read the raw value and convert explicitly instead.
                    var rawId     = result.Row!["ProjectId"];
                    var projectId = rawId == DBNull.Value ? (int?)null : (int)Convert.ToUInt32(rawId);
                    _ = FireUserNotifAsync(userId,
                        "Attendance Confirmed",
                        "Your attendance has been recorded. Thank you for showing up!",
                        "QR_CHECKIN", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CheckInAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SelfCheckInAsync(int projectId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_SelfCheckIn", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                if (result.Succeeded)
                {
                    _ = FireUserNotifAsync(userId,
                        "Attendance Confirmed",
                        "Your attendance has been recorded. Thank you for showing up!",
                        "SELF_CHECKIN", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SelfCheckInAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ApplyAsync(int projectId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Apply", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",         projectId);
                    _db.AddParameter(cmd, "p_UserId",            userId);
                    _db.AddParameter(cmd, "p_Motivation",        (object?)null);
                    _db.AddParameter(cmd, "p_RequestedSessions", (object?)null);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApplyAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReviewApplicationAsync(int reviewedBy, ReviewApplicationRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Review", cmd =>
                {
                    _db.AddParameter(cmd, "p_ApplicationId",   request.ApplicationId);
                    _db.AddParameter(cmd, "p_ReviewedBy",      reviewedBy);
                    _db.AddParameter(cmd, "p_StatusCode",      request.StatusCode);
                    _db.AddParameter(cmd, "p_RejectionReason", request.AdminNotes);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReviewApplicationAsync failed ReviewedBy={ReviewedBy}", reviewedBy);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetApplicationsAsync(
            int projectId, int pageNumber, int pageSize, string? statusCode = null)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Application_GetByProject", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",  projectId);
                    _db.AddParameter(cmd, "p_StatusCode", statusCode);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetApplicationsAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CompleteAsync(int projectId, int userId, CompleteProjectRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_Complete", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",        projectId);
                    _db.AddParameter(cmd, "p_CompletedBy",      userId);
                    _db.AddParameter(cmd, "p_ImpactSummary",    request.CompletionNotes);
                    _db.AddParameter(cmd, "p_BeneficiaryCount", request.BeneficiaryCount);
                });
                // #20 — notify all attendees that the project is complete
                if (result.Succeeded)
                    _ = FireProjectNotifAsync(projectId, "ATTENDED",
                        "Project Completed!",
                        "The project you attended has been marked as complete. Check your impact stats!",
                        "PROJECT_COMPLETED", projectId, "PROJECT");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CompleteAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CancelAsync(int projectId, int userId, CancelProjectRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_Cancel", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",    projectId);
                    _db.AddParameter(cmd, "p_UserId",       userId);
                    _db.AddParameter(cmd, "p_CancelReason", request.CancelReason);
                });
                // #19 — notify all APPROVED applicants that the project was cancelled
                if (result.Succeeded)
                    _ = FireProjectNotifAsync(projectId, "APPROVED",
                        "Project Cancelled",
                        "A project you were approved for has been cancelled.",
                        "PROJECT_CANCELLED", projectId, "PROJECT");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CancelAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ManualAttendanceAsync(int markedBy, ManualAttendanceRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_ManualAttendance", cmd =>
                {
                    _db.AddParameter(cmd, "p_ApplicationId", request.ApplicationId);
                    _db.AddParameter(cmd, "p_MarkedBy",      markedBy);
                });
                // #22 — notify the specific volunteer that admin marked their attendance
                if (result.Succeeded)
                {
                    var volunteerId = Col<int?>(result.Row!, "UserId");
                    var projectId   = Col<int?>(result.Row!, "ProjectId");
                    if (volunteerId.HasValue)
                        _ = FireUserNotifAsync(volunteerId.Value,
                            "Attendance Marked",
                            "Your attendance has been manually marked by the admin.",
                            "MANUAL_ATTENDANCE", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ManualAttendanceAsync failed ApplicationId={ApplicationId}", request.ApplicationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Private notification helpers ──────────────────────────────────────────

        private async Task FireUserNotifAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                await _notif.CreateAsync(userId, title, body, notifType, refId, refType);
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "ProjectDal.FireUserNotifAsync failed"); }
        }

        private async Task FireOrgNotifAsync(int orgId, int excludeUserId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var members = await _notif.GetMembersWithTokensAsync(orgId, excludeUserId);
                if (members.Count == 0) return;

                // Persist to Notifications inbox per member — appears in bell icon + notification page
                await Task.WhenAll(members.Select(m =>
                    _notif.CreateAsync(m.UserId, title, body, notifType, refId, refType, orgId)));

                // FCM push
                var tokens = members.Select(m => m.Token).ToList();
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "ProjectDal.FireOrgNotifAsync failed OrgId={OrgId}", orgId); }
        }

        private async Task FireProjectNotifAsync(int projectId, string statusCode, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var tokens = await _notif.GetTokensByProjectIdAsync(projectId, statusCode);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "ProjectDal.FireProjectNotifAsync failed"); }
        }
    }
}

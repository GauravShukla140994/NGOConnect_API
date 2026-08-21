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
                    _db.AddParameter(cmd, "p_City",              request.City);
                    _db.AddParameter(cmd, "p_State",             request.State);
                    _db.AddParameter(cmd, "p_IsDraft",           request.IsDraft);
                    // v5.1 schedule-override params
                    _db.AddParameter(cmd, "p_MinAttendPct",      request.MinAttendPct);
                    _db.AddParameter(cmd, "p_MaxDailyHours",     request.MaxDailyHours);
                    _db.AddParameter(cmd, "p_MinSessionHours",   request.MinSessionHours);
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
                    _db.AddParameter(cmd, "p_City",              request.City);
                    _db.AddParameter(cmd, "p_State",             request.State);
                    _db.AddParameter(cmd, "p_IsDraft",           request.IsDraft);
                    // v5.1 schedule-override params (SP locks these if project is not UPCOMING)
                    _db.AddParameter(cmd, "p_MinAttendPct",      request.MinAttendPct);
                    _db.AddParameter(cmd, "p_MaxDailyHours",     request.MaxDailyHours);
                    _db.AddParameter(cmd, "p_MinSessionHours",   request.MinSessionHours);
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
            string? keyword = null, decimal? userLat = null, decimal? userLon = null,
            int userId = 0)
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
                    _db.AddParameter(cmd, "p_UserId",     userId > 0 ? (object)userId : DBNull.Value);
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
                    _db.AddParameter(cmd, "p_SessionId", (object?)null);
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

        public async Task<ApiResponse> AdminRemoveVolunteerAsync(int projectId, int userId, int removedBy)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_AdminRemoveVolunteer", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",  projectId);
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_RemovedBy",  removedBy);
                });
                if (result.Succeeded)
                {
                    // Notify only the removed volunteer — targeted single-user push
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var tokens = await _notif.GetTokensByUserIdAsync(userId);
                            await _fcm.SendMulticastAsync(tokens,
                                "Removed from Project",
                                "An admin has removed you from a project you were approved for. The slot has been freed.",
                                "APP_REMOVED", projectId, "PROJECT");
                        }
                        catch (Exception ex) { Log.Error(ex, "AdminRemoveVolunteerAsync notification failed UserId={UserId}", userId); }
                    });
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AdminRemoveVolunteerAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse.Fail("An error occurred while removing the volunteer.", "INTERNAL_ERROR");
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

        public async Task<ApiResponse> ExcuseNoShowAsync(int attendanceId, int excusedBy)
        {
            try
            {
                var result = await ExecuteWriteAsync("Attendance_ExcuseNoShow", cmd =>
                {
                    _db.AddParameter(cmd, "p_AttendanceId", attendanceId);
                    _db.AddParameter(cmd, "p_ExcusedBy",    excusedBy);
                });
                if (result.Succeeded)
                {
                    var volunteerId = result.Row != null ? ColNullable<int>(result.Row, "UserId")    : null;
                    var projectId   = result.Row != null ? ColNullable<int>(result.Row, "ProjectId") : null;
                    if (volunteerId.HasValue && volunteerId.Value > 0)
                        _ = FireUserNotifAsync(volunteerId.Value,
                            "Absence Excused",
                            "Your no-show has been marked as excused by the admin. It will not affect your reliability score.",
                            "MANUAL_ATTENDANCE", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ExcuseNoShowAsync failed AttendanceId={AttendanceId}", attendanceId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ConfirmNoShowAsync(int attendanceId, int confirmedBy)
        {
            try
            {
                var result = await ExecuteWriteAsync("Attendance_ConfirmNoShow", cmd =>
                {
                    _db.AddParameter(cmd, "p_AttendanceId", attendanceId);
                    _db.AddParameter(cmd, "p_ConfirmedBy",  confirmedBy);
                });
                if (result.Succeeded)
                {
                    var volunteerId = result.Row != null ? ColNullable<int>(result.Row, "UserId")    : null;
                    var projectId   = result.Row != null ? ColNullable<int>(result.Row, "ProjectId") : null;
                    if (volunteerId.HasValue && volunteerId.Value > 0)
                        _ = FireUserNotifAsync(volunteerId.Value,
                            "No-Show Confirmed",
                            "Your absence from a project session has been reviewed and confirmed. This will affect your reliability score.",
                            "MANUAL_ATTENDANCE", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ConfirmNoShowAsync failed AttendanceId={AttendanceId}", attendanceId);
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
                    var volunteerId = result.Row != null ? ColNullable<int>(result.Row, "UserId")    : null;
                    var projectId   = result.Row != null ? ColNullable<int>(result.Row, "ProjectId") : null;
                    if (volunteerId.HasValue && volunteerId.Value > 0)
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

        // ── v5.1: RECURRING + FLEXIBLE methods ───────────────────────────────────

        public async Task<ApiResponse<DynamicRow>> FlexCheckInAsync(int projectId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_FlexCheckIn", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "FLEX_CHECKIN_FAILED");

                var sessionId = result.Row != null ? ColNullable<int>(result.Row, "SessionId") : null;
                // Return today's session info so client can show check-in confirmation
                var row = sessionId.HasValue
                    ? await ExecuteDynamicGetAsync("Project_GetSessionQr", cmd =>
                    {
                        _db.AddParameter(cmd, "p_SessionId", sessionId.Value);
                        _db.AddParameter(cmd, "p_UserId",    userId);
                    })
                    : null;

                _ = FireUserNotifAsync(userId,
                    "Checked In",
                    "You're checked in for today's session. See you there!",
                    "FLEX_CHECKIN", projectId, "PROJECT");

                return ApiResponse<DynamicRow>.Success(row, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FlexCheckInAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> FlexCheckOutAsync(int projectId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_FlexCheckOut", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "FLEX_CHECKOUT_FAILED");

                var hours = result.Row != null ? Col<decimal>(result.Row, "HoursLogged") : 0m;

                _ = FireUserNotifAsync(userId,
                    "Checked Out",
                    $"Your session is complete! You logged {hours:F1} hours today.",
                    "FLEX_CHECKOUT", projectId, "PROJECT");

                // Trigger milestone check (fire-and-forget)
                _ = CheckAndFireMilestoneAsync(projectId, userId);

                return ApiResponse<DynamicRow>.Success(null, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FlexCheckOutAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> FinalizeClosingAsync(int projectId, int completedBy, FinalizeClosingRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Project_FinalizeClosing", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",        projectId);
                    _db.AddParameter(cmd, "p_CompletedBy",      completedBy);
                    _db.AddParameter(cmd, "p_ImpactSummary",    request.ImpactSummary);
                    _db.AddParameter(cmd, "p_BeneficiaryCount", request.BeneficiaryCount);
                });
                if (result.Succeeded)
                    _ = FireProjectNotifAsync(projectId, "APPROVED",
                        "Project Completed!",
                        "A project you participated in has been marked complete. Check your impact stats!",
                        "PROJECT_COMPLETED", projectId, "PROJECT");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FinalizeClosingAsync failed ProjectId={ProjectId}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CancelSessionAsync(int sessionId, int cancelledBy, CancelSessionRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Session_Cancel", cmd =>
                {
                    _db.AddParameter(cmd, "p_SessionId",   sessionId);
                    _db.AddParameter(cmd, "p_CancelledBy", cancelledBy);
                    _db.AddParameter(cmd, "p_Reason",      request.Reason);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CancelSessionAsync failed SessionId={SessionId}", sessionId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SessionOptOutAsync(int requestedBy, SessionOptOutRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Session_OptOut", cmd =>
                {
                    _db.AddParameter(cmd, "p_SessionId",  request.SessionId);
                    _db.AddParameter(cmd, "p_UserId",     request.UserId);
                    _db.AddParameter(cmd, "p_OptOutType", request.OptOutType);
                    _db.AddParameter(cmd, "p_Reason",     request.Reason);
                    _db.AddParameter(cmd, "p_CreatedBy",  requestedBy);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SessionOptOutAsync failed SessionId={SessionId}", request.SessionId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AddSessionSkillRatingAsync(int ratedBy, SessionSkillRatingRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserSessionSkillRating_AddUpdate", cmd =>
                {
                    _db.AddParameter(cmd, "p_SessionId", request.SessionId);
                    _db.AddParameter(cmd, "p_UserId",    request.UserId);
                    _db.AddParameter(cmd, "p_SkillId",   request.SkillId);
                    _db.AddParameter(cmd, "p_Rating",    request.Rating);
                    _db.AddParameter(cmd, "p_RatedBy",   ratedBy);
                    _db.AddParameter(cmd, "p_Notes",     request.Notes);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddSessionSkillRatingAsync failed SessionId={SessionId}", request.SessionId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetMySessionListAsync(int projectId, int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Project_GetMySessionList", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMySessionListAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetVolunteerEligibilityAsync(int projectId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_GetVolunteerEligibility", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Eligibility data not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetVolunteerEligibilityAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> CheckMilestoneAsync(int projectId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_CheckMilestoneNotification", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CheckMilestoneAsync failed ProjectId={ProjectId} UserId={UserId}", projectId, userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Hangfire job entry points ─────────────────────────────────────────────

        public async Task<ApiResponse<DynamicRow>> AutoActivateAsync()
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_AutoActivate", cmd => { });
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AutoActivateAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> TransitionToClosingAsync()
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_TransitionToClosing", cmd => { });
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "TransitionToClosingAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> MarkNoShowsAsync()
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_MarkNoShows", cmd => { });
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "MarkNoShowsAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AutoCheckoutMissedAsync()
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_AutoCheckoutMissed", cmd => { });
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AutoCheckoutMissedAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Private helper: fire milestone push (fire-and-forget) ────────────────
        private async Task CheckAndFireMilestoneAsync(int projectId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Project_CheckMilestoneNotification", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                });
                if (row is null) return;

                var milestone = row.Get<int>("milestoneReached");
                if (milestone == 0) return;

                await FireUserNotifAsync(userId,
                    $"🎯 {milestone}% Milestone!",
                    $"You've attended {milestone}% of the project sessions. Keep it up!",
                    $"MILESTONE_{milestone}", projectId, "PROJECT");
            }
            catch (Exception ex) { Log.Error(ex, "CheckAndFireMilestoneAsync failed ProjectId={ProjectId}", projectId); }
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

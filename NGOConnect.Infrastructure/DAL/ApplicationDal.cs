using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Application;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class ApplicationDal : BaseDal, IApplicationDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public ApplicationDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse> ApplyAsync(int projectId, int userId, ApplyRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Apply", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",         projectId);
                    _db.AddParameter(cmd, "p_UserId",            userId);
                    _db.AddParameter(cmd, "p_Motivation",        request.Motivation);
                    _db.AddParameter(cmd, "p_RequestedSessions", request.RequestedSessions);
                });

                if (result.Succeeded && result.Row is not null)
                {
                    var orgId = Col<int>(result.Row, "OrgId");
                    _ = FireAdminNotifAsync(orgId, "New Application", "A new volunteer has applied to your project.", "NEW_APPLICATION", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApplyAsync failed ProjectId={Id}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetByProjectAsync(
            int projectId, int? statusLkpId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Application_GetByProject", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",  projectId);
                    _db.AddParameter(cmd, "p_StatusCode", statusLkpId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByProjectAsync failed ProjectId={Id}", projectId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReviewAsync(int applicationId, int reviewedBy, ReviewApplicationRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Review", cmd =>
                {
                    _db.AddParameter(cmd, "p_ApplicationId",   applicationId);
                    _db.AddParameter(cmd, "p_ReviewedBy",      reviewedBy);
                    _db.AddParameter(cmd, "p_StatusCode",      request.StatusCode);
                    _db.AddParameter(cmd, "p_RejectionReason", request.RejectionReason);
                });

                if (result.Succeeded && result.Row is not null)
                {
                    var applicantUserId = Col<int>(result.Row, "ApplicantUserId");
                    var projectId       = Col<int>(result.Row, "ProjectId");
                    var isApproved = request.StatusCode?.Equals("APPROVED", StringComparison.OrdinalIgnoreCase) == true;

                    if (isApproved)
                        _ = FireUserNotifAsync(applicantUserId, "Application Approved 🎉", "Your application has been approved. Get ready to volunteer!", "APPLICATION_APPROVED", projectId, "PROJECT");
                    else
                        _ = FireUserNotifAsync(applicantUserId, "Application Update", "Your application was not selected this time. Keep applying!", "APPLICATION_REJECTED", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReviewAsync failed ApplicationId={Id}", applicationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetMyApplicationsAsync(int userId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("Application_GetByUser", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_PageNumber", 1);
                    _db.AddParameter(cmd, "p_PageSize",   200);
                });
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMyApplicationsAsync failed UserId={Id}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> WithdrawAsync(int applicationId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Withdraw", cmd =>
                {
                    _db.AddParameter(cmd, "p_ApplicationId", applicationId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "WithdrawAsync failed ApplicationId={Id}", applicationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Notification helpers ──────────────────────────────────────────────────

        private async Task FireUserNotifAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                await _notif.CreateAsync(userId, title, body, notifType, refId, refType);
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "FireUserNotifAsync failed"); }
        }

        private async Task FireAdminNotifAsync(int orgId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var admins = await _notif.GetAdminsWithTokensAsync(orgId);
                if (admins.Count == 0) return;
                await Task.WhenAll(admins.Select(a =>
                    _notif.CreateAsync(a.UserId, title, body, notifType, refId, refType, orgId)));
                var tokens = admins.Select(a => a.Token).ToList();
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "ApplicationDal.FireAdminNotifAsync failed"); }
        }
    }
}

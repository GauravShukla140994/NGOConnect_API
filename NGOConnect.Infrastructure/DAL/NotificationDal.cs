using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Notification;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class NotificationDal : BaseDal, INotificationDal
    {
        public NotificationDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(
            int userId, int pageNumber, int pageSize, bool onlyUnread = false)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Notification_GetByUser", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_OnlyUnread", onlyUnread ? 1 : 0);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetListAsync failed UserId={UserId}", userId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetUnreadCountAsync(int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Notification_GetUnreadCount",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<DynamicRow>.Success(row ?? new DynamicRow());
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetUnreadCountAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> MarkReadAsync(int notificationId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Notification_MarkRead", cmd =>
                {
                    _db.AddParameter(cmd, "p_NotificationId", notificationId);
                    _db.AddParameter(cmd, "p_UserId",         userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "MarkReadAsync failed NotificationId={Id}", notificationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> MarkAllReadAsync(int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Notification_MarkAllRead",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "MarkAllReadAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SaveDeviceTokenAsync(int userId, SaveDeviceTokenRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Notification_SaveDeviceToken", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",   userId);
                    _db.AddParameter(cmd, "p_Token",    request.Token);
                    _db.AddParameter(cmd, "p_Platform", request.Platform);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SaveDeviceTokenAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Internal helpers — called by other DALs ───────────────────────────────

        public async Task CreateAsync(
            int userId, string title, string body, string notifType,
            int? refId = null, string? refType = null, int? orgId = null)
        {
            try
            {
                await ExecuteWriteAsync("Notification_Create", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",    userId);
                    _db.AddParameter(cmd, "p_Title",     title);
                    _db.AddParameter(cmd, "p_Body",      body);
                    _db.AddParameter(cmd, "p_NotifType", notifType);
                    _db.AddParameter(cmd, "p_RefId",     (object?)refId  ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_RefType",   (object?)refType ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_OrgId",     (object?)orgId  ?? DBNull.Value);
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Notification.CreateAsync failed UserId={UserId} Type={Type}", userId, notifType);
            }
        }

        public async Task<List<string>> GetTokensByUserIdAsync(int userId)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<string>(
                    "Notification_GetTokenByUserId",
                    r => r["Token"]?.ToString() ?? "",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return rows.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetTokensByUserIdAsync failed UserId={UserId}", userId);
                return [];
            }
        }

        public async Task DeleteStaleTokenAsync(string token)
        {
            try
            {
                await ExecuteWriteAsync("Notification_DeleteStaleToken",
                    cmd => _db.AddParameter(cmd, "p_Token", token));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeleteStaleTokenAsync failed Token={Token}", token.Length > 8 ? token[..8] + "..." : "***");
            }
        }

        public async Task<List<string>> GetTokensByOrgIdAsync(int orgId, int excludeUserId = 0)
        {
            var members = await GetMembersWithTokensAsync(orgId, excludeUserId);
            return members.Select(m => m.Token).ToList();
        }

        public async Task<List<(int UserId, string Token)>> GetMembersWithTokensAsync(int orgId, int excludeUserId = 0)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<(int UserId, string Token)>(
                    "Notification_GetTokensByOrgId",
                    r => (
                        r["UserId"] == DBNull.Value ? 0 : Convert.ToInt32(r["UserId"]),
                        r["Token"]?.ToString() ?? ""
                    ),
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",         orgId);
                        _db.AddParameter(cmd, "p_ExcludeUserId", excludeUserId);
                    });
                return rows.Where(m => m.UserId > 0 && !string.IsNullOrWhiteSpace(m.Token)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMembersWithTokensAsync failed OrgId={OrgId}", orgId);
                return [];
            }
        }

        public async Task<List<string>> GetAdminTokensByOrgIdAsync(int orgId)
        {
            var admins = await GetAdminsWithTokensAsync(orgId);
            return admins.Select(a => a.Token).ToList();
        }

        public async Task<List<(int UserId, string Token)>> GetAdminsWithTokensAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<(int UserId, string Token)>(
                    "Notification_GetAdminTokensByOrgId",
                    r => (
                        r["UserId"] == DBNull.Value ? 0 : Convert.ToInt32(r["UserId"]),
                        r["Token"]?.ToString() ?? ""
                    ),
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return rows.Where(m => m.UserId > 0 && !string.IsNullOrWhiteSpace(m.Token)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetAdminsWithTokensAsync failed OrgId={OrgId}", orgId);
                return [];
            }
        }

        public async Task<List<string>> GetTokensByProjectIdAsync(int projectId, string? statusCode = null)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<string>(
                    "Notification_GetTokensByProjectId",
                    r => r["Token"]?.ToString() ?? "",
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_ProjectId",  projectId);
                        _db.AddParameter(cmd, "p_StatusCode", (object?)statusCode ?? DBNull.Value);
                    });
                return rows.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetTokensByProjectIdAsync failed ProjectId={ProjectId}", projectId);
                return [];
            }
        }

        public async Task<List<string>> GetTokensBySosIncidentIdAsync(int sosIncidentId)
        {
            var responders = await GetSosRespondersWithTokensAsync(sosIncidentId);
            return responders.Select(r => r.Token).ToList();
        }

        public async Task<List<(int UserId, string Token)>> GetSosRespondersWithTokensAsync(int sosIncidentId)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<(int UserId, string Token)>(
                    "Notification_GetTokensBySosIncidentId",
                    r => (
                        r["UserId"] == DBNull.Value ? 0 : Convert.ToInt32(r["UserId"]),
                        r["Token"]?.ToString() ?? ""
                    ),
                    cmd => _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId));
                return rows.Where(m => m.UserId > 0 && !string.IsNullOrWhiteSpace(m.Token)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSosRespondersWithTokensAsync failed SosIncidentId={Id}", sosIncidentId);
                return [];
            }
        }

        public async Task<List<(int UserId, string Token)>> GetSosRecipientsWithTokensAsync(int orgId, int victimUserId)
        {
            try
            {
                var rows = await ExecuteReaderListAsync<(int UserId, string Token)>(
                    "Notification_GetSosMemberTokens",
                    r => (
                        r["UserId"] == DBNull.Value ? 0 : Convert.ToInt32(r["UserId"]),
                        r["Token"]?.ToString() ?? ""
                    ),
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",        orgId);
                        _db.AddParameter(cmd, "p_VictimUserId", victimUserId);
                    });
                return rows.Where(m => m.UserId > 0 && !string.IsNullOrWhiteSpace(m.Token)).ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSosRecipientsWithTokensAsync failed OrgId={OrgId} VictimUserId={VId}", orgId, victimUserId);
                return [];
            }
        }

        public async Task<FeedPostNotifData> BulkNotifyFeedPostAsync(int postId, int orgId, int authorUserId)
        {
            var result = new FeedPostNotifData();
            try
            {
                // SP: saves Notifications rows + returns (UserId, Token, Platform, Title, Body)
                var rows = await ExecuteReaderListAsync<(string Token, string Title, string Body)>(
                    "Post_BulkNotifyOrgMembers",
                    r => (
                        Token: r["Token"]?.ToString()  ?? "",
                        Title: r["Title"]?.ToString()  ?? "",
                        Body:  r["Body"]?.ToString()   ?? ""
                    ),
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_PostId",       postId);
                        _db.AddParameter(cmd, "p_OrgId",        orgId);
                        _db.AddParameter(cmd, "p_AuthorUserId", authorUserId);
                    });

                if (rows.Count == 0) return result;

                result.Title  = rows[0].Title;
                result.Body   = rows[0].Body;
                result.Tokens = rows
                    .Select(r => r.Token)
                    .Where(t => !string.IsNullOrWhiteSpace(t))
                    .Distinct()
                    .ToList();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "BulkNotifyFeedPostAsync failed PostId={PostId} OrgId={OrgId}", postId, orgId);
            }
            return result;
        }
    }
}

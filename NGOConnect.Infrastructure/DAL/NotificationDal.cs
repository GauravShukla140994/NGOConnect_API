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
    }
}

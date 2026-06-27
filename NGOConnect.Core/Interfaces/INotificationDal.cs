using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Notification;

namespace NGOConnect.Core.Interfaces
{
    public interface INotificationDal
    {
        Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(int userId, int pageNumber, int pageSize, bool onlyUnread = false);
        Task<ApiResponse<DynamicRow>>              GetUnreadCountAsync(int userId);
        Task<ApiResponse>                          MarkReadAsync(int notificationId, int userId);
        Task<ApiResponse>                          MarkAllReadAsync(int userId);
        Task<ApiResponse>                          SaveDeviceTokenAsync(int userId, SaveDeviceTokenRequest request);
    }
}

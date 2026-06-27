using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Notification;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/notifications")]
    [Authorize]
    [Produces("application/json")]
    public class NotificationController : ControllerBase
    {
        private readonly INotificationDal _notification;
        public NotificationController(INotificationDal notification) => _notification = notification;

        [HttpGet]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetList(
            [FromQuery] bool onlyUnread = false,
            [FromQuery] int  pageNumber = 1,
            [FromQuery] int  pageSize   = 30)
            => await _notification.GetListAsync(GetUserId(), pageNumber, pageSize, onlyUnread);

        [HttpGet("unread-count")]
        public async Task<ApiResponse<DynamicRow>> GetUnreadCount()
            => await _notification.GetUnreadCountAsync(GetUserId());

        [HttpPut("{notificationId:int}/read")]
        public async Task<ApiResponse> MarkRead(int notificationId)
            => await _notification.MarkReadAsync(notificationId, GetUserId());

        [HttpPut("read-all")]
        public async Task<ApiResponse> MarkAllRead()
            => await _notification.MarkAllReadAsync(GetUserId());

        [HttpPost("device-token")]
        public async Task<ApiResponse> SaveDeviceToken([FromBody] SaveDeviceTokenRequest request)
            => await _notification.SaveDeviceTokenAsync(GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

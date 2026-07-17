using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Notification;

namespace NGOConnect.Core.Interfaces
{
    public interface INotificationDal
    {
        // ── User-facing endpoints ──────────────────────────────────
        Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(int userId, int pageNumber, int pageSize, bool onlyUnread = false);
        Task<ApiResponse<DynamicRow>>              GetUnreadCountAsync(int userId);
        Task<ApiResponse>                          MarkReadAsync(int notificationId, int userId);
        Task<ApiResponse>                          MarkAllReadAsync(int userId);
        Task<ApiResponse>                          SaveDeviceTokenAsync(int userId, SaveDeviceTokenRequest request);

        // ── Internal helpers — called by other DALs to fire notifications ──
        /// <summary>Save a notification record to the Notifications inbox table.
        /// Pass orgId when the notification originates from a specific organisation — shown on the history list.</summary>
        Task CreateAsync(int userId, string title, string body, string notifType, int? refId = null, string? refType = null, int? orgId = null);

        /// <summary>Get all FCM tokens for a user (may have android + ios).</summary>
        Task<List<string>> GetTokensByUserIdAsync(int userId);

        /// <summary>Get FCM tokens for all APPROVED members of an org (excludes the sender).</summary>
        Task<List<string>> GetTokensByOrgIdAsync(int orgId, int excludeUserId = 0);

        /// <summary>Delete a stale/unregistered FCM token from UserDeviceTokens.
        /// Call when Firebase returns MessagingErrorCode.Unregistered.</summary>
        Task DeleteStaleTokenAsync(string token);

        /// <summary>Get UserId + Token pairs for all APPROVED org members — use this when you need to write
        /// a Notifications inbox row per member AND send FCM in the same fan-out.</summary>
        Task<List<(int UserId, string Token)>> GetMembersWithTokensAsync(int orgId, int excludeUserId = 0);

        /// <summary>Get FCM tokens for FOUNDER + ADMIN members of an org only.</summary>
        Task<List<string>> GetAdminTokensByOrgIdAsync(int orgId);

        /// <summary>Get FCM tokens for project applicants filtered by statusCode (APPROVED | ATTENDED | null = all).</summary>
        Task<List<string>> GetTokensByProjectIdAsync(int projectId, string? statusCode = null);

        /// <summary>Get FCM tokens for all APPROVED responders on a SOS incident (for resolve/cancel fan-out).</summary>
        Task<List<string>> GetTokensBySosIncidentIdAsync(int sosIncidentId);
    }
}

using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Invite;

namespace NGOConnect.Core.Interfaces
{
    public interface IOrgInviteDal
    {
        // ── Admin: send invitation ───────────────────────────────────────────────
        /// <summary>
        /// Creates the invitation record in DB, then sends the delivery (SMS/Email).
        /// Returns a rich result so the controller can surface profile preview data
        /// when the invitee is already a platform user.
        /// </summary>
        Task<InviteSendResult> SendAsync(int orgId, int invitedByUserId, SendInviteRequest request, string inviterName);

        // ── Admin: cancel invitation ─────────────────────────────────────────────
        Task<ApiResponse> CancelAsync(int invitationId, int cancelledByUserId);

        // ── Authenticated: invitee declines their own invitation ─────────────────
        Task<ApiResponse> DeclineAsync(int invitationId, int userId);

        // ── Admin: resend invitation (new token + expiry) ────────────────────────
        /// <summary>
        /// Refreshes the token and expiry, re-sends the link via the original channel.
        /// </summary>
        Task<ApiResponse> ResendAsync(int invitationId, int requestedByUserId, string inviterName);

        // ── Admin: list org invitations (paged) ──────────────────────────────────
        Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(int orgId, int requestorId, InviteListRequest request);

        // ── Public: verify token (called from deep link, before login) ───────────
        Task<ApiResponse<DynamicRow>> VerifyTokenAsync(string token);

        // ── Authenticated: accept invitation ─────────────────────────────────────
        Task<ApiResponse<DynamicRow>> AcceptAsync(int invitationId, int userId);

        // ── Authenticated: get pending invitations for the logged-in user ─────────
        Task<ApiResponse<List<DynamicRow>>> GetPendingForUserAsync(int userId);
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Invite;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Org Member Invitation endpoints (v4.9).
    ///
    /// Routes:
    ///   POST   /api/v1/org/{orgId}/invite/send          Admin: send invitation
    ///   GET    /api/v1/org/{orgId}/invite/list          Admin: paged invitation list
    ///   POST   /api/v1/org/invite/{invitationId}/cancel Admin: cancel invitation
    ///   POST   /api/v1/org/invite/{invitationId}/resend Admin: resend invitation
    ///   GET    /api/v1/org/invite/verify/{token}        Public: verify deep link token
    ///   POST   /api/v1/org/invite/{invitationId}/accept Auth: accept invitation
    ///   GET    /api/v1/org/invite/pending               Auth: pending invites for current user
    /// </summary>
    [ApiController]
    [Route("api/v1/org")]
    [Produces("application/json")]
    public class OrgInviteController : ControllerBase
    {
        private readonly IOrgInviteDal _invite;
        private readonly IUserDal      _user;

        public OrgInviteController(IOrgInviteDal invite, IUserDal user)
        {
            _invite = invite;
            _user   = user;
        }

        // ── Admin: Send Invitation ───────────────────────────────────────────────
        /// <summary>
        /// Create and deliver an invitation via Phone or Email.
        /// Caller must be FOUNDER or ADMIN of the org (enforced in SP).
        /// Response includes an ExistingUserFound flag + profile preview when
        /// the invitee already has a platform account.
        /// </summary>
        [HttpPost("{orgId:int}/invite/send")]
        [Authorize]
        public async Task<IActionResult> Send(int orgId, [FromBody] SendInviteRequest request)
        {
            var userId      = GetUserId();
            var inviterName = await GetDisplayNameAsync(userId);

            var result = await _invite.SendAsync(orgId, userId, request, inviterName);

            if (!result.Succeeded)
                return Ok(new ApiResponse<object>
                {
                    IsSuccess = 0,
                    Message   = result.Message,
                    ErrorCode = result.ErrorCode,
                    Data      = result.InvitationId.HasValue
                        ? new { invitationId = result.InvitationId }
                        : null
                });

            return Ok(new ApiResponse<object>
            {
                IsSuccess = 1,
                Message   = result.Message,
                Data      = new
                {
                    invitationId        = result.InvitationId,
                    existingUserFound   = result.ExistingUserFound,
                    // Profile preview — null when invitee is not on the platform
                    existingUserId      = result.ExistingUserId,
                    existingUserName    = result.ExistingUserName,
                    existingUserPhoto   = result.ExistingUserPhoto,
                    existingUserCity    = result.ExistingUserCity,
                    existingUserOrgCount= result.ExistingUserOrgCount,
                    // For non-platform contacts: app uses this to open a share sheet
                    inviteLink          = result.InviteLink
                }
            });
        }

        // ── Admin: List Invitations ──────────────────────────────────────────────
        /// <summary>
        /// Paginated list of all invitations for the org.
        /// Optional statusCode filter: PENDING | OPENED | ACCEPTED | CANCELLED | EXPIRED
        /// </summary>
        [HttpGet("{orgId:int}/invite/list")]
        [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> List(
            int orgId,
            [FromQuery] string? statusCode  = null,
            [FromQuery] int     pageNumber  = 1,
            [FromQuery] int     pageSize    = 20)
        {
            var req = new InviteListRequest
            {
                StatusCode = statusCode,
                PageNumber = pageNumber,
                PageSize   = pageSize
            };
            return await _invite.ListAsync(orgId, GetUserId(), req);
        }

        // ── Admin: Cancel Invitation ─────────────────────────────────────────────
        [HttpPost("invite/{invitationId:int}/cancel")]
        [Authorize]
        public async Task<ApiResponse> Cancel(int invitationId)
            => await _invite.CancelAsync(invitationId, GetUserId());

        // ── Authenticated: Decline Invitation (invitee rejects their own invite) ──
        [HttpPost("invite/{invitationId:int}/decline")]
        [Authorize]
        public async Task<ApiResponse> Decline(int invitationId)
            => await _invite.DeclineAsync(invitationId, GetUserId());

        // ── Admin: Resend Invitation ─────────────────────────────────────────────
        /// <summary>
        /// Generates a fresh token + expiry and re-sends the link via the original channel.
        /// Old link is invalidated.
        /// </summary>
        [HttpPost("invite/{invitationId:int}/resend")]
        [Authorize]
        public async Task<ApiResponse> Resend(int invitationId)
        {
            var userId      = GetUserId();
            var inviterName = await GetDisplayNameAsync(userId);
            return await _invite.ResendAsync(invitationId, userId, inviterName);
        }

        // ── Public: Verify Token ─────────────────────────────────────────────────
        /// <summary>
        /// Called from the deep link handler before the user is logged in.
        /// Returns org info + invitation details so the app can show the invitation
        /// card on the login/register screen.
        /// No [Authorize] — this is a public endpoint.
        /// </summary>
        [HttpGet("invite/verify/{token}")]
        public async Task<ApiResponse<DynamicRow>> VerifyToken(string token)
            => await _invite.VerifyTokenAsync(token);

        // ── Authenticated: Accept Invitation ─────────────────────────────────────
        /// <summary>
        /// Authenticated user accepts an invitation.
        /// Creates an OrgMembershipRequest (or auto-joins if org has open membership).
        /// InvitationId is retrieved after VerifyToken — stored client-side before login.
        /// </summary>
        [HttpPost("invite/{invitationId:int}/accept")]
        [Authorize]
        public async Task<ApiResponse<DynamicRow>> Accept(int invitationId)
            => await _invite.AcceptAsync(invitationId, GetUserId());

        // ── Authenticated: Pending Invitations for Current User ───────────────────
        /// <summary>
        /// Called after login/register to surface any pending invitations that
        /// match the user's phone or email. App shows a banner for each.
        /// </summary>
        [HttpGet("invite/pending")]
        [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetPending()
            => await _invite.GetPendingForUserAsync(GetUserId());

        // ── Helpers ──────────────────────────────────────────────────────────────

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }

        /// <summary>
        /// Gets the caller's display name for use in SMS/Email invitation messages.
        /// Falls back to "A RippleHub member" if the profile cannot be fetched.
        /// </summary>
        private async Task<string> GetDisplayNameAsync(int userId)
        {
            try
            {
                var profile = await _user.GetProfileAsync(userId);
                if (profile?.Data == null) return "A RippleHub member";
                var first = profile.Data.FirstName ?? "";
                var last  = profile.Data.LastName  ?? "";
                var name  = $"{first} {last}".Trim();
                return string.IsNullOrEmpty(name) ? "A RippleHub member" : name;
            }
            catch
            {
                return "A RippleHub member";
            }
        }
    }
}

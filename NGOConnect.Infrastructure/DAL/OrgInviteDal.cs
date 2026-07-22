using System.Security.Cryptography;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Invite;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// DAL for the Org Member Invitation feature.
    /// Handles all DB operations via Org_Invite_* stored procedures.
    /// Delivery (SMS/Email) is triggered here after a successful SP call,
    /// using ISmsService / IEmailService + invite link from SettingsCache.
    ///
    /// Token generation: 32 random bytes → URL-safe base64 (43 chars, no padding).
    /// The C# layer generates tokens so we stay away from RAND() in MySQL,
    /// which is not cryptographically secure.
    /// </summary>
    public class OrgInviteDal : BaseDal, IOrgInviteDal
    {
        private readonly ISettingsCache _settings;
        private readonly ISmsService    _sms;
        private readonly IEmailService  _email;

        public OrgInviteDal(
            IDbProvider    db,
            ISettingsCache settings,
            ISmsService    sms,
            IEmailService  email)
            : base(db)
        {
            _settings = settings;
            _sms      = sms;
            _email    = email;
        }

        // ── Private helpers ──────────────────────────────────────────────────────

        private static string GenerateToken()
        {
            var bytes = new byte[32];
            RandomNumberGenerator.Fill(bytes);
            // URL-safe base64 — 43 chars, no trailing '='
            return Convert.ToBase64String(bytes)
                .Replace('+', '-')
                .Replace('/', '_')
                .TrimEnd('=');
        }

        private string GetBaseUrl()
            => _settings.GetValue("INVITE_BASE_URL") ?? "https://ripplehub.app/invite/";

        private int GetExpiryDays()
            => _settings.GetValue<int>("INVITE_TOKEN_EXPIRY_DAYS", 30);

        // ── IOrgInviteDal ────────────────────────────────────────────────────────

        public async Task<InviteSendResult> SendAsync(
            int orgId, int invitedByUserId, SendInviteRequest request, string inviterName)
        {
            try
            {
                var token   = GenerateToken();
                var expiry  = DateTime.UtcNow.AddDays(GetExpiryDays());
                var baseUrl = GetBaseUrl();

                // Normalise: email → lowercase; phone → strip spaces
                var inviteValue = request.InviteTypeCode.ToUpperInvariant() == "EMAIL"
                    ? request.InviteValue.Trim().ToLowerInvariant()
                    : request.InviteValue.Trim();

                var result = await ExecuteWriteAsync("Org_Invite_Send", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",           orgId);
                    _db.AddParameter(cmd, "p_InvitedByUserId", invitedByUserId);
                    _db.AddParameter(cmd, "p_InviteTypeCode",  request.InviteTypeCode.ToUpperInvariant());
                    _db.AddParameter(cmd, "p_InviteValue",     inviteValue);
                    _db.AddParameter(cmd, "p_CountryCode",     request.CountryCode);
                    _db.AddParameter(cmd, "p_InviteToken",     token);
                    _db.AddParameter(cmd, "p_TokenExpiry",     expiry);
                    _db.AddParameter(cmd, "p_InviteBaseUrl",   baseUrl);
                });

                if (!result.Succeeded)
                {
                    // Derive machine-readable error code from SP result columns
                    // (SP returns ExistingUserFound=1 for member, InvitationId IS NOT NULL for active invite)
                    string? errorCode = null;
                    if (result.Row != null)
                    {
                        var existingFound = Col<int>(result.Row, "ExistingUserFound");
                        var pendingId     = ColNullable<int>(result.Row, "InvitationId");
                        if      (existingFound == 1)       errorCode = "ALREADY_MEMBER";
                        else if (pendingId.HasValue)       errorCode = "ALREADY_INVITED";
                    }

                    return new InviteSendResult
                    {
                        Succeeded    = false,
                        Message      = result.Message,
                        ErrorCode    = errorCode,
                        InvitationId = result.Row != null ? ColNullable<int>(result.Row, "InvitationId") : null
                    };
                }

                var row = result.Row!;
                var invitationId      = Col<int>(row, "InvitationId");
                var existingUserFound = Col<int>(row, "ExistingUserFound") == 1;
                var existingUserId    = ColNullable<int>(row, "ExistingUserId");
                var existingUserName  = Col<string?>(row, "ExistingUserName");
                var existingUserPhoto = Col<string?>(row, "ExistingUserPhoto");
                var existingUserCity  = Col<string?>(row, "ExistingUserCity");
                var existingOrgCount  = Col<int>(row, "ExistingUserOrgCount");
                var inviteLink        = Col<string?>(row, "InviteLink") ?? $"{baseUrl}{token}";

                // In-app notification is already sent by the SP for existing users.
                // For non-platform contacts, fire-and-forget the SMS/Email delivery.
                if (!existingUserFound)
                {
                    var orgName = await GetOrgNameAsync(orgId);
                    _ = DeliverInviteAsync(
                        request.InviteTypeCode.ToUpperInvariant(),
                        inviteValue, request.CountryCode,
                        inviterName, orgName, inviteLink);
                }

                return new InviteSendResult
                {
                    Succeeded            = true,
                    Message              = result.Message,
                    InvitationId         = invitationId,
                    ExistingUserFound    = existingUserFound,
                    ExistingUserId       = existingUserId,
                    ExistingUserName     = existingUserName,
                    ExistingUserPhoto    = existingUserPhoto,
                    ExistingUserCity     = existingUserCity,
                    ExistingUserOrgCount = existingOrgCount,
                    InviteToken          = token,
                    InviteLink           = inviteLink,
                    InviteTypeCode       = request.InviteTypeCode.ToUpperInvariant(),
                    InviteValue          = inviteValue,
                    CountryCode          = request.CountryCode
                };
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.SendAsync failed OrgId={OrgId} InvitedBy={UserId}", orgId, invitedByUserId);
                return new InviteSendResult { Succeeded = false, Message = "An error occurred. Please try again." };
            }
        }

        public async Task<ApiResponse> CancelAsync(int invitationId, int cancelledByUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Invite_Cancel", cmd =>
                {
                    _db.AddParameter(cmd, "p_InvitationId",      invitationId);
                    _db.AddParameter(cmd, "p_CancelledByUserId", cancelledByUserId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.CancelAsync failed InvitationId={Id}", invitationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ResendAsync(int invitationId, int requestedByUserId, string inviterName)
        {
            try
            {
                var newToken  = GenerateToken();
                var newExpiry = DateTime.UtcNow.AddDays(GetExpiryDays());
                var baseUrl   = GetBaseUrl();

                var result = await ExecuteWriteAsync("Org_Invite_Resend", cmd =>
                {
                    _db.AddParameter(cmd, "p_InvitationId",      invitationId);
                    _db.AddParameter(cmd, "p_RequestedByUserId", requestedByUserId);
                    _db.AddParameter(cmd, "p_NewToken",          newToken);
                    _db.AddParameter(cmd, "p_NewExpiry",         newExpiry);
                    _db.AddParameter(cmd, "p_InviteBaseUrl",     baseUrl);
                });

                if (!result.Succeeded)
                    return result.ToApiResponse();

                var row          = result.Row!;
                var inviteLink   = Col<string?>(row, "InviteLink")    ?? $"{baseUrl}{newToken}";
                var inviteValue  = Col<string?>(row, "InviteValue")   ?? "";
                var countryCode  = Col<string?>(row, "CountryCode");
                var invitedUserId= ColNullable<int>(row, "InvitedUserId");

                // Re-deliver only for contacts not yet on the platform
                if (invitedUserId == null && !string.IsNullOrEmpty(inviteValue))
                {
                    var typeCode = inviteValue.Contains('@') ? "EMAIL" : "PHONE";
                    var orgName  = await GetOrgNameAsync(0); // org unknown here; use generic name
                    _ = DeliverInviteAsync(typeCode, inviteValue, countryCode, inviterName, orgName, inviteLink);
                }

                return ApiResponse.Ok(result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.ResendAsync failed InvitationId={Id}", invitationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> ListAsync(
            int orgId, int requestorId, InviteListRequest request)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync(
                    "Org_Invite_List",
                    request.PageNumber,
                    request.PageSize,
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",       orgId);
                        _db.AddParameter(cmd, "p_RequestorId", requestorId);
                        _db.AddParameter(cmd, "p_StatusCode",  request.StatusCode);
                        _db.AddParameter(cmd, "p_PageNumber",  request.PageNumber);
                        _db.AddParameter(cmd, "p_PageSize",    request.PageSize);
                    });

                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.ListAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> VerifyTokenAsync(string token)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Org_Invite_VerifyToken", cmd =>
                {
                    _db.AddParameter(cmd, "p_Token", token);
                });

                if (row == null)
                    return ApiResponse<DynamicRow>.Failure("Invitation not found.", "INVALID_TOKEN");

                // SP returns IsSuccess in the result set (both success and error paths)
                var isSuccess = row.Get<int>("isSuccess") == 1;
                if (!isSuccess)
                {
                    var errCode = row.Get<string>("errorCode") ?? "INVALID_TOKEN";
                    var msg     = row.Get<string>("message")   ?? "Invalid invitation.";
                    return ApiResponse<DynamicRow>.Failure(msg, errCode);
                }

                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.VerifyTokenAsync failed Token={Prefix}...", token[..Math.Min(8, token.Length)]);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AcceptAsync(int invitationId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Invite_Accept", cmd =>
                {
                    _db.AddParameter(cmd, "p_InvitationId", invitationId);
                    _db.AddParameter(cmd, "p_UserId",       userId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "ACCEPT_FAILED");

                // Surface OrgId, OrgName, JoinType from SP result row
                var data = new DynamicRow();
                if (result.Row != null)
                {
                    data["joinType"] = Col<string?>(result.Row, "JoinType");
                    data["orgId"]    = ColNullable<int>(result.Row,    "OrgId");
                    data["orgName"]  = Col<string?>(result.Row, "OrgName");
                }

                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.AcceptAsync failed InvitationId={Id} UserId={UserId}", invitationId, userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetPendingForUserAsync(int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_Invite_GetPendingForUser", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                });

                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "OrgInviteDal.GetPendingForUserAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Delivery helpers ─────────────────────────────────────────────────────

        /// <summary>
        /// Fire-and-forget delivery via SMS or Email.
        /// Runs on the thread pool — never blocks the API response.
        /// Failures are logged but swallowed; delivery status is not written
        /// back to DB in this phase (can be wired via Org_Invite_UpdateDelivery in v5.0).
        /// </summary>
        private async Task DeliverInviteAsync(
            string typeCode, string inviteValue, string? countryCode,
            string inviterName, string orgName, string inviteLink)
        {
            try
            {
                if (typeCode == "PHONE")
                {
                    // Keep within 160 chars for single-segment SMS
                    var smsText = $"{inviterName} invited you to join {orgName} on RippleHub. Accept: {inviteLink}";
                    await _sms.SendAsync(inviteValue, countryCode ?? "+91", smsText);
                }
                else
                {
                    await _email.SendInviteAsync(inviteValue, inviterName, orgName, inviteLink);
                }
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Invite delivery failed Type={Type} Value={Value}", typeCode, MaskValue(inviteValue, typeCode));
                // Swallow — delivery failure must NOT affect the API response
            }
        }

        private async Task<string> GetOrgNameAsync(int orgId)
        {
            if (orgId <= 0) return "Organisation";
            try
            {
                var row = await ExecuteDynamicGetAsync("Org_GetProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", 0);
                });
                return row?.Get<string>("orgName") ?? "Organisation";
            }
            catch { return "Organisation"; }
        }

        private static string MaskValue(string value, string typeCode)
            => typeCode == "EMAIL"
                ? (value.Split('@') is [var u, var d] ? $"{u[..Math.Min(2, u.Length)]}****@{d}" : "****")
                : (value.Length > 4 ? new string('*', value.Length - 4) + value[^4..] : "****");
    }
}

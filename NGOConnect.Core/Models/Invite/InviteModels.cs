using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Invite
{
    // ── Send Invitation ─────────────────────────────────────────────────────────
    public class SendInviteRequest
    {
        /// <summary>PHONE or EMAIL</summary>
        [Required][MaxLength(10)] public string InviteTypeCode { get; set; } = string.Empty;

        /// <summary>
        /// For PHONE: digits only, no country code (e.g. "9876543210").
        /// For EMAIL: full email address.
        /// </summary>
        [Required][MaxLength(255)] public string InviteValue { get; set; } = string.Empty;

        /// <summary>E.g. "+91". Required when InviteTypeCode = PHONE, null for EMAIL.</summary>
        [MaxLength(6)] public string? CountryCode { get; set; }
    }

    // ── Resend Invitation ───────────────────────────────────────────────────────
    public class ResendInviteRequest
    {
        public int InvitationId { get; set; }
    }

    // ── Cancel Invitation ───────────────────────────────────────────────────────
    public class CancelInviteRequest
    {
        public int InvitationId { get; set; }
    }

    // ── Accept Invitation ───────────────────────────────────────────────────────
    public class AcceptInviteRequest
    {
        /// <summary>The raw token from the deep link URL.</summary>
        [Required][MaxLength(128)] public string Token { get; set; } = string.Empty;
    }

    // ── List Invitations (paged, admin) ─────────────────────────────────────────
    public class InviteListRequest
    {
        /// <summary>PENDING | OPENED | ACCEPTED | CANCELLED | EXPIRED — null = all</summary>
        public string? StatusCode { get; set; }
        public int PageNumber { get; set; } = 1;
        public int PageSize   { get; set; } = 20;
    }

    // ── Result returned by Send (carries delivery context back to controller) ───
    public class InviteSendResult
    {
        public bool    Succeeded          { get; init; }
        public string  Message            { get; init; } = string.Empty;
        /// <summary>
        /// Machine-readable reason for failure.
        /// ALREADY_MEMBER — contact is already an active org member.
        /// ALREADY_INVITED — an active invite already exists; admin should Resend instead.
        /// </summary>
        public string? ErrorCode          { get; init; }
        public int?   InvitationId        { get; init; }
        public bool   ExistingUserFound  { get; init; }
        public int?   ExistingUserId     { get; init; }
        public string? ExistingUserName  { get; init; }
        public string? ExistingUserPhoto { get; init; }
        public string? ExistingUserCity  { get; init; }
        public int    ExistingUserOrgCount { get; init; }
        public string? InviteToken       { get; init; }
        public string? InviteLink        { get; init; }
        /// <summary>PHONE or EMAIL — needed by controller to choose delivery channel.</summary>
        public string  InviteTypeCode    { get; init; } = string.Empty;
        public string  InviteValue       { get; init; } = string.Empty;
        public string? CountryCode       { get; init; }
    }

    // ── Result returned by Resend ───────────────────────────────────────────────
    public class InviteResendResult
    {
        public bool   Succeeded      { get; init; }
        public string Message        { get; init; } = string.Empty;
        public string? InviteToken   { get; init; }
        public string? InviteLink    { get; init; }
        public string? InviteValue   { get; init; }
        public string? CountryCode   { get; init; }
        public int?    InvitedUserId { get; init; }
    }
}

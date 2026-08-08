using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Auth
{
    // ── Send OTP ────────────────────────────────────────────────
    public class SendOtpRequest
    {
        [Required(ErrorMessage = "Recipient is required")]
        public string Recipient { get; set; } = string.Empty;    // Mobile or Email

        [Required]
        public string CountryCode { get; set; } = "+91";

        /// <summary>LookupValueId from OTP_PURPOSE lookup type</summary>
        [Required]
        public int PurposeLkpId { get; set; }
    }

    public class SendOtpResponse
    {
        public string MaskedRecipient { get; set; } = string.Empty;  // e.g. ******4321
        public int ExpiresInSeconds { get; set; } = 600;             // 10 minutes
    }

    // ── Verify OTP ──────────────────────────────────────────────
    public class VerifyOtpRequest
    {
        [Required]
        public string Recipient { get; set; } = string.Empty;

        [Required]
        [StringLength(6, MinimumLength = 6, ErrorMessage = "OTP must be 6 digits")]
        public string OtpCode { get; set; } = string.Empty;

        /// <summary>LookupValueId from OTP_PURPOSE lookup type</summary>
        [Required]
        public int PurposeLkpId { get; set; }

        /// <summary>Dial code e.g. +44, +91 — stored on Users.CountryCode for new registrations</summary>
        public string CountryCode { get; set; } = "+91";
    }

    public class VerifyOtpResponse
    {
        public int UserId { get; set; }
        public bool IsNewUser { get; set; }           // true = first time registration
        public string AccessToken { get; set; } = string.Empty;
        public string RefreshToken { get; set; } = string.Empty;
        public DateTime AccessTokenExpiry { get; set; }
        public DateTime RefreshTokenExpiry { get; set; }
    }

    // ── Refresh Token ───────────────────────────────────────────
    public class RefreshTokenRequest
    {
        [Required]
        public string RefreshToken { get; set; } = string.Empty;
        public string? DeviceInfo { get; set; }
    }

    public class RefreshTokenResponse
    {
        public string AccessToken { get; set; } = string.Empty;
        public string RefreshToken { get; set; } = string.Empty;
        public DateTime AccessTokenExpiry { get; set; }
        public DateTime RefreshTokenExpiry { get; set; }
    }

    // ── Revoke Token ────────────────────────────────────────────
    public class RevokeTokenRequest
    {
        [Required]
        public string RefreshToken { get; set; } = string.Empty;
    }

    // ── Internal DAL model ──────────────────────────────────────
    public class OtpRecord
    {
        public int OtpTokenId { get; set; }
        public int? UserId { get; set; }
        public string OtpCode { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public int AttemptCount { get; set; }
        public bool IsUsed { get; set; }
    }

    public class RefreshTokenRecord
    {
        public int RefreshTokenId { get; set; }
        public int UserId { get; set; }
        public string Token { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public bool IsRevoked { get; set; }
    }
}

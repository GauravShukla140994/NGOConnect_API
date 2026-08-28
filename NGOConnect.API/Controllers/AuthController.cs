using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Auth;
using NGOConnect.Core.Models.Common;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/[controller]")]
    [Produces("application/json")]
    public class AuthController : ControllerBase
    {
        private readonly IAuthDal _authDal;

        public AuthController(IAuthDal authDal)
        {
            _authDal = authDal;
        }

        /// <summary>Send OTP to mobile or email </summary>
        [HttpPost("send-otp")]
        [ProducesResponseType(typeof(ApiResponse<SendOtpResponse>), 200)]
        public async Task<ApiResponse<SendOtpResponse>> SendOtp(
            [FromBody] SendOtpRequest request)
        {
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            return await _authDal.SendOtpAsync(request, ipAddress);
        }

        /// <summary>Verify OTP and receive JWT tokens</summary>
        [HttpPost("verify-otp")]
        [ProducesResponseType(typeof(ApiResponse<VerifyOtpResponse>), 200)]
        public async Task<ApiResponse<VerifyOtpResponse>> VerifyOtp(
            [FromBody] VerifyOtpRequest request)
        {
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            return await _authDal.VerifyOtpAsync(request, ipAddress);
        }

        /// <summary>Refresh expired access token using refresh token</summary>
        [HttpPost("refresh-token")]
        [ProducesResponseType(typeof(ApiResponse<RefreshTokenResponse>), 200)]
        public async Task<ApiResponse<RefreshTokenResponse>> RefreshToken(
            [FromBody] RefreshTokenRequest request)
        {
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            return await _authDal.RefreshTokenAsync(request, ipAddress);
        }

        /// <summary>Revoke refresh token on logout</summary>
        [HttpPost("revoke-token")]
        [ProducesResponseType(typeof(ApiResponse), 200)]
        public async Task<ApiResponse> RevokeToken(
            [FromBody] RevokeTokenRequest request)
        {
            return await _authDal.RevokeTokenAsync(request);
        }

        /// <summary>
        /// Creates a fresh account with the same Mobile/Email as a grace-period deleted account.
        /// Called when the user taps "No thanks, start fresh" in the revival modal.
        /// Requires the grace-period Bearer token issued during OTP verify (IsPendingDeletion=true).
        /// Returns new JWT tokens for the brand-new UserId.
        /// </summary>
        [HttpPost("fresh-account")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<VerifyOtpResponse>), 200)]
        public async Task<ApiResponse<VerifyOtpResponse>> CreateFreshAccount()
        {
            var ip        = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
            var claim     = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            var oldUserId = claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;

            return await _authDal.CreateFreshAccountAsync(oldUserId, ip);
        }
    }
}

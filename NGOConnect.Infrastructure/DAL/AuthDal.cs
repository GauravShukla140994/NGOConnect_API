using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Auth;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// Auth DAL — Controller → IAuthDal → AuthDal → Stored Procedures → MySQL
    /// All DB calls go through IDbProvider. No direct MySqlConnection usage.
    /// </summary>
    public class AuthDal : IAuthDal
    {
        private readonly IDbProvider _db;
        private readonly IConfiguration _config;

        public AuthDal(IDbProvider db, IConfiguration config)
        {
            _db = db;
            _config = config;
        }

        // ── Send OTP ─────────────────────────────────────────────
        public async Task<ApiResponse<SendOtpResponse>> SendOtpAsync(
            SendOtpRequest request, string ipAddress)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Auth_SendOTP", conn);

                // Generate OTP here (6-digit)
                var otp = GenerateOtp();

                _db.AddParameter(cmd, "p_Recipient",     request.Recipient);
                _db.AddParameter(cmd, "p_CountryCode",   request.CountryCode);
                _db.AddParameter(cmd, "p_OtpCode",       otp);
                _db.AddParameter(cmd, "p_PurposeLkpId",  request.PurposeLkpId);
                _db.AddParameter(cmd, "p_IpAddress",     ipAddress);
                _db.AddParameter(cmd, "p_ExpiryMinutes", 10);

                var ds = await _db.FillDataSetAsync(cmd);

                if (!HasRows(ds))
                    return ApiResponse<SendOtpResponse>.Failure("Failed to generate OTP. Please try again.", "OTP_GENERATE_FAILED");

                var row = ds.Tables[0].Rows[0];
                int isSuccess = Convert.ToInt32(row["IsSuccess"]);

                if (isSuccess == 0)
                    return ApiResponse<SendOtpResponse>.Failure(row["Message"].ToString()!, "OTP_BLOCKED");

                // TODO: Send OTP via Twilio/MSG91
                // await _smsService.SendAsync(request.Recipient, otp);
                Log.Information("OTP generated for {Recipient} | Purpose: {Purpose}",
                    MaskRecipient(request.Recipient), request.PurposeLkpId);

                return ApiResponse<SendOtpResponse>.Success(new SendOtpResponse
                {
                    MaskedRecipient  = MaskRecipient(request.Recipient),
                    ExpiresInSeconds = Convert.ToInt32(otp), // 10 minutes × 60 seconds (matches p_ExpiryMinutes above)
                }, "OTP sent successfully");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SendOtpAsync failed for {Recipient}", request.Recipient);
                return ApiResponse<SendOtpResponse>.Failure("An error occurred. Please try again.", "INTERNAL_ERROR");
            }
        }

        // ── Verify OTP ───────────────────────────────────────────
        public async Task<ApiResponse<VerifyOtpResponse>> VerifyOtpAsync(
            VerifyOtpRequest request, string ipAddress)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Auth_VerifyOTP", conn);

                _db.AddParameter(cmd, "p_Recipient",    request.Recipient);
                _db.AddParameter(cmd, "p_OtpCode",      request.OtpCode);
                _db.AddParameter(cmd, "p_PurposeLkpId", request.PurposeLkpId);
                _db.AddParameter(cmd, "p_IpAddress",    ipAddress);

                var ds = await _db.FillDataSetAsync(cmd);

                if (!HasRows(ds))
                    return ApiResponse<VerifyOtpResponse>.Failure("Invalid or expired OTP.", "OTP_INVALID");

                var row       = ds.Tables[0].Rows[0];
                int isSuccess = Convert.ToInt32(row["IsSuccess"]);

                if (isSuccess == 0)
                    return ApiResponse<VerifyOtpResponse>.Failure(
                        row["Message"].ToString()!, "OTP_VERIFY_FAILED");

                int  userId    = row["UserId"] == DBNull.Value? 0: Convert.ToInt32(row["UserId"]);
                bool isNewUser = Convert.ToBoolean(row["IsNewUser"]);

                // Generate JWT + Refresh token
                var accessToken    = GenerateJwt(userId, request.Recipient);
                var refreshToken   = GenerateRefreshToken();
                var accessExpiry   = DateTime.UtcNow.AddMinutes(15);
                var refreshExpiry  = DateTime.UtcNow.AddDays(30);

                // Save refresh token to DB
                await SaveRefreshTokenAsync(conn, userId, refreshToken, refreshExpiry, ipAddress);

                Log.Information("OTP verified. UserId={UserId} IsNew={IsNew}", userId, isNewUser);

                return ApiResponse<VerifyOtpResponse>.Success(new VerifyOtpResponse
                {
                    UserId             = userId,
                    IsNewUser          = isNewUser,
                    AccessToken        = accessToken,
                    RefreshToken       = refreshToken,
                    AccessTokenExpiry  = accessExpiry,
                    RefreshTokenExpiry = refreshExpiry
                }, isNewUser ? "Registration successful" : "Login successful");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyOtpAsync failed for {Recipient}", request.Recipient);
                return ApiResponse<VerifyOtpResponse>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Refresh Token ────────────────────────────────────────
        public async Task<ApiResponse<RefreshTokenResponse>> RefreshTokenAsync(
            RefreshTokenRequest request, string ipAddress)
        {
            try
            {
                var hashedToken = HashToken(request.RefreshToken);

                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Auth_GetRefreshToken", conn);
                _db.AddParameter(cmd, "p_Token", hashedToken);

                var ds = await _db.FillDataSetAsync(cmd);

                if (!HasRows(ds))
                    return ApiResponse<RefreshTokenResponse>.Failure("Invalid refresh token.", "TOKEN_INVALID");

                var row       = ds.Tables[0].Rows[0];
                int isSuccess = Convert.ToInt32(row["IsSuccess"]);

                if (isSuccess == 0)
                    return ApiResponse<RefreshTokenResponse>.Failure(
                        row["Message"].ToString()!, "TOKEN_EXPIRED");

                int      userId      = Convert.ToInt32(row["UserId"]);
                string   recipient   = row["Recipient"].ToString()!;
                int      tokenId     = Convert.ToInt32(row["RefreshTokenId"]);

                // Rotate: revoke old, issue new
                await RevokeRefreshTokenByIdAsync(conn, tokenId);

                var newAccessToken   = GenerateJwt(userId, recipient);
                var newRefreshToken  = GenerateRefreshToken();
                var accessExpiry     = DateTime.UtcNow.AddMinutes(15);
                var refreshExpiry    = DateTime.UtcNow.AddDays(30);

                await SaveRefreshTokenAsync(conn, userId, newRefreshToken, refreshExpiry,
                    ipAddress, request.DeviceInfo);

                Log.Information("Token refreshed. UserId={UserId}", userId);

                return ApiResponse<RefreshTokenResponse>.Success(new RefreshTokenResponse
                {
                    AccessToken        = newAccessToken,
                    RefreshToken       = newRefreshToken,
                    AccessTokenExpiry  = accessExpiry,
                    RefreshTokenExpiry = refreshExpiry
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RefreshTokenAsync failed");
                return ApiResponse<RefreshTokenResponse>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Revoke Token ─────────────────────────────────────────
        public async Task<ApiResponse> RevokeTokenAsync(RevokeTokenRequest request)
        {
            try
            {
                var hashedToken = HashToken(request.RefreshToken);

                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Auth_RevokeRefreshToken", conn);
                _db.AddParameter(cmd, "p_Token", hashedToken);

                var ds        = await _db.FillDataSetAsync(cmd);
                var row       = ds.Tables[0].Rows[0];
                int isSuccess = Convert.ToInt32(row["IsSuccess"]);

                return isSuccess == 1
                    ? ApiResponse.Ok("Token revoked successfully")
                    : ApiResponse.Fail(row["Message"].ToString()!, "TOKEN_NOT_FOUND");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RevokeTokenAsync failed");
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Private Helpers ──────────────────────────────────────

        private string GenerateJwt(int userId, string recipient)
        {
            var jwtKey     = _config["Jwt:Key"]
                ?? throw new InvalidOperationException("JWT Key not configured");
            var jwtIssuer  = _config["Jwt:Issuer"]    ?? "NGOConnect";
            var jwtAudience = _config["Jwt:Audience"] ?? "NGOConnectUsers";

            var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
            var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var claims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub,  userId.ToString()),
                new Claim(JwtRegisteredClaimNames.Email, recipient),
                new Claim(JwtRegisteredClaimNames.Jti,  Guid.NewGuid().ToString()),
                new Claim("uid", userId.ToString())
            };

            var token = new JwtSecurityToken(
                issuer:             jwtIssuer,
                audience:           jwtAudience,
                claims:             claims,
                expires:            DateTime.UtcNow.AddMinutes(15),
                signingCredentials: creds);

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        private static string GenerateRefreshToken()
        {
            var bytes = RandomNumberGenerator.GetBytes(64);
            return Convert.ToBase64String(bytes);
        }

        private static string GenerateOtp()
        {
            // Cryptographically secure 6-digit OTP
            var bytes = RandomNumberGenerator.GetBytes(4);
            var value = BitConverter.ToUInt32(bytes, 0) % 1000000;
            return value.ToString("D6");
        }

        private static string HashToken(string token)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            return Convert.ToBase64String(bytes);
        }

        private static string MaskRecipient(string recipient)
        {
            if (recipient.Contains('@'))
            {
                // Email: ab****@domain.com
                var parts = recipient.Split('@');
                var masked = parts[0].Length > 2
                    ? parts[0][..2] + "****"
                    : "****";
                return $"{masked}@{parts[1]}";
            }
            // Mobile: ******4321
            return recipient.Length > 4
                ? new string('*', recipient.Length - 4) + recipient[^4..]
                : "****";
        }

        private async Task SaveRefreshTokenAsync(
            IDbConnection conn, int userId, string rawToken,
            DateTime expiry, string ipAddress, string? deviceInfo = null)
        {
            using var cmd = _db.CreateCommand("Auth_SaveRefreshToken", conn);
            _db.AddParameter(cmd, "p_UserId",     userId);
            _db.AddParameter(cmd, "p_Token",      HashToken(rawToken));
            _db.AddParameter(cmd, "p_DeviceInfo", deviceInfo);
            _db.AddParameter(cmd, "p_IpAddress",  ipAddress);
            _db.AddParameter(cmd, "p_ExpiresAt",  expiry);
            await _db.ExecuteNonQueryAsync(cmd);
        }

        private async Task RevokeRefreshTokenByIdAsync(IDbConnection conn, int tokenId)
        {
            using var cmd = _db.CreateCommand("Auth_RevokeRefreshTokenById", conn);
            _db.AddParameter(cmd, "p_RefreshTokenId", tokenId);
            await _db.ExecuteNonQueryAsync(cmd);
        }

        private static bool HasRows(DataSet ds)
            => ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0;
    }
}

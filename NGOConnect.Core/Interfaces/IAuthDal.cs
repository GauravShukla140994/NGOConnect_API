using NGOConnect.Core.Models.Auth;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Auth Data Access Layer contract.
    /// Implemented in NGOConnect.Infrastructure.DAL.AuthDal
    /// </summary>
    public interface IAuthDal
    {
        Task<ApiResponse<SendOtpResponse>>      SendOtpAsync(SendOtpRequest request, string ipAddress);
        Task<ApiResponse<VerifyOtpResponse>>    VerifyOtpAsync(VerifyOtpRequest request, string ipAddress);
        Task<ApiResponse<RefreshTokenResponse>> RefreshTokenAsync(RefreshTokenRequest request, string ipAddress);
        Task<ApiResponse>                       RevokeTokenAsync(RevokeTokenRequest request);

        /// <summary>
        /// Creates a brand-new Users + UserProfiles row using the same Mobile/Email
        /// as the grace-period deleted account (p_OldUserId). Issues fresh JWT tokens
        /// for the new account. Called when user taps "Start Fresh" in the revival modal.
        /// </summary>
        Task<ApiResponse<VerifyOtpResponse>>    CreateFreshAccountAsync(int oldUserId, string ipAddress);
    }
}

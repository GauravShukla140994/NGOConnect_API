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
        Task<ApiResponse<SendOtpResponse>>    SendOtpAsync(SendOtpRequest request, string ipAddress);
        Task<ApiResponse<VerifyOtpResponse>>  VerifyOtpAsync(VerifyOtpRequest request, string ipAddress);
        Task<ApiResponse<RefreshTokenResponse>> RefreshTokenAsync(RefreshTokenRequest request, string ipAddress);
        Task<ApiResponse>                     RevokeTokenAsync(RevokeTokenRequest request);
    }
}

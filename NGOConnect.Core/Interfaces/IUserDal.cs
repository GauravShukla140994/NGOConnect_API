using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;

namespace NGOConnect.Core.Interfaces
{
    public interface IUserDal
    {
        // Profile
        Task<ApiResponse<UserProfileModel>>         GetProfileAsync(int userId);
        Task<ApiResponse<DynamicRow>>               GetPublicProfileAsync(int userId);
        Task<ApiResponse>                           UpdateProfileAsync(int userId, UpdateProfileRequest request);
        // Safety
        Task<ApiResponse<UserSafetyPrefsModel>>     GetSafetyPrefsAsync(int userId);
        Task<ApiResponse>                           UpdateSafetyPrefsAsync(int userId, UpdateSafetyPrefsRequest request);
        // Interests
        Task<ApiResponse<List<UserInterestModel>>>  GetInterestsAsync(int userId);
        Task<ApiResponse>                           SaveInterestsAsync(int userId, SaveInterestsRequest request);
        // Documents
        Task<ApiResponse>                              UploadDocumentAsync(int userId, UploadDocumentRequest request);
        Task<ApiResponse<List<UserDocumentModel>>>     GetDocumentsAsync(int userId);
        Task<ApiResponse>                              DeleteDocumentAsync(int userId, int userDocumentId);
        // Skills
        Task<ApiResponse<List<UserSkillModel>>>     GetSkillsAsync(int userId);
        Task<ApiResponse>                           AddSkillAsync(int userId, AddSkillRequest request);
        Task<ApiResponse>                           RemoveSkillAsync(int userId, int userSkillId);
        // My Organisations
        Task<ApiResponse<List<UserOrgModel>>>       GetMyOrgsAsync(int userId);
        // Badges
        Task<ApiResponse<List<UserBadgeModel>>>     GetBadgesAsync(int userId);
        // Impact Dashboard
        Task<ApiResponse<UserImpactModel>>          GetImpactAsync(int userId);
        // Impact Summary — single call: impact stats + 4 tab lists + badges + counts
        Task<ApiResponse<ImpactSummaryModel>>       GetImpactSummaryAsync(int userId);
        // Contact Update (OTP flow)
        Task<ApiResponse>                           SendContactOtpAsync(int userId, SendContactOtpRequest request, string ipAddress);
        Task<ApiResponse>                           VerifyContactOtpAsync(int userId, VerifyContactOtpRequest request, string ipAddress);
        // Account Deletion + Revival (Google Play + App Store compliance)
        Task<ApiResponse>                           RequestAccountDeletionAsync(int userId);
        Task<ApiResponse>                           ReviveAccountAsync(int userId);
    }
}

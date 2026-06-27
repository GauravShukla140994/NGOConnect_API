using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;

namespace NGOConnect.Core.Interfaces
{
    public interface IUserDal
    {
        Task<ApiResponse<UserProfileModel>>     GetProfileAsync(int userId);
        Task<ApiResponse<DynamicRow>>           GetPublicProfileAsync(int userId);
        Task<ApiResponse>                       UpdateProfileAsync(int userId, UpdateProfileRequest request);
        Task<ApiResponse>                       UpdateSafetyPrefsAsync(int userId, UpdateSafetyPrefsRequest request);
        Task<ApiResponse>                       SaveInterestsAsync(int userId, SaveInterestsRequest request);
        Task<ApiResponse>                       UploadDocumentAsync(int userId, UploadDocumentRequest request);
        Task<ApiResponse<List<UserSkillModel>>> GetSkillsAsync(int userId);
        Task<ApiResponse>                       AddSkillAsync(int userId, AddSkillRequest request);
        Task<ApiResponse>                       RemoveSkillAsync(int userId, int userSkillId);
    }
}

using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.User;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// User Data Access Layer contract.
    /// Implemented in NGOConnect.Infrastructure.DAL.UserDal
    ///
    /// GetProfile        → typed UserProfileModel (own profile, private data)
    /// GetPublicProfile  → DynamicRow (public display, shape driven by SP)
    /// UpdateProfile     → write
    /// GetSkills         → typed list via DataReader (frequent call)
    /// AddSkill          → write (upsert — also updates proficiency)
    /// RemoveSkill       → write
    /// </summary>
    public interface IUserDal
    {
        Task<ApiResponse<UserProfileModel>>     GetProfileAsync(int userId);
        Task<ApiResponse<DynamicRow>>           GetPublicProfileAsync(int userId);
        Task<ApiResponse>                       UpdateProfileAsync(int userId, UpdateProfileRequest request);
        Task<ApiResponse<List<UserSkillModel>>> GetSkillsAsync(int userId);
        Task<ApiResponse>                       AddSkillAsync(int userId, AddSkillRequest request);
        Task<ApiResponse>                       RemoveSkillAsync(int userId, int userSkillId);
    }
}

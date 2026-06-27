using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;

namespace NGOConnect.Core.Interfaces
{
    public interface ISkillRatingDal
    {
        Task<ApiResponse> AddRatingAsync(int raterUserId, AddSkillRatingRequest request);
    }
}

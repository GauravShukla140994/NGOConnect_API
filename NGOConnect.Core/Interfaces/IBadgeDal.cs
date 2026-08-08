using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;

namespace NGOConnect.Core.Interfaces
{
    public interface IBadgeDal
    {
        Task<ApiResponse> AwardAsync(int awardedBy, AwardBadgeRequest request);
    }
}

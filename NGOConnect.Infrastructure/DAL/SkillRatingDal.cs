using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class SkillRatingDal : BaseDal, ISkillRatingDal
    {
        public SkillRatingDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse> AddRatingAsync(int raterUserId, AddSkillRatingRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserSkillRating_Add", cmd =>
                {
                    _db.AddParameter(cmd, "p_RaterUserId",  raterUserId);
                    _db.AddParameter(cmd, "p_RatedUserId",  request.RatedUserId);
                    _db.AddParameter(cmd, "p_UserSkillId",  request.UserSkillId);
                    _db.AddParameter(cmd, "p_Rating",       request.Rating);
                    _db.AddParameter(cmd, "p_Review",       request.Review);
                    _db.AddParameter(cmd, "p_ProjectId",    request.ProjectId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddRatingAsync failed RaterUserId={Id}", raterUserId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

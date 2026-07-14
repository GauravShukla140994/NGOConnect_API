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
                    _db.AddParameter(cmd, "p_UserId",    request.RatedUserId);   // the volunteer being rated
                    _db.AddParameter(cmd, "p_OrgId",     (object?)null);          // no org context here
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                    _db.AddParameter(cmd, "p_SkillId",   request.UserSkillId);   // UserSkillId IS the skill being rated
                    _db.AddParameter(cmd, "p_Rating",    request.Rating);
                    _db.AddParameter(cmd, "p_RatedBy",   raterUserId);
                    _db.AddParameter(cmd, "p_Notes",     request.Review);
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

using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class BadgeDal : BaseDal, IBadgeDal
    {
        public BadgeDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse> AwardAsync(int awardedBy, AwardBadgeRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserBadge_Award", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     request.UserId);
                    _db.AddParameter(cmd, "p_BadgeLkpId", request.BadgeLkpId);
                    _db.AddParameter(cmd, "p_AwardedBy",  awardedBy);
                    _db.AddParameter(cmd, "p_OrgId",      (object?)null);   // no org context in standalone badge award
                    _db.AddParameter(cmd, "p_ProjectId",  request.ProjectId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwardAsync failed AwardedBy={Id}", awardedBy);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

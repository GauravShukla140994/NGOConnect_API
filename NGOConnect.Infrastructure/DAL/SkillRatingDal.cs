using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class SkillRatingDal : BaseDal, ISkillRatingDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public SkillRatingDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse> AddRatingAsync(int raterUserId, AddSkillRatingRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserSkillRating_Add", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",    request.RatedUserId);
                    _db.AddParameter(cmd, "p_OrgId",     (object?)request.OrgId);
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                    _db.AddParameter(cmd, "p_SkillId",   request.ProjectSkillId);
                    _db.AddParameter(cmd, "p_Rating",    request.Rating);
                    _db.AddParameter(cmd, "p_RatedBy",   raterUserId);
                    _db.AddParameter(cmd, "p_Notes",     request.Notes);
                });

                if (result.Succeeded)
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            await _notif.CreateAsync(request.RatedUserId, "⭐ Skill Rating Received",
                                "Someone rated one of your skills. Check your impact profile!",
                                "SKILL_RATING", request.ProjectId, "PROJECT");
                            var tokens = await _notif.GetTokensByUserIdAsync(request.RatedUserId);
                            await _fcm.SendMulticastAsync(tokens, "⭐ Skill Rating Received",
                                "Someone rated one of your skills. Check your impact profile!",
                                "SKILL_RATING", request.ProjectId, "PROJECT");
                        }
                        catch (Exception ex) { Log.Error(ex, "SkillRatingDal.AddRatingAsync notify failed"); }
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

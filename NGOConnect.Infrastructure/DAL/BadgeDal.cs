using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Skill;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class BadgeDal : BaseDal, IBadgeDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public BadgeDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse> AwardAsync(int awardedBy, AwardBadgeRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserBadge_Award", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     request.UserId);
                    _db.AddParameter(cmd, "p_BadgeLkpId", request.BadgeLkpId);
                    _db.AddParameter(cmd, "p_AwardedBy",  awardedBy);
                    _db.AddParameter(cmd, "p_OrgId",      (object?)null);
                    _db.AddParameter(cmd, "p_ProjectId",  request.ProjectId);
                });

                if (result.Succeeded)
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            await _notif.CreateAsync(request.UserId, "🏅 Badge Awarded!",
                                "Congratulations! You have earned a new badge.",
                                "BADGE_AWARDED", request.UserId, "USER");
                            var tokens = await _notif.GetTokensByUserIdAsync(request.UserId);
                            await _fcm.SendMulticastAsync(tokens, "🏅 Badge Awarded!",
                                "Congratulations! You have earned a new badge.",
                                "BADGE_AWARDED", request.UserId, "USER");
                        }
                        catch (Exception ex) { Log.Error(ex, "BadgeDal.AwardAsync notify failed"); }
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

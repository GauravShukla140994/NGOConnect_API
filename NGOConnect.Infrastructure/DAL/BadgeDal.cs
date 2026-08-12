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
                    _db.AddParameter(cmd, "p_UserId",    request.UserId);
                    _db.AddParameter(cmd, "p_BadgeCode", request.BadgeCode);
                    _db.AddParameter(cmd, "p_AwardedBy", awardedBy);
                    _db.AddParameter(cmd, "p_OrgId",     (object?)null);
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                });

                if (result.Succeeded)
                {
                    var badgeName = Col<string>(result.Row!, "BadgeName") ?? "Badge";
                    var title     = "🏅 Badge Awarded!";
                    var body      = $"Congratulations! You've earned the {badgeName} badge. Keep up the great work!";

                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            await _notif.CreateAsync(request.UserId, title, body,
                                "BADGE_AWARDED", request.ProjectId, "PROJECT");
                            var tokens = await _notif.GetTokensByUserIdAsync(request.UserId);
                            await _fcm.SendMulticastAsync(tokens, title, body,
                                "BADGE_AWARDED", request.ProjectId, "PROJECT");
                        }
                        catch (Exception ex) { Log.Error(ex, "BadgeDal.AwardAsync notify failed"); }
                    });
                }

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

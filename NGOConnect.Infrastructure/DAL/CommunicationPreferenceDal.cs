using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CommunicationPreferenceDal : BaseDal, ICommunicationPreferenceDal
    {
        public CommunicationPreferenceDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<DynamicRow>> GetAsync(int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("UserCommunicationPreference_Get",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<DynamicRow>.Success(row ?? new DynamicRow());
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CommunicationPreference.GetAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateAsync(int userId, UpdateCommunicationPreferencesRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserCommunicationPreference_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_ReceivePushNotifications",      ToDb(request.ReceivePushNotifications));
                    _db.AddParameter(cmd, "p_ReceivePromotionalEmails",      ToDb(request.ReceivePromotionalEmails));
                    _db.AddParameter(cmd, "p_ReceivePromotionalSms",        ToDb(request.ReceivePromotionalSms));
                    _db.AddParameter(cmd, "p_ReceiveNgoUpdates",             ToDb(request.ReceiveNgoUpdates));
                    _db.AddParameter(cmd, "p_ReceiveDonationAlerts",         ToDb(request.ReceiveDonationAlerts));
                    _db.AddParameter(cmd, "p_ReceiveVolunteerOpportunities", ToDb(request.ReceiveVolunteerOpportunities));
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CommunicationPreference.UpdateAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        private static object ToDb(bool? value) => value.HasValue ? (value.Value ? 1 : 0) : DBNull.Value;
    }
}

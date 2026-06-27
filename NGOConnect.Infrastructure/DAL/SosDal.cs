using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Sos;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class SosDal : BaseDal, ISosDal
    {
        public SosDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<DynamicRow>> TriggerAsync(int userId, TriggerSosRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Trigger", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgId",          (object?)null);
                    _db.AddParameter(cmd, "p_AlertTypeLkpId", request.AlertTypeLkpId);
                    _db.AddParameter(cmd, "p_Description",    request.Description);
                    _db.AddParameter(cmd, "p_ApproxLocation", (object?)null);
                    _db.AddParameter(cmd, "p_Latitude",       request.Latitude);
                    _db.AddParameter(cmd, "p_Longitude",      request.Longitude);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "SOS_TRIGGER_FAILED");

                var incidentId = Col<int>(result.Row!, "SosIncidentId");
                var data = new DynamicRow();
                data["sosIncidentId"] = incidentId;
                data["message"]       = result.Message;
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "TriggerAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetActiveAsync(int userId, int? orgId = null)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Sos_GetActive", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetActiveAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int sosIncidentId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Sos_GetById", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("SOS incident not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByIdAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ResolveAsync(int sosIncidentId, int userId, ResolveSosRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Resolve", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId",  sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_StatusCode",     "RESOLVED");
                    _db.AddParameter(cmd, "p_CancelReason",   (object?)null);
                    _db.AddParameter(cmd, "p_ResolvedByLkpId", request.ResolvedByLkpId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ResolveAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CancelAsync(int sosIncidentId, int userId, CancelSosRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Resolve", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId",  sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_StatusCode",     "CANCELLED");
                    _db.AddParameter(cmd, "p_CancelReason",   request.CancelReason);
                    _db.AddParameter(cmd, "p_ResolvedByLkpId", (object?)null);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CancelAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RespondAsync(int sosIncidentId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Respond", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RespondAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ApproveResponderAsync(int sosIncidentId, int userId, ApproveResponderRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_ApproveResponder", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId",  sosIncidentId);
                    _db.AddParameter(cmd, "p_ApprovedBy",     userId);
                    _db.AddParameter(cmd, "p_ResponderId",    request.ResponderId);
                    _db.AddParameter(cmd, "p_CanViewLocation", request.CanViewLocation);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApproveResponderAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetLatestLocationAsync(int sosIncidentId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Sos_GetLatestLocation", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Location not available or access denied.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetLatestLocationAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateLocationAsync(int sosIncidentId, int userId, UpdateLocationRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_UpdateLocation", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_Latitude",      request.Latitude);
                    _db.AddParameter(cmd, "p_Longitude",     request.Longitude);
                    _db.AddParameter(cmd, "p_Accuracy",      request.Accuracy);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateLocationAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

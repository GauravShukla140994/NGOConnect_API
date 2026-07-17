using Microsoft.AspNetCore.SignalR;
using NGOConnect.API.Hubs;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Sos;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class SosDal : BaseDal, ISosDal
    {
        private readonly IHubContext<SosHub> _hub;
        private readonly INotificationDal    _notif;
        private readonly IFCMService         _fcm;

        public SosDal(IDbProvider db, IHubContext<SosHub> hub, INotificationDal notif, IFCMService fcm)
            : base(db) { _hub = hub; _notif = notif; _fcm = fcm; }

        // ── Bug 4 fixed: now passes OrgId + ApproxLocation from request ────────
        public async Task<ApiResponse<DynamicRow>> TriggerAsync(int userId, TriggerSosRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Trigger", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgId",          (object?)request.OrgId);
                    _db.AddParameter(cmd, "p_AlertTypeLkpId", request.AlertTypeLkpId);
                    _db.AddParameter(cmd, "p_Description",    request.Description);
                    _db.AddParameter(cmd, "p_ApproxLocation", request.ApproxLocation);
                    _db.AddParameter(cmd, "p_Latitude",       request.Latitude);
                    _db.AddParameter(cmd, "p_Longitude",      request.Longitude);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "SOS_TRIGGER_FAILED");

                var incidentId = Col<int>(result.Row!, "SosIncidentId");
                var data = new DynamicRow();
                data["sosIncidentId"] = incidentId;
                data["message"]       = result.Message;

                // SignalR + FCM fan-out: notify all org members of new SOS
                if (request.OrgId.HasValue)
                {
                    await _hub.Clients.Group($"org-{request.OrgId}")
                        .SendAsync("NewSosAlert", new { sosIncidentId = incidentId });
                    _ = FireOrgNotifAsync(request.OrgId.Value, userId,
                        "🆘 SOS Alert!", "A member needs help urgently. Tap to respond.",
                        "SOS_TRIGGERED", incidentId, "SOS");
                }

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

        public async Task<ApiResponse<List<DynamicRow>>> GetOrgAlertsAsync(int orgId, int userId, int limit = 20)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Sos_GetOrgAlerts", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_Limit",  limit);
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgAlertsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Bug 3 fixed: reads 2 result sets (incident + responders) ──────────
        public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int sosIncidentId, int userId)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Sos_GetById", conn);
                _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                _db.AddParameter(cmd, "p_UserId",        userId);

                var ds = await _db.FillDataSetAsync(cmd);

                if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return ApiResponse<DynamicRow>.Failure("SOS incident not found.", "NOT_FOUND");

                var incident = new DynamicRow(ds.Tables[0].Rows[0]);

                var responders = new List<DynamicRow>();
                if (ds.Tables.Count > 1)
                    foreach (System.Data.DataRow r in ds.Tables[1].Rows)
                        responders.Add(new DynamicRow(r));

                incident["responders"] = responders;
                return ApiResponse<DynamicRow>.Success(incident);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByIdAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── New: victim's own active incident + responders ────────────────────
        public async Task<ApiResponse<DynamicRow>> GetMyActiveAsync(int userId)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Sos_GetMyActive", conn);
                _db.AddParameter(cmd, "p_UserId", userId);

                var ds = await _db.FillDataSetAsync(cmd);

                if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return ApiResponse<DynamicRow>.Failure("No active SOS found.", "NOT_FOUND");

                var incident = new DynamicRow(ds.Tables[0].Rows[0]);

                var responders = new List<DynamicRow>();
                if (ds.Tables.Count > 1)
                    foreach (System.Data.DataRow r in ds.Tables[1].Rows)
                        responders.Add(new DynamicRow(r));

                incident["responders"] = responders;
                return ApiResponse<DynamicRow>.Success(incident);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMyActiveAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Bug 2 fixed: removed p_ResolvedByLkpId, no request body ─────────
        public async Task<ApiResponse> ResolveAsync(int sosIncidentId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Resolve", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_StatusCode",    "RESOLVED");
                    _db.AddParameter(cmd, "p_CancelReason",  (object?)null);
                });

                if (result.Succeeded)
                {
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("SosResolved", new { sosIncidentId, status = "RESOLVED" });
                    _ = FireSosResponderNotifAsync(sosIncidentId, "SOS Resolved ✅", "The SOS has been resolved. Thank you for responding!", "SOS_RESOLVED");
                }

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ResolveAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Bug 2 fixed: removed p_ResolvedByLkpId from Cancel too ──────────
        public async Task<ApiResponse> CancelAsync(int sosIncidentId, int userId, CancelSosRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_Resolve", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId", sosIncidentId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_StatusCode",    "CANCELLED");
                    _db.AddParameter(cmd, "p_CancelReason",  request.CancelReason);
                });

                if (result.Succeeded)
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("SosResolved", new { sosIncidentId, status = "CANCELLED" });

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

                if (result.Succeeded)
                {
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("NewResponder", new { sosIncidentId });
                    // #36 — Notify the SOS victim that someone is coming to help
                    var victimUserId = Col<int?>(result.Row!, "VictimUserId");
                    if (victimUserId.HasValue)
                        _ = FireUserNotifAsync(victimUserId.Value,
                            "🙋 Someone Is Responding!",
                            "A member has offered to help you. Hang on — they are on their way.",
                            "SOS_RESPONDER_INCOMING", sosIncidentId, "SOS");
                }

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RespondAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Bug 1 fixed: uses p_SosResponderId (not p_SosIncidentId + p_ResponderId) ──
        public async Task<ApiResponse> ApproveResponderAsync(int sosIncidentId, int userId, ApproveResponderRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_ApproveResponder", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosResponderId",  request.SosResponderId);
                    _db.AddParameter(cmd, "p_ApprovedBy",      userId);
                    _db.AddParameter(cmd, "p_CanViewLocation", request.CanViewLocation);
                });

                if (result.Succeeded)
                {
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("ResponderApproved", new { sosIncidentId, sosResponderId = request.SosResponderId });
                    if (result.Row is not null)
                    {
                        var responderUserId = Col<int>(result.Row, "ResponderUserId");
                        _ = FireUserNotifAsync(responderUserId, "SOS: You're Approved ✅", "You have been approved as a responder. Head to the live location now.", "SOS_RESPONDER_APPROVED", sosIncidentId, "SOS");
                    }
                }

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApproveResponderAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> DeclineResponderAsync(int sosIncidentId, int userId, DeclineResponderRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Sos_DeclineResponder", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId",  sosIncidentId);
                    _db.AddParameter(cmd, "p_SosResponderId", request.SosResponderId);
                    _db.AddParameter(cmd, "p_DeclinedBy",     userId);
                });

                if (result.Succeeded)
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("ResponderDeclined", new { sosIncidentId, sosResponderId = request.SosResponderId });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeclineResponderAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetLatestLocationAsync(int sosIncidentId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Sos_GetLatestLocation", cmd =>
                {
                    _db.AddParameter(cmd, "p_SosIncidentId",    sosIncidentId);
                    _db.AddParameter(cmd, "p_RequestingUserId", userId);
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

                if (result.Succeeded)
                    await _hub.Clients.Group($"sos-{sosIncidentId}")
                        .SendAsync("LocationUpdated", new { sosIncidentId, userId,
                            latitude = request.Latitude, longitude = request.Longitude });

                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateLocationAsync failed SosIncidentId={Id}", sosIncidentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Notification helpers ──────────────────────────────────────────────────

        private async Task FireUserNotifAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                await _notif.CreateAsync(userId, title, body, notifType, refId, refType);
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SosDal.FireUserNotifAsync failed"); }
        }

        private async Task FireOrgNotifAsync(int orgId, int excludeUserId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var tokens = await _notif.GetTokensByOrgIdAsync(orgId, excludeUserId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SosDal.FireOrgNotifAsync failed"); }
        }

        private async Task FireSosResponderNotifAsync(int sosIncidentId, string title, string body, string notifType)
        {
            try
            {
                var tokens = await _notif.GetTokensBySosIncidentIdAsync(sosIncidentId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, sosIncidentId, "SOS");
            }
            catch (Exception ex) { Log.Error(ex, "SosDal.FireSosResponderNotifAsync failed"); }
        }
    }
}

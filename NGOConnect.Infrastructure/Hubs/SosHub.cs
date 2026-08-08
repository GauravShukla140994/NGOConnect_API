using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace NGOConnect.API.Hubs
{
    /// <summary>
    /// Real-time hub for SOS incidents.
    ///
    /// Groups:
    ///   sos-{sosIncidentId}  — victim + all approved responders for a specific incident
    ///   org-{orgId}          — all org members (receive new SOS alert notifications)
    ///
    /// Client events received (client → server):
    ///   JoinSosGroup(sosIncidentId)        — join the incident group
    ///   LeaveSosGroup(sosIncidentId)       — leave the incident group
    ///   JoinOrgGroup(orgId)                — join org group (receive new SOS alerts)
    ///   SendLocation(sosIncidentId, lat, lng) — victim pushes live location
    ///
    /// Server events sent (server → client):
    ///   LocationUpdated   { sosIncidentId, latitude, longitude, timestamp }
    ///   ResponderApproved { sosIncidentId, sosResponderId }
    ///   SosResolved       { sosIncidentId, status }         status: RESOLVED | CANCELLED
    ///   NewResponder      { sosIncidentId }
    ///   NewSosAlert       { sosIncidentId }                  sent to org group
    /// </summary>
    [Authorize]
    public class SosHub : Hub
    {
        /// <summary>Victim and approved responders join this group to receive real-time updates.</summary>
        public async Task JoinSosGroup(int sosIncidentId)
            => await Groups.AddToGroupAsync(Context.ConnectionId, $"sos-{sosIncidentId}");

        /// <summary>Leave incident group (called when screen is exited or SOS ends).</summary>
        public async Task LeaveSosGroup(int sosIncidentId)
            => await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"sos-{sosIncidentId}");

        /// <summary>Org members join this group to receive new SOS alert notifications.</summary>
        public async Task JoinOrgGroup(int orgId)
            => await Groups.AddToGroupAsync(Context.ConnectionId, $"org-{orgId}");

        /// <summary>Leave org group (called on logout or org switch).</summary>
        public async Task LeaveOrgGroup(int orgId)
            => await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"org-{orgId}");

        /// <summary>
        /// Victim broadcasts live GPS to all others in the incident group.
        /// Also saves to DB via POST /sos/{id}/location — do NOT call both; prefer the API endpoint
        /// which also logs to SosLocationLogs. This method is here as a direct push fallback.
        /// </summary>
        public async Task SendLocation(int sosIncidentId, decimal latitude, decimal longitude)
        {
            await Clients.OthersInGroup($"sos-{sosIncidentId}")
                .SendAsync("LocationUpdated", new
                {
                    sosIncidentId,
                    latitude,
                    longitude,
                    timestamp = DateTime.UtcNow
                });
        }
    }
}

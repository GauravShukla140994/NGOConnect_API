using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Sos
{
    /// <summary>
    /// DB column mapping notes:
    ///   SosIncidents.AlertTypeLkpId INT FK (TypeCode='SOS_ALERT_TYPE')
    ///   SosIncidents.StatusLkpId INT FK (TypeCode='SOS_STATUS')
    ///   SosIncidents.OrgId — the NGO the victim belongs to at time of trigger
    ///   SosIncidents.ApproxLocation — reverse-geocoded address string
    /// </summary>
    public class TriggerSosRequest
    {
        [Required]
        [Range(-90, 90)]
        public decimal Latitude  { get; set; }

        [Required]
        [Range(-180, 180)]
        public decimal Longitude { get; set; }

        public string? Description { get; set; }

        /// <summary>LookupValueId from TypeCode='SOS_ALERT_TYPE'
        /// (SOS_ALERT / HELP_REQUEST / MISSING_VOLUNTEER / SAFE_ARRIVAL)</summary>
        [Required(ErrorMessage = "AlertTypeLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid AlertTypeLkpId")]
        public int AlertTypeLkpId { get; set; }

        /// <summary>OrgId the victim belongs to — sent to SP so org members can be notified.</summary>
        public int? OrgId { get; set; }

        /// <summary>Reverse-geocoded address string, e.g. "Whitefield, Bengaluru"</summary>
        public string? ApproxLocation { get; set; }
    }

    public class UpdateLocationRequest
    {
        [Required]
        [Range(-90, 90)]
        public decimal Latitude  { get; set; }

        [Required]
        [Range(-180, 180)]
        public decimal Longitude { get; set; }

        /// <summary>GPS accuracy in metres</summary>
        public decimal? Accuracy { get; set; }
    }

    /// <summary>No request body needed — victim just hits PUT /resolve.
    /// SP derives ResolvedByLkpId internally based on p_StatusCode = 'RESOLVED'.</summary>
    // ResolveSosRequest intentionally removed — use no-body endpoint

    public class CancelSosRequest
    {
        [MaxLength(500)] public string? CancelReason { get; set; }
    }

    public class ApproveResponderRequest
    {
        /// <summary>SosResponders.SosResponderId — renamed from ResponderId to match SP param p_SosResponderId.</summary>
        [Required] public int  SosResponderId   { get; set; }
        public bool            CanViewLocation  { get; set; } = true;
    }

    public class DeclineResponderRequest
    {
        /// <summary>SosResponders.SosResponderId of the responder being declined.</summary>
        [Required] public int SosResponderId { get; set; }
    }
}

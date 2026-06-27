using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Sos
{
    /// <summary>
    /// DB column mapping notes:
    ///   SosIncidents.AlertTypeLkpId INT FK (not SosType VARCHAR)
    ///   SosIncidents.StatusLkpId INT FK (not Status VARCHAR)
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

        /// <summary>LookupValueId from TypeCode='SOS_ALERT_TYPE' (SOS / HELP_REQUEST / MISSING_VOL / SAFE_ARRIVAL)
        /// DB column: AlertTypeLkpId (was SosType string)</summary>
        [Required(ErrorMessage = "AlertTypeLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid AlertTypeLkpId")]
        public int AlertTypeLkpId { get; set; }
    }

    public class UpdateLocationRequest
    {
        [Required]
        [Range(-90, 90)]
        public decimal Latitude  { get; set; }

        [Required]
        [Range(-180, 180)]
        public decimal Longitude { get; set; }

        /// <summary>GPS accuracy in metres (DB column: Accuracy)</summary>
        public decimal? Accuracy { get; set; }
    }

    public class ResolveSosRequest
    {
        /// <summary>LookupValueId from TypeCode='SOS_RESOLUTION_TYPE' (DB column: ResolvedByLkpId)</summary>
        [Required(ErrorMessage = "ResolvedByLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid ResolvedByLkpId")]
        public int ResolvedByLkpId { get; set; }
    }

    /// <summary>Respond to an active SOS — SP takes only p_SosIncidentId + p_UserId, no Note param.</summary>
    public class RespondSosRequest
    {
        // No properties — body is empty; UserId comes from JWT, SosIncidentId from route
    }

    // v4.0 NEW
    public class CancelSosRequest
    {
        [MaxLength(500)] public string? CancelReason { get; set; }
    }

    public class ApproveResponderRequest
    {
        [Required] public int  ResponderId      { get; set; }
        public bool            CanViewLocation  { get; set; } = true;
    }
}

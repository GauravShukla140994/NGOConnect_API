using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Donation
{
    /// <summary>
    /// DB column mapping notes:
    ///   DonationCampaigns.CampaignName  (not Title — Title param maps to CampaignName in SP)
    ///   DonationCampaigns.TargetAmount  (not GoalAmount — GoalAmount param maps to TargetAmount in SP)
    ///   DonationCampaigns.StartDate DATE — required by DB, added to model
    ///   DonationCampaigns.CampaignTypeLkpId INT FK — added to model
    ///   DonationCampaigns.StatusLkpId INT FK (not VARCHAR)
    ///   RecurringDonations.FrequencyLkpId INT FK (not Frequency VARCHAR)
    /// </summary>
    public class CreateCampaignRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int OrgId { get; set; }

        /// <summary>Maps to DB column: CampaignName</summary>
        [Required(ErrorMessage = "Campaign title is required")]
        [MaxLength(200)]
        public string Title { get; set; } = string.Empty;

        public string? Description { get; set; }

        /// <summary>Maps to DB column: TargetAmount</summary>
        [Required]
        [Range(1, double.MaxValue, ErrorMessage = "Goal amount must be greater than 0")]
        public decimal GoalAmount { get; set; }

        /// <summary>Campaign start date (DB column: StartDate DATE)</summary>
        [Required(ErrorMessage = "StartDate is required")]
        public DateTime StartDate { get; set; }

        /// <summary>Campaign end date (optional)</summary>
        public DateTime? EndDate { get; set; }

        [Url, MaxLength(500)]
        public string? BannerUrl { get; set; }

        /// <summary>LookupValueId from TypeCode='CAMPAIGN_TYPE' (GENERAL / PROJECT / EMERGENCY / RECURRING)</summary>
        [Required(ErrorMessage = "CampaignTypeLkpId is required")]
        [Range(1, int.MaxValue)]
        public int CampaignTypeLkpId { get; set; }
    }

    public class InitiateDonationRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int CampaignId { get; set; }

        [Required]
        [Range(1, double.MaxValue, ErrorMessage = "Amount must be greater than 0")]
        public decimal Amount { get; set; }

        public string? Note        { get; set; }
        public bool    IsAnonymous { get; set; } = false;

        /// <summary>LookupValueId from TypeCode='PAYMENT_METHOD' (UPI / CARD / NET_BANKING / WALLET)</summary>
        [Required(ErrorMessage = "PayMethodLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid PayMethodLkpId")]
        public int PayMethodLkpId { get; set; }
    }

    public class VerifyPaymentRequest
    {
        [Required]
        public string RazorpayOrderId   { get; set; } = string.Empty;

        [Required]
        public string RazorpayPaymentId { get; set; } = string.Empty;

        [Required]
        public string RazorpaySignature { get; set; } = string.Empty;

        /// <summary>Readable donation reference e.g. DON-2026-000001 (DB column: DonationId)</summary>
        [Required]
        public string DonationRef { get; set; } = string.Empty;
    }

    public class SetupRecurringRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int OrgId { get; set; }

        [Required]
        [Range(1, int.MaxValue)]
        public int CampaignId { get; set; }

        [Required]
        [Range(1, double.MaxValue)]
        public decimal Amount { get; set; }

        /// <summary>LookupValueId from TypeCode='RECURRING_FREQUENCY' (WEEKLY / MONTHLY / QUARTERLY / YEARLY)</summary>
        [Required(ErrorMessage = "FrequencyLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid FrequencyLkpId")]
        public int FrequencyLkpId { get; set; }

        /// <summary>First billing date (DB column: StartDate DATE)</summary>
        [Required(ErrorMessage = "StartDate is required")]
        public DateTime StartDate { get; set; }
    }

    // v4.0 NEW
    public class ConfirmPaymentRequest
    {
        [Required] public string DonationRef { get; set; } = string.Empty;
    }
}

using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Withdrawal
{
    public class CreateWithdrawalRequest
    {
        [Required][Range(1, int.MaxValue)]
        public int     CampaignId    { get; set; }

        [Required][Range(1, double.MaxValue, ErrorMessage = "Amount must be greater than 0")]
        public decimal Amount        { get; set; }

        [Required][MaxLength(200)]
        public string  BankAccount   { get; set; } = string.Empty;

        [Required][MaxLength(20)]
        public string  IfscCode      { get; set; } = string.Empty;

        [Required][MaxLength(200)]
        public string  AccountHolder { get; set; } = string.Empty;

        [MaxLength(500)] public string? Purpose { get; set; }
    }

    public class AdminReviewWithdrawalRequest
    {
        [Required] public int    WithdrawalId { get; set; }
        [Required][MaxLength(20)] public string StatusCode { get; set; } = string.Empty; // APPROVED / REJECTED
        [MaxLength(500)] public string? AdminNotes { get; set; }
        [Required] public int    ReviewedBy   { get; set; }
    }
}

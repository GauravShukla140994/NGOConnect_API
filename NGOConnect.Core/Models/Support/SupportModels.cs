using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Support
{
    /// <summary>
    /// Request body for POST /api/v1/support/contact
    /// </summary>
    public class SupportContactRequest
    {
        /// <summary>
        /// Category code — one of: GENERAL_QUERY, DONATION_SUPPORT,
        ///   ORG_APPROVAL, BUG_REPORT, FEEDBACK
        /// </summary>
        [Required]
        [MaxLength(50)]
        public string CategoryCode { get; set; } = string.Empty;

        /// <summary>Human-readable category label (sent in email for readability).</summary>
        [Required]
        [MaxLength(100)]
        public string CategoryLabel { get; set; } = string.Empty;

        [Required]
        [MaxLength(255)]
        public string Subject { get; set; } = string.Empty;

        [Required]
        [MaxLength(2000)]
        public string Description { get; set; } = string.Empty;

        /// <summary>
        /// User's contact email — pre-filled from profile but editable.
        /// This is the Reply-To address for the support team's reply.
        /// </summary>
        [Required]
        [EmailAddress]
        [MaxLength(150)]
        public string ContactEmail { get; set; } = string.Empty;

        [Required]
        [MaxLength(100)]
        public string ContactName { get; set; } = string.Empty;

        /// <summary>
        /// Optional public URL of an uploaded attachment (PDF, image, or video ≤ 5 MB).
        /// Uploaded by the mobile app to /api/v1/media/upload?module=support-attachments
        /// before submitting this request; included as a clickable link in the support email.
        /// </summary>
        [MaxLength(2048)]
        public string? AttachmentUrl { get; set; }
    }
}

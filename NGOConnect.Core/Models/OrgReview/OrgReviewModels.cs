using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.OrgReview
{
    /// <summary>
    /// Request body for POST /orgs/{orgId}/reviews
    /// </summary>
    public class AddReviewRequest
    {
        [Required]
        [Range(1, 5, ErrorMessage = "Rating must be between 1 and 5.")]
        public int OverallRating { get; set; }

        [Required]
        [MinLength(10, ErrorMessage = "Review must be at least 10 characters (excluding spaces).")]
        [MaxLength(500, ErrorMessage = "Review cannot exceed 500 characters.")]
        public string ReviewText { get; set; } = string.Empty;

        /// <summary>VOLUNTEER | DONOR | GENERAL — matched to REVIEWER_TYPE LookupType.</summary>
        public string ReviewerType { get; set; } = "VOLUNTEER";

        /// <summary>
        /// Optional media items already uploaded to blob storage.
        /// Each item carries the public URL and its type code (IMAGE | VIDEO).
        /// Max 5 images or 1 video, enforced at controller level.
        /// </summary>
        public List<ReviewMediaItem> MediaItems { get; set; } = [];
    }

    public class ReviewMediaItem
    {
        [Required]
        [MaxLength(500)]
        public string Url { get; set; } = string.Empty;

        /// <summary>IMAGE | VIDEO</summary>
        [Required]
        public string Type { get; set; } = "IMAGE";
    }

    /// <summary>
    /// Request body for POST /orgs/{orgId}/reviews/{reviewId}/helpful
    /// </summary>
    public class MarkHelpfulRequest
    {
        /// <summary>true = 👍 helpful, false = 👎 not helpful. Toggled if same value sent again.</summary>
        [Required]
        public bool IsHelpful { get; set; }
    }

    /// <summary>
    /// Request body for POST /orgs/{orgId}/reviews/{reviewId}/response
    /// </summary>
    public class AddReviewResponseRequest
    {
        [Required]
        [MinLength(10, ErrorMessage = "Response must be at least 10 characters.")]
        [MaxLength(1000, ErrorMessage = "Response cannot exceed 1000 characters.")]
        public string ResponseText { get; set; } = string.Empty;
    }
}

using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Post
{
    /// <summary>
    /// DB column mapping notes:
    ///   Posts.PostTypeLkpId INT FK (not PostType VARCHAR)
    ///   Posts.VisibilityLkpId INT FK
    ///   PostReports.ReasonLkpId INT FK (not Reason VARCHAR)
    /// </summary>
    public class CreatePostRequest
    {
        [Required(ErrorMessage = "Content is required")]
        public string  Content   { get; set; } = string.Empty;

        public int?    OrgId     { get; set; }

        /// <summary>
        /// One or more media URLs. Stored as comma-separated string in DB (Posts.MediaUrls).
        /// Accepts a JSON array from the client — DAL joins to CSV before passing to SP.
        /// Supports up to 5 URLs (Instagram-style carousel).
        /// </summary>
        public List<string>? MediaUrls { get; set; }

        /// <summary>LookupValueId from TypeCode='POST_TYPE_FEED' (DB column: PostTypeLkpId)</summary>
        public int? PostTypeLkpId { get; set; }  // was PostType string

        /// <summary>LookupValueId from TypeCode='POST_VISIBILITY'. Defaults to PUBLIC if null.</summary>
        public int? VisibilityLkpId { get; set; }
    }

    public class AddCommentRequest
    {
        [Required(ErrorMessage = "Content is required")]
        public string Content          { get; set; } = string.Empty;

        public int?   ParentCommentId  { get; set; }
    }

    public class ReportPostRequest
    {
        /// <summary>ValueCode from LookupType REPORT_REASON: SPAM | HATE | INAPPROPRIATE | SCAM | OTHER</summary>
        [Required(ErrorMessage = "ReasonCode is required")]
        public string ReasonCode { get; set; } = string.Empty;

        public string? Details { get; set; }
    }
}

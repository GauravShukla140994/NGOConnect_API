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

        /// <summary>Comma-separated Azure Blob URLs for media attachments</summary>
        public string? MediaUrls { get; set; }

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
        /// <summary>LookupValueId from TypeCode='REPORT_REASON' (DB column: ReasonLkpId)</summary>
        [Required(ErrorMessage = "ReasonLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid ReasonLkpId")]
        public int ReasonLkpId { get; set; }  // was Reason string

        public string? Details { get; set; }
    }
}

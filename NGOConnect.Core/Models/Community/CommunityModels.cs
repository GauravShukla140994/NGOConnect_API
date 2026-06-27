using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Community
{
    /// <summary>
    /// DB column mapping notes:
    ///   CommunityPosts.Title VARCHAR(300) NOT NULL — required field
    ///   CommunityPosts.PostTypeLkpId INT FK (TypeCode='POST_TYPE_COMMUNITY')
    ///   CommunityPosts.AudienceLkpId INT FK (TypeCode='POST_VISIBILITY')
    ///   CommunityPosts.OrgId NOT NULL (required, not optional)
    ///   No Tags column in DB — removed
    ///   For POLL type: PollEndsAt DATETIME computed from ExpiresInHours
    ///   PollOptions in separate table, linked by CommunityPostId
    /// </summary>
    public class CreateCommunityPostRequest
    {
        [Required(ErrorMessage = "OrgId is required")]
        [Range(1, int.MaxValue)]
        public int OrgId { get; set; }   // NOT NULL in DB — was optional

        /// <summary>Brief title for the community post (DB column: Title, NOT NULL)</summary>
        [Required(ErrorMessage = "Title is required")]
        [MaxLength(300)]
        public string Title { get; set; } = string.Empty;

        public string? Content { get; set; }

        /// <summary>LookupValueId from TypeCode='POST_TYPE_COMMUNITY' (DISCUSSION / QUESTION / ANNOUNCEMENT / RESOURCE etc.)</summary>
        [Required(ErrorMessage = "PostTypeLkpId is required")]
        [Range(1, int.MaxValue)]
        public int PostTypeLkpId { get; set; }

        /// <summary>LookupValueId from TypeCode='POST_VISIBILITY'. Defaults to ORG_MEMBERS.</summary>
        public int? AudienceLkpId { get; set; }
    }

    public class CreatePollRequest
    {
        [Required(ErrorMessage = "OrgId is required")]
        [Range(1, int.MaxValue)]
        public int OrgId { get; set; }

        /// <summary>Poll question — stored as CommunityPosts.Title</summary>
        [Required(ErrorMessage = "Question is required")]
        [MaxLength(300)]
        public string Question { get; set; } = string.Empty;

        /// <summary>Poll answer options — stored as PollOptions rows</summary>
        [Required]
        [MinLength(2, ErrorMessage = "A poll must have at least 2 options")]
        public List<string> Options { get; set; } = new();

        /// <summary>How long before the poll expires (stored as PollEndsAt = NOW() + ExpiresInHours)</summary>
        [Range(1, 8760, ErrorMessage = "ExpiresInHours must be between 1 and 8760 (1 year)")]
        public int ExpiresInHours { get; set; } = 24;
    }

    public class VoteRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int PollOptionId { get; set; }
    }
}

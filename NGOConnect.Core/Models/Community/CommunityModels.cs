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

        /// <summary>LookupValueId from TypeCode='AUDIENCE_TYPE' (ALL_MEMBERS / ADMINS_ONLY / VOLUNTEERS). Defaults to ALL_MEMBERS.</summary>
        public int? AudienceLkpId { get; set; }

        /// <summary>Azure Blob URL of the uploaded file. Only used for RESOURCE post type.</summary>
        public string? ResourceFileUrl { get; set; }

        /// <summary>Whether this post is pinned. Only honoured for ANNOUNCEMENT type.</summary>
        public bool? IsPinned { get; set; }

        /// <summary>Number of volunteers needed. Only used for VOL_REQUEST type.</summary>
        public int? VolunteersNeeded { get; set; }

        /// <summary>
        /// Multipurpose extra text stored in the EventRef column — interpretation varies by type:
        ///   EVENT_UPDATE  → what changed (e.g. "Venue changed")
        ///   VOL_REQUEST   → event date/time display text (e.g. "Jun 14, 6:30 AM")
        ///   TASK          → free-text assignee name (no DB user lookup at this stage)
        /// </summary>
        public string? EventRef { get; set; }
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

        /// <summary>When true, voters may select multiple options. Stored as CommunityPosts.PollIsMultiChoice.</summary>
        public bool IsMultiChoice { get; set; } = false;

        /// <summary>LookupValueId from TypeCode='AUDIENCE_TYPE' (ALL_MEMBERS / ADMINS_ONLY / VOLUNTEERS). Defaults to ALL_MEMBERS if not provided.</summary>
        public int? AudienceLkpId { get; set; }
    }

    public class VoteRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int PollOptionId { get; set; }
    }

    public class AddCommentRequest
    {
        [Required(ErrorMessage = "Content is required")]
        [MaxLength(2000)]
        public string Content { get; set; } = string.Empty;
    }
}

using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Application
{
    /// <summary>
    /// DB column mapping notes:
    ///   Motivation — SP takes p_Motivation, inserts into Motivation column
    ///   RequestedSessions — SP takes p_RequestedSessions (comma-separated day codes e.g. "TUE,FRI")
    ///   StatusLkpId INT FK (not Status VARCHAR) — RejectionReason (not Note for reviews)
    /// </summary>
    public class ApplicationModel
    {
        public int      ApplicationId { get; set; }
        public int      ProjectId     { get; set; }
        public string   ProjectName   { get; set; } = string.Empty;  // DB: ProjectName (not Title)
        public int      UserId        { get; set; }
        public string   FullName      { get; set; } = string.Empty;
        public string   Status        { get; set; } = string.Empty;  // from LookupValues join
        public string?  Motivation    { get; set; }                  // DB column: Motivation
        public DateTime AppliedAt     { get; set; }
        public DateTime? ReviewedAt   { get; set; }
    }

    public class ApplyRequest
    {
        /// <summary>Volunteer's reason for applying. Maps to DB column: Motivation</summary>
        public string? Motivation { get; set; }

        /// <summary>
        /// For RECURRING projects: comma-separated day codes the volunteer wants to attend.
        /// E.g. "TUE", "FRI", or "TUE,FRI" for both days.
        /// Maps to DB column: RequestedSessions
        /// </summary>
        public string? RequestedSessions { get; set; }
    }

    public class ReviewApplicationRequest
    {
        /// <summary>LookupValueId from TypeCode='APPLICATION_STATUS' (APPROVED / REJECTED)</summary>
        [Required(ErrorMessage = "StatusLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid StatusLkpId")]
        public int StatusLkpId { get; set; }   // was Status string

        /// <summary>Maps to DB column: RejectionReason</summary>
        public string? Note { get; set; }
    }
}

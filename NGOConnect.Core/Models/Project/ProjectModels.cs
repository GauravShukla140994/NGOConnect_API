using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Project
{
    // ── Create/Update Project (v4.0 — all 17 schedule/location params) ──────────
    public class CreateProjectRequest
    {
        [Required][MaxLength(200)] public string  Title             { get; set; } = string.Empty;
        [MaxLength(2000)]          public string? Description       { get; set; }
        [Required]                 public int     OrgId             { get; set; }
        public int?     ProjectTypeLkpId   { get; set; }
        public int?     JoinTypeLkpId      { get; set; }
        public int?     StatusLkpId        { get; set; }
        public int?     MaxVolunteers      { get; set; }
        public int?     MinAge             { get; set; }
        public int?     MaxAge             { get; set; }
        public bool?    IsPublic           { get; set; }
        // Schedule
        public DateTime? StartDate         { get; set; }
        public DateTime? EndDate           { get; set; }
        [MaxLength(20)] public string? ScheduleType  { get; set; }
        [MaxLength(100)]public string? RecurrenceDays { get; set; }
        [MaxLength(10)] public string? StartTime     { get; set; }
        [MaxLength(10)] public string? EndTime       { get; set; }
        public int?     DurationMinutes    { get; set; }
        // Location
        public int?     LocationTypeLkpId  { get; set; }
        [MaxLength(200)]public string? LocationName  { get; set; }
        [MaxLength(500)]public string? Address       { get; set; }
        public decimal? Latitude           { get; set; }
        public decimal? Longitude          { get; set; }
        [MaxLength(500)]public string? GoogleMapsUrl { get; set; }
        // Restrictions
        // Category stored as string in DB
        [MaxLength(100)]public string? Category         { get; set; }
        // Location type code resolved to LkpId inside the SP (IN_PERSON | REMOTE | HYBRID)
        [MaxLength(20)] public string? LocationTypeCode { get; set; }
        // Restrictions
        [MaxLength(20)] public string? GenderRestriction { get; set; }
        public bool?    RequiresApproval   { get; set; }
        [MaxLength(255)]public string? CoverImageUrl  { get; set; }
        [MaxLength(100)]public string? City           { get; set; }
        [MaxLength(100)]public string? State          { get; set; }
        // Status: true = save as DRAFT, false/null = UPCOMING
        public bool?    IsDraft            { get; set; }
    }

    public class UpdateProjectRequest : CreateProjectRequest { }

    // ── Add Project Skill (v4.0) ────────────────────────────────────────────────
    public class AddProjectSkillRequest
    {
        [Required][MaxLength(100)] public string SkillName   { get; set; } = string.Empty;
        public bool IsRequired { get; set; } = false;
    }

    // ── Session ─────────────────────────────────────────────────────────────────
    public class CreateSessionRequest
    {
        [Required] public DateTime SessionDate { get; set; }
        [Required][RegularExpression(@"^([01]\d|2[0-3]):([0-5]\d)$")]
        public string StartTime { get; set; } = string.Empty;
        [Required][RegularExpression(@"^([01]\d|2[0-3]):([0-5]\d)$")]
        public string EndTime   { get; set; } = string.Empty;
        public int? MaxVolunteers { get; set; }
    }

    // ── Check-In ────────────────────────────────────────────────────────────────
    public class CheckInRequest
    {
        [Required] public string QrToken { get; set; } = string.Empty;
    }

    // ── Complete Project (v4.0) ──────────────────────────────────────────────────
    public class CompleteProjectRequest
    {
        [MaxLength(1000)] public string? CompletionNotes  { get; set; }   // maps to SP p_ImpactSummary
        public int? BeneficiaryCount { get; set; }
    }

    // ── Cancel Project ────────────────────────────────────────────────────────────
    public class CancelProjectRequest
    {
        [MaxLength(500)] public string? CancelReason { get; set; }
    }

    // ── Manual Attendance (admin override) ────────────────────────────────────────
    public class ManualAttendanceRequest
    {
        public int ApplicationId { get; set; }
    }

    // ── Review Application (v4.0) ───────────────────────────────────────────────
    public class ReviewApplicationRequest
    {
        public int     ApplicationId { get; set; }
        [Required][MaxLength(20)] public string StatusCode { get; set; } = string.Empty; // APPROVED / REJECTED
        [MaxLength(500)] public string? AdminNotes { get; set; }
    }

    // ── Typed Model ─────────────────────────────────────────────────────────────
    public class ProjectModel
    {
        public int       ProjectId        { get; set; }
        public int       OrgId            { get; set; }
        public string    OrgName          { get; set; } = string.Empty;
        public string    Title            { get; set; } = string.Empty;
        public string?   Description      { get; set; }
        public string?   ProjectTypeCode  { get; set; }
        public string?   StatusCode       { get; set; }
        public int?      MaxVolunteers    { get; set; }
        public DateTime? StartDate        { get; set; }
        public DateTime? EndDate          { get; set; }
        public string?   City             { get; set; }
        public string?   State            { get; set; }
        public int       AppliedCount     { get; set; }
        public DateTime  CreatedAt        { get; set; }
    }
}

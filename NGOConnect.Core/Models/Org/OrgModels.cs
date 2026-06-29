using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Org
{
    // ── Register Org (v4.1) ─────────────────────────────────────────────────────
    public class RegisterOrgRequest
    {
        [Required][MaxLength(200)] public string  OrgName            { get; set; } = string.Empty;
        [Required][MaxLength(100)] public string  RegistrationNumber { get; set; } = string.Empty;
        [Required]                 public int     OrgTypeLkpId       { get; set; }
        // Category: free-text tag shown on NGO card (e.g. "Education", "Environment")
        // Pass the ValueName from LookupType ORG_CATEGORY (stored as-is in DB)
        [MaxLength(100)]           public string? Category           { get; set; }
        // Contact person shown on public NGO profile (Step 2 of create wizard)
        [MaxLength(100)]           public string? ContactPerson      { get; set; }
        [MaxLength(500)]           public string? About              { get; set; }
        [MaxLength(500)]           public string? Mission            { get; set; }
        [MaxLength(500)]           public string? Vision             { get; set; }
        [MaxLength(255)]           public string? LogoUrl            { get; set; }
        [MaxLength(20)]            public string? Phone              { get; set; }
        [MaxLength(150)]           public string? Email              { get; set; }
        [MaxLength(255)]           public string? Website            { get; set; }
        [MaxLength(255)]           public string? AddressLine1       { get; set; }
        [MaxLength(255)]           public string? AddressLine2       { get; set; }
        [MaxLength(20)]            public string? Pincode            { get; set; }
        [MaxLength(100)]           public string? City               { get; set; }
        [MaxLength(100)]           public string? State              { get; set; }
        [MaxLength(100)]           public string? Country            { get; set; }
    }

    // ── Update Org (v4.1) ───────────────────────────────────────────────────────
    public class UpdateOrgRequest
    {
        [MaxLength(200)] public string? OrgName       { get; set; }
        [MaxLength(100)] public string? Category      { get; set; }
        [MaxLength(100)] public string? ContactPerson { get; set; }
        [MaxLength(500)] public string? About         { get; set; }
        [MaxLength(500)] public string? Mission       { get; set; }
        [MaxLength(500)] public string? Vision        { get; set; }
        [MaxLength(255)] public string? LogoUrl       { get; set; }
        [MaxLength(20)]  public string? Phone         { get; set; }
        [MaxLength(150)] public string? Email         { get; set; }
        [MaxLength(255)] public string? Website       { get; set; }
        [MaxLength(255)] public string? AddressLine1  { get; set; }
        [MaxLength(255)] public string? AddressLine2  { get; set; }
        [MaxLength(20)]  public string? Pincode       { get; set; }
        [MaxLength(100)] public string? City          { get; set; }
        [MaxLength(100)] public string? State         { get; set; }
        [MaxLength(100)] public string? Country       { get; set; }
    }

    // ── Admin Dashboard KPIs (s-admin screen) ──────────────────────────────────
    public class OrgDashboardModel
    {
        public int     TotalMembers        { get; set; }   // All APPROVED members
        public int     NewMembersThisMonth { get; set; }   // Joined in current calendar month
        public int     ActiveVolunteers    { get; set; }   // Attended ≥1 project this month
        public decimal ActiveRatePct       { get; set; }   // ActiveVolunteers / TotalMembers * 100
        public decimal VolunteerHoursMonth { get; set; }   // SUM of session hours attended this month
        public int     ActiveProjects      { get; set; }   // Projects with ACTIVE status
        public int     PendingApplications { get; set; }   // Membership requests awaiting review
    }

    // ── Add Member ──────────────────────────────────────────────────────────────
    public class AddMemberRequest
    {
        [Required] public int UserId   { get; set; }
        [Required] public int RoleLkpId { get; set; }
    }

    // ── Request Membership (v4.0) ───────────────────────────────────────────────
    public class RequestMembershipRequest
    {
        [MaxLength(500)] public string? Message { get; set; }
    }

    // ── Review Membership (v4.0) ────────────────────────────────────────────────
    public class ReviewMembershipRequest
    {
        [Required] public int    RequestId  { get; set; }
        [Required] public string StatusCode { get; set; } = string.Empty; // APPROVED / REJECTED
        [MaxLength(500)] public string? AdminNotes { get; set; }
    }

    // ── Update Member Permissions (v4.0) ────────────────────────────────────────
    public class UpdateMemberPermissionsRequest
    {
        [Required] public int  MemberId              { get; set; }
        public bool? CanPost                 { get; set; }
        public bool? CanComment              { get; set; }
        public bool? CanCommunityPost        { get; set; }
        public int?  MaxPostsPerDay          { get; set; }
        public int?  LocationSharingLkpId    { get; set; }
    }

    // ── Upload Org Document (v4.1) ──────────────────────────────────────────────
    // Frontend flow:
    //   1. POST /media/upload?module=org-documents → get { fileUrl, fileName, fileSizeKb }
    //   2. POST /org/{orgId}/documents with those values + documentTypeLkpId
    public class UploadOrgDocumentRequest
    {
        [Required] public int    DocumentTypeLkpId { get; set; }   // LookupType: DOCUMENT_TYPE
        [Required] public string FileUrl           { get; set; } = string.Empty;   // from /media/upload
        [Required] public string FileName          { get; set; } = string.Empty;   // from /media/upload
    }
}

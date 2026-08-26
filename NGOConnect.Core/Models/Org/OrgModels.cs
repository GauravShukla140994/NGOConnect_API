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
        [MaxLength(20)]            public string? ContactPhone       { get; set; }
        [MaxLength(150)]           public string? ContactEmail       { get; set; }
        [MaxLength(255)]           public string? Website            { get; set; }
        [MaxLength(255)]           public string? AddressLine1       { get; set; }
        [MaxLength(255)]           public string? AddressLine2       { get; set; }
        [MaxLength(20)]            public string? Pincode            { get; set; }
        [MaxLength(100)]           public string? City               { get; set; }
        [MaxLength(100)]           public string? State              { get; set; }
        [MaxLength(100)]           public string? Country            { get; set; }
        // Tax exemption flags — stored in Organisations.Is80GEligible / Is12AEligible
        public bool Is80GEligible     { get; set; } = false;
        public bool Is12AEligible     { get; set; } = false;
        // Non-registered flag — true when org has no govt registration number
        public bool IsNonRegistered   { get; set; } = false;
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
        [MaxLength(20)]  public string? ContactPhone   { get; set; }
        [MaxLength(150)] public string? ContactEmail   { get; set; }
        [MaxLength(255)] public string? Website       { get; set; }
        [MaxLength(255)] public string? AddressLine1  { get; set; }
        [MaxLength(255)] public string? AddressLine2  { get; set; }
        [MaxLength(20)]  public string? Pincode       { get; set; }
        [MaxLength(100)] public string? City          { get; set; }
        [MaxLength(100)] public string? State         { get; set; }
        [MaxLength(100)] public string? Country       { get; set; }
        // Tax exemption flags — stored in Organisations.Is80GEligible / Is12AEligible.
        // Nullable so an update that doesn't touch these leaves the existing value alone
        // (Org_Update uses COALESCE against p_Is80GEligible/p_Is12AEligible).
        public bool? Is80GEligible { get; set; }
        public bool? Is12AEligible { get; set; }
    }

    // ── Resubmit Org after rejection (v4.5) — founder-side, new SP Org_Resubmit ──
    public class ResubmitOrgRequest
    {
        [Required][MaxLength(200)] public string  OrgName       { get; set; } = string.Empty;
        [MaxLength(100)]            public string? Category      { get; set; }
        [MaxLength(100)]            public string? ContactPerson { get; set; }
        [MaxLength(500)]            public string? About         { get; set; }
        [MaxLength(500)]            public string? Mission       { get; set; }
        [MaxLength(500)]            public string? Vision        { get; set; }
        [MaxLength(255)]            public string? LogoUrl       { get; set; }
        [MaxLength(20)]             public string? ContactPhone   { get; set; }
        [MaxLength(150)]            public string? ContactEmail   { get; set; }
        [MaxLength(255)]            public string? Website       { get; set; }
        [MaxLength(255)]            public string? AddressLine1  { get; set; }
        [MaxLength(255)]            public string? AddressLine2  { get; set; }
        [MaxLength(20)]             public string? Pincode       { get; set; }
        [MaxLength(100)]            public string? City          { get; set; }
        [MaxLength(100)]            public string? State         { get; set; }
        [MaxLength(100)]            public string? Country       { get; set; }
        // Registration — founder can correct non-registered status during resubmission
        [MaxLength(100)]            public string? RegistrationNumber { get; set; }
        public bool IsNonRegistered { get; set; } = false;
        // Tax exemption flags — resubmission is a full re-declaration, so these are
        // included so the founder can correct them alongside a rejection.
        public bool Is80GEligible { get; set; } = false;
        public bool Is12AEligible { get; set; } = false;
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
        public int     PendingApplications        { get; set; }   // Membership requests awaiting review
        public int     PendingProjectApplications { get; set; }   // Volunteer project applications awaiting review
        public int     FollowerCount              { get; set; }   // Denormalized from Organisations.FollowerCount
    }

    // ── Add Member ──────────────────────────────────────────────────────────────
    public class AddMemberRequest
    {
        [Required] public int    UserId   { get; set; }
        /// <summary>ValueCode from LookupType MEMBER_ROLE — e.g. MEMBER, COORDINATOR, ADMIN</summary>
        [Required][MaxLength(50)] public string RoleCode { get; set; } = "MEMBER";
        [Obsolete("Use RoleCode (string ValueCode). RoleLkpId is no longer passed to Org_AddMember SP.")]
        public int? RoleLkpId { get; set; }
    }

    // ── Request Membership (v4.0) ───────────────────────────────────────────────
    public class RequestMembershipRequest
    {
        public string? PrevNgoExperience { get; set; }  // p_PrevNgoExperience
        public string? VolunteerSkills   { get; set; }  // p_VolunteerSkills (comma-separated)
        public string? AreasOfInterest   { get; set; }  // p_AreasOfInterest
        public string? WhyJoin           { get; set; }  // p_WhyJoin
    }

    // ── Review Membership (v4.0) ────────────────────────────────────────────────
    public class ReviewMembershipRequest
    {
        [Required] public int    MembershipRequestId { get; set; }
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
        public bool? LocationSharing         { get; set; }
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

    // ── Award Badge to volunteer (s-vol-profile, s-participants screens) ─────────
    public class AwardBadgeRequest
    {
        [Required] public int    UserId    { get; set; }
        [Required] public string BadgeCode { get; set; } = string.Empty;  // LookupType: BADGE_TYPE ValueCode e.g. STAR_VOL
        public int? ProjectId             { get; set; }   // project it was earned on (optional)
        public int? SessionId             { get; set; }   // v5.1: session context for RECURRING/FLEXIBLE (accepted by SP, not stored in UserBadges)
    }

    // ── Update member role (s-admin-vols screen) ─────────────────────────────────
    public class UpdateMemberRoleRequest
    {
        [Required] public int    MemberId { get; set; }
        [Required] public string RoleCode { get; set; } = "MEMBER";  // ValueCode from MEMBER_ROLE — SP resolves to LkpId internally
    }

    // ── Mark attendance no-show as excused (s-participants screen) ───────────────
    public class ExcuseNoShowRequest
    {
        [Required] public int AttendanceId { get; set; }
    }

    // ── Org List / Search result (s-explore All NGOs tab + s-my-orgs) ────────────
    // AvgRating and Latitude/Longitude added to Organisations table in Patch Section 7
    public class OrgListItemModel
    {
        public int      OrgId       { get; set; }
        public string   OrgName     { get; set; } = string.Empty;
        public string?  Category     { get; set; }
        public string?  CategoryName { get; set; }   // resolved ValueName from LookupValues
        public string?  LogoUrl      { get; set; }
        public string?  City        { get; set; }
        public string?  State       { get; set; }
        public int      MemberCount      { get; set; }
        public decimal  AvgRating        { get; set; }   // 0.00–5.00
        public decimal? Latitude         { get; set; }   // for client-side distance calc
        public decimal? Longitude        { get; set; }
        public bool     IsNonRegistered  { get; set; }   // true = no govt reg number
    }

    // ── Recommended org (s-explore Recommended tab) ───────────────────────────────
    public class RecommendedOrgModel : OrgListItemModel
    {
        public int     MatchScore             { get; set; }   // matching user interest count
        public string? VerificationStatusCode { get; set; }   // e.g. VERIFIED, PENDING, REJECTED
    }

    // ── Trending campaign (s-explore Trending tab) ───────────────────────────────
    public class TrendingCampaignModel
    {
        public int      CampaignId    { get; set; }
        public string   CampaignName  { get; set; } = string.Empty;
        public string   OrgName       { get; set; } = string.Empty;
        public string?  OrgLogoUrl    { get; set; }
        public decimal  RaisedAmount  { get; set; }
        public decimal  TargetAmount  { get; set; }
        public int      DonorCount    { get; set; }
        public decimal  ProgressPct   { get; set; }   // RaisedAmount/TargetAmount * 100
        public DateTime? EndDate      { get; set; }
        public string?  BannerUrl     { get; set; }
        public bool     IsEmergency   { get; set; }
    }

    // ── Admin Donation Dashboard (s-admin-donations screen) ──────────────────────
    public class OrgDonationDashboardModel
    {
        public decimal TotalRaisedAllTime      { get; set; }
        public decimal ThisMonthRaised         { get; set; }
        public decimal LastMonthRaised         { get; set; }   // for % change calculation
        public decimal TodayRaised             { get; set; }
        public int     TodayTransactionCount   { get; set; }
        public decimal RecurringMonthlyAmount  { get; set; }   // sum of active recurring donations
        public int     ActiveRecurringDonors   { get; set; }
        public int     TotalCampaigns          { get; set; }
        public int     ActiveCampaigns         { get; set; }
    }

    // ── Admin Donor list item (s-admin-donors screen) ────────────────────────────
    public class OrgDonorModel
    {
        public int      UserId         { get; set; }
        public string?  FullName       { get; set; }   // null if anonymous
        public string?  Email          { get; set; }
        public string?  Phone          { get; set; }
        public decimal  TotalDonated   { get; set; }
        public int      DonationCount  { get; set; }
        public DateTime LastDonatedAt  { get; set; }
        public bool     IsAnonymous    { get; set; }
        public bool     IsRecurring    { get; set; }   // has active recurring donation
    }

    // ── Admin Transaction list item (s-admin-transactions screen) ────────────────
    public class OrgTransactionModel
    {
        public int      TransactionId     { get; set; }
        public string   ReadableId        { get; set; } = string.Empty;   // DON-2026-000147
        public string?  DonorName         { get; set; }   // null if anonymous
        public decimal  Amount            { get; set; }
        public decimal  NetAmount         { get; set; }   // after platform fee
        public string?  CampaignName      { get; set; }   // null if general donation
        public string   StatusCode        { get; set; } = string.Empty;
        public string   StatusName        { get; set; } = string.Empty;
        public string?  PaymentMethod     { get; set; }
        public DateTime CreatedAt         { get; set; }
        public bool     IsAnonymous       { get; set; }
    }

    // ── Admin Volunteer Profile (s-vol-profile screen — admin view) ───────────────
    public class OrgVolunteerProfileModel
    {
        // Basic info
        public int      UserId          { get; set; }
        public string?  FullName        { get; set; }
        public string?  City            { get; set; }
        public string?  State           { get; set; }
        public string?  Occupation      { get; set; }
        public string?  ProfilePhoto    { get; set; }
        public string?  Bio             { get; set; }   // about text from UserProfiles
        public string?  VolunteerExp    { get; set; }   // volunteer experience text
        // Public impact stats
        public decimal  TotalHours      { get; set; }
        public int      ProjectCount    { get; set; }
        public int      OrgCount        { get; set; }
        // Reliability (admin-only, never shown publicly)
        public decimal  ReliabilityPct  { get; set; }
        public decimal  AvgRating       { get; set; }   // admin's rating of this volunteer
        public decimal  PeerRating      { get; set; }   // peer-rated avg across skills
        public int      NoShowCount     { get; set; }
        public int      ExcusedCount    { get; set; }
        public int      ComplaintCount  { get; set; }
        // Membership in THIS org
        public string?  RoleCode        { get; set; }
        public string?  RoleName        { get; set; }
        public string?  StatusCode      { get; set; }
        public string?  StatusName      { get; set; }
        public DateTime? JoinedAt       { get; set; }
        // Membership request (what the volunteer submitted when applying)
        public string?   PrevNgoExperience { get; set; }
        public string?   VolunteerSkills   { get; set; }
        public string?   AreasOfInterest   { get; set; }
        public string?   WhyJoin           { get; set; }
        public DateTime? RequestedAt       { get; set; }
        // Badges — comma-separated BADGE_TYPE ValueCodes awarded to this volunteer
        public string?   AwardedBadgeCodes { get; set; }
    }

    // ── Admin Posts requests ─────────────────────────────────────────────────────
    public class ModeratePostRequest
    {
        /// <summary>KEEP (clear reports) or REMOVE (delete post + clear reports)</summary>
        public string Action { get; set; } = "KEEP";
    }

    // ── Admin Member Impact (s-member-impact screen — admin view) ────────────────
    public class OrgMemberImpactModel
    {
        public int      UserId          { get; set; }
        public string?  FullName        { get; set; }
        public string?  Occupation      { get; set; }
        public string?  City            { get; set; }
        public string?  RoleName        { get; set; }   // role in THIS org
        public int      ImpactScore     { get; set; }
        public decimal  ReliabilityPct  { get; set; }   // admin-only
        public decimal  TotalHours      { get; set; }
        public int      ProjectCount    { get; set; }
        public int      OrgCount        { get; set; }
        public int      BadgeCount      { get; set; }
        public int      NoShowCount     { get; set; }
        public int      ComplaintCount  { get; set; }
    }
}

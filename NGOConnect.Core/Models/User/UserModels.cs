using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.User
{
    // ── Get Own Profile ─────────────────────────────────────────────────────────
    public class UserProfileModel
    {
        public int       UserId             { get; set; }
        public string?   Mobile             { get; set; }
        public string?   Email              { get; set; }
        public string    CountryCode        { get; set; } = "+91";
        public bool      IsVerified         { get; set; }
        public string?   FirstName          { get; set; }
        public string?   LastName           { get; set; }
        public string?   Bio                { get; set; }
        public int?      GenderLkpId        { get; set; }   // LkpId — for dropdown pre-selection
        public string?   Gender             { get; set; }   // ValueName  e.g. "Male"
        public string?   GenderCode         { get; set; }   // ValueCode  e.g. "MALE"
        public DateTime? DateOfBirth        { get; set; }
        public string?   ProfilePhoto       { get; set; }
        public string?   Occupation         { get; set; }
        public string?   Organisation       { get; set; }
        public string?   VolunteerExp       { get; set; }   // Previous NGO/volunteer experience
        // Education
        public int?      EducationLkpId     { get; set; }   // LkpId — for dropdown pre-selection
        public string?   Education          { get; set; }   // ValueName  e.g. "Bachelor's Degree"
        public string?   EducationCode      { get; set; }   // ValueCode  e.g. "BACHELOR"
        public string?   FieldOfStudy       { get; set; }
        // Work Experience
        public int?      WorkExpLkpId       { get; set; }   // LkpId — for dropdown pre-selection
        public string?   WorkExperience     { get; set; }   // ValueName  e.g. "3–5 years"
        public string?   WorkExpCode        { get; set; }   // ValueCode  e.g. "EXP_3_5"
        // Address
        public string?   AddressLine1       { get; set; }
        public string?   AddressLine2       { get; set; }
        public string?   Pincode            { get; set; }
        public string?   City               { get; set; }
        public string?   State              { get; set; }
        public string?   Country            { get; set; }
        public int       ImpactScore        { get; set; }
        public decimal   ReliabilityPct     { get; set; }
        public DateTime  MemberSince        { get; set; }   // u.CreatedAt aliased in SP
        public DateTime? UpdatedAt          { get; set; }
        public bool      IsProfileComplete  { get; set; }
        // ── Impact stats (v4.9 — same logic as User_GetImpact) ───────────────
        public decimal   TotalHours         { get; set; }
        public int       ProjectsCount      { get; set; }
        public int       NgosJoined         { get; set; }
    }

    // ── Update Profile Request (v4.0 — 18 params) ───────────────────────────────
    public class UpdateProfileRequest
    {
        [MaxLength(80)]   public string?   FirstName    { get; set; }
        [MaxLength(80)]   public string?   LastName     { get; set; }
        [MaxLength(1000)] public string?   Bio          { get; set; }
        public int?       GenderLkpId                   { get; set; }
        public DateTime?  DateOfBirth                   { get; set; }
        [MaxLength(255)]  public string?   ProfilePhoto { get; set; }
        [MaxLength(150)]  public string?   Occupation   { get; set; }
        [MaxLength(200)]  public string?   Organisation { get; set; }
        public string?    VolunteerExp                  { get; set; }   // Previous NGO/volunteer experience
        public int?       EducationLkpId                { get; set; }
        [MaxLength(150)]  public string?   FieldOfStudy { get; set; }
        public int?       WorkExpLkpId                  { get; set; }
        [MaxLength(255)]  public string?   AddressLine1 { get; set; }
        [MaxLength(255)]  public string?   AddressLine2 { get; set; }
        [MaxLength(20)]   public string?   Pincode      { get; set; }
        [MaxLength(100)]  public string?   City         { get; set; }
        [MaxLength(100)]  public string?   State        { get; set; }
        [MaxLength(100)]  public string?   Country      { get; set; }
    }

    // ── Safety Preferences (v4.0) ───────────────────────────────────────────────
    public class UpdateSafetyPrefsRequest
    {
        // Visibility & location — map to UserSafetyPreferences table
        public int?    EmergVisibilityLkpId     { get; set; }   // Who can see SOS alert
        public int?    AutoShareDurLkpId        { get; set; }   // Auto stop location sharing after X
        public bool?   AllowLocDuringSos        { get; set; }   // Share live location during SOS
        public bool?   AllowLocDuringProj       { get; set; }   // Share live location during project

        // Emergency contact — map to UserSafetyPreferences table (Option B)
        [MaxLength(100)] public string? EmergencyContactName     { get; set; }
        [MaxLength(20)]  public string? EmergencyContactPhone    { get; set; }
        [MaxLength(50)]  public string? EmergencyContactRelation { get; set; }
    }

    // ── Interests (v4.1) ────────────────────────────────────────────────────────
    public class SaveInterestsRequest
    {
        // LookupType: INTEREST_TYPE — send LookupValueIds from GET /lookup/values/INTEREST_TYPE
        [Required] public List<int> InterestLkpIds { get; set; } = [];
    }

    // ── Document Upload (v4.1) ──────────────────────────────────────────────────
    // Frontend flow:
    //   1. POST /media/upload?module=user-documents → get { fileUrl, fileName, fileSizeKb }
    //   2. POST /user/documents with those values + documentTypeLkpId
    public class UploadDocumentRequest
    {
        [Required] public int    DocumentTypeLkpId { get; set; }   // LookupType: DOCUMENT_TYPE
        [Required] public string FileUrl           { get; set; } = string.Empty;   // from /media/upload
        [Required] public string FileName          { get; set; } = string.Empty;   // from /media/upload
        [Required] public int    FileSizeKb        { get; set; }                   // from /media/upload
    }

    // ── Document ────────────────────────────────────────────────────────────────
    public class UserDocumentModel
    {
        public int      UserDocumentId     { get; set; }
        public int      DocumentTypeLkpId  { get; set; }
        public string   DocTypeCode        { get; set; } = string.Empty;
        public string   DocTypeName        { get; set; } = string.Empty;
        public string   FileUrl            { get; set; } = string.Empty;
        public string   FileName           { get; set; } = string.Empty;
        public int?     FileSizeKb         { get; set; }
        public bool     IsVerified         { get; set; }
        public DateTime UploadedAt         { get; set; }
    }

    // ── Skill ───────────────────────────────────────────────────────────────────
    public class UserSkillModel
    {
        public int     UserSkillId { get; set; }
        public string  SkillName   { get; set; } = string.Empty;
        public decimal AvgRating   { get; set; }
        public int     RatingCount { get; set; }
    }

    public class AddSkillRequest
    {
        [Required][MaxLength(100)] public string SkillName { get; set; } = string.Empty;
    }

    // ── Safety Preferences — GET response ──────────────────────────────────────
    public class UserSafetyPrefsModel
    {
        public int?    EmergVisibilityLkpId     { get; set; }
        public string? EmergVisibility          { get; set; }   // ValueName e.g. "Friends Only"
        public int?    AutoShareDurLkpId        { get; set; }
        public string? AutoShareDuration        { get; set; }   // ValueName e.g. "30 Minutes"
        public bool    AllowLocDuringSos        { get; set; }
        public bool    AllowLocDuringProj       { get; set; }
        public string? EmergencyContactName     { get; set; }
        public string? EmergencyContactPhone    { get; set; }
        public string? EmergencyContactRelation { get; set; }
    }

    // ── Interests — GET response ────────────────────────────────────────────────
    public class UserInterestModel
    {
        public int    InterestLkpId   { get; set; }
        public string InterestName    { get; set; } = string.Empty;   // ValueName e.g. "Education"
        public string InterestCode    { get; set; } = string.Empty;   // ValueCode e.g. "EDUCATION"
    }

    // ── My Organisations — GET response ────────────────────────────────────────
    public class UserOrgModel
    {
        public int      OrgId             { get; set; }
        public string   OrgName           { get; set; } = string.Empty;
        public string?  LogoUrl           { get; set; }
        public string?  OrgType           { get; set; }   // ValueName e.g. "Education"
        public string?  City              { get; set; }
        public string?  State             { get; set; }
        public string   Role              { get; set; } = string.Empty;   // ValueName e.g. "Admin"
        public string   RoleCode          { get; set; } = string.Empty;   // ValueCode e.g. "ADMIN", "FOUNDER", "MEMBER"
        public string   MemberStatusCode  { get; set; } = string.Empty;   // APPROVED | PENDING
        public string   OrgStatusCode     { get; set; } = string.Empty;   // ACTIVE | PENDING | REJECTED | SUSPENDED
        public int      MemberCount       { get; set; }
        public DateTime JoinedAt          { get; set; }
        public string?  RejectionReason   { get; set; }   // populated when OrgStatusCode = REJECTED
    }

    // ── Badges — GET response ───────────────────────────────────────────────────
    public class UserBadgeModel
    {
        public int      UserBadgeId    { get; set; }
        public int      BadgeLkpId     { get; set; }
        public string   BadgeName      { get; set; } = string.Empty;   // ValueName e.g. "10 Hours"
        public string   BadgeCode      { get; set; } = string.Empty;   // ValueCode e.g. "HOURS_10"
        public string?  OrgName        { get; set; }   // Org that awarded it (nullable)
        public string?  ProjectName    { get; set; }   // Project it was awarded for (nullable)
        public DateTime AwardedAt      { get; set; }
    }

    // ── User Application list — GET response (s-all-projects screen) ──────────
    public class UserApplicationModel
    {
        public int      ApplicationId      { get; set; }
        public int      ProjectId          { get; set; }
        public string   ProjectName        { get; set; } = string.Empty;
        public string   OrgName            { get; set; } = string.Empty;
        public string?  OrgLogoUrl         { get; set; }
        // Application status
        public string   StatusCode         { get; set; } = string.Empty;  // PENDING | APPROVED | REJECTED | WITHDRAWN
        public string   Status             { get; set; } = string.Empty;  // Human-readable
        public DateTime CreatedAt          { get; set; }
        public DateTime? StatusUpdatedAt   { get; set; }
        // Project schedule
        public string?  ScheduleTypeCode   { get; set; }  // ONE_TIME | RECURRING | FLEXIBLE
        public string?  ScheduleTypeName   { get; set; }
        public DateTime? RecurStart        { get; set; }
        public DateTime? RecurEnd          { get; set; }
        public string?  RecurDays          { get; set; }  // comma-separated day names
        public TimeSpan? SessionStartTime  { get; set; }
        public TimeSpan? SessionEndTime    { get; set; }
        public string?  Landmark           { get; set; }
        public string?  City               { get; set; }
        // Project status (drives tab routing on mobile)
        public string?  ProjectStatusCode  { get; set; }  // UPCOMING | ACTIVE | COMPLETED | EXPIRED | CANCELLED
        public string?  ProjectStatus      { get; set; }
    }

    // ── Contact Update (OTP flow) ───────────────────────────────────────────────
    public class SendContactOtpRequest
    {
        /// <summary>"EMAIL" or "PHONE"</summary>
        [Required][MaxLength(10)]  public string Type  { get; set; } = string.Empty;
        /// <summary>The email address or phone number to add</summary>
        [Required][MaxLength(200)] public string Value { get; set; } = string.Empty;
    }

    public class VerifyContactOtpRequest
    {
        /// <summary>"EMAIL" or "PHONE"</summary>
        [Required][MaxLength(10)]  public string Type    { get; set; } = string.Empty;
        /// <summary>The email address or phone number being verified</summary>
        [Required][MaxLength(200)] public string Value   { get; set; } = string.Empty;
        /// <summary>6-digit OTP entered by the user</summary>
        [Required][MaxLength(6)]   public string OtpCode { get; set; } = string.Empty;
    }

    // ── Impact Dashboard — GET response ────────────────────────────────────────
    public class UserImpactModel
    {
        // Scores
        public int      ImpactScore          { get; set; }
        public decimal  ReliabilityPct       { get; set; }
        // Activity totals
        public int      ProjectsCompleted    { get; set; }
        public decimal  TotalHours           { get; set; }
        public int      BadgeCount           { get; set; }
        public int      SkillCount           { get; set; }
        // Volunteer history
        public int      ProjectsApplied      { get; set; }
        public int      CertificateCount     { get; set; }
        public DateTime MemberSince          { get; set; }
        // Rank
        public string   RankName             { get; set; } = "Newcomer";
        public int      RankNumber           { get; set; }
        public int      TotalRanked          { get; set; }
        // NGOs
        public int      NgosJoined           { get; set; }
        // Application summary counts
        public int      PendingApplications  { get; set; }
        public int      ApprovedApplications { get; set; }
        // Profile fields (avoids a second API call on Impact screen)
        public string?  FirstName            { get; set; }
        public string?  LastName             { get; set; }
        public string?  ProfilePhoto         { get; set; }
        public string?  Bio                  { get; set; }
    }
}

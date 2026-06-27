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
        public string?   Gender             { get; set; }   // ValueName  e.g. "Male"
        public string?   GenderCode         { get; set; }   // ValueCode  e.g. "MALE"
        public DateTime? DateOfBirth        { get; set; }
        public string?   ProfilePhoto       { get; set; }
        public string?   Occupation         { get; set; }
        public string?   Organisation       { get; set; }
        public string?   VolunteerExp       { get; set; }   // Previous NGO/volunteer experience
        // Education
        public string?   Education          { get; set; }   // ValueName  e.g. "Bachelor's Degree"
        public string?   EducationCode      { get; set; }   // ValueCode  e.g. "BACHELOR"
        public string?   FieldOfStudy       { get; set; }
        // Work Experience
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
}

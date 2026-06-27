using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.User
{
    // ── Get Own Profile ─────────────────────────────────────────────────────────
    public class UserProfileModel
    {
        public int       UserId           { get; set; }
        public string?   Mobile           { get; set; }
        public string?   Email            { get; set; }
        public string    CountryCode      { get; set; } = "+91";
        public string?   FirstName        { get; set; }
        public string?   LastName         { get; set; }
        public string?   Bio              { get; set; }
        public string?   GenderValueCode  { get; set; }
        public DateTime? DateOfBirth      { get; set; }
        public string?   ProfilePhoto     { get; set; }
        public string?   Occupation       { get; set; }
        public string?   Organisation     { get; set; }
        // v4.0 Education
        public string?   EducationCode    { get; set; }
        public string?   FieldOfStudy     { get; set; }
        // v4.0 WorkExp
        public string?   WorkExpCode      { get; set; }
        // v4.0 Address
        public string?   AddressLine1     { get; set; }
        public string?   AddressLine2     { get; set; }
        public string?   Pincode          { get; set; }
        public string?   City             { get; set; }
        public string?   State            { get; set; }
        public string?   Country          { get; set; }
        public int       ImpactScore      { get; set; }
        public decimal   ReliabilityPct   { get; set; }
        public DateTime  CreatedAt        { get; set; }
        public DateTime? UpdatedAt        { get; set; }
        public bool      IsProfileComplete { get; set; }
    }

    // ── Update Profile Request (v4.0 — 17 params) ───────────────────────────────
    public class UpdateProfileRequest
    {
        [MaxLength(80)]  public string?   FirstName        { get; set; }
        [MaxLength(80)]  public string?   LastName         { get; set; }
        [MaxLength(1000)]public string?   About            { get; set; }
        public int?      GenderLkpId      { get; set; }
        public DateTime? DateOfBirth      { get; set; }
        [MaxLength(255)] public string?   ProfilePhoto     { get; set; }
        [MaxLength(150)] public string?   Occupation       { get; set; }
        [MaxLength(200)] public string?   Organisation     { get; set; }
        public int?      EducationLkpId   { get; set; }
        [MaxLength(150)] public string?   FieldOfStudy     { get; set; }
        public int?      WorkExpLkpId     { get; set; }
        [MaxLength(255)] public string?   AddressLine1     { get; set; }
        [MaxLength(255)] public string?   AddressLine2     { get; set; }
        [MaxLength(20)]  public string?   Pincode          { get; set; }
        [MaxLength(100)] public string?   City             { get; set; }
        [MaxLength(100)] public string?   State            { get; set; }
        [MaxLength(100)] public string?   Country          { get; set; }
    }

    // ── Safety Preferences (v4.0) ───────────────────────────────────────────────
    public class UpdateSafetyPrefsRequest
    {
        public int?   SosAlertTypeLkpId    { get; set; }
        public string? EmergencyContactName { get; set; }
        public string? EmergencyContactPhone { get; set; }
        public string? EmergencyContactRelation { get; set; }
        public bool?  ShareLocationDuringSos { get; set; }
    }

    // ── Interests (v4.0) ────────────────────────────────────────────────────────
    public class SaveInterestsRequest
    {
        [Required] public List<int> InterestLkpIds { get; set; } = [];
    }

    // ── Document Upload (v4.0) ──────────────────────────────────────────────────
    public class UploadDocumentRequest
    {
        [Required] public int    DocumentTypeLkpId { get; set; }
        [Required] public string DocumentUrl       { get; set; } = string.Empty;
        public string? ExpiryDate { get; set; }
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

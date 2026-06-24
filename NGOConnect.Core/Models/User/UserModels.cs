using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.User
{
    // ── Get Own Profile (Authenticated) ─────────────────────────────────────────
    /// <summary>
    /// Full profile — only returned to the authenticated user for their own profile.
    /// Contains PII: mobile, email. NOT used for public profile display.
    /// Typed model (core entity — 30% typed rule).
    /// SP: User_GetProfile
    /// </summary>
    public class UserProfileModel
    {
        public int      UserId         { get; set; }
        public string   MobileNumber   { get; set; } = string.Empty;
        public string?  Email          { get; set; }
        public string   CountryCode    { get; set; } = "+91";

        // Profile fields
        public string?   FirstName       { get; set; }
        public string?   LastName        { get; set; }
        public string?   DisplayName     { get; set; }
        public string?   About           { get; set; }
        public string?   GenderValueCode { get; set; }   // MALE / FEMALE / OTHER
        public DateTime? DateOfBirth     { get; set; }
        public string?   ProfilePhotoUrl { get; set; }
        public string?   City            { get; set; }
        public string?   State           { get; set; }
        public string?   Country         { get; set; }
        public string?   LinkedInUrl     { get; set; }
        public string?   WebsiteUrl      { get; set; }

        public DateTime  CreatedAt        { get; set; }
        public DateTime? UpdatedAt        { get; set; }
        public bool      IsProfileComplete { get; set; }  // true when FirstName + LastName filled
    }

    // ── Update Profile Request ───────────────────────────────────────────────────
    /// <summary>
    /// All fields are optional — COALESCE in SP preserves existing values for nulls.
    /// PATCH semantics: send only what you want to change.
    /// SP: User_UpdateProfile
    /// </summary>
    public class UpdateProfileRequest
    {
        [MaxLength(100)]
        public string?   FirstName    { get; set; }

        [MaxLength(100)]
        public string?   LastName     { get; set; }

        [MaxLength(200)]
        public string?   DisplayName  { get; set; }

        [MaxLength(1000)]
        public string?   About        { get; set; }

        /// <summary>LookupValueId from LookupValues where TypeCode = 'GENDER'</summary>
        public int?      GenderLkpId  { get; set; }

        public DateTime? DateOfBirth  { get; set; }

        [MaxLength(100)]
        public string?   City         { get; set; }

        [MaxLength(100)]
        public string?   State        { get; set; }

        [MaxLength(100)]
        public string?   Country      { get; set; }

        [Url, MaxLength(500)]
        public string?   LinkedInUrl  { get; set; }

        [Url, MaxLength(500)]
        public string?   WebsiteUrl   { get; set; }
    }

    // ── User Skill ───────────────────────────────────────────────────────────────
    /// <summary>
    /// Skill entry in a user's profile.
    /// Typed model — referenced in C# code.
    /// SP: User_GetSkills (DataReader — frequent call)
    /// </summary>
    public class UserSkillModel
    {
        public int    UserSkillId      { get; set; }
        public int    SkillLkpId       { get; set; }
        public string SkillName        { get; set; } = string.Empty;
        public int    ProficiencyLkpId { get; set; }
        public string ProficiencyName  { get; set; } = string.Empty;
    }

    // ── Add/Update Skill Request ─────────────────────────────────────────────────
    /// <summary>
    /// Add a skill or update proficiency if skill already exists (upsert in SP).
    /// SkillLkpId       → LookupValueId where TypeCode = 'SKILL'
    /// ProficiencyLkpId → LookupValueId where TypeCode = 'SKILL_PROFICIENCY'
    /// SP: User_AddSkill
    /// </summary>
    public class AddSkillRequest
    {
        [Required(ErrorMessage = "SkillLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid SkillLkpId")]
        public int SkillLkpId { get; set; }

        [Required(ErrorMessage = "ProficiencyLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid ProficiencyLkpId")]
        public int ProficiencyLkpId { get; set; }
    }
}

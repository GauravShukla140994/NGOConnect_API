using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Organisation
{
    /// <summary>
    /// DB column mapping notes:
    ///   RegNumber       (not RegistrationNo)
    ///   OrgTypeLkpId    (not OrgTypeId)
    ///   ContactEmail    (not Email)
    ///   ContactPhone    (not Phone)
    ///   StatusLkpId     (INT FK, not IsVerified BOOL)
    ///   Category        VARCHAR(100), not via LookupValues
    /// </summary>
    public class OrgProfileModel
    {
        public int     OrgId          { get; set; }
        public string  OrgName        { get; set; } = string.Empty;
        public string? RegNumber      { get; set; }   // DB column: RegNumber
        public string? About          { get; set; }
        public string? Mission        { get; set; }
        public string? Vision         { get; set; }
        public string? Website        { get; set; }
        public string? ContactPhone   { get; set; }   // DB column: ContactPhone
        public string? ContactEmail   { get; set; }   // DB column: ContactEmail
        public string? City           { get; set; }
        public string? State          { get; set; }
        public string? Country        { get; set; }
        public string? LogoUrl        { get; set; }
        public string? Category       { get; set; }
        public string? OrgType        { get; set; }   // from LookupValues join
        public string? OrgStatus      { get; set; }   // from LookupValues join (not IsVerified)
        public int     MemberCount    { get; set; }
        public DateTime CreatedAt     { get; set; }
    }

    public class RegisterOrgRequest
    {
        [Required(ErrorMessage = "Organisation name is required")]
        [MaxLength(200)]
        public string  OrgName        { get; set; } = string.Empty;

        /// <summary>Maps to DB column: RegNumber</summary>
        [MaxLength(100)]
        public string? RegistrationNo { get; set; }

        [MaxLength(100)]
        public string? Category       { get; set; }   // Required by DB — Education, Healthcare, etc.

        [MaxLength(1000)]
        public string? About          { get; set; }

        [MaxLength(255)]
        public string? Website        { get; set; }

        /// <summary>Maps to DB column: ContactPhone</summary>
        [MaxLength(20)]
        public string? Phone          { get; set; }

        /// <summary>Maps to DB column: ContactEmail</summary>
        [MaxLength(150)]
        public string? Email          { get; set; }

        [MaxLength(100)]
        public string? City           { get; set; }

        [MaxLength(100)]
        public string? State          { get; set; }

        [MaxLength(100)]
        public string? Country        { get; set; }

        /// <summary>LookupValueId from LookupValues where TypeCode = 'ORG_TYPE' (DB column: OrgTypeLkpId)</summary>
        [Required(ErrorMessage = "OrgTypeLkpId is required")]
        [Range(1, int.MaxValue)]
        public int OrgTypeLkpId { get; set; }   // was OrgTypeId — renamed to match DB
    }

    public class UpdateOrgRequest
    {
        [MaxLength(1000)]
        public string? About   { get; set; }

        [MaxLength(255)]
        public string? Website { get; set; }

        /// <summary>Maps to DB column: ContactPhone</summary>
        [MaxLength(20)]
        public string? Phone   { get; set; }

        [MaxLength(100)]
        public string? City    { get; set; }

        [MaxLength(100)]
        public string? State   { get; set; }

        [MaxLength(100)]
        public string? Country { get; set; }
    }

    public class OrgMemberModel
    {
        public int      OrgMemberId  { get; set; }
        public int      UserId       { get; set; }
        public string   FullName     { get; set; } = string.Empty;
        public string?  ProfilePhoto { get; set; }
        public string   RoleCode     { get; set; } = string.Empty;   // FOUNDER / ADMIN / MODERATOR / MEMBER
        public string   StatusCode   { get; set; } = string.Empty;   // APPROVED / PENDING / etc.
        public DateTime? JoinedAt   { get; set; }
    }

    public class AddMemberRequest
    {
        [Required]
        [Range(1, int.MaxValue)]
        public int UserId { get; set; }

        /// <summary>LookupValueId from LookupValues where TypeCode = 'MEMBER_ROLE' (DB column: RoleLkpId)</summary>
        [Required(ErrorMessage = "RoleLkpId is required")]
        [Range(1, int.MaxValue, ErrorMessage = "Invalid RoleLkpId")]
        public int RoleLkpId { get; set; }   // was Role string — DB stores INT FK to LookupValues
    }
}

using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.SuperAdmin
{
    // ── Login ─────────────────────────────────────────────────────────────────
    public class SuperAdminLoginRequest
    {
        [Required][MaxLength(100)] public string Username { get; set; } = string.Empty;
        [Required]                 public string Password { get; set; } = string.Empty;
    }

    public class SuperAdminLoginResponse
    {
        public int      SuperAdminUserId { get; set; }
        public string   Username         { get; set; } = string.Empty;
        public string   FullName         { get; set; } = string.Empty;
        public string   AccessToken      { get; set; } = string.Empty;
        public DateTime AccessTokenExpiry { get; set; }
    }

    // ── Organisation review ──────────────────────────────────────────────────
    // OrgId/OrgDocumentId/UserId/UserDocumentId fields below were replaced with
    // encrypted tokens (2026-08-24) — see SuperAdminController.TryResolveId.
    // Raw sequential IDs are decrypted server-side in the controller only; the
    // DAL/SP layer below still works with plain ints exactly as before.
    public class RejectOrgRequest
    {
        [Required] public string OrgToken { get; set; } = string.Empty;
        [Required][MaxLength(1000)] public string Reason { get; set; } = string.Empty;
    }

    public class SuspendOrgRequest
    {
        [Required] public string OrgToken { get; set; } = string.Empty;
        [MaxLength(1000)] public string? Reason { get; set; }
    }

    public class VerifyOrgDocumentRequest
    {
        [Required] public string OrgDocumentToken { get; set; } = string.Empty;
        [Required] public bool   IsVerified       { get; set; }
    }

    // ── Member review ─────────────────────────────────────────────────────────
    public class VerifyMemberDocumentRequest
    {
        [Required] public string UserDocumentToken { get; set; } = string.Empty;
        [Required] public bool   IsVerified         { get; set; }
    }

    public class RequestMemberUpdateRequest
    {
        [Required] public string UserToken { get; set; } = string.Empty;
        [Required][MaxLength(1000)] public string Reason { get; set; } = string.Empty;
    }

    public class SuspendMemberRequest
    {
        [Required][MaxLength(1000)] public string Reason { get; set; } = string.Empty;
    }

    // ── Lookup type management ───────────────────────────────────────────────
    public class AddLookupTypeRequest
    {
        [Required][MaxLength(50)]  public string  TypeCode    { get; set; } = string.Empty;
        [Required][MaxLength(100)] public string  TypeName    { get; set; } = string.Empty;
        [MaxLength(300)]           public string? Description { get; set; }
    }

    public class UpdateLookupTypeRequest
    {
        [Required] public int     LookupTypeId { get; set; }
        [Required][MaxLength(100)] public string  TypeName    { get; set; } = string.Empty;
        [MaxLength(300)]           public string? Description { get; set; }
    }

    // ── Lookup value management ──────────────────────────────────────────────
    public class AddLookupValueRequest
    {
        [Required] public int     LookupTypeId { get; set; }
        [Required][MaxLength(50)]  public string  ValueCode   { get; set; } = string.Empty;
        [Required][MaxLength(100)] public string  ValueName   { get; set; } = string.Empty;
        [MaxLength(300)]           public string? Description { get; set; }
        public short  OrderNo   { get; set; } = 0;
        public bool   IsDefault { get; set; } = false;
    }

    public class UpdateLookupValueRequest
    {
        [Required] public int     LookupValueId { get; set; }
        [Required][MaxLength(100)] public string  ValueName   { get; set; } = string.Empty;
        [MaxLength(300)]           public string? Description { get; set; }
        public short  OrderNo   { get; set; } = 0;
        public bool   IsDefault { get; set; } = false;
    }

    public class SetLookupValueActiveRequest
    {
        [Required] public int  LookupValueId { get; set; }
        [Required] public bool IsActive      { get; set; }
    }

    // ── Org project permissions + limits ──────────────────────────────────────
    public class UpdateOrgProjectPermissionsRequest
    {
        [Required] public bool CanCreateRecurring { get; set; }
        [Required] public bool CanCreateFlexible  { get; set; }
        /// <summary>Max volunteers per project for this org. Null = leave unchanged.</summary>
        [Range(1, int.MaxValue)] public int? OrgMaxVolunteers { get; set; }
    }

    // ── Proactive Member + Organisation onboarding ───────────────────────────
    // Super Admin creates a User + UserProfile + (new or existing) Organisation +
    // OrgMembers association in one atomic call — SuperAdmin_CreateMemberWithOrg.
    // See that SP for the full validation/rollback behaviour.
    public class CreateMemberWithOrgRequest
    {
        // ── Member ──
        [MaxLength(80)]  public string? FirstName { get; set; }
        [MaxLength(80)]  public string? LastName  { get; set; }
        [MaxLength(150)][EmailAddress] public string? Email  { get; set; }
        [MaxLength(20)]  public string? Mobile      { get; set; }
        [MaxLength(6)]   public string  CountryCode { get; set; } = "+91";
        public int?      GenderLkpId  { get; set; }
        public DateTime? DateOfBirth  { get; set; }
        [MaxLength(500)] public string? ProfilePhoto { get; set; }
        [MaxLength(200)] public string? AddressLine1 { get; set; }
        [MaxLength(200)] public string? AddressLine2 { get; set; }
        [MaxLength(100)] public string? City    { get; set; }
        [MaxLength(100)] public string? State   { get; set; }
        [MaxLength(20)]  public string? Pincode { get; set; }
        [MaxLength(100)] public string? Country { get; set; }

        // ── Organisation ──
        /// <summary>"NEW" or "EXISTING".</summary>
        [Required][MaxLength(10)] public string OrgMode { get; set; } = string.Empty;
        /// <summary>Required when OrgMode = "EXISTING".</summary>
        public int? ExistingOrgId { get; set; }

        // Required when OrgMode = "NEW" — validated inside the SP, not here,
        // since requiredness depends on OrgMode (conditional validation).
        [MaxLength(200)] public string? OrgName      { get; set; }
        public int?      OrgTypeLkpId  { get; set; }
        [MaxLength(100)] public string? RegNumber    { get; set; }
        [MaxLength(100)] public string? Category     { get; set; }
        public string?   About   { get; set; }
        public string?   Mission { get; set; }
        public string?   Vision  { get; set; }
        [MaxLength(500)] public string? LogoUrl      { get; set; }
        [MaxLength(150)][EmailAddress] public string? ContactEmail { get; set; }
        [MaxLength(20)]  public string? ContactPhone { get; set; }
        [MaxLength(255)] public string? Website      { get; set; }
        [MaxLength(200)] public string? OrgAddressLine1 { get; set; }
        [MaxLength(200)] public string? OrgAddressLine2 { get; set; }
        [MaxLength(100)] public string? OrgCity    { get; set; }
        [MaxLength(100)] public string? OrgState   { get; set; }
        [MaxLength(20)]  public string? OrgPincode { get; set; }
        [MaxLength(100)] public string? OrgCountry { get; set; }

        // ── Role ──
        /// <summary>MEMBER_ROLE ValueCode: FOUNDER | ADMIN | MODERATOR | MEMBER.</summary>
        [Required][MaxLength(20)] public string RoleCode { get; set; } = string.Empty;
    }

    // ── Post-creation profile correction (SuperAdmin_Org_UpdateProfile / SuperAdmin_User_UpdateProfile) ──
    // Full-profile overwrite, same shape as the corresponding fields on
    // CreateMemberWithOrgRequest — not a per-field PATCH.
    public class UpdateOrgProfileRequest
    {
        [Required][MaxLength(200)] public string  OrgName      { get; set; } = string.Empty;
        [Required] public int      OrgTypeLkpId   { get; set; }
        [Required][MaxLength(100)] public string  RegNumber    { get; set; } = string.Empty;
        [MaxLength(100)] public string? Category      { get; set; }
        [MaxLength(100)] public string? ContactPerson { get; set; }
        public string?   About   { get; set; }
        public string?   Mission { get; set; }
        public string?   Vision  { get; set; }
        [MaxLength(500)] public string? LogoUrl      { get; set; }
        [MaxLength(150)][EmailAddress] public string? ContactEmail { get; set; }
        [MaxLength(20)]  public string? ContactPhone { get; set; }
        [MaxLength(255)] public string? Website      { get; set; }
        [MaxLength(200)] public string? AddressLine1 { get; set; }
        [MaxLength(200)] public string? AddressLine2 { get; set; }
        [MaxLength(100)] public string? City    { get; set; }
        [MaxLength(100)] public string? State   { get; set; }
        [MaxLength(20)]  public string? Pincode { get; set; }
        [MaxLength(100)] public string? Country { get; set; }
    }

    /// <summary>
    /// Email/Mobile are included so a pre-first-login (IsVerified=0) member's
    /// typo'd contact details can still be fixed here. SuperAdmin_User_UpdateProfile
    /// silently ignores both once the member has logged in — see that SP.
    /// </summary>
    public class UpdateMemberProfileRequest
    {
        [Required][MaxLength(80)] public string  FirstName { get; set; } = string.Empty;
        [MaxLength(80)]  public string? LastName  { get; set; }
        [MaxLength(150)][EmailAddress] public string? Email  { get; set; }
        [MaxLength(20)]  public string? Mobile      { get; set; }
        [MaxLength(6)]   public string? CountryCode { get; set; }
        public int?      GenderLkpId  { get; set; }
        public DateTime? DateOfBirth  { get; set; }
        [MaxLength(500)] public string? ProfilePhoto { get; set; }
        [MaxLength(200)] public string? AddressLine1 { get; set; }
        [MaxLength(200)] public string? AddressLine2 { get; set; }
        [MaxLength(100)] public string? City    { get; set; }
        [MaxLength(100)] public string? State   { get; set; }
        [MaxLength(20)]  public string? Pincode { get; set; }
        [MaxLength(100)] public string? Country { get; set; }
    }
}

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
    public class RejectOrgRequest
    {
        [Required] public int    OrgId  { get; set; }
        [Required][MaxLength(1000)] public string Reason { get; set; } = string.Empty;
    }

    public class SuspendOrgRequest
    {
        [Required] public int    OrgId  { get; set; }
        [MaxLength(1000)] public string? Reason { get; set; }
    }

    public class VerifyOrgDocumentRequest
    {
        [Required] public int  OrgDocumentId { get; set; }
        [Required] public bool IsVerified    { get; set; }
    }

    // ── Member review ─────────────────────────────────────────────────────────
    public class VerifyMemberDocumentRequest
    {
        [Required] public int  UserDocumentId { get; set; }
        [Required] public bool IsVerified     { get; set; }
    }

    public class RequestMemberUpdateRequest
    {
        [Required] public int    UserId { get; set; }
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

    // ── Org project permissions ────────────────────────────────────────────────
    public class UpdateOrgProjectPermissionsRequest
    {
        [Required] public bool CanCreateRecurring { get; set; }
        [Required] public bool CanCreateFlexible  { get; set; }
    }
}

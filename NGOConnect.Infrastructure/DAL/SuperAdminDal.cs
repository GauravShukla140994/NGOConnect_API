using System.Data;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.SuperAdmin;
using Serilog;
using BCrypt.Net;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// Super Admin DAL — Controller → ISuperAdminDal → SuperAdminDal → Stored Procedures → MySQL.
    ///
    /// Isolation by design (Core Mandate — this module must never regress existing flows):
    ///   - Every SP called here is brand new (SuperAdmin_* prefix). None reuse or modify
    ///     any SP used by the mobile app or NGO-admin flows.
    ///   - JWT generation is a private copy here, not a call into AuthDal — same signing
    ///     key/issuer/audience (so the existing JwtBearer pipeline still validates it),
    ///     but with a SUPER_ADMIN role claim that normal user tokens never carry.
    ///   - BCrypt password verification happens here in C#, not in the SP — MySQL has no
    ///     native bcrypt function.
    /// </summary>
    public class SuperAdminDal : BaseDal, ISuperAdminDal
    {
        private readonly IConfiguration    _config;
        private readonly INotificationDal  _notif;
        private readonly IFCMService       _fcm;
        private readonly IUrlTokenService  _tokens;

        // Matches ShareController / CertificateDal's convention — hardcoded prod domain
        // rather than Settings-driven. See CertificateDal.cs for the same note.
        private const string BaseUrl = "https://www.ripplehub.app";

        public SuperAdminDal(IDbProvider db, IConfiguration config, INotificationDal notif, IFCMService fcm, IUrlTokenService tokens)
            : base(db)
        {
            _config = config;
            _notif  = notif;
            _fcm    = fcm;
            _tokens = tokens;
        }

        // ══════════════════════════════════════════════════════════════
        // Auth
        // ══════════════════════════════════════════════════════════════

        public async Task<ApiResponse<SuperAdminLoginResponse>> LoginAsync(SuperAdminLoginRequest request, string ipAddress)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("SuperAdmin_GetByUsername", cmd =>
                {
                    _db.AddParameter(cmd, "p_Username", request.Username);
                });

                if (row is null)
                {
                    Log.Warning("SuperAdmin login failed — unknown username {Username} from {Ip}", request.Username, ipAddress);
                    return ApiResponse<SuperAdminLoginResponse>.Failure("Invalid username or password.", "SUPERADMIN_LOGIN_FAILED");
                }

                var isActive     = row.Get<bool?>("isActive") ?? false;
                var passwordHash = row.Get<string>("passwordHash") ?? string.Empty;

                if (!isActive || !BCrypt.Net.BCrypt.Verify(request.Password, passwordHash))
                {
                    Log.Warning("SuperAdmin login failed — bad password or inactive account. Username={Username} Ip={Ip}", request.Username, ipAddress);
                    return ApiResponse<SuperAdminLoginResponse>.Failure("Invalid username or password.", "SUPERADMIN_LOGIN_FAILED");
                }

                var superAdminUserId = row.Get<int?>("superAdminUserId") ?? 0;
                var fullName         = row.Get<string>("fullName") ?? string.Empty;

                var accessToken  = GenerateJwt(superAdminUserId, request.Username, fullName);
                var accessExpiry = DateTime.UtcNow.AddMinutes(15);

                await ExecuteWriteAsync("SuperAdmin_UpdateLastLogin", cmd =>
                {
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                Log.Information("SuperAdmin login OK. SuperAdminUserId={Id} Username={Username}", superAdminUserId, request.Username);

                return ApiResponse<SuperAdminLoginResponse>.Success(new SuperAdminLoginResponse
                {
                    SuperAdminUserId  = superAdminUserId,
                    Username          = request.Username,
                    FullName          = fullName,
                    AccessToken       = accessToken,
                    AccessTokenExpiry = accessExpiry
                }, "Login successful");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SuperAdmin LoginAsync failed for {Username}", request.Username);
                return ApiResponse<SuperAdminLoginResponse>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        private string GenerateJwt(int superAdminUserId, string username, string fullName)
        {
            var jwtKey      = _config["Jwt:Key"] ?? throw new InvalidOperationException("JWT Key not configured");
            var jwtIssuer   = _config["Jwt:Issuer"]   ?? "NGOConnect";
            var jwtAudience = _config["Jwt:Audience"] ?? "NGOConnectUsers";

            var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
            var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var claims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub,  superAdminUserId.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti,  Guid.NewGuid().ToString()),
                new Claim("uid",      superAdminUserId.ToString()),
                new Claim("username", username),
                new Claim("fullName", fullName),
                new Claim(ClaimTypes.Role, "SUPER_ADMIN")
            };

            var token = new JwtSecurityToken(
                issuer:             jwtIssuer,
                audience:           jwtAudience,
                claims:             claims,
                expires:            DateTime.UtcNow.AddMinutes(15),
                signingCredentials: creds);

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        // ══════════════════════════════════════════════════════════════
        // Organisation review
        // ══════════════════════════════════════════════════════════════

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgListAsync(string statusCode, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("SuperAdmin_Org_GetList", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_StatusCode", statusCode);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                // orgToken added per row (2026-08-24) so the website can build
                // detail/action URLs without exposing raw OrgId in the Network
                // tab — orgId itself is left in the row too (already visible in
                // the response body, used for table keys/filters).
                foreach (var row in paged.Items)
                    row["orgToken"] = _tokens.Encrypt("ORG", row.Get<int>("orgId"));
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgListAsync failed StatusCode={StatusCode}", statusCode);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetOrgDetailAsync(int orgId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("SuperAdmin_Org_GetDetail", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });

                if (row is null)
                    return ApiResponse<DynamicRow>.Failure("Organisation not found.", "ORG_NOT_FOUND");

                row["orgToken"] = _tokens.Encrypt("ORG", orgId);
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgDetailAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetOrgDocumentsAsync(int orgId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("SuperAdmin_Org_GetDocuments", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });
                foreach (var row in list)
                    row["orgDocumentToken"] = _tokens.Encrypt("ORGDOC", row.Get<int>("orgDocumentId"));
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgDocumentsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyOrgDocumentAsync(int orgDocumentId, bool isVerified, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_OrgDocument_Verify", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgDocumentId",    orgDocumentId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_IsVerified",       isVerified);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyOrgDocumentAsync failed OrgDocumentId={Id}", orgDocumentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyOrgProfileAsync(int orgId, string statusCode, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_VerifyProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",          orgId);
                    _db.AddParameter(cmd, "p_StatusCode",     statusCode);
                    _db.AddParameter(cmd, "p_SuperAdminId",   superAdminUserId);
                });
                if (result.Succeeded)
                {
                    if (statusCode == "VERIFIED")
                        _ = FireOrgAdminNotifAsync(orgId, "✅ NGO Profile Verified",
                            "Your NGO profile has been verified! Your verified badge is now visible on the platform.",
                            "ORG_PROFILE_VERIFIED", orgId, "ORG");
                    else if (statusCode == "REJECTED")
                        _ = FireOrgAdminNotifAsync(orgId, "NGO Profile Verification Update",
                            "Your NGO profile verification was not approved. Please review your details and resubmit.",
                            "ORG_PROFILE_REJECTED", orgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyOrgProfileAsync failed OrgId={OrgId} StatusCode={StatusCode}", orgId, statusCode);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ApproveOrgAsync(int orgId, bool isNonRegistered, string? remarks, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Approve", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_IsNonRegistered",  isNonRegistered ? 1 : 0);
                    _db.AddParameter(cmd, "p_Remarks",          remarks);
                });
                if (result.Succeeded)
                {
                    // SP already inserts the canonical Notifications row (founder only,
                    // NotifType='ORG_APPROVED') — push-only here, broadcast to ALL org
                    // admins (broader reach than the SP's founder-only insert).
                    var pushBody = string.IsNullOrWhiteSpace(remarks)
                        ? "Your organisation has been approved. You can now start managing projects and volunteers."
                        : $"Your organisation has been approved. Note from admin: {remarks.Trim()}";
                    _ = PushOnlyOrgAdminAsync(orgId, "🎉 NGO Approved!", pushBody, "ORG_APPROVED", orgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApproveOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SetOrgNonRegisteredAsync(int orgId, bool isNonRegistered, string? remarks, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_SetNonRegistered", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_IsNonRegistered",  isNonRegistered ? 1 : 0);
                    _db.AddParameter(cmd, "p_Remarks",          remarks);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                if (result.Succeeded)
                {
                    // SP inserts Notifications row for founder only — push to all org admins here
                    var title    = isNonRegistered ? "Organisation Marked as Non-Registered" : "Organisation Registration Status Updated";
                    var pushBody = isNonRegistered
                        ? "Your organisation has been classified as non-registered by the platform admin."
                        : "Your organisation registration status has been updated by the platform admin.";
                    if (!string.IsNullOrWhiteSpace(remarks))
                        pushBody = $"{pushBody} Note from admin: {remarks.Trim()}";
                    _ = PushOnlyOrgAdminAsync(orgId, title, pushBody, "ORG_STATUS_UPDATE", orgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SetOrgNonRegisteredAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RejectOrgAsync(int orgId, string reason, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Reject", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           reason);
                });
                if (result.Succeeded)
                {
                    var rejectBody = string.IsNullOrWhiteSpace(reason)
                        ? "Your organisation registration was not approved. Please review your details and resubmit."
                        : $"Your organisation registration was not approved. Reason: {reason}";
                    _ = FireOrgAdminNotifAsync(orgId, "NGO Registration Not Approved",
                        rejectBody, "ORG_REJECTED", orgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RejectOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RequestOrgUpdateAsync(int orgId, string reason, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_RequestUpdate", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           reason);
                });
                if (result.Succeeded)
                    // SP already inserts the canonical Notifications row (NotifType=
                    // 'ORG_UPDATE_REQUIRED') — push-only here, matching the
                    // RequestMemberUpdateAsync pattern, to avoid the duplicate-row
                    // dual-write bug fixed earlier for the member flow.
                    _ = PushOnlyOrgAdminAsync(orgId, "⚠️ Action Required: Update Your Organisation",
                        reason, "ORG_UPDATE_REQUIRED", orgId, "ORG");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RequestOrgUpdateAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SuspendOrgAsync(int orgId, string? reason, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Suspend", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           reason);
                });
                if (result.Succeeded)
                {
                    var suspendBody = string.IsNullOrWhiteSpace(reason)
                        ? "Your organisation has been suspended. Please contact support for details."
                        : $"Your organisation has been suspended. Reason: {reason}";
                    _ = FireOrgAdminNotifAsync(orgId, "⚠️ NGO Suspended",
                        suspendBody, "ORG_SUSPENDED", orgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SuspendOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReactivateOrgAsync(int orgId, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Reactivate", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                if (result.Succeeded)
                    _ = FireOrgAdminNotifAsync(orgId, "✅ NGO Reactivated",
                        "Your NGO has been reactivated. You can now manage projects and members again.",
                        "ORG_REACTIVATED", orgId, "ORG");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReactivateOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetOrgStatusHistoryAsync(int orgId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("SuperAdmin_Org_GetStatusHistory", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgStatusHistoryAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ══════════════════════════════════════════════════════════════
        // Members review (cross-NGO oversight)
        // ══════════════════════════════════════════════════════════════

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetMemberListAsync(string? orgIds, string? search, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("SuperAdmin_User_GetList", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgIds",     orgIds);
                    _db.AddParameter(cmd, "p_Search",     search);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                // userToken added per row (2026-08-24) — same rationale as
                // orgToken on GetOrgListAsync. userId stays in the row too.
                foreach (var row in paged.Items)
                    row["userToken"] = _tokens.Encrypt("USER", row.Get<int>("userId"));
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMemberListAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        /// <summary>
        /// SuperAdmin_User_GetFullProfile returns 5 result sets (core profile, skills,
        /// interests, badges, other-orgs) — same multi-result-set pattern as Sos_GetById.
        /// None of the 8 BaseDal helpers cover 5 sets, so this reads the DataSet directly.
        /// </summary>
        public async Task<ApiResponse<DynamicRow>> GetMemberProfileAsync(int userId)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("SuperAdmin_User_GetFullProfile", conn);
                _db.AddParameter(cmd, "p_UserId", userId);

                var ds = await _db.FillDataSetAsync(cmd);

                if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return ApiResponse<DynamicRow>.Failure("Member not found.", "MEMBER_NOT_FOUND");

                var profile = new DynamicRow(ds.Tables[0].Rows[0]);

                var skills = new List<string>();
                if (ds.Tables.Count > 1)
                    foreach (DataRow r in ds.Tables[1].Rows)
                        skills.Add(Col<string>(r, "SkillName"));
                profile["skills"] = skills;

                var interests = new List<string>();
                if (ds.Tables.Count > 2)
                    foreach (DataRow r in ds.Tables[2].Rows)
                        interests.Add(Col<string>(r, "ValueName"));
                profile["interests"] = interests;

                var badges = new List<string>();
                if (ds.Tables.Count > 3)
                    foreach (DataRow r in ds.Tables[3].Rows)
                        badges.Add(Col<string>(r, "BadgeType"));
                profile["badges"] = badges;

                var otherOrgs = new List<DynamicRow>();
                if (ds.Tables.Count > 4)
                    foreach (DataRow r in ds.Tables[4].Rows)
                        otherOrgs.Add(new DynamicRow(r));
                profile["otherOrgs"] = otherOrgs;

                profile["userToken"] = _tokens.Encrypt("USER", userId);
                return ApiResponse<DynamicRow>.Success(profile);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMemberProfileAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetMemberDocumentsAsync(int userId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("SuperAdmin_User_GetDocuments", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                foreach (var row in list)
                    row["userDocumentToken"] = _tokens.Encrypt("USERDOC", row.Get<int>("userDocumentId"));
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMemberDocumentsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyMemberDocumentAsync(int userDocumentId, bool isVerified, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_UserDocument_Verify", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserDocumentId",   userDocumentId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_IsVerified",       isVerified);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyMemberDocumentAsync failed UserDocumentId={Id}", userDocumentId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyMemberProfileAsync(int userId, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_VerifyProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           userId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                if (result.Succeeded)
                    // SP already inserts the canonical Notifications row (NotifType matches) — push-only.
                    _ = PushOnlyUserAsync(userId, "✅ Profile Verified",
                        "Your profile has been verified! Your verified badge is now visible to NGOs.",
                        "PROFILE_VERIFIED", userId, "USER");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyMemberProfileAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RequestMemberUpdateAsync(int userId, string reason, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_RequestUpdate", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           userId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           reason);
                });
                if (result.Succeeded)
                    // SP already inserts the canonical Notifications row with the REAL
                    // reason text (NotifType='PROFILE_UPDATE_REQUIRED') — push-only here,
                    // and the push body now carries the actual reason instead of generic
                    // text, so the user sees it immediately instead of only in-app later.
                    _ = PushOnlyUserAsync(userId, "⚠️ Action Required: Update Your Profile",
                        reason, "PROFILE_UPDATE_REQUIRED", userId, "USER");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RequestMemberUpdateAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SuspendMemberAsync(int userId, SuspendMemberRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_Suspend", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           userId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           request.Reason);
                });
                if (result.Succeeded)
                {
                    // SP already inserts the canonical Notifications row with the real
                    // reason as Body (NotifType matches) — push-only, and the push body
                    // now carries the real reason too instead of generic text.
                    var suspendPushBody = string.IsNullOrWhiteSpace(request.Reason)
                        ? "Your account has been suspended. Please contact support for assistance."
                        : request.Reason;
                    _ = PushOnlyUserAsync(userId, "⚠️ Account Suspended",
                        suspendPushBody, "ACCOUNT_SUSPENDED", userId, "USER");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SuspendMemberAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReactivateMemberAsync(int userId, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_Reactivate", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           userId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                if (result.Succeeded)
                    _ = FireUserNotifAsync(userId, "✅ Account Reactivated",
                        "Your account has been reactivated. Welcome back to Ripple Hub!",
                        "ACCOUNT_REACTIVATED", userId, "USER");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReactivateMemberAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ══════════════════════════════════════════════════════════════
        // Dashboard
        // ══════════════════════════════════════════════════════════════

        public async Task<ApiResponse<DynamicRow>> GetDashboardAsync()
        {
            try
            {
                var kpis   = await ExecuteDynamicGetAsync("SuperAdmin_Dashboard_GetKpis");
                var recent = await ExecuteDynamicListAsync("SuperAdmin_Org_GetRecent", cmd =>
                {
                    _db.AddParameter(cmd, "p_Limit", 10);
                });

                var data = kpis ?? new DynamicRow();
                data["recentOrgs"] = recent;

                return ApiResponse<DynamicRow>.Success(data);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDashboardAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ══════════════════════════════════════════════════════════════
        // Lookup management
        // ══════════════════════════════════════════════════════════════

        public async Task<ApiResponse<List<DynamicRow>>> GetLookupTypesAsync()
        {
            try
            {
                var list = await ExecuteDynamicListAsync("SuperAdmin_LookupType_GetList");
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetLookupTypesAsync failed");
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetLookupValuesAsync(int lookupTypeId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("SuperAdmin_LookupValue_GetByType", cmd =>
                {
                    _db.AddParameter(cmd, "p_LookupTypeId", lookupTypeId);
                });
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetLookupValuesAsync failed LookupTypeId={Id}", lookupTypeId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AddLookupTypeAsync(AddLookupTypeRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_LookupType_Add", cmd =>
                {
                    _db.AddParameter(cmd, "p_TypeCode",         request.TypeCode);
                    _db.AddParameter(cmd, "p_TypeName",         request.TypeName);
                    _db.AddParameter(cmd, "p_Description",      request.Description);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "LOOKUPTYPE_ADD_FAILED");

                var data = new DynamicRow();
                data["lookupTypeId"] = Col<int>(result.Row!, "LookupTypeId");
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddLookupTypeAsync failed TypeCode={Code}", request.TypeCode);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateLookupTypeAsync(UpdateLookupTypeRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_LookupType_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_LookupTypeId",     request.LookupTypeId);
                    _db.AddParameter(cmd, "p_TypeName",         request.TypeName);
                    _db.AddParameter(cmd, "p_Description",      request.Description);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateLookupTypeAsync failed LookupTypeId={Id}", request.LookupTypeId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> AddLookupValueAsync(AddLookupValueRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_LookupValue_Add", cmd =>
                {
                    _db.AddParameter(cmd, "p_LookupTypeId",     request.LookupTypeId);
                    _db.AddParameter(cmd, "p_ValueCode",        request.ValueCode);
                    _db.AddParameter(cmd, "p_ValueName",        request.ValueName);
                    _db.AddParameter(cmd, "p_Description",      request.Description);
                    _db.AddParameter(cmd, "p_OrderNo",          request.OrderNo);
                    _db.AddParameter(cmd, "p_IsDefault",        request.IsDefault);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "LOOKUPVALUE_ADD_FAILED");

                var data = new DynamicRow();
                data["lookupValueId"] = Col<int>(result.Row!, "LookupValueId");
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddLookupValueAsync failed ValueCode={Code}", request.ValueCode);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateLookupValueAsync(UpdateLookupValueRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_LookupValue_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_LookupValueId",    request.LookupValueId);
                    _db.AddParameter(cmd, "p_ValueName",        request.ValueName);
                    _db.AddParameter(cmd, "p_Description",      request.Description);
                    _db.AddParameter(cmd, "p_OrderNo",          request.OrderNo);
                    _db.AddParameter(cmd, "p_IsDefault",        request.IsDefault);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateLookupValueAsync failed LookupValueId={Id}", request.LookupValueId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SetLookupValueActiveAsync(SetLookupValueActiveRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_LookupValue_SetActive", cmd =>
                {
                    _db.AddParameter(cmd, "p_LookupValueId",    request.LookupValueId);
                    _db.AddParameter(cmd, "p_IsActive",         request.IsActive);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SetLookupValueActiveAsync failed LookupValueId={Id}", request.LookupValueId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Notification helpers ──────────────────────────────────────────────────

        private async Task FireUserNotifAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                await _notif.CreateAsync(userId, title, body, notifType, refId, refType);
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SuperAdminDal.FireUserNotifAsync failed"); }
        }

        private async Task FireOrgAdminNotifAsync(int orgId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var admins = await _notif.GetAdminsWithTokensAsync(orgId);
                if (admins.Count == 0) return;

                // Persist to Notifications inbox for every FOUNDER/ADMIN — appears in bell icon + notification page
                await Task.WhenAll(admins.Select(a =>
                    _notif.CreateAsync(a.UserId, title, body, notifType, refId, refType, orgId)));

                // FCM push
                var tokens = admins.Select(a => a.Token).ToList();
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SuperAdminDal.FireOrgAdminNotifAsync failed OrgId={OrgId}", orgId); }
        }

        // Push-only variants (2026-08-23) — for actions whose stored procedure ALREADY
        // inserts the canonical Notifications row (SuperAdmin_User_RequestUpdate,
        // _VerifyProfile, _Suspend, Org_Approve). Previously these callers ALSO called
        // FireUserNotifAsync/FireOrgAdminNotifAsync, which inserted a SECOND duplicate
        // row — for RequestMemberUpdateAsync with a different NotifType than the SP's
        // own insert, which broke in-app notification tap navigation, and for the
        // others a same-type but still-duplicate row. These variants send the FCM
        // push only, leaving the SP's insert as the single source of truth.
        private async Task PushOnlyUserAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SuperAdminDal.PushOnlyUserAsync failed"); }
        }

        private async Task PushOnlyOrgAdminAsync(int orgId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var admins = await _notif.GetAdminsWithTokensAsync(orgId);
                if (admins.Count == 0) return;
                var tokens = admins.Select(a => a.Token).ToList();
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "SuperAdminDal.PushOnlyOrgAdminAsync failed OrgId={OrgId}", orgId); }
        }

        // ── Org project permissions ───────────────────────────────────────────

        public async Task<ApiResponse> UpdateOrgProjectPermissionsAsync(
            int orgId, UpdateOrgProjectPermissionsRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_UpdateOrgProjectPermissions", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",              orgId);
                    _db.AddParameter(cmd, "p_CanCreateRecurring",  request.CanCreateRecurring ? 1 : 0);
                    _db.AddParameter(cmd, "p_CanCreateFlexible",   request.CanCreateFlexible  ? 1 : 0);
                    _db.AddParameter(cmd, "p_OrgMaxVolunteers",    (object?)request.OrgMaxVolunteers ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_UpdatedBy",           superAdminUserId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateOrgProjectPermissionsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred while updating project permissions.", "INTERNAL_ERROR");
            }
        }

        // ── Proactive Member + Organisation onboarding ───────────────────────

        public async Task<ApiResponse<DynamicRow>> CreateMemberWithOrgAsync(
            CreateMemberWithOrgRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_CreateMemberWithOrg", cmd =>
                {
                    _db.AddParameter(cmd, "p_FirstName",        request.FirstName);
                    _db.AddParameter(cmd, "p_LastName",         request.LastName);
                    _db.AddParameter(cmd, "p_Email",            request.Email);
                    _db.AddParameter(cmd, "p_Mobile",           request.Mobile);
                    _db.AddParameter(cmd, "p_CountryCode",      request.CountryCode);
                    _db.AddParameter(cmd, "p_GenderLkpId",      (object?)request.GenderLkpId ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_DateOfBirth",      (object?)request.DateOfBirth ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_ProfilePhoto",     request.ProfilePhoto);
                    _db.AddParameter(cmd, "p_AddressLine1",     request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",     request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",             request.City);
                    _db.AddParameter(cmd, "p_State",            request.State);
                    _db.AddParameter(cmd, "p_Pincode",          request.Pincode);
                    _db.AddParameter(cmd, "p_Country",          request.Country);

                    _db.AddParameter(cmd, "p_OrgMode",          request.OrgMode);
                    _db.AddParameter(cmd, "p_ExistingOrgId",    (object?)request.ExistingOrgId ?? DBNull.Value);

                    _db.AddParameter(cmd, "p_OrgName",          request.OrgName);
                    _db.AddParameter(cmd, "p_OrgTypeLkpId",     (object?)request.OrgTypeLkpId ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_RegNumber",        request.RegNumber);
                    _db.AddParameter(cmd, "p_Category",         request.Category);
                    _db.AddParameter(cmd, "p_About",            request.About);
                    _db.AddParameter(cmd, "p_Mission",          request.Mission);
                    _db.AddParameter(cmd, "p_Vision",           request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",          request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",     request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactPhone",     request.ContactPhone);
                    _db.AddParameter(cmd, "p_Website",          request.Website);
                    _db.AddParameter(cmd, "p_OrgAddressLine1",  request.OrgAddressLine1);
                    _db.AddParameter(cmd, "p_OrgAddressLine2",  request.OrgAddressLine2);
                    _db.AddParameter(cmd, "p_OrgCity",          request.OrgCity);
                    _db.AddParameter(cmd, "p_OrgState",         request.OrgState);
                    _db.AddParameter(cmd, "p_OrgPincode",       request.OrgPincode);
                    _db.AddParameter(cmd, "p_OrgCountry",       request.OrgCountry);

                    _db.AddParameter(cmd, "p_RoleCode",         request.RoleCode);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "VALIDATION_ERROR");

                var userId = Col<int>(result.Row!, "UserId");
                var orgId  = Col<int>(result.Row!, "OrgId");

                // Reuses the same encrypted-token mechanism as ShareController/
                // CertificateDal — no new secure-link plumbing needed. Entity type
                // "ORG" is exactly what PublicController.GetOrgPreview decrypts.
                var token = _tokens.Encrypt("ORG", orgId);

                var data = new DynamicRow
                {
                    ["userId"]        = userId,
                    ["orgId"]         = orgId,
                    ["orgShareToken"] = token,
                    ["orgShareUrl"]   = $"{BaseUrl}/organisation/{token}",
                };

                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreateMemberWithOrgAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred while creating the member.", "INTERNAL_ERROR");
            }
        }

        // ── Post-creation profile correction ─────────────────────────────────

        public async Task<ApiResponse<DynamicRow>> UpdateOrgProfileAsync(
            int orgId, UpdateOrgProfileRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_UpdateProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",           orgId);
                    _db.AddParameter(cmd, "p_OrgName",         request.OrgName);
                    _db.AddParameter(cmd, "p_OrgTypeLkpId",    request.OrgTypeLkpId);
                    _db.AddParameter(cmd, "p_RegNumber",       request.RegNumber);
                    _db.AddParameter(cmd, "p_RegistrationDate", (object?)request.RegistrationDate ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_Category",        request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson",   request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",           request.About);
                    _db.AddParameter(cmd, "p_Mission",         request.Mission);
                    _db.AddParameter(cmd, "p_Vision",          request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",         request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",    request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactPhone",    request.ContactPhone);
                    _db.AddParameter(cmd, "p_Website",         request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",    request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",    request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",            request.City);
                    _db.AddParameter(cmd, "p_State",           request.State);
                    _db.AddParameter(cmd, "p_Pincode",         request.Pincode);
                    _db.AddParameter(cmd, "p_Country",         request.Country);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "VALIDATION_ERROR");

                var data = new DynamicRow { ["orgId"] = orgId };
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateOrgProfileAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred while updating the organisation.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> UpdateMemberProfileAsync(
            int userId, UpdateMemberProfileRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_UpdateProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_FirstName",       request.FirstName);
                    _db.AddParameter(cmd, "p_LastName",        request.LastName);
                    _db.AddParameter(cmd, "p_Email",           request.Email);
                    _db.AddParameter(cmd, "p_Mobile",          request.Mobile);
                    _db.AddParameter(cmd, "p_CountryCode",     request.CountryCode);
                    _db.AddParameter(cmd, "p_GenderLkpId",     (object?)request.GenderLkpId ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_DateOfBirth",     (object?)request.DateOfBirth ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_ProfilePhoto",    request.ProfilePhoto);
                    _db.AddParameter(cmd, "p_AddressLine1",    request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",    request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",            request.City);
                    _db.AddParameter(cmd, "p_State",           request.State);
                    _db.AddParameter(cmd, "p_Pincode",         request.Pincode);
                    _db.AddParameter(cmd, "p_Country",         request.Country);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "VALIDATION_ERROR");

                var emailMobileLocked = Col<bool>(result.Row!, "EmailMobileLocked");
                var data = new DynamicRow { ["userId"] = userId, ["emailMobileLocked"] = emailMobileLocked };
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateMemberProfileAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred while updating the member.", "INTERNAL_ERROR");
            }
        }
    }
}

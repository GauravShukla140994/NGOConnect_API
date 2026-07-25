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
        private readonly IConfiguration   _config;
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public SuperAdminDal(IDbProvider db, IConfiguration config, INotificationDal notif, IFCMService fcm)
            : base(db)
        {
            _config = config;
            _notif  = notif;
            _fcm    = fcm;
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

                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Organisation not found.", "ORG_NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
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
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgDocumentsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyOrgDocumentAsync(VerifyOrgDocumentRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_OrgDocument_Verify", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgDocumentId",    request.OrgDocumentId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_IsVerified",       request.IsVerified);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyOrgDocumentAsync failed OrgDocumentId={Id}", request.OrgDocumentId);
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

        public async Task<ApiResponse> ApproveOrgAsync(int orgId, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Approve", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            orgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                });
                if (result.Succeeded)
                    _ = FireOrgAdminNotifAsync(orgId, "🎉 NGO Approved!",
                        "Your organisation has been approved. You can now start managing projects and volunteers.",
                        "ORG_APPROVED", orgId, "ORG");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApproveOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RejectOrgAsync(RejectOrgRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Reject", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            request.OrgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           request.Reason);
                });
                if (result.Succeeded)
                {
                    var rejectBody = string.IsNullOrWhiteSpace(request.Reason)
                        ? "Your organisation registration was not approved. Please review your details and resubmit."
                        : $"Your organisation registration was not approved. Reason: {request.Reason}";
                    _ = FireOrgAdminNotifAsync(request.OrgId, "NGO Registration Not Approved",
                        rejectBody, "ORG_REJECTED", request.OrgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RejectOrgAsync failed OrgId={OrgId}", request.OrgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SuspendOrgAsync(SuspendOrgRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_Org_Suspend", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            request.OrgId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           request.Reason);
                });
                if (result.Succeeded)
                {
                    var suspendBody = string.IsNullOrWhiteSpace(request.Reason)
                        ? "Your organisation has been suspended. Please contact support for details."
                        : $"Your organisation has been suspended. Reason: {request.Reason}";
                    _ = FireOrgAdminNotifAsync(request.OrgId, "⚠️ NGO Suspended",
                        suspendBody, "ORG_SUSPENDED", request.OrgId, "ORG");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SuspendOrgAsync failed OrgId={OrgId}", request.OrgId);
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
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMemberDocumentsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> VerifyMemberDocumentAsync(VerifyMemberDocumentRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_UserDocument_Verify", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserDocumentId",   request.UserDocumentId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_IsVerified",       request.IsVerified);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "VerifyMemberDocumentAsync failed UserDocumentId={Id}", request.UserDocumentId);
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
                    _ = FireUserNotifAsync(userId, "✅ Profile Verified",
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

        public async Task<ApiResponse> RequestMemberUpdateAsync(RequestMemberUpdateRequest request, int superAdminUserId)
        {
            try
            {
                var result = await ExecuteWriteAsync("SuperAdmin_User_RequestUpdate", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",           request.UserId);
                    _db.AddParameter(cmd, "p_SuperAdminUserId", superAdminUserId);
                    _db.AddParameter(cmd, "p_Reason",           request.Reason);
                });
                if (result.Succeeded)
                    _ = FireUserNotifAsync(request.UserId, "⚠️ Action Required: Update Your Profile",
                        "Please review and update your profile to continue using NGO Connect.",
                        "PROFILE_UPDATE_REQUIRED", request.UserId, "USER");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RequestMemberUpdateAsync failed UserId={UserId}", request.UserId);
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
                    _ = FireUserNotifAsync(userId, "⚠️ Account Suspended",
                        "Your account has been suspended. Please contact support for assistance.",
                        "ACCOUNT_SUSPENDED", userId, "USER");
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
                        "Your account has been reactivated. Welcome back to NGO Connect!",
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
    }
}

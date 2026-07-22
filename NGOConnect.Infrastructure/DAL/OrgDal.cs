using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Org;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class OrgDal : BaseDal, IOrgDal
    {
        private readonly INotificationDal _notif;
        private readonly IFCMService      _fcm;

        public OrgDal(IDbProvider db, INotificationDal notif, IFCMService fcm)
            : base(db) { _notif = notif; _fcm = fcm; }

        public async Task<ApiResponse<DynamicRow>> RegisterAsync(int userId, RegisterOrgRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Register", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgName",        request.OrgName);
                    _db.AddParameter(cmd, "p_RegistrationNo", request.RegistrationNumber);   // SP uses p_RegistrationNo
                    _db.AddParameter(cmd, "p_OrgTypeLkpId",   request.OrgTypeLkpId);
                    _db.AddParameter(cmd, "p_Category",       request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson",  request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",          request.About);
                    _db.AddParameter(cmd, "p_Mission",        request.Mission);
                    _db.AddParameter(cmd, "p_Vision",         request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",        request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",   request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactPhone",   request.ContactPhone);
                    _db.AddParameter(cmd, "p_Website",        request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",   request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",   request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",           request.City);
                    _db.AddParameter(cmd, "p_State",          request.State);
                    _db.AddParameter(cmd, "p_Pincode",        request.Pincode);
                    _db.AddParameter(cmd, "p_Country",        request.Country);
                    _db.AddParameter(cmd, "p_Is80GEligible",  request.Is80GEligible ? 1 : 0);
                    _db.AddParameter(cmd, "p_Is12AEligible",  request.Is12AEligible ? 1 : 0);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "ORG_REGISTER_FAILED");

                var orgId = Col<int>(result.Row!, "OrgId");
                var row = await ExecuteDynamicGetAsync("Org_GetProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });

                return ApiResponse<DynamicRow>.Success(row!, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RegisterAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetProfileAsync(int orgId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Org_GetProfile", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetProfileAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetPublicPreviewAsync(int orgId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Org_GetPublicPreview", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPublicPreviewAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateAsync(int orgId, int userId, UpdateOrgRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",         orgId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_OrgName",       request.OrgName);
                    _db.AddParameter(cmd, "p_Category",      request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson", request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",         request.About);
                    _db.AddParameter(cmd, "p_Mission",       request.Mission);
                    _db.AddParameter(cmd, "p_Vision",        request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",       request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",  request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactPhone",  request.ContactPhone);
                    _db.AddParameter(cmd, "p_Website",       request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",  request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",  request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",          request.City);
                    _db.AddParameter(cmd, "p_State",         request.State);
                    _db.AddParameter(cmd, "p_Pincode",       request.Pincode);
                    _db.AddParameter(cmd, "p_Country",       request.Country);
                    _db.AddParameter(cmd, "p_Is80GEligible",  request.Is80GEligible.HasValue ? (int?)(request.Is80GEligible.Value ? 1 : 0) : null);
                    _db.AddParameter(cmd, "p_Is12AEligible",  request.Is12AEligible.HasValue ? (int?)(request.Is12AEligible.Value ? 1 : 0) : null);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // v4.5 — founder resubmits a rejected org for another review. Brand-new SP
        // (Org_Resubmit) — does not touch Org_Update.
        public async Task<ApiResponse> ResubmitAsync(int orgId, int userId, ResubmitOrgRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Resubmit", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",         orgId);
                    _db.AddParameter(cmd, "p_UserId",        userId);
                    _db.AddParameter(cmd, "p_OrgName",       request.OrgName);
                    _db.AddParameter(cmd, "p_Category",      request.Category);
                    _db.AddParameter(cmd, "p_ContactPerson", request.ContactPerson);
                    _db.AddParameter(cmd, "p_About",         request.About);
                    _db.AddParameter(cmd, "p_Mission",       request.Mission);
                    _db.AddParameter(cmd, "p_Vision",        request.Vision);
                    _db.AddParameter(cmd, "p_LogoUrl",       request.LogoUrl);
                    _db.AddParameter(cmd, "p_ContactEmail",  request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactPhone",  request.ContactPhone);
                    _db.AddParameter(cmd, "p_Website",       request.Website);
                    _db.AddParameter(cmd, "p_AddressLine1",  request.AddressLine1);
                    _db.AddParameter(cmd, "p_AddressLine2",  request.AddressLine2);
                    _db.AddParameter(cmd, "p_City",          request.City);
                    _db.AddParameter(cmd, "p_State",         request.State);
                    _db.AddParameter(cmd, "p_Pincode",       request.Pincode);
                    _db.AddParameter(cmd, "p_Country",       request.Country);
                    _db.AddParameter(cmd, "p_Is80GEligible",  request.Is80GEligible ? 1 : 0);
                    _db.AddParameter(cmd, "p_Is12AEligible",  request.Is12AEligible ? 1 : 0);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ResubmitAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<OrgDashboardModel>> GetDashboardAsync(int orgId)
        {
            try
            {
                var row = await ExecuteGetAsync("Org_GetDashboard",
                    r => new OrgDashboardModel
                    {
                        TotalMembers        = Col<int>(r,     "TotalMembers"),
                        NewMembersThisMonth = Col<int>(r,     "NewMembersThisMonth"),
                        ActiveVolunteers    = Col<int>(r,     "ActiveVolunteers"),
                        ActiveRatePct       = Col<decimal>(r, "ActiveRatePct"),
                        VolunteerHoursMonth = Col<decimal>(r, "VolunteerHoursMonth"),
                        ActiveProjects      = Col<int>(r,     "ActiveProjects"),
                        PendingApplications        = Col<int>(r, "PendingApplications"),
                        PendingProjectApplications = Col<int>(r, "PendingProjectApplications"),
                        FollowerCount              = Col<int>(r, "FollowerCount"),
                    },
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));

                return row is null
                    ? ApiResponse<OrgDashboardModel>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<OrgDashboardModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDashboardAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<OrgDashboardModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<OrgListItemModel>>> ListAsync(
            int pageNumber, int pageSize, string? keyword = null, string? category = null,
            decimal? lat = null, decimal? lng = null)
        {
            try
            {
                // Org_List always returns APPROVED orgs; returns 2 result sets for pagination
                // p_Lat / p_Lng optional — when provided, SP sorts nearest-first via Haversine
                var paged = await ExecutePagedListAsync("Org_List", MapOrgListItem, pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_Keyword",    keyword);
                    _db.AddParameter(cmd, "p_Category",   category);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                    // p_Lat / p_Lng removed — Org_List SP does not accept these params
                });

                return ApiResponse<PagedResult<OrgListItemModel>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ListAsync failed");
                return ApiResponse<PagedResult<OrgListItemModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<RecommendedOrgModel>>> GetRecommendedAsync(int userId)
        {
            try
            {
                var rows = await ExecuteListAsync("Org_ListRecommended",
                    r => new RecommendedOrgModel
                    {
                        OrgId       = Col<int>(r,      "OrgId"),
                        OrgName     = Col<string>(r,   "OrgName")   ?? string.Empty,
                        Category    = Col<string>(r,   "Category"),
                        LogoUrl     = Col<string>(r,   "LogoUrl"),
                        City        = Col<string>(r,   "City"),
                        State       = Col<string>(r,   "State"),
                        MemberCount = Col<int>(r,      "MemberCount"),
                        AvgRating   = Col<decimal>(r,  "AvgRating"),
                        Latitude    = ColNullable<decimal>(r, "Latitude"),
                        Longitude   = ColNullable<decimal>(r, "Longitude"),
                        MatchScore  = Col<int>(r,      "MatchScore"),
                    },
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<RecommendedOrgModel>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetRecommendedAsync failed UserId={UserId}", userId);
                return ApiResponse<List<RecommendedOrgModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<TrendingCampaignModel>>> GetTrendingCampaignsAsync(int pageSize)
        {
            try
            {
                var rows = await ExecuteListAsync("Campaign_ListPublicTrending",
                    r => new TrendingCampaignModel
                    {
                        CampaignId   = Col<int>(r,      "CampaignId"),
                        CampaignName = Col<string>(r,   "CampaignName") ?? string.Empty,
                        OrgName      = Col<string>(r,   "OrgName")      ?? string.Empty,
                        OrgLogoUrl   = Col<string>(r,   "OrgLogoUrl"),
                        RaisedAmount = Col<decimal>(r,  "RaisedAmount"),
                        TargetAmount = Col<decimal>(r,  "TargetAmount"),
                        DonorCount   = Col<int>(r,      "DonorCount"),
                        ProgressPct  = Col<decimal>(r,  "ProgressPct"),
                        EndDate      = ColNullable<DateTime>(r, "EndDate"),
                        BannerUrl    = Col<string>(r,   "BannerUrl"),
                        IsEmergency  = Col<bool>(r,     "IsEmergency"),
                    },
                    cmd => _db.AddParameter(cmd, "p_PageSize", pageSize));
                return ApiResponse<List<TrendingCampaignModel>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetTrendingCampaignsAsync failed");
                return ApiResponse<List<TrendingCampaignModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<OrgDonationDashboardModel>> GetDonationDashboardAsync(int orgId)
        {
            try
            {
                var row = await ExecuteGetAsync("Org_GetDonationDashboard",
                    r => new OrgDonationDashboardModel
                    {
                        TotalRaisedAllTime     = Col<decimal>(r, "TotalRaisedAllTime"),
                        ThisMonthRaised        = Col<decimal>(r, "ThisMonthRaised"),
                        LastMonthRaised        = Col<decimal>(r, "LastMonthRaised"),
                        TodayRaised            = Col<decimal>(r, "TodayRaised"),
                        TodayTransactionCount  = Col<int>(r,     "TodayTransactionCount"),
                        RecurringMonthlyAmount = Col<decimal>(r, "RecurringMonthlyAmount"),
                        ActiveRecurringDonors  = Col<int>(r,     "ActiveRecurringDonors"),
                        TotalCampaigns         = Col<int>(r,     "TotalCampaigns"),
                        ActiveCampaigns        = Col<int>(r,     "ActiveCampaigns"),
                    },
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return row is null
                    ? ApiResponse<OrgDonationDashboardModel>.Failure("Organisation not found.", "NOT_FOUND")
                    : ApiResponse<OrgDonationDashboardModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDonationDashboardAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<OrgDonationDashboardModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<OrgDonorModel>>> GetDonorsAsync(
            int orgId, string tab, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecutePagedListAsync("Org_GetDonors",
                    r => new OrgDonorModel
                    {
                        UserId        = Col<int>(r,      "UserId"),
                        FullName      = Col<string>(r,   "FullName"),
                        Email         = Col<string>(r,   "Email"),
                        Phone         = Col<string>(r,   "Phone"),
                        TotalDonated  = Col<decimal>(r,  "TotalDonated"),
                        DonationCount = Col<int>(r,      "DonationCount"),
                        LastDonatedAt = Col<DateTime>(r, "LastDonatedAt"),
                        IsAnonymous   = Col<bool>(r,     "IsAnonymous"),
                        IsRecurring   = Col<bool>(r,     "IsRecurring"),
                    },
                    pageNumber, pageSize, cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",      orgId);
                        _db.AddParameter(cmd, "p_Tab",        tab);
                        _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                        _db.AddParameter(cmd, "p_PageSize",   pageSize);
                    });

                return ApiResponse<PagedResult<OrgDonorModel>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDonorsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<OrgDonorModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<OrgTransactionModel>>> GetTransactionsAsync(
            int orgId, string? statusCode, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecutePagedListAsync("Org_GetTransactions",
                    r => new OrgTransactionModel
                    {
                        TransactionId = Col<int>(r,      "TransactionId"),
                        ReadableId    = Col<string>(r,   "ReadableId")   ?? string.Empty,
                        DonorName     = Col<string>(r,   "DonorName"),
                        Amount        = Col<decimal>(r,  "Amount"),
                        NetAmount     = Col<decimal>(r,  "NetAmount"),
                        CampaignName  = Col<string>(r,   "CampaignName"),
                        StatusCode    = Col<string>(r,   "StatusCode")   ?? string.Empty,
                        StatusName    = Col<string>(r,   "StatusName")   ?? string.Empty,
                        PaymentMethod = Col<string>(r,   "PaymentMethod"),
                        CreatedAt     = Col<DateTime>(r, "CreatedAt"),
                        IsAnonymous   = Col<bool>(r,     "IsAnonymous"),
                    },
                    pageNumber, pageSize, cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",      orgId);
                        _db.AddParameter(cmd, "p_StatusCode", statusCode);
                        _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                        _db.AddParameter(cmd, "p_PageSize",   pageSize);
                    });

                return ApiResponse<PagedResult<OrgTransactionModel>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetTransactionsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<OrgTransactionModel>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<OrgVolunteerProfileModel>> GetVolunteerProfileAsync(int orgId, int userId)
        {
            try
            {
                var row = await ExecuteGetAsync("Org_GetVolunteerProfile",
                    r => new OrgVolunteerProfileModel
                    {
                        UserId         = Col<int>(r,      "UserId"),
                        FullName       = Col<string>(r,   "FullName"),
                        City           = Col<string>(r,   "City"),
                        Occupation     = Col<string>(r,   "Occupation"),
                        ProfilePhoto   = Col<string>(r,   "ProfilePhoto"),
                        TotalHours     = Col<decimal>(r,  "TotalHours"),
                        ProjectCount   = Col<int>(r,      "ProjectCount"),
                        OrgCount       = Col<int>(r,      "OrgCount"),
                        ReliabilityPct = Col<decimal>(r,  "ReliabilityPct"),
                        AvgRating      = Col<decimal>(r,  "AvgRating"),
                        PeerRating     = Col<decimal>(r,  "PeerRating"),
                        NoShowCount    = Col<int>(r,      "NoShowCount"),
                        ExcusedCount   = Col<int>(r,      "ExcusedCount"),
                        ComplaintCount = Col<int>(r,      "ComplaintCount"),
                        RoleCode       = Col<string>(r,   "RoleCode"),
                        RoleName       = Col<string>(r,   "RoleName"),
                        StatusCode     = Col<string>(r,   "StatusCode"),
                        StatusName     = Col<string>(r,   "StatusName"),
                        JoinedAt       = ColNullable<DateTime>(r, "JoinedAt"),
                    },
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",  orgId);
                        _db.AddParameter(cmd, "p_UserId", userId);
                    });
                return row is null
                    ? ApiResponse<OrgVolunteerProfileModel>.Failure("Volunteer not found.", "NOT_FOUND")
                    : ApiResponse<OrgVolunteerProfileModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetVolunteerProfileAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse<OrgVolunteerProfileModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<OrgMemberImpactModel>> GetMemberImpactAsync(int orgId, int userId)
        {
            try
            {
                var row = await ExecuteGetAsync("Org_GetMemberImpact",
                    r => new OrgMemberImpactModel
                    {
                        UserId         = Col<int>(r,     "UserId"),
                        FullName       = Col<string>(r,  "FullName"),
                        Occupation     = Col<string>(r,  "Occupation"),
                        City           = Col<string>(r,  "City"),
                        RoleName       = Col<string>(r,  "RoleName"),
                        ImpactScore    = Col<int>(r,     "ImpactScore"),
                        ReliabilityPct = Col<decimal>(r, "ReliabilityPct"),
                        TotalHours     = Col<decimal>(r, "TotalHours"),
                        ProjectCount   = Col<int>(r,     "ProjectCount"),
                        OrgCount       = Col<int>(r,     "OrgCount"),
                        BadgeCount     = Col<int>(r,     "BadgeCount"),
                        NoShowCount    = Col<int>(r,     "NoShowCount"),
                        ComplaintCount = Col<int>(r,     "ComplaintCount"),
                    },
                    cmd =>
                    {
                        _db.AddParameter(cmd, "p_OrgId",  orgId);
                        _db.AddParameter(cmd, "p_UserId", userId);
                    });
                return row is null
                    ? ApiResponse<OrgMemberImpactModel>.Failure("Member not found.", "NOT_FOUND")
                    : ApiResponse<OrgMemberImpactModel>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMemberImpactAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse<OrgMemberImpactModel>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AwardBadgeAsync(int orgId, int awardedBy, AwardBadgeRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("UserBadge_Award", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",    request.UserId);
                    _db.AddParameter(cmd, "p_BadgeLkpId", request.BadgeLkpId);
                    _db.AddParameter(cmd, "p_AwardedBy", awardedBy);
                    _db.AddParameter(cmd, "p_OrgId",     orgId);
                    _db.AddParameter(cmd, "p_ProjectId", request.ProjectId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwardBadgeAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ExcuseNoShowAsync(int orgId, int adminUserId, ExcuseNoShowRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Attendance_ExcuseNoShow", cmd =>
                {
                    _db.AddParameter(cmd, "p_AttendanceId", request.AttendanceId);
                    _db.AddParameter(cmd, "p_OrgId",        orgId);
                    _db.AddParameter(cmd, "p_ExcusedBy",    adminUserId);
                });
                if (result.Succeeded)
                {
                    var userId    = Col<int?>(result.Row!, "UserId");
                    var projectId = Col<int?>(result.Row!, "ProjectId");
                    if (userId.HasValue)
                        _ = FireUserNotifAsync(userId.Value, "✅ No-Show Excused",
                            "Your no-show has been excused by the admin. Your reliability score will not be affected.",
                            "NO_SHOW_EXCUSED", projectId, "PROJECT");
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ExcuseNoShowAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateMemberRoleAsync(int orgId, int updatedBy, UpdateMemberRoleRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_UpdateMemberRole", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",     orgId);
                    _db.AddParameter(cmd, "p_MemberId",  request.MemberId);
                    _db.AddParameter(cmd, "p_RoleCode",  request.RoleCode);
                    _db.AddParameter(cmd, "p_UpdatedBy", updatedBy);
                });
                if (result.Succeeded)
                {
                    var userId = Col<int?>(result.Row!, "UserId");
                    if (userId.HasValue)
                        _ = FireUserNotifAsync(userId.Value, "🔄 Role Updated",
                            $"Your role in the organisation has been updated to {request.RoleCode.ToLower().Replace("_", " ")}.",
                            "MEMBER_ROLE_CHANGED", orgId, "ORG", orgId);
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateMemberRoleAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Private mapper helpers ────────────────────────────────────────────────

        private OrgListItemModel MapOrgListItem(System.Data.DataRow r) => new()
        {
            OrgId       = Col<int>(r,     "OrgId"),
            OrgName     = Col<string>(r,  "OrgName")   ?? string.Empty,
            Category    = Col<string>(r,  "Category"),
            LogoUrl     = Col<string>(r,  "LogoUrl"),
            City        = Col<string>(r,  "City"),
            State       = Col<string>(r,  "State"),
            MemberCount = Col<int>(r,     "MemberCount"),
            AvgRating   = Col<decimal>(r, "AvgRating"),
            Latitude    = ColNullable<decimal>(r, "Latitude"),
            Longitude   = ColNullable<decimal>(r, "Longitude"),
        };

        public async Task<ApiResponse<List<DynamicRow>>> GetMembersAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_GetMembers",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMembersAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AddMemberAsync(int orgId, int requestedBy, AddMemberRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_AddMember", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",    orgId);
                    _db.AddParameter(cmd, "p_UserId",   request.UserId);
                    _db.AddParameter(cmd, "p_RoleCode", request.RoleCode);
                    _db.AddParameter(cmd, "p_AddedBy",  requestedBy);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AddMemberAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RemoveMemberAsync(int orgId, int userId, int requestedBy)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_RemoveMember", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",     orgId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                    _db.AddParameter(cmd, "p_RemovedBy", requestedBy);
                });
                if (result.Succeeded)
                    _ = FireUserNotifAsync(userId, "Membership Update", "Your membership has been removed from an organisation.", "MEMBER_REMOVED", orgId, "ORG", orgId);
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RemoveMemberAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> RequestMembershipAsync(int orgId, int userId, RequestMembershipRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_RequestMembership", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",             orgId);
                    _db.AddParameter(cmd, "p_UserId",            userId);
                    _db.AddParameter(cmd, "p_PrevNgoExperience", request.PrevNgoExperience);
                    _db.AddParameter(cmd, "p_VolunteerSkills",   request.VolunteerSkills);
                    _db.AddParameter(cmd, "p_AreasOfInterest",   request.AreasOfInterest);
                    _db.AddParameter(cmd, "p_WhyJoin",           request.WhyJoin);
                });
                if (result.Succeeded)
                    _ = FireAdminNotifAsync(orgId, "New Membership Request", "A volunteer wants to join your organisation.", "MEMBERSHIP_REQUEST", orgId, "ORG");
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "RequestMembershipAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReviewMembershipAsync(int reviewedBy, ReviewMembershipRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_ReviewMembership", cmd =>
                {
                    _db.AddParameter(cmd, "p_RequestId",  request.MembershipRequestId);
                    _db.AddParameter(cmd, "p_ReviewedBy", reviewedBy);
                    _db.AddParameter(cmd, "p_StatusCode", request.StatusCode);
                    _db.AddParameter(cmd, "p_ReviewNote", request.AdminNotes);
                });
                if (result.Succeeded && result.Row is not null)
                {
                    var applicantUserId = Col<int>(result.Row, "ApplicantUserId");
                    var orgId           = Col<int>(result.Row, "OrgId");
                    var isApproved = request.StatusCode?.Equals("APPROVED", StringComparison.OrdinalIgnoreCase) == true;
                    if (isApproved)
                        _ = FireUserNotifAsync(applicantUserId, "Membership Approved 🎉", "Welcome! You are now a member of the organisation.", "MEMBERSHIP_APPROVED", orgId, "ORG", orgId);
                    else
                        _ = FireUserNotifAsync(applicantUserId, "Membership Update", "Your membership request was not approved at this time.", "MEMBERSHIP_REJECTED", orgId, "ORG", orgId);
                }
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReviewMembershipAsync failed ReviewedBy={ReviewedBy}", reviewedBy);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetPendingMembersAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_GetPendingMembers", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_PageNumber", 1);
                    _db.AddParameter(cmd, "p_PageSize",   100);  // all pending requests (typically small)
                });
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPendingMembersAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateMemberPermissionsAsync(int orgId, int updatedBy, UpdateMemberPermissionsRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_UpdateMemberPermissions", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgMemberId",          request.MemberId);
                    _db.AddParameter(cmd, "p_OrgId",                orgId);
                    _db.AddParameter(cmd, "p_UpdatedBy",            updatedBy);
                    _db.AddParameter(cmd, "p_CanPost",              request.CanPost);
                    _db.AddParameter(cmd, "p_CanComment",           request.CanComment);
                    _db.AddParameter(cmd, "p_CanCommunityPost",     request.CanCommunityPost);
                    _db.AddParameter(cmd, "p_MaxPostsPerDay",       request.MaxPostsPerDay);
                    _db.AddParameter(cmd, "p_LocationSharingLkpId", request.LocationSharingLkpId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UpdateMemberPermissionsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetAdminPostsAsync(int orgId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Org_GetAdminPosts",
                    cmd => _db.AddParameter(cmd, "p_OrgId", orgId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetAdminPostsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> PinPostAsync(int orgId, int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_PinPost", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",   postId);
                    _db.AddParameter(cmd, "p_OrgId",    orgId);
                    _db.AddParameter(cmd, "p_PinnedBy", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "PinPostAsync failed OrgId={OrgId} PostId={PostId}", orgId, postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> DeletePostAsync(int orgId, int postId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_DeletePost", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",    postId);
                    _db.AddParameter(cmd, "p_OrgId",     orgId);
                    _db.AddParameter(cmd, "p_DeletedBy", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeletePostAsync failed OrgId={OrgId} PostId={PostId}", orgId, postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ModeratePostAsync(int orgId, int postId, int userId, string action)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_ModeratePost", cmd =>
                {
                    _db.AddParameter(cmd, "p_PostId",     postId);
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_ReviewedBy", userId);
                    _db.AddParameter(cmd, "p_Action",     action);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ModeratePostAsync failed OrgId={OrgId} PostId={PostId}", orgId, postId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> FollowOrgAsync(int orgId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Follow", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FollowOrgAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UnfollowOrgAsync(int orgId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_Unfollow", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",  orgId);
                    _db.AddParameter(cmd, "p_UserId", userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UnfollowOrgAsync failed OrgId={OrgId} UserId={UserId}", orgId, userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetDocumentsAsync(int orgId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("Org_GetDocuments", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId", orgId);
                });
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDocumentsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UploadDocumentAsync(int orgId, int userId, UploadOrgDocumentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Org_UploadDocument", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",             orgId);
                    _db.AddParameter(cmd, "p_UploadedBy",        userId);
                    _db.AddParameter(cmd, "p_DocumentTypeLkpId", request.DocumentTypeLkpId);
                    _db.AddParameter(cmd, "p_FileUrl",           request.FileUrl);
                    _db.AddParameter(cmd, "p_FileName",          request.FileName);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UploadDocumentAsync failed OrgId={OrgId}", orgId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Notification helpers ──────────────────────────────────────────────────

        private async Task FireUserNotifAsync(int userId, string title, string body,
            string notifType, int? refId = null, string? refType = null, int? orgId = null)
        {
            try
            {
                await _notif.CreateAsync(userId, title, body, notifType, refId, refType, orgId);
                var tokens = await _notif.GetTokensByUserIdAsync(userId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "OrgDal.FireUserNotifAsync failed"); }
        }

        private async Task FireAdminNotifAsync(int orgId, string title, string body,
            string notifType, int? refId = null, string? refType = null)
        {
            try
            {
                var tokens = await _notif.GetAdminTokensByOrgIdAsync(orgId);
                await _fcm.SendMulticastAsync(tokens, title, body, notifType, refId, refType);
            }
            catch (Exception ex) { Log.Error(ex, "OrgDal.FireAdminNotifAsync failed"); }
        }
    }
}

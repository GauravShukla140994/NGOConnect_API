using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Donation;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class DonationDal : BaseDal, IDonationDal
    {
        public DonationDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<DynamicRow>> CreateCampaignAsync(int userId, CreateCampaignRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_CreateCampaign", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",            request.OrgId);
                    _db.AddParameter(cmd, "p_Title",            request.Title);
                    _db.AddParameter(cmd, "p_Description",      request.Description);
                    _db.AddParameter(cmd, "p_TargetAmount",     request.GoalAmount);
                    _db.AddParameter(cmd, "p_StartDate",        request.StartDate);
                    _db.AddParameter(cmd, "p_EndDate",          request.EndDate);
                    _db.AddParameter(cmd, "p_CampaignTypeLkpId", request.CampaignTypeLkpId);
                    _db.AddParameter(cmd, "p_CreatedBy",        userId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "CAMPAIGN_CREATE_FAILED");

                // Return campaignId from the write result (Donation_GetCampaignById SP not yet in setup SQL)
                var campaignId = Col<int>(result.Row!, "CampaignId");
                var data = new DynamicRow();
                data["campaignId"] = campaignId;
                data["message"]    = result.Message;
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreateCampaignAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetCampaignsAsync(int? orgId, string? keyword, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Donation_GetCampaigns", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_StatusCode", keyword);   // filter by status code (ACTIVE/COMPLETED etc); variable named 'keyword' for compat
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetCampaignsAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetCampaignByIdAsync(int campaignId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Donation_GetCampaignById",
                    cmd => _db.AddParameter(cmd, "p_CampaignId", campaignId));
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Campaign not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetCampaignByIdAsync failed CampaignId={Id}", campaignId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetDonorsAsync(int campaignId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Donation_GetDonors", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      (object?)null);   // no org context; SP filters by campaignId
                    _db.AddParameter(cmd, "p_CampaignId", campaignId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetDonorsAsync failed CampaignId={Id}", campaignId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> InitiateDonationAsync(int userId, InitiateDonationRequest request)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Donation_Donate", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",                   userId);
                    _db.AddParameter(cmd, "p_CampaignId",               request.CampaignId);
                    _db.AddParameter(cmd, "p_Amount",                   request.Amount);
                    _db.AddParameter(cmd, "p_PaymentGatewayRef",        (object?)null);   // set after Razorpay order creation
                    _db.AddParameter(cmd, "p_IsAnonymous",              request.IsAnonymous ? 1 : 0);
                    _db.AddParameter(cmd, "p_IsRecurring",              0);
                    _db.AddParameter(cmd, "p_RecurringFrequencyLkpId",  (object?)null);
                    _db.AddParameter(cmd, "p_Message",                  request.Note);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Could not initiate donation.", "DONATE_FAILED")
                    : ApiResponse<DynamicRow>.Success(row, "Donation initiated. Proceed to payment.");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "InitiateDonationAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ConfirmPaymentAsync(int userId, ConfirmPaymentRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_ConfirmPayment", cmd =>
                {
                    _db.AddParameter(cmd, "p_TransactionId",    request.DonationRef);   // Razorpay payment_id = TransactionId
                    _db.AddParameter(cmd, "p_StatusCode",       "COMPLETED");
                    _db.AddParameter(cmd, "p_GatewayResponse",  (object?)null);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ConfirmPaymentAsync failed UserId={UserId}", userId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetHistoryAsync(int userId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Donation_GetHistory", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",     userId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetHistoryAsync failed UserId={UserId}", userId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetReceiptAsync(int donationId, int userId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Donation_GetReceipt", cmd =>
                {
                    _db.AddParameter(cmd, "p_DonationId", donationId);
                    _db.AddParameter(cmd, "p_UserId",     userId);
                });
                return row is null
                    ? ApiResponse<DynamicRow>.Failure("Receipt not found.", "NOT_FOUND")
                    : ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetReceiptAsync failed DonationId={Id}", donationId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> SetupRecurringAsync(int userId, SetupRecurringRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_SetupRecurring", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",         userId);
                    _db.AddParameter(cmd, "p_OrgId",          request.OrgId);
                    _db.AddParameter(cmd, "p_CampaignId",     request.CampaignId);
                    _db.AddParameter(cmd, "p_Amount",         request.Amount);
                    _db.AddParameter(cmd, "p_FrequencyLkpId", request.FrequencyLkpId);
                    _db.AddParameter(cmd, "p_StartDate",      request.StartDate);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "RECURRING_SETUP_FAILED");

                var recurringId = Col<int>(result.Row!, "RecurringDonId");
                var data = new DynamicRow();
                data["recurringDonId"] = recurringId;
                data["message"]        = result.Message;
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SetupRecurringAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> PauseRecurringAsync(int recurringId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_PauseRecurring", cmd =>
                {
                    _db.AddParameter(cmd, "p_RecurringDonationId", recurringId);
                    _db.AddParameter(cmd, "p_UserId",              userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "PauseRecurringAsync failed RecurringId={Id}", recurringId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ResumeRecurringAsync(int recurringId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_ResumeRecurring", cmd =>
                {
                    _db.AddParameter(cmd, "p_RecurringDonationId", recurringId);
                    _db.AddParameter(cmd, "p_UserId",              userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ResumeRecurringAsync failed RecurringId={Id}", recurringId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> CancelRecurringAsync(int recurringId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Donation_CancelRecurring", cmd =>
                {
                    _db.AddParameter(cmd, "p_RecurringDonId", recurringId);
                    _db.AddParameter(cmd, "p_UserId",         userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CancelRecurringAsync failed RecurringId={Id}", recurringId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetAnnualSummaryAsync(int userId, int year)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Donation_GetAnnualSummary", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_Year",   year);
                });
                return ApiResponse<DynamicRow>.Success(row ?? new DynamicRow());
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetAnnualSummaryAsync failed UserId={UserId}", userId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetSupportedNGOsAsync(int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Donation_GetSupportedNGOs",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSupportedNGOsAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetOrgTransactionsAsync(int orgId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Donation_GetOrgTransactions", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetOrgTransactionsAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

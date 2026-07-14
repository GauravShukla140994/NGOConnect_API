using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Withdrawal;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class WithdrawalDal : BaseDal, IWithdrawalDal
    {
        public WithdrawalDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<DynamicRow>> CreateAsync(int orgId, int userId, CreateWithdrawalRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Withdrawal_Create", cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",             orgId);
                    _db.AddParameter(cmd, "p_CampaignId",        request.CampaignId);
                    _db.AddParameter(cmd, "p_Amount",            request.Amount);
                    _db.AddParameter(cmd, "p_BankAccountName",   request.AccountHolder);  // account holder name
                    _db.AddParameter(cmd, "p_BankAccountNumber", request.BankAccount);    // account number
                    _db.AddParameter(cmd, "p_BankIfsc",          request.IfscCode);
                    _db.AddParameter(cmd, "p_Notes",             request.Purpose);
                    _db.AddParameter(cmd, "p_RequestedBy",       userId);
                });

                if (!result.Succeeded)
                    return ApiResponse<DynamicRow>.Failure(result.Message, "WITHDRAWAL_CREATE_FAILED");

                var data = new DynamicRow();
                data["withdrawalId"] = Col<int>(result.Row!, "WithdrawalId");
                data["withdrawalRef"] = Col<string>(result.Row!, "WithdrawalRef") ?? string.Empty;
                data["message"]      = result.Message;
                return ApiResponse<DynamicRow>.Success(data, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CreateAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetByOrgAsync(int orgId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Withdrawal_GetByOrg", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_OrgId",      orgId);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByOrgAsync failed OrgId={OrgId}", orgId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> AdminReviewAsync(AdminReviewWithdrawalRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Withdrawal_AdminReview", cmd =>
                {
                    _db.AddParameter(cmd, "p_WithdrawalRequestId", request.WithdrawalId);
                    _db.AddParameter(cmd, "p_StatusCode",          request.StatusCode);
                    _db.AddParameter(cmd, "p_AdminNotes",          request.AdminNotes);
                    _db.AddParameter(cmd, "p_ReviewedBy",          request.ReviewedBy);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AdminReviewAsync failed WithdrawalId={Id}", request.WithdrawalId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

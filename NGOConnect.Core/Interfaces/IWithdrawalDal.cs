using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Withdrawal;

namespace NGOConnect.Core.Interfaces
{
    public interface IWithdrawalDal
    {
        Task<ApiResponse<DynamicRow>>              CreateAsync(int orgId, int userId, CreateWithdrawalRequest request);
        Task<ApiResponse<PagedResult<DynamicRow>>> GetByOrgAsync(int orgId, int pageNumber, int pageSize);
        Task<ApiResponse>                          AdminReviewAsync(AdminReviewWithdrawalRequest request);
    }
}

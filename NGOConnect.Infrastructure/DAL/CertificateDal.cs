using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class CertificateDal : BaseDal, ICertificateDal
    {
        public CertificateDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse<List<DynamicRow>>> GetByUserAsync(int userId)
        {
            try
            {
                var rows = await ExecuteDynamicListAsync("Certificate_GetByUser",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<DynamicRow>>.Success(rows);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByUserAsync failed UserId={UserId}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

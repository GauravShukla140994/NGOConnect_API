using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Application;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class ApplicationDal : BaseDal, IApplicationDal
    {
        public ApplicationDal(IDbProvider db) : base(db) { }

        public async Task<ApiResponse> ApplyAsync(int projectId, int userId, ApplyRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Apply", cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId", projectId);
                    _db.AddParameter(cmd, "p_UserId",    userId);
                    _db.AddParameter(cmd, "p_Note",      request.Note);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ApplyAsync failed ProjectId={Id}", projectId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetByProjectAsync(
            int projectId, int? statusLkpId, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Application_GetByProject", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_ProjectId",   projectId);
                    _db.AddParameter(cmd, "p_StatusLkpId", statusLkpId);
                    _db.AddParameter(cmd, "p_PageNumber",  pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",    pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetByProjectAsync failed ProjectId={Id}", projectId);
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> ReviewAsync(int applicationId, int reviewedBy, ReviewApplicationRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("Application_Review", cmd =>
                {
                    _db.AddParameter(cmd, "p_ApplicationId", applicationId);
                    _db.AddParameter(cmd, "p_ReviewedBy",    reviewedBy);
                    _db.AddParameter(cmd, "p_StatusLkpId",   request.StatusLkpId);
                    _db.AddParameter(cmd, "p_Note",          request.Note);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ReviewAsync failed ApplicationId={Id}", applicationId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<List<DynamicRow>>> GetMyApplicationsAsync(int userId)
        {
            try
            {
                var list = await ExecuteDynamicListAsync("Application_GetByUser",
                    cmd => _db.AddParameter(cmd, "p_UserId", userId));
                return ApiResponse<List<DynamicRow>>.Success(list);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetMyApplicationsAsync failed UserId={Id}", userId);
                return ApiResponse<List<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }
    }
}

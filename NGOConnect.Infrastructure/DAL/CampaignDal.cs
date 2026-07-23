using System.Text.Json;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Campaign;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// Marketing & Communication Center — Phase 0 + Phase 1 (Push + Email only).
    /// See Documents/MarketingCommunicationCenter_BRD_v1.0.docx.
    /// </summary>
    public class CampaignDal : BaseDal, ICampaignDal
    {
        public CampaignDal(IDbProvider db) : base(db) { }

        // ── CRUD ──────────────────────────────────────────────────

        public async Task<ApiResponse<int>> CreateAsync(CreateCampaignRequest request, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Campaign_Create", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignName",     request.CampaignName);
                    _db.AddParameter(cmd, "p_InternalNotes",    (object?)request.InternalNotes ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_CampaignTypeCode", request.CampaignTypeCode);
                    _db.AddParameter(cmd, "p_PriorityCode",     request.PriorityCode);
                    _db.AddParameter(cmd, "p_CreatedBy",        userId);
                });

                if (!result.Succeeded) return ApiResponse<int>.Failure(result.Message);
                var campaignId = Col<int>(result.Row!, "CampaignId");
                return ApiResponse<int>.Success(campaignId, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.CreateAsync failed UserId={UserId}", userId);
                return ApiResponse<int>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> UpdateAsync(int campaignId, UpdateCampaignRequest request, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Campaign_Update", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",       campaignId);
                    _db.AddParameter(cmd, "p_CampaignName",     (object?)request.CampaignName ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_InternalNotes",    (object?)request.InternalNotes ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_CampaignTypeCode", (object?)request.CampaignTypeCode ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PriorityCode",     (object?)request.PriorityCode ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_ScheduleType",     (object?)request.ScheduleType ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_ScheduledAt",      (object?)request.ScheduledAt ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_TimezoneName",     (object?)request.TimezoneName ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_UpdatedBy",        userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.UpdateAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> SetStatusAsync(int campaignId, string statusCode, string? hangfireJobId, int userId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Campaign_SetStatus", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",    campaignId);
                    _db.AddParameter(cmd, "p_NewStatusCode", statusCode);
                    _db.AddParameter(cmd, "p_HangfireJobId", (object?)hangfireJobId ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_UpdatedBy",     userId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.SetStatusAsync failed CampaignId={CampaignId} Status={Status}", campaignId, statusCode);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Channels ──────────────────────────────────────────────

        public async Task<ApiResponse> SaveChannelAsync(int campaignId, SaveCampaignChannelRequest request)
        {
            try
            {
                var result = await ExecuteWriteAsync("CampaignChannel_Save", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",      campaignId);
                    _db.AddParameter(cmd, "p_ChannelCode",     request.ChannelCode);
                    _db.AddParameter(cmd, "p_PushTitle",       (object?)request.PushTitle ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PushBody",        (object?)request.PushBody ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PushImageUrl",    (object?)request.PushImageUrl ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PushDeepLink",    (object?)request.PushDeepLink ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PushActionLabel", (object?)request.PushActionLabel ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_EmailSubject",    (object?)request.EmailSubject ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_EmailHtmlBody",   (object?)request.EmailHtmlBody ?? DBNull.Value);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.SaveChannelAsync failed CampaignId={CampaignId} Channel={Channel}", campaignId, request.ChannelCode);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse> DeleteChannelAsync(int campaignId, string channelCode)
        {
            try
            {
                var result = await ExecuteWriteAsync("CampaignChannel_Delete", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",  campaignId);
                    _db.AddParameter(cmd, "p_ChannelCode", channelCode);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.DeleteChannelAsync failed CampaignId={CampaignId} Channel={Channel}", campaignId, channelCode);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Audience ──────────────────────────────────────────────

        public async Task<ApiResponse> SaveAudienceRuleAsync(int campaignId, SaveAudienceRuleRequest request)
        {
            try
            {
                var ruleJson = request.RuleValue is null ? "{}" : JsonSerializer.Serialize(request.RuleValue);

                var result = await ExecuteWriteAsync("CampaignAudienceRule_Save", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",    campaignId);
                    _db.AddParameter(cmd, "p_RuleType",      request.RuleType);
                    _db.AddParameter(cmd, "p_RuleValueJson", ruleJson);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.SaveAudienceRuleAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse.Fail("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> EstimateAudienceAsync(int campaignId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Campaign_EstimateAudience",
                    cmd => _db.AddParameter(cmd, "p_CampaignId", campaignId));
                return ApiResponse<DynamicRow>.Success(row ?? new DynamicRow());
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.EstimateAudienceAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> ResolveRecipientsAsync(int campaignId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Campaign_ResolveRecipients",
                    cmd => _db.AddParameter(cmd, "p_CampaignId", campaignId));

                if (!result.Succeeded) return ApiResponse<DynamicRow>.Failure(result.Message);

                var row = new DynamicRow();
                row["totalRecipients"]  = Col<int>(result.Row!, "TotalRecipients");
                row["queuedRecipients"] = Col<int>(result.Row!, "QueuedRecipients");
                return ApiResponse<DynamicRow>.Success(row, result.Message);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.ResolveRecipientsAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Reads ─────────────────────────────────────────────────

        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetListAsync(string? statusCode, string? search, int pageNumber, int pageSize)
        {
            try
            {
                var paged = await ExecuteDynamicPagedListAsync("Campaign_GetList", pageNumber, pageSize, cmd =>
                {
                    _db.AddParameter(cmd, "p_StatusCode", (object?)statusCode ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_Search",     (object?)search ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_PageNumber", pageNumber);
                    _db.AddParameter(cmd, "p_PageSize",   pageSize);
                });
                return ApiResponse<PagedResult<DynamicRow>>.Success(paged);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetListAsync failed");
                return ApiResponse<PagedResult<DynamicRow>>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetByIdAsync(int campaignId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Campaign_GetById",
                    cmd => _db.AddParameter(cmd, "p_CampaignId", campaignId));

                if (row is null) return ApiResponse<DynamicRow>.Failure("Campaign not found.", "NOT_FOUND");
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetByIdAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetHistoryDetailAsync(int campaignId)
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Campaign_GetHistoryDetail",
                    cmd => _db.AddParameter(cmd, "p_CampaignId", campaignId));

                if (row is null) return ApiResponse<DynamicRow>.Failure("Campaign not found.", "NOT_FOUND");
                return ApiResponse<DynamicRow>.Success(row);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetHistoryDetailAsync failed CampaignId={CampaignId}", campaignId);
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        public async Task<ApiResponse<DynamicRow>> GetDashboardStatsAsync()
        {
            try
            {
                var row = await ExecuteDynamicGetAsync("Communication_GetDashboardStats");
                return ApiResponse<DynamicRow>.Success(row ?? new DynamicRow());
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetDashboardStatsAsync failed");
                return ApiResponse<DynamicRow>.Failure("An error occurred.", "INTERNAL_ERROR");
            }
        }

        // ── Dispatch support ──────────────────────────────────────

        public async Task<List<DynamicRow>> GetQueuedRecipientsAsync(int campaignId, string channelCode, int batchSize)
        {
            try
            {
                return await ExecuteDynamicListAsync("Campaign_GetQueuedRecipients", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",  campaignId);
                    _db.AddParameter(cmd, "p_ChannelCode", channelCode);
                    _db.AddParameter(cmd, "p_BatchSize",   batchSize);
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetQueuedRecipientsAsync failed CampaignId={CampaignId} Channel={Channel}", campaignId, channelCode);
                return [];
            }
        }

        public async Task MarkRecipientStatusAsync(long campaignRecipientId, string statusCode, string? providerMessageId, string? failReason)
        {
            try
            {
                await ExecuteWriteAsync("CampaignRecipient_MarkStatus", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignRecipientId", campaignRecipientId);
                    _db.AddParameter(cmd, "p_StatusCode",          statusCode);
                    _db.AddParameter(cmd, "p_ProviderMessageId",   (object?)providerMessageId ?? DBNull.Value);
                    _db.AddParameter(cmd, "p_FailReason",          (object?)failReason ?? DBNull.Value);
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.MarkRecipientStatusAsync failed RecipientId={RecipientId}", campaignRecipientId);
            }
        }

        public async Task<long> CreateQueueJobAsync(int campaignId, int batchNumber, string channelCode, int batchSize)
        {
            try
            {
                var result = await ExecuteWriteAsync("CampaignQueueJob_Create", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignId",  campaignId);
                    _db.AddParameter(cmd, "p_BatchNumber", batchNumber);
                    _db.AddParameter(cmd, "p_ChannelCode", channelCode);
                    _db.AddParameter(cmd, "p_BatchSize",   batchSize);
                });
                return result.Succeeded ? Col<long>(result.Row!, "CampaignQueueJobId") : 0;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.CreateQueueJobAsync failed CampaignId={CampaignId} Batch={Batch}", campaignId, batchNumber);
                return 0;
            }
        }

        public async Task MarkQueueJobStatusAsync(long queueJobId, string status, string? errorMessage)
        {
            try
            {
                await ExecuteWriteAsync("CampaignQueueJob_MarkStatus", cmd =>
                {
                    _db.AddParameter(cmd, "p_CampaignQueueJobId", queueJobId);
                    _db.AddParameter(cmd, "p_Status",             status);
                    _db.AddParameter(cmd, "p_ErrorMessage",       (object?)errorMessage ?? DBNull.Value);
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.MarkQueueJobStatusAsync failed QueueJobId={QueueJobId}", queueJobId);
            }
        }

        public async Task<List<DynamicRow>> GetUserContactsAsync(List<int> userIds)
        {
            if (userIds.Count == 0) return [];
            try
            {
                var csv = string.Join(",", userIds);
                return await ExecuteDynamicListAsync("User_GetContactsByIds",
                    cmd => _db.AddParameter(cmd, "p_UserIdsCsv", csv));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Campaign.GetUserContactsAsync failed");
                return [];
            }
        }
    }
}

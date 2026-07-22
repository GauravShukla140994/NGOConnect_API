using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Feed;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class FeedDal : BaseDal, IFeedDal
    {
        public FeedDal(IDbProvider db) : base(db) { }

        // ── GetPersonalizedAsync ──────────────────────────────────────────────
        // SP returns 3× pageSize candidates (scored, cursor-filtered).
        // C# diversity engine trims to pageSize ensuring no more than 2 consecutive
        // posts from the same org and no more than 3 consecutive of the same type.
        public async Task<ApiResponse<FeedPageResult>> GetPersonalizedAsync(
            int      userId,
            int?     cursorPostId,
            decimal? cursorScore,
            int      pageSize)
        {
            try
            {
                var candidates = await ExecuteDynamicListAsync("Feed_GetPersonalized", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",       userId);
                    _db.AddParameter(cmd, "p_CursorPostId", cursorPostId.HasValue ? (object)cursorPostId.Value : DBNull.Value);
                    _db.AddParameter(cmd, "p_CursorScore",  cursorScore.HasValue  ? (object)cursorScore.Value  : DBNull.Value);
                    _db.AddParameter(cmd, "p_PageSize",     pageSize);
                });

                var page = ApplyDiversityEngine(candidates, pageSize);
                return ApiResponse<FeedPageResult>.Success(page);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetPersonalizedAsync failed UserId={UserId}", userId);
                return ApiResponse<FeedPageResult>.Failure("Could not load feed.", "INTERNAL_ERROR");
            }
        }

        // ── SavePostAsync ─────────────────────────────────────────────────────
        public async Task<ApiResponse> SavePostAsync(int userId, int postId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Save", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_PostId", postId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SavePostAsync failed UserId={UserId} PostId={PostId}", userId, postId);
                return ApiResponse.Fail("Could not save post.", "INTERNAL_ERROR");
            }
        }

        // ── UnsavePostAsync ───────────────────────────────────────────────────
        public async Task<ApiResponse> UnsavePostAsync(int userId, int postId)
        {
            try
            {
                var result = await ExecuteWriteAsync("Post_Unsave", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId", userId);
                    _db.AddParameter(cmd, "p_PostId", postId);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "UnsavePostAsync failed UserId={UserId} PostId={PostId}", userId, postId);
                return ApiResponse.Fail("Could not unsave post.", "INTERNAL_ERROR");
            }
        }

        // ── TrackInteractionAsync ─────────────────────────────────────────────
        public async Task<ApiResponse> TrackInteractionAsync(
            int    userId,
            int    postId,
            string interactionType,
            int?   durationMs)
        {
            try
            {
                var result = await ExecuteWriteAsync("Feed_TrackInteraction", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",          userId);
                    _db.AddParameter(cmd, "p_PostId",          postId);
                    _db.AddParameter(cmd, "p_InteractionType", interactionType);
                    _db.AddParameter(cmd, "p_DurationMs",      durationMs.HasValue ? (object)durationMs.Value : DBNull.Value);
                });
                return result.ToApiResponse();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "TrackInteractionAsync failed UserId={UserId} PostId={PostId}", userId, postId);
                return ApiResponse.Fail("Could not track interaction.", "INTERNAL_ERROR");
            }
        }

        // ── Diversity Engine ──────────────────────────────────────────────────
        /// <summary>
        /// Post-processes the over-fetched candidate list to prevent monotonous feeds.
        ///
        /// Rules:
        ///   – No more than 2 consecutive posts from the same org (OrgId)
        ///   – No more than 3 consecutive posts of the same type (PostTypeCode)
        ///
        /// Algorithm: sliding-window approach — maintain a small window of recently
        /// selected items; skip a candidate that would violate diversity constraints
        /// and continue scanning. Skipped candidates are NOT permanently excluded —
        /// they may qualify later once the window advances.
        /// </summary>
        private static FeedPageResult ApplyDiversityEngine(List<DynamicRow> candidates, int pageSize)
        {
            var selected      = new List<DynamicRow>(pageSize);
            var recentOrgIds  = new Queue<int>(3);    // tracks last 2 selected orgIds
            var recentTypes   = new Queue<string>(4); // tracks last 3 selected typesCodes

            // Phase 1: greedy pass — collect non-violating candidates in score order
            var skipped = new List<DynamicRow>();

            foreach (var row in candidates)
            {
                if (selected.Count >= pageSize) break;

                var orgId    = row.Get<int?>("orgId")        ?? 0;
                var typeCode = row.Get<string>("postTypeCode") ?? "";

                if (ViolatesDiversity(orgId, typeCode, recentOrgIds, recentTypes))
                {
                    skipped.Add(row);
                    continue;
                }

                AddToSelected(selected, row, orgId, typeCode, recentOrgIds, recentTypes);
            }

            // Phase 2: if still short, fill from skipped pool (relaxed order)
            if (selected.Count < pageSize)
            {
                foreach (var row in skipped)
                {
                    if (selected.Count >= pageSize) break;

                    var orgId    = row.Get<int?>("orgId")        ?? 0;
                    var typeCode = row.Get<string>("postTypeCode") ?? "";

                    // Re-check against the CURRENT window (may now be OK)
                    if (!ViolatesDiversity(orgId, typeCode, recentOrgIds, recentTypes))
                        AddToSelected(selected, row, orgId, typeCode, recentOrgIds, recentTypes);
                }
            }

            // Cursor = last selected item's (UNIX_TIMESTAMP(CreatedAt), PostId).
            // NextCursorScore now carries the Unix timestamp of the last post's CreatedAt,
            // matching the SP's time-first pagination (ORDER BY CreatedAt DESC, PostId DESC).
            var last = selected.LastOrDefault();
            var lastCreatedAt = last?.Get<DateTime?>("createdAt");
            return new FeedPageResult
            {
                Items            = selected,
                NextCursorPostId = last?.Get<int?>("postId"),
                NextCursorScore  = lastCreatedAt.HasValue
                    ? (decimal)new DateTimeOffset(DateTime.SpecifyKind(lastCreatedAt.Value, DateTimeKind.Utc)).ToUnixTimeSeconds()
                    : null,
                HasMore          = candidates.Count > pageSize,
            };
        }

        private static bool ViolatesDiversity(
            int orgId, string typeCode,
            Queue<int> recentOrgIds, Queue<string> recentTypes)
        {
            // Violation: 3rd consecutive from the same org (window is last 2)
            if (recentOrgIds.Count >= 2 && recentOrgIds.All(o => o == orgId))
                return true;

            // Violation: 4th consecutive of the same type (window is last 3)
            if (!string.IsNullOrEmpty(typeCode) &&
                recentTypes.Count >= 3 && recentTypes.All(t => t == typeCode))
                return true;

            return false;
        }

        private static void AddToSelected(
            List<DynamicRow> selected, DynamicRow row,
            int orgId, string typeCode,
            Queue<int> recentOrgIds, Queue<string> recentTypes)
        {
            selected.Add(row);

            recentOrgIds.Enqueue(orgId);
            if (recentOrgIds.Count > 2) recentOrgIds.Dequeue();

            if (!string.IsNullOrEmpty(typeCode))
            {
                recentTypes.Enqueue(typeCode);
                if (recentTypes.Count > 3) recentTypes.Dequeue();
            }
        }
    }
}

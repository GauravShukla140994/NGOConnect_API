using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Models.Feed
{
    /// <summary>
    /// Cursor-based page result for the personalised feed.
    /// Use (NextCursorPostId, NextCursorScore) to fetch the next page.
    /// HasMore = false means this is the last page.
    /// </summary>
    public class FeedPageResult
    {
        public List<DynamicRow> Items            { get; set; } = [];
        public int?             NextCursorPostId { get; set; }
        public decimal?         NextCursorScore  { get; set; }
        public bool             HasMore          { get; set; }
    }
}

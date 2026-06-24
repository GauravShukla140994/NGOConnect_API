namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Wrapper for paged list responses.
    /// SP must return 2 result sets:
    ///   1st: the data rows
    ///   2nd: SELECT COUNT(*) AS TotalCount FROM ...
    /// </summary>
    public class PagedResult<T>
    {
        public List<T> Items      { get; init; } = [];
        public int     TotalCount { get; init; }
        public int     PageNumber { get; init; }
        public int     PageSize   { get; init; }
        public int     TotalPages => PageSize > 0
                                        ? (int)Math.Ceiling((double)TotalCount / PageSize)
                                        : 0;
    }
}

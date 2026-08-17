using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Backs the no-auth "Global exploration" stats used by the marketing website
    /// (Countries / Organisations / Volunteers / Raised). Isolated on purpose —
    /// new SP only (Public_GetGlobalStats), never touches an existing SP.
    /// </summary>
    public interface IPublicStatsDal
    {
        Task<ApiResponse<DynamicRow>> GetGlobalStatsAsync();
    }
}

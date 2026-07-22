using NGOConnect.Core.Models.Support;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// DAL contract for Phase 1 Help &amp; Support.
    /// Logs submissions to AuditLogs — no SupportTickets table in Phase 1.
    /// </summary>
    public interface ISupportDal
    {
        /// <summary>
        /// Logs the contact submission to AuditLogs and returns IsSuccess=1.
        /// </summary>
        Task<WriteResult> LogContactAsync(
            int userId,
            SupportContactRequest request,
            string ipAddress);
    }
}

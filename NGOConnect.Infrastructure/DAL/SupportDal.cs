using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Support;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class SupportDal : BaseDal, ISupportDal
    {
        public SupportDal(IDbProvider db) : base(db) { }

        public async Task<WriteResult> LogContactAsync(
            int userId,
            SupportContactRequest request,
            string ipAddress)
        {
            try
            {
                return await ExecuteWriteAsync("Support_LogContact", cmd =>
                {
                    _db.AddParameter(cmd, "p_UserId",       userId);
                    _db.AddParameter(cmd, "p_CategoryCode", request.CategoryCode);
                    _db.AddParameter(cmd, "p_Subject",      request.Subject);
                    _db.AddParameter(cmd, "p_Description",  request.Description);
                    _db.AddParameter(cmd, "p_ContactEmail", request.ContactEmail);
                    _db.AddParameter(cmd, "p_ContactName",   request.ContactName);
                    _db.AddParameter(cmd, "p_IpAddress",    ipAddress);
                    _db.AddParameter(cmd, "p_AttachmentUrl", request.AttachmentUrl);
                });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "SupportDal.LogContactAsync failed for UserId={UserId}", userId);
                return new WriteResult { Succeeded = false, Message = "An error occurred logging your request." };
            }
        }
    }
}

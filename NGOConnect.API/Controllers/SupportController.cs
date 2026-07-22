using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Support;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/support")]
    [Authorize]
    [Produces("application/json")]
    public class SupportController : ControllerBase
    {
        private readonly ISupportDal   _support;
        private readonly IEmailService _email;

        public SupportController(ISupportDal support, IEmailService email)
        {
            _support = support;
            _email   = email;
        }

        /// <summary>
        /// POST /api/v1/support/contact
        /// Submit a Help &amp; Support request.
        /// Logs to AuditLogs and sends an email to the support inbox.
        /// </summary>
        [HttpPost("contact")]
        public async Task<ApiResponse> Contact([FromBody] SupportContactRequest request)
        {
            var userId    = GetUserId();
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

            // 1. Log to AuditLogs
            var result = await _support.LogContactAsync(userId, request, ipAddress);
            if (!result.Succeeded)
                return result.ToApiResponse();

            // 2. Send email to support inbox (fire-and-forget style — don't fail the user if email glitches)
            _ = _email.SendSupportEmailAsync(
                contactName:   request.ContactName,
                categoryLabel: request.CategoryLabel,
                subject:       request.Subject,
                description:   request.Description,
                contactEmail:  request.ContactEmail,
                attachmentUrl: request.AttachmentUrl);

            return result.ToApiResponse();
        }

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}

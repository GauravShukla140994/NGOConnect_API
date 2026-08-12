using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Server-side certificate HTML renderer.
    /// Reads the CertificateTemplate.html file once at startup, then for each call
    /// substitutes all {{PLACEHOLDER}} tokens from the DynamicRow returned by
    /// Certificate_GetData / Certificate_GetDataById and returns a fully-rendered HTML string.
    ///
    /// Single source of truth for the certificate design — mobile app and website both
    /// call GET /certificates/{certCode}/html or GET /certificates/verify/{token}/html
    /// and receive the same rendered HTML without maintaining local templates.
    /// </summary>
    public interface ICertificateHtmlService
    {
        string Render(DynamicRow row);
    }
}

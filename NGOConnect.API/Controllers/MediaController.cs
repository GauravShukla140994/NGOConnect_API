using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Handles all file uploads and private document access.
    ///
    /// PUBLIC upload flow (photos, logos, post media):
    ///   POST /api/v1/media/upload?module=user-photos
    ///   → returns { fileUrl, fileName, fileSizeKb, isPrivate: false }
    ///   → pass fileUrl to the entity endpoint
    ///
    /// PRIVATE upload flow (KYC docs, NGO docs, receipts, certificates):
    ///   POST /api/v1/media/upload?module=user-documents
    ///   → returns { fileKey, fileName, fileSizeKb, isPrivate: true }
    ///   → store fileKey in DB via entity endpoint (NOT fileUrl)
    ///   → call GET /api/v1/media/signed-url?key={fileKey} to view the document
    ///
    /// Module routing:
    ///   PUBLIC  → user-photos, org-logos, project-images, post-media
    ///   PRIVATE → user-documents, org-documents, certificates, donation-receipts
    /// </summary>
    [ApiController]
    [Route("api/v1/media")]
    public class MediaController : ControllerBase
    {
        private readonly IBlobService        _blob;
        private readonly IPrivateBlobService _privateBlob;

        // Modules that go to private storage — everything else goes to public
        private static readonly HashSet<string> PrivateModules = new(StringComparer.OrdinalIgnoreCase)
        {
            "user-documents",
            "org-documents",
            "certificates",
            "donation-receipts"
        };

        public MediaController(IBlobService blob, IPrivateBlobService privateBlob)
        {
            _blob        = blob;
            _privateBlob = privateBlob;
        }

        /// <summary>
        /// Upload a file. Automatically routes to public or private storage based on the module.
        /// Use multipart/form-data with field name "file".
        /// </summary>
        /// <param name="module">
        /// PUBLIC modules  : user-photos, org-logos, project-images, post-media
        /// PRIVATE modules : user-documents, org-documents, certificates, donation-receipts
        /// </param>
        [HttpPost("upload")]
        [Authorize]
        [RequestSizeLimit(50 * 1024 * 1024)]
        [Consumes("multipart/form-data")]
        public async Task<ApiResponse<BlobUploadResult>> Upload([FromQuery] string module, IFormFile file)
        {
            if (string.IsNullOrWhiteSpace(module))
                return ApiResponse<BlobUploadResult>.Failure(
                    "Query parameter 'module' is required.", "UPLOAD_MODULE_MISSING");

            if (file == null || file.Length == 0)
                return ApiResponse<BlobUploadResult>.Failure(
                    "No file provided or file is empty.", "UPLOAD_FILE_MISSING");

            var userId = GetUserId();

            try
            {
                if (PrivateModules.Contains(module))
                {
                    // ── Private upload → IPrivateBlobService ──────────────────
                    var result = await _privateBlob.UploadAsync(file, module, userId);

                    return ApiResponse<BlobUploadResult>.Success(new BlobUploadResult
                    {
                        FileUrl    = null,
                        FileKey    = result.FileKey,
                        FileName   = result.FileName,
                        FileSizeKb = result.FileSizeKb,
                        Module     = result.Module,
                        IsPrivate  = true
                    }, "File uploaded securely. Use fileKey to reference this document. " +
                       "Call GET /api/v1/media/signed-url?key={fileKey} to generate a temporary view link.");
                }
                else
                {
                    // ── Public upload → IBlobService ──────────────────────────
                    var result = await _blob.UploadAsync(file, module, userId);
                    result.IsPrivate = false;

                    return ApiResponse<BlobUploadResult>.Success(result,
                        "File uploaded successfully. Use fileUrl in your next request.");
                }
            }
            catch (ArgumentException ex)
            {
                Log.Warning("Upload validation failed: Module={Module} Message={Message}", module, ex.Message);
                return ApiResponse<BlobUploadResult>.Failure(ex.Message, "UPLOAD_INVALID");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Upload failed: UserId={UserId} Module={Module}", userId, module);
                return ApiResponse<BlobUploadResult>.Failure(
                    "File upload failed. Please try again.", "UPLOAD_FAILED");
            }
        }

        /// <summary>
        /// Generate a temporary signed URL for a private document.
        /// The URL expires in 15 minutes (or the specified duration).
        /// Only the authenticated user should receive and use this URL.
        /// </summary>
        /// <param name="key">The fileKey returned from a private upload.</param>
        /// <param name="expiryMinutes">URL validity in minutes (default: 15, max: 60).</param>
        [HttpGet("signed-url")]
        [Authorize]
        public async Task<ApiResponse<object>> GetSignedUrl(
            [FromQuery] string key,
            [FromQuery] int expiryMinutes = 15)
        {
            if (string.IsNullOrWhiteSpace(key))
                return ApiResponse<object>.Failure("Query parameter 'key' is required.", "KEY_MISSING");

            // Cap expiry to 60 minutes — prevents generating long-lived links
            expiryMinutes = Math.Clamp(expiryMinutes, 1, 60);

            try
            {
                var signedUrl = await _privateBlob.GetSignedUrlAsync(key, expiryMinutes);

                return ApiResponse<object>.Success(new
                {
                    signedUrl,
                    expiresInMinutes = expiryMinutes
                }, $"Signed URL generated. Valid for {expiryMinutes} minute(s).");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetSignedUrl failed: Key={Key}", key);
                return ApiResponse<object>.Failure(
                    "Failed to generate signed URL. Please try again.", "SIGNED_URL_FAILED");
            }
        }

        // ── Helpers ───────────────────────────────────────────────
        private int GetUserId() =>
            int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;
    }
}

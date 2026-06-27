using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    /// <summary>
    /// Handles file uploads for all modules.
    /// Frontend flow:
    ///   1. POST /api/v1/media/upload?module=user-documents  → gets { fileUrl, fileName, fileSizeKb }
    ///   2. Use those values in the entity endpoint (POST /user/documents, PUT /user/profile, etc.)
    ///
    /// Supported modules:
    ///   user-documents  — Aadhaar, PAN, Passport, Driving License
    ///   user-photos     — Profile photo
    ///   org-documents   — Registration cert, 80G, 12A, FCRA
    ///   org-logos       — NGO logo
    ///   certificates    — Volunteer completion certificates
    /// </summary>
    [ApiController]
    [Route("api/v1/media")]
    public class MediaController : ControllerBase
    {
        private readonly IBlobService _blob;

        public MediaController(IBlobService blob)
        {
            _blob = blob;
        }

        /// <summary>
        /// Upload a file and receive its permanent URL + metadata.
        /// Use multipart/form-data with field name "file".
        /// </summary>
        /// <param name="module">
        /// Target module — determines subfolder and allowed file types.
        /// Allowed values: user-documents, user-photos, org-documents, org-logos, certificates
        /// </param>
        [HttpPost("upload")]
        [Authorize]
        [RequestSizeLimit(10 * 1024 * 1024)]   // 10 MB hard limit at HTTP level
        [Consumes("multipart/form-data")]
        public async Task<ApiResponse<BlobUploadResult>> Upload(
            [FromQuery] string module,
            IFormFile file)
        {
            if (string.IsNullOrWhiteSpace(module))
                return ApiResponse<BlobUploadResult>.Failure(
                    "Query parameter 'module' is required.", "UPLOAD_MODULE_MISSING");

            if (file == null || file.Length == 0)
                return ApiResponse<BlobUploadResult>.Failure(
                    "No file provided or file is empty.", "UPLOAD_FILE_MISSING");

            try
            {
                var userId = GetUserId();
                var result = await _blob.UploadAsync(file, module, userId);

                return ApiResponse<BlobUploadResult>.Success(result,
                    $"File uploaded successfully. Use fileUrl in your next request.");
            }
            catch (ArgumentException ex)
            {
                // Validation failures (bad module, bad extension, size exceeded)
                Log.Warning("Upload validation failed: {Message}", ex.Message);
                return ApiResponse<BlobUploadResult>.Failure(ex.Message, "UPLOAD_INVALID");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Upload failed for UserId={UserId} Module={Module}", GetUserId(), module);
                return ApiResponse<BlobUploadResult>.Failure(
                    "File upload failed. Please try again.", "UPLOAD_FAILED");
            }
        }

        // ── Helpers ───────────────────────────────────────────────

        private int GetUserId() =>
            int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;
    }
}

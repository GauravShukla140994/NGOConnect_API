using Microsoft.AspNetCore.Http;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Fallback IPrivateBlobService for Local and Cloudinary storage modes (dev / staging).
    /// Delegates to the registered IBlobService — files are stored the same way as public files.
    /// The returned URL is used as the FileKey — callers treat it as an opaque string.
    ///
    /// In production (StorageProvider=awss3), this class is replaced by AwsS3PrivateBlobService
    /// which provides true private storage with presigned URLs and real expiry.
    ///
    /// This means: in local/cloudinary mode, "private" docs are not truly private (acceptable for dev/staging).
    /// </summary>
    public class FallbackPrivateBlobService : IPrivateBlobService
    {
        private readonly IBlobService _blob;

        public FallbackPrivateBlobService(IBlobService blob)
        {
            _blob = blob;
        }

        public async Task<PrivateBlobUploadResult> UploadAsync(IFormFile file, string module, int userId)
        {
            // Map private module names to the allowed modules in IBlobService
            var publicModule = module switch
            {
                "donation-receipts" => "user-documents",
                _                   => module   // user-documents, org-documents, certificates pass through
            };

            var result = await _blob.UploadAsync(file, publicModule, userId);

            Log.Debug("FallbackPrivateBlobService: uploaded via {Provider}. FileKey={Key}",
                _blob.GetType().Name, result.FileUrl);

            return new PrivateBlobUploadResult
            {
                FileKey    = result.FileUrl ?? result.FileName,  // URL used as opaque key
                FileName   = result.FileName,
                FileSizeKb = result.FileSizeKb,
                Module     = module
            };
        }

        public Task<string> GetSignedUrlAsync(string fileKey, int expiryMinutes = 15)
        {
            // In fallback mode, fileKey IS the URL — return it directly (no expiry concept)
            Log.Debug("FallbackPrivateBlobService.GetSignedUrlAsync: returning fileKey as URL (no expiry in dev mode)");
            return Task.FromResult(fileKey);
        }

        public async Task<bool> DeleteAsync(string fileKey)
        {
            return await _blob.DeleteAsync(fileKey);
        }
    }
}

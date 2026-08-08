using Microsoft.AspNetCore.Http;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Storage provider abstraction — swap implementation to change storage backend.
    /// Phase 1 : LocalFileService  (saves to server disk)
    /// Phase 2 : AzureBlobService  (Azure Blob Storage)
    /// Phase 3 : S3BlobService     (AWS S3 / Google GCS)
    ///
    /// TO SWITCH: change one line in ServiceCollectionExtensions.AddBlobService().
    /// Zero other code changes required anywhere.
    /// </summary>
    public interface IBlobService
    {
        /// <summary>
        /// Upload a file and return its permanent URL + metadata.
        /// </summary>
        /// <param name="file">Incoming multipart file from the request.</param>
        /// <param name="module">
        /// Logical storage bucket — controls subfolder / container.
        /// Allowed: user-documents, user-photos, org-documents, org-logos, certificates
        /// </param>
        /// <param name="userId">Uploader's UserId — embedded in file name for traceability.</param>
        Task<BlobUploadResult> UploadAsync(IFormFile file, string module, int userId);

        /// <summary>
        /// Delete a previously uploaded file by its URL.
        /// Safe to call even if the file no longer exists.
        /// </summary>
        Task<bool> DeleteAsync(string fileUrl);
    }
}

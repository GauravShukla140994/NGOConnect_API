using Microsoft.AspNetCore.Http;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Private storage provider — for sensitive documents (KYC, NGO legal docs, receipts, certs).
    /// Files are NEVER publicly accessible. Access is only via signed URLs with short expiry.
    ///
    /// Allowed modules:
    ///   user-documents    — Aadhaar, PAN, Passport, Driving License (pdf, jpg, jpeg, png)
    ///   org-documents     — Registration cert, 80G, 12A, FCRA         (pdf, jpg, jpeg, png)
    ///   certificates      — Volunteer completion certificates          (pdf)
    ///   donation-receipts — Donation receipts                          (pdf)
    ///
    /// awss3 mode  → AwsS3PrivateBlobService  (ripplehub-private bucket, true signed URLs)
    /// local mode  → FallbackPrivateBlobService (disk storage, URL returned as key)
    /// cloudinary  → FallbackPrivateBlobService (Cloudinary storage, URL returned as key)
    /// </summary>
    public interface IPrivateBlobService
    {
        /// <summary>
        /// Upload a sensitive file to private storage.
        /// Returns a FileKey (S3 object key or file path) — NOT a public URL.
        /// Store the FileKey in the DB. Use GetSignedUrlAsync() to generate a temporary access link.
        /// </summary>
        Task<PrivateBlobUploadResult> UploadAsync(IFormFile file, string module, int userId);

        /// <summary>
        /// Generate a short-lived signed URL for accessing a private file.
        /// In awss3 mode: true presigned S3 URL with expiry.
        /// In local/cloudinary fallback: returns the stored URL directly (no expiry in dev).
        /// Default expiry: 15 minutes.
        /// </summary>
        Task<string> GetSignedUrlAsync(string fileKey, int expiryMinutes = 15);

        /// <summary>Delete a private file by its FileKey. Safe to call if file doesn't exist.</summary>
        Task<bool> DeleteAsync(string fileKey);
    }
}

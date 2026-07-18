namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Returned by IBlobService.UploadAsync — same shape regardless of storage provider.
    /// For PUBLIC uploads (photos, logos, post media):
    ///   FileUrl is set (permanent CDN URL), FileKey is null.
    /// For PRIVATE uploads (KYC docs, NGO docs, receipts) in awss3 mode:
    ///   FileKey is set (S3 object key — store in DB), FileUrl is null.
    ///   Use GET /api/v1/media/signed-url?key={FileKey} to generate a temporary access URL.
    /// </summary>
    public class BlobUploadResult
    {
        public string? FileUrl    { get; set; }                   // Permanent public URL (public uploads)
        public string? FileKey    { get; set; }                   // S3 object key (private uploads only)
        public string  FileName   { get; set; } = string.Empty;   // Stored file name (with guid)
        public int     FileSizeKb { get; set; }                   // File size in KB
        public string  Module     { get; set; } = string.Empty;   // e.g. user-documents, org-logos
        public bool    IsPrivate  { get; set; }                   // true = private (use signed URL), false = public
    }

    /// <summary>
    /// Internal result from IPrivateBlobService.UploadAsync.
    /// FileKey is the S3 object key — store this in the DB, never a public URL.
    /// </summary>
    public class PrivateBlobUploadResult
    {
        public string FileKey    { get; set; } = string.Empty;   // S3 object key — store in DB
        public string FileName   { get; set; } = string.Empty;   // Original sanitized file name
        public int    FileSizeKb { get; set; }
        public string Module     { get; set; } = string.Empty;
    }
}

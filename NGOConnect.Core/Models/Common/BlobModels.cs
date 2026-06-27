namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Returned by IBlobService.UploadAsync — same shape regardless of storage provider.
    /// Frontend receives this and passes FileUrl + FileName + FileSizeKb to the entity endpoint.
    /// </summary>
    public class BlobUploadResult
    {
        public string FileUrl    { get; set; } = string.Empty;   // Permanent accessible URL
        public string FileName   { get; set; } = string.Empty;   // Stored file name (with guid)
        public int    FileSizeKb { get; set; }                   // File size in KB
        public string Module     { get; set; } = string.Empty;   // e.g. user-documents, org-logos
    }
}

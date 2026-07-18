using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// AWS S3 private storage provider — implements IPrivateBlobService.
    /// Stores sensitive documents in the fully-private S3 bucket.
    /// Files are NEVER publicly accessible — access is via presigned URLs (default: 15-min expiry).
    ///
    /// Activate by setting StorageProvider = "awss3" in appsettings.json.
    ///
    /// Bucket: AWS:PrivateBucket  (e.g. ripplehub-private)
    /// Region: AWS:Region         (e.g. ap-south-1)
    ///
    /// Key layout: {module}/{userId}/{yyyyMMdd}_{userId}_{8-guid}_{safeName}.{ext}
    /// Example   : user-documents/42/20260718_42_a1b2c3d4_aadhaar.pdf
    ///
    /// Supported modules:
    ///   user-documents    — Aadhaar, PAN, Passport, Driving License (max 10 MB, pdf/jpg/jpeg/png)
    ///   org-documents     — Registration cert, 80G, 12A, FCRA        (max 10 MB, pdf/jpg/jpeg/png)
    ///   certificates      — Volunteer completion certificates         (max  5 MB, pdf)
    ///   donation-receipts — Donation receipts                         (max  5 MB, pdf)
    /// </summary>
    public class AwsS3PrivateBlobService : IPrivateBlobService
    {
        private readonly AmazonS3Client _s3;
        private readonly string         _bucket;

        private static readonly Dictionary<string, HashSet<string>> AllowedExtensions =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"]    = ["pdf", "jpg", "jpeg", "png"],
            ["org-documents"]     = ["pdf", "jpg", "jpeg", "png"],
            ["certificates"]      = ["pdf"],
            ["donation-receipts"] = ["pdf"],
        };

        private static readonly Dictionary<string, long> MaxFileSizePerModule =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"]    = 10L * 1024 * 1024,
            ["org-documents"]     = 10L * 1024 * 1024,
            ["certificates"]      =  5L * 1024 * 1024,
            ["donation-receipts"] =  5L * 1024 * 1024,
        };

        public AwsS3PrivateBlobService(IConfiguration config)
        {
            var accessKey = config["AWS:AccessKeyId"]
                ?? throw new InvalidOperationException("AWS:AccessKeyId not configured.");
            var secretKey = config["AWS:SecretAccessKey"]
                ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured.");
            var region    = config["AWS:Region"] ?? "ap-south-1";
            _bucket       = config["AWS:PrivateBucket"]
                ?? throw new InvalidOperationException("AWS:PrivateBucket not configured.");

            _s3 = new AmazonS3Client(accessKey, secretKey, RegionEndpoint.GetBySystemName(region));
        }

        // ── Upload ────────────────────────────────────────────────────────────
        public async Task<PrivateBlobUploadResult> UploadAsync(IFormFile file, string module, int userId)
        {
            if (!AllowedExtensions.ContainsKey(module))
                throw new ArgumentException(
                    $"Unknown private module '{module}'. Allowed: {string.Join(", ", AllowedExtensions.Keys)}");

            if (file == null || file.Length == 0)
                throw new ArgumentException("No file provided or file is empty.");

            var maxBytes = MaxFileSizePerModule.TryGetValue(module, out var mb) ? mb : 10L * 1024 * 1024;
            if (file.Length > maxBytes)
                throw new ArgumentException(
                    $"File size {file.Length / 1024 / 1024}MB exceeds the {maxBytes / 1024 / 1024}MB limit for module '{module}'.");

            var ext = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
            if (!AllowedExtensions[module].Contains(ext))
                throw new ArgumentException(
                    $"File type '.{ext}' not allowed for module '{module}'. " +
                    $"Allowed: {string.Join(", ", AllowedExtensions[module].Select(e => "." + e))}");

            var datePart = DateTime.UtcNow.ToString("yyyyMMdd");
            var guidPart = Guid.NewGuid().ToString("N")[..8];
            var safeName = SanitizeName(Path.GetFileNameWithoutExtension(file.FileName));
            // Include userId in path for easy per-user lifecycle management
            var key      = $"{module}/{userId}/{datePart}_{userId}_{guidPart}_{safeName}.{ext}";

            await using var stream = file.OpenReadStream();

            var putRequest = new PutObjectRequest
            {
                BucketName                 = _bucket,
                Key                        = key,
                InputStream                = stream,
                ContentType                = GetContentType(ext),
                ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
                // No CannedACL — bucket is fully private, no public access possible
            };

            await _s3.PutObjectAsync(putRequest);

            var fileSizeKb = (int)Math.Ceiling(file.Length / 1024.0);

            Log.Information(
                "S3 private upload: Module={Module} UserId={UserId} Key={Key} Size={SizeKb}KB",
                module, userId, key, fileSizeKb);

            return new PrivateBlobUploadResult
            {
                FileKey    = key,
                FileName   = $"{safeName}.{ext}",
                FileSizeKb = fileSizeKb,
                Module     = module
            };
        }

        // ── Get Signed URL ────────────────────────────────────────────────────
        public async Task<string> GetSignedUrlAsync(string fileKey, int expiryMinutes = 15)
        {
            if (string.IsNullOrWhiteSpace(fileKey))
                throw new ArgumentException("FileKey cannot be empty.");

            var request = new GetPreSignedUrlRequest
            {
                BucketName = _bucket,
                Key        = fileKey,
                Expires    = DateTime.UtcNow.AddMinutes(expiryMinutes),
                Protocol   = Protocol.HTTPS,
                Verb       = HttpVerb.GET
            };

            var url = await _s3.GetPreSignedURLAsync(request);
            Log.Debug("S3 signed URL: Key={Key} ExpiryMin={Expiry}", fileKey, expiryMinutes);
            return url;
        }

        // ── Delete ────────────────────────────────────────────────────────────
        public async Task<bool> DeleteAsync(string fileKey)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(fileKey)) return false;
                await _s3.DeleteObjectAsync(_bucket, fileKey);
                Log.Information("S3 private delete: Key={Key}", fileKey);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsS3PrivateBlobService.DeleteAsync failed for Key={Key}", fileKey);
                return false;
            }
        }

        // ── Helpers ───────────────────────────────────────────────────────────

        private static string GetContentType(string ext) => ext switch
        {
            "jpg" or "jpeg" => "image/jpeg",
            "png"           => "image/png",
            "pdf"           => "application/pdf",
            _               => "application/octet-stream"
        };

        private static string SanitizeName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "file";
            var safe = new string(name.Where(c => char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return safe.Length == 0 ? "file" : safe[..Math.Min(safe.Length, 30)];
        }
    }
}

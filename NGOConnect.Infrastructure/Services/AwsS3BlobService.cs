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
    /// AWS S3 public storage provider — implements IBlobService.
    /// Stores media files (photos, logos, post media) in the public S3 bucket.
    /// Files are publicly readable via bucket policy — no per-object ACL needed.
    ///
    /// Activate by setting StorageProvider = "awss3" in appsettings.json.
    ///
    /// Bucket: AWS:PublicBucket  (e.g. ripplehub-public)
    /// Region: AWS:Region        (e.g. ap-south-1)
    ///
    /// Key layout: {module}/{yyyyMMdd}_{userId}_{8-guid}_{safeName}.{ext}
    /// Example   : user-photos/20260718_42_a1b2c3d4_profilepic.jpg
    ///
    /// Supported modules (public only — sensitive docs go to IPrivateBlobService):
    ///   user-photos    — Profile photos             (max  5 MB, jpg/jpeg/png)
    ///   org-logos      — NGO logos                  (max  5 MB, jpg/jpeg/png/svg)
    ///   project-images — Project cover images        (max 10 MB, jpg/jpeg/png)
    ///   post-media     — Feed/community post media   (max 50 MB, jpg/jpeg/png/mp4/mov/webm/mkv/m4v)
    /// </summary>
    public class AwsS3BlobService : IBlobService
    {
        private readonly AmazonS3Client _s3;
        private readonly string         _bucket;
        private readonly string         _publicBaseUrl;

        private static readonly Dictionary<string, HashSet<string>> AllowedExtensions =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-photos"]    = ["jpg", "jpeg", "png"],
            ["org-logos"]      = ["jpg", "jpeg", "png", "svg"],
            ["project-images"] = ["jpg", "jpeg", "png"],
            ["post-media"]     = ["jpg", "jpeg", "png", "mp4", "mov", "webm", "mkv", "m4v"],
        };

        private static readonly Dictionary<string, long> MaxFileSizePerModule =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-photos"]    =  5L * 1024 * 1024,
            ["org-logos"]      =  5L * 1024 * 1024,
            ["project-images"] = 10L * 1024 * 1024,
            ["post-media"]     = 50L * 1024 * 1024,
        };

        public AwsS3BlobService(IConfiguration config)
        {
            var accessKey  = config["AWS:AccessKeyId"]
                ?? throw new InvalidOperationException("AWS:AccessKeyId not configured.");
            var secretKey  = config["AWS:SecretAccessKey"]
                ?? throw new InvalidOperationException("AWS:SecretAccessKey not configured.");
            var region     = config["AWS:Region"] ?? "ap-south-1";
            _bucket        = config["AWS:PublicBucket"]
                ?? throw new InvalidOperationException("AWS:PublicBucket not configured.");
            _publicBaseUrl = (config["AWS:PublicBaseUrl"]
                ?? $"https://{_bucket}.s3.{region}.amazonaws.com").TrimEnd('/');

            _s3 = new AmazonS3Client(accessKey, secretKey, RegionEndpoint.GetBySystemName(region));
        }

        // ── Upload ────────────────────────────────────────────────────────────
        public async Task<BlobUploadResult> UploadAsync(IFormFile file, string module, int userId)
        {
            if (!AllowedExtensions.ContainsKey(module))
                throw new ArgumentException(
                    $"Unknown module '{module}'. Allowed for public upload: {string.Join(", ", AllowedExtensions.Keys)}. " +
                    "For sensitive documents use the private upload endpoint.");

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
            var key      = $"{module}/{datePart}_{userId}_{guidPart}_{safeName}.{ext}";

            await using var stream = file.OpenReadStream();

            var putRequest = new PutObjectRequest
            {
                BucketName  = _bucket,
                Key         = key,
                InputStream = stream,
                ContentType = GetContentType(ext),
                // Public read via bucket policy — no per-object ACL required
            };

            await _s3.PutObjectAsync(putRequest);

            var fileUrl    = $"{_publicBaseUrl}/{key}";
            var fileSizeKb = (int)Math.Ceiling(file.Length / 1024.0);

            Log.Information(
                "S3 public upload: Module={Module} UserId={UserId} Key={Key} Size={SizeKb}KB Url={Url}",
                module, userId, key, fileSizeKb, fileUrl);

            return new BlobUploadResult
            {
                FileUrl    = fileUrl,
                FileKey    = null,
                FileName   = key,
                FileSizeKb = fileSizeKb,
                Module     = module,
                IsPrivate  = false
            };
        }

        // ── Delete ────────────────────────────────────────────────────────────
        public async Task<bool> DeleteAsync(string fileUrl)
        {
            try
            {
                if (!Uri.TryCreate(fileUrl, UriKind.Absolute, out var uri)) return false;
                var key = uri.AbsolutePath.TrimStart('/');
                if (string.IsNullOrWhiteSpace(key)) return false;

                await _s3.DeleteObjectAsync(_bucket, key);
                Log.Information("S3 public delete: Key={Key}", key);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "AwsS3BlobService.DeleteAsync failed for URL={Url}", fileUrl);
                return false;
            }
        }

        // ── Helpers ───────────────────────────────────────────────────────────

        private static string GetContentType(string ext) => ext switch
        {
            "jpg" or "jpeg" => "image/jpeg",
            "png"           => "image/png",
            "svg"           => "image/svg+xml",
            "mp4"           => "video/mp4",
            "mov"           => "video/quicktime",
            "webm"          => "video/webm",
            "mkv"           => "video/x-matroska",
            "m4v"           => "video/x-m4v",
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

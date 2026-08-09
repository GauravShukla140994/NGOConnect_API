using CloudinaryDotNet;
using CloudinaryDotNet.Actions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;
using System.Text.RegularExpressions;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Cloudinary storage provider — implements IBlobService.
    /// Activate by setting StorageProvider = "cloudinary" in appsettings.json.
    /// Zero other code changes required — callers depend on IBlobService only.
    ///
    /// Folder layout in Cloudinary:
    ///   ngoconnect/user-documents/
    ///   ngoconnect/user-photos/
    ///   ngoconnect/org-documents/
    ///   ngoconnect/org-logos/
    ///   ngoconnect/certificates/
    ///   ngoconnect/post-media/
    ///
    /// File naming: {yyyyMMdd}_{userId}_{8-char-guid}_{safeName}
    /// Example    : 20260710_42_a1b2c3d4_passport   (image — no ext in publicId)
    ///            : 20260710_42_a1b2c3d4_contract.pdf (raw — ext included in publicId)
    ///
    /// Resource type is auto-detected from extension:
    ///   image → jpg, jpeg, png, svg
    ///   video → mp4, mov, webm, mkv, m4v
    ///   raw   → pdf (and any other non-media type)
    /// </summary>
    public class CloudinaryBlobService : IBlobService
    {
        private readonly Cloudinary _cloudinary;

        // ── Module validation — mirrors LocalFileService exactly ─────────────
        private static readonly Dictionary<string, HashSet<string>> AllowedExtensions =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"]      = ["pdf", "jpg", "jpeg", "png"],
            ["user-photos"]         = ["jpg", "jpeg", "png"],
            ["org-documents"]       = ["pdf", "jpg", "jpeg", "png"],
            ["org-logos"]           = ["jpg", "jpeg", "png", "svg"],
            ["certificates"]        = ["pdf"],
            ["post-media"]          = ["jpg", "jpeg", "png", "mp4", "mov", "webm", "mkv", "m4v"],
            ["review-media"]        = ["jpg", "jpeg", "png", "mp4", "mov"],
            ["support-attachments"] = ["jpg", "jpeg", "png", "pdf", "mp4", "mov"],
        };

        private static readonly HashSet<string> AllowedModules =
            new(AllowedExtensions.Keys, StringComparer.OrdinalIgnoreCase);

        private static readonly Dictionary<string, long> MaxFileSizePerModule =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"] = 10L * 1024 * 1024,
            ["user-photos"]    =  5L * 1024 * 1024,
            ["org-documents"]  = 10L * 1024 * 1024,
            ["org-logos"]      =  5L * 1024 * 1024,
            ["certificates"]   =  5L * 1024 * 1024,
            ["post-media"]     = 50L * 1024 * 1024,
            ["review-media"]   = 20L * 1024 * 1024,
        };

        public CloudinaryBlobService(IConfiguration config)
        {
            var cloudName = config["Cloudinary:CloudName"]
                ?? throw new InvalidOperationException("Cloudinary:CloudName not configured in appsettings.");
            var apiKey    = config["Cloudinary:ApiKey"]
                ?? throw new InvalidOperationException("Cloudinary:ApiKey not configured in appsettings.");
            var apiSecret = config["Cloudinary:ApiSecret"]
                ?? throw new InvalidOperationException("Cloudinary:ApiSecret not configured in appsettings.");

            var account  = new Account(cloudName, apiKey, apiSecret);
            _cloudinary  = new Cloudinary(account);
            _cloudinary.Api.Secure = true;   // Always use HTTPS URLs
        }

        // ── Upload ────────────────────────────────────────────────────────────
        public async Task<BlobUploadResult> UploadAsync(IFormFile file, string module, int userId)
        {
            // Validate module
            if (!AllowedModules.Contains(module))
                throw new ArgumentException(
                    $"Unknown upload module '{module}'. Allowed: {string.Join(", ", AllowedModules)}");

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

            // Build Cloudinary public ID
            var datePart = DateTime.UtcNow.ToString("yyyyMMdd");
            var guidPart = Guid.NewGuid().ToString("N")[..8];
            var safeName = SanitizeName(Path.GetFileNameWithoutExtension(file.FileName));
            var publicId = $"ngoconnect/{module}/{datePart}_{userId}_{guidPart}_{safeName}";

            // Upload
            await using var stream = file.OpenReadStream();
            var uploadResult = await UploadStreamAsync(stream, ext, publicId);

            if (uploadResult.Error != null)
                throw new Exception($"Cloudinary upload failed: {uploadResult.Error.Message}");

            var fileUrl    = uploadResult.SecureUrl.ToString();
            var fileSizeKb = (int)Math.Ceiling(file.Length / 1024.0);

            Log.Information(
                "Cloudinary upload: Module={Module} UserId={UserId} PublicId={PublicId} Size={SizeKb}KB Url={Url}",
                module, userId, uploadResult.PublicId, fileSizeKb, fileUrl);

            return new BlobUploadResult
            {
                FileUrl    = fileUrl,
                FileName   = uploadResult.PublicId,   // PublicId stored — enables delete-by-id in future
                FileSizeKb = fileSizeKb,
                Module     = module
            };
        }

        // ── Delete ────────────────────────────────────────────────────────────
        public async Task<bool> DeleteAsync(string fileUrl)
        {
            try
            {
                if (!Uri.TryCreate(fileUrl, UriKind.Absolute, out var uri)) return false;

                // Cloudinary URL path: /{cloudName}/{resourceType}/upload/[v{version}/]{publicId}[.{ext}]
                var segments = uri.AbsolutePath.TrimStart('/').Split('/');
                if (segments.Length < 4) return false;

                // Index 1 = resource type ("image", "video", "raw")
                var cloudResourceType = segments[1] switch
                {
                    "video" => ResourceType.Video,
                    "raw"   => ResourceType.Raw,
                    _       => ResourceType.Image
                };

                // Everything after /upload/ (index 3 onward)
                var afterUpload = segments.Skip(3).ToList();

                // Skip version segment if present (e.g. "v1720000000")
                if (afterUpload.Count > 0 && Regex.IsMatch(afterUpload[0], @"^v\d+$"))
                    afterUpload.RemoveAt(0);

                if (afterUpload.Count == 0) return false;

                var pathWithExt = string.Join("/", afterUpload);

                // Raw publicId includes extension; image/video publicId does not.
                string publicId;
                if (cloudResourceType == ResourceType.Raw)
                {
                    publicId = pathWithExt;
                }
                else
                {
                    var lastSlash = pathWithExt.LastIndexOf('/');
                    var lastDot   = pathWithExt.LastIndexOf('.');
                    publicId = (lastDot > lastSlash)
                        ? pathWithExt[..lastDot]
                        : pathWithExt;
                }

                var result = await _cloudinary.DestroyAsync(
                    new DeletionParams(publicId) { ResourceType = cloudResourceType });

                Log.Information("Cloudinary delete: PublicId={PublicId} Result={Result}", publicId, result.Result);
                return result.Result == "ok";
            }
            catch (Exception ex)
            {
                Log.Error(ex, "CloudinaryBlobService.DeleteAsync failed for URL={Url}", fileUrl);
                return false;
            }
        }

        // ── Private Helpers ───────────────────────────────────────────────────

        /// <summary>
        /// Dispatch to the correct Cloudinary upload params type based on file extension.
        /// image → ImageUploadParams | video → VideoUploadParams | pdf/raw → RawUploadParams
        /// All return UploadResult (common base class).
        /// </summary>
        private async Task<UploadResult> UploadStreamAsync(Stream stream, string ext, string publicId)
        {
            var resourceType = GetResourceType(ext);

            switch (resourceType)
            {
                case "video":
                    return await _cloudinary.UploadAsync(new VideoUploadParams
                    {
                        File      = new FileDescription(publicId, stream),
                        PublicId  = publicId,
                        Overwrite = false
                    });

                case "raw":
                    // For raw resources the extension must be part of the PublicId
                    var rawPublicId = $"{publicId}.{ext}";
                    return await _cloudinary.UploadAsync(new RawUploadParams
                    {
                        File      = new FileDescription(rawPublicId, stream),
                        PublicId  = rawPublicId,
                        Overwrite = false
                    });

                default:   // image
                    return await _cloudinary.UploadAsync(new ImageUploadParams
                    {
                        File      = new FileDescription(publicId, stream),
                        PublicId  = publicId,
                        Overwrite = false
                    });
            }
        }

        /// <summary>Determine Cloudinary resource type from file extension.</summary>
        private static string GetResourceType(string ext) => ext switch
        {
            "mp4" or "mov" or "webm" or "mkv" or "m4v" => "video",
            "pdf"                                        => "raw",
            _                                            => "image"
        };

        /// <summary>Strip unsafe characters from the original file name portion.</summary>
        private static string SanitizeName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "file";
            var safe = new string(name.Where(c => char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return safe.Length == 0 ? "file" : safe[..Math.Min(safe.Length, 30)];
        }
    }
}

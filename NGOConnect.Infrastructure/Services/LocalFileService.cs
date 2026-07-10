using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Phase 1 storage: saves files to the local server disk.
    /// To switch to Azure/AWS/GCS, replace this registration in ServiceCollectionExtensions
    /// with AzureBlobService / S3BlobService — IBlobService callers need zero changes.
    ///
    /// Root path is read from appsettings.json key "UploadRootPath".
    ///
    /// Base URL is built DYNAMICALLY from the incoming HTTP request host so that the
    /// returned file URL is always reachable on whatever IP/port the API is running on.
    /// Fallback (e.g., background jobs): appsettings.json key "UploadBaseUrl".
    ///
    /// Folder layout:
    ///   {UploadRootPath}/
    ///     user-documents/
    ///     user-photos/
    ///     org-documents/
    ///     org-logos/
    ///     certificates/
    ///
    /// File naming: {yyyyMMdd}_{userId}_{8-char-guid}.{ext}
    /// Example    : 20260627_42_a1b2c3d4.pdf
    /// </summary>
    public class LocalFileService : IBlobService
    {
        private readonly string             _rootPath;
        private readonly string             _fallbackBaseUrl;
        private readonly IHttpContextAccessor _httpContext;

        // Allowed extensions per module — prevent arbitrary file types
        private static readonly Dictionary<string, HashSet<string>> AllowedExtensions =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"] = ["pdf", "jpg", "jpeg", "png"],
            ["user-photos"]    = ["jpg", "jpeg", "png"],
            ["org-documents"]  = ["pdf", "jpg", "jpeg", "png"],
            ["org-logos"]      = ["jpg", "jpeg", "png", "svg"],
            ["certificates"]   = ["pdf"],
            ["post-media"]     = ["jpg", "jpeg", "png", "mp4", "mov", "webm", "mkv", "m4v"],
        };

        private static readonly HashSet<string> AllowedModules =
            new(AllowedExtensions.Keys, StringComparer.OrdinalIgnoreCase);

        // Max file size per module (videos need more headroom)
        private static readonly Dictionary<string, long> MaxFileSizePerModule =
            new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"] = 10L * 1024 * 1024,
            ["user-photos"]    =  5L * 1024 * 1024,
            ["org-documents"]  = 10L * 1024 * 1024,
            ["org-logos"]      =  5L * 1024 * 1024,
            ["certificates"]   =  5L * 1024 * 1024,
            ["post-media"]     = 50L * 1024 * 1024,   // 50 MB — covers short videos
        };

        public LocalFileService(IConfiguration config, IHttpContextAccessor httpContext)
        {
            _rootPath        = config["UploadRootPath"]
                               ?? Path.Combine(Directory.GetCurrentDirectory(), "uploads");

            // Fallback only — used when HttpContext is unavailable (e.g., background jobs)
            _fallbackBaseUrl = (config["UploadBaseUrl"] ?? "http://localhost:5000/uploads")
                               .TrimEnd('/');

            _httpContext = httpContext;
        }

        // ── Build base URL from current request ───────────────────────────────────
        // If a real HTTP request is in scope, use its scheme + host so the URL works
        // on whatever IP/port the API is being accessed (dev, LAN, staging, prod).
        // Falls back to the appsettings value for background/non-request contexts.
        private string GetBaseUrl()
        {
            var req = _httpContext.HttpContext?.Request;
            if (req is null) return _fallbackBaseUrl;

            return $"{req.Scheme}://{req.Host}/uploads";
        }

        public async Task<BlobUploadResult> UploadAsync(IFormFile file, string module, int userId)
        {
            // ── Validate module ───────────────────────────────────
            if (!AllowedModules.Contains(module))
                throw new ArgumentException($"Unknown upload module '{module}'. " +
                    $"Allowed: {string.Join(", ", AllowedModules)}");

            // ── Validate file ─────────────────────────────────────
            if (file == null || file.Length == 0)
                throw new ArgumentException("No file provided or file is empty.");

            var maxBytes = MaxFileSizePerModule.TryGetValue(module, out var mb) ? mb : 10L * 1024 * 1024;
            if (file.Length > maxBytes)
                throw new ArgumentException(
                    $"File size {file.Length / 1024 / 1024}MB exceeds the {maxBytes / 1024 / 1024}MB limit for module '{module}'.");

            var ext = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
            if (!AllowedExtensions[module].Contains(ext))
                throw new ArgumentException(
                    $"File type '.{ext}' is not allowed for module '{module}'. " +
                    $"Allowed: {string.Join(", ", AllowedExtensions[module].Select(e => "." + e))}");

            // ── Build safe file name ──────────────────────────────
            var datePart = DateTime.UtcNow.ToString("yyyyMMdd");
            var guidPart = Guid.NewGuid().ToString("N")[..8];   // 8-char hex
            var safeOrig = SanitizeName(Path.GetFileNameWithoutExtension(file.FileName));
            var fileName = $"{datePart}_{userId}_{guidPart}_{safeOrig}.{ext}";

            // ── Ensure directory exists ───────────────────────────
            var moduleDir = Path.Combine(_rootPath, module);
            Directory.CreateDirectory(moduleDir);

            // ── Write to disk ─────────────────────────────────────
            var filePath = Path.Combine(moduleDir, fileName);
            await using var stream = new FileStream(filePath, FileMode.Create, FileAccess.Write);
            await file.CopyToAsync(stream);

            var fileSizeKb = (int)Math.Ceiling(file.Length / 1024.0);

            // URL uses the dynamic base — always matches the caller's IP/port
            var fileUrl = $"{GetBaseUrl()}/{module}/{fileName}";

            Log.Information("File uploaded: Module={Module} UserId={UserId} File={FileName} Size={SizeKb}KB Url={Url}",
                module, userId, fileName, fileSizeKb, fileUrl);

            return new BlobUploadResult
            {
                FileUrl    = fileUrl,
                FileName   = fileName,
                FileSizeKb = fileSizeKb,
                Module     = module
            };
        }

        public Task<bool> DeleteAsync(string fileUrl)
        {
            try
            {
                // Parse the URL and extract the path segment after "/uploads/"
                // Works regardless of host/IP/port — no string comparison against _baseUrl needed.
                if (!Uri.TryCreate(fileUrl, UriKind.Absolute, out var uri))
                    return Task.FromResult(false);

                // AbsolutePath example: /uploads/user-photos/20260627_4_abc_photo.jpg
                var abs = uri.AbsolutePath.TrimStart('/');   // "uploads/user-photos/..."

                const string prefix = "uploads/";
                if (!abs.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    return Task.FromResult(false);

                var relative = abs[prefix.Length..]   // "user-photos/20260627_4_abc_photo.jpg"
                    .Replace('/', Path.DirectorySeparatorChar);

                var filePath = Path.Combine(_rootPath, relative);

                if (!File.Exists(filePath))
                    return Task.FromResult(true);   // Already gone — treat as success

                File.Delete(filePath);
                Log.Information("File deleted: {FilePath}", filePath);
                return Task.FromResult(true);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "DeleteAsync failed for URL={FileUrl}", fileUrl);
                return Task.FromResult(false);
            }
        }

        // ── Helpers ───────────────────────────────────────────────

        /// <summary>Strip unsafe characters from the original file name portion.</summary>
        private static string SanitizeName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "file";
            var safe = new string(name.Where(c => char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return safe.Length == 0 ? "file" : safe[..Math.Min(safe.Length, 30)];
        }
    }
}

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
    /// Base URL is read from appsettings.json key "UploadBaseUrl".
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
        private readonly string _rootPath;
        private readonly string _baseUrl;

        // Allowed extensions per module — prevent arbitrary file types
        private static readonly Dictionary<string, HashSet<string>> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
        {
            ["user-documents"] = ["pdf", "jpg", "jpeg", "png"],
            ["user-photos"]    = ["jpg", "jpeg", "png"],
            ["org-documents"]  = ["pdf", "jpg", "jpeg", "png"],
            ["org-logos"]      = ["jpg", "jpeg", "png", "svg"],
            ["certificates"]   = ["pdf"]
        };

        private static readonly HashSet<string> AllowedModules =
            new(AllowedExtensions.Keys, StringComparer.OrdinalIgnoreCase);

        // Max file size: 10 MB
        private const long MaxFileSizeBytes = 10 * 1024 * 1024;

        public LocalFileService(IConfiguration config)
        {
            _rootPath = config["UploadRootPath"]
                ?? Path.Combine(Directory.GetCurrentDirectory(), "uploads");

            _baseUrl = (config["UploadBaseUrl"] ?? "http://localhost:5000/uploads")
                .TrimEnd('/');
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

            if (file.Length > MaxFileSizeBytes)
                throw new ArgumentException($"File size {file.Length / 1024}KB exceeds the 10MB limit.");

            var ext = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
            if (!AllowedExtensions[module].Contains(ext))
                throw new ArgumentException(
                    $"File type '.{ext}' is not allowed for module '{module}'. " +
                    $"Allowed: {string.Join(", ", AllowedExtensions[module].Select(e => "." + e))}");

            // ── Build safe file name ──────────────────────────────
            var datePart  = DateTime.UtcNow.ToString("yyyyMMdd");
            var guidPart  = Guid.NewGuid().ToString("N")[..8];   // 8-char hex
            var safeOrig  = SanitizeName(Path.GetFileNameWithoutExtension(file.FileName));
            var fileName  = $"{datePart}_{userId}_{guidPart}_{safeOrig}.{ext}";

            // ── Ensure directory exists ───────────────────────────
            var moduleDir = Path.Combine(_rootPath, module);
            Directory.CreateDirectory(moduleDir);

            // ── Write to disk ─────────────────────────────────────
            var filePath = Path.Combine(moduleDir, fileName);
            await using var stream = new FileStream(filePath, FileMode.Create, FileAccess.Write);
            await file.CopyToAsync(stream);

            var fileSizeKb = (int)Math.Ceiling(file.Length / 1024.0);
            var fileUrl    = $"{_baseUrl}/{module}/{fileName}";

            Log.Information("File uploaded: Module={Module} UserId={UserId} File={FileName} Size={SizeKb}KB",
                module, userId, fileName, fileSizeKb);

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
                // Convert URL back to physical path
                if (!fileUrl.StartsWith(_baseUrl, StringComparison.OrdinalIgnoreCase))
                    return Task.FromResult(false);

                var relativePath = fileUrl[_baseUrl.Length..].TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                var filePath     = Path.Combine(_rootPath, relativePath);

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

            // Keep only alphanumeric, dash, underscore — max 30 chars
            var safe = new string(name.Where(c => char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return safe.Length == 0 ? "file" : safe[..Math.Min(safe.Length, 30)];
        }
    }
}

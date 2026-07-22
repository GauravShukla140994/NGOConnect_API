using System.Security.Cryptography;
using System.Text;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// AES-256-GCM implementation of IUrlTokenService.
    ///
    /// Security properties:
    ///   - Confidentiality: AES-256 cipher — key is never in client code
    ///   - Integrity:       GCM authentication tag (16 bytes) — tampered tokens rejected
    ///   - Randomness:      Per-encryption random 12-byte nonce — same ID → different token each time
    ///   - URL safety:      Output is URL-safe Base64 (no +, /, or = characters)
    ///
    /// Token byte layout: [ nonce (12) | tag (16) | ciphertext (N) ]
    /// For "ORG:55" (6 bytes), total = 34 bytes → 46 URL-safe Base64 chars.
    ///
    /// Key management:
    ///   Settings table → SettingKey = "URL_SHARE_SECRET_KEY"
    ///   Value = 64-char lowercase hex string representing 32 bytes.
    ///   Generate once: Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower()
    /// </summary>
    public class UrlTokenService : IUrlTokenService
    {
        private const int NonceSize = 12;   // AES-GCM standard nonce (96-bit)
        private const int TagSize   = 16;   // AES-GCM authentication tag (128-bit)

        private readonly byte[] _key;

        public UrlTokenService(ISettingsCache settings)
        {
            try
            {
                var hex = settings.GetValue("URL_SHARE_SECRET_KEY")?.Trim();

                if (string.IsNullOrEmpty(hex) || hex.Length != 64)
                    throw new InvalidOperationException(
                        "URL_SHARE_SECRET_KEY in Settings table must be a 64-character hex string (32 bytes). " +
                        "Generate with: Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower()");

                _key = Convert.FromHexString(hex);
            }
            catch (Exception ex) when (ex is not InvalidOperationException)
            {
                Log.Error(ex, "UrlTokenService: failed to load URL_SHARE_SECRET_KEY from SettingsCache");
                throw new InvalidOperationException(
                    "UrlTokenService could not initialise — URL_SHARE_SECRET_KEY missing or invalid.", ex);
            }
        }

        // ── Encrypt ─────────────────────────────────────────────────────────────
        public string Encrypt(string entityType, int id)
        {
            var plaintext  = Encoding.UTF8.GetBytes($"{entityType.ToUpper()}:{id}");
            var nonce      = RandomNumberGenerator.GetBytes(NonceSize);
            var ciphertext = new byte[plaintext.Length];
            var tag        = new byte[TagSize];

            using var aes = new AesGcm(_key, TagSize);
            aes.Encrypt(nonce, plaintext, ciphertext, tag);

            // Layout: nonce | tag | ciphertext
            var result = new byte[NonceSize + TagSize + ciphertext.Length];
            Buffer.BlockCopy(nonce,      0, result, 0,                      NonceSize);
            Buffer.BlockCopy(tag,        0, result, NonceSize,              TagSize);
            Buffer.BlockCopy(ciphertext, 0, result, NonceSize + TagSize,    ciphertext.Length);

            return Base64UrlEncode(result);
        }

        // ── Decrypt ─────────────────────────────────────────────────────────────
        public (string EntityType, int Id)? Decrypt(string token)
        {
            try
            {
                var data = Base64UrlDecode(token);

                // Minimum valid length: nonce + tag only (zero-length plaintext not expected but handled)
                if (data.Length < NonceSize + TagSize)
                    return null;

                var nonce      = data[..NonceSize];
                var tag        = data[NonceSize..(NonceSize + TagSize)];
                var ciphertext = data[(NonceSize + TagSize)..];
                var plaintext  = new byte[ciphertext.Length];

                using var aes = new AesGcm(_key, TagSize);
                aes.Decrypt(nonce, ciphertext, tag, plaintext);   // throws if tag invalid

                // Parse payload "ENTITYTYPE:ID"
                var payload = Encoding.UTF8.GetString(plaintext);
                var sep     = payload.IndexOf(':');
                if (sep <= 0) return null;

                var entityType = payload[..sep];
                if (!int.TryParse(payload[(sep + 1)..], out var id) || id <= 0)
                    return null;

                return (entityType, id);
            }
            catch (CryptographicException)
            {
                // Tag verification failed — token tampered or wrong key
                return null;
            }
            catch
            {
                // Malformed Base64, unexpected format, etc.
                return null;
            }
        }

        // ── Helpers ─────────────────────────────────────────────────────────────

        /// <summary>Encodes bytes to RFC 4648 §5 URL-safe Base64 (no padding).</summary>
        private static string Base64UrlEncode(byte[] data) =>
            Convert.ToBase64String(data)
                   .TrimEnd('=')
                   .Replace('+', '-')
                   .Replace('/', '_');

        /// <summary>Decodes RFC 4648 §5 URL-safe Base64 (with or without padding).</summary>
        private static byte[] Base64UrlDecode(string s)
        {
            s = s.Replace('-', '+').Replace('_', '/');
            // Re-add stripped padding
            s += (s.Length % 4) switch { 2 => "==", 3 => "=", _ => string.Empty };
            return Convert.FromBase64String(s);
        }
    }
}

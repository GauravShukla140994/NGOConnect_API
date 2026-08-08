namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Encrypts and decrypts public-facing share tokens that hide raw numeric IDs.
    /// Used to avoid exposing sequential DB IDs in shareable URLs like /ngo/55.
    ///
    /// Payload format: "{EntityType}:{Id}"  e.g.  "ORG:55"  or  "OPP:3"
    /// Token format:   URL-safe Base64 of  nonce(12) ‖ tag(16) ‖ ciphertext(N)
    /// Algorithm:      AES-256-GCM
    /// Key source:     ISettingsCache → URL_SHARE_SECRET_KEY (64-char hex = 32 bytes)
    /// </summary>
    public interface IUrlTokenService
    {
        /// <summary>
        /// Encrypts an entity type + numeric ID into a URL-safe token string.
        /// </summary>
        /// <param name="entityType">Short uppercase label: "ORG" or "OPP"</param>
        /// <param name="id">Positive database primary key</param>
        /// <returns>URL-safe Base64 token (~46 characters)</returns>
        string Encrypt(string entityType, int id);

        /// <summary>
        /// Decrypts and validates a token produced by <see cref="Encrypt"/>.
        /// Returns null if the token is invalid, tampered, or malformed.
        /// </summary>
        /// <param name="token">URL-safe Base64 token from a shared link</param>
        /// <returns>(EntityType, Id) tuple on success; null on failure</returns>
        (string EntityType, int Id)? Decrypt(string token);
    }
}

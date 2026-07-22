-- ═══════════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: URL Share Token Encryption (v4.9)
-- Date   : 2026-07-22
-- Purpose:
--   Shared URLs like https://ripplehub.app/ngo/55 expose raw numeric
--   database IDs, allowing ID enumeration attacks.  This patch adds the
--   AES-256-GCM secret key to the Settings table so the backend can
--   encrypt those IDs into opaque tokens before sharing.
--
-- What this patch does:
--   • Inserts one row into Settings:
--       SECURITY / URL_SHARE_SECRET_KEY
--     (INSERT IGNORE — safe to re-run; will not overwrite an existing key)
--
-- ⚠️  ACTION REQUIRED before running:
--   1. Generate a secure 32-byte key:
--        openssl rand -hex 32
--        — OR —
--        (PowerShell): [System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLower()
--   2. Replace the placeholder below with the output (64 hex characters).
--   3. Use a DIFFERENT key for staging and production.
--   4. Store the key somewhere safe (password manager) — if lost, all
--      existing share links become undecryptable.
--
-- NO stored procedure changes — encryption is handled entirely in C#.
-- ═══════════════════════════════════════════════════════════════════════

-- Replace this placeholder with your generated key BEFORE running:
SET @ShareKey = 'REPLACE_WITH_OPENSSL_RAND_HEX_32_OUTPUT';

-- Validate key length (must be exactly 64 hex chars = 32 bytes)
SELECT IF(
    LENGTH(@ShareKey) = 64 AND @ShareKey REGEXP '^[0-9a-fA-F]+$',
    'KEY OK — proceeding',
    '⛔ KEY INVALID — must be exactly 64 hex characters. Abort and fix before continuing.'
) AS PreflightCheck;

-- Insert the key (INSERT IGNORE — will not overwrite if already set)
INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic)
VALUES (
    'SECURITY',
    'URL_SHARE_SECRET_KEY',
    @ShareKey,
    'STRING',
    'AES-256-GCM key (64-char hex / 32 bytes) used to encrypt share URL tokens. Never expose publicly. Rotate by updating this value and redeploying — old links will break.',
    0   -- IsPublic = 0 — NEVER returned to frontend
);

-- Confirm insertion
SELECT
    SettingKey,
    LEFT(SettingValue, 8) AS KeyPreview,   -- show only first 8 chars for safety
    '...(hidden)' AS Rest,
    IsPublic,
    CreatedAt
FROM Settings
WHERE SettingKey = 'URL_SHARE_SECRET_KEY';

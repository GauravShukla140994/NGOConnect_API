-- ============================================================
-- patch_public_global_stats.sql
-- New no-auth Public_GetGlobalStats SP + GLOBAL_STATS_* Settings —
-- backs the Website's "Global exploration" section (Countries /
-- Organisations / Volunteers / Raised). See Public_GetGlobalStats
-- and PublicStatsDal.cs for full design rationale.
--
-- Run on: local → Railway staging → Railway production
-- Safe to re-run: DROP+CREATE and INSERT IGNORE are idempotent.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS Public_GetGlobalStats //
CREATE PROCEDURE Public_GetGlobalStats()
BEGIN
    SELECT
        (SELECT COUNT(DISTINCT o.Country) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS TotalCountries,
        (SELECT COUNT(*) FROM Organisations o
            JOIN LookupValues sv ON o.StatusLkpId = sv.LookupValueId
            WHERE o.IsDeleted = 0 AND sv.ValueCode = 'APPROVED') AS TotalOrgs,
        (SELECT COUNT(DISTINCT u.UserId) FROM Users u
            JOIN OrgMembers om ON om.UserId = u.UserId AND om.IsDeleted = 0
            JOIN LookupValues sv ON om.StatusLkpId = sv.LookupValueId
            WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND sv.ValueCode = 'APPROVED') AS TotalVolunteers;
END //

DELIMITER ;

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES
('PLATFORM', 'GLOBAL_STATS_MIN_COUNTRIES',  '1',        'NUMBER', 'Website Global exploration section — floor shown for Countries until real count exceeds it.',    0),
('PLATFORM', 'GLOBAL_STATS_MIN_ORGS',       '50',       'NUMBER', 'Website Global exploration section — floor shown for Organisations until real count exceeds it.', 0),
('PLATFORM', 'GLOBAL_STATS_MIN_VOLUNTEERS', '4000',     'NUMBER', 'Website Global exploration section — floor shown for Volunteers until real count exceeds it.',    0),
('PLATFORM', 'GLOBAL_STATS_RAISED_DISPLAY', '1000000',  'NUMBER', 'Website Global exploration section — static "Raised" display value. Not DB-driven (2026-08-17 product decision).', 0),
('PLATFORM', 'GLOBAL_STATS_CACHE_MINUTES',  '10',       'NUMBER', 'How long /api/v1/public/global-stats caches its DB query result in memory before re-querying.', 0);

INSERT IGNORE INTO SchemaVersions (Version, Description, CreatedBy)
VALUES ('v5.2-public-global-stats', 'Public_GetGlobalStats SP + GLOBAL_STATS_* Settings for the website Global exploration section.', 'System');

-- ============================================================
-- VERIFICATION QUERIES (run after applying)
-- ============================================================
-- CALL Public_GetGlobalStats();
-- SELECT SettingKey, SettingValue FROM Settings WHERE SettingGroup = 'PLATFORM' AND SettingKey LIKE 'GLOBAL_STATS_%';
-- IMPORTANT: after applying, RESTART the API process — SettingsCache is loaded
-- once at startup and MySqlConnector caches SP metadata per connection pool;
-- neither picks up a brand-new SP/setting until the process restarts.

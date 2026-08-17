using Microsoft.Extensions.Caching.Memory;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// Backs GET /api/v1/public/global-stats (no auth) — the Website's "Global
    /// exploration" section (Countries / Organisations / Volunteers / Raised).
    ///
    /// Security notes (this endpoint is fully unauthenticated, public internet):
    ///   - Zero input parameters accepted from the caller at all — nothing to
    ///     validate, sanitize, or inject through. The SP takes no arguments.
    ///   - Only aggregate COUNT(...) numbers are ever returned — no row-level
    ///     org/user data, no IDs, no PII, nothing an attacker could pivot on.
    ///   - The real DB query result is cached in-memory (IMemoryCache) for
    ///     GLOBAL_STATS_CACHE_MINUTES (Settings, default 10 min). A flood of
    ///     requests against this public endpoint hits the cache, not the DB —
    ///     this is the primary hardening against scraping/DoS-by-refresh, on
    ///     top of the platform's existing global rate limiter (100 req/min/IP).
    ///   - Display floors (GLOBAL_STATS_MIN_*) come from ISettingsCache, which
    ///     is itself zero-DB (loaded once at startup) — blending never adds a
    ///     DB round trip.
    /// </summary>
    public class PublicStatsDal : BaseDal, IPublicStatsDal
    {
        private const string CacheKey = "public-global-stats:raw";

        private readonly ISettingsCache _settings;
        private readonly IMemoryCache   _cache;

        public PublicStatsDal(IDbProvider db, ISettingsCache settings, IMemoryCache cache) : base(db)
        {
            _settings = settings;
            _cache    = cache;
        }

        public async Task<ApiResponse<DynamicRow>> GetGlobalStatsAsync()
        {
            try
            {
                var raw = await _cache.GetOrCreateAsync(CacheKey, async entry =>
                {
                    var cacheMinutes = _settings.GetValue<int>("GLOBAL_STATS_CACHE_MINUTES", 10);
                    entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(Math.Max(1, cacheMinutes));

                    var row = await ExecuteDynamicGetAsync("Public_GetGlobalStats");
                    return row ?? new DynamicRow();
                });

                var actualCountries  = raw?.Get<int>("totalCountries")  ?? 0;
                var actualOrgs       = raw?.Get<int>("totalOrgs")       ?? 0;
                var actualVolunteers = raw?.Get<int>("totalVolunteers") ?? 0;

                var minCountries  = _settings.GetValue<int>("GLOBAL_STATS_MIN_COUNTRIES", 1);
                var minOrgs       = _settings.GetValue<int>("GLOBAL_STATS_MIN_ORGS", 50);
                var minVolunteers = _settings.GetValue<int>("GLOBAL_STATS_MIN_VOLUNTEERS", 4000);
                var raisedDisplay = _settings.GetValue<long>("GLOBAL_STATS_RAISED_DISPLAY", 1_000_000);

                // Blended, public-facing shape only — never leak the raw actual counts
                // (not sensitive, but no reason to expose internal DB numbers either).
                var result = new DynamicRow
                {
                    ["countries"]     = Math.Max(actualCountries, minCountries),
                    ["organisations"] = Math.Max(actualOrgs, minOrgs),
                    ["volunteers"]    = Math.Max(actualVolunteers, minVolunteers),
                    ["raised"]        = raisedDisplay,
                };

                return ApiResponse<DynamicRow>.Success(result);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetGlobalStatsAsync failed");
                return ApiResponse<DynamicRow>.Failure("Stats unavailable.", "INTERNAL_ERROR");
            }
        }
    }
}

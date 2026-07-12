using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using NGOConnect.Core.Interfaces;
using NGOConnect.Infrastructure.Cache;
using NGOConnect.Infrastructure.DAL;
using NGOConnect.Infrastructure.DbProvider;
using NGOConnect.Infrastructure.Services;
using Serilog;
// v4.0 new namespaces registered below (models live in Core, DALs in Infrastructure)

namespace NGOConnect.API.Extensions
{
    public static class ServiceCollectionExtensions
    {
        // ── Database Provider ────────────────────────────────────
        /// <summary>
        /// Register the DB provider.
        /// TO SWITCH DB: change MySqlDbProvider to SqlServerDbProvider here. That's all.
        /// </summary>
        public static IServiceCollection AddDatabaseProvider(
            this IServiceCollection services)
        {
            services.AddScoped<IDbProvider, MySqlDbProvider>();
            return services;
        }

        // ── DAL Registrations ────────────────────────────────────
        public static IServiceCollection AddDataAccessLayer(
            this IServiceCollection services)
        {
            // Foundation
            services.AddScoped<IAuthDal,         AuthDal>();
            services.AddScoped<ILookupDal,        LookupDal>();
            services.AddScoped<IUserDal,          UserDal>();
            // Settings
            services.AddScoped<ISettingsDal,      SettingsDal>();
            services.AddSingleton<ISettingsCache, SettingsCache>();
            // Organisation
            services.AddScoped<IOrgDal,           OrgDal>();
            // Projects
            services.AddScoped<IProjectDal,       ProjectDal>();
            // Applications
            services.AddScoped<IApplicationDal,   ApplicationDal>();
            // Feed / Posts
            services.AddScoped<IPostDal,          PostDal>();
            services.AddScoped<IFeedDal,          FeedDal>();
            // Community
            services.AddScoped<ICommunityDal,     CommunityDal>();
            // Donations
            services.AddScoped<IDonationDal,      DonationDal>();
            // SOS
            services.AddScoped<ISosDal,           SosDal>();
            // Notifications
            services.AddScoped<INotificationDal,  NotificationDal>();
            // v4.0 NEW modules
            services.AddScoped<IWithdrawalDal,    WithdrawalDal>();
            services.AddScoped<ICertificateDal,   CertificateDal>();
            services.AddScoped<ISkillRatingDal,   SkillRatingDal>();
            services.AddScoped<IBadgeDal,         BadgeDal>();
            // v4.5 — Super Admin module (new SPs only, see SuperAdminDal for isolation notes)
            services.AddScoped<ISuperAdminDal,    SuperAdminDal>();
            return services;
        }

        // ── Blob / File Storage ──────────────────────────────────
        /// <summary>
        /// Register the file storage provider based on appsettings.json "StorageProvider" key.
        ///
        ///   "local"      → LocalFileService       (server disk, good for dev + VPS)
        ///   "cloudinary" → CloudinaryBlobService  (Cloudinary CDN, good for staging + prod)
        ///
        /// TO SWITCH: change StorageProvider value in appsettings.json. Zero code changes needed.
        /// IHttpContextAccessor is always registered — required by LocalFileService to build
        /// dynamic file URLs that reflect the actual IP/port (LAN, dev, staging, prod).
        /// </summary>
        public static IServiceCollection AddBlobService(
            this IServiceCollection services, IConfiguration config)
        {
            services.AddHttpContextAccessor();

            var provider = (config["StorageProvider"] ?? "local").Trim().ToLowerInvariant();

            if (provider == "cloudinary")
            {
                services.AddScoped<IBlobService, CloudinaryBlobService>();
                Log.Information("BlobService: CloudinaryBlobService (CDN)");
            }
            else
            {
                services.AddScoped<IBlobService, LocalFileService>();
                Log.Information("BlobService: LocalFileService (disk)");
            }

            return services;
        }

        // ── JWT Authentication ───────────────────────────────────
        public static IServiceCollection AddJwtAuthentication(
            this IServiceCollection services, IConfiguration config)
        {
            var jwtKey = config["Jwt:Key"]
                ?? throw new InvalidOperationException("Jwt:Key not configured");

            services
                .AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                    options.DefaultChallengeScheme    = JwtBearerDefaults.AuthenticationScheme;
                })
                .AddJwtBearer(options =>
                {
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuer           = true,
                        ValidateAudience         = true,
                        ValidateLifetime         = true,
                        ValidateIssuerSigningKey = true,
                        ValidIssuer              = config["Jwt:Issuer"],
                        ValidAudience            = config["Jwt:Audience"],
                        IssuerSigningKey         = new SymmetricSecurityKey(
                                                       Encoding.UTF8.GetBytes(jwtKey)),
                        ClockSkew                = TimeSpan.Zero  // No grace period on expiry
                    };

                    // Return 401 JSON instead of redirect
                    options.Events = new JwtBearerEvents
                    {
                        OnChallenge = async context =>
                        {
                            context.HandleResponse();
                            context.Response.StatusCode  = 401;
                            context.Response.ContentType = "application/json";
                            await context.Response.WriteAsync(
                                "{\"isSuccess\":0,\"message\":\"Unauthorized. Please login.\",\"errorCode\":\"UNAUTHORIZED\"}");
                        }
                    };
                });

            return services;
        }

        // ── Swagger with JWT support ─────────────────────────────
        public static IServiceCollection AddSwaggerWithJwt(
            this IServiceCollection services)
        {
            services.AddSwaggerGen(options =>
            {
                options.SwaggerDoc("v1", new OpenApiInfo
                {
                    Title       = "NGO Connect API",
                    Version     = "v1",
                    Description = "NGO Connect — The LinkedIn of Social Impact",
                    Contact     = new OpenApiContact
                    {
                        Name  = "NGO Connect Team",
                        Email = "api@ngoconnect.app"
                    }
                });

                // Enable [Authorize] padlock in Swagger UI
                options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
                {
                    Name         = "Authorization",
                    Type         = SecuritySchemeType.Http,
                    Scheme       = "bearer",
                    BearerFormat = "JWT",
                    In           = ParameterLocation.Header,
                    Description  = "Enter your JWT token. Example: eyJhbGci..."
                });

                options.AddSecurityRequirement(new OpenApiSecurityRequirement
                {
                    {
                        new OpenApiSecurityScheme
                        {
                            Reference = new OpenApiReference
                            {
                                Type = ReferenceType.SecurityScheme,
                                Id   = "Bearer"
                            }
                        },
                        Array.Empty<string>()
                    }
                });
            });

            return services;
        }

        // ── CORS ─────────────────────────────────────────────────
        public static IServiceCollection AddNgoConnectCors(
            this IServiceCollection services, IConfiguration config)
        {
            var allowedOrigins = config.GetSection("Cors:AllowedOrigins")
                                       .Get<string[]>() ?? [];

            services.AddCors(options =>
            {
                options.AddPolicy("NGOConnectPolicy", policy =>
                {
                    if (allowedOrigins.Length > 0)
                        policy.WithOrigins(allowedOrigins);
                    else
                        policy.AllowAnyOrigin(); // Dev only

                    policy.AllowAnyHeader()
                          .AllowAnyMethod();
                });
            });

            return services;
        }
    }
}

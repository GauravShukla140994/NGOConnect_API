using System.Text;
using Hangfire;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using NGOConnect.Core.Interfaces;
using NGOConnect.Infrastructure.Cache;
using NGOConnect.Infrastructure.DAL;
using NGOConnect.Infrastructure.DbProvider;
using NGOConnect.Infrastructure.Jobs;
using NGOConnect.Infrastructure.Services;
using Serilog;

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
            // Notifications + FCM (singleton — FirebaseApp is process-wide)
            services.AddScoped<INotificationDal,  NotificationDal>();
            services.AddSingleton<IFCMService,    FCMService>();
            // v4.0 NEW modules
            services.AddScoped<IWithdrawalDal,    WithdrawalDal>();
            services.AddScoped<ICertificateDal,   CertificateDal>();
            services.AddScoped<ISkillRatingDal,   SkillRatingDal>();
            services.AddScoped<IBadgeDal,         BadgeDal>();
            // v4.5 — Super Admin module (new SPs only, see SuperAdminDal for isolation notes)
            services.AddScoped<ISuperAdminDal,    SuperAdminDal>();
            // v4.9 — Org Member Invitations
            services.AddScoped<IOrgInviteDal,     OrgInviteDal>();
            // v4.9 — URL Share Token encryption (AES-256-GCM; key from Settings table)
            services.AddSingleton<IUrlTokenService, UrlTokenService>();
            // v4.9 — Help & Support (Phase 1: logs to AuditLogs, sends email)
            services.AddScoped<ISupportDal, SupportDal>();
            // v5.0 — Marketing & Communication Center (Phase 0 + Phase 1, Push + Email only)
            services.AddScoped<ICampaignDal,               CampaignDal>();
            services.AddScoped<ICommunicationPreferenceDal, CommunicationPreferenceDal>();
            services.AddScoped<ICampaignDispatchService,    CampaignDispatchService>();
            // v5.1 — NGO Reviews
            services.AddScoped<IOrgReviewDal,              OrgReviewDal>();
            // v5.2 — Certificate HTML service (server-side template renderer; Singleton — reads template once at startup)
            services.AddSingleton<ICertificateHtmlService>(sp =>
            {
                var env = sp.GetRequiredService<IWebHostEnvironment>();
                return new CertificateHtmlService(env.ContentRootPath);
            });
            return services;
        }

        // ── Hangfire Background Jobs ─────────────────────────────
        /// <summary>
        /// v5.0 NEW: Marketing & Communication Center, Phase 0 foundation.
        /// Reuses the same MySQL connection string as everything else (DefaultConnection) —
        /// no second database. Storage schema is created/migrated automatically by
        /// Hangfire.MySqlStorage itself on first run (PrepareSchemaIfNecessary), so it is
        /// intentionally NOT part of NGOConnect_Complete_Setup_v4.9.sql.
        /// </summary>
        public static IServiceCollection AddHangfireBackgroundJobs(
            this IServiceCollection services, IConfiguration configuration)
        {
            var connectionString = configuration.GetConnectionString("DefaultConnection")
                ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found — required for Hangfire storage too.");

            services.AddHangfire(config => config
                .SetDataCompatibilityLevel(Hangfire.CompatibilityLevel.Version_180)
                .UseSimpleAssemblyNameTypeSerializer()
                .UseRecommendedSerializerSettings()
                .UseStorage(new Hangfire.MySql.MySqlStorage(connectionString, new Hangfire.MySql.MySqlStorageOptions
                {
                    TablesPrefix           = "Hangfire",
                    PrepareSchemaIfNecessary = true,
                    QueuePollInterval      = TimeSpan.FromSeconds(15)
                })));

            services.AddHangfireServer(options =>
            {
                options.WorkerCount = Math.Max(1, Environment.ProcessorCount);
                options.Queues      = new[] { "default" };
            });

            // v5.1: Register RECURRING + FLEXIBLE background job classes (transient — Hangfire
            // resolves these via DI on each execution, so Scoped deps work safely inside them)
            services.AddTransient<AutoActivateProjectsJob>();
            services.AddTransient<TransitionToClosingJob>();
            services.AddTransient<MarkNoShowJob>();
            services.AddTransient<AutoCheckoutMissedJob>();

            return services;
        }

        // ── Email Service ────────────────────────────────────────
        /// <summary>
        /// Register email service based on "EmailProvider" config key.
        ///
        ///   "smtp"   → SmtpEmailService (MailKit)       — local dev only (SMTP blocked on Railway/PaaS)
        ///   "resend" → ResendEmailService (HTTPS API)   — staging + production (not blocked by Railway)
        ///   "awsses" → AwsSesEmailService (AWS SDK)     — future production via AWS SES (requires approval)
        ///
        /// Railway env var: EmailProvider = resend
        /// Resend config:   Resend__ApiKey (Railway env var) / Resend:ApiKey (appsettings.Development.json)
        /// Note: Raw SMTP (port 587/465) is blocked by Railway. Always use resend or awsses on Railway.
        /// </summary>
        public static IServiceCollection AddEmailService(
            this IServiceCollection services, IConfiguration config)
        {
            var provider = (config["EmailProvider"] ?? "smtp").Trim().ToLowerInvariant();

            switch (provider)
            {
                case "awsses":
                    services.AddSingleton<IEmailService, AwsSesEmailService>();
                    Log.Information("EmailService: AwsSesEmailService (AWS SES SDK)");
                    break;

                case "resend":
                    services.AddHttpClient<IEmailService, ResendEmailService>();
                    Log.Information("EmailService: ResendEmailService (Resend HTTPS API)");
                    break;

                default: // "smtp"
                    services.AddSingleton<IEmailService, SmtpEmailService>();
                    Log.Information("EmailService: SmtpEmailService (SMTP / MailKit) — use only in local dev");
                    break;
            }

            return services;
        }

        // ── SMS Service ──────────────────────────────────────────
        /// <summary>
        /// Register Fast2SMS gateway for mobile OTP delivery.
        /// Config: appsettings.json → "Sms" section.
        ///   Sms:ApiKey     — Fast2SMS API key (gitignored / Railway env var Sms__ApiKey)
        ///   Sms:Route      — "q" (quick/test) | "dlt" (production, TRAI-registered)
        ///   Sms:SenderId   — DLT route only (registered sender ID)
        ///   Sms:TemplateId — DLT route only (TRAI-approved template ID)
        /// </summary>
        public static IServiceCollection AddSmsService(
            this IServiceCollection services)
        {
            services.AddHttpClient<ISmsService, Fast2SmsService>();
            return services;
        }

        // ── Blob / File Storage ──────────────────────────────────
        /// <summary>
        /// Register the file storage providers based on appsettings.json "StorageProvider" key.
        ///
        ///   "local"      → IBlobService: LocalFileService        (disk)          dev / VPS
        ///                  IPrivateBlobService: FallbackPrivateBlobService
        ///
        ///   "cloudinary" → IBlobService: CloudinaryBlobService   (CDN)           staging
        ///                  IPrivateBlobService: FallbackPrivateBlobService
        ///
        ///   "awss3"      → IBlobService: AwsS3BlobService        (public bucket) production
        ///                  IPrivateBlobService: AwsS3PrivateBlobService (private bucket)
        ///
        /// TO SWITCH: change StorageProvider in appsettings.json. Zero code changes needed.
        ///
        /// Module routing:
        ///   PUBLIC  (IBlobService)         → user-photos, org-logos, project-images, post-media
        ///   PRIVATE (IPrivateBlobService)  → user-documents, org-documents, certificates, donation-receipts
        /// </summary>
        public static IServiceCollection AddBlobService(
            this IServiceCollection services, IConfiguration config)
        {
            services.AddHttpContextAccessor();

            var provider = (config["StorageProvider"] ?? "local").Trim().ToLowerInvariant();

            switch (provider)
            {
                case "awss3":
                    services.AddScoped<IBlobService,        AwsS3BlobService>();
                    services.AddScoped<IPrivateBlobService, AwsS3PrivateBlobService>();
                    Log.Information("BlobService: AwsS3BlobService (public) + AwsS3PrivateBlobService (private)");
                    break;

                case "cloudinary":
                    services.AddScoped<IBlobService, CloudinaryBlobService>();
                    // Fallback: private docs stored via Cloudinary (acceptable for staging)
                    services.AddScoped<IPrivateBlobService, FallbackPrivateBlobService>();
                    Log.Information("BlobService: CloudinaryBlobService (CDN) + FallbackPrivateBlobService");
                    break;

                default:   // "local"
                    services.AddScoped<IBlobService, LocalFileService>();
                    services.AddScoped<IPrivateBlobService, FallbackPrivateBlobService>();
                    Log.Information("BlobService: LocalFileService (disk) + FallbackPrivateBlobService");
                    break;
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

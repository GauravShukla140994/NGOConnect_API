using Hangfire;
using Microsoft.Extensions.FileProviders;
using Serilog;
using Serilog.Events;
using NGOConnect.API.Extensions;
using NGOConnect.API.HangfireSupport;
using NGOConnect.API.Hubs;
using NGOConnect.API.Middleware;
using NGOConnect.Core.Interfaces;

// ── Serilog Bootstrap Logger ─────────────────────────────────
// Captures startup errors before the full host is built
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("NGO Connect API starting up...");

    var builder = WebApplication.CreateBuilder(args);

    // ── Serilog (full configuration from appsettings) ────────
    builder.Host.UseSerilog((context, services, configuration) =>
    {
        configuration
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Enrich.WithMachineName()
            .Enrich.WithThreadId()
            .Enrich.WithProcessId()
            .WriteTo.Console(outputTemplate:
                "[{Timestamp:HH:mm:ss} {Level:u3}] {CorrelationId} | {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path:            "logs/ngoconnect-.log",
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 30,
                outputTemplate:  "[{Timestamp:yyyy-MM-dd HH:mm:ss} {Level:u3}] {CorrelationId} | {Message:lj}{NewLine}{Exception}");
        // Future: add .WriteTo.Seq() or .WriteTo.ApplicationInsights() here
    });

    // ── Services ─────────────────────────────────────────────
    builder.Services.AddControllers();
    builder.Services.AddEndpointsApiExplorer();

    // Extension methods — each group in its own method for clarity
    builder.Services.AddDatabaseProvider();              // IDbProvider → MySqlDbProvider
    builder.Services.AddDataAccessLayer();               // All DAL registrations
    builder.Services.AddBlobService(builder.Configuration); // IBlobService → driven by StorageProvider in appsettings
    builder.Services.AddEmailService(builder.Configuration); // IEmailService → driven by EmailProvider in appsettings
    builder.Services.AddSmsService();                        // ISmsService → Fast2SmsService
    // v5.0 NEW: Marketing & Communication Center, Phase 0 — background job engine
    builder.Services.AddHangfireBackgroundJobs(builder.Configuration);
    builder.Services.AddJwtAuthentication(builder.Configuration);
    builder.Services.AddSwaggerWithJwt();
    builder.Services.AddNgoConnectCors(builder.Configuration);

    // SignalR — real-time SOS location + events
    builder.Services.AddSignalR();

    // Rate limiting (ASP.NET Core built-in, no extra package needed)
    builder.Services.AddRateLimiter(options =>
    {
        options.GlobalLimiter = System.Threading.RateLimiting.PartitionedRateLimiter
            .Create<HttpContext, string>(context =>
                System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
                    {
                        PermitLimit      = 100,
                        Window           = TimeSpan.FromMinutes(1),
                        QueueLimit       = 0
                    }));

        options.OnRejected = async (context, _) =>
        {
            context.HttpContext.Response.StatusCode = 429;
            await context.HttpContext.Response.WriteAsync(
                "{\"isSuccess\":0,\"message\":\"Too many requests. Please try again later.\",\"errorCode\":\"RATE_LIMIT_EXCEEDED\"}");
        };
    });

    // ── Sentry Error Monitoring ──────────────────────────────
    // DSN is read from config — set Sentry__Dsn as Railway env variable per environment.
    // Plan upgrades on sentry.io do NOT change the DSN — only quota limits increase.
    builder.WebHost.UseSentry(o =>
    {
        o.Dsn              = builder.Configuration["Sentry:Dsn"];
        o.Environment      = builder.Environment.EnvironmentName; // Development / Staging / Production
        o.TracesSampleRate = builder.Configuration.GetValue<double>("Sentry:TracesSampleRate", 0.2);
        o.MinimumEventLevel = Microsoft.Extensions.Logging.LogLevel.Error;
        o.Debug            = builder.Configuration.GetValue<bool>("Sentry:Debug", false);
    });

    // ── Build App ─────────────────────────────────────────────
    var app = builder.Build();

    // ── Warm up Settings Cache ────────────────────────────────
    // Must run before any request is served. RefreshAsync() loads all rows
    // from the Settings table into memory so every GetValue() call is zero-DB.
    var settingsCache = app.Services.GetRequiredService<ISettingsCache>();
    await settingsCache.RefreshAsync();
    Log.Information("SettingsCache loaded.");

    // ── Middleware Pipeline (ORDER MATTERS) ───────────────────
    // 1. Sentry request tracing — must be before other middleware
    app.UseSentryTracing();

    // 2. Correlation ID first — all subsequent middleware can use it
    app.UseMiddleware<CorrelationIdMiddleware>();

    // 3. Global exception handler — catches everything below it
    app.UseMiddleware<GlobalExceptionMiddleware>();

    // 4. Request logging
    app.UseMiddleware<RequestLoggingMiddleware>();

    // 5. Rate limiting
    app.UseRateLimiter();

    // 6. Swagger (dev + staging only)
    if (app.Environment.IsDevelopment() || app.Environment.IsStaging())
    {
        app.UseSwagger();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/swagger/v1/swagger.json", "NGO Connect API v1");
            options.RoutePrefix = "swagger";
            options.DocumentTitle = "NGO Connect API";
        });
    }

    // 6. HTTPS redirect
    if (!app.Environment.IsDevelopment())
    {
        app.UseHttpsRedirection();
    }

    // 6b. Hangfire dashboard — Marketing & Communication Center, Phase 0.
    //     Gated by HangfireDashboardAuthFilter (Development always allowed; otherwise
    //     requires Settings.COMMUNICATION.HANGFIRE_DASHBOARD_KEY, fails closed if unset).
    app.UseHangfireDashboard("/hangfire", new Hangfire.DashboardOptions
    {
        Authorization = new[] { new HangfireDashboardAuthFilter() }
    });

    // 7. Static files — serve uploaded media under /uploads/*
    //    UploadRootPath must exist; LocalFileService creates subdirectories on first upload.
    var uploadRootPath = builder.Configuration["UploadRootPath"]
        ?? Path.Combine(builder.Environment.ContentRootPath, "uploads");
    Directory.CreateDirectory(uploadRootPath);
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(uploadRootPath),
        RequestPath  = "/uploads"
    });

    // 8. CORS
    app.UseCors("NGOConnectPolicy");

    // 9. Auth
    app.UseAuthentication();
    app.UseAuthorization();

    // 10. Health check endpoint
    app.MapGet("/health", () => new { status = "healthy", timestamp = DateTime.UtcNow })
        .AllowAnonymous();

    // 11. Controllers
    app.MapControllers();

    // 12. SignalR hub
    app.MapHub<SosHub>("/hubs/sos");

    Log.Information("NGO Connect API started. Swagger: /swagger");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "NGO Connect API failed to start");
}
finally
{
    Log.CloseAndFlush();
}

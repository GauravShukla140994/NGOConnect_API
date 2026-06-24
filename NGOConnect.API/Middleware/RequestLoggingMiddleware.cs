using System.Diagnostics;
using Serilog;

namespace NGOConnect.API.Middleware
{
    /// <summary>
    /// Logs every HTTP request and response with timing.
    /// Output: [GET] /api/v1/auth/send-otp | 200 | 42ms | CorrelationId=ABC123
    /// Skips logging for health check and swagger endpoints to reduce noise.
    /// </summary>
    public class RequestLoggingMiddleware
    {
        private readonly RequestDelegate _next;
        private static readonly string[] _skipPaths =
            ["/health", "/swagger", "/favicon.ico"];

        public RequestLoggingMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var path = context.Request.Path.Value ?? string.Empty;

            // Skip noisy paths
            if (_skipPaths.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
            {
                await _next(context);
                return;
            }

            var correlationId = context.Items["CorrelationId"]?.ToString() ?? "N/A";
            var stopwatch     = Stopwatch.StartNew();

            Log.Information(
                "→ {Method} {Path} | CorrelationId={CorrelationId} | IP={IP}",
                context.Request.Method,
                context.Request.Path,
                correlationId,
                context.Connection.RemoteIpAddress);

            await _next(context);

            stopwatch.Stop();

            Log.Information(
                "← {Method} {Path} | {StatusCode} | {ElapsedMs}ms | CorrelationId={CorrelationId}",
                context.Request.Method,
                context.Request.Path,
                context.Response.StatusCode,
                stopwatch.ElapsedMilliseconds,
                correlationId);
        }
    }
}

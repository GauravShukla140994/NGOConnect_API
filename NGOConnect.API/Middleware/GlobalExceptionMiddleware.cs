using System.Net;
using System.Text.Json;
using NGOConnect.Core.Models.Common;
using Serilog;

namespace NGOConnect.API.Middleware
{
    /// <summary>
    /// Catches any unhandled exception across the entire application.
    /// Returns a clean ApiResponse instead of exposing stack traces to clients.
    /// All unhandled exceptions are logged with full context via Serilog.
    /// </summary>
    public class GlobalExceptionMiddleware
    {
        private readonly RequestDelegate _next;

        public GlobalExceptionMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            try
            {
                await _next(context);
            }
            catch (Exception ex)
            {
                var correlationId = context.Items["CorrelationId"]?.ToString() ?? "N/A";

                Log.Error(ex,
                    "Unhandled exception | CorrelationId={CorrelationId} | Path={Path} | Method={Method}",
                    correlationId,
                    context.Request.Path,
                    context.Request.Method);

                context.Response.StatusCode  = (int)HttpStatusCode.InternalServerError;
                context.Response.ContentType = "application/json";

                var response = ApiResponse.Fail(
                    "An unexpected error occurred. Please try again later.",
                    "INTERNAL_SERVER_ERROR");

                var json = JsonSerializer.Serialize(response, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });

                await context.Response.WriteAsync(json);
            }
        }
    }
}

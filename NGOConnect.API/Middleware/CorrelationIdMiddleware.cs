namespace NGOConnect.API.Middleware
{
    /// <summary>
    /// Assigns a unique CorrelationId to every request.
    /// Used in Serilog log context to trace a full request across all log entries.
    /// Client can optionally pass X-Correlation-ID header; otherwise we generate one.
    /// </summary>
    public class CorrelationIdMiddleware
    {
        private const string CorrelationIdHeader = "X-Correlation-ID";
        private readonly RequestDelegate _next;

        public CorrelationIdMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            // Use client-provided ID or generate a new one
            var correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault()
                                ?? Guid.NewGuid().ToString("N")[..16].ToUpper();

            context.Items["CorrelationId"] = correlationId;
            context.Response.Headers[CorrelationIdHeader] = correlationId;

            // Push into Serilog's log context so all log entries in this request carry it
            using (Serilog.Context.LogContext.PushProperty("CorrelationId", correlationId))
            {
                await _next(context);
            }
        }
    }
}

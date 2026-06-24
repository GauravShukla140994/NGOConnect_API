namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Unified response model for all NGO Connect API endpoints.
    /// Replaces the old ResponseModel with object ReturnValue.
    /// IsSuccess: 1 = success, 0 = failure
    /// </summary>
    public class ApiResponse<T>
    {
        public int IsSuccess { get; set; }
        public string Message { get; set; } = string.Empty;
        public T? Data { get; set; }
        public string? ErrorCode { get; set; }

        // ── Factory helpers ──────────────────────────────────────
        public static ApiResponse<T> Success(T data, string message = "Success")
            => new() { IsSuccess = 1, Message = message, Data = data };

        public static ApiResponse<T> Failure(string message, string? errorCode = null)
            => new() { IsSuccess = 0, Message = message, ErrorCode = errorCode };
    }

    /// <summary>
    /// Non-generic version for endpoints that return no data payload.
    /// </summary>
    public class ApiResponse : ApiResponse<object>
    {
        public static ApiResponse Ok(string message = "Success")
            => new() { IsSuccess = 1, Message = message };

        public static ApiResponse Fail(string message, string? errorCode = null)
            => new() { IsSuccess = 0, Message = message, ErrorCode = errorCode };
    }
}

using System.Data;

namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Result of any WRITE stored procedure (INSERT / UPDATE / DELETE).
    /// SP must always return: IsSuccess INT, Message VARCHAR, [optional extra columns]
    ///
    /// Usage in DAL:
    ///   var result = await ExecuteWriteAsync("Org_AddUpdate", cmd => { ... });
    ///   if (!result.Succeeded) return result.ToApiResponse();
    ///   var newId = Col&lt;int&gt;(result.Row!, "OrgId");
    /// </summary>
    public class WriteResult
    {
        public bool    Succeeded { get; init; }
        public string  Message   { get; init; } = string.Empty;

        /// <summary>
        /// Full SP result row. Available only when Succeeded = true.
        /// Use Col&lt;T&gt;(result.Row!, "ColumnName") to read extra columns (e.g. OrgId, UserId).
        /// </summary>
        public DataRow? Row { get; init; }

        /// <summary>Converts to non-generic ApiResponse (no data payload).</summary>
        public ApiResponse ToApiResponse()
            => Succeeded ? ApiResponse.Ok(Message) : ApiResponse.Fail(Message);

        /// <summary>
        /// Converts to typed ApiResponse&lt;T&gt; with a data payload.
        /// Usage: result.ToApiResponse(Col&lt;int&gt;(result.Row!, "OrgId"))
        /// </summary>
        public ApiResponse<T> ToApiResponse<T>(T data)
            => Succeeded
                ? ApiResponse<T>.Success(data, Message)
                : ApiResponse<T>.Failure(Message);
    }
}

using System.Data;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;

namespace NGOConnect.Infrastructure.DAL
{
    /// <summary>
    /// Base class for ALL DAL classes in NGO Connect.
    ///
    /// Core Mandate: Dynamic / Efficient / Super Fast / Change-Adoptable
    ///   – 8 SP execution patterns to match every use case
    ///   – Col&lt;T&gt; safe DBNull helper — no NullReferenceException on DB reads
    ///   – DynamicRow for display queries — SP change = zero C# change
    ///   – DataReader path for hot list endpoints — 2-5x faster than DataSet
    ///
    /// Architecture: Controller → Interface → DAL (inherits BaseDal) → SP → MySQL
    /// Never instantiate BaseDal directly. Inherit and inject IDbProvider.
    /// </summary>
    public abstract class BaseDal
    {
        protected readonly IDbProvider _db;

        protected BaseDal(IDbProvider db) => _db = db;

        // ══════════════════════════════════════════════════════════════
        // Col<T> — Safe DBNull Helper
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Read a column value safely. Returns default(T) on DBNull or missing column.
        /// Handles: int, string, bool (MySQL TINYINT), DateTime, decimal, etc.
        ///
        /// Examples:
        ///   Col&lt;int&gt;(row, "OrgId")            returns 0 if DBNull
        ///   Col&lt;string&gt;(row, "OrgName")        returns null if DBNull
        ///   Col&lt;bool&gt;(row, "IsActive")          handles TINYINT(1) → bool
        ///   Col&lt;DateTime&gt;(row, "CreatedAt")     returns DateTime.MinValue if DBNull
        /// </summary>
        protected static T Col<T>(DataRow row, string col)
        {
            if (!row.Table.Columns.Contains(col)) return default!;
            var val = row[col];
            if (val is DBNull || val is null) return default!;

            // Special case: bool from MySQL TINYINT(1) — comes as sbyte/byte/int
            if (typeof(T) == typeof(bool))
            {
                var boolVal = Convert.ToInt32(val) != 0;
                return (T)(object)boolVal;
            }

            // Special case: string — avoid Convert.ChangeType overhead
            if (typeof(T) == typeof(string))
                return (T)(object)val.ToString()!;

            return (T)Convert.ChangeType(val, typeof(T));
        }

        /// <summary>
        /// Read a nullable struct column. Returns null on DBNull or missing column.
        /// Use for: DateTime?, int?, decimal?, bool?
        ///
        /// Example:
        ///   ColNullable&lt;DateTime&gt;(row, "UpdatedAt")  returns null if not yet updated
        ///   ColNullable&lt;int&gt;(row, "DeletedBy")       returns null if not deleted
        /// </summary>
        protected static T? ColNullable<T>(DataRow row, string col) where T : struct
        {
            if (!row.Table.Columns.Contains(col)) return null;
            var val = row[col];
            if (val is DBNull || val is null) return null;

            if (typeof(T) == typeof(bool))
                return (T?)(object)(Convert.ToInt32(val) != 0);

            return (T)Convert.ChangeType(val, typeof(T));
        }

        // ══════════════════════════════════════════════════════════════
        // 1. ExecuteWriteAsync — INSERT / UPDATE / DELETE
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute any WRITE stored procedure.
        /// SP must return: SELECT IsSuccess INT, Message VARCHAR, [optional extra columns]
        ///
        /// Usage:
        ///   var result = await ExecuteWriteAsync("Org_AddUpdate", cmd =>
        ///   {
        ///       _db.AddParameter(cmd, "p_OrgName", request.OrgName);
        ///   });
        ///   if (!result.Succeeded) return result.ToApiResponse();
        ///   var orgId = Col&lt;int&gt;(result.Row!, "OrgId");
        /// </summary>
        protected async Task<WriteResult> ExecuteWriteAsync(
            string sp, Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                return new WriteResult { Succeeded = false, Message = "Operation returned no result from database." };

            var row       = ds.Tables[0].Rows[0];
            var succeeded = Col<int>(row, "IsSuccess") == 1;
            var message   = Col<string>(row, "Message") ?? (succeeded ? "Success." : "Operation failed.");

            return new WriteResult { Succeeded = succeeded, Message = message, Row = row };
        }

        // ══════════════════════════════════════════════════════════════
        // 2. ExecuteListAsync — Small typed lists (<50 rows), DataSet
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a LIST SP and return a typed list via DataSet.
        /// Use for small, infrequently-called lists (e.g. dropdown data).
        /// For large/hot paths use ExecuteReaderListAsync instead.
        /// </summary>
        protected async Task<List<T>> ExecuteListAsync<T>(
            string sp, Func<DataRow, T> map, Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            if (ds.Tables.Count == 0) return [];

            return ds.Tables[0].Rows
                .Cast<DataRow>()
                .Select(map)
                .ToList();
        }

        // ══════════════════════════════════════════════════════════════
        // 3. ExecuteReaderListAsync — Large/hot lists, DataReader
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a LIST SP and return a typed list via DataReader.
        /// 2-5x faster than DataSet. Streams rows — never loads full result into memory.
        /// Use for: any list called frequently or expected to grow large.
        /// </summary>
        protected async Task<List<T>> ExecuteReaderListAsync<T>(
            string sp, Func<IDataReader, T> map, Action<IDbCommand>? addParams = null)
        {
            using var conn   = await _db.CreateConnectionAsync();
            using var cmd    = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            using var reader = await _db.ExecuteReaderAsync(cmd);
            var result = new List<T>();
            while (reader.Read())
                result.Add(map(reader));
            return result;
        }

        // ══════════════════════════════════════════════════════════════
        // 4. ExecutePagedListAsync — Paged typed lists
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a paged LIST SP. SP must return 2 result sets:
        ///   1st result set: the data rows (with LIMIT/OFFSET applied)
        ///   2nd result set: SELECT COUNT(*) AS TotalCount FROM ... (same WHERE, no LIMIT)
        ///
        /// Usage:
        ///   var paged = await ExecutePagedListAsync("Project_List", MapProject, pageNumber, pageSize, cmd =>
        ///   {
        ///       _db.AddParameter(cmd, "p_PageNumber", pageNumber);
        ///       _db.AddParameter(cmd, "p_PageSize",   pageSize);
        ///   });
        /// </summary>
        protected async Task<PagedResult<T>> ExecutePagedListAsync<T>(
            string sp, Func<DataRow, T> map,
            int pageNumber, int pageSize,
            Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            var items = ds.Tables.Count > 0
                ? ds.Tables[0].Rows.Cast<DataRow>().Select(map).ToList()
                : new List<T>();

            var totalCount = ds.Tables.Count > 1 && ds.Tables[1].Rows.Count > 0
                ? Col<int>(ds.Tables[1].Rows[0], "TotalCount")
                : items.Count;

            return new PagedResult<T>
            {
                Items      = items,
                TotalCount = totalCount,
                PageNumber = pageNumber,
                PageSize   = pageSize
            };
        }

        // ══════════════════════════════════════════════════════════════
        // 5. ExecuteGetAsync — Single row, typed
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a GET SP and map to a single typed entity.
        /// Returns null if SP returns no rows (entity not found).
        /// Use for: GetById, GetProfile, GetSettings on core typed entities.
        /// </summary>
        protected async Task<T?> ExecuteGetAsync<T>(
            string sp, Func<DataRow, T> map, Action<IDbCommand>? addParams = null)
            where T : class
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return null;

            return map(ds.Tables[0].Rows[0]);
        }

        // ══════════════════════════════════════════════════════════════
        // 6. ExecuteDynamicListAsync — Display queries, shape = SP output
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a display/dashboard/feed SP. Returns DynamicRow list.
        /// Adding a column to the SP tomorrow → appears in JSON with zero C# changes.
        /// Use for: admin search, feed, activity log, analytics, impact reports.
        /// </summary>
        protected async Task<List<DynamicRow>> ExecuteDynamicListAsync(
            string sp, Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            if (ds.Tables.Count == 0) return [];

            return ds.Tables[0].Rows
                .Cast<DataRow>()
                .Select(r => new DynamicRow(r))
                .ToList();
        }

        // ══════════════════════════════════════════════════════════════
        // 7. ExecuteDynamicGetAsync — Single dynamic row
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a display SP that returns a single row.
        /// Returns null if SP returns no rows.
        /// Use for: public profiles, dashboard KPI cards, single record display views.
        /// </summary>
        protected async Task<DynamicRow?> ExecuteDynamicGetAsync(
            string sp, Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return null;

            return new DynamicRow(ds.Tables[0].Rows[0]);
        }

        // ══════════════════════════════════════════════════════════════
        // 8. ExecuteDynamicPagedListAsync — Paged display queries
        // ══════════════════════════════════════════════════════════════

        /// <summary>
        /// Execute a paged display SP. Returns PagedResult&lt;DynamicRow&gt;.
        /// SP must return 2 result sets (same as ExecutePagedListAsync).
        /// Use for: paged admin search, paged feed, paged impact reports.
        /// </summary>
        protected async Task<PagedResult<DynamicRow>> ExecuteDynamicPagedListAsync(
            string sp, int pageNumber, int pageSize,
            Action<IDbCommand>? addParams = null)
        {
            using var conn = await _db.CreateConnectionAsync();
            using var cmd  = _db.CreateCommand(sp, conn);
            addParams?.Invoke(cmd);

            var ds = await _db.FillDataSetAsync(cmd);

            var items = ds.Tables.Count > 0
                ? ds.Tables[0].Rows.Cast<DataRow>().Select(r => new DynamicRow(r)).ToList()
                : new List<DynamicRow>();

            var totalCount = ds.Tables.Count > 1 && ds.Tables[1].Rows.Count > 0
                ? Col<int>(ds.Tables[1].Rows[0], "TotalCount")
                : items.Count;

            return new PagedResult<DynamicRow>
            {
                Items      = items,
                TotalCount = totalCount,
                PageNumber = pageNumber,
                PageSize   = pageSize
            };
        }
    }
}

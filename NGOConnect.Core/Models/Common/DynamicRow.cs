using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NGOConnect.Core.Models.Common
{
    /// <summary>
    /// Used for display / dashboard / feed SPs where the shape is driven by the SP, not a typed model.
    ///
    /// Core Mandate — Change-Adoptable:
    ///   SP adds a new column tomorrow → appears in JSON with ZERO C# changes.
    ///
    /// Behaviour:
    ///   SP column  OrgName     → JSON key  orgName      (auto camelCase)
    ///   SP column  MemberCount → JSON key  memberCount
    ///   DBNull                 → null in JSON
    ///
    /// Usage:
    ///   var row = await ExecuteDynamicGetAsync("Dashboard_GetKpis", ...);
    ///   int count = row?.Get&lt;int&gt;("memberCount") ?? 0;
    /// </summary>
    [JsonConverter(typeof(DynamicRowConverter))]
    public class DynamicRow
    {
        private readonly Dictionary<string, object?> _store;

        /// <summary>Construct an empty DynamicRow for manually building ad-hoc responses.</summary>
        public DynamicRow()
        {
            _store = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Indexer for setting/getting values. Key is auto-camelCased on write.
        /// Enables: data["someId"] = 42; — consistent with SP-sourced rows.
        /// </summary>
        public object? this[string key]
        {
            get => _store.TryGetValue(key, out var v) ? v : null;
            set => _store[ToCamelCase(key)] = value;
        }

        /// <summary>Construct from DataSet DataRow (used by ExecuteDynamicListAsync / ExecuteDynamicGetAsync).</summary>
        public DynamicRow(DataRow row)
        {
            _store = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            foreach (DataColumn col in row.Table.Columns)
                _store[ToCamelCase(col.ColumnName)] = row[col] == DBNull.Value ? null : row[col];
        }

        /// <summary>Construct from DataReader (used by ExecuteDynamicReaderListAsync if needed).</summary>
        public DynamicRow(IDataReader reader)
        {
            _store = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < reader.FieldCount; i++)
                _store[ToCamelCase(reader.GetName(i))] = reader.IsDBNull(i) ? null : reader.GetValue(i);
        }

        /// <summary>
        /// Get a typed value by camelCase key. Returns default(T) if key is missing or null.
        /// Key is case-insensitive: Get&lt;int&gt;("memberCount") == Get&lt;int&gt;("MemberCount")
        /// </summary>
        public T? Get<T>(string key)
        {
            if (!_store.TryGetValue(key, out var v) || v is null) return default;
            if (v is T typed) return typed;

            // Convert.ChangeType throws InvalidCastException ("Invalid cast from 'X' to
            // 'System.Nullable`1[...]'") if given a Nullable<T> target type directly — it
            // does not unwrap nullable types on its own. Convert against the underlying
            // type instead; the (T) cast below is a legal unboxing conversion from object
            // to Nullable<T> as long as the boxed value's type matches the underlying type,
            // which it now does.
            //
            // This specifically matters for MySqlConnector, which returns MySQL numeric
            // columns using their closest CLR type rather than always widening to the type
            // a caller asks for — e.g. INT UNSIGNED comes back as System.UInt32, not Int32,
            // so Get<int?>("someUnsignedIntColumn") would otherwise throw even though the
            // value fits comfortably in an int.
            var targetType = Nullable.GetUnderlyingType(typeof(T)) ?? typeof(T);
            var converted  = Convert.ChangeType(v, targetType);
            return (T)converted;
        }

        /// <summary>Raw dictionary — used by DynamicRowConverter for JSON serialization.</summary>
        public Dictionary<string, object?> AsDictionary() => _store;

        /// <summary>Remove a key from the store. Useful in DAL post-processing to strip
        /// intermediate columns (e.g. PollOptionsJson) before serialization.</summary>
        public bool Remove(string key) => _store.Remove(ToCamelCase(key));

        private static string ToCamelCase(string s) =>
            string.IsNullOrEmpty(s) ? s : char.ToLowerInvariant(s[0]) + s[1..];
    }

    /// <summary>
    /// Serializes DynamicRow as a flat JSON object — not wrapped in {"data": ...}.
    /// ApiResponse&lt;DynamicRow&gt; serializes as: { "isSuccess": 1, "data": { "orgName": "...", ... } }
    /// </summary>
    public class DynamicRowConverter : JsonConverter<DynamicRow>
    {
        public override DynamicRow Read(ref Utf8JsonReader reader, Type typeToConvert,
            JsonSerializerOptions options)
            => throw new NotSupportedException("DynamicRow is write-only for JSON.");

        public override void Write(Utf8JsonWriter writer, DynamicRow value,
            JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            foreach (var (key, val) in value.AsDictionary())
            {
                writer.WritePropertyName(key);
                JsonSerializer.Serialize(writer, val, options);
            }
            writer.WriteEndObject();
        }
    }
}

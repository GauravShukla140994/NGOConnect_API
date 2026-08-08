using System.Data;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Lookup;
using Serilog;

namespace NGOConnect.Infrastructure.DAL
{
    public class LookupDal : ILookupDal
    {
        private readonly IDbProvider _db;

        public LookupDal(IDbProvider db)
        {
            _db = db;
        }

        public async Task<ApiResponse<List<LookupTypeModel>>> GetAllTypesAsync()
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Lookup_GetAllTypes", conn);
                var ds = await _db.FillDataSetAsync(cmd);

                var result = ds.Tables[0].Rows
                    .Cast<DataRow>()
                    .Select(MapType)
                    .ToList();

                return ApiResponse<List<LookupTypeModel>>.Success(result);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetAllTypesAsync failed");
                return ApiResponse<List<LookupTypeModel>>.Failure("Failed to load lookup types.", "LOOKUP_ERROR");
            }
        }

        public async Task<ApiResponse<List<LookupValueModel>>> GetValuesByTypeCodeAsync(string typeCode)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd  = _db.CreateCommand("Lookup_GetValuesByTypeCode", conn);
                _db.AddParameter(cmd, "p_TypeCode", typeCode);

                var ds = await _db.FillDataSetAsync(cmd);

                var result = ds.Tables[0].Rows
                    .Cast<DataRow>()
                    .Select(MapValue)
                    .ToList();

                return ApiResponse<List<LookupValueModel>>.Success(result);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetValuesByTypeCodeAsync failed for TypeCode={TypeCode}", typeCode);
                return ApiResponse<List<LookupValueModel>>.Failure("Failed to load lookup values.", "LOOKUP_ERROR");
            }
        }

        /// <summary>
        /// No Lookup_GetValueByCode SP exists in DB.
        /// Calls Lookup_GetValuesByTypeCode then filters in C# — avoids an extra SP round-trip.
        /// </summary>
        public async Task<ApiResponse<LookupValueModel>> GetValueByCodeAsync(
            string typeCode, string valueCode)
        {
            try
            {
                using var conn = await _db.CreateConnectionAsync();
                using var cmd = _db.CreateCommand("Lookup_GetValueByCode", conn);
                _db.AddParameter(cmd, "p_TypeCode", typeCode);
                _db.AddParameter(cmd, "p_ValueCode", valueCode);

                var ds = await _db.FillDataSetAsync(cmd);

                var row = ds.Tables[0].Rows
                    .Cast<DataRow>()
                    .FirstOrDefault(r => r["ValueCode"]?.ToString() == valueCode);

                if (row is null)
                    return ApiResponse<LookupValueModel>.Failure(
                        $"Lookup value '{valueCode}' not found in type '{typeCode}'.", "LOOKUP_NOT_FOUND");

                return ApiResponse<LookupValueModel>.Success(MapValue(row));
            }
            catch (Exception ex)
            {
                Log.Error(ex, "GetValueByCodeAsync failed {TypeCode}/{ValueCode}", typeCode, valueCode);
                return ApiResponse<LookupValueModel>.Failure("Failed to load lookup value.", "LOOKUP_ERROR");
            }
        }

        // ── Mappers ──────────────────────────────────────────────
        private static LookupTypeModel MapType(DataRow row) => new()
        {
            LookupTypeId = Convert.ToInt32(row["LookupTypeId"]),
            TypeCode     = row["TypeCode"].ToString()!,
            TypeName     = row["TypeName"].ToString()!,
            Description  = row["Description"] == DBNull.Value ? null : row["Description"].ToString()
        };

        private static LookupValueModel MapValue(DataRow row) => new()
        {
            LookupValueId = Convert.ToInt32(row["LookupValueId"]),
            // LookupTypeId not returned by Lookup_GetValuesByTypeCode — left as 0 default
            ValueCode     = row["ValueCode"].ToString()!,
            ValueName     = row["ValueName"].ToString()!,
            Description   = row["Description"] == DBNull.Value ? null : row["Description"].ToString(),
            OrderNo       = Convert.ToInt32(row["OrderNo"]),
            IsDefault     = Convert.ToBoolean(row["IsDefault"])
        };
    }
}

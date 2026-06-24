using System.Data;

namespace NGOConnect.Core.Interfaces
{
    /// <summary>
    /// Database provider abstraction.
    /// All DAL classes inject this — never a concrete DB class directly.
    /// To switch DB: register a different implementation in Program.cs. Zero code changes in DAL.
    ///
    /// Current implementation: MySqlDbProvider
    /// Future: SqlServerDbProvider, PostgreSqlDbProvider — drop-in replacements.
    /// </summary>
    public interface IDbProvider
    {
        /// <summary>Creates and returns an open DB connection.</summary>
        Task<IDbConnection> CreateConnectionAsync();

        /// <summary>Creates a DB command for a stored procedure.</summary>
        IDbCommand CreateCommand(string storedProcedureName, IDbConnection connection);

        /// <summary>Adds a parameter to a command.</summary>
        void AddParameter(IDbCommand command, string name, object? value);

        /// <summary>Fills a DataSet using the command. Used for SP calls that return result sets.</summary>
        Task<DataSet> FillDataSetAsync(IDbCommand command);

        /// <summary>Executes a SP that returns no result set (INSERT/UPDATE/DELETE with OUT params).</summary>
        Task ExecuteNonQueryAsync(IDbCommand command);

        /// <summary>
        /// Executes a SP and returns a forward-only DataReader.
        /// Use for large/high-frequency lists — 2-5x faster and lower memory than DataSet.
        /// Caller is responsible for disposing the reader.
        /// </summary>
        Task<IDataReader> ExecuteReaderAsync(IDbCommand command);
    }
}

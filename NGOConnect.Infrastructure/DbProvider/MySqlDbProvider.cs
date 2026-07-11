using System.Data;
using Microsoft.Extensions.Configuration;
using MySqlConnector;
using NGOConnect.Core.Interfaces;

namespace NGOConnect.Infrastructure.DbProvider
{
    /// <summary>
    /// MySQL implementation of IDbProvider.
    ///
    /// TO SWITCH TO SQL SERVER:
    ///   1. Create SqlServerDbProvider : IDbProvider in this folder
    ///   2. Change registration in Program.cs:
    ///      services.AddScoped&lt;IDbProvider, SqlServerDbProvider&gt;();
    ///   3. Done. Zero changes in any DAL class.
    /// </summary>
    public class MySqlDbProvider : IDbProvider
    {
        private readonly string _connectionString;

        public MySqlDbProvider(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("DefaultConnection")
                ?? throw new InvalidOperationException(
                    "Connection string 'DefaultConnection' not found in configuration.");
        }

        public async Task<IDbConnection> CreateConnectionAsync()
        {
            var connection = new MySqlConnection(_connectionString);
            await connection.OpenAsync();
            return connection;
        }

        public IDbCommand CreateCommand(string storedProcedureName, IDbConnection connection)
        {
            var command = connection.CreateCommand();
            command.CommandText = storedProcedureName;
            command.CommandType = CommandType.StoredProcedure;
            command.CommandTimeout = 30;
            return command;
        }

        public void AddParameter(IDbCommand command, string name, object? value)
        {
            var param = command.CreateParameter();
            param.ParameterName = name;
            param.Value = value ?? DBNull.Value;
            command.Parameters.Add(param);
        }

        public async Task<DataSet> FillDataSetAsync(IDbCommand command)
        {
            // MySqlDataAdapter.Fill is synchronous — wrapping in Task.Run is an
            // anti-pattern that moves execution to a thread-pool thread, causing
            // cross-thread connection state issues with MySql.Data (DML executes
            // but does not commit). Call Fill directly on the calling thread.
            var ds = new DataSet();
            using var adapter = new MySqlDataAdapter((MySqlCommand)command);
            adapter.Fill(ds);
            return await Task.FromResult(ds);
        }

        public async Task ExecuteNonQueryAsync(IDbCommand command)
        {
            await ((MySqlCommand)command).ExecuteNonQueryAsync();
        }

        public async Task<IDataReader> ExecuteReaderAsync(IDbCommand command)
        {
            // Default behavior — allows column access by name in mappers
            // Still 2-5x faster than DataSet because rows are streamed, not fully buffered
            return await ((MySqlCommand)command).ExecuteReaderAsync();
        }
    }
}

using System.Data;
using Microsoft.Extensions.Configuration;
using MySql.Data.MySqlClient;
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
            var ds = new DataSet();
            using var adapter = new MySqlDataAdapter((MySqlCommand)command);
            await Task.Run(() => adapter.Fill(ds));
            return ds;
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

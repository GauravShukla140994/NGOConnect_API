# NGO Connect API — Setup Guide

## Solution Structure

```
NGOConnect.sln
├── NGOConnect.API              → ASP.NET Core 9 Web API (controllers, middleware, startup)
├── NGOConnect.Core             → Contracts only (models, interfaces) — no dependencies
├── NGOConnect.Infrastructure   → DB access (IDbProvider, MySqlDbProvider, all DAL classes)
└── NGOConnect.Tests            → Unit tests (xUnit + Moq + FluentAssertions)
```

## Prerequisites

- .NET 9 SDK
- MySQL 8.0+
- Visual Studio 2022 v17.8+ or Rider

## Step 1 — Database Setup

Run these SQL files in MySQL Workbench (in this order):
1. `NGOConnect_DB_Schema_Final.sql`    → Creates all 42 tables
2. `NGOConnect_Lookup_Tables.sql`      → Creates LookupTypes + LookupValues with seed data

## Step 2 — Configure Connection String

Open `NGOConnect.API/appsettings.json` and update:

```json
"ConnectionStrings": {
  "DefaultConnection": "Server=localhost;Port=3306;Database=NGOConnect;Uid=root;Pwd=YOUR_PASSWORD;"
}
```

## Step 3 — Configure JWT Secret

In `appsettings.json`, replace the JWT key with a secure 32+ character string:

```json
"Jwt": {
  "Key": "YOUR_SECURE_KEY_MINIMUM_32_CHARACTERS_HERE",
  "Issuer": "NGOConnect",
  "Audience": "NGOConnectUsers"
}
```

## Step 4 — Restore & Run

```bash
cd NGOConnect
dotnet restore
cd NGOConnect.API
dotnet run
```

API will start at: https://localhost:7001
Swagger UI: https://localhost:7001/swagger
Health check: https://localhost:7001/health

## Switching Database

To switch from MySQL to SQL Server or PostgreSQL:

1. Create a new class implementing `IDbProvider` in `NGOConnect.Infrastructure/DbProvider/`
2. In `NGOConnect.API/Extensions/ServiceCollectionExtensions.cs`, change:
   ```csharp
   services.AddScoped<IDbProvider, MySqlDbProvider>();
   // to:
   services.AddScoped<IDbProvider, SqlServerDbProvider>();
   ```
3. Zero changes required in any DAL, Controller, or Interface.

## API Endpoints (Phase 0)

### Auth
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/v1/auth/send-otp | Send OTP to mobile or email |
| POST | /api/v1/auth/verify-otp | Verify OTP, receive JWT tokens |
| POST | /api/v1/auth/refresh-token | Get new access token |
| POST | /api/v1/auth/revoke-token | Logout / revoke refresh token |

### Lookup
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/v1/lookup/types | All lookup type categories |
| GET | /api/v1/lookup/values/{typeCode} | All values for a type (e.g. GENDER) |
| GET | /api/v1/lookup/values/{typeCode}/{valueCode} | Single value |

## Logs

Logs are written to:
- Console (development)
- `logs/ngoconnect-YYYYMMDD.log` (daily rolling file, 30 days retained)

Each log entry includes: Timestamp | Level | CorrelationId | Message

## Response Format

All endpoints return `ApiResponse<T>`:

```json
{
  "isSuccess": 1,
  "message": "OTP sent successfully",
  "data": {
    "maskedRecipient": "******4321",
    "expiresInSeconds": 600
  },
  "errorCode": null
}
```

## Next Modules to Build
1. Users & Profiles
2. Organisations & Members
3. Projects & Sessions
4. Applications & Attendance
5. Feed Posts
6. Community Posts
7. Donations
8. SOS
9. Notifications

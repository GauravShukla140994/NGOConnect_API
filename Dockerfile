# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy solution + all project files first (layer cache — only re-runs restore if .csproj changes)
COPY NGOConnect.API/NGOConnect.API.csproj             NGOConnect.API/
COPY NGOConnect.Core/NGOConnect.Core.csproj           NGOConnect.Core/
COPY NGOConnect.Infrastructure/NGOConnect.Infrastructure.csproj NGOConnect.Infrastructure/

# Restore NuGet packages
RUN dotnet restore NGOConnect.API/NGOConnect.API.csproj

# Copy the rest of the source code
COPY . .

# Publish release build
RUN dotnet publish NGOConnect.API/NGOConnect.API.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

# ── Stage 2: Runtime ───────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Copy published output from build stage
COPY --from=build /app/publish .

# Railway injects PORT env var — ASP.NET Core reads ASPNETCORE_URLS
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "NGOConnect.API.dll"]

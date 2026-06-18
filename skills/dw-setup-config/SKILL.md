---
name: dw-setup-config
description: Configure Dynamicweb 10 environment and connection settings. Triggers: configuration surfaces, environment setup, connection strings, GlobalSettings, appsettings.json, environment variables, SMTP, log retention, go-live checklist. Non-triggers: upgrading versions -> dw-setup-upgrade; installing new solutions -> dw-setup-install.
---

# Dynamicweb 10 Configuration

## Configuration Files and Their Priority

Dynamicweb 10 uses a layered configuration system. All `.config` files in `/Files/` are read in **reverse alphabetical order** — files later in the alphabet win. `GlobalSettings.config` is always read last (lowest priority), so any `GlobalSettings.Database.config` or `GlobalSettings.Local.*.config` file overrides it.

| File | Location | Purpose |
|------|----------|---------|
| `appsettings.json` | App root (alongside `bin/`) | FilesPath, Database override, LogLevel |
| `appsettings.[ENV].json` | App root | Environment-specific overrides |
| `GlobalSettings.config` | `/Files/` root | All platform settings (written by admin UI) |
| `GlobalSettings.Database.config` | `/Files/` root | DB connection only — overrides GlobalSettings |
| `web.config` | Solution root (IIS only) | Environment variables, process path |
| `launchSettings.json` | Project root | VS / .NET CLI launch profiles |

## appsettings.json

Place in the application root (next to `bin/` and `wwwroot/`). Minimum useful file:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "FilesPath": "C:\\DwSolutions\\Customer1\\Files",
  "Database": {
    "Server": "localhost",
    "UserName": "sa",
    "Password": "SuperStrOng(!)Passw0rd"
  }
}
```

- `FilesPath` — overrides the default `/wwwroot/Files` location. Use `\\` on Windows, forward slashes on Linux.
- `Database.*` — overrides what is in `GlobalSettings.Database.config` for this environment. Useful for local dev pointing at a local SQL Server while the Files folder belongs to a shared solution.
- Create `appsettings.Development.json`, `appsettings.Production.json` etc. for environment-specific values.

## GlobalSettings.Database.config

The canonical way to store database credentials separately from `GlobalSettings.config`:

```xml
<?xml version="1.0"?>
<Globalsettings>
  <System>
    <Database>
      <UserName>myUsername</UserName>
      <Password>myPassword</Password>
      <Database>myDatabaseName</Database>
      <SQLServer>localhost</SQLServer>
      <IntegratedSecurity>False</IntegratedSecurity>
      <ConnectionString></ConnectionString>
    </Database>
  </System>
</Globalsettings>
```

For high-demand solutions add a timeout: `<ConnectionString>Connect Timeout=600</ConnectionString>`.

**Gitignore this file** — credentials must not be committed.

## Programmatic Access to GlobalSettings

```csharp
// Read a setting
string value = Dynamicweb.Configuration.SystemConfiguration.Instance
    .GetValue("/Globalsettings/System/Logging/MinimumLogLevel");

// Write a setting
Dynamicweb.Configuration.SystemConfiguration.Instance
    .SetValue("/Globalsettings/System/Logging/MinimumLogLevel", "Warning");
Dynamicweb.Configuration.SystemConfiguration.Instance.Save();
```

Custom config sections can be added via a class implementing `IConfigurationProvider`.

## Setting the Environment

### Via ASPNETCORE_ENVIRONMENT

Set this variable to match the suffix of your `appsettings.[ENV].json` file.

**.NET CLI:**
```powershell
dotnet run --environment Production
dotnet run --launch-profile "Development"
```

**IIS (`web.config`):**
```xml
<aspNetCore processPath="dotnet" arguments="D:\DW\10.0.0\Dynamicweb.Host.dll" ...>
  <environmentVariables>
    <environmentVariable name="ASPNETCORE_ENVIRONMENT" value="Production" />
    <environmentVariable name="DW_FilesPath" value="C:\DwSolutions\Customer1\Files" />
  </environmentVariables>
</aspNetCore>
```

## Environment Variables

All Dynamicweb config keys can be set as OS/container environment variables using the `DW_` prefix. Object hierarchy is flattened with `__`:

| OS Env Var | appsettings key | Purpose |
|-----------|----------------|---------|
| `DW_FilesPath` | `FilesPath` | Override Files folder path |
| `DW_Database__Server` | `Database.Server` | DB server hostname |
| `DW_Database__UserName` | `Database.UserName` | DB username |
| `DW_Database__Password` | `Database.Password` | DB password |
| `DW_Database__Database` | `Database.Database` | DB name |

**Docker example:**
```dockerfile
ENV DW_FilesPath=/data/Files
ENV DW_Database__Server=sql-server
ENV DW_Database__UserName=sa
ENV DW_Database__Password=MyStr0ngPass!
ENV ASPNETCORE_ENVIRONMENT=Production
```

## Admin UI Configuration Surfaces

Access via **Settings** in the Dynamicweb admin:

| Admin Path | What it controls |
|-----------|-----------------|
| Settings > System > Global Settings | `DisableDebug`, general platform switches |
| Settings > System > Web and HTTP > SMTP | SMTP server, port, credentials |
| Settings > System > Log Retention | Auto-cleanup for `Files/System/Logs` and DB log tables |
| Settings > System > System Information | Shows Bin path, release ring on cloud |
| Settings > Developer > OAuth Clients / API Keys | Headless/API authentication |
| Website Settings > Domain and URL | Domain, noindex/nofollow flags |

### SMTP

Cloud default: `smtp.dynamicweb-cms.com`. On Azure App Service, check **"Do not use SMTP pickup directory"** and use an external SMTP relay — the pickup directory is not supported on App Service.

## Dynamicweb Cloud Control Files

Place these files in `/Files/System/CloudHosting/` to trigger platform operations:

| File | Effect |
|------|--------|
| `changeversion.txt` containing `R1`–`R4` | Switch release ring |
| `recycle.txt` | Recycle the application pool |
| `restart.txt` | Full application restart |
| `BackupRestoreDB/backup.txt` | Trigger database bacpac export |

## Multi-Tenant / IIS Folder Structure

```
Drive:\
  Dynamicweb\
    DW10\
      bin\                            ← shared application binaries
    DW10 Solutions\
      solution1.yourdomain.com\
        web.config                    ← points bin path at DW10\bin
        wwwroot\
          Files\
            GlobalSettings.Database.config
      solution2.yourdomain.com\
        ...
```

## Go-Live Checklist

1. **`DisableDebug` = `true`** — Settings > System > Global Settings. Required for production performance.
2. **noindex/nofollow off** — Website Settings > Domain and URL. Defaults to `true` during setup; must be unchecked before launch.
3. **Log retention configured** — without it, `Files/System/Log` grows unboundedly.
4. **License type** — Development and Staging licenses will not run on public domains. A Live license is required.
5. **SMTP relay verified** — send a test email from the admin before go-live.
6. **`GlobalSettings.Database.config` in place and gitignored** — no DB credentials in version control.
7. **IIS app pool: `LoadUserProfile = true`** — required for Windows auth scenarios.

## Recommended .gitignore Entries

```gitignore
*.license
GlobalSettings.*.config
GlobalSettings.Local.*.config
appsettings.*.json
!appsettings.json
/Files/System/Log
/Files/System/Diagnostics
/Files/System/Indexes
Templates/Designs/**/_parsed
```

## Common Pitfalls

**Setup Guide redirect loop** — caused by: (a) `FilesPath` in `appsettings.json` not resolving, (b) bad DB credentials in `GlobalSettings.Database.config`, or (c) DB found but schema not applied. Verify each in that order.

**Config hierarchy confusion** — if a setting change in the admin UI has no effect, check whether a higher-priority `.config` file (alphabetically later) is overriding it.

**Backslash escaping** — `FilesPath` in `appsettings.json` on Windows requires double-backslash: `"C:\\DwSolutions\\Files"`.

**Azure scale-out** — Dynamicweb does not support horizontal scale-out (multiple instances). Only scale-up is supported.

## Next Steps

- **Installing a new solution?** See [dw-setup-install](../dw-setup-install)
- **Upgrading to a new version?** See [dw-setup-upgrade](../dw-setup-upgrade)
- **Adding custom config sections in code?** See [dw-extend-csharp-api](../dw-extend-csharp-api)

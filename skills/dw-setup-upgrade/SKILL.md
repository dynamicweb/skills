---
name: dw-setup-upgrade
type: flow
group: setup
description: Manage Dynamicweb 10 version upgrades and migration mechanics. Triggers: upgrading versions, migration steps, pre-upgrade checks, DW9 to DW10 migration, minor version upgrades within DW10. Non-triggers: initial setup -> dw-setup-install; configuration -> dw-setup-config.
---

# Dynamicweb 10 Upgrade Guide

## Upgrade Scope — Choose Your Approach

| Approach | Effort | Best for |
|----------|--------|---------|
| Migrate Swift 1 to DW10 | Low | Recently-built sites, keep existing features |
| Upgrade to Swift 2 on DW10 | Medium | Modern UX/editing without full rebuild |
| Full rebuild on Swift 2 | High | Sites 3+ years old or needing redesign |

## Pre-Upgrade Compatibility Checklist

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| DynamicWeb | 9.17+ | Earlier versions: first upgrade to 9.18 |
| Swift | 1.25+ | Earlier versions: upgrade to 1.26 first |
| Rapido | any | **Not compatible** — must migrate to Swift |

Before starting:
1. Upgrade DW9 to 9.18 if on 9.x–16 (9.18 shares much of the DW10 codebase, minimizing the diff).
2. Upgrade Swift to 1.26+ before the DW10 upgrade.
3. Disable all scheduled tasks in source DB: `UPDATE dbo.ScheduledTask SET TaskEnabled = 0`.
4. Audit custom code for `[Obsolete]` attributes — DW9.15+ already flags what gets removed in DW10.

## Phase A: Database Setup

Export the DW9.18 database as `.bacpac` from SSMS. For speed, you can omit these tables:
- `dbo.ActionLog`, `dbo.CommandLog`, `dbo.EmailMessage`, `dbo.EmailRecipient`
- `dbo.GeneralLog`, `dbo.RecycleBin`, `dbo.SmsMessage`, `dbo.TrackingSession`, `dbo.TrashBin`

Import to a local SQL Express instance. **Work with a copy — never the live database.**

The SQL user needs: `db_datareader`, `db_datawriter`, `db_ddladmin`.

## Phase B: Create the DW10 Project

Install project templates:
```powershell
dotnet new install Dynamicweb.ProjectTemplates
```

Scaffold the solution:
```powershell
dotnet new dw10-suite --name MyProject.Host
dotnet new classlib --name MyProject.CustomCode --framework net10.0
dotnet new classlib --name MyProject.Swift --framework net10.0
```

In `MyProject.CustomCode.csproj`:
```xml
<PackageReference Include="Dynamicweb.Suite" Version="10.*" />
```

In `MyProject.Host.csproj`:
```xml
<ProjectReference Include="..\MyProject.CustomCode\MyProject.CustomCode.csproj" />
```

In `appsettings.json` (Host project):
```json
{
  "FilesPath": "..\MyProject.Swift\Files\"
}
```

Configure `GlobalSettings.Database.config` in the Files folder:
```xml
<?xml version="1.0"?>
<Globalsettings>
  <System>
    <Database>
      <UserName>myUser</UserName>
      <Password>myPassword</Password>
      <Database>myDatabase</Database>
      <SQLServer>localhost</SQLServer>
      <IntegratedSecurity>False</IntegratedSecurity>
    </Database>
  </System>
</Globalsettings>
```

Copy the DW9 `/Files` folder into `MyProject.Swift/Files`. Do **not** copy old index files — these must be rebuilt.

## Phase C: Migrate Custom Code

Extensibility compatibility at a glance:

| Extension Point | Compatibility |
|----------------|--------------|
| Notifications | 95% |
| Providers (PriceProvider, CheckoutHandler, etc.) | 100% |
| ContentModule backend settings (.aspx) | 0% — must replace |
| DynamicWeb API | 85% |
| Ecommerce API | 90% |

**Per custom class:**
1. Create a new `classlib` targeting `net10.0`
2. Remove all `System.Web` usage — replace with `Dynamicweb.Context`
3. Switch to `PackageReference` format
4. Update NuGet references to latest `10.X`
5. Remove deprecated APIs flagged by the DW9.15 compiler warnings

**Key code migration patterns:**

```csharp
// DW9: HttpContext
var id = HttpContext.Current.Request.QueryString("ID");

// DW10: Dynamicweb.Context
var id = Dynamicweb.Context.Current.Request.QueryString["ID"];
```

```csharp
// DW9: @helper in Razor (removed)
@helper RenderItem(Item item) { ... }

// DW10: @functions block
@functions {
    void RenderItem(Item item) { ... }
}
```

**Alternative:** Use the [.NET Upgrade Assistant](https://dotnet.microsoft.com/en-us/platform/upgrade-assistant) for bulk project migrations.

## Phase D: Migrate Templates

Use the Template Compatibility debug tool at **Settings > System > Web and HTTP** to auto-convert DW9 Razor templates during development. **Disable it before go-live — it impacts performance.**

## Database Migrations — How They Work

Database migrations in DW10 are **automatic on startup**. No manual `Updates.xml` files:
- Updates are embedded in NuGet packages (`Dynamicweb`, `Dynamicweb.Ecommerce`, etc.)
- Applied updates are tracked in the `dbo.Updates` table
- Updating NuGet packages + restarting the app runs all pending migrations

The old `@1@,@2@` format for user-group relations in `AccessUser` is auto-migrated to `AccessUserGroupRelation` on first run. Any custom code reading user groups via the old format must be updated.

## Minor Version Upgrades (DW 10.x → 10.y)

1. **Update `global.json`** SDK version (e.g., `"version": "8.0.100"` → `"version": "10.0.100"`)
2. **Update `<TargetFramework>`** in `.csproj` (e.g., `net8.0` → `net10.0`)
3. **Update package references:**
   - Wildcard `Version="10.*-*"` → just rebuild: `dotnet build`
   - Pinned minor → `dotnet install Dynamicweb.Suite`
4. **Update addons via the Appstore** — addons are runtime-specific; a .NET 8 addon will not work on a .NET 10 host

## Post-Upgrade Steps

1. Rebuild all search indices (do not copy old index files)
2. Reconfigure permissions from scratch — the permission system was rebuilt in DW10
3. Re-enable scheduled tasks one by one and test each
4. Set `DisableDebug = true` in Settings > System > Global Settings
5. Remove noindex/nofollow flags in Website Settings > Domain and URL
6. Verify integration jobs (set to "log errors only" mode during testing)
7. Switch payment/shipping gateways to production mode
8. Run the Health dashboard (Insights > Monitoring > Health) for data integrity checks

## Breaking Changes to Check

| Area | Change |
|------|--------|
| Users/Groups | Relations moved from `@1@,@2@` format to `AccessUserGroupRelation` table |
| Authentication | No shared sessions between frontend/backend; external login providers removed |
| Permissions | Rebuilt from scratch — DW9 permission configs cannot be migrated |
| Products | Moved to dedicated Products area; Commerce is sales-only now |
| PIM Data Models | New concept — products can belong to multiple categories with inherited attributes |
| Updates.xml | Removed — updates are now in NuGet packages, tracked in `dbo.Updates` |

### Removed Features (no migration path)

- News v2 → Items
- Content personalization
- Leads, Maps, Old Statistics, SMS, RemoteHttp
- Sales Discounts → Discount matrix
- Datalists → Forms for editors
- Image editor, Upload manager

### Removed Providers (replace before upgrading)

- `ImageGlue` → ImageSharp
- `AbcPdf` → IronPdf
- All old external login providers → New implementations
- Old Checkout Handlers (Authorize, old Klarna) → New versions
- `Dynamicweb.SmartSearch.Providers.Lucene` → Lucene4

### Package Consolidation

Many packages merged into `Dynamicweb.Core`. If you reference these separately, switch to `Dynamicweb.Core`:
`Dynamicweb.Cache`, `Dynamicweb.Configuration`, `Dynamicweb.Data`, `Dynamicweb.Diagnostics`, `Dynamicweb.Extensibility`, `Dynamicweb.Imaging`, `Dynamicweb.Indexing`, `Dynamicweb.Logging`, `Dynamicweb.Scheduling`, `Dynamicweb.Security`, `Dynamicweb.Updates`

## DW CLI for Upgrade Workflows

```bash
npm i @dynamicweb/cli -g

dw env                                           # switch environments
dw database -e ./backup                          # export .bacpac
dw files /templates ./templates --export --recursive  # export templates
dw files ./templates /templates --import --recursive  # import templates
dw install ./bin/Release/net10.0/MyAddin.dll    # install custom addon
```

For database export, grant the DB user `db_backupoperator`:
```sql
ALTER ROLE [db_backupoperator] ADD MEMBER [yourDwDbUserName]
```

## Cloud Release Rings

Cloud-hosted solutions receive upgrades through rings R0 (cutting-edge) → R4 (stable). Production typically runs R3/R4. To change ring, place a `changeversion.txt` file containing `R1`–`R4` in `/Files/System/CloudHosting/`.

## Next Steps

- **Configuration questions?** See [dw-setup-config](../dw-setup-config)
- **After upgrade: custom backend work?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **After upgrade: providers/notifications?** See [dw-extend-providers](../dw-extend-providers)

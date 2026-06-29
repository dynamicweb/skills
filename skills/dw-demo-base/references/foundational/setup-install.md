# Foundational candidate → dw-setup-install

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 host install / scaffold-prerequisites / host-config
> knowledge, staged here for a future fold-up into `dw-setup-install`. No demo/customer content.
> When folded, move this body into `dw-setup-install` and re-target the pointers in the demo skills.
> Until then, the demo skills reference this file.

This is the platform-level "what a DW10 host needs to be installed and to run correctly" knowledge:
machine prerequisites, the mandatory host `TargetFramework`, the build-time host-config patches, the
release-ring version model, and the MSDTC / distributed-transaction prereq for multi-connection
admin operations.

## 1. Machine prerequisites

A `dotnet new dw10-suite` scaffold needs three things present on the box. Probe each; fix the cheap
ones opt-in, print+link the install-grade ones (never auto-install an SDK / service).

### .NET 10 SDK

The host runs on .NET 10 (the csproj pins `<TargetFramework>net10.0</TargetFramework>`, see §2). Net 8
SDKs may coexist for legacy compatibility, but .NET 10 must be present.

```powershell
dotnet --version                          # any installed SDK; not the authoritative check
dotnet --list-sdks | Select-String '^10\.'   # expect at least one 10.x row
```

If absent: download the latest 10.0.x from <https://dotnet.microsoft.com/download/dotnet/10.0> and run
the installer.

### Dynamicweb.ProjectTemplates

`dotnet new dw10-suite` requires the `Dynamicweb.ProjectTemplates` package. Templates are forward-only —
pin to the latest verified version.

```powershell
dotnet new list | Select-String 'dw10-suite'   # expect a row matching the template short name
```

Install (mutates user-global dotnet template config; no admin needed):

```powershell
dotnet new install Dynamicweb.ProjectTemplates::<version>
```

### SQL Express service

The `dw10-suite` first run auto-creates the database if the connecting SQL user holds `dbcreator`. SQL
Server can also crash silently, after which the host hangs on startup.

```powershell
Get-Service "MSSQL`$SQLEXPRESS" | Select-Object Name, Status   # expect Status = Running
```

Note the backtick — `$SQLEXPRESS` is a PowerShell special token unless escaped. Start a stopped
service with `Start-Service "MSSQL`$SQLEXPRESS"` (may prompt for elevation). If the service is missing
entirely, install SQL Server Express with the named instance `SQLEXPRESS`.

## 2. The host TargetFramework MUST be `net10.0`

The Dynamicweb project template ships multi-target (`<TargetFrameworks>net8.0;net10.0</TargetFrameworks>`).
**Pin to single-target `net10.0`** — non-negotiable for any host that loads the Backend MCP AddIn,
because the MCP AddIn loader hard-requires the host process to run on .NET 10.

```xml
<TargetFramework>net10.0</TargetFramework>
```

The MCP package ships only `lib/net6.0/` and `lib/net8.0/` binaries (no `net10.0/`), so the *DLLs*
load fine on net8 — but the AddIn loader's runtime check fails. Symptom: the install POST returns 200,
files drop to `wwwroot/Files/System/AddIns/Installed/Dynamicweb.MCP.<ver>/lib/`, but the AddIn never
registers, never appears in Installed Apps, and `/admin/mcp` returns 404. This is indistinguishable
from the queue-stuck DB-update bug ([`setup-upgrade.md`](setup-upgrade.md)).

**Triage in this exact order:**

1. Open the host startup log. If it says `Dynamicweb is running on .NET 8`, **the TFM is wrong** — fix
   it first. Edit csproj, restart, verify the log now says `Dynamicweb is running on .NET 10 or greater`.
2. Only after the host is confirmed on net10, look at the DB-update path ([`setup-upgrade.md`](setup-upgrade.md)).

Single-target net10 (not multi-target) keeps the compile/launch loop simple. The only reason to keep
net8 in the matrix is fallback-compatibility testing.

## 3. Build-time host-config patches

### 3.1 — `ImplicitDistributedTransactions` opt-in (.NET 7+)

Add this line at the very top of `Program.cs`, before `WebApplication.CreateBuilder`:

```csharp
System.Transactions.TransactionManager.ImplicitDistributedTransactions = true;
```

.NET 7+ changed the default for `TransactionManager.ImplicitDistributedTransactions` from `true` to
`false`. Without this opt-in, every DW10 operation that opens >1 SQL connection inside a single
`TransactionScope` fails with `System.Transactions.TransactionException: The operation is not valid for
the state of the transaction` — even when MSDTC + firewall are correctly configured. Affected hosts
include `/admin/api/AreaCopy` (creating a language layer), `/admin/api/PageCopy` (copy-with-content of
multi-paragraph pages), bulk imports / batch jobs, and any path where DW domain code uses
`Helpers.CreateTransactionScope(...)` and an inner repository call opens a fresh `SqlConnection`.

The setting is per-process; set it in `Program.cs` ahead of any DI / framework init so it is installed
before any TransactionScope opens. It is **separate from and orthogonal to** the MSDTC + firewall
configuration in §4:

- **MSDTC inbound/outbound + firewall** → makes the *transport* available.
- **`ImplicitDistributedTransactions = true`** → tells .NET 7+ the app *consents* to using it.

### 3.2 — Exclude `wwwroot\Files\System\**` from the build

`wwwroot\Files\System\` is a runtime-managed folder (AddIns, Indexes, Repositories, Log, Diagnostics).
The Web SDK's default Content glob pulls everything under `wwwroot/**` into MSBuild's item set, so a
populated host ends up tracking thousands of runtime files on every build (typically 7k+ files / 20+ MB
after first run). MSBuild's up-to-date check then walks all of them, slowing builds.

```xml
<ItemGroup>
  <!-- Runtime-managed folder (AddIns, Indexes, Repositories, Log, Diagnostics, etc.). -->
  <Content Remove="wwwroot\Files\System\**" />
  <None Remove="wwwroot\Files\System\**" />
</ItemGroup>
```

Apply at scaffold time, before the first `dotnet run` — the glob matches nothing until the host
populates the folder. The host reads/writes the folder at runtime regardless of MSBuild item
membership; excluding it from the build does not change runtime behaviour.

## 4. MSDTC for cross-connection TransactionScope

Several DW10 admin operations open multiple `SqlConnection` instances inside one `TransactionScope` —
the classic example is `/admin/api/AreaCopy` (the "+ New website Language" flow, which clones the full
content tree). The second connection's `EnlistPromotableSinglePhase` call needs all three of:

1. **MSDTC service running** AND **inbound/outbound transactions enabled** at the service level.
2. **DTC Windows Firewall rules enabled** (DTC RPC, RPC-EPMAP, TCP-In, TCP-Out).
3. **`TransactionManager.ImplicitDistributedTransactions = true`** in the host process (§3.1).

On a fresh dev box only (1) is partially true (MSDTC runs Manual with all flags off). Without all
three, AreaCopy fails with `System.Transactions.TransactionException: The operation is not valid for
the state of the transaction`, stack going through `EnlistPromotableSinglePhase` →
`SqlInternalConnection.EnlistNonNull`.

**Probe (no admin needed):**

```powershell
$dtc = Get-DtcNetworkSetting -DtcName Local -ErrorAction SilentlyContinue
$fw  = (Get-NetFirewallRule | ? { $_.DisplayName -match 'Distributed Transaction|DTC' } | ? Enabled -eq $true).Count
"InboundTx=$($dtc.InboundTransactionsEnabled) OutboundTx=$($dtc.OutboundTransactionsEnabled) FwRulesEnabled=$fw"
```

Expected: `InboundTx=True OutboundTx=True FwRulesEnabled=>0`.

**Install-grade fix (requires admin), one-time per machine, persists across reboots:**

```powershell
#requires -RunAsAdministrator
Set-DtcNetworkSetting -DtcName Local -InboundTransactionsEnabled $true -OutboundTransactionsEnabled $true -AuthenticationLevel NoAuth -Confirm:$false
Get-NetFirewallRule | ? { $_.DisplayName -match 'Distributed Transaction|DTC' } | Enable-NetFirewallRule
Restart-Service msdtc -Force
```

`AuthenticationLevel=NoAuth` is fine for a local-only dev box. **Verify after fix** with a 2-connection
`TransactionScope` (returns "OK" once wired):

```powershell
$cs = "Server=localhost\SQLEXPRESS;Database=master;Integrated Security=True;TrustServerCertificate=True"
try { $s = New-Object System.Transactions.TransactionScope; $c1 = New-Object System.Data.SqlClient.SqlConnection $cs; $c1.Open(); $c2 = New-Object System.Data.SqlClient.SqlConnection $cs; $c2.Open(); $c1.Close(); $c2.Close(); $s.Complete(); $s.Dispose(); "OK" } catch { "FAIL: $($_.Exception.Message)" }
```

If it returns "Implicit distributed transactions have not been enabled", the runtime is .NET 7+ and the
§3.1 `Program.cs` patch is still needed in the host. The PowerShell test runs in its own process that
needs the same opt-in — for the test only, set
`[System.Transactions.TransactionManager]::ImplicitDistributedTransactions = $true` first.

### 4.1 — net10 hosts: MSDTC + opt-in is still NOT sufficient for AreaCopy

On a **net10 single-target host**, an `/admin/api/AreaCopy` (full-content copy / language-layer create)
tries to promote its `TransactionScope` to MSDTC, and `System.Data.SqlClient` cannot promote on
.NET 10 — the same `TransactionException` fires even with §3.1 + §4 fully configured. The real
exception lands in `Files/System/Log/EventViewer/<guid>.log`, not the API response. Workaround:

1. Take a DB snapshot/backup (the copy then runs non-transactionally).
2. Add `Enlist=false` to the `<ConnectionString>` in `GlobalSettings.Database.config` and restart.
3. Run the AreaCopy.
4. Revert the connection string and restart again.

## 5. Release rings (regression triage only)

Dynamicweb publishes the Suite as five parallel NuGet packages — one per release ring. Ring 0
(`Dynamicweb.Suite`) is the stable default and the ring every install should ship on. Rings 1–4
(`Dynamicweb.Suite.Ring1` … `Ring4`) are earlier-cadence preview tracks (higher number = earlier ring,
faster cadence).

| Package | Ring | Versioning | Use for |
|---|---|---|---|
| `Dynamicweb.Suite` | 0 (stable) | `10.x.y` (e.g. `10.25.8`) | **Default.** Ship on this. |
| `Dynamicweb.Suite.Ring1` | 1 | `YYYY.M.D` (e.g. `2026.5.20`) | Regression triage |
| `Dynamicweb.Suite.Ring2..4` | 2–4 | `YYYY.M.D` | Internal validation tracks; rarely useful |

Browse versions at <https://www.nuget.org/packages?q=DynamicWeb.Suite>. **Mind the version-scheme
split:** Ring 0 uses semver-style `10.x.y`; Rings 1–4 use date-stamped `YYYY.M.D`. A `10.*` float will
NOT match a Ring-N package, and vice versa.

**When to swap:** only as regression triage — a bug shows on Ring 0 and you want to know whether it
reproduces on a later ring. Same result on Ring N → platform-wide bug; gone on Ring N → ring-specific,
will land in the next Ring-0 promotion. After triage, **swap back to `Dynamicweb.Suite`**.

```xml
<!-- Default -->
<PackageReference Include="Dynamicweb.Suite" Version="10.*" />
<!-- Triage on Ring 1 (bump the year prefix when crossing into a new year) -->
<PackageReference Include="Dynamicweb.Suite.Ring1" Version="2026.*" />
```

**Process-lock gotcha (MSB3026 / MSB3027).** `dotnet restore` after the swap succeeds quietly; the next
`dotnet build` / `dotnet run` fails repeatedly with `Could not copy "...\apphost.exe" ... locked by
<HostProcess> (<PID>)`. The csproj edit changes the package set MSBuild writes to `bin/`, but the
previous-ring host still has the exe + DLLs loaded. Stop the host BEFORE the next build — target it by
its launchSettings port, not its project name (a name match can kill sibling hosts that scaffold the
same project name):

```powershell
$p = Get-NetTCPConnection -LocalPort <PORT> -State Listen | Select-Object -ExpandProperty OwningProcess -Unique
if ($p) { Stop-Process -Id $p -Force }
```

If a fresh host PID appears within a second of the kill, a watch/auto-restart hook (Visual Studio
debugger, `dotnet watch`, an IDE-managed reload) is respawning it — stop the upstream source too.

## 6. Anti-patterns

- **Do not target Dynamicweb 9.x.** EOL trajectory; Dynamicweb Commerce is exclusively DW10 going
  forward. Swift 2.x explicitly drops DW9 support.
- **Do not reference the older `Dynamicweb` meta-package** (distinct from `Dynamicweb.Suite`) standalone
  in the host project. Reference `Dynamicweb.Suite` only — it transitively pulls Content + PIM +
  Commerce + Users + Files + Settings + Headless.
- **Do not use the `dotnet new dw10-cms` template** (CMS-only) for a solution that needs Commerce + PIM.
  Use `dw10-suite` (the full Suite template).

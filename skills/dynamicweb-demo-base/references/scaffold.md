# Scaffold — `dotnet new dw10-suite`

Scaffold a new Dynamicweb 10 demo project. Walk `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is **mandatory** — sister-skill path discovery (`Dynamicweb.Host.Suite/Properties/launchSettings.json`, `Dynamicweb.Host.Suite/GlobalSettings.Database.config`) depends on this name.

Suite version is whatever the template + `dotnet restore` resolve. **Version policy is out of scope for this skill** — neither pinning a specific patch nor enforcing Ring-N stability is something this skill does. If a particular demo needs a frozen version, edit its csproj directly.

---

## 1. Prerequisites

Before running `dotnet new dw10-suite`, verify:

- **.NET 10 SDK** is installed (`dotnet --list-sdks | Select-String '^10\.'` returns at least one row). Net 8 is NOT sufficient — see Section 2.1 below for why the host must run on net10.
- **`Dynamicweb.ProjectTemplates 1.26.0`** is installed (`dotnet new list | Select-String 'dw10-suite'` returns a match).
- **SQL Express service** (`MSSQL$SQLEXPRESS`) is running — needed by Section 3's first-run.

If any of these are missing, run `references/setup-checks.md` first.

---

## 2. Scaffold the per-demo project

Inside the demo solution folder (e.g. `C:\Projects\Solutions\<demo>\`):

```powershell
dotnet new dw10-suite --name Dynamicweb.Host.Suite
```

**Constraint:** `--name Dynamicweb.Host.Suite` is mandatory (the discover-from-project-files path-discovery contract). Sister skills (`dynamicweb-pim-demo`, `dynamicweb-swift-demo`) and references in this skill (`mcp-setup.md`, `setup-checks.md`'s discovery table) all assume this exact project name when reading `launchSettings.json` and `GlobalSettings.Database.config`. Renaming the host project breaks the entire downstream chain.

After the command completes, the solution folder contains a new `Dynamicweb.Host.Suite/` folder with the canonical Suite scaffold (`.csproj`, `Program.cs`, `Properties/launchSettings.json`, etc.). The csproj's `Dynamicweb.Suite` PackageReference is whatever the template ships with — leave it as-is unless the demo has a specific reason to freeze a version.

### 2.1 — TargetFramework MUST be `net10.0` (mandatory)

Template 1.26.0 ships multi-target (`<TargetFrameworks>net8.0;net10.0</TargetFrameworks>`). **Pin to single-target `net10.0`** — this is non-negotiable for any Dynamicweb demo, because every Dynamicweb demo needs the AppStore Backend MCP AddIn (per `references/mcp-setup.md`, a non-skippable canonical step), and the MCP AddIn loader hard-requires the host process to run on .NET 10:

```xml
<TargetFramework>net10.0</TargetFramework>
```

The MCP package (`Dynamicweb.MCP.0.2.0-BETA`) ships only `lib/net6.0/` and `lib/net8.0/` binaries (no `net10.0/`), so the *DLLs* themselves load fine on net8 — but the AddIn loader's runtime check fails. Symptom: install POST `/Admin/Api/AddinInstall` returns 200, files drop to `wwwroot/Files/System/AddIns/Installed/Dynamicweb.MCP.<ver>/lib/`, but the AddIn never registers, never appears in Installed Apps, and `/admin/mcp` returns 404. Indistinguishable from the queue-stuck DB-update bug (`references/db-update-recovery.md`).

**Triage in this exact order:**

1. Open the host startup log. If it says `Dynamicweb is running on .NET 8`, **the TFM is wrong** — fix this first. Edit csproj, restart, verify the log now says `Dynamicweb is running on .NET 10 or greater`.
2. Only after the host is confirmed on net10, look at the DB-update path (`references/db-update-recovery.md`).

Single-target net10 (not multi-target) keeps the compile/launch loop simple. The only reason to keep net8 in the matrix would be fallback-compatibility testing, which is out of scope for a per-demo build.

### 2.1b — Patch `Program.cs` for .NET 7+ distributed-transactions opt-in (mandatory)

**Add this line at the very top of `Program.cs`, before `WebApplication.CreateBuilder`:**

```csharp
System.Transactions.TransactionManager.ImplicitDistributedTransactions = true;
```

**Why this is mandatory on every demo:** .NET 7+ changed the default for `TransactionManager.ImplicitDistributedTransactions` from `true` to `false`. Without this opt-in, every DW10 operation that opens >1 SQL connection inside a single `TransactionScope` fails with `System.Transactions.TransactionException: The operation is not valid for the state of the transaction.` — even when MSDTC + firewall are correctly configured. The hosts affected include but are not limited to:

- `/admin/api/AreaCopy` (the "+ New website Language" admin flow — creating a language layer)
- `/admin/api/PageCopy` (copy-with-content of multi-paragraph pages)
- Bulk imports / batch jobs that fan out across services
- Any catch where DW domain code uses `Helpers.CreateTransactionScope(...)` and one of its inner repository calls opens a fresh `SqlConnection`

This setting is per-process and applies for the lifetime. Setting it in `Program.cs` ahead of any DI / framework init is the safest place — it gets installed before any TransactionScope is opened.

This is a separate prereq from the MSDTC + firewall configuration documented in `references/setup-checks.md` §"MSDTC for cross-connection TransactionScope". Both are required and orthogonal:

- **MSDTC inbound/outbound + firewall** → makes the *transport* available
- **`ImplicitDistributedTransactions = true`** → tells .NET 7+ that the app *consents* to using the transport

Without either, AreaCopy fails the same way. With both, AreaCopy completes in ~7-10s for a 95-page Swift website.

### 2.2 — Exclude `wwwroot\Files\System\**` from the build (mandatory)

`wwwroot\Files\System\` is a runtime-managed folder (AddIns, Indexes, Repositories, Log, Diagnostics, etc.). It is created and mutated by the host at runtime — none of it is source. The Web SDK's default Content glob pulls everything under `wwwroot/**` into MSBuild's item set, so a populated demo ends up tracking thousands of runtime files on every build (typical: 7k+ files / 20+ MB after first run, growing with use). MSBuild's up-to-date check then walks all of them, slowing both incremental and full builds.

Add this `<ItemGroup>` to the csproj (alongside the `Dynamicweb.Suite` package reference):

```xml
<ItemGroup>
  <!-- Runtime-managed folder (AddIns, Indexes, Repositories, Log, Diagnostics, etc.).
       Excluding from MSBuild's Content enumeration speeds up build. -->
  <Content Remove="wwwroot\Files\System\**" />
  <None Remove="wwwroot\Files\System\**" />
</ItemGroup>
```

Apply this at scaffold time, before the first `dotnet run` — the glob safely matches nothing until the host populates the folder, so the exclusion is in place from day one. The host reads/writes `wwwroot\Files\System\` at runtime regardless of MSBuild item membership; excluding it from the build does not change runtime behaviour.

### 2.3 — Release rings (regression triage only)

Dynamicweb publishes the Suite as five parallel NuGet packages — one per release ring. Ring 0 (`Dynamicweb.Suite`) is the stable default and the ring every demo ships on. Rings 1–4 (`Dynamicweb.Suite.Ring1` … `Ring4`) are earlier-cadence preview tracks — higher number = earlier ring, faster cadence.

| Package | Ring | Versioning | Use for |
|---|---|---|---|
| `Dynamicweb.Suite` | 0 (stable) | `10.x.y` (e.g. `10.25.8`) | **Default for demos.** Ship on this. |
| `Dynamicweb.Suite.Ring1` | 1 | `YYYY.M.D` (e.g. `2026.5.20`) | Regression triage |
| `Dynamicweb.Suite.Ring2..4` | 2–4 | `YYYY.M.D` | Internal validation tracks; rarely useful for demos |

Browse versions at <https://www.nuget.org/packages?q=DynamicWeb.Suite>. Mind the version-scheme split: Ring 0 uses semver-style `10.x.y`; Rings 1–4 use date-stamped `YYYY.M.D`. A `10.*` float will NOT match a Ring-N package, and vice versa.

**When to swap.** Only as a regression-triage tool: a bug shows on Ring 0 and you want to know whether it reproduces on a later ring. Same result on Ring N → platform-wide bug; gone on Ring N → ring-specific, will land in the next Ring-0 promotion. After triage, **swap back to `Dynamicweb.Suite`** before continuing the demo build. Do not ship a demo on a non-stable ring.

**Swap recipe** — edit the csproj:

```xml
<!-- Default -->
<PackageReference Include="Dynamicweb.Suite" Version="10.*" />

<!-- Triage on Ring 1 (bump the year prefix when crossing into a new year) -->
<PackageReference Include="Dynamicweb.Suite.Ring1" Version="2026.*" />
```

Then stop the running host, restore, and restart per the host-lifecycle pattern in SKILL.md.

**Process-lock gotcha (MSB3026 / MSB3027).** `dotnet restore` after the swap succeeds quietly. The next `dotnet build` / `dotnet run` then fails repeatedly with `Could not copy "...\apphost.exe" ... locked by Dynamicweb.Host.Suite (<PID>)`. The csproj edit changes the package set MSBuild wants to write to `bin/`, but the previous-ring host still has the exe + DLLs loaded. Stop the host BEFORE the next build:

```powershell
Get-Process -Name "Dynamicweb.Host.Suite" -ErrorAction SilentlyContinue | Stop-Process -Force
```

If a fresh `Dynamicweb.Host.Suite` PID appears within a second of the kill, you have a watch/auto-restart hook (Visual Studio debugger, `dotnet watch`, an IDE-managed reload). Stop the upstream source too, otherwise the loop repeats and the build keeps failing the copy step.

**Out of scope here.** The skill defaults the host to Ring 0 and never auto-pins a ring. Section 2.3 surfaces the swap only as a debugging tool — the disclaimer in this file's intro still holds: "Suite version is whatever the template + `dotnet restore` resolve".

---

## 3. First run — Setup Guide for DB + Files folder

```powershell
cd Dynamicweb.Host.Suite
dotnet run
# Open the printed https://localhost:<PORT>/ URL; complete the Setup Guide.
# SQL user needs `dbcreator` for first-run DB auto-creation.
```

The Setup Guide on first run will:

1. Auto-create the demo database under `MSSQL$SQLEXPRESS` if the connecting SQL user has `dbcreator`. The DB name defaults to the solution folder name unless overridden.
2. Initialise the `Files/` folder under `Dynamicweb.Host.Suite/wwwroot/` with the empty default structure.
3. Print a one-time admin user prompt (capture the credentials — they're needed for the admin UI walkthrough in `references/mcp-setup.md` Step 3).

Once the Setup Guide completes, the `Properties/launchSettings.json` file has its final `applicationUrl` and the `GlobalSettings.Database.config` has the actual DB name. **These two files are the source of truth for port and DB name from now on** (the discover-from-project-files rule).

---

## 4. Discover-from-project-files rule

After the first run completes, the per-demo project files are the source of truth — sister skills must read from these, not from hardcoded fallbacks:

| What | Read from | Used by |
|---|---|---|
| HTTPS port | `Dynamicweb.Host.Suite/Properties/launchSettings.json` (`applicationUrl`, HTTPS profile) | `references/mcp-setup.md` Step 1, all subsequent Management API calls |
| Database name | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` (`Database=` or `Initial Catalog=` in connection string) | Swift's [`../../dynamicweb-swift-demo/references/integrity-sweep.md`](../../dynamicweb-swift-demo/references/integrity-sweep.md) SQL probes; PIM admin/SQL recipes |
| Management API bearer token | Captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`). Storage contract is canonical in `references/mcp-setup.md` Step 6. | Swift's [`../../dynamicweb-swift-demo/references/deserialize-flow.md`](../../dynamicweb-swift-demo/references/deserialize-flow.md) + [`../../dynamicweb-swift-demo/references/integrity-sweep.md`](../../dynamicweb-swift-demo/references/integrity-sweep.md); any Management API call |

`references/mcp-setup.md` Section 1 contains the verbatim port-discovery PowerShell that reads `launchSettings.json`.

---

## 5. Anti-patterns (CLAUDE.md "What NOT to Use")

- **Do not target Dynamicweb 9.x.** EOL trajectory; Dynamicweb Commerce is exclusively DW10 going forward. Swift 2.x explicitly drops DW9 support.
- **Do not reference the older `Dynamicweb` meta-package** (distinct from `Dynamicweb.Suite`) standalone in the host project. The host should reference `Dynamicweb.Suite` only, which transitively pulls Content + PIM + Commerce + Users + Files + Settings + Headless.
- **Do not name the host project anything other than `Dynamicweb.Host.Suite`.** The path-discovery contract is hardcoded to this name across this skill and all sister skills.
- **Do not use the `dotnet new dw10-cms` template** (CMS-only) for a Dynamicweb demo that needs Commerce + PIM. Use `dw10-suite` (the full Suite template).

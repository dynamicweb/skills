# Scaffold — `dotnet new dw10-suite`

## Contents

- [1. Prerequisites](#1-prerequisites)
- [2. Scaffold the per-demo project](#2-scaffold-the-per-demo-project)
- [3. First run — Setup Guide for DB + Files folder](#3-first-run--setup-guide-for-db--files-folder)
- [4. Discover-from-project-files rule](#4-discover-from-project-files-rule)

Scaffold a new Dynamicweb 10 demo project. Walk `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is **mandatory** — sister-skill path discovery (`Dynamicweb.Host.Suite/Properties/launchSettings.json`, `Dynamicweb.Host.Suite/GlobalSettings.Database.config`) depends on this name.

Suite version is whatever the template + `dotnet restore` resolve. **Version policy is out of scope for this skill** — neither pinning a specific patch nor enforcing Ring-N stability is something this skill does. If a particular demo needs a frozen version, edit its csproj directly. (The release-ring model and the version-scheme split, for the rare regression triage, are platform knowledge — [`foundational/setup-install.md`](foundational/setup-install.md) §5.)

---

## 1. Prerequisites

Before running `dotnet new dw10-suite`, the box needs the **.NET 10 SDK**, **`Dynamicweb.ProjectTemplates`**, and a running **SQL Express service** (`MSSQL$SQLEXPRESS`). The platform-level rationale, probes, and install/fix paths for each are owned by [`foundational/setup-install.md`](foundational/setup-install.md) §1. Run the quick verification ritual in `references/setup-checks.md` first — it probes these plus the demo-specific checks (TLS env var, `gh` CLI, writable `baselines\`, versions prompt) in one pass.

---

## 2. Scaffold the per-demo project

Inside the demo solution folder (e.g. `C:\Projects\Solutions\<demo>\`):

```powershell
dotnet new dw10-suite --name Dynamicweb.Host.Suite
```

**Constraint:** `--name Dynamicweb.Host.Suite` is mandatory (the discover-from-project-files path-discovery contract). Sister skills and references in this skill (`mcp-setup.md`, `setup-checks.md`'s discovery table) all assume this exact project name when reading `launchSettings.json` and `GlobalSettings.Database.config`. Renaming the host project breaks the entire downstream chain.

After the command completes, the solution folder contains a new `Dynamicweb.Host.Suite/` folder with the canonical Suite scaffold (`.csproj`, `Program.cs`, `Properties/launchSettings.json`, etc.).

### 2.1 — Mandatory host-config before the first run

Every Dynamicweb demo needs the same host-config patches applied at scaffold time, before the first `dotnet run`. These are vendor-generic platform requirements owned by [`foundational/setup-install.md`](foundational/setup-install.md); apply all of them now:

- **Pin `<TargetFramework>net10.0</TargetFramework>`** (single-target). Non-negotiable — the Backend MCP AddIn loader hard-requires net10, and a net8 host makes the AddIn install silently no-op. Rationale + triage order: `setup-install.md` §2.
- **Patch `Program.cs`** with `System.Transactions.TransactionManager.ImplicitDistributedTransactions = true;` before `WebApplication.CreateBuilder`, and **exclude `wwwroot\Files\System\**`** from the build. Both: `setup-install.md` §3.
- **Install the Backend MCP AddIn** via a NuGet `PackageReference` (the deterministic default; AppStore is the last resort). The AddIn is a non-skippable canonical step for every demo and registers at host startup. Recipe + auth model: [`foundational/extend-mcp-tools.md`](foundational/extend-mcp-tools.md) §1, then continue MCP configuration in `references/mcp-setup.md`.

The distributed-transaction host prereqs (MSDTC, the net10 promotion caveat) only bite specific admin operations like AreaCopy — `setup-install.md` §4 owns them; `references/setup-checks.md` carries the demo-time probe.

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
3. **Force the license step.** On DW 10.27.x the Setup Guide redirects to `/admin/license` immediately after the database step, BEFORE any admin-user setup. Complete it — a **Suite Trial** is fine for demos. The trial expiry lands ~30 days out; record it in the demo's `CUSTOMISATIONS.md` so the next run on this box knows when the demo goes dark. Platform-level detail + the headless trial-activation path: [`foundational/setup-install.md`](foundational/setup-install.md) §7.
4. Print a one-time admin user prompt (capture the credentials — they're needed for the admin UI walkthrough in `references/mcp-setup.md` Step 3). **Gotcha:** the license gate can skip this step entirely, leaving every seeded user inactive with an empty password — no usable admin login, and the standard flow dead-ends. If `/admin` rejects every credential after setup, apply the headless admin-password recovery in [`foundational/setup-install.md`](foundational/setup-install.md) §7 before going further.

Once the Setup Guide completes, the `Properties/launchSettings.json` file has its final `applicationUrl` and the `GlobalSettings.Database.config` has the actual DB name. **These two files are the source of truth for port and DB name from now on** (the discover-from-project-files rule).

---

## 4. Discover-from-project-files rule

After the first run completes, the per-demo project files are the source of truth — sister skills must read from these, not from hardcoded fallbacks:

| What | Read from | Used by |
|---|---|---|
| HTTPS port | `Dynamicweb.Host.Suite/Properties/launchSettings.json` (`applicationUrl`, HTTPS profile) | `references/mcp-setup.md` Step 1, all subsequent Management API calls |
| Database name | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` (`Database=` or `Initial Catalog=` in connection string) | Swift's [`../../dw-demo-swift/references/integrity-sweep.md`](../../dw-demo-swift/references/integrity-sweep.md) SQL probes; PIM admin/SQL recipes |
| Management API bearer token | Captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`). Storage contract is canonical in `references/mcp-setup.md` Step 6. | Swift's [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) + [`../../dw-demo-swift/references/integrity-sweep.md`](../../dw-demo-swift/references/integrity-sweep.md); any Management API call |

`references/mcp-setup.md` Section 1 contains the verbatim port-discovery PowerShell that reads `launchSettings.json`.

The platform anti-patterns to avoid when scaffolding (don't target DW9, don't reference the bare `Dynamicweb` meta-package, don't use the CMS-only `dw10-cms` template) are owned by [`foundational/setup-install.md`](foundational/setup-install.md) §6.

# Scaffold — `dotnet new dw10-suite`

## Contents

- [1. Prerequisites](#1-prerequisites)
- [2. Scaffold the per-demo project](#2-scaffold-the-per-demo-project)
- [3. First run — wizardless bootstrap (HTTP-driven, ~40 s)](#3-first-run--wizardless-bootstrap-http-driven-40-s)
- [4. Discover-from-project-files rule](#4-discover-from-project-files-rule)

Scaffold a new Dynamicweb 10 demo project. Walk `dotnet new dw10-suite --name Dynamicweb.Host.Suite`. The `--name Dynamicweb.Host.Suite` is **mandatory** — sister-skill path discovery (`Dynamicweb.Host.Suite/Properties/launchSettings.json`, `Dynamicweb.Host.Suite/GlobalSettings.Database.config`) depends on this name.

Suite version is whatever the template + `dotnet restore` resolve. **Version policy is out of scope for this skill** — neither pinning a specific patch nor enforcing Ring-N stability is something this skill does. If a particular demo needs a frozen version, edit its csproj directly. (The release-ring model and the version-scheme split, for the rare regression triage, are platform knowledge — [`foundational/setup-install.md`](foundational/setup-install.md) §5.) **One carve-out:** a scaffold whose job is to **validate Distribution content** (deserialize its layers/editions) is NOT free to float — it MUST pin `Dynamicweb.Suite` to the platform version the Distribution gate-proved on. That is a correctness constraint, not version policy — see [§2.2](#22--platform-pin--scaffolds-that-validate-distribution-content).

---

## 1. Prerequisites

Before running `dotnet new dw10-suite`, the box needs the **.NET 10 SDK**, **`Dynamicweb.ProjectTemplates`**, and a running **SQL Express service** (`MSSQL$SQLEXPRESS`). The platform-level rationale, probes, and install/fix paths for each are owned by [`foundational/setup-install.md`](foundational/setup-install.md) §1. Run the quick verification ritual in `references/setup-checks.md` first — it probes these plus the demo-specific checks (TLS env var, `git` + `gh` CLI, writable `<demo-root>\distribution\` clone target, versions prompt) in one pass.

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

- **Seed the demo's `.gitignore` with the artifact-hygiene entries.** Ephemeral build evidence lands under `notes\` (the canonical scratch layout — see `SKILL.md` "Artifact hygiene"), so the scaffolded `.gitignore` must ignore those dirs alongside the standard ones. Ensure it contains:
  ```gitignore
  bin/
  obj/
  wwwroot/Files/System/
  notes/credentials.local.md
  notes/qa/
  notes/logs/
  notes/snapshots/
  ```
  Keeper screenshots worth committing are copied out of `notes\qa\` explicitly; everything the QA / host-log / snapshot passes emit stays untracked.

### 2.2 — Platform pin — scaffolds that validate Distribution content

A scaffold whose purpose is to **deserialize and validate the Distribution's layers/editions** MUST pin the host's `Dynamicweb.Suite` package to the platform version the Distribution gate-proved on — its `layers/INDEX.json` `gateProven.dwPlatformVersion` (the same value the versions prompt captured as the DW10 answer; currently **`10.28.1-PreRelease`**). Set it explicitly in the host `.csproj`:

```xml
<PackageReference Include="Dynamicweb.Suite" Version="10.28.1-PreRelease" />
```

**Floating `10.*` is a sideways-failure trap, not a convenience.** `Dynamicweb.Suite 10.*` resolves to the latest **STABLE** (`10.27.6` at the last full run) — NOT the gate-proven prerelease. Version-coupled layers then fail *silently sideways*: `feature-b2b-comms`' flow SQL uses `10.28.1` (unprefixed) column names that `10.27.6` doesn't have — strict mode rejects the table and the flow simply **can't exist**, with no loud error. The static file-tree gate stays green; only a runtime deserialize on the *right* platform proves the content. Pinning to `gateProven.dwPlatformVersion` is the fix. (This is why "version policy out of scope" has its one carve-out — a content-validating scaffold on the wrong platform validates nothing.)

**The single exception:** a **platform-currency probe** — a scaffold built to test the Distribution against a *newer* platform than it gate-proved on — deliberately floats `10.*` (or pins the candidate). Floating is legitimate there and **nowhere else**: any scaffold whose output is a claim about Distribution content pins.

---

## 3. First run — wizardless bootstrap (HTTP-driven, ~40 s)

The setup wizard is plain ASP.NET MVC forms and is **fully HTTP-drivable** — drive it with `Invoke-WebRequest`/`Invoke-RestMethod` instead of walking it in a browser. Measured on DW 10.28.1: host cold start ~25 s, the schema step ~6 s (~260 tables), trial license + token auth < 5 s — **~40 s total** after the one-time scaffold + build, versus ~20 minutes of manual setup-guide clicking. There is **no browser-only step anywhere in host bootstrap** — license activation included.

1. **Create an empty database** first (`CREATE DATABASE [<demo-db>]` against `MSSQL$SQLEXPRESS`). Run it via `Invoke-Sqlcmd -TrustServerCertificate` (the self-signed local cert otherwise blocks the connect) — **not** `sqlcmd -E -i`, which current builds reject with a mutually-exclusive-flag error (`-E` integrated auth and `-i` input file collide). If you instead let the setup wizard create the DB (`CreateDatabase=true` on Step3), know the race: **"Create database" can report `Login failed` while the DB was in fact created** — re-POST Step3 (or re-click Next in the browser fallback) rather than treating the error as fatal; a `SELECT db_id('<demo-db>')` confirms it exists. Pre-creating with `Invoke-Sqlcmd` sidesteps the race entirely. Do **NOT** pre-provision `GlobalSettings.Database.config` against an empty DB — a pre-provisioned connection makes the wizard skip its own Step3 (the step that owns schema creation), and Step4 then faults with `Invalid object name 'AccessUser'`. DW10 does not migrate an empty DB on startup; with GlobalSettings pre-provisioned and an empty DB the wizard can never finish. **What decides "wizard or no wizard" is the DATABASE state, not the config**: a DB that already carries schema + an active Administrator row boots straight past the wizard.
2. **Start the host** (`dotnet run` — the "Host lifecycle authority" `Start-Process` recipe in `SKILL.md`), then drive the wizard over HTTPS:
   - `GET /Admin/Installation/Start` — captures the session cookie + antiforgery token.
   - `POST /Admin/Installation/Step2` with `{MapFilesToExistingFolder=True, FilesPath=<wwwroot\Files>, ResetSettings=false}` — the files repository.
   - `POST /Admin/Installation/Step3` with `{DatabaseType=sql, Server, Database, CreateDatabase=false, Encrypt=false, IntegratedSecurity=true}` — **this is the schema step**: ~6 s, ~260 tables migrated, and DW itself writes `GlobalSettings.Database.config`.
   - **Admin user:** the schema seed creates an inactive `Administrator` (id 2, empty password). `POST /Admin/Installation/Step4` with `{Name, Email, Username, Password, PasswordConfirm}` — and on a **local demo host, the username/password is always `Admin` / `Admin1`**. One memorable credential across every local demo host is a presenter requirement (zero-lookup during a live demo); per-host generated secrets and the `Administrator` spelling both cost demo-time fumbling. Record it in `notes/credentials.local.md` anyway (the file is the single credential home). Hosted / customer-facing installs use real secrets — this convention is local-demo-only. If the host already has a differently-named admin, rename it to `Admin` and set the password via the plaintext escape hatch ([`foundational/users-permissions.md`](foundational/users-permissions.md) §13) — there is no MCP/API password surface.
3. **License — also plain HTTP.** Probe `/Admin/` for the `/admin/license` redirect, then `GET` + `POST /Admin/License/TrialInstallStep` (antiforgery token + the preselected trialId radio). A **Suite Trial** is fine for demos; expiry lands ~30 days out — record it in the demo's `CUSTOMISATIONS.md`. Platform-level detail: [`foundational/setup-install.md`](foundational/setup-install.md) §7.
4. **Verify:** a Management API token auth returns 200, and `/Admin/` redirects to the login screen (`/Admin/UI`), not to `/Admin/Installation/Start`.
5. **Delete the leftover `Standard` area (AreaId 1).** Every wizard bootstrap seeds a `Standard` website that no demo uses; it must not survive into a demo host (it pollutes the area list and can grab root-URL resolution). Delete its pages, grid rows, paragraphs and the `Area` row via SQL — the MCP `delete_area` tool reports success without deleting ([`foundational/extend-mcp-tools.md`](foundational/extend-mcp-tools.md) §5). Verify `SELECT COUNT(*) FROM Area WHERE AreaId=1` returns 0.

**Restore flavor — skipping the wizard entirely.** When a clean-template `.bak`/bacpac with schema + an active Administrator is available, restore it and pre-provision only: `wwwroot\Files\` (any skeleton — DW fills `System/`, `Images/`, `Files/`) plus `wwwroot\Files\GlobalSettings.Database.config` (`<Globalsettings><System><Database>`: `Type=ms_sqlserver`, `SQLServer`, `Database`, `IntegratedSecurity=True`). The restored DB is the actual wizard-skipper; `GlobalSettings.config` is optional (DW writes one on first run).

(The interactive Setup Guide in a browser still works as a fallback — same steps, ~20 minutes of clicking — but the HTTP recipe is the default. **Gotcha** either way: the license gate can leave every seeded user inactive with an empty password — no usable admin login. If `/admin` rejects every credential after setup, apply the headless admin-password recovery in [`foundational/setup-install.md`](foundational/setup-install.md) §7.)

Once bootstrap completes, the `Properties/launchSettings.json` file has its final `applicationUrl` and the `GlobalSettings.Database.config` has the actual DB name. **These two files are the source of truth for port and DB name from now on** (the discover-from-project-files rule).

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

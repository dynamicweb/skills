# Setup Checks — fresh-machine readiness

## Contents

- [1. Quick verification ritual](#1-quick-verification-ritual)
- [2. Per-check sections](#2-per-check-sections)
- [3. Discovery table — read these from project files (the discover-from-project-files rule)](#3-discovery-table--read-these-from-project-files-the-discover-from-project-files-rule)
- [4. Dual-set env-var propagation pattern — User-scope env-var doesn't propagate](#4-dual-set-env-var-propagation-pattern--user-scope-env-var-doesnt-propagate)

Verification logic lives as fenced PowerShell inside this Markdown reference. Use it to verify, before touching any per-demo work: the `NODE_TLS_REJECT_UNAUTHORIZED` env var, `git` plus the `gh` CLI (present + authenticated, for cloning the distribution repos), a writable `<demo-root>\baselines\` folder, and the demo's DW10 + Swift versions prompt — owned here — plus the platform install prerequisites (.NET 10 SDK, `Dynamicweb.ProjectTemplates`, SQL Express, MSDTC), whose per-check detail is owned by [`foundational/setup-install.md`](foundational/setup-install.md).

**Posture:** verify + opt-in fix.

- **Cheap fixes** (env vars at User scope) → the skill prompts for approval, runs the fix, advises a Claude Code restart.
- **Install-grade fixes** (.NET 10 SDK, SQL Express, `Dynamicweb.ProjectTemplates`, MSDTC) → print + link only. Never auto-install. The user runs the installer. See `setup-install.md`.

---

## 1. Quick verification ritual

Run all probes at once. If every line is green, you can skip the per-check sections below and head to `references/scaffold.md`.

```powershell
dotnet --list-sdks | Select-String '^10\.'        # .NET 10 SDK present (host targets net10)
dotnet new list | Select-String 'dw10-suite'       # expect "DynamicWeb 10 Suite Project Template" or similar
Get-Service "MSSQL`$SQLEXPRESS" | Select-Object Name, Status
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
git --version                                      # git present (clones the distribution repos)
gh auth status                                     # gh CLI installed AND authenticated (private-repo clone over HTTPS)
```

Note the backtick on `MSSQL`$SQLEXPRESS` — `$SQLEXPRESS` is a PowerShell special token unless escaped.

The first three lines are the platform install prerequisites — if any is red, work the per-check sections in [`foundational/setup-install.md`](foundational/setup-install.md) §1 (and §4 for MSDTC). The last three are demo-specific, owned below (the TLS env var, `git`, and the `gh` CLI). The DW10 + Swift versions prompt and the writable-`baselines\` check are also owned here.

---

## 2. Per-check sections

Each check follows the same shape: **Why** → **Probe** → **Expected** → **Cheap fix (opt-in)** OR **Install-grade fix (print+link)**.

> **Platform install prerequisites** — the per-check detail for the **.NET 10 SDK**, **`Dynamicweb.ProjectTemplates`**, the **SQL Express service**, and **MSDTC for cross-connection TransactionScope** (with the `enable-msdtc.ps1` admin script) is owned by [`foundational/setup-install.md`](foundational/setup-install.md) §1 and §4. They are platform-generic, not demo-specific — verify them via the ritual above and fix per that reference. The MSDTC requirement pairs with the `Program.cs` `ImplicitDistributedTransactions` opt-in (`setup-install.md` §3.1); both are needed for admin operations like AreaCopy.

The demo-specific checks owned here are the TLS env var, `git` + the `gh` CLI, the writable `baselines\` folder, and the versions prompt.

### Check: NODE_TLS_REJECT_UNAUTHORIZED env var (User scope)

**Why this matters:** This is the load-bearing layer of the two-layer TLS bypass — without it the MCP HTTPS handshake fails silently (`claude mcp list` shows "Failed to connect"). Full rationale and both layers: `references/tls-bypass.md`; this check is only the env-var verification.

**Probe:**

```powershell
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
```

**Expected:** literal `"0"` (string).

**Cheap fix (opt-in):** Set both the User-scope persistent var AND the current-process `$env:VAR` (the dual-set pattern, Section 4). Ask the user:

> "NODE_TLS_REJECT_UNAUTHORIZED is not set to `0` at User scope. The MCP HTTPS handshake will fail without it (see `references/tls-bypass.md`). I can set it by running:
>
> ```powershell
> [System.Environment]::SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED", "0", "User")
> $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
> ```
>
> After this, you'll need to **close ALL Claude Code instances and reopen from a fresh PowerShell**. Approve? [Set + restart guidance / Skip]"

**Cross-reference:** `references/tls-bypass.md` is the long-form rationale.

### Check: `git` + `gh` CLI present and authenticated

**Why this matters:** Demo artifacts (baseline, theme, feature-pack) are **cloned** per-demo with `git clone` (sparse-checkout of the version/pack subtree) from the ecosystem distribution repos — there are **no releases** to download (see the base SKILL "Versions prompt + per-demo artifact clone"). `git` does the clone; `gh`, authenticated, supplies the credential helper that lets a **private** ecosystem repo clone over HTTPS. If either is missing or unauthenticated, the Swift deserialize and pack-activation flows cannot fetch their sources.

**Probe:**

```powershell
git --version         # git installed (clones the distribution repos)
gh --version          # gh CLI installed
gh auth status        # authenticated to github.com (non-zero exit / "not logged in" = fix below)
```

**Expected:** `git` and `gh` both print a version, and `gh auth status` reports a logged-in account with repo read scope.

**Install-grade fix (print + link):** If `git` is absent, print `winget install --id Git.Git` (or link https://git-scm.com/). If `gh` is absent, print `winget install --id GitHub.cli` (or link https://cli.github.com/) and let the user install. If `gh` is installed but not authenticated, have the user run `gh auth login` in their own shell (`gh auth setup-git` wires it as the git credential helper) — never script a credential flow.

### Check: `<demo-root>\baselines\` folder is writable

**Why this matters:** Every cloned artifact lands under the demo's own `baselines\` folder. A read-only or non-existent parent path makes the first `git clone` fail.

**Probe:**

```powershell
$baselines = Join-Path (Get-Location).Path "baselines"
New-Item -ItemType Directory -Path $baselines -Force | Out-Null
$probe = Join-Path $baselines ".write-probe"
Set-Content -Path $probe -Value "ok"; Remove-Item $probe   # throws if not writable
```

**Expected:** the folder is created (or already present) and the write probe succeeds.

**Cheap fix (opt-in):** If creation fails, the demo root is likely under a protected path — ask the user to relocate the demo or grant write access. Do not elevate automatically.

### Check: Versions prompt (DW10 + Swift)

**Why this matters:** The version answers select which baseline **package dir** (`packages/swift/<version>`) the demo clones from `main`, drive the Swift design-package clone tag (`v<version>.0`), and pack compatibility checks. Ask **before** cloning anything. Note: the distribution repos ship **no release tags** — the Swift version picks a directory in `main`, and the reproducibility pin is the **commit SHA** cloned, recorded in `CUSTOMISATIONS.md`.

**Probe:** conversational — ask the user via `AskUserQuestion`:

> "Which **DW10 platform version** does this demo target, and which **Swift version** (e.g. `2.3`)? Both get recorded in `CUSTOMISATIONS.md` for reproducibility and select which baseline package dir (`packages/swift/<version>`) to clone from `main`."

**Expected:** two values captured in conversation state and written to the demo's `CUSTOMISATIONS.md`. No default — never guess a version.

---

## 3. Discovery table — read these from project files (the discover-from-project-files rule)

Once setup is verified, the per-demo project files are the source of truth for port, DB name, and bearer token. Never hardcode these.

| What | Where to read it |
|---|---|
| **HTTPS port + host URL** | `.mcp.json` at solution root (e.g. `https://localhost:<PORT>/admin/mcp`) — or `Dynamicweb.Host.Suite/Properties/launchSettings.json` under `applicationUrl` |
| **Database name** | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` — look for the `<database>` element or `Initial Catalog=` in the connection string. Falls back to the solution folder name if no explicit setting. |
| **Management API bearer token** | Project-specific — captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`). Storage contract is canonical in `references/mcp-setup.md` Step 6. |

---

## 4. Dual-set env-var propagation pattern — User-scope env-var doesn't propagate

When you set any User-scope env var via `[Environment]::SetEnvironmentVariable(name, value, "User")` or `setx`, **it is NOT visible to the currently-running Claude Code process** (or to any already-spawned shell). The fix has three parts:

1. **Set User-scope** (persistent for future sessions): `[Environment]::SetEnvironmentVariable(name, value, "User")`.
2. **Set current-process `$env:`** (visible to the rest of the current PowerShell session, but NOT to Claude Code): `$env:NAME = value`.
3. **Restart Claude Code from a fresh shell**: close ALL Claude Code instances, open a new PowerShell, run `claude` from there.

Use `[Environment]::GetEnvironmentVariable(name, "User")` (not `$env:NAME`) for verification re-reads — `$env:NAME` reads the current-process copy, which is stale after a `setx`/`SetEnvironmentVariable` call.

This pattern applies to **all** User-scope env-var fixes in this file (NODE_TLS_REJECT_UNAUTHORIZED, anything else) and is the canonical statement of the dual-set pattern — other files (e.g. `tls-bypass.md` §3) pointer here. The two-line setter (`SetEnvironmentVariable` + `$env:NAME = ...`) covers parts 1 and 2; the user must do part 3.

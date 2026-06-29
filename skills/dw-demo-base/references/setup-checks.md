# Setup Checks — fresh-machine readiness

## Contents

- [1. Quick verification ritual](#1-quick-verification-ritual)
- [2. Per-check sections](#2-per-check-sections)
- [3. Discovery table — read these from project files (the discover-from-project-files rule)](#3-discovery-table--read-these-from-project-files-the-discover-from-project-files-rule)
- [4. Dual-set env-var propagation pattern — User-scope env-var doesn't propagate](#4-dual-set-env-var-propagation-pattern--user-scope-env-var-doesnt-propagate)

Verification logic lives as fenced PowerShell inside this Markdown reference. Use it to verify, before touching any per-demo work: the two demo-specific env vars (`DW_VAULT`, `NODE_TLS_REJECT_UNAUTHORIZED`) and the five vault slots — owned here — plus the platform install prerequisites (.NET 10 SDK, `Dynamicweb.ProjectTemplates`, SQL Express, MSDTC), whose per-check detail is owned by [`foundational/setup-install.md`](foundational/setup-install.md).

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
[Environment]::GetEnvironmentVariable("DW_VAULT","User")
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
```

Note the backtick on `MSSQL`$SQLEXPRESS` — `$SQLEXPRESS` is a PowerShell special token unless escaped.

The first three lines are the platform install prerequisites — if any is red, work the per-check sections in [`foundational/setup-install.md`](foundational/setup-install.md) §1 (and §4 for MSDTC). The last two are the demo-specific env vars, owned below.

---

## 2. Per-check sections

Each check follows the same shape: **Why** → **Probe** → **Expected** → **Cheap fix (opt-in)** OR **Install-grade fix (print+link)**.

> **Platform install prerequisites** — the per-check detail for the **.NET 10 SDK**, **`Dynamicweb.ProjectTemplates`**, the **SQL Express service**, and **MSDTC for cross-connection TransactionScope** (with the `enable-msdtc.ps1` admin script) is owned by [`foundational/setup-install.md`](foundational/setup-install.md) §1 and §4. They are platform-generic, not demo-specific — verify them via the ritual above and fix per that reference. The MSDTC requirement pairs with the `Program.cs` `ImplicitDistributedTransactions` opt-in (`setup-install.md` §3.1); both are needed for admin operations like AreaCopy.

The demo-specific checks owned here are the two env vars and the vault inventory.

### Check: DW_VAULT env var (User scope)

**Why this matters:** Every reference in this skill (and every sister skill) resolves vault content via `$env:DW_VAULT`. If the var is unset, `compare-vault.md`, the slot-inventory probe below, and Swift's [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) all fail.

**Probe:**

```powershell
[Environment]::GetEnvironmentVariable("DW_VAULT","User")
```

**Expected:** non-empty path that exists on disk.

**Cheap fix (opt-in):** If empty or path doesn't exist, ask the user via `AskUserQuestion`:

> "DW_VAULT is not set at User scope. I can set it to `C:\VibeCode\dw-vault` (or another path you specify) by running:
>
> ```powershell
> [Environment]::SetEnvironmentVariable("DW_VAULT", "C:\VibeCode\dw-vault", "User")
> $env:DW_VAULT = "C:\VibeCode\dw-vault"
> ```
>
> After this, you'll need to **close ALL Claude Code instances and reopen from a fresh PowerShell** for the new value to be visible to MCP/Node tooling. Approve? [Set + restart guidance / Specify different path / Skip]"

**Ask before fixing — never auto-apply.** This is a User-scope mutation; user opt-in is the contract.

**Dual-set pattern:** Always set both the User-scope persistent var AND the current-process `$env:VAR`. The two-line setter above does both. See Section 4.

### Check: NODE_TLS_REJECT_UNAUTHORIZED env var (User scope)

**Why this matters:** This is the load-bearing layer of the two-layer TLS bypass — without it the MCP HTTPS handshake fails silently (`claude mcp list` shows "Failed to connect"). Full rationale and both layers: `references/tls-bypass.md`; this check is only the env-var verification.

**Probe:**

```powershell
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
```

**Expected:** literal `"0"` (string).

**Cheap fix (opt-in):** Same pattern as DW_VAULT. Ask the user:

> "NODE_TLS_REJECT_UNAUTHORIZED is not set to `0` at User scope. The MCP HTTPS handshake will fail without it (see `references/tls-bypass.md`). I can set it by running:
>
> ```powershell
> [System.Environment]::SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED", "0", "User")
> $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
> ```
>
> After this, you'll need to **close ALL Claude Code instances and reopen from a fresh PowerShell**. Approve? [Set + restart guidance / Skip]"

**Cross-reference:** `references/tls-bypass.md` is the long-form rationale.

### Check: Vault slot inventory

**Why this matters:** The skill resolves all reference content via `$env:DW_VAULT` + the slot table in `$env:DW_VAULT\INDEX.md`. The five slots are `dw10source`, `samples`, `databases`, `docs`, `serialized-data`. The vault layout also hard-relocated `dw10adminUI-samples\` → `samples\dw10adminUI\`; if the legacy top-level location is still present, INDEX.md tells two stories and the vault is in a drift state (apply the baseline-drift self-diagnosis rule).

**Probe:**

```powershell
$vault = [Environment]::GetEnvironmentVariable("DW_VAULT","User")
if (-not $vault) { throw "DW_VAULT not set at User scope. See the DW_VAULT check above." }

# 1. INDEX.md presence
if (-not (Test-Path (Join-Path $vault "INDEX.md"))) {
  throw "INDEX.md missing at $vault\INDEX.md. Vault is not initialised."
}

# 2. All five slots present
$slots = "dw10source","samples","databases","docs","serialized-data"
$missing = $slots | Where-Object { -not (Test-Path (Join-Path $vault $_)) }
if ($missing) {
  Write-Host "Missing slots: $($missing -join ', ')"
  Write-Host "Recreate the vault layout (see INDEX.md) or copy from a sibling machine."
}

# 3. Stale-state detection: legacy top-level dw10adminUI-samples\
$legacy = Join-Path $vault "dw10adminUI-samples"
if (Test-Path $legacy) {
  Write-Host "STALE: legacy top-level $legacy still exists alongside $vault\samples\dw10adminUI\."
  Write-Host "The vault layout hard-relocated this. Run:"
  Write-Host "  Move-Item -Path '$legacy' -Destination '$vault\samples\dw10adminUI' -Force"
  Write-Host "or remove the legacy folder if a copy already exists at the new path."
}
```

**Expected:** INDEX.md present, all five slots present, no legacy `dw10adminUI-samples\` at top level.

**Cheap fix (opt-in, only if individual slots missing):** Offer to `New-Item -ItemType Directory -Force` the missing slot folders. Do NOT seed content automatically — slot population is a vault-bootstrap concern; this check just detects absence.

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

This pattern applies to **all** User-scope env-var fixes in this file (DW_VAULT, NODE_TLS_REJECT_UNAUTHORIZED, anything else) and is the canonical statement of the dual-set pattern — other files (e.g. `tls-bypass.md` §3) pointer here. The two-line setter (`SetEnvironmentVariable` + `$env:NAME = ...`) covers parts 1 and 2; the user must do part 3.

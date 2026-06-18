# Setup Checks â€” fresh-machine readiness

Verification logic lives as fenced PowerShell inside this Markdown reference, not as standalone `.ps1` scripts. Use it to verify env vars, the .NET 10 SDK, `Dynamicweb.ProjectTemplates`, the SQL Express service, and the five vault slots before touching any per-demo work.

**Posture:** verify + opt-in fix.

- **Cheap fixes** (env vars at User scope) â†’ the skill prompts for approval, runs the fix, advises a Claude Code restart.
- **Install-grade fixes** (.NET 10 SDK, SQL Express, `Dynamicweb.ProjectTemplates`) â†’ print + link only. Never auto-install. The user runs the installer.

---

## 1. Quick verification ritual

Run all probes at once. If every line is green, you can skip the per-check sections below and head to `references/scaffold.md`.

```powershell
dotnet --version                                   # any modern SDK is fine; the live check is `--list-sdks | Select-String '^10\.'` below (host targets net10 â€” required for AppStore Backend MCP)
dotnet new list | Select-String 'dw10-suite'       # expect "DynamicWeb 10 Suite Project Template" or similar
Get-Service "MSSQL`$SQLEXPRESS" | Select-Object Name, Status
[Environment]::GetEnvironmentVariable("DW_VAULT","User")
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
```

Note the backtick on `MSSQL`$SQLEXPRESS` â€” `$SQLEXPRESS` is a PowerShell special token unless escaped.

If any line is red, jump to its per-check section below.

---

## 2. Per-check sections

Each check follows the same shape: **Why** â†’ **Probe** â†’ **Expected** â†’ **Cheap fix (opt-in)** OR **Install-grade fix (print+link)**.

### Check: DW_VAULT env var (User scope)

**Why this matters:** Every reference in this skill (and every sister skill) resolves vault content via `$env:DW_VAULT`. If the var is unset, `compare-vault.md`, the slot-inventory probe in Check 6, and Swift's [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) all fail.

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

**Don't fix automatically.** This is a User-scope mutation; user opt-in is the contract.

**Dual-set pattern:** Always set both the User-scope persistent var AND the current-process `$env:VAR`. The two-line setter above does both. See Section 4.

### Check: NODE_TLS_REJECT_UNAUTHORIZED env var (User scope)

**Why this matters:** This is the load-bearing layer of the two-layer TLS bypass â€” without it the MCP HTTPS handshake fails silently (`claude mcp list` shows "Failed to connect"). Full rationale and both layers: `references/tls-bypass.md`; this check is only the env-var verification.

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

### Check: .NET 10 SDK

**Why this matters:** the host runs on .NET 10 (csproj is pinned to `<TargetFramework>net10.0</TargetFramework>` per `references/scaffold.md` Section 2.1). The AppStore Backend MCP AddIn loader hard-requires .NET 10 even though its package ships net6/net8 lib binaries â€” installing on a net8 host appears to succeed (POST returns 200, files drop to disk) but the AddIn never registers. Net8 SDKs may also be installed for legacy compatibility and that's fine â€” they coexist â€” but .NET 10 must be present.

**Probe:**

```powershell
dotnet --version            # any installed SDK; useful but not the authoritative check
dotnet --list-sdks | Select-String '^10\.'
```

**Expected:** `--list-sdks` filtered by `^10\.` returns at least one line (e.g. `10.0.100 [C:\Program Files\dotnet\sdk]`).

**Install-grade fix (print + link only):** Do NOT auto-install. Print:

> ".NET 10 SDK is not installed. Download the latest 10.0.x from <https://dotnet.microsoft.com/download/dotnet/10.0> and run the installer. After install, re-run this probe."

### Check: Dynamicweb.ProjectTemplates 1.26.0

**Why this matters:** `dotnet new dw10-suite` (the canonical scaffold command) requires the `Dynamicweb.ProjectTemplates` package. Pin to 1.26.0 â€” templates are forward-only and 1.26.0 is the latest version we have verified against.

**Probe:**

```powershell
dotnet new list | Select-String 'dw10-suite'
```

**Expected:** a row matching `dw10-suite` (the template short name).

**Cheap fix (borderline; opt-in):** This sits between cheap and install-grade â€” it mutates user-global dotnet template config but doesn't require admin. Ask the user via `AskUserQuestion`:

> "`Dynamicweb.ProjectTemplates 1.26.0` is not installed. I can run:
>
> ```powershell
> dotnet new install Dynamicweb.ProjectTemplates::1.26.0
> ```
>
> This mutates user-global dotnet template config. Approve? [Install / Skip â€” I'll install manually]"

If the user prefers manual: link <https://www.nuget.org/packages/Dynamicweb.ProjectTemplates/1.26.0>.

### Check: SQL Express service

**Why this matters:** SQL Server can crash silently, after which the host hangs on startup. The `dw10-suite` project's first run auto-creates the demo DB if `dbcreator` is granted; without a running SQL Express service, nothing works downstream.

**Probe:**

```powershell
Get-Service "MSSQL`$SQLEXPRESS" | Select-Object Name, Status
```

**Expected:** `Status = Running`.

**Cheap fix (opt-in, may prompt for elevation):** If `Status = Stopped`, ask:

> "SQL Express service `MSSQL$SQLEXPRESS` is stopped. I can start it by running:
>
> ```powershell
> Start-Service "MSSQL`$SQLEXPRESS"
> ```
>
> Windows may prompt for admin elevation. Approve? [Start / Skip]"

**Install-grade fallback:** If `Get-Service` returns no service at all (not just stopped â€” missing), SQL Express isn't installed. Do not auto-install. Print:

> "SQL Express is not installed. Download SQL Server Express 2022 from <https://www.microsoft.com/en-us/sql-server/sql-server-downloads> and run the installer with the named instance `SQLEXPRESS`. After install, re-run this probe."

### Check: Vault slot inventory

**Why this matters:** The skill resolves all reference content via `$env:DW_VAULT` + the slot table in `$env:DW_VAULT\INDEX.md`. The five slots are `dw10source`, `samples`, `databases`, `docs`, `serialized-data`. The vault layout also hard-relocated `dw10adminUI-samples\` â†’ `samples\dw10adminUI\`; if the legacy top-level location is still present, INDEX.md tells two stories and the vault is in a drift state (apply the baseline-drift self-diagnosis rule).

**Probe:**

```powershell
$vault = [Environment]::GetEnvironmentVariable("DW_VAULT","User")
if (-not $vault) { throw "DW_VAULT not set at User scope. See Check 1 above." }

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

**Cheap fix (opt-in, only if individual slots missing):** Offer to `New-Item -ItemType Directory -Force` the missing slot folders. Do NOT seed content automatically â€” slot population is a vault-bootstrap concern; this check just detects absence.

---

### Check: MSDTC for cross-connection TransactionScope (mandatory)

**Why this matters:** Several DW10 admin operations open multiple `SqlConnection` instances inside a single `TransactionScope`. The classic example is `/admin/api/AreaCopy` (the "+ New website Language" admin flow, which clones the full 95-page Swift tree). The second connection's `EnlistPromotableSinglePhase` call needs:

1. **MSDTC service running** AND **inbound/outbound transactions enabled** at the service level
2. **DTC Windows Firewall rules enabled** (DTC RPC, RPC-EPMAP, TCP-In, TCP-Out)
3. **`TransactionManager.ImplicitDistributedTransactions = true`** set in the host process (see `scaffold.md` Â§2.1b â€” applied at project scaffold time)

On a fresh dev box only (1) is partially true (MSDTC runs in Manual mode with all flags off). Without all three, AreaCopy fails with:

> `System.Transactions.TransactionException: The operation is not valid for the state of the transaction.`

with a stack going through `EnlistPromotableSinglePhase` â†’ `SqlInternalConnection.EnlistNonNull`. Every per-page warning logs the same exception; the final ColorSwatch.Save throws fatally and the catch block returns `"Area was not copied!"`.

**Probe (no admin needed):**

```powershell
$dtc = Get-DtcNetworkSetting -DtcName Local -ErrorAction SilentlyContinue
$fw  = (Get-NetFirewallRule | ? { $_.DisplayName -match 'Distributed Transaction|DTC' } | ? Enabled -eq $true).Count
"InboundTx=$($dtc.InboundTransactionsEnabled) OutboundTx=$($dtc.OutboundTransactionsEnabled) FwRulesEnabled=$fw"
```

**Expected:** `InboundTx=True OutboundTx=True FwRulesEnabled=8` (or however many DTC rules your Windows ships â€” the key is `> 0` and most enabled).

**Install-grade fix (requires admin):** the `enable-msdtc.ps1` script pattern below is reusable per demo. Drop it at `<demo>\audit\enable-msdtc.ps1` and ask the user to run it elevated:

```powershell
#requires -RunAsAdministrator
Set-DtcNetworkSetting -DtcName Local -InboundTransactionsEnabled $true -OutboundTransactionsEnabled $true -AuthenticationLevel NoAuth -Confirm:$false
Get-NetFirewallRule | ? { $_.DisplayName -match 'Distributed Transaction|DTC' } | Enable-NetFirewallRule
Restart-Service msdtc -Force
```

`AuthenticationLevel=NoAuth` is fine for a local-only dev box. One-time per machine â€” persists across reboots.

**Verify after fix:** re-run the probe. Then test directly with a 2-connection TransactionScope (this should return "OK" once everything is wired):

```powershell
$cs = "Server=localhost\SQLEXPRESS;Database=master;Integrated Security=True;TrustServerCertificate=True"
try { $s = New-Object System.Transactions.TransactionScope; $c1 = New-Object System.Data.SqlClient.SqlConnection $cs; $c1.Open(); $c2 = New-Object System.Data.SqlClient.SqlConnection $cs; $c2.Open(); $c1.Close(); $c2.Close(); $s.Complete(); $s.Dispose(); "OK" } catch { "FAIL: $($_.Exception.Message)" }
```

If this returns "Implicit distributed transactions have not been enabled", the runtime is .NET 7+ and `scaffold.md Â§2.1b` Program.cs patch is still needed inside the host process. The PowerShell test itself runs in a fresh process that needs the same opt-in â€” for the test only, set `[System.Transactions.TransactionManager]::ImplicitDistributedTransactions = $true` before the test.

---

## 3. Discovery table â€” read these from project files (the discover-from-project-files rule)

Once setup is verified, the per-demo project files are the source of truth for port, DB name, and bearer token. Never hardcode these.

| What | Where to read it |
|---|---|
| **HTTPS port + host URL** | `.mcp.json` at solution root (e.g. `https://localhost:<PORT>/admin/mcp`) â€” or `Dynamicweb.Host.Suite/Properties/launchSettings.json` under `applicationUrl` |
| **Database name** | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` â€” look for the `<database>` element or `Initial Catalog=` in the connection string. Falls back to the solution folder name if no explicit setting. |
| **Management API bearer token** | Project-specific â€” captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`). Storage contract is canonical in `references/mcp-setup.md` Step 6. |

---

## 4. Dual-set env-var propagation pattern â€” User-scope env-var doesn't propagate

When you set any User-scope env var via `[Environment]::SetEnvironmentVariable(name, value, "User")` or `setx`, **it is NOT visible to the currently-running Claude Code process** (or to any already-spawned shell). The fix has three parts:

1. **Set User-scope** (persistent for future sessions): `[Environment]::SetEnvironmentVariable(name, value, "User")`.
2. **Set current-process `$env:`** (visible to the rest of the current PowerShell session, but NOT to Claude Code): `$env:NAME = value`.
3. **Restart Claude Code from a fresh shell**: close ALL Claude Code instances, open a new PowerShell, run `claude` from there.

Use `[Environment]::GetEnvironmentVariable(name, "User")` (not `$env:NAME`) for verification re-reads â€” `$env:NAME` reads the current-process copy, which is stale after a `setx`/`SetEnvironmentVariable` call.

This pattern applies to **all** User-scope env-var fixes in this file (DW_VAULT, NODE_TLS_REJECT_UNAUTHORIZED, anything else) and is the canonical statement of the dual-set pattern â€” other files (e.g. `tls-bypass.md` Â§3) pointer here. The two-line setter (`SetEnvironmentVariable` + `$env:NAME = ...`) covers parts 1 and 2; the user must do part 3.



# Setup Checks — fresh-machine readiness

## Contents

- [1. Quick verification ritual](#1-quick-verification-ritual)
- [2. Per-check sections](#2-per-check-sections)
- [2a. Post-clone check: `/Files` must resolve to the DW file archive](#2a-post-clone-check-files-must-resolve-to-the-dw-file-archive)
- [2b. Post-restore check: orphaned shop/group relation rows](#2b-post-restore-check-orphaned-shopgroup-relation-rows)
- [3. Discovery table — read these from project files (the discover-from-project-files rule)](#3-discovery-table--read-these-from-project-files-the-discover-from-project-files-rule)
- [4. Dual-set env-var propagation pattern — User-scope env-var doesn't propagate](#4-dual-set-env-var-propagation-pattern--user-scope-env-var-doesnt-propagate)

Verification logic lives as fenced PowerShell inside this Markdown reference. Use it to verify, before touching any per-demo work: the `NODE_TLS_REJECT_UNAUTHORIZED` env var, `git` plus the `gh` CLI (present + authenticated, for cloning the Distribution repo), a writable `<demo-root>\distribution\` clone target, and the demo's DW10 + Swift versions prompt — owned here — plus the platform install prerequisites (.NET 10 SDK, `Dynamicweb.ProjectTemplates`, SQL Express, MSDTC), whose per-check detail is owned by [`../../dw-setup-install/references/install-anatomy.md`](../../dw-setup-install/references/install-anatomy.md).

**Posture:** verify + opt-in fix.

- **Cheap fixes** (env vars at User scope) → the skill prompts for approval, runs the fix, advises a Claude Code restart.
- **Install-grade fixes** (.NET 10 SDK, SQL Express, `Dynamicweb.ProjectTemplates`, MSDTC) → print + link only. Never auto-install. The user runs the installer. See `setup-install.md`.

---

## 1. Quick verification ritual

Run all probes at once. If every line is green, you can skip the per-check sections below and head to `references/scaffold.md`.

```powershell
$PSVersionTable.PSVersion                          # pwsh 7+ REQUIRED — run every recipe/verb from pwsh, not Windows PowerShell 5.1
dotnet --list-sdks | Select-String '^10\.'        # .NET 10 SDK present (host targets net10)
dotnet new list | Select-String 'dw10-suite'       # expect "DynamicWeb 10 Suite Project Template" or similar
Get-Service "MSSQL`$SQLEXPRESS" | Select-Object Name, Status
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
git --version                                      # git present (clones the distribution repos)
gh auth status                                     # gh CLI installed AND authenticated (private-repo clone over HTTPS)
```

Note the backtick on `MSSQL`$SQLEXPRESS` — `$SQLEXPRESS` is a PowerShell special token unless escaped.

Once a host is scaffolded and running, the *host-side* readiness checks (admin/license gate, MCP
route gates, handshake, tool count) have their own harness — run
[`../../dw-setup-install/scripts/Test-DwHostReady.ps1`](../../dw-setup-install/scripts/Test-DwHostReady.ps1)
with the host's base URL rather than probing the routes by hand.

**Run everything from pwsh 7+, never Windows PowerShell 5.1.** The skill's PowerShell recipes and any harness verbs (the standalone lightweight harness, DemoAgent `bin/` verbs) use the null-coalescing operator `??` and other pwsh-7 syntax — **5.1 parse-fails the whole script before the first line runs** (`Telemetry.Common.ps1` is the canonical offender). `$PSVersionTable.PSVersion.Major` must be `≥ 7`; if a verb dies with a parser error on `??`, you are in 5.1 — relaunch in `pwsh`.

**Install-grade fix (print + link):** if `pwsh` is not on `PATH`, print `winget install --id Microsoft.PowerShell --source winget` (or link https://aka.ms/powershell) and let the user install, then relaunch. PowerShell scripts shipped under `skills/*/scripts/` carry `#Requires -Version 7.0` (right after the help block — a leading `#Requires` breaks `Get-Help` binding), so under 5.1 they stop with a one-line message instead of a parse error; this check is the only place the version is handled. A skill that ships a script in another runtime (Python, Node) declares it in its `compatibility:` frontmatter; handle it the same way, print + link.

**A 5.1 parse casualty still EXITS 0, so assert success from the EFFECT, never from the exit code.** Repo scripts are UTF-8 without BOM, and Windows PowerShell 5.1 decodes a BOM-less file as ANSI/CP1252: a UTF-8 em-dash (`E2 80 94`) becomes three CP1252 characters ending in `0x94`, which is a RIGHT DOUBLE QUOTATION MARK that PowerShell accepts as a real string delimiter. That terminated a double-quoted `throw` message early inside `Do-Recycle` and cascaded into "Unexpected token", "Missing statement body in do loop" and "Missing closing }". The function was never defined, the caller failed on "Do-Recycle is not recognized", the script exited 0, and the background-task notification reported success while nothing had been uploaded and no recycle had happened. Prevention is `pwsh` 7 plus saving scripts as UTF-8 WITH BOM so 5.1 cannot mis-decode them. Proof is an effect assertion at the end of the script: after `Do-Recycle`, `FilesByDirectory /Files/System/CloudHosting` must list `changeversion.txt` pre-consume, and a new `w3wp`/stdout log must appear post-consume.

The first three lines are the platform install prerequisites — if any is red, work the per-check sections in [`../../dw-setup-install/references/install-anatomy.md`](../../dw-setup-install/references/install-anatomy.md) §1 (and §4 for MSDTC). The last three are demo-specific, owned below (the TLS env var, `git`, and the `gh` CLI). The DW10 + Swift versions prompt and the writable-`distribution\` check are also owned here.

---

## 2. Per-check sections

Each check follows the same shape: **Why** → **Probe** → **Expected** → **Cheap fix (opt-in)** OR **Install-grade fix (print+link)**.

> **Platform install prerequisites** — the per-check detail for the **.NET 10 SDK**, **`Dynamicweb.ProjectTemplates`**, the **SQL Express service**, and **MSDTC for cross-connection TransactionScope** (with the `enable-msdtc.ps1` admin script) is owned by [`../../dw-setup-install/references/install-anatomy.md`](../../dw-setup-install/references/install-anatomy.md) §1 and §4. They are platform-generic, not demo-specific — verify them via the ritual above and fix per that reference. The MSDTC requirement pairs with the `Program.cs` `ImplicitDistributedTransactions` opt-in (`setup-install.md` §3.1); both are needed for admin operations like AreaCopy.

The demo-specific checks owned here are the TLS env var, `git` + the `gh` CLI, the writable `distribution\` clone target, and the versions prompt.

### Check: NODE_TLS_REJECT_UNAUTHORIZED env var (User scope)

**Why this matters:** This is the load-bearing layer of the two-layer TLS bypass — without it the MCP HTTPS handshake fails silently (`claude mcp list` shows "Failed to connect"). Full rationale and both layers: `references/mcp-setup.md` Step 2; this check is only the env-var verification.

**Probe:**

```powershell
[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")
```

**Expected:** literal `"0"` (string).

**Cheap fix (opt-in):** Set both the User-scope persistent var AND the current-process `$env:VAR` (the dual-set pattern, Section 4). Ask the user:

> "NODE_TLS_REJECT_UNAUTHORIZED is not set to `0` at User scope. The MCP HTTPS handshake will fail without it (see `references/mcp-setup.md` Step 2). I can set it by running:
>
> ```powershell
> [System.Environment]::SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED", "0", "User")
> $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
> ```
>
> After this, you'll need to **close ALL Claude Code instances and reopen from a fresh PowerShell**. Approve? [Set + restart guidance / Skip]"

**Cross-reference:** `references/mcp-setup.md` Step 2 is the long-form rationale.

### Check: `git` + `gh` CLI present and authenticated

**Why this matters:** Demo artifacts (base, catalog, theme, feature layers) are consumed per-demo with `git clone` + `git pull --ff-only origin main` from the single Distribution repo (URL from `$env:DW_DISTRIBUTION_REPO`) — **main IS the version**; there are **no releases** to download and no tag checkout (see the base SKILL "Versions prompt + Distribution clone/checkout"). `git` does the clone; `gh`, authenticated, supplies the credential helper that lets a **private** Distribution repo clone over HTTPS. If either is missing or unauthenticated, the Swift deserialize and pack-activation flows cannot fetch their sources.

**Probe:**

```powershell
git --version         # git installed (clones the distribution repos)
gh --version          # gh CLI installed
gh auth status        # authenticated to github.com (non-zero exit / "not logged in" = fix below)
```

**Expected:** `git` and `gh` both print a version, and `gh auth status` reports a logged-in account with repo read scope.

**Install-grade fix (print + link):** If `git` is absent, print `winget install --id Git.Git` (or link https://git-scm.com/). If `gh` is absent, print `winget install --id GitHub.cli` (or link https://cli.github.com/) and let the user install. If `gh` is installed but not authenticated, have the user run `gh auth login` in their own shell (`gh auth setup-git` wires it as the git credential helper) — never script a credential flow.

### Check: `<demo-root>\distribution\` clone target is writable

**Why this matters:** The demo's Distribution checkout lands under the demo's own `distribution\` folder. A read-only or non-existent parent path makes the first `git clone` fail.

**Probe:**

```powershell
$dist = Join-Path (Get-Location).Path "distribution"
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$probe = Join-Path $dist ".write-probe"
Set-Content -Path $probe -Value "ok"; Remove-Item $probe   # throws if not writable
```

**Expected:** the folder is created (or already present) and the write probe succeeds.

**Cheap fix (opt-in):** If creation fails, the demo root is likely under a protected path — ask the user to relocate the demo or grant write access. Do not elevate automatically.

### Check: Versions prompt (DW10 + Swift)

**Why this matters:** The version answers drive the Swift design-package clone tag (`v<version>.0`) and layer-compatibility checks (each layer's `layer.json` declares the `swiftVersion` it targets). Ask **before** cloning anything. Note: the demo consumes the latest gate-proven `main` of the Distribution (resolved from `layers/INDEX.json`, not a tag), and the reproducibility pin is the **resolved commit SHA**, recorded in `CUSTOMISATIONS.md`.

**Probe:** conversational — ask the user via `AskUserQuestion`:

> "Which **DW10 platform version** does this demo target, and which **Swift version** (e.g. `2.4`)? Both get recorded in `CUSTOMISATIONS.md` for reproducibility and drive layer-compatibility checks against the Distribution's latest gate-proven `main`."

**Expected:** two values captured in conversation state and written to the demo's `CUSTOMISATIONS.md`. No default — never guess a version.

---

## 2a. Post-clone check: `/Files` must resolve to the DW file archive

**Run this on any host cloned with `CopyDemoSite`, before any deserialize.** On the IIS-hosted demo
sites the web-visible `/Files` root is `<site>\Files`, a **sibling of `Application\`**, and
`CopyDemoSite` leaves it EMPTY, while DW resolves its own file archive to
`<site>\Application\wwwroot\Files`. Two different folders. A working site keeps the archive in the
sibling; a fresh clone does not, and every asset under `/Files` then 404s (`swift.css`, `swift.js`,
`Styles/*.css`, every icon) while `/Admin` and the page pipeline work perfectly. The storefront
renders completely unstyled, which reads as a broken deserialize and sends the run down the wrong
diagnosis.

Assert a known file resolves over HTTP before deserializing anything:

```powershell
# Expect 200 and a real body (~350 KB for swift.css on a Swift 2.4 site)
$r = Invoke-WebRequest -SkipCertificateCheck `
  "https://<host>/Files/Templates/Designs/Swift-v2/Assets/css/swift.css"
if ($r.StatusCode -ne 200) { throw "/Files does not resolve to the DW file archive on this clone." }
```

To discriminate the two folders directly, write a probe file into `<site>\Files\__probe.txt` and into
`<site>\Application\wwwroot\Files\__probe.txt` and GET both: on a broken clone the sibling answers 200
and the archive answers 404. The remedy that shipped was junctioning `Templates`, `Images`, `Icons`
and `System\Styles` from the sibling into the real archive, after which the five asset URLs returned
200 and the home page rendered styled.

## 2b. Post-restore check: orphaned shop/group relation rows

**Run this after any restore or `CopyDemoSite`, before the first group-tree audit.** A restored
database routinely carries relation rows pointing at group ids that no longer exist in any language —
one measured host held 186 orphans out of 219 `EcomShopGroupRelation` rows, residue from the source
demo's own group tree. They are **inert** (every consumer joins to `EcomGroups`, so nothing errors and
no admin warning appears) and they make any shop/group audit unreadable: most of the channels in the
listing turn out to have no real groups at all.

`SQL` is the surface here, and it is the only one: no MCP tool and no Management API verb reports a
dangling relation row, because the relation is only ever read through a join that hides it. Local
installs only; a read owes nothing, the delete below owes a host restart to flush the group caches.

```sql
-- Audit: expect 0
SELECT COUNT(*) FROM EcomShopGroupRelation sgr
WHERE NOT EXISTS (SELECT 1 FROM EcomGroups g WHERE g.GroupId = sgr.ShopGroupGroupId);

-- Cleanup, once the count is understood
DELETE FROM EcomShopGroupRelation
WHERE NOT EXISTS (SELECT 1 FROM EcomGroups g WHERE g.GroupId = EcomShopGroupRelation.ShopGroupGroupId);
```

Run the same shape against the sibling relation tables. Confirm before deleting that the ids really
are dangling rather than live configuration: a DB-wide scan for one known-deleted group id found it
only in the relation tables and the command-log audit rows, which is what made the delete safe. Keep
the audit query as a standing post-restore step, so orphan volume is caught before it is mistaken for
a real tree — and read `EcomGroups.GroupType` before deleting any *group*
([`dw-pim-modelling`](../../dw-pim-modelling/references/structural-model.md#22-group-types--data-models-vs-catalog-groups)),
since the data-model tree looks exactly like a duplicate catalogue tree from the outside.

## 3. Discovery table — read these from project files (the discover-from-project-files rule)

Once setup is verified, the per-demo project files are the source of truth for port, DB name, and bearer token. Never hardcode these.

| What | Where to read it |
|---|---|
| **HTTPS port + host URL** | `.mcp.json` at solution root (e.g. `https://localhost:<PORT>/admin/mcp`) — or `Dynamicweb.Host.Suite/Properties/launchSettings.json` under `applicationUrl` |
| **Database name** | `Dynamicweb.Host.Suite/GlobalSettings.Database.config` — look for the `<database>` element or `Initial Catalog=` in the connection string. Falls back to the solution folder name if no explicit setting. |
| **Management API bearer token** | Project-specific — captured via `AskUserQuestion` from chat (format `CLAUDE.<hex>`). Storage contract is canonical in `references/mcp-setup.md` Step 6. |

---

## 4. Dual-set env-var propagation pattern — User-scope env-var doesn't propagate

A User-scope env var set via `[Environment]::SetEnvironmentVariable(name, value, "User")` or `setx` is **NOT visible to the currently-running Claude Code process** — set User scope AND the current-process `$env:` copy, then restart Claude Code from a fresh shell, and verify re-reads with `[Environment]::GetEnvironmentVariable(name, "User")`, never `$env:NAME`. The canonical statement of the dual-set pattern is `references/mcp-setup.md` Step 2; this file keeps the probes above.

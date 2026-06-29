# MCP Setup — `.mcp.json` + admin-UI walkthrough + verification gate

Wire MCP for the Dynamicweb MCP server (`dynamicweb-commerce-mcp`) bundled with `Dynamicweb.Suite` 10.x. The canonical flow is **API-Key auth with a static bearer in `.mcp.json`** — five steps in **strict order**:

1. Write `.mcp.json` with the discovered HTTPS port (bearer placeholder filled in Step 3b).
2. Verify the two-layer TLS bypass is in place (see `references/tls-bypass.md`).
3. Create the MCP configuration **MANUALLY** in DW admin UI with **Authentication method = API Key** — DW10 does **not** auto-create one. Step 3 is the most-missed step.
3b. Paste the plaintext API key into `.mcp.json` as the `Authorization: Bearer …` header and save it to per-demo Claude memory.
4. Verification gate.

The verification gate (Step 4) refuses to declare 'setup complete' until BOTH `claude mcp list` shows `dynamicweb-commerce-mcp ✓ Connected` AND tool discovery returns > 200 dynamicweb tools.

## Why API Key by default (not Claude.ai OAuth)

The Backend MCP plugin (`Dynamicweb.MCP`) exposes four auth handlers in `McpAuthMiddleware`: `ApiKey`, `BearerToken` (OAuth-issued), `Jwt`, `OAuthClient`. The admin UI surfaces two as first-class choices: **API Key** and **Claude.ai** (the latter is the OAuth + Dynamic Client Registration flow used by claude.ai's hosted client).

For local Claude Code development, **API Key is strictly better**:

- **Restart-resilient.** Token validation hits `AccessUserToken` (DB) on every request. When the host bounces, the next MCP call from Claude Code revalidates the bearer against the DB row — no interactive `/mcp` re-authorization, no checkpoint, no "MCP server requires re-authorization (token expired)" mid-flow.
- **No client to register.** OAuth/Claude.ai uses Dynamic Client Registration: each Claude Code instance registers itself as an OAuth client and gets bound to a session. Host restarts and Claude Code restarts both interrupt that binding. API Key has no client state at all.
- **Same model as the Management API.** Both ride `AccessUserToken`. You already paste `CLAUDE.<hex>` bearer tokens into Management API requests; the MCP API key is the same shape, same storage, same lifecycle.

Use Claude.ai OAuth only when you must connect the hosted claude.ai web client (which can't read a local `.mcp.json`). For Claude Code + a local Dynamicweb host, default to API Key.

---

## Step 1 — Discover port from `launchSettings.json`

Run from the solution root after the first `dotnet run` (see `references/scaffold.md` Section 5):

```powershell
$ls = Get-Content "Dynamicweb.Host.Suite/Properties/launchSettings.json" -Raw | ConvertFrom-Json
$httpsUrl = $ls.profiles.PSObject.Properties |
            ForEach-Object { $_.Value.applicationUrl } |
            Where-Object { $_ -match '^https://' } |
            Select-Object -First 1
# $httpsUrl looks like "https://localhost:44312;http://localhost:5000"
$port = ($httpsUrl -split ';')[0] -replace 'https://localhost:', ''
$mcpUrl = "https://localhost:$port/admin/mcp"
Write-Host "Discovered MCP URL: $mcpUrl"
```

The regex `^https://` + `Select-Object -First 1` pins down the HTTPS profile deterministically; the `-split ';'` then `-replace` strips the protocol/host prefix to leave just the port number.

---

## Step 1b — Generate `.mcp.json` at solution root (bearer placeholder)

Continuing from the snippet above (`$mcpUrl` is in scope). Write `.mcp.json` with the URL now and the bearer as a `<MCP_API_KEY>` placeholder — the actual key is generated in Step 3 and pasted in Step 3b:

```powershell
$mcpJson = @{
  mcpServers = @{
    "dynamicweb-commerce-mcp" = @{
      type    = "http"
      url     = $mcpUrl  # from Step 1
      headers = @{
        Authorization = "Bearer <MCP_API_KEY>"
      }
    }
  }
} | ConvertTo-Json -Depth 5
$mcpJson | Set-Content -Encoding UTF8 ".mcp.json"
```

The skill's `assets/mcp.json.template` is the parametric source (with literal `<PORT>` and `<MCP_API_KEY>` placeholders); the snippet above is the runtime-discovered version that substitutes the actual port. Either route produces the same JSON shape:

```json
{
  "mcpServers": {
    "dynamicweb-commerce-mcp": {
      "type": "http",
      "url": "https://localhost:44312/admin/mcp",
      "headers": {
        "Authorization": "Bearer <MCP_API_KEY>"
      }
    }
  }
}
```

> **Do not commit the real key.** `.mcp.json` is project-tracked. Leave `<MCP_API_KEY>` as a literal placeholder in source control. The substituted-in version with the real bearer lives on each developer's machine only; the canonical store is per-demo Claude memory (see Step 6).

---

## Step 2 — Verify the two-layer TLS bypass

**Both layers from `references/tls-bypass.md` must be in place before continuing.** If `claude mcp list` (run later in Step 4) shows `Failed to connect`, return to `references/tls-bypass.md` and re-verify the User-scope env var (the load-bearing layer) — that's almost always the cause.

---

## Step 3 — Create the MCP configuration in DW10 admin UI (API Key)

**Create the MCP configuration in DW admin UI** — REQUIRED, and it must be done by hand. DW10 does NOT auto-create a usable MCP config when an HTTP client first connects. `/admin/mcp` will respond `401 Unauthorized` (or `200` with an empty `tools/list` for the legacy Claude.ai OAuth path) until a configuration exists. Create it manually:

- Admin UI → **Settings → Integration → MCP configurations** (exact menu path may vary by DW10 version — look for "MCP" under Integration).
- **New configuration**, set **Access = Full access**, set **Authentication method = API Key**.
- Save. The admin UI generates a plaintext API key and **shows it once** — copy it immediately (you cannot retrieve the plaintext later; the DB only stores the hash). Format is the same shape as the Management API token: `CLAUDE.<hex>` (or similar; whatever the admin UI displays is what you paste).

If you don't capture the key on first display, delete the configuration and recreate it — there is no "show again" path.

After saving, do **not** rerun `/mcp` in Claude Code yet — there's no bearer in `.mcp.json` until Step 3b. The MCP session will pick up the key on the next request after Step 3b completes.

> **Why not Claude.ai?** That auth method is for the hosted claude.ai web client and uses OAuth + Dynamic Client Registration — its session dies when the host or Claude Code restarts, forcing an interactive `/mcp` re-auth that cannot be scripted around. See the "Why API Key by default" preamble at the top of this file.

## Step 3b — Paste the bearer into `.mcp.json` and per-demo memory

1. Open `.mcp.json` (created in Step 1b) and replace the literal `<MCP_API_KEY>` with the plaintext key from Step 3:

   ```jsonc
   "headers": {
     "Authorization": "Bearer CLAUDE.abc123…"   // ← paste the plaintext key here
   }
   ```

   **Locally only.** Don't commit this change — the source-controlled `.mcp.json` keeps the `<MCP_API_KEY>` placeholder. See Step 6 for the per-demo storage contract.

2. Save the key to per-demo Claude memory as a `reference` memory (host URL + plaintext key + a one-line how-to-use). See Step 6 for the token-storage contract. The memory is the authoritative copy; if `.mcp.json` is wiped or regenerated, you re-paste from memory, not from chat.

3. Run `/mcp` in Claude Code (or open a fresh Claude Code shell) so the client picks up the new bearer. The connection should immediately authenticate against the DW host and `tools/list` returns the full catalog (~260 tools).

---

## Step 3 (headless alternative) — create the token + MCP config without the admin UI

Steps 3 and 3b assume the admin UI is reachable. When it isn't (a fully headless build / automated provisioning), create both the API token and the MCP configuration **in code** — e.g. a one-shot `Program.cs` maintenance branch run *inside the built host* (after `app.UseDynamicweb()`, so DI is live — see [`../../dw-extend-csharp-api/SKILL.md`](../../dw-extend-csharp-api/SKILL.md)). Three pieces, and the third is the non-obvious one:

1. **Issue the token.** `TokenService.TryCreateToken(new ApiTokenRequestModel { Name = …, Prefix = "CLAUDE", ExpiryDate = … }, user)` returns the **unhashed** token; the DB stores only the hash in `AccessUserToken`. The public-facing bearer is `CLAUDE.<secret>` — capture it now, it can't be recovered later (same as the admin-UI "shown once" behaviour in Step 3).

2. **Create the MCP configuration.** Insert an `McpConfiguration` row (`Name`, `TokenId`, `AllowEverything = 1` for full access — the headless equivalent of `Access = Full access`).

3. **Bind the token to the config through the service — not raw SQL.** A raw `McpConfigurationCredential` insert does **NOT** satisfy the auth path; the request still returns `401`. You must call `McpConfigurationService.LinkToken(configId, tokenId, user)`. That class is **internal**, so invoke it by reflection, resolving the instance from the live DI container (`app.Services`):

   ```csharp
   var asm = Assembly.Load("Dynamicweb.MCP");
   var t   = asm.GetType("Dynamicweb.MCP.Configuration.Services.McpConfigurationService");
   var svc = app.Services.GetService(t) ?? Activator.CreateInstance(t, true);
   t.GetMethod("LinkToken").Invoke(svc, new object[] { configId, tokenId, user });
   ```

**Then restart the host.** The MCP configuration is cached at startup, so a freshly inserted/bound config is invisible to `/admin/mcp` until the next boot. (The same startup-cache rule applies to the admin password and the token — direct SQL writes don't take until restart; for MCP credentials a raw insert is *insufficient* even after restart, hence the `LinkToken` call.)

> **Brittleness warning.** `McpConfigurationService` is an internal type invoked by reflection — its namespace, method name, and signature can change between DW10 releases without notice, and the `Dynamicweb.MCP` version pin matters. Prefer the admin-UI route (Step 3) whenever the UI is reachable; use this code path only for genuinely headless installs, and re-verify the type/method names against the `Dynamicweb.MCP` version in use.

---

## Step 4 — The MCP verification gate

The skill **refuses to declare setup complete** until BOTH conditions pass:

### 4a. Connection check

```powershell
$mcpList = claude mcp list 2>&1
if ($mcpList -notmatch 'dynamicweb-commerce-mcp.*✓.*Connected') {
  Write-Host "FAILED: claude mcp list does not show dynamicweb-commerce-mcp Connected."
  Write-Host "Work the 'Triage table — when verification fails' at the bottom of mcp-setup.md."
  throw "MCP not connected. Fix and retry."
}
Write-Host "OK: dynamicweb-commerce-mcp ✓ Connected"
```

### 4b. Tool count check (in-conversation)

The skill's verification gate ALSO requires `ToolSearch +dynamicweb` to return **> 200 tools**. Claude Code does not currently expose a CLI verb for tool count, so this check runs in conversation: ask Claude to run `ToolSearch +dynamicweb` and confirm count > 200 before declaring setup complete.

Triage rules for tool-count outcomes:

- **`count == 0`** → admin-UI MCP config (Step 3) was not created, or `.mcp.json` still has the literal `<MCP_API_KEY>` placeholder (Step 3b not done). Check both.
- **`count < 50`** (small) → admin-UI config has restrictive scope (not Full access). Re-create with `Access = Full access`.
- **`50 <= count < 200`** → unusual; likely a DW10 version where the MCP catalogue is partial. Compare against another known-good machine using `compare-vault.md`'s output as a sanity check on `serialized-data/` baseline drift; consult the team.
- **`count > 200`** → gate passes; proceed to step 4 (drop guardrails) and then to the demo-type-specific path (PIM modelling via `dynamicweb-pim-demo`, or Swift baseline deserialize via [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md)).

The conjunction (Connected AND > 200 tools) catches all three failure shapes: TLS bypass missing (Step 4a fails with "Failed to connect"), admin-UI MCP config missing (Step 4a fails with `401 Unauthorized` once the bearer is in place), and the bearer placeholder not substituted (Step 4a fails with `401 Unauthorized` even with a config in place).

---

## Step 5 — Install Browser MCP (machine-level, do once per Windows account)

The Browser MCP (`@playwright/mcp`) gives Claude first-class browser tooling — log in, navigate, click, screenshot, inspect DOM — so verification flows after PIM seeding / template edits / customer-center wiring don't require the user to manually drive a tab. Unlike the Backend MCP (Steps 1–4 above, **per-demo**), the Browser MCP is **per-machine**: install once at user scope, every Dynamicweb demo on this account inherits it.

The full recipe + flag rationale + verification gate lives in [`references/browser-automation.md`](browser-automation.md). One-line install:

```powershell
claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest --ignore-https-errors --output-dir "$env:USERPROFILE\.playwright-mcp-output"
```

`--output-dir` keeps `browser_take_screenshot` from dumping shots into the demo solution root — see browser-automation.md "Where screenshots land".

Verification gate: `claude mcp list` shows `playwright ✓ Connected`. Tool surface (`mcp__playwright__browser_*`) appears only in a **fresh** Claude Code session — see browser-automation.md Step 3 for why.

This step is idempotent — safe to skip if `claude mcp list` already shows `playwright ✓ Connected` from a prior demo build.

---

## Step 6 — Discover bearer tokens (the discover-from-project-files rule)

A Dynamicweb demo has **two** bearer tokens, both `CLAUDE.<hex>`-shaped rows in `AccessUserToken`:

| Token | Issued from | Used for |
|---|---|---|
| **MCP API key** | Admin UI → Settings → Integration → MCP configurations → New (Authentication method = API Key). Captured in Step 3 of this file. | `Authorization: Bearer …` header in `.mcp.json` (Step 3b). Validated against `AccessUserTokenHash` by `McpAuthMiddleware`. |
| **Management API token** | Admin UI → Settings → System → Developer → API keys → New. Captured here in Step 6 via `AskUserQuestion`. | `Authorization: Bearer …` header on `/admin/api/...` calls. Used by Swift's [`../../dw-demo-swift/references/deserialize-flow.md`](../../dw-demo-swift/references/deserialize-flow.md) and [`../../dw-demo-swift/references/integrity-sweep.md`](../../dw-demo-swift/references/integrity-sweep.md), and by PIM admin-API calls. |

These are distinct rows. The MCP API key is bound to the MCP configuration via `McpConfigurationTokenId` — established by the admin UI on save, or in code by `McpConfigurationService.LinkToken` (a raw `McpConfigurationCredential` insert does not satisfy the auth path; see "Step 3 (headless alternative)"). The Management API token is the unconstrained admin-API key. Don't try to reuse one for the other unless you've verified empirically — the validation paths differ.

If you don't have a Management API token in conversation state or memory, capture it via:

> "I need the Management API bearer token for this Dynamicweb host. The format is `CLAUDE.<hex>`. You can find it in the admin UI under **Settings → System → Developer → API keys** (create one if none exists). Please paste the token in chat."

**Token-storage contract — where both tokens may live (same rules for each; this table is the canonical statement — other files pointer here):**

| Location | Allowed? | Why |
|---|---|---|
| Conversation state | ✅ Always | Default scope; cleared at session end. |
| Per-demo Claude memory (`~/.claude/projects/<encoded-cwd-of-demo>/memory/`) | ✅ Canonical for local dev hosts | Survives across sessions; user-machine-only; naturally scoped to one demo (the encoded cwd is the demo solution folder); never shared via git or commits. Save **two** `reference` memories — one for the MCP API key, one for the Management API token — each with the host URL, the token, and a how-to-use note. |
| Env vars (User or Machine scope, e.g. `DYNAMICWEB_MGMT_API_TOKEN`) | ❌ Never | The tokens are per-demo, but env vars are machine-global — a second demo on the same machine would clobber the first. Use per-demo Claude memory instead, which is the only storage location that gives one slot per demo. |
| Project-tracked files (`.mcp.json` with substituted bearer, `Files/Serializer.config.json`, csproj, `settings.local.json`, anything inside the demo solution folder that git tracks) | ❌ Never commit | A local-only `.mcp.json` with the real bearer is fine to live on disk — but the source-controlled copy keeps the `<MCP_API_KEY>` placeholder. Don't `git add` after substitution. |
| Production hosts | ❌ Never persist outside conversation state | Different threat model — out of scope for this skill. |

If a token isn't in conversation state and no memory entry exists, capture again via the appropriate prompt above and save to per-demo Claude memory.

---

## Triage table — when verification fails

| Symptom | Fix |
|---|---|
| `claude mcp list` shows "Failed to connect" | Almost always the TLS bypass: the User-scope `NODE_TLS_REJECT_UNAUTHORIZED=0` env var is missing (project-level config is silently insufficient) — fix per `references/tls-bypass.md`, then fully restart Claude Code from a fresh shell. Also check: is the `Dynamicweb.Host.Suite` host actually running on the port `.mcp.json` references? |
| `claude mcp list` shows the server but requests fail `401 Unauthorized` despite a substituted bearer | The bearer in `.mcp.json` is not the EXACT plaintext key the admin UI displayed — check for extra whitespace or a trailing newline introduced when pasting. |
| `claude mcp list` shows the server but `ToolSearch +dynamicweb` returns 0 / 401 Unauthorized on `/admin/mcp` requests | **Three distinct causes — check in order.** (1) `.mcp.json` still has the literal `<MCP_API_KEY>` placeholder — substitute the plaintext key from the admin UI (Step 3b). (2) No MCP configuration exists on the DW side — admin UI → Settings → Integration → MCP configurations → New, set **Access = Full access**, **Authentication method = API Key**, save, copy the displayed plaintext key (shown once), and paste into `.mcp.json`. (3) Stale bearer (config was deleted/regenerated since the key was last captured) — the configuration row in the admin UI is now linked to a different `AccessUserTokenId`; capture the new key and update `.mcp.json` + per-demo memory. |
| AppStore install of "Backend MCP" appears to do nothing — no UI confirmation, the MCP configurations menu the app is supposed to add never appears, `/admin/mcp` returns 404 | **Two distinct causes, in order of likelihood.** (1) **Host TFM is net8.** The MCP AddIn loader requires .NET 10 even though the package ships net6/net8 lib binaries. Symptom: install POST returns 200, files drop to `wwwroot/Files/System/AddIns/Installed/Dynamicweb.MCP.<ver>/lib/`, but AddIn never registers. Fix: pin csproj `<TargetFramework>net10.0</TargetFramework>` and restart the host (verify in startup log: `Dynamicweb is running on .NET 10 or greater`). See `references/scaffold.md` Section 2.1. (2) **Stuck DB update queue** (or buggy CREATE in update queue). Check `wwwroot/Files/System/Log/EventViewer/*.log` for `Update failed:.*Cannot find the object`. Recovery: `references/db-update-recovery.md` (Mode A or B depending on triage). |
| Mid-run MCP call fails with `401 Unauthorized` after a host restart | Should be rare with API-Key auth (the bearer is DB-backed, stateless, and the host revalidates against `AccessUserToken` on every request). If it happens: the admin UI's MCP config was likely deleted/recreated, which generates a new `AccessUserTokenId` and invalidates the old plaintext key. Open the admin UI, confirm the MCP configuration still exists, and capture a fresh key if the link is broken. **Do NOT silently pivot to direct-SQL fallbacks** for create/update operations — that bypasses MCP cache invalidation AND leaves required columns unset (e.g. `EcomDetails.DetailLanguageId` defaulting to empty string, see `dynamicweb-pim-demo/references/structural-model.md` §2.10). The MCP-plugin tools (e.g. `import_product_images_from_urls`, `add_product_image`) have NO Management API endpoint backing — there is no plain-HTTP fallback that preserves their column-population guarantees. |
| Mid-run MCP call fails with `MCP server "..." requires re-authorization (token expired)` | You're on the legacy Claude.ai OAuth auth method, not API Key — that's exactly the failure mode the API-Key default exists to avoid. Switch the admin UI's MCP configuration to `Authentication method = API Key`, capture the plaintext key, and update `.mcp.json` per Step 3b. After that, host restarts and Claude Code restarts no longer trigger re-auth. |



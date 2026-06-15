# TLS Bypass — two-layer for self-signed localhost dev cert

Two-layer TLS bypass for the self-signed localhost dev cert. **REQUIRED** for the MCP HTTPS handshake to `https://localhost:<PORT>/admin/mcp`. The User-scope env var is the load-bearing layer; project-only configuration is silently insufficient — the symptom is `/mcp` reporting "Authentication successful" while `claude mcp list` then says "Failed to connect" and no tools load.

---

## 1. Two-layer pattern — and why both layers

- **Layer 1 — project**: `.claude/settings.local.json` at solution root with `{"env":{"NODE_TLS_REJECT_UNAUTHORIZED":"0"}}`. This layer **documents intent** — it signals to anyone reading the project that this demo expects the bypass, and it is what Claude Code's own settings reader sees for tools/scripts inside the project. It does **not** propagate reliably into the Node TLS handshake performed by the MCP transport: empirically, `/mcp` reports "Authentication successful" (the OAuth handshake uses a different code path) while the actual MCP HTTP requests fail with `unable to verify the first certificate`.
- **Layer 2 — User-scope env var (the load-bearing one)**: `[System.Environment]::SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","0","User")` (or `setx NODE_TLS_REJECT_UNAUTHORIZED 0`), then **close and reopen Claude Code from a fresh shell**. Node's TLS stack reads `process.env.NODE_TLS_REJECT_UNAUTHORIZED` at handshake time; a User-scope var persists and is inherited by every new process under that user — including the MCP transport Claude Code spawns.

**Why not `NODE_EXTRA_CA_CERTS`?** The ASP.NET dev cert is a self-signed leaf, not a CA. `NODE_EXTRA_CA_CERTS` only adds **trusted CAs** — Node will not accept a self-signed leaf cert through it, even when the fingerprint matches, and there is no public Node API to whitelist a specific leaf cert. The bypass is the only documented working method.

**Safe?** Yes, for localhost-only dev boxes. The bypass disables cert validation for the entire Node process, but on a dev box the only HTTPS traffic from Node is to your own `localhost:<PORT>/admin/mcp` plus outbound `npm` calls. **Never set this on a server.**

---

## 2. Layer 1 generator — project `.claude/settings.local.json`

Run from the solution root (the demo project folder, e.g. `C:\Projects\Solutions\<demo>\`):

```powershell
New-Item -ItemType Directory -Path ".claude" -Force | Out-Null
$settings = @{ env = @{ NODE_TLS_REJECT_UNAUTHORIZED = "0" } } | ConvertTo-Json -Depth 5
$settings | Set-Content -Encoding UTF8 ".claude/settings.local.json"
```

This is the project-scoped Claude Code settings file. The skill's `assets/settings.local.json.template` is the parametric source; the snippet above produces the same JSON shape.

If the file already exists (e.g. it has other settings), merge instead of overwrite:

```powershell
$path = ".claude/settings.local.json"
$existing = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $existing.env) { $existing | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }
$existing.env | Add-Member -NotePropertyName NODE_TLS_REJECT_UNAUTHORIZED -NotePropertyValue "0" -Force
$existing | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $path
```

---

## 3. Layer 2 setter — User-scope env var (the load-bearing layer)

```powershell
[System.Environment]::SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED", "0", "User")
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"  # current process — see dual-set pattern note below

Write-Host "Set NODE_TLS_REJECT_UNAUTHORIZED=0 at User scope."
Write-Host "IMPORTANT: Close ALL Claude Code instances and reopen from a fresh PowerShell."
Write-Host "Verify with: claude mcp list  (should show 'truvio-commerce-mcp ✓ Connected' after restart)"
```

The two-line setter follows the dual-set env-var propagation pattern (canonical in `references/setup-checks.md` §4): set User scope for persistence AND the current-process `$env:` copy, then restart Claude Code from a fresh shell.

---

## 4. Verification gate (forward-reference to mcp-setup.md)

After both layers are in place AND the admin-UI MCP config is created (see `references/mcp-setup.md` Step 3), run:

```powershell
claude mcp list
```

- If it shows `truvio-commerce-mcp ✓ Connected` → Layer 2 is working.
- If it shows `Failed to connect` → return to this file, re-verify Layer 2:
  - `[Environment]::GetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED","User")` returns `"0"`?
  - Did you close ALL Claude Code instances and reopen from a fresh PowerShell after setting the var?
  - Is the `Dynamicweb.Host.Suite` host actually running on the port `.mcp.json` references?

The MCP verification gate (Connected AND >200 tools — see `references/mcp-setup.md`) is the **only** evidence the skill accepts that the TLS bypass is functioning. Don't declare setup complete on intermediate signals (e.g. `/mcp` saying "Authentication successful").

# tunnel.md

> Bring the local DW host up at a stable public HTTPS URL via ngrok so a Business Central tenant can call it. Loaded from `~/.claude/skills/truvio-pim-for-bc/SKILL.md` "Where to find things" table.

## Prerequisites

- Host running on the standard `Dynamicweb.Host.Suite` launch profile -- `https://localhost:31873` (HTTPS) and `http://localhost:35180` (HTTP). Verify via `Get-NetTCPConnection -LocalPort 35180 -State Listen` before running ngrok.
- **Paid ngrok account with a reserved domain.** Free tier shows an HTML interstitial on first browser visit which the BC connector will choke on (it expects JSON, gets HTML). Free tier also gives random subdomains that change on restart -- BC's connector config can't track that.
- ngrok 3.x installed and authtoken configured. Install on Windows: `winget install Ngrok.Ngrok`. Authenticate: `ngrok config add-authtoken <token>`. Verify: `ngrok config check`.

## Why HTTP profile, not HTTPS

Tunnel `http://localhost:35180`, not `https://localhost:31873`. Reasoning:

- ngrok's edge already terminates TLS with a real cert; the public URL is HTTPS regardless of the upstream.
- Tunnelling the HTTPS profile means ngrok has to re-verify the local dev cert. The `dw10-suite` template ships with a self-signed dev cert that ngrok's upstream verification rejects unless you pass `--upstream-tls-verify=disabled` (3.18+) or the older flag set. Adds friction with no benefit.
- The HTTP profile is plaintext loopback only -- ngrok forwards plaintext from edge to localhost; nothing leaves the box unencrypted.

## ngrok flag drift -- 3.3.x vs 3.18+

The reserved-domain flag changed names. Pick the right one for your installed version (`ngrok version`):

| ngrok version | Reserved-domain flag |
|---|---|
| 3.3.x -- 3.17.x | `--domain=<reserved>` |
| 3.18.x and later | `--url=<reserved>` (the old `--domain` still works but is deprecated) |

If you pass the wrong flag, ngrok prints help text + `unknown flag` and exits 1. The help dump is misleadingly long -- look for the `unknown flag:` line.

## Recipe (ngrok 3.3.x against reserved domain)

```powershell
$ngrok = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe"
& $ngrok http --domain=<your-reserved>.ngrok.app --log=stdout --log-format=json 35180
```

For ngrok 3.18+ swap `--domain=` for `--url=`. For a script that auto-picks, parse `ngrok version` output once and branch.

The flags are deliberate:

- `--log=stdout --log-format=json` makes the tunnel-up event greppable. The handshake-success line has shape `{"msg":"started tunnel","url":"https://<reserved>.ngrok.app","addr":"http://localhost:35180"}`. A monitor or `until` loop on `started tunnel|err=|level=error` lets the orchestrator know when to start probing.
- No `--host-header=rewrite`. We want ngrok to forward the public Host header so `ForwardedHeaders` (see [forwarded-headers.md](forwarded-headers.md)) can promote it into `Request.Host`. Rewriting Host to `localhost:35180` would make DW think it's local and emit localhost URLs in absolute paths.
- No `--inspect=false` for demos. The web inspector at `127.0.0.1:4040` is useful when troubleshooting which header BC is actually sending; turn it off only in CI.

## Smoke test (run after tunnel is up)

```powershell
$base = "https://<your-reserved>.ngrok.app"
$token = (Get-Content ".\.claude\settings.local.json" | ConvertFrom-Json).env.DW_API_TOKEN
$h = @{ "Authorization" = "Bearer $token"; "Accept" = "application/json" }

# 1. Auth + connector reachable through public URL
Invoke-RestMethod -Uri "$base/admin/api/BCLicense" -Headers $h | ConvertTo-Json -Depth 3
# Expect: { successful: true, model: { pim: true, ecommerce: true, version: 2, ... } }

# 2. Settings round-trip
Invoke-RestMethod -Uri "$base/admin/api/BCSettings" -Headers $h | ConvertTo-Json -Depth 3

# 3. Field schema (proves PIM data is reachable through the tunnel)
$fields = Invoke-RestMethod -Uri "$base/admin/api/BCProductFields" -Headers $h
"Field count: $($fields.model.fields.Count)"

# 4. ForwardedHeaders sanity -- run the Verification block in forwarded-headers.md
```

## Tunnel lifecycle for a demo

- **Start**: launch the tunnel via `run_in_background` so you can keep working. Watch the log for `started tunnel`.
- **Verify**: smoke test above. Should take < 5 seconds.
- **Demo**: BC's PIM connector config points at the reserved domain. URL is stable across `ngrok` restarts as long as the same reserved domain is passed.
- **Stop**: `TaskStop` the background ngrok task, OR Ctrl+C in the foreground shell. The reserved domain stays reserved on your account; the *agent* (this binary instance) terminates.

## The web inspector at `127.0.0.1:4040`

ngrok exposes a local-only HTTP UI at `http://127.0.0.1:4040` showing every request through the tunnel -- request headers (BC's `Authorization`, `User-Agent`, BC tenant ID if any), response status, latency. Invaluable when BC says "the connector returns an error" -- inspect first, ask second.

The `Authorization`-header-dropped-on-redirect pitfall lives in the [forwarded-headers.md](forwarded-headers.md) troubleshooting table.

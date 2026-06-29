# forwarded-headers.md

## Contents

- [Customisations preflight](#customisations-preflight)
- [Why this is needed](#why-this-is-needed)
- [The exact edit](#the-exact-edit)
- [Restart required](#restart-required)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [When NOT to do this](#when-not-to-do-this)

> Wire ASP.NET Core `ForwardedHeaders` middleware in `Program.cs` so DW emits public URLs in any absolute-URL paths -- redirects, JSON payloads, OpenID metadata, JWT issuer URIs. Without this, DW thinks it's still `https://localhost:31873` and BC follows redirects to localhost (and obviously fails). Loaded from `~/.claude/skills/dynamicweb-pim-for-bc/SKILL.md` "Where to find things" table.

## Customisations preflight

This is a `Program.cs` edit -- a customisation. **Run the customisations-ledger preflight from `dynamicweb-demo-base/references/customisations.md` before applying.** Approved ledger entry shape (drop into `CUSTOMISATIONS.md` at solution root):

```
| Path | Type | Reason | Date approved |
|------|------|--------|---------------|
| Dynamicweb.Host.Suite/Program.cs | Middleware wiring | Add `UseForwardedHeaders` so DW honours `X-Forwarded-Proto`/`X-Forwarded-Host` from the ngrok edge during BC connector demos. Required for absolute-URL emission to use the public ngrok hostname. | YYYY-MM-DD |
```

The diff is small (8 lines added) and the middleware is opt-in, so the customisation footprint stays low. Phase-4 review target of zero custom controllers is unaffected -- this is middleware, not a controller.

## Why this is needed

Default `dw10-suite` template `Program.cs` is bare:

```csharp
using Microsoft.AspNetCore.Builder;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDynamicweb(builder.Environment, builder.Configuration);

var app = builder.Build();
app.UseDynamicweb();

app.Run();
```

`AddDynamicweb` does NOT register `ForwardedHeaders`. ASP.NET Core's default behaviour: `Request.Scheme` and `Request.Host` come from the *immediate* connection (which from DW's view is `http://localhost:35180`, not `https://<reserved>.ngrok.app`). Anywhere DW generates absolute URLs -- via `Url.Action`, `IHttpContextAccessor.HttpContext.Request.GetDisplayUrl`, `Request.Scheme + "://" + Request.Host + path`, etc. -- the result is `http://localhost:35180/whatever`. BC follows that and fails.

`UseForwardedHeaders` reads `X-Forwarded-Proto` and `X-Forwarded-Host` (and optionally `X-Forwarded-For` for client IP) from the upstream proxy and overwrites `Request.Scheme`/`Host`/`Connection.RemoteIpAddress`. Once installed, DW's URL generation produces `https://<reserved>.ngrok.app/whatever`.

## The exact edit

Replace the bare-template `Program.cs` with:

```csharp
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDynamicweb(builder.Environment, builder.Configuration);

// Trust X-Forwarded-* headers from the ngrok edge so DW emits public URLs
// in redirects/links instead of localhost. Permissive (clear KnownProxies/
// KnownNetworks) is appropriate for a demo host that only listens on
// localhost -- ngrok is the only path inbound when the tunnel is up.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders =
        ForwardedHeaders.XForwardedFor |
        ForwardedHeaders.XForwardedHost |
        ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

var app = builder.Build();
app.UseForwardedHeaders();
app.UseDynamicweb();

app.Run();
```

Three things matter, in order of subtlety:

1. **`KnownNetworks.Clear()` + `KnownProxies.Clear()`** -- by default ASP.NET Core only honours forwarded headers from `127.0.0.1`/`::1`. ngrok forwards from `127.0.0.1` so that should work, but production `ForwardedHeadersOptions` documentation guides toward an explicit allowlist. Clearing both = "trust whatever upstream sends these headers". Safe here because the host listens only on localhost; ngrok is the only inbound path. **Do NOT clear these on a host that has direct internet exposure.**

2. **`UseForwardedHeaders` BEFORE `UseDynamicweb`.** The middleware that promotes `X-Forwarded-*` into `Request.Scheme`/`Host` must run first; DW middleware downstream reads the rewritten values. If you put `UseForwardedHeaders` after `UseDynamicweb`, DW sees the local values and the rewrite has no effect.

3. **All three flags (`Proto`, `Host`, `For`)** -- you need `Proto` for HTTPS scheme, `Host` for the public hostname, and `For` for the original client IP (useful for logging; harmless if BC's behind its own reverse proxy).

## Restart required

Code change. The running host must be stopped and `dotnet run` restarted before the middleware is active. Verify post-restart by checking the host log for the standard "Now listening on..." lines (no extra log entries from `ForwardedHeaders` itself -- it's silent).

## Verification

After tunnel is up (see [tunnel.md](tunnel.md)) and host has restarted with the new `Program.cs`:

```powershell
# Hit the public URL, scan the response HTML for any localhost leak.
$root = Invoke-WebRequest -Uri "https://<your-reserved>.ngrok.app/" -MaximumRedirection 0
$content = [System.Text.Encoding]::UTF8.GetString($root.RawContentStream.ToArray())
"localhost refs: $([regex]::Matches($content, 'localhost(:\d+)?').Count)"            # should be 0
"public-host refs: $([regex]::Matches($content, '<your-reserved>\.ngrok\.app').Count)"  # should be > 0
```

Zero `localhost` references and at least one ngrok-host reference = `ForwardedHeaders` is working. If you still see `localhost` references, double-check the middleware ordering and that the host restarted after the edit.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `localhost:35180` still appears in public-URL responses | `UseForwardedHeaders` placed after `UseDynamicweb`; or host wasn't restarted after edit; or `ForwardedHeaders.XForwardedHost` flag missing |
| Public-URL responses show `http://` even though tunnel is HTTPS | `ForwardedHeaders.XForwardedProto` flag missing |
| Logs flooded with "ignoring forwarded header from untrusted proxy" | `KnownNetworks`/`KnownProxies` not cleared -- ngrok forwards from `127.0.0.1` which IS in the default allowlist, but if you're behind a corporate proxy the chain may go through other IPs first |
| BC connector returns 401 on retry-after-redirect | Different problem -- BC may strip `Authorization` on cross-host redirect. The `/admin/api/BC*` surface doesn't redirect, so this shouldn't bite for connector flows; if you're seeing it, it's likely Admin UI not BC API |

## When NOT to do this

- Production hosts with direct internet exposure -- the permissive `KnownNetworks.Clear()` is unsafe. Use an explicit `KnownProxies.Add(...)` with the specific upstream IPs.
- Demos that don't need absolute-URL accuracy. If BC just calls `/admin/api/BC*` and reads JSON (no link-following), `ForwardedHeaders` is defensive but not required. We add it anyway because the BC connector occasionally surfaces absolute URLs in error messages or admin UI panels and the inconsistency confuses the demo audience.

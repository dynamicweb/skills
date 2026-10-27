# Forwarded headers for a local PIM tunnel

Truvio Commerce (powered by Dynamicweb) must emit the public HTTPS host when BC follows
generated product links. First test the current hosting topology. A reverse proxy may already
set the correct scheme/host; a working public deployment needs no duplicate middleware.

## Customisation preflight

Read the demo's `CUSTOMISATIONS.md`, host instructions and freeze window before editing
`Program.cs`. Record the changed file, reason, rollback and evidence in the ledger. Keep the
host's existing startup configuration and package/version pin. A code change needs an
authorised build/restart window; this recipe does not create that window.

## Configure the actual proxy

For a loopback ngrok upstream, add the following configuration to the existing startup
before building the application. `DW_PUBLIC_HOST` is the allocated hostname, without scheme
or port. For any other proxy, use its actual trusted address/network instead of loopback.

```csharp
using System.Net;
using Microsoft.AspNetCore.HttpOverrides;

var publicHost = Environment.GetEnvironmentVariable("DW_PUBLIC_HOST")
    ?? throw new InvalidOperationException("Set DW_PUBLIC_HOST to the allocated public hostname.");
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedProto
        | ForwardedHeaders.XForwardedHost | ForwardedHeaders.XForwardedFor;
    options.KnownProxies.Add(IPAddress.Loopback);
    options.KnownProxies.Add(IPAddress.IPv6Loopback);
    options.ForwardLimit = 1;
    options.AllowedHosts.Add(publicHost);
});
```

Place `app.UseForwardedHeaders()` before `app.UseDynamicweb()` and any authentication,
HTTPS-redirect or link-generating middleware. Retain the rest of the existing pipeline.
Keep explicit trusted proxies; clearing all proxy/network restrictions trusts arbitrary
forwarded headers. Review pre-existing proxy settings before adding these lines.

## Verify after the authorised restart

```powershell
$public = [uri]$env:DW_PUBLIC_URL
if (-not $public.IsAbsoluteUri -or $public.Scheme -ne 'https') {
    throw 'Set DW_PUBLIC_URL to the allocated public HTTPS URL.'
}
$response = Invoke-WebRequest -Method Get -Uri $public.AbsoluteUri -MaximumRedirection 0
$localReferences = [regex]::Matches($response.Content, 'https?://(?:localhost|127\.0\.0\.1)(?::\d+)?').Count
if ($localReferences -gt 0) { throw 'Public response still contains loopback URLs; inspect the emitted links.' }
```

The absence of loopback links alone does not prove the middleware. Inspect an actual absolute
product link or redirect and assert the allocated public HTTPS host; follow it from BC.
Check middleware order, immediate proxy address, forwarded host allowlist and restart state
if the scheme or host is wrong. HTTP 401 after a cross-host redirect is a separate
authentication problem; fix the URL and avoid forwarding the bearer across hosts.

Source: [ASP.NET Core proxy configuration](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/proxy-load-balancer).

# Public HTTPS for the PIM connector

Truvio Commerce (powered by Dynamicweb) needs a stable public HTTPS URL when the BC PIM
extension calls a locally hosted solution. A hosted solution with a working public URL
does not need a tunnel. This recipe is separate from Commerce calling BC's ERP endpoints.

## Preflight

Read the host's actual launch profile and listening sockets. Select a loopback HTTP upstream
and set `DW_HTTP_UPSTREAM` to that URL, including its discovered port. Set `DW_PUBLIC_URL`
to the domain allocated to this demo. Use the existing authenticated ngrok configuration;
confirm `ngrok config check` and inspect `ngrok http --help` for the installed CLI's flags.

A stable free development domain may be available. Verify plan limits and test the actual BC
request for an HTML warning page; the free-plan browser warning does not mean every API call
fails. Choose a reserved/paid endpoint only when the existing account and required traffic
need one. Do not rotate the configured BC URL on every start.

## Start the tunnel

```powershell
$upstream = [uri]$env:DW_HTTP_UPSTREAM
$public = [uri]$env:DW_PUBLIC_URL
if (-not $upstream.IsAbsoluteUri -or -not $upstream.IsLoopback -or $upstream.Scheme -ne 'http') {
    throw 'Set DW_HTTP_UPSTREAM to the discovered loopback HTTP launch URL.'
}
if (-not $public.IsAbsoluteUri -or $public.Scheme -ne 'https') {
    throw 'Set DW_PUBLIC_URL to the allocated public HTTPS URL.'
}
ngrok http $upstream.AbsoluteUri --url $public.AbsoluteUri --inspect=false --log=stdout --log-format=json
```

The modern CLI uses `--url`; consult local help if an older installation requires `--domain`.
The public edge terminates HTTPS and the local hop stays loopback. An HTTPS upstream needs
a certificate chain the tunnel trusts; use the selected HTTP launch profile rather than
disabling certificate validation. Preserve the public host and verify
[forwarded headers](forwarded-headers.md) if generated links or redirects need them.

Run in the session's supported background process facility. If using PowerShell
`Start-Process`, use `-WindowStyle Hidden`, record that process ID and keep logs outside the
repo. Stop only that recorded process at the end; another demo may own a different tunnel.

## Smoke test

Use the dedicated Commerce Management API token from the process environment. These are
Management API reads, not Dynamicweb MCP tools or BC ERP APIs:

```powershell
$public = [uri]$env:DW_PUBLIC_URL
if ($public.Scheme -ne 'https' -or -not $env:DW_API_TOKEN) {
    throw 'Set DW_PUBLIC_URL and resolve DW_API_TOKEN from the vault into this process.'
}
$headers = @{ Authorization = "Bearer $env:DW_API_TOKEN"; Accept = 'application/json' }
$base = $public.AbsoluteUri.TrimEnd('/')
$license = Invoke-RestMethod -Method Get -Uri "$base/admin/api/BCLicense" -Headers $headers -MaximumRedirection 0
$settings = Invoke-RestMethod -Method Get -Uri "$base/admin/api/BCSettings" -Headers $headers -MaximumRedirection 0
$fields = Invoke-RestMethod -Method Get -Uri "$base/admin/api/BCProductFields" -Headers $headers -MaximumRedirection 0
```

Assert the response shapes and connector success fields without printing headers or tokens.
Then run BC's own connection and field-mapping checks in [bc-side-config.md](bc-side-config.md).
Inspect redirects before following them so a bearer token cannot travel to an unintended host.
Keep request inspection disabled unless needed briefly; captured headers may contain credentials.

Sources: [ngrok stable dev domains](https://ngrok.com/blog/free-static-domains-ngrok-users),
[current agent command](https://ngrok.com/download/coding-agent).

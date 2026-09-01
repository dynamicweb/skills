<#
.SYNOPSIS
    READ-ONLY. Verifies a Dynamicweb host answers its post-install contract
    and writes a PASS/FAIL report.

.DESCRIPTION
    Runs the dw-setup-install verification checks as one harness: /admin
    reachable and licensed (not redirecting to /admin/license), /admin/mcp
    answering 401 unauthenticated, HEAD /admin/mcp/bootstrap answering 405,
    and — when -McpToken is given — the MCP JSON-RPC handshake, a tool count
    above 200, and get_areas/get_shops returning data. A custom expectation
    table (-Expectation, a .psd1 array of @{ Name; Method; Path; ExpectStatus;
    BodyPattern }) replaces the HTTP checks when supplied.

    Exit 0 when every check passes, 1 otherwise. -OutFile writes the same
    results as a markdown table. Self-contained by design (dw-setup-install
    scripts run before the shared module's bundles exist); TLS validation is
    skipped only for a localhost base URL or with -AllowSelfSignedCertificate.

    Owning reference: dw-setup-install/SKILL.md ("Verification").

.PARAMETER BaseUrl
    Base URL of the Dynamicweb site, e.g. https://localhost:<port> — read the
    port from Dynamicweb.Host.Suite/Properties/launchSettings.json.

.PARAMETER McpToken
    MCP bearer token; enables the MCP handshake, tool-count, and data checks.
    Defaults to $env:DW_MCP_TOKEN when set.

.PARAMETER Expectation
    Path to a .psd1 file holding an array of custom HTTP checks:
    @{ Name = '...'; Method = 'GET'; Path = '/...'; ExpectStatus = 200;
       BodyPattern = 'regex' } (BodyPattern optional).

.PARAMETER OutFile
    Write the results as a markdown report to this path.

.PARAMETER TimeoutSec
    Per-request timeout.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS certificate validation for a non-localhost base URL.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwHostReady.ps1 -BaseUrl "https://localhost:<port>"

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwHostReady.ps1 -BaseUrl "https://localhost:<port>" -McpToken $env:DW_MCP_TOKEN -OutFile readiness.md
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$McpToken = $env:DW_MCP_TOKEN,
    [string]$Expectation,
    [string]$OutFile,
    [int]$TimeoutSec = 30,
    [switch]$AllowSelfSignedCertificate
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
$skipCert = [bool](($BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)') -or $AllowSelfSignedCertificate)
$results = [System.Collections.Generic.List[object]]::new()

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $results.Add([pscustomobject]@{ Name = $Name; OK = $Ok; Detail = $Detail })
    $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} — {2}" -f $mark, $Name, $Detail)
}

function Invoke-Probe([string]$Method, [string]$Path) {
    Invoke-WebRequest -Uri "$BaseUrl$Path" -Method $Method -TimeoutSec $TimeoutSec `
        -SkipCertificateCheck:$skipCert -SkipHttpErrorCheck -MaximumRedirection 5
}

function Invoke-McpRpc([hashtable]$Payload, [hashtable]$Headers) {
    $r = Invoke-WebRequest -Uri "$BaseUrl/admin/mcp" -Method Post `
        -Body ($Payload | ConvertTo-Json -Depth 10) -ContentType 'application/json' `
        -Headers $Headers -TimeoutSec $TimeoutSec -SkipCertificateCheck:$skipCert
    $data = @($r.Content -split "`n" | Where-Object { $_ -match '^data:' })
    $json = if ($data.Count -gt 0) { $data[-1] -replace '^data:\s?', '' } else { $r.Content }
    @{ Reply = ($json | ConvertFrom-Json); SessionId = ($r.Headers['mcp-session-id'] | Select-Object -First 1) }
}

if ($Expectation) {
    # Custom table replaces the default HTTP checks.
    foreach ($check in (Import-PowerShellDataFile -LiteralPath $Expectation)) {
        try {
            $r = Invoke-Probe ($check.Method ?? 'GET') $check.Path
            $ok = $r.StatusCode -eq $check.ExpectStatus
            $detail = "status $($r.StatusCode) (want $($check.ExpectStatus))"
            if ($ok -and $check.BodyPattern) {
                $content = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
                $ok = $content -match $check.BodyPattern
                if (-not $ok) { $detail += "; body lacks /$($check.BodyPattern)/" }
            }
            Add-Check $check.Name $ok $detail
        }
        catch { Add-Check $check.Name $false $_.Exception.Message }
    }
}
else {
    # 1. /admin reachable and licensed
    try {
        $r = Invoke-Probe GET '/admin'
        $finalUrl = [string]$r.BaseResponse.RequestMessage.RequestUri
        if ($finalUrl -match '/admin/license($|[/?#])') {
            Add-Check 'admin licensed' $false "redirects to /admin/license — install a license (activate-free-trial.ps1)"
        }
        else {
            Add-Check 'admin reachable' ($r.StatusCode -eq 200) "GET /admin -> $($r.StatusCode)"
        }
    }
    catch { Add-Check 'admin reachable' $false $_.Exception.Message }

    # 2. /admin/mcp gate: 401 unauthenticated
    try {
        $r = Invoke-Probe GET '/admin/mcp'
        Add-Check 'mcp route gated' ($r.StatusCode -eq 401) "GET /admin/mcp -> $($r.StatusCode) (want 401; 404 means Custom.Mcp is not deployed or the host is not on net10.0)"
    }
    catch { Add-Check 'mcp route gated' $false $_.Exception.Message }

    # 3. bootstrap route present: HEAD -> 405
    try {
        $r = Invoke-Probe HEAD '/admin/mcp/bootstrap'
        Add-Check 'bootstrap route present' ($r.StatusCode -eq 405) "HEAD /admin/mcp/bootstrap -> $($r.StatusCode) (want 405)"
    }
    catch { Add-Check 'bootstrap route present' $false $_.Exception.Message }

    if ($McpToken) {
        try {
            $headers = @{ Authorization = "Bearer $McpToken"; Accept = 'application/json, text/event-stream' }
            $init = Invoke-McpRpc @{
                jsonrpc = '2.0'; id = 1; method = 'initialize'
                params  = @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'Test-DwHostReady'; version = '1.0' } }
            } $headers
            if ($init.SessionId) { $headers['mcp-session-id'] = $init.SessionId }
            Add-Check 'mcp handshake' ($null -ne $init.Reply.result) "server: $($init.Reply.result.serverInfo.name) $($init.Reply.result.serverInfo.version)"
            Invoke-McpRpc @{ jsonrpc = '2.0'; method = 'notifications/initialized' } $headers | Out-Null

            $tools = @(); $cursor = $null; $rpcId = 1
            do {
                $params = if ($cursor) { @{ cursor = $cursor } } else { @{} }
                $page = Invoke-McpRpc @{ jsonrpc = '2.0'; id = (++$rpcId); method = 'tools/list'; params = $params } $headers
                $tools += $page.Reply.result.tools
                $cursor = $page.Reply.result.nextCursor
            } while ($cursor)
            Add-Check 'mcp tool count > 200' ($tools.Count -gt 200) "$($tools.Count) tools"

            foreach ($probe in @(
                    @{ Tool = 'get_areas'; Check = 'areas present' },
                    @{ Tool = 'get_shops'; Check = 'shops present' })) {
                $call = Invoke-McpRpc @{ jsonrpc = '2.0'; id = (++$rpcId); method = 'tools/call'; params = @{ name = $probe.Tool; arguments = @{} } } $headers
                $ok = ($null -ne $call.Reply.result) -and (-not $call.Reply.error) -and (-not $call.Reply.result.isError)
                Add-Check $probe.Check $ok "$($probe.Tool) $(if ($ok) { 'returned a result' } else { 'failed' })"
            }
        }
        catch { Add-Check 'mcp checks' $false $_.Exception.Message }
    }
    else {
        Write-Host 'NOTE: no -McpToken / $env:DW_MCP_TOKEN — MCP handshake, tool-count, and data checks skipped.'
    }
}

$passed = @($results | Where-Object OK).Count
$failed = @($results | Where-Object { -not $_.OK }).Count
Write-Host ''
Write-Host "$passed passed, $failed failed."

if ($OutFile) {
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# Host readiness — $BaseUrl ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))")
    $md.Add('')
    $md.Add('| Check | Result | Detail |')
    $md.Add('|---|---|---|')
    foreach ($row in $results) {
        $md.Add("| $($row.Name) | $(if ($row.OK) { 'PASS' } else { 'FAIL' }) | $($row.Detail -replace '\|', '\|') |")
    }
    $md.Add('')
    $md.Add("**$passed passed, $failed failed.**")
    Set-Content -LiteralPath $OutFile -Value ($md -join "`n") -Encoding UTF8
    Write-Host "Report written: $OutFile"
}

if ($failed -gt 0) { exit 1 }
exit 0

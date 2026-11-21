<#
.SYNOPSIS
    READ-ONLY. The one HTTP call of the shared transport; a request writes only what its caller sends.

.DESCRIPTION
    Invoke-DwHttp takes the Invoke-WebRequest parameters the transport uses (-Rest makes it
    Invoke-RestMethod) and, on the normal path, calls that cmdlet with exactly the parameters it
    was given: the same timeouts, certificate handling, error records and status codes.

    Some sandboxed agent shells run PowerShell under a restricted token that cannot acquire TLS
    credentials from the platform: every HTTPS call fails with "No credentials are available in
    the security package" (SEC_E_NO_CREDENTIALS, 0x8009030E), to any host, while Node, which
    ships its own TLS, still connects. When a call fails with exactly that failure and node 18 or
    later is on PATH, the call is retried through Dw.Http.mjs beside this file, and the rest of the
    process stays on Node. An ordinary certificate error, a 4xx or 5xx, a DNS failure or a timeout
    never switches. DW_HTTP_TRANSPORT forces the choice: auto (the default), powershell or node.

    The Node path rebuilds what the callers read: StatusCode, Content (text for a text type,
    bytes otherwise), Headers, an Invoke-RestMethod result parsed from JSON, -OutFile, and on a
    status outside 2xx the same HttpResponseException with the response and ErrorDetails. It does
    not carry -Form, -WebSession or -SessionVariable. The request goes to the helper on stdin, so
    no header or token is ever on a command line, and every message it raises masks the header
    values. The certificate bypass is the caller's: Dw.Api.psm1 grants it for a localhost base URL
    or after -AllowSelfSignedCertificate, and this file only passes the switch on.

    Dot-source it (Dw.Api.psm1 does; the ledger and recipe transports do too, so their calls
    resolve in their own scope).

.EXAMPLE
    . (Join-Path $PSScriptRoot 'Dw.Http.ps1')
    $descriptor = Invoke-DwHttp -Rest -Uri "$base/admin/api/api.json" -TimeoutSec 20
#>
#Requires -Version 7.0
param()

if (-not (Get-Variable -Name DwHttpTransport -Scope Global -ErrorAction Ignore)) {
    $global:DwHttpTransport = @{ engaged = $false; noted = $false; probed = $false; node = $null; nodeVersion = $null }
}

function Reset-DwHttpTransport {
    # Forget the process-wide choice (tests; a shell whose PATH changed).
    $global:DwHttpTransport = @{ engaged = $false; noted = $false; probed = $false; node = $null; nodeVersion = $null }
}

function Get-DwHttpTransportMode {
    $value = "$env:DW_HTTP_TRANSPORT".Trim().ToLowerInvariant()
    if (-not $value) { return 'auto' }
    if ($value -notin @('auto', 'powershell', 'node')) {
        throw [ArgumentException]::new("DW_HTTP_TRANSPORT is '$($env:DW_HTTP_TRANSPORT)'; it takes auto (the default), powershell or node.")
    }
    $value
}

function Test-DwTlsCredentialFailure {
    # True only for the platform refusing TLS credentials to this process. A certificate the
    # client rejects is an AuthenticationException too, so the type alone never decides.
    param($Exception)
    for ($e = $Exception; $e; $e = $e.InnerException) {
        if ($e -is [ComponentModel.Win32Exception] -and ((([int64]$e.NativeErrorCode) -band 0xFFFFFFFFL) -eq 0x8009030EL)) { return $true }
        if (($e -is [ComponentModel.Win32Exception] -or $e -is [Security.Authentication.AuthenticationException]) -and
            $e.Message -match 'No credentials are available in the security package|SEC_E_NO_CREDENTIALS|0x8009030E') { return $true }
    }
    $false
}

function Get-DwNodeRuntime {
    # The path of node 18 or later on PATH, or $null. Probed once per process.
    if ($global:DwHttpTransport.probed) { return $global:DwHttpTransport.node }
    $global:DwHttpTransport.probed = $true
    $command = Get-Command -Name node -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($command) {
        $version = "$(& $command.Source --version 2>$null)".Trim()
        $global:DwHttpTransport.nodeVersion = $version
        if ($version -match '^v(\d+)\.' -and [int]$Matches[1] -ge 18) { $global:DwHttpTransport.node = $command.Source }
    }
    $global:DwHttpTransport.node
}

function Get-DwNodeMissingReason {
    if ($global:DwHttpTransport.nodeVersion) { return "node on PATH is $($global:DwHttpTransport.nodeVersion), and the Node transport needs 18 or later" }
    'node (18 or later) is not on PATH'
}

function Format-DwHttpMasked {
    # A message with every header value of the request, and any bearer token, masked.
    param([string]$Text, $Headers)
    if (-not $Text) { return $Text }
    if ($Headers -is [Collections.IDictionary]) {
        foreach ($value in @($Headers.Values)) { if ("$value".Length -ge 4) { $Text = $Text.Replace("$value", '***') } }
    }
    $Text -replace '(?i)Bearer\s+\S+', 'Bearer ***'
}

function New-DwNodeStartInfo {
    # The command line names the helper and nothing else: the request travels on stdin.
    param([string]$Node, [string]$Helper)
    $info = [Diagnostics.ProcessStartInfo]::new($Node)
    $info.ArgumentList.Add('--no-warnings')
    $info.ArgumentList.Add($Helper)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $utf8 = [Text.UTF8Encoding]::new($false)
    $info.StandardInputEncoding = $utf8
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $info
}

function Invoke-DwNodeProcess {
    # One helper run: the request JSON on stdin, the answer JSON from stdout.
    param([string]$Node, [string]$InputJson, [int]$WaitMs)
    $helper = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File) 'Dw.Http.mjs'
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw [IO.FileNotFoundException]::new('The Node transport helper Dw.Http.mjs is missing beside Dw.Http.ps1.') }
    $process = [Diagnostics.Process]::Start((New-DwNodeStartInfo $Node $helper))
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputJson)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($WaitMs)) {
            try { $process.Kill($true) } catch { Write-Verbose 'The Node transport had already exited.' }
            throw [TimeoutException]::new("The Node transport did not answer within $([int]($WaitMs / 1000)) seconds.")
        }
        $process.WaitForExit()
        @{ exitCode = $process.ExitCode; stdout = $stdout.GetAwaiter().GetResult(); stderr = $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Get-DwHttpCharset([string]$ContentType) {
    $m = [regex]::Match("$ContentType", '(?i)charset\s*=\s*"?([^";\s]+)')
    if ($m.Success) { try { return [Text.Encoding]::GetEncoding($m.Groups[1].Value) } catch { Write-Verbose "Unknown charset $($m.Groups[1].Value); reading UTF-8." } }
    [Text.UTF8Encoding]::new($false)
}

function ConvertTo-DwNodeRequest {
    # The bound Invoke-WebRequest parameters as the helper's request object.
    param([hashtable]$Bound)
    foreach ($name in @('Form', 'WebSession', 'SessionVariable', 'InFile', 'Credential', 'UseDefaultCredentials', 'Proxy')) {
        if ($Bound.ContainsKey($name)) { throw [NotSupportedException]::new("-$name is not carried by the Node transport; run this call from a shell that can open TLS connections from PowerShell.") }
    }
    $method = if ($Bound.ContainsKey('Method')) { "$($Bound.Method)".ToUpperInvariant() } else { 'GET' }
    $url = "$($Bound.Uri)"
    $headers = [ordered]@{}
    if ($Bound.Headers -is [Collections.IDictionary]) { foreach ($k in @($Bound.Headers.Keys)) { $headers[[string]$k] = [string]$Bound.Headers[$k] } }
    $contentType = if ($Bound.ContainsKey('ContentType')) { [string]$Bound.ContentType } else { $null }
    if (-not @($headers.Keys | Where-Object { $_ -ieq 'User-Agent' }).Count) {
        # why: the Node path sends the User-Agent PowerShell sends, so a server that varies on it answers alike.
        $headers['User-Agent'] = "Mozilla/5.0 ($([Environment]::OSVersion.Platform -replace 'Win32NT', 'Windows NT') $([Environment]::OSVersion.Version.ToString(2)); $([Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()); $([Globalization.CultureInfo]::CurrentCulture.Name)) PowerShell/$($PSVersionTable.PSVersion)"
    }
    $bytes = $null
    if ($Bound.ContainsKey('Body') -and $null -ne $Bound.Body) {
        $body = $Bound.Body
        if ($body -is [byte[]]) { $bytes = $body }
        elseif ($body -is [Collections.IDictionary]) {
            $pairs = @(foreach ($k in @($body.Keys)) { [Net.WebUtility]::UrlEncode([string]$k) + '=' + [Net.WebUtility]::UrlEncode([string]$body[$k]) })
            if ($method -eq 'GET') { $url += $(if ($url.Contains('?')) { '&' } else { '?' }) + ($pairs -join '&') }
            else { $bytes = [Text.Encoding]::UTF8.GetBytes($pairs -join '&') }
        } else { $bytes = (Get-DwHttpCharset $contentType).GetBytes([string]$body) }
        if ($null -ne $bytes -and -not $contentType) { $contentType = 'application/x-www-form-urlencoded' }
    }
    if ($contentType) { foreach ($k in @($headers.Keys | Where-Object { $_ -ieq 'Content-Type' })) { $headers.Remove($k) }; $headers['Content-Type'] = $contentType }
    $request = [ordered]@{
        url = $url; method = $method; headers = $headers
        timeoutSec = $(if ($Bound.ContainsKey('TimeoutSec')) { [int]$Bound.TimeoutSec } else { 0 })
        skipCertificateCheck = [bool]$Bound.SkipCertificateCheck
        followRedirects = -not ($Bound.ContainsKey('MaximumRedirection') -and [int]$Bound.MaximumRedirection -le 0)
    }
    if ($null -ne $bytes) { $request.bodyBase64 = [Convert]::ToBase64String([byte[]]$bytes) }
    $request
}

function Invoke-DwHttpViaNode {
    # The call through Dw.Http.mjs, answered in the shape the cmdlet would have answered.
    [CmdletBinding()]
    param([hashtable]$Bound, [switch]$Rest)
    $node = Get-DwNodeRuntime
    if (-not $node) { throw [InvalidOperationException]::new("DW_HTTP_TRANSPORT selects the Node transport, but $(Get-DwNodeMissingReason).") }
    $request = ConvertTo-DwNodeRequest $Bound
    $waitMs = if ($request.timeoutSec -gt 0) { $request.timeoutSec * 1000 + 15000 } else { -1 }
    $run = Invoke-DwNodeProcess -Node $node -InputJson ($request | ConvertTo-Json -Depth 5 -Compress) -WaitMs $waitMs
    $answer = $null
    try { $answer = ConvertFrom-Json -InputObject $run.stdout -AsHashtable } catch { $answer = $null }
    if ($answer -isnot [Collections.IDictionary]) {
        $why = Format-DwHttpMasked ((("$($run.stderr)" -replace '\s+', ' ').Trim()) -replace '^(.{300}).+$', '$1...') $request.headers
        throw [Net.Http.HttpRequestException]::new("The Node transport gave no answer (exit $($run.exitCode))$(if ($why) { ": $why" }).")
    }
    if ($answer.error) {
        $message = Format-DwHttpMasked ([string]$answer.error.message) $request.headers
        if ($answer.error.kind -eq 'timeout') { throw [TimeoutException]::new("The request was canceled due to the configured timeout of $($request.timeoutSec) seconds elapsing (Node transport).") }
        throw [Net.Http.HttpRequestException]::new("$message (Node transport$(if ($answer.error.code) { ", $($answer.error.code)" }))")
    }
    $status = [int]$answer.status
    $bytes = [Convert]::FromHexString([string]$answer.bodyHex)
    $headers = [Collections.Generic.Dictionary[string, string[]]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @($answer.headers.Keys)) { $headers[$k] = [string[]]@($answer.headers[$k]) }
    $type = if ($headers.ContainsKey('Content-Type')) { $headers['Content-Type'][0] } else { '' }
    $isText = $type -match '(?i)^text/|[/+](json|xml)\b|javascript|x-www-form-urlencoded'
    $text = if ($isText -or $Rest -or ($status -lt 200 -or $status -gt 299)) { (Get-DwHttpCharset $type).GetString($bytes) } else { $null }
    if (($status -lt 200 -or $status -gt 299) -and -not $Bound.SkipHttpErrorCheck) {
        $message = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$status)
        $message.ReasonPhrase = [string]$answer.statusText
        $message.Content = [Net.Http.ByteArrayContent]::new($bytes)
        foreach ($k in $headers.Keys) { if (-not $message.Headers.TryAddWithoutValidation($k, $headers[$k])) { $null = $message.Content.Headers.TryAddWithoutValidation($k, $headers[$k]) } }
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $status ($($answer.statusText)).", $message)
        $record = [Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', [Management.Automation.ErrorCategory]::InvalidOperation, $null)
        if ($text) {
            $details = $text
            try { $details = ConvertFrom-Json -InputObject $text -NoEnumerate | ConvertTo-Json -Depth 100 } catch { $details = $text }
            $record.ErrorDetails = [Management.Automation.ErrorDetails]::new($details)
        }
        $PSCmdlet.ThrowTerminatingError($record)
    }
    if ($Bound.ContainsKey('OutFile') -and $Bound.OutFile) {
        [IO.File]::WriteAllBytes($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$Bound.OutFile), $bytes)
        return
    }
    if ($Rest) {
        if (-not $text) { return }
        try { $parsed = ConvertFrom-Json -InputObject $text -NoEnumerate } catch { return $text }
        return , $parsed
    }
    [pscustomobject]@{
        StatusCode = $status; StatusDescription = [string]$answer.statusText
        Content = $(if ($isText) { $text } else { $bytes }); RawContentLength = $bytes.Length; Headers = $headers
    }
}

function Invoke-DwHttp {
    <#
    .SYNOPSIS
        READ-ONLY by itself. One HTTP call: Invoke-WebRequest, or Invoke-RestMethod with -Rest.
    .DESCRIPTION
        The parameters are the cmdlet's own and pass through unchanged. On the platform TLS
        credential failure (and only that) with DW_HTTP_TRANSPORT auto, the call is retried
        through Node and the process stays on Node; DW_HTTP_TRANSPORT node goes there directly.
    .EXAMPLE
        Invoke-DwHttp -Uri "$base/dwapi/users/authenticate" -Method Post -Body $json -ContentType 'application/json' -SkipHttpErrorCheck
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Uri,
        $Method,
        $Headers,
        $Body,
        [string]$ContentType,
        [int]$TimeoutSec,
        [switch]$SkipCertificateCheck,
        [switch]$SkipHttpErrorCheck,
        [int]$MaximumRedirection,
        [string]$OutFile,
        $Form,
        [switch]$Rest
    )
    $bound = @{} + $PSBoundParameters
    $null = $bound.Remove('Rest')
    $mode = Get-DwHttpTransportMode
    if ($mode -eq 'node' -or ($mode -eq 'auto' -and $global:DwHttpTransport.engaged)) { return Invoke-DwHttpViaNode -Bound $bound -Rest:$Rest }
    try {
        if ($Rest) { return Invoke-RestMethod @bound }
        return Invoke-WebRequest @bound
    } catch {
        if ($mode -ne 'auto' -or -not (Test-DwTlsCredentialFailure $_.Exception)) { throw }
        if (-not (Get-DwNodeRuntime)) {
            throw [Net.Http.HttpRequestException]::new("This shell cannot open TLS connections from PowerShell (no credentials in the security package), and $(Get-DwNodeMissingReason) to carry the call instead; put Node 18+ on PATH or use another shell.", $_.Exception)
        }
        $global:DwHttpTransport.engaged = $true
        if (-not $global:DwHttpTransport.noted) {
            $global:DwHttpTransport.noted = $true
            Write-Host 'NOTE transport: this shell cannot open TLS connections from PowerShell; using Node for HTTP'
        }
    }
    Invoke-DwHttpViaNode -Bound $bound -Rest:$Rest
}

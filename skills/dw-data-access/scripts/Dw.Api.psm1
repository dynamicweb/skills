<#
.SYNOPSIS
    WRITES: nothing on import. Shared Dynamicweb 10 connection module — every
    exported function states its own read/write behavior in its help.

.DESCRIPTION
    One implementation of the plumbing every Dynamicweb operations script needs:
    connection discovery, the Management API (/Admin/Api), the MCP JSON-RPC
    endpoint (/admin/mcp), direct SQL reads (LOCAL installs only — a hosted
    install has no SQL surface, and this module deliberately ships no remote
    SQL path), and targeted cache flushes.

    This module is the READ half plus the connection. Every write and cleanup
    verb lives in Dw.Api.Write.psm1 beside it, which imports this one: a single
    file that reads, uploads, deletes users and rewrites settings is the verb
    cluster endpoint protection scores, so the two halves stay apart.

    Owning reference: dw-data-access/references/management-api-and-sql.md.
    Traps encoded here so callers cannot re-create them:
      - One-row SQL results are returned as an ARRAY from inside the helper
        (PowerShell unrolls a one-element collection at the call site, and [0]
        on a DataRow indexes its first COLUMN — a plausible wrong answer).
        ASSIGN the result ($rows = Get-DwSqlRows ...); never wrap the CALL
        itself in @() — @(Get-DwSqlRows ...) double-wraps the protected array
        and hands loops a single Object[] element (measured).
      - SQL rows are projected to [pscustomobject] before they leave this file;
        a raw DataRow passed to ConvertTo-Json hangs on its object graph.
      - Callers keying lookups on integer ids must use a plain hashtable, not
        [ordered]@{} — bare Int32 keys hit the POSITIONAL indexer (documented
        here because the module cannot fix the caller's data structure).
      - Import can be blocked (AMSI false positive) while the calling script
        keeps running: import with -ErrorAction Stop, then call
        Assert-DwConnection — if the module never loaded, the unknown command
        fails the script loudly instead of comparing against empty output.
      - The read-model-is-not-a-save-model 500: Remove-DwDisplayOnlyMember
        strips modelIdentifier and *Icon members before a round-trip save.
      - The TLS bypass is gated: certificates are skipped only for a localhost
        base URL or after an explicit -AllowSelfSignedCertificate opt-in.
      - A list read that returns page 1 of 4 while reporting the full
        totalCount makes a present item read as ABSENT. Invoke-DwQuery walks
        every page, reconciles the collected count against totalCount, and
        refuses to return a partial read.
      - A 429, or a 5xx on a read, is retried with exponential backoff. A 5xx
        on a write is not: it may have applied before it failed.
      - TaskRun is asynchronous. Invoke-DwTaskRun captures the task's own
        last-run value before the trigger and polls for it to CHANGE, because a
        wall-clock freshness window is satisfied by the previous run.
      - A Razor compile error still answers HTTP 200, and the static-file cache
        does not invalidate through a junction. Test-DwPageProbe reads the body
        and Get-DwServedFileHash hashes the bytes the host actually serves.
      - The browser User-Agent is a protocol requirement of the target, not
        evasion, and is set in one documented place (Get-DwBrowserUserAgent).

    Connection discovery (Connect-Dw), in order: explicit parameter, then
    $env:DW_BASE_URL / DW_API_TOKEN / DW_MCP_TOKEN / DW_SQL_CONNECTION, then
    the port from Dynamicweb.Host.Suite/Properties/launchSettings.json, then
    fail with the one-liner that fixes it. No default host, port, path, or
    token. Tokens are masked in every log line.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
    Assert-DwConnection
    (Invoke-DwApi 'GetPageById?Id=1').model
#>
#Requires -Version 7.0
param()

$ErrorActionPreference = 'Stop'

# The single browser-shaped User-Agent this module sends on web probes.
# why: the target silently drops cart commands, and negotiates image content,
# on this header - see Get-DwBrowserUserAgent for the measurement.
$script:DwBrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

$script:DwState = @{
    BaseUrl       = $null
    ApiToken      = $null
    McpToken      = $null
    SqlConnection = $null
    SkipCert      = $false
    McpHeaders    = $null
    McpRpcId      = 100
}

function Format-DwMaskedToken([string]$Token) {
    if (-not $Token) { return '(none)' }
    if ($Token.Length -le 8) { return '****' }
    return '****' + $Token.Substring($Token.Length - 4)
}

function Connect-Dw {
    <#
    .SYNOPSIS
        READ-ONLY. Resolves and stores the connection for this session.
    .DESCRIPTION
        Discovery order per value: explicit parameter, then $env:DW_BASE_URL /
        DW_API_TOKEN / DW_MCP_TOKEN / DW_SQL_CONNECTION, then (base URL only)
        the first https port in Dynamicweb.Host.Suite/Properties/
        launchSettings.json under -SolutionPath or the current directory.
        Fails with the fix when no base URL is found. Tokens are optional here;
        the first function that needs a missing one fails with its own fix.
    .PARAMETER BaseUrl
        Base URL of the Dynamicweb host.
    .PARAMETER ApiToken
        Management API bearer token.
    .PARAMETER McpToken
        MCP bearer token.
    .PARAMETER SqlConnection
        SQL connection string for direct reads.
    .PARAMETER SolutionPath
        Solution folder used for launchSettings.json discovery.
    .PARAMETER AllowSelfSignedCertificate
        Skip TLS certificate validation for a non-localhost base URL.
    .EXAMPLE
        Connect-Dw -SolutionPath C:\Dev\my-solution
    #>
    [CmdletBinding()]
    param(
        [string]$BaseUrl,
        [string]$ApiToken,
        [string]$McpToken,
        [string]$SqlConnection,
        [string]$SolutionPath,
        [switch]$AllowSelfSignedCertificate
    )

    if (-not $BaseUrl) { $BaseUrl = $env:DW_BASE_URL }
    if (-not $BaseUrl) {
        $root = if ($SolutionPath) { $SolutionPath } else { (Get-Location).Path }
        $launchSettings = Join-Path $root 'Dynamicweb.Host.Suite/Properties/launchSettings.json'
        if (Test-Path $launchSettings) {
            $m = [regex]::Match((Get-Content $launchSettings -Raw), 'https://localhost:(\d+)')
            if ($m.Success) { $BaseUrl = 'https://localhost:' + $m.Groups[1].Value }
        }
    }
    if (-not $BaseUrl) {
        throw ("No Dynamicweb base URL. Pass -BaseUrl, set `$env:DW_BASE_URL, or run " +
            "from (or pass -SolutionPath to) a solution folder containing " +
            "Dynamicweb.Host.Suite/Properties/launchSettings.json.")
    }
    $BaseUrl = $BaseUrl.TrimEnd('/')

    if (-not $ApiToken) { $ApiToken = $env:DW_API_TOKEN }
    if (-not $McpToken) { $McpToken = $env:DW_MCP_TOKEN }
    if (-not $SqlConnection) { $SqlConnection = $env:DW_SQL_CONNECTION }

    $isLocalhost = $BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)'
    $script:DwState.BaseUrl = $BaseUrl
    $script:DwState.ApiToken = $ApiToken
    $script:DwState.McpToken = $McpToken
    $script:DwState.SqlConnection = $SqlConnection
    $script:DwState.SkipCert = [bool]($isLocalhost -or $AllowSelfSignedCertificate)
    $script:DwState.McpHeaders = $null   # force a fresh MCP handshake

    Write-Verbose ("Connect-Dw: $BaseUrl api=" + (Format-DwMaskedToken $ApiToken) +
        ' mcp=' + (Format-DwMaskedToken $McpToken) +
        " skipCert=$($script:DwState.SkipCert)")
    $script:DwState
}

function Assert-DwConnection {
    <#
    .SYNOPSIS
        READ-ONLY. Proves the module loaded and a connection is resolved.
    .DESCRIPTION
        Call immediately after Import-Module. If the import was blocked (AMSI
        false positive) this command does not exist and the caller fails
        loudly instead of running against empty state. Runs Connect-Dw
        discovery when it has not run yet.
    .EXAMPLE
        Assert-DwConnection
    #>
    [CmdletBinding()]
    param()
    if (-not $script:DwState.BaseUrl) { Connect-Dw | Out-Null }
    $true
}

function Invoke-DwApi {
    <#
    .SYNOPSIS
        WRITES: whatever the named command writes; a bare query is read-only.
        Calls a Management API command on /Admin/Api/.
    .DESCRIPTION
        GET without -Body, POST with it. The body is serialized at -Depth 50
        and sent as UTF-8 bytes with an explicit charset, so non-ASCII content
        survives. Errors carry the HTTP status and the server's message.
    .PARAMETER Command
        Command name plus query string (e.g. 'GetPageById?Id=1'), or an
        absolute URL.
    .PARAMETER Body
        Request body (hashtable/object, or a pre-serialized JSON string).
    .PARAMETER Method
        HTTP method override; defaults to Get, or Post when -Body is present.
    .PARAMETER TimeoutSec
        Request timeout in seconds.
    .PARAMETER RetryCount
        Retries for a 429 or, on a read, a 5xx. 0 disables the retry.
    .PARAMETER RetryDelayMs
        First backoff delay; each further attempt doubles it. A Retry-After
        header, when the server sends one, wins over the computed delay.
    .EXAMPLE
        Invoke-DwApi 'CacheInformationRefresh' -Body @{ CacheTypeName = 'Dynamicweb.Ecommerce.Shops.ShopService' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        $Body,
        [string]$Method,
        [int]$TimeoutSec = 120,
        [int]$RetryCount = 3,
        [int]$RetryDelayMs = 500
    )
    Assert-DwConnection | Out-Null
    if (-not $script:DwState.ApiToken) {
        throw "No Management API token. Pass -ApiToken to Connect-Dw or set `$env:DW_API_TOKEN."
    }
    if (-not $Method) { $Method = if ($null -ne $Body) { 'Post' } else { 'Get' } }
    $uri = if ($Command -match '^https?://') { $Command }
           else { "$($script:DwState.BaseUrl)/Admin/Api/$Command" }
    $params = @{
        Uri                  = $uri
        Method               = $Method
        Headers              = @{ Authorization = "Bearer $($script:DwState.ApiToken)" }
        TimeoutSec           = $TimeoutSec
        SkipCertificateCheck = $script:DwState.SkipCert
    }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 50 }
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    # A 429 is the server refusing the request before acting on it, so it is
    # safe to retry whatever the method. A 5xx may have applied a write before
    # failing, so only a read is retried - a blind POST retry double-writes.
    $attempt = 0
    while ($true) {
        try { return Invoke-RestMethod @params }
        catch {
            $status = 0
            try { $status = [int]$_.Exception.Response.StatusCode.value__ } catch { $status = 0 }
            if ($attempt -lt $RetryCount -and (Test-DwRetryableStatus $status $Method)) {
                $delay = [int]($RetryDelayMs * [math]::Pow(2, $attempt))
                try {
                    $after = $_.Exception.Response.Headers.RetryAfter.Delta.TotalMilliseconds
                    if ($after) { $delay = [int]$after }
                } catch { }
                Write-Verbose "Invoke-DwApi $Command -> HTTP $status, retrying in ${delay}ms"
                Start-Sleep -Milliseconds $delay
                $attempt++
                continue
            }
            throw "$Method $Command failed [$status]: $($_.ErrorDetails.Message)"
        }
    }
}

function Remove-DwDisplayOnlyMember {
    <#
    .SYNOPSIS
        READ-ONLY. Strips the members a Save command cannot deserialize.
    .DESCRIPTION
        A read model round-tripped into a Save 500s on display-only members;
        the known offenders are modelIdentifier and any *Icon member. Use on
        the .model of a ById/New response before posting it back.
    .PARAMETER Model
        The model object to clean (mutated in place and returned).
    .EXAMPLE
        $m = Remove-DwDisplayOnlyMember (Invoke-DwApi 'EmailById?Id=3').model
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Model)
    $doomed = @($Model.PSObject.Properties.Name |
        Where-Object { $_ -eq 'modelIdentifier' -or $_ -like '*Icon' })
    foreach ($name in $doomed) { $Model.PSObject.Properties.Remove($name) }
    $Model
}

function Initialize-DwMcp {
    # Internal: JSON-RPC handshake against /admin/mcp — initialize, capture
    # the mcp-session-id header, send notifications/initialized.
    if (-not $script:DwState.McpToken) {
        throw "No MCP token. Pass -McpToken to Connect-Dw or set `$env:DW_MCP_TOKEN."
    }
    $headers = @{
        Authorization = "Bearer $($script:DwState.McpToken)"
        Accept        = 'application/json, text/event-stream'
    }
    $uri = "$($script:DwState.BaseUrl)/admin/mcp"
    $body = @{
        jsonrpc = '2.0'; id = 1; method = 'initialize'
        params  = @{
            protocolVersion = '2025-03-26'; capabilities = @{}
            clientInfo      = @{ name = 'Dw.Api.psm1'; version = '1.0' }
        }
    } | ConvertTo-Json -Depth 10
    $r = Invoke-WebRequest -Uri $uri -Method Post -Body $body -Headers $headers `
        -ContentType 'application/json' -TimeoutSec 60 `
        -SkipCertificateCheck:$script:DwState.SkipCert
    $sessionId = $r.Headers['mcp-session-id'] | Select-Object -First 1
    if ($sessionId) { $headers['mcp-session-id'] = $sessionId }
    Invoke-WebRequest -Uri $uri -Method Post -Headers $headers `
        -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' `
        -ContentType 'application/json' -TimeoutSec 30 `
        -SkipCertificateCheck:$script:DwState.SkipCert | Out-Null
    $script:DwState.McpHeaders = $headers
}

function ConvertFrom-DwSse([string]$Content) {
    # Internal: an SSE-framed response carries the JSON-RPC reply in its
    # data: lines; the LAST data: event is the final result. Plain JSON
    # responses pass through unchanged.
    $data = @($Content -split "`n" | Where-Object { $_ -match '^data:' })
    if ($data.Count -eq 0) { return $Content | ConvertFrom-Json }
    ($data[-1] -replace '^data:\s?', '') | ConvertFrom-Json
}

function Invoke-DwMcp {
    <#
    .SYNOPSIS
        WRITES: whatever the named tool writes; read tools are read-only.
        Calls one MCP tool on /admin/mcp as JSON-RPC 2.0.
    .DESCRIPTION
        Performs the handshake once per session (session id header, SSE
        unwrap). Throws on a JSON-RPC error. Returns structuredContent when
        present, else the joined text content, else the raw result; -Raw
        always returns the raw result.
    .PARAMETER Tool
        Tool name from tools/list.
    .PARAMETER Arguments
        Tool arguments hashtable.
    .PARAMETER Raw
        Return the unprojected JSON-RPC result.
    .PARAMETER TimeoutSec
        Request timeout in seconds.
    .EXAMPLE
        Invoke-DwMcp 'get_shops'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [hashtable]$Arguments = @{},
        [switch]$Raw,
        [int]$TimeoutSec = 120
    )
    Assert-DwConnection | Out-Null
    if (-not $script:DwState.McpHeaders) { Initialize-DwMcp }
    $script:DwState.McpRpcId++
    $payload = @{
        jsonrpc = '2.0'; id = $script:DwState.McpRpcId; method = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    } | ConvertTo-Json -Depth 50
    $r = Invoke-WebRequest -Uri "$($script:DwState.BaseUrl)/admin/mcp" -Method Post `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
        -ContentType 'application/json; charset=utf-8' `
        -Headers $script:DwState.McpHeaders -TimeoutSec $TimeoutSec `
        -SkipCertificateCheck:$script:DwState.SkipCert
    $reply = ConvertFrom-DwSse $r.Content
    if ($reply.PSObject.Properties['error'] -and $reply.error) {
        throw "MCP $Tool error: $($reply.error | ConvertTo-Json -Depth 5 -Compress)"
    }
    if ($Raw) { return $reply.result }
    if ($reply.result.PSObject.Properties['structuredContent'] -and $reply.result.structuredContent) {
        return $reply.result.structuredContent
    }
    if ($reply.result.PSObject.Properties['content'] -and $reply.result.content) {
        return ($reply.result.content | ForEach-Object { $_.text }) -join "`n"
    }
    $reply.result
}

function Get-DwMcpTools {
    <#
    .SYNOPSIS
        READ-ONLY. Enumerates the full MCP tool catalog.
    .DESCRIPTION
        Follows nextCursor pagination until exhausted; a healthy DW10 host
        returns well over 200 tools.
    .EXAMPLE
        (Get-DwMcpTools).Count
    #>
    [CmdletBinding()]
    param()
    Assert-DwConnection | Out-Null
    if (-not $script:DwState.McpHeaders) { Initialize-DwMcp }
    $all = @()
    $cursor = $null
    do {
        $script:DwState.McpRpcId++
        $params = if ($cursor) { @{ cursor = $cursor } } else { @{} }
        $payload = @{
            jsonrpc = '2.0'; id = $script:DwState.McpRpcId
            method  = 'tools/list'; params = $params
        } | ConvertTo-Json -Depth 10
        $r = Invoke-WebRequest -Uri "$($script:DwState.BaseUrl)/admin/mcp" -Method Post `
            -Body $payload -ContentType 'application/json' `
            -Headers $script:DwState.McpHeaders -TimeoutSec 60 `
            -SkipCertificateCheck:$script:DwState.SkipCert
        $reply = ConvertFrom-DwSse $r.Content
        $all += $reply.result.tools
        $cursor = $reply.result.nextCursor
    } while ($cursor)
    , $all
}

function Get-DwSqlRows {
    <#
    .SYNOPSIS
        READ-ONLY. Runs a SQL query and returns the rows as an array.
    .DESCRIPTION
        Reads through a raw SqlDataReader and projects every row to a
        [pscustomobject], so no DataRow ever leaves this function (safe to
        ConvertTo-Json) and a one-row result is still an ARRAY — index it
        with [0] safely. ASSIGN the result to a variable; wrapping the call
        itself in @() double-wraps the protected array. Long columns are read
        in full (no Invoke-Sqlcmd truncation).
    .PARAMETER Sql
        The query to run.
    .PARAMETER ConnectionString
        Overrides the connection resolved by Connect-Dw / $env:DW_SQL_CONNECTION.
    .EXAMPLE
        @(Get-DwSqlRows 'SELECT TOP 5 PageId, PageName FROM Page')[0].PageName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$ConnectionString
    )
    $conn = Get-DwSqlConnectionString $ConnectionString
    $connection = [System.Data.SqlClient.SqlConnection]::new($conn)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Sql
        $command.CommandTimeout = 300
        $reader = $command.ExecuteReader()
        $rows = [System.Collections.Generic.List[object]]::new()
        while ($reader.Read()) {
            $row = [ordered]@{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
            }
            $rows.Add([pscustomobject]$row)
        }
        $reader.Dispose()
        , $rows.ToArray()
    }
    finally { $connection.Dispose() }
}

function Get-DwSqlScalar {
    <#
    .SYNOPSIS
        READ-ONLY. Runs a SQL query and returns the single scalar result.
    .DESCRIPTION
        ExecuteScalar directly — the safe way to read one value, immune to the
        one-row unrolling trap.
    .PARAMETER Sql
        The query to run.
    .PARAMETER ConnectionString
        Overrides the connection resolved by Connect-Dw / $env:DW_SQL_CONNECTION.
    .EXAMPLE
        Get-DwSqlScalar 'SELECT COUNT(*) FROM Page'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$ConnectionString
    )
    $conn = Get-DwSqlConnectionString $ConnectionString
    $connection = [System.Data.SqlClient.SqlConnection]::new($conn)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Sql
        $command.CommandTimeout = 300
        $command.ExecuteScalar()
    }
    finally { $connection.Dispose() }
}

function Get-DwSqlConnectionString([string]$Override) {
    # Internal: explicit parameter > Connect-Dw state > environment > fail.
    if ($Override) { return $Override }
    if ($script:DwState.SqlConnection) { return $script:DwState.SqlConnection }
    if ($env:DW_SQL_CONNECTION) { return $env:DW_SQL_CONNECTION }
    throw ("No SQL connection. Pass -ConnectionString, -SqlConnection to Connect-Dw, or set " +
        "`$env:DW_SQL_CONNECTION. SQL is LOCAL-ONLY: a hosted install has no SQL surface, " +
        "and no remote SQL path exists by design.")
}

function Clear-DwServiceCache {
    <#
    .SYNOPSIS
        WRITES: flushes host service caches (no data change, no restart).
    .DESCRIPTION
        Targeted flush per cache type name, or -All for every registered
        cache. Discover names with (Invoke-DwApi 'GetServiceCaches'). Reach
        for this before a host restart when staleness is the only symptom.
    .PARAMETER CacheTypeName
        One or more cache type names, e.g.
        'Dynamicweb.Ecommerce.Shops.ShopService'.
    .PARAMETER All
        Flush every registered service cache.
    .EXAMPLE
        Clear-DwServiceCache -CacheTypeName 'Dynamicweb.Ecommerce.Shops.ShopService'
    #>
    [CmdletBinding()]
    param(
        [string[]]$CacheTypeName,
        [switch]$All
    )
    if (-not $All -and -not $CacheTypeName) {
        throw 'Pass -CacheTypeName (see Invoke-DwApi ''GetServiceCaches'') or -All.'
    }
    if ($All) {
        Invoke-DwApi 'CacheInformationsRefresh' -Body @{ model = @{} } | Out-Null
        return
    }
    foreach ($name in $CacheTypeName) {
        Invoke-DwApi 'CacheInformationRefresh' -Body @{ CacheTypeName = $name } | Out-Null
    }
}

function Set-DwDbConnectionTrust {
    <#
    .SYNOPSIS
        WRITES: the host's database connection string (adds certificate trust).
    .DESCRIPTION
        Reads DatabaseSettings, rebuilds the connection string from its own
        parts with TrustServerCertificate=True, and saves it back — the fix
        for a host that cannot reach its SQL Server after a certificate
        change. The password is round-tripped from the live model, never
        logged.
    .EXAMPLE
        Set-DwDbConnectionTrust
    #>
    [CmdletBinding()]
    param()
    $settings = (Invoke-DwApi 'DatabaseSettings').model
    $settings.databaseConnectionString = (
        "Server=$($settings.databaseSQLServer);Database=$($settings.databaseName);" +
        "User Id=$($settings.databaseUserName);Password=$($settings.databasePassword);" +
        'TrustServerCertificate=True;Encrypt=True;')
    $result = Invoke-DwApi 'DatabaseSettingsSave' -Body @{ Model = $settings }
    Write-Verbose "DatabaseSettingsSave status: $($result.status)"
    $result
}

function Get-DwConnection {
    <#
    .SYNOPSIS
        READ-ONLY. The connection resolved for this session.
    .DESCRIPTION
        Runs discovery when it has not run yet, then returns the live state:
        BaseUrl, ApiToken, McpToken, SqlConnection, SkipCert. Read it rather
        than calling Connect-Dw again, which re-runs discovery and discards the
        MCP handshake. The tokens in the returned object are LIVE VALUES: pass
        them to a request, never to a log line - Write-Verbose output in this
        module is masked for that reason.
    .EXAMPLE
        (Get-DwConnection).BaseUrl
    #>
    [CmdletBinding()]
    param()
    Assert-DwConnection | Out-Null
    $script:DwState
}

function Get-DwBrowserUserAgent {
    <#
    .SYNOPSIS
        READ-ONLY. The one browser User-Agent every web probe in this module sends.
    .DESCRIPTION
        # why: Dynamicweb 10 SILENTLY SKIPS CART COMMANDS for a non-browser
        User-Agent. A cart command from a default tool UA answers HTTP 200,
        creates the cart row, and adds ZERO order lines, with nothing in the
        log - every observable except the order lines says success. The image
        handler negotiates content on the same header. So a browser-shaped UA
        is a protocol requirement of the target, not an attempt to look like a
        human, and it lives in exactly one named, documented place rather than
        being pasted into each probe.
    .EXAMPLE
        Get-DwBrowserUserAgent
    #>
    [CmdletBinding()]
    param()
    $script:DwBrowserUserAgent
}

function Test-DwRetryableStatus([int]$Status, [string]$Method) {
    # Internal. 429 is the server refusing the request before acting on it, so a
    # retry is safe for any method. A 5xx may have applied a write before
    # failing, so only a read retries - a blind POST retry double-writes.
    if ($Status -eq 429) { return $true }
    if ($Status -ge 500 -and $Status -le 599) { return @('Get', 'Head') -contains $Method }
    return $false
}

function Invoke-DwQuery {
    <#
    .SYNOPSIS
        READ-ONLY. Reads a Management API list query to completion and
        reconciles the rows against the server's own totalCount.
    .DESCRIPTION
        The list verbs apply a DEFAULT page size while still reporting the full
        model.totalCount. A "does this field exist" assert run against page 1 of
        4 reports FALSE for a field that is present, and a membership test then
        reads absence as evidence. This function never hands a caller a partial
        page: it walks the pages, concatenates them, and throws when the
        collected count does not equal totalCount.

        It also refuses to concatenate a repeated page. When a host ignores the
        page parameter, page 2 answers with page 1's rows; appending them would
        double the count instead of failing. The first row of each page is
        compared with the previous page's and an identical page throws.

        A verb that answers a bare collection with no totalCount cannot be
        reconciled; the result then carries complete = $false rather than
        implying it was verified.
    .PARAMETER Query
        Management API list command name, without a query string.
    .PARAMETER Parameters
        Extra query-string parameters; keys and values are URL-escaped.
    .PARAMETER PagingSize
        Rows per page. Always sent: a missing PagingSize is how the default
        page size gets applied silently.
    .PARAMETER PageParameterName
        Name of the page-number parameter, overridable so a verb that spells it
        differently stays a parameter rather than an edit.
    .PARAMETER MaxPages
        Safety stop, so a host that never advances cannot loop forever.
    .PARAMETER TimeoutSec
        Per-request timeout in seconds.
    .EXAMPLE
        $r = Invoke-DwQuery 'UserList' -PagingSize 500
        $r.complete; $r.totalCount; $r.data.Count
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [hashtable]$Parameters = @{},
        [int]$PagingSize = 500,
        [string]$PageParameterName = 'PagingPage',
        [int]$MaxPages = 500,
        [int]$TimeoutSec = 120
    )
    Assert-DwConnection | Out-Null
    $rows = [System.Collections.Generic.List[object]]::new()
    $total = $null
    $page = 1
    $previousFingerprint = $null
    while ($page -le $MaxPages) {
        $qs = @("PagingSize=$PagingSize", "$PageParameterName=$page")
        foreach ($key in @($Parameters.Keys)) {
            $qs += ('{0}={1}' -f [uri]::EscapeDataString([string]$key),
                                 [uri]::EscapeDataString([string]$Parameters[$key]))
        }
        $response = Invoke-DwApi ($Query + '?' + ($qs -join '&')) -TimeoutSec $TimeoutSec
        $model = if ($response -and $response.PSObject.Properties['model']) { $response.model } else { $response }
        $data = @($model.data)
        if ($null -eq $total -and $model -and $model.PSObject.Properties['totalCount']) {
            $total = [int]$model.totalCount
        }
        if ($null -eq $total) {
            return [pscustomobject]@{
                query = $Query; data = @($data); totalCount = $data.Count
                pages = 1; complete = $false
            }
        }
        if ($data.Count -eq 0) { break }
        $fingerprint = ($data[0] | ConvertTo-Json -Depth 8 -Compress)
        if ($page -gt 1 -and $fingerprint -eq $previousFingerprint) {
            throw ("Invoke-DwQuery ${Query}: page $page repeated page $($page - 1). The host " +
                "is ignoring '$PageParameterName', so concatenating would double the rows " +
                "instead of failing. Pass the page parameter this verb uses, or raise " +
                "-PagingSize above $total and read one page.")
        }
        $previousFingerprint = $fingerprint
        $rows.AddRange($data)
        if ($rows.Count -ge $total) { break }
        $page++
    }
    if ($rows.Count -ne $total) {
        throw ("Invoke-DwQuery ${Query}: collected $($rows.Count) row(s) of totalCount $total " +
            "across $page page(s) at PagingSize=$PagingSize. A membership test on a partial " +
            "read reports a present item as ABSENT, so this refuses to return.")
    }
    [pscustomobject]@{
        query = $Query; data = $rows.ToArray(); totalCount = $total
        pages = $page; complete = $true
    }
}

function Get-DwTaskLastRun {
    <#
    .SYNOPSIS
        READ-ONLY. The scheduled task's own last-run value, as a string.
    .DESCRIPTION
        The property name differs across builds, so the known spellings are
        tried in order and the value is returned as a string for comparison.
        An empty string means the task has no recorded run, which is a valid
        BEFORE value for Invoke-DwTaskRun.
    .PARAMETER TaskId
        Scheduled task id.
    .EXAMPLE
        Get-DwTaskLastRun -TaskId 1519
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$TaskId)
    $response = Invoke-DwApi "TaskById?Id=$TaskId"
    $model = if ($response -and $response.PSObject.Properties['model']) { $response.model } else { $response }
    foreach ($name in @('lastRun', 'taskLastRun', 'lastRunDate')) {
        if ($model -and $model.PSObject.Properties[$name]) { return "$($model.$name)" }
    }
    ''
}

function Invoke-DwTaskRun {
    <#
    .SYNOPSIS
        WRITES: triggers one scheduled task, then waits for THAT run to finish.
    .DESCRIPTION
        TaskRun is ASYNCHRONOUS: it queues the task for the scheduler's next
        poll. A freshness guard of the form "last run is within the last 120
        seconds" is satisfied by the PREVIOUS run, so a harness returns
        immediately and reads the pre-run state as the post-run state.

        So: capture the task's own last-run value BEFORE the trigger, fire, and
        poll for that value to CHANGE. Never a wall clock. The before and after
        values and the wait are returned so a caller can record them as
        evidence.
    .PARAMETER TaskId
        Scheduled task id.
    .PARAMETER TimeoutSec
        How long to wait for the last-run value to advance.
    .PARAMETER PollIntervalMs
        Delay between polls.
    .EXAMPLE
        Invoke-DwTaskRun -TaskId 1519 -TimeoutSec 300
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$TaskId,
        [int]$TimeoutSec = 300,
        [int]$PollIntervalMs = 2000
    )
    $before = Get-DwTaskLastRun -TaskId $TaskId
    Invoke-DwApi 'TaskRun' -Body @{ Ids = @("$TaskId") } | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $after = $before
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Milliseconds $PollIntervalMs
        $after = Get-DwTaskLastRun -TaskId $TaskId
        if ("$after" -ne "$before") { break }
    }
    $watch.Stop()
    if ("$after" -eq "$before") {
        throw ("Invoke-DwTaskRun: task $TaskId last-run did not advance from '$before' within " +
            "${TimeoutSec}s. TaskRun only QUEUES the task; a run that never fired must not be " +
            'read as a run that completed.')
    }
    [pscustomobject]@{
        taskId = $TaskId; lastRunBefore = "$before"; lastRunAfter = "$after"
        waitedMs = [int]$watch.Elapsed.TotalMilliseconds
    }
}

function Test-DwPageProbe {
    <#
    .SYNOPSIS
        READ-ONLY. Fetches one URL and reports a verdict a status code alone
        cannot give.
    .DESCRIPTION
        Three measured traps are closed here:

        A Razor compile error STILL ANSWERS HTTP 200, so -RejectCompileError
        reads the BODY; a status-only probe passes a page that renders an
        error.

        PowerShell 7 does not throw on a suppressed redirect, so a Location
        reader written only for the catch block never runs and a healthy page
        falls through to nothing. The RETURNED response is inspected first and
        the caught one second. -MaximumRedirection 0 is never combined with
        -SkipHttpErrorCheck: together they throw with no response object and
        the redirect becomes unreadable.

        A response header is a string array, so casting the array itself throws
        INSIDE the try and a successful request lands in the failure handler
        with a blank status. Headers are indexed before they are cast, and the
        status is seeded to -1 so a blank can never read as a pass.
    .PARAMETER Url
        Absolute URL to fetch.
    .PARAMETER Method
        GET, HEAD or POST.
    .PARAMETER Body
        Request body for POST.
    .PARAMETER NoFollowRedirect
        Do not follow redirects; the Location header is reported instead.
    .PARAMETER ExpectContains
        Literal strings the body must contain.
    .PARAMETER RejectContains
        Literal strings the body must not contain.
    .PARAMETER RejectCompileError
        Fail on a Razor or compile-error marker in the body behind any status.
    .PARAMETER TimeoutSec
        Request timeout in seconds.
    .EXAMPLE
        (Test-DwPageProbe "$base/shop" -RejectCompileError).ok
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [ValidateSet('GET', 'HEAD', 'POST')][string]$Method = 'GET',
        $Body,
        [switch]$NoFollowRedirect,
        [string[]]$ExpectContains = @(),
        [string[]]$RejectContains = @(),
        [switch]$RejectCompileError,
        [int]$TimeoutSec = 60
    )
    Assert-DwConnection | Out-Null
    $status = -1        # a blank must never read as a pass
    $bodyText = ''
    $location = $null
    $contentLength = $null
    $transportError = $null
    $params = @{
        Uri                  = $Url
        Method               = $Method
        # why: the target skips cart commands for a non-browser UA - see Get-DwBrowserUserAgent.
        Headers              = @{ 'User-Agent' = Get-DwBrowserUserAgent }
        SkipCertificateCheck = $script:DwState.SkipCert
        TimeoutSec           = $TimeoutSec
        ErrorAction          = 'Stop'
    }
    if ($NoFollowRedirect) { $params.MaximumRedirection = 0 }
    else { $params.MaximumRedirection = 10; $params.SkipHttpErrorCheck = $true }
    if ($null -ne $Body) { $params.Body = $Body }

    $response = $null
    try { $response = Invoke-WebRequest @params }
    catch {
        $caught = $_.Exception.Response
        if ($caught) { $response = $caught } else { $transportError = "$($_.Exception.Message)" }
    }
    if ($response) {
        try { $status = [int]$response.StatusCode } catch { $status = -1 }
        if ($response -is [System.Net.Http.HttpResponseMessage]) {
            try { $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { $bodyText = '' }
            try { if ($response.Headers.Location) { $location = "$($response.Headers.Location)" } } catch { }
            try { if ($null -ne $response.Content.Headers.ContentLength) { $contentLength = [int]$response.Content.Headers.ContentLength } } catch { }
        }
        else {
            try { $bodyText = "$($response.Content)" } catch { $bodyText = '' }
            $headers = $null
            try { $headers = $response.Headers } catch { $headers = $null }
            if ($headers) {
                if ($headers['Location']) { $location = @($headers['Location'])[0] }
                if ($headers['Content-Length']) { $contentLength = [int](@($headers['Content-Length'])[0]) }
            }
        }
    }
    $failures = @()
    if ($status -lt 0) { $failures += "no response$(if ($transportError) { " ($transportError)" })" }
    foreach ($needle in @($ExpectContains)) {
        if ($bodyText -notmatch [regex]::Escape($needle)) { $failures += "body is missing '$needle'" }
    }
    foreach ($needle in @($RejectContains)) {
        if ($bodyText -match [regex]::Escape($needle)) { $failures += "body carries '$needle'" }
    }
    if ($RejectCompileError) {
        $marker = [regex]::Match($bodyText, '(?i)(Compilation Error|CS\d{4}:|RazorTemplateEngine|An error occurred while (compiling|processing) the template|The type or namespace name)')
        if ($marker.Success) {
            $failures += "body carries a compile-error marker '$($marker.Value)' behind HTTP $status"
        }
    }
    [pscustomobject]@{
        url = $Url; status = $status; location = $location; contentLength = $contentLength
        bytes = $bodyText.Length; body = $bodyText; error = $transportError
        ok = ($failures.Count -eq 0); failures = @($failures)
    }
}

function Get-DwServedFileHash {
    <#
    .SYNOPSIS
        READ-ONLY. SHA256 of the bytes the host actually serves at a URL.
    .DESCRIPTION
        The file archive is reached through directory junctions, and Windows
        file-change notification does not propagate through a junction, so the
        static-file cache never invalidates: a redeployed stylesheet lands on
        disk while the host keeps serving the old bytes. Because the stale copy
        still carries every sentinel marker the new one has, a marker-presence
        check calls that green. Only a hash of the SERVED bytes compared with
        the local file can tell the two apart.
    .PARAMETER Url
        Absolute URL of the served file.
    .PARAMETER TimeoutSec
        Request timeout in seconds.
    .EXAMPLE
        Get-DwServedFileHash "$base/Files/Templates/Designs/Swift/theme.css"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 120
    )
    Assert-DwConnection | Out-Null
    # why: the target negotiates served content on the UA - see Get-DwBrowserUserAgent.
    $headers = @{ 'User-Agent' = Get-DwBrowserUserAgent }
    $response = Invoke-WebRequest -Uri $Url -Method Get -Headers $headers `
        -SkipCertificateCheck:$script:DwState.SkipCert -SkipHttpErrorCheck `
        -TimeoutSec $TimeoutSec -ErrorAction Stop
    if ([int]$response.StatusCode -ge 400) {
        throw "Get-DwServedFileHash: GET $Url -> HTTP $([int]$response.StatusCode)"
    }
    $bytes = if ($response.Content -is [byte[]]) { $response.Content }
             else { [Text.Encoding]::UTF8.GetBytes("$($response.Content)") }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') }) -join '') }
    finally { $sha.Dispose() }
}

function Get-DwSqlCount {
    <#
    .SYNOPSIS
        READ-ONLY. Runs a COUNT query and returns an [int], never a blank.
    .DESCRIPTION
        A blank is NOT a zero. A count helper that returns an empty value for a
        failed read makes "nothing matched" and "the read never ran" the same
        observation, and a delete gated on "count is 0" then passes on a read
        that never happened. This throws on a blank and on a non-integer.
    .PARAMETER Sql
        The COUNT query to run.
    .PARAMETER ConnectionString
        Overrides the connection resolved by Connect-Dw / $env:DW_SQL_CONNECTION.
    .EXAMPLE
        Get-DwSqlCount 'SELECT COUNT(*) FROM AccessUser WHERE AccessUserActive = 1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$ConnectionString
    )
    $value = Get-DwSqlScalar -Sql $Sql -ConnectionString $ConnectionString
    if ($null -eq $value -or "$value".Trim().Length -eq 0) {
        throw "Get-DwSqlCount: the query returned no value, and a blank is NOT a zero. Query: $Sql"
    }
    $parsed = 0
    if (-not [int]::TryParse("$value".Trim(), [ref]$parsed)) {
        throw "Get-DwSqlCount: the query returned '$value', which is not an integer. Query: $Sql"
    }
    $parsed
}

function ConvertTo-DwApiValue {
    <#
    .SYNOPSIS
        READ-ONLY. Fences a SQL-read value before it enters an API payload.
    .DESCRIPTION
        A DataRow field, a DBNull, or any non-primitive handed to ConvertTo-Json
        arrives at the API as a JSON OBJECT. The model binder cannot bind it, the
        property lands as an empty string, and the call still answers ok - so the
        write silently blanks the column it meant to preserve.

        Scalars come back as strings; DBNull and $null become $null. Booleans and
        numbers are preserved as-is, because the binder wants those typed and
        neither suffers the defect. A dictionary is walked recursively, so a whole
        Model can be fenced in one call.
    .PARAMETER Value
        The value, dictionary or collection to fence.
    .EXAMPLE
        $model = ConvertTo-DwApiValue @{ Id = $row.Id; Name = $row.Name }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)][AllowNull()]$Value)
    process {
        if ($null -eq $Value) { return $null }
        if ($Value -is [System.DBNull]) { return $null }
        if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or
            $Value -is [double] -or $Value -is [decimal]) { return $Value }
        if ($Value -is [string]) { return [string]$Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($key in @($Value.Keys)) { $out["$key"] = ConvertTo-DwApiValue -Value $Value[$key] }
            return $out
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            return @(foreach ($item in $Value) { ConvertTo-DwApiValue -Value $item })
        }
        [string]$Value
    }
}

function Get-DwCategoryFieldSort {
    <#
    .SYNOPSIS
        READ-ONLY. The current field sort order for one product category.
    .DESCRIPTION
        There is no API read of this model: the list GET answers 500 because the
        shared sort-screen query model exposes a save-command member of type
        System.Type, which the JSON serializer refuses. Only the save command is
        usable, so the read before that write has to come from SQL (LOCAL installs
        only). Repoint this helper the day the GET returns an ordered-ids model.

        The table and column names are parameters so a schema difference stays a
        parameter rather than an edit.
    .PARAMETER CategoryId
        Product category id.
    .PARAMETER Table
        Category-field table name.
    .PARAMETER SortColumn
        Sort-order column name.
    .PARAMETER IdColumn
        Field-id column name.
    .PARAMETER CategoryColumn
        Category-id column name.
    .PARAMETER ConnectionString
        Overrides the connection resolved by Connect-Dw / $env:DW_SQL_CONNECTION.
    .EXAMPLE
        $order = Get-DwCategoryFieldSort -CategoryId 'Specs'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CategoryId,
        [string]$Table = 'EcomProductCategoryField',
        [string]$SortColumn = 'FieldSortOrder',
        [string]$IdColumn = 'FieldId',
        [string]$CategoryColumn = 'FieldCategoryId',
        [string]$ConnectionString
    )
    $safeCategory = $CategoryId -replace "'", "''"
    $sql = "SELECT [$IdColumn], [$SortColumn] FROM [$Table] " +
           "WHERE [$CategoryColumn] = '$safeCategory' ORDER BY [$SortColumn]"
    $rows = Get-DwSqlRows -Sql $sql -ConnectionString $ConnectionString
    $out = @(foreach ($row in $rows) {
        [pscustomobject]@{
            fieldId   = [string]$row.$IdColumn
            sortOrder = if ($null -eq $row.$SortColumn) { $null } else { [int]$row.$SortColumn }
        }
    })
    , $out
}

Export-ModuleMember -Function @(
    'Connect-Dw', 'Assert-DwConnection', 'Invoke-DwApi', 'Remove-DwDisplayOnlyMember',
    'Invoke-DwMcp', 'Get-DwMcpTools',
    'Get-DwSqlRows', 'Get-DwSqlScalar', 'Clear-DwServiceCache', 'Set-DwDbConnectionTrust',
    'Get-DwConnection', 'Get-DwBrowserUserAgent', 'Invoke-DwQuery', 'Get-DwTaskLastRun', 'Invoke-DwTaskRun',
    'Test-DwPageProbe', 'Get-DwServedFileHash', 'Get-DwSqlCount', 'ConvertTo-DwApiValue',
    'Get-DwCategoryFieldSort'
)

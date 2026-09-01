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
    .EXAMPLE
        Invoke-DwApi 'CacheInformationRefresh' -Body @{ CacheTypeName = 'Dynamicweb.Ecommerce.Shops.ShopService' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        $Body,
        [string]$Method,
        [int]$TimeoutSec = 120
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
    try { Invoke-RestMethod @params }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        throw "$Method $Command failed [$status]: $($_.ErrorDetails.Message)"
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

Export-ModuleMember -Function @(
    'Connect-Dw', 'Assert-DwConnection', 'Invoke-DwApi', 'Remove-DwDisplayOnlyMember',
    'Invoke-DwMcp', 'Get-DwMcpTools',
    'Get-DwSqlRows', 'Get-DwSqlScalar', 'Clear-DwServiceCache', 'Set-DwDbConnectionTrust'
)

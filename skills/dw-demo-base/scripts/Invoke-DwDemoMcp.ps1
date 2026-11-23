<#
.SYNOPSIS
    WRITES: whatever the called tool writes; -List and -Schema are read-only.
    One command-line entry to a demo site's MCP endpoint, for a session whose
    MCP client never loaded that site's server.

.DESCRIPTION
    A site that came up during this session has its MCP server registered in
    .mcp.json after the session started, so its tools are not loaded in the
    session. Call the same endpoint with this script instead of writing a
    client. It is a thin entry over Connect-Dw, Get-DwMcpTools and Invoke-DwMcp
    in ../../dw-data-access/scripts/Dw.Api.psm1, which own the transport (the
    handshake, the session id, the SSE unwrap, tools/list paging). Uploads and
    the Management API stay with that module and Dw.Api.Write.psm1.

    Owning reference: ../references/mcp-setup.md, "Autonomous/headless
    fallback". The guarded-writes discipline applies to a -Call exactly as it
    does to a tool called through the client.

    Connection, in this order:
      1. -BaseUrl, with the token read from the environment variable named by
         -TokenEnv (default DW_MCP_TOKEN).
      2. .mcp.json in -SolutionDir (default: the current directory). A server
         whose name starts with dw-demo- wins, else the first with a url;
         -Server picks one by name. The base URL is the server url without
         /admin/mcp; the token is its Authorization header without "Bearer ".
         A header value of ${NAME} is read from that environment variable.

    The token is never printed, never part of an error message and never put
    on a process argument list.

    Modes (exactly one):
      -List [-Filter <regex>]  tool names with the first sentence of their
                               description; the regex matches name or text.
      -Schema <tool>           the tool's input schema as JSON.
      -Call <tool>             -Arguments <json> or -ArgumentsFile <path>;
                               prints the tool's result as JSON.

    Exit 0 = done, 1 = the tool answered with an error (its own message is on
    stderr), 2 = usage or connection error.

.PARAMETER BaseUrl
    Site base URL. Without it the connection comes from .mcp.json.

.PARAMETER TokenEnv
    Name of the environment variable holding the MCP key when -BaseUrl is given.

.PARAMETER SolutionDir
    Folder holding .mcp.json. Default: the current directory.

.PARAMETER Server
    Server name in .mcp.json, when the default choice is not the one wanted.

.PARAMETER List
    List the tools.

.PARAMETER Filter
    Regex over tool name and description, with -List.

.PARAMETER Schema
    Tool whose input schema to print.

.PARAMETER Call
    Tool to call.

.PARAMETER Arguments
    The tool arguments as a JSON object string.

.PARAMETER ArgumentsFile
    A file holding the tool arguments as a JSON object.

.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation for a non-localhost site. Localhost is bypassed anyway.

.PARAMETER TimeoutSec
    Timeout of the tool call in seconds.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwDemoMcp.ps1 -SolutionDir <demo-root> -List -Filter color

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwDemoMcp.ps1 -Schema get_color_schemes

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwDemoMcp.ps1 -Call get_areas -Arguments '{}'
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$BaseUrl,
    [string]$TokenEnv = 'DW_MCP_TOKEN',
    [string]$SolutionDir = (Get-Location).Path,
    [string]$Server,
    [switch]$List,
    [string]$Filter,
    [string]$Schema,
    [string]$Call,
    [string]$Arguments,
    [string]$ArgumentsFile,
    [switch]$AllowSelfSignedCertificate,
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'

# The servers in a .mcp.json that carry a url, in file order: { name; url; authorization }.
function Read-DwMcpJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "No .mcp.json at $Path." }
    $doc = $null
    try { $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "$Path is not valid JSON." }
    if (-not $doc -or -not $doc.PSObject.Properties['mcpServers'] -or -not $doc.mcpServers) {
        throw "$Path has no mcpServers object."
    }
    $out = @()
    foreach ($p in $doc.mcpServers.PSObject.Properties) {
        $v = $p.Value
        if (-not $v -or -not $v.PSObject.Properties['url'] -or -not $v.url) { continue }
        $auth = $null
        if ($v.PSObject.Properties['headers'] -and $v.headers) {
            foreach ($h in $v.headers.PSObject.Properties) {
                if ($h.Name -ieq 'Authorization') { $auth = "$($h.Value)" }
            }
        }
        $out += [pscustomobject]@{ name = $p.Name; url = "$($v.url)"; authorization = $auth }
    }
    , $out
}

# -Server by name, else the first dw-demo-* server, else the first with a url.
function Select-DwMcpServer {
    param([object[]]$Servers, [string]$Name)
    $Servers = @($Servers)
    if ($Servers.Count -eq 0) { throw 'The .mcp.json lists no server with a url.' }
    if ($Name) {
        $hit = @($Servers | Where-Object { $_.name -eq $Name })
        if ($hit.Count -eq 0) {
            throw "No server '$Name' in .mcp.json. Servers: $(($Servers.name) -join ', ')."
        }
        return $hit[0]
    }
    $demo = @($Servers | Where-Object { $_.name -like 'dw-demo-*' })
    if ($demo.Count -gt 0) { return $demo[0] }
    $Servers[0]
}

# The base URL from an MCP endpoint url: the /admin/mcp suffix and trailing slashes removed.
function ConvertTo-DwBaseUrl {
    param([Parameter(Mandatory)][string]$Url)
    ($Url.Trim() -replace '(?i)/admin/mcp/?$', '').TrimEnd('/')
}

# The key from an Authorization header value. "Bearer " is removed; ${NAME} reads that
# environment variable. Never echoes the value in an error.
function ConvertFrom-DwAuthorization {
    param([string]$Value)
    if (-not $Value) { return $null }
    $key = ($Value.Trim() -replace '^(?i)Bearer\s+', '').Trim()
    $m = [regex]::Match($key, '^\$\{(\w+)\}$')
    if ($m.Success) { $key = [Environment]::GetEnvironmentVariable($m.Groups[1].Value) }
    if (-not $key) { return $null }
    $key
}

# The connection: { BaseUrl; Token; Source }. Explicit -BaseUrl + env first, then .mcp.json.
function Resolve-DwDemoMcpConnection {
    param([string]$BaseUrl, [string]$TokenEnv, [string]$SolutionDir, [string]$Server)
    if ($BaseUrl) {
        $token = if ($TokenEnv) { [Environment]::GetEnvironmentVariable($TokenEnv) } else { $null }
        if (-not $token) {
            throw "-BaseUrl was given but `$env:$TokenEnv is empty. Set it to the site's MCP key, or drop -BaseUrl to read .mcp.json."
        }
        return [pscustomobject]@{ BaseUrl = (ConvertTo-DwBaseUrl $BaseUrl); Token = $token; Source = "-BaseUrl + `$env:$TokenEnv" }
    }
    $path = Join-Path $SolutionDir '.mcp.json'
    $chosen = Select-DwMcpServer -Servers (Read-DwMcpJson -Path $path) -Name $Server
    $token = ConvertFrom-DwAuthorization $chosen.authorization
    if (-not $token) {
        throw "Server '$($chosen.name)' in $path has no Authorization header with a key."
    }
    [pscustomobject]@{ BaseUrl = (ConvertTo-DwBaseUrl $chosen.url); Token = $token; Source = "$path ($($chosen.name))" }
}

# Exactly one mode, and argument switches only with -Call.
function Assert-DwDemoMcpMode {
    param([switch]$List, [string]$Schema, [string]$Call, [string]$Arguments, [string]$ArgumentsFile, [string]$Filter)
    $modes = @(@($List.IsPresent, [bool]$Schema, [bool]$Call) | Where-Object { $_ }).Count
    if ($modes -ne 1) { throw 'Pass exactly one of -List, -Schema <tool> or -Call <tool>.' }
    if ($Filter -and -not $List) { throw '-Filter goes with -List.' }
    if (($Arguments -or $ArgumentsFile) -and -not $Call) { throw '-Arguments and -ArgumentsFile go with -Call.' }
    if ($Arguments -and $ArgumentsFile) { throw 'Pass -Arguments or -ArgumentsFile, not both.' }
}

# The tool arguments as a hashtable. Empty input is an empty object; anything but an object is refused.
function ConvertFrom-DwToolArguments {
    param([string]$Arguments, [string]$ArgumentsFile)
    $text = $Arguments
    if ($ArgumentsFile) {
        if (-not (Test-Path -LiteralPath $ArgumentsFile)) { throw "No arguments file at $ArgumentsFile." }
        $text = Get-Content -LiteralPath $ArgumentsFile -Raw
    }
    if (-not $text -or -not $text.Trim()) { return @{} }
    if ($text.TrimStart()[0] -ne '{') { throw 'The tool arguments must be a JSON object, for example {"id": 1}.' }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw "The tool arguments are not valid JSON: $($_.Exception.Message)" }
    $out = @{}
    foreach ($k in @($parsed.Keys)) { $out[$k] = $parsed[$k] }
    $out
}

# The first sentence of a description: up to the first full stop followed by a space, or the first line.
function Get-DwFirstSentence {
    param([string]$Text)
    if (-not $Text) { return '' }
    $line = (($Text -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $line) { return '' }
    $line = $line.Trim()
    # An abbreviation (e.g., i.e., etc., vs.) does not end the sentence.
    $m = [regex]::Match($line, '^.*?(?<!\be\.g|\bi\.e|\betc|\bvs)[.!?](?=\s|$)')
    if ($m.Success) { return $m.Value }
    $line
}

# { name; summary } per tool, sorted by name, optionally filtered by a regex over name and description.
function Select-DwToolSummary {
    param([object[]]$Tools, [string]$Filter)
    $rows = foreach ($t in @($Tools)) {
        if (-not $t) { continue }
        $desc = if ($t.PSObject.Properties['description']) { "$($t.description)" } else { '' }
        if ($Filter -and -not ("$($t.name)" -match $Filter -or $desc -match $Filter)) { continue }
        [pscustomobject]@{ name = "$($t.name)"; summary = (Get-DwFirstSentence $desc) }
    }
    $rows | Sort-Object name
}

# The printable result of a raw tools/call result. An isError result throws the tool's own message.
function ConvertFrom-DwToolResult {
    param($Result)
    $text = ''
    if ($Result -and $Result.PSObject.Properties['content'] -and $Result.content) {
        $text = (@($Result.content) | Where-Object { $_.PSObject.Properties['text'] } |
            ForEach-Object { "$($_.text)" }) -join "`n"
    }
    if ($Result -and $Result.PSObject.Properties['isError'] -and $Result.isError) {
        throw [System.InvalidOperationException]::new($(if ($text) { $text } else { 'the tool reported an error with no message' }))
    }
    if ($Result -and $Result.PSObject.Properties['structuredContent'] -and $null -ne $Result.structuredContent) {
        return $Result.structuredContent
    }
    if ($text) {
        try { return ($text | ConvertFrom-Json -Depth 100) } catch { return $text }
    }
    $Result
}

# A message with the token replaced, so no error path can echo it.
function Hide-DwSecret {
    param([string]$Text, [string]$Secret)
    if (-not $Text -or -not $Secret) { return $Text }
    $Text.Replace($Secret, '****')
}

function Invoke-Main {
    $token = $null
    try {
        Assert-DwDemoMcpMode -List:$List -Schema $Schema -Call $Call -Arguments $Arguments `
            -ArgumentsFile $ArgumentsFile -Filter $Filter
        $toolArgs = if ($Call) { ConvertFrom-DwToolArguments -Arguments $Arguments -ArgumentsFile $ArgumentsFile } else { $null }
        $conn = Resolve-DwDemoMcpConnection -BaseUrl $BaseUrl -TokenEnv $TokenEnv -SolutionDir $SolutionDir -Server $Server
        $token = $conn.Token
        Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
        Connect-Dw -BaseUrl $conn.BaseUrl -McpToken $token -AllowSelfSignedCertificate:$AllowSelfSignedCertificate | Out-Null
        Assert-DwConnection | Out-Null
        Write-Verbose "MCP endpoint from $($conn.Source): $($conn.BaseUrl)/admin/mcp"
    }
    catch {
        [Console]::Error.WriteLine("Invoke-DwDemoMcp: $(Hide-DwSecret "$($_.Exception.Message)" $token)")
        exit 2
    }

    try {
        if ($List -or $Schema) {
            $tools = Get-DwMcpTools
            if ($List) {
                $rows = @(Select-DwToolSummary -Tools $tools -Filter $Filter)
                foreach ($r in $rows) { Write-Output ('{0}  {1}' -f $r.name, $r.summary) }
                [Console]::Error.WriteLine("$(@($rows).Count) of $(@($tools).Count) tool(s).")
                exit 0
            }
            $tool = @($tools | Where-Object { $_.name -eq $Schema }) | Select-Object -First 1
            if (-not $tool) {
                $near = @(Select-DwToolSummary -Tools $tools -Filter ([regex]::Escape($Schema))).name | Select-Object -First 8
                [Console]::Error.WriteLine("Invoke-DwDemoMcp: no tool '$Schema'.$(if ($near) { " Close: $($near -join ', ')." })")
                exit 2
            }
            Write-Output ($tool.inputSchema | ConvertTo-Json -Depth 50)
            exit 0
        }
        $raw = Invoke-DwMcp -Tool $Call -Arguments $toolArgs -Raw -TimeoutSec $TimeoutSec
        $out = ConvertFrom-DwToolResult $raw
        if ($out -is [string]) { Write-Output $out } else { Write-Output ($out | ConvertTo-Json -Depth 50) }
        exit 0
    }
    catch {
        [Console]::Error.WriteLine("Invoke-DwDemoMcp: $(Hide-DwSecret "$($_.Exception.Message)" $token)")
        exit 1
    }
}

# Dot-sourcing loads the functions and runs nothing (that is how the Pester suite covers
# the pure parts); invoking the file runs the mode.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }

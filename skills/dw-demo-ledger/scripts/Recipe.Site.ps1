<#
.SYNOPSIS
READ-ONLY. The site a recipe run targets: the connection read from the demo folder, and the {build.*} values read from the site when the input leaves them out; definitions only.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md ("Connection"). Dot-sourced after Recipe.Core.ps1 (New-RecipeFault).
Resolve-RecipeConnection: a parameter wins, then DW_BASE_URL / DW_MCP_TOKEN / DW_API_TOKEN, then the demo folder (-SiteFolder, else the current directory). From that folder it reads the project .mcp.json (the server whose url ends in /admin/mcp: the base URL and the bearer of its Authorization header) and the optional host facts file demo-host.json (url; keys.resultFile with keys.adminKeyField for the Management API key and keys.mcpKeyField for the MCP key). Each value it resolves is one NOTE line naming the file, never the value. No token is printed, logged or returned in a line.
Get-RecipeBuildNeeds and Resolve-RecipeBuildDefaults: a {build.areaId}, {build.defaultLanguage} or {build.pimShop} token without a default that the input's build section does not fill is read from the site when there is exactly one candidate (one website that is not a language layer, one default language, one DataStructure shop), with a NOTE line naming the value; several candidates or none stop the run with one message that lists them and names the member to add.
.EXAMPLE
. ./Recipe.Site.ps1
#>
#Requires -Version 7.0
function Get-RecipeJsonFile {
    # A small JSON file as hashtables, or $null when it is absent. A file that is not JSON is a named fault, never its content.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return , (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw) -AsHashtable -NoEnumerate) }
    catch { throw (New-RecipeFault "Runner input: $(Split-Path -Leaf $Path) in the site folder is not JSON.") }
}
function Get-RecipeMemberIgnoreCase {
    # The value of a member whatever its casing, or $null. A dotted name walks nested objects.
    param($Object, [string]$Name)
    $node = $Object
    foreach ($part in $Name.Split('.')) {
        if ($node -isnot [Collections.IDictionary]) { return $null }
        $key = @($node.Keys | Where-Object { [string]$_ -ieq $part })[0]
        if ($null -eq $key) { return $null }
        $node = $node[$key]
    }
    return $node
}
function Resolve-RecipeConnection {
    # The base URL and the two tokens for this run. Returns @{baseUrl; apiToken; mcpToken; notes}; notes name sources only.
    param([string]$SiteFolder, [string]$BaseUrl, [string]$ApiToken, [string]$McpToken)
    $notes = [Collections.Generic.List[string]]::new()
    if (-not $BaseUrl) { $BaseUrl = $env:DW_BASE_URL }
    if (-not $ApiToken) { $ApiToken = $env:DW_API_TOKEN }
    if (-not $McpToken) { $McpToken = $env:DW_MCP_TOKEN }
    $result = @{baseUrl = $BaseUrl; apiToken = $ApiToken; mcpToken = $McpToken; notes = $notes}
    if ($BaseUrl -and $ApiToken -and $McpToken) { return $result }
    $folder = if ($SiteFolder) { $SiteFolder } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw (New-RecipeFault "Runner input: -SiteFolder is not a folder.") }
    $folder = (Resolve-Path -LiteralPath $folder).Path
    $mcpFile = Get-RecipeJsonFile (Join-Path $folder '.mcp.json')
    $hostFile = Get-RecipeJsonFile (Join-Path $folder 'demo-host.json')

    # The project MCP config: every server whose url ends in /admin/mcp is a Dynamicweb site.
    $server = $null
    $servers = Get-RecipeMemberIgnoreCase $mcpFile 'mcpServers'
    if ($servers -is [Collections.IDictionary]) {
        $sites = @(foreach ($name in @($servers.Keys)) {
                $url = [string](Get-RecipeMemberIgnoreCase $servers[$name] 'url')
                if ($url -match '(?i)^https?://.+/admin/mcp/?$') { @{name = [string]$name; url = $url.TrimEnd('/'); entry = $servers[$name]} }
            })
        if ($sites.Count -gt 1) {
            # The host facts file names the one this folder builds; otherwise the choice is the caller's.
            $wantName = [string](Get-RecipeMemberIgnoreCase $hostFile 'mcp.name')
            $wantUrl = ([string](Get-RecipeMemberIgnoreCase $hostFile 'mcp.url')).TrimEnd('/')
            $picked = @($sites | Where-Object { ($wantName -and $_.name -ceq $wantName) -or ($wantUrl -and $_.url -ieq $wantUrl) })
            if ($picked.Count -ne 1) {
                throw (New-RecipeFault ("Runner input: .mcp.json in the site folder lists $($sites.Count) Dynamicweb servers (" + (@($sites | ForEach-Object { $_.name } | Sort-Object) -join ', ') + '); set DW_BASE_URL and DW_MCP_TOKEN, or name the server in demo-host.json mcp.name.'))
            }
            $server = $picked[0]
        } elseif ($sites.Count -eq 1) { $server = $sites[0] }
    }
    # The host facts file names the keys file and the field of each key in it; the file is read once, when a key is needed.
    $keys = Get-RecipeMemberIgnoreCase $hostFile 'keys'
    $keyCache = @{}
    $readKey = {
        param([string]$Field)
        if ($keys -isnot [Collections.IDictionary]) { return $null }
        $fieldName = [string](Get-RecipeMemberIgnoreCase $keys $Field)
        $path = [string](Get-RecipeMemberIgnoreCase $keys 'resultFile')
        if (-not $fieldName -or -not $path) { return $null }
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $folder $path }
        if (-not $keyCache.Contains('data')) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (New-RecipeFault "Runner input: demo-host.json keys.resultFile names $(Split-Path -Leaf $path), which does not exist.") }
            $keyCache.data = Get-RecipeJsonFile $path
        }
        $value = Get-RecipeMemberIgnoreCase $keyCache.data $fieldName
        if ($value -is [string] -and $value.Trim()) { return @{value = $value.Trim(); file = (Split-Path -Leaf $path)} }
        return $null
    }

    if (-not $result.baseUrl) {
        if ($server) {
            $result.baseUrl = $server.url -replace '(?i)/admin/mcp$', ''
            $notes.Add("NOTE connection: base URL from .mcp.json (server $($server.name))")
        } elseif ([string](Get-RecipeMemberIgnoreCase $hostFile 'url')) {
            $result.baseUrl = ([string](Get-RecipeMemberIgnoreCase $hostFile 'url')).TrimEnd('/')
            $notes.Add('NOTE connection: base URL from demo-host.json')
        }
    }
    if (-not $result.mcpToken) {
        $auth = if ($server) { [string](Get-RecipeMemberIgnoreCase (Get-RecipeMemberIgnoreCase $server.entry 'headers') 'Authorization') } else { '' }
        $bearer = ($auth -replace '(?i)^\s*Bearer\s+', '').Trim()
        if ($bearer -and $bearer -notmatch '^<.*>$') {
            $result.mcpToken = $bearer
            $notes.Add('NOTE connection: MCP token from .mcp.json')
        } else {
            if ($bearer) { $notes.Add('NOTE connection: .mcp.json holds a placeholder, not an MCP key') }
            $found = & $readKey 'mcpKeyField'
            if ($found) { $result.mcpToken = $found.value; $notes.Add("NOTE connection: MCP token from demo-host.json keys ($($found.file))") }
        }
    }
    if (-not $result.apiToken) {
        $found = & $readKey 'adminKeyField'
        if ($found) { $result.apiToken = $found.value; $notes.Add("NOTE connection: Management API token from demo-host.json keys ($($found.file))") }
    }
    return $result
}
function Get-RecipeConnectionGaps {
    # One NOTE per credential still missing, naming both ways to supply it.
    param($Connection)
    if (-not $Connection.mcpToken) { 'NOTE connection: no MCP token: set DW_MCP_TOKEN, or run from the folder that holds the site''s .mcp.json (or pass -SiteFolder)' }
    if (-not $Connection.apiToken) { 'NOTE connection: no Management API token: set DW_API_TOKEN, or run from the site folder whose demo-host.json names the keys file (or pass -SiteFolder)' }
}
$script:RecipeBuildMembers = [ordered]@{
    areaId = @{tool = 'get_areas'; what = 'website'}
    defaultLanguage = @{tool = 'get_languages'; what = 'default language'}
    pimShop = @{tool = 'get_shops'; what = 'DataStructure shop'}
}
function Get-RecipeBuildNeeds {
    # The build members these recipes read with no default (a {build.x|default} token needs nothing) and the build lacks.
    param([object[]]$Docs, $Build)
    $text = (@($Docs) | ForEach-Object { $_ | ConvertTo-Json -Depth 80 -Compress }) -join "`n"
    return @(foreach ($name in $script:RecipeBuildMembers.Keys) {
            if ($Build -is [Collections.IDictionary] -and $Build.Contains($name) -and "$($Build[$name])") { continue }
            if ($text -match ('\{(text:)?build\.' + $name + '\}')) { $name }
        })
}
function Get-RecipeSiteRows {
    # The rows of a read, one per output: {count, data} or a bare list. The caller collects them with @().
    param($Data)
    if ($Data -is [Collections.IDictionary]) { $Data = Get-RecipeMemberIgnoreCase $Data 'data' }
    foreach ($row in @($Data)) { if ($null -ne $row) { $row } }
}
function Resolve-RecipeBuildDefaults {
    # Fills the needed build members from the site. -Read is {param($tool) <the tool's data>}; $null when MCP is not connected.
    # Returns @{values; notes}. Any member it cannot settle to one candidate stops the run with one message for all of them.
    param([string[]]$Needs, [scriptblock]$Read)
    $values = @{}; $notes = [Collections.Generic.List[string]]::new(); $faults = [Collections.Generic.List[string]]::new()
    foreach ($name in @($Needs)) {
        $member = $script:RecipeBuildMembers[$name]
        if (-not $Read) { $faults.Add("build.$name (no MCP connection to read $($member.tool))"); continue }
        $rows = @(Get-RecipeSiteRows (& $Read $member.tool))
        $candidates = @(@(switch ($name) {
                # A language layer names its master website; only a website without one is a candidate.
                'areaId' { foreach ($r in $rows) { $master = Get-RecipeMemberIgnoreCase $r 'masterAreaId'; if (-not $master -or "$master" -eq '0') { Get-RecipeMemberIgnoreCase $r 'id' } } }
                'defaultLanguage' { foreach ($r in $rows) { if ((Get-RecipeMemberIgnoreCase $r 'isDefault') -eq $true) { $id = Get-RecipeMemberIgnoreCase $r 'languageId'; if (-not $id) { $id = Get-RecipeMemberIgnoreCase $r 'id' }; $id } } }
                'pimShop' { foreach ($r in $rows) { $type = "$(Get-RecipeMemberIgnoreCase $r 'usageType')"; if ($type -eq '4' -or $type -ieq 'DataStructure') { Get-RecipeMemberIgnoreCase $r 'id' } } }
            }) | Where-Object { $null -ne $_ -and "$_" -ne '' })
        if ($candidates.Count -eq 1) {
            $values[$name] = if ($name -eq 'areaId') { [int]$candidates[0] } else { [string]$candidates[0] }
            $notes.Add("NOTE build.${name}: $($values[$name]), the site's only $($member.what) ($($member.tool)); add build.$name to the input to choose another")
        } elseif ($candidates.Count -gt 1) {
            $faults.Add("build.$name (the site has $($candidates.Count) candidates from $($member.tool): $(@($candidates | Select-Object -First 10) -join ', '))")
        } else {
            $faults.Add("build.$name ($($member.tool) shows no $($member.what))")
        }
    }
    if ($faults.Count) { throw (New-RecipeFault ('Runner input: the data file''s build section lacks ' + ($faults -join '; ') + '. Add each under "build" in the data file, then run again.')) }
    return @{values = $values; notes = $notes}
}

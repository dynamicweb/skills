<#
.SYNOPSIS
READ-ONLY. Recipe target discovery and the reads a recipe names: MCP, Management API, delivery API and local SQL.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Uses the shared transport (Dw.Api.psm1) and the ledger's local SQL guard (Ledger.Sql.ps1). Every read is on an allowlist in assets/handlers.json, checked before the call; an MCP call's top-level argument names are checked against the tool's own tools/list input schema, because a wrong name answers only a hintless invocation error. SQL is one guarded SELECT, run with parameters (never a token spliced into the text) inside a transaction that is always rolled back. A delivery read sends no credential except the sign-in a read-back names, or the bearer token of the signIn a dwapi-signed-in-get binding names (signed in for that read, never kept or printed). The TLS bypass follows the runner's gate: a loopback base URL or -AllowSelfSignedCertificate. No response body is printed.
.EXAMPLE
. ./Recipe.Transport.ps1
#>
#Requires -Version 7.0
function ConvertTo-RecipeData {
    # A response as nested hashtables, the shape every recipe path walks.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        try { return , (ConvertFrom-Json -InputObject $Value -AsHashtable -NoEnumerate) } catch { throw 'Response is not JSON.' }
    }
    return , ($Value | ConvertTo-Json -Depth 80 -Compress | ConvertFrom-Json -AsHashtable -NoEnumerate)
}
function Get-RecipeCapabilities {
    # What this run may use: surfaces in preference order, the MCP tools offered (with their input schemas), Admin, SQL.
    param([string[]]$Surfaces, [switch]$McpOnly, [string]$McpToken, [string]$ApiToken, [switch]$AllowSql, [string]$SqlServer, [string]$Database)
    $cap = @{surfaces = @($(if ($McpOnly) { 'mcp' } else { $Surfaces })); mcp = $false; tools = @{}; admin = $false; sql = $false; dwapi = $false; sqlServer = $SqlServer; database = $Database; errors = @()}
    if ('mcp' -in $cap.surfaces -and $McpToken) {
        try {
            # Assigned first: Get-DwMcpTools returns its list as one object, and @() around the call would wrap it again.
            $listed = Get-DwMcpTools
            foreach ($tool in $listed) { $cap.tools[[string]$tool.name] = ConvertTo-RecipeData $tool.inputSchema }
            $cap.mcp = $true
        } catch { $cap.errors += 'MCP tools/list failed; MCP bindings are unavailable.' }
    }
    $cap.admin = 'admin-api' -in $cap.surfaces -and [bool]$ApiToken
    $cap.dwapi = 'dwapi' -in $cap.surfaces
    if ('sql' -in $cap.surfaces -and $AllowSql) {
        if (-not $SqlServer -or -not $Database) { throw (New-RecipeFault 'Runner input: -AllowSql needs -SqlServer and -Database for the local install.') }
        Assert-LedgerLocalServer $SqlServer
        $cap.sql = $true
    }
    return $cap
}
function Assert-RecipeArguments {
    # The tool's own input schema names its arguments; a recipe that names others is refused before the call.
    param([string]$Operation, $Arguments, $Capabilities)
    $schema = $Capabilities.tools[$Operation]
    if ($schema -isnot [Collections.IDictionary] -or $schema.properties -isnot [Collections.IDictionary]) { return }
    $unknown = @($Arguments.Keys | Where-Object { -not $schema.properties.Contains([string]$_) })
    $missing = @(@($schema.required) | Where-Object { $_ -and -not $Arguments.Contains([string]$_) })
    if ($unknown.Count -or $missing.Count) {
        throw (New-RecipeFault ("MCP $Operation arguments disagree with its tools/list input schema" + $(if ($unknown.Count) { '; not in the schema: ' + ($unknown -join ', ') }) + $(if ($missing.Count) { '; required and absent: ' + ($missing -join ', ') }) + '.'))
    }
}
function Invoke-RecipeMcpCall {
    # One MCP tool call; the structured result as hashtables. An error result never reads as data.
    param([string]$Operation, $Arguments, $Capabilities, [int]$TimeoutSec = 120, [switch]$AllowText)
    Assert-RecipeArguments $Operation $Arguments $Capabilities
    $raw = Invoke-DwMcp -Tool $Operation -Arguments $Arguments -Raw -TimeoutSec $TimeoutSec
    if ($raw.isError) {
        if ((@($raw.content | ForEach-Object { $_.text }) -join ' ') -match '(?i)not allowed|access denied|unauthorized|forbidden') { throw [UnauthorizedAccessException]::new("MCP $Operation was refused for this key.") }
        throw (New-RecipeFailure "MCP $Operation answered an error result.")
    }
    if ($raw.structuredContent) { return , (ConvertTo-RecipeData $raw.structuredContent) }
    $text = (@($raw.content | ForEach-Object { $_.text })) -join "`n"
    # A write may answer a sentence ("Primary image updated ..."); its read-back is the evidence, so the text is no data.
    if ($AllowText) { try { return , (ConvertTo-RecipeData $text) } catch { return @{} } }
    return , (ConvertTo-RecipeData $text)
}
function Invoke-RecipeSqlRows {
    # One guarded local SELECT with named parameters; every column of every row. Nothing is ever committed.
    param($Binding, $Context, $Capabilities)
    Assert-LedgerLocalServer $Capabilities.sqlServer
    Assert-LedgerSelect $Binding.query
    $connection = New-LedgerSqlConnection $Capabilities.sqlServer $Capabilities.database
    try {
        $connection.Open()
        $transaction = $connection.BeginTransaction()
        try {
            $command = $connection.CreateCommand(); $command.Transaction = $transaction; $command.CommandText = $Binding.query; $command.CommandTimeout = 30
            if ($Binding.parameters) {
                foreach ($name in $Binding.parameters.Keys) {
                    $value = Expand-RecipeValue $Binding.parameters[$name] $Context
                    $null = $command.Parameters.AddWithValue('@' + $name, $(if ($null -eq $value) { [DBNull]::Value } else { $value }))
                }
            }
            $rows = [Collections.Generic.List[object]]::new()
            $reader = $command.ExecuteReader()
            try {
                while ($reader.Read()) {
                    $row = @{}
                    for ($i = 0; $i -lt $reader.FieldCount; $i++) { $row[$reader.GetName($i)] = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) } }
                    $rows.Add($row)
                }
            } finally { $reader.Dispose(); $command.Dispose() }
            return , $rows.ToArray()
        } finally {
            try { $transaction.Rollback() } catch { Write-Verbose 'Transaction was already ended by the server.' }
            $transaction.Dispose()
        }
    } finally { $connection.Dispose() }
}
function Invoke-RecipeSignIn {
    # A read-back of a password write: POST {username, password} to an allowlisted sign-in route; one row {signedIn, status}.
    # The password and any token stay in this function; no response body is kept.
    param($Binding, $Context)
    $arguments = Expand-RecipeValue $Binding.arguments $Context
    $body = @{username = $arguments.username; password = $arguments.password} | ConvertTo-Json -Compress
    $response = Invoke-WebRequest -Uri ($script:RecipeTarget.baseUrl + '/dwapi/' + $Binding.operation) -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept = 'application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
    $status = [int]$response.StatusCode
    if ($status -ge 500) { throw 'Sign-in request failed on the server.' }
    $signedIn = $false
    if ($status -eq 200) { try { $answer = ConvertFrom-Json -InputObject ([string]$response.Content) -AsHashtable; $signedIn = $answer.token -is [string] -and [bool]$answer.token.Trim() } catch { $signedIn = $false } }
    return , @(@{signedIn = $signedIn; status = $status})
}
function Get-RecipeSignInToken {
    # The bearer token of a sign-in a dwapi-signed-in-get binding names in signIn {username, password}. It stays
    # in the caller; a refused sign-in is a fault that names no value.
    param($Binding, $Context, $Registry)
    $credential = Expand-RecipeValue $Binding.signIn $Context
    if ($credential -isnot [Collections.IDictionary] -or -not $credential.username -or -not $credential.password) { throw (New-RecipeFault 'Runner input: a signed-in delivery read names no signIn username and password.') }
    $body = @{username = $credential.username; password = $credential.password} | ConvertTo-Json -Compress
    $route = @($Registry.dwapiSignInRoutes)[0]
    $response = Invoke-WebRequest -Uri ($script:RecipeTarget.baseUrl + '/dwapi/' + $route) -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept = 'application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
    $token = $null
    if ([int]$response.StatusCode -eq 200) { try { $token = (ConvertFrom-Json -InputObject ([string]$response.Content) -AsHashtable).token } catch { $token = $null } }
    if ($token -isnot [string] -or -not $token.Trim()) { throw [UnauthorizedAccessException]::new("The signed-in delivery read could not sign in (HTTP $([int]$response.StatusCode)).") }
    return $token
}
function Invoke-RecipeDeliveryGet {
    # One GET on an allowlisted delivery route: anonymous (dwapi-get), or as the user signIn names (dwapi-signed-in-get).
    # {areaId} takes the build's area id; any other {name} in the route takes the argument of that name, and the
    # remaining arguments are the query.
    param($Binding, $Context, $Registry)
    $route = [string]$Binding.operation
    if ($route.Contains('{areaId}')) {
        $area = [string]$Context.build.areaId
        if ($area -notmatch '^[0-9]+$') { throw (New-RecipeFault 'Runner input: build.areaId is needed by this delivery route.') }
        $route = $route.Replace('{areaId}', $area)
    }
    $query = if ($Binding.arguments) { Expand-RecipeValue $Binding.arguments $Context } else { @{} }
    foreach ($m in @([regex]::Matches($route, '\{(?<name>[A-Za-z][A-Za-z0-9]*)\}'))) {
        $name = $m.Groups['name'].Value
        if (-not $query.Contains($name) -or [string]::IsNullOrEmpty([string]$query[$name])) { throw (New-RecipeFault "Runner input: delivery route $($Binding.operation) needs the argument $name.") }
        $route = $route.Replace($m.Value, [Uri]::EscapeDataString([string]$query[$name])); $query.Remove($name)
    }
    $pairs = @(foreach ($k in @($query.Keys | Sort-Object)) { [Uri]::EscapeDataString($k) + '=' + [Uri]::EscapeDataString([string]$query[$k]) })
    $uri = $script:RecipeTarget.baseUrl + '/dwapi/' + $route + $(if ($pairs.Count) { '?' + ($pairs -join '&') })
    $headers = @{Accept = 'application/json'}
    if ($Binding.handler -eq 'dwapi-signed-in-get') { $headers.Authorization = 'Bearer ' + (Get-RecipeSignInToken $Binding $Context $Registry) }
    $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
    $status = [int]$response.StatusCode
    if ($status -in @(401, 403)) { throw [UnauthorizedAccessException]::new("Delivery read is not authorised ($($Binding.handler)).") }
    if ($status -ne 200) { throw (New-RecipeFault "Delivery route $($Binding.operation) answered HTTP $status.") }
    return , (ConvertTo-RecipeData ([string]$response.Content))
}
function Read-RecipeRows {
    # The rows one read binding returns, from the member its `rows` path names ('$' for the response itself).
    param($Binding, $Context, $Run)
    $operation = if ($Binding.surface -eq 'sql') { 'SELECT' } else { [string]$Binding.operation }
    $fault = Get-RecipeSurfaceFault $Binding $operation 'read' $Run.cap $Run.registry
    if ($fault) { throw (New-RecipeFault "Read refused before the call: $fault.") }
    $data = switch ($Binding.surface) {
        'mcp' { Invoke-RecipeMcpCall $operation (Expand-RecipeValue $Binding.arguments $Context) $Run.cap 60 }
        'admin-api' {
            $query = Expand-RecipeValue $Binding.arguments $Context
            $pairs = @(foreach ($k in @($query.Keys | Sort-Object)) { [Uri]::EscapeDataString($k) + '=' + [Uri]::EscapeDataString([string]$query[$k]) })
            ConvertTo-RecipeData (Invoke-DwApi ($operation + $(if ($pairs.Count) { '?' + ($pairs -join '&') })))
        }
        'sql' { return , (Invoke-RecipeSqlRows $Binding $Context $Run.cap) }
        'dwapi' {
            if ($Binding.handler -eq 'dwapi-sign-in') { return , (Invoke-RecipeSignIn $Binding $Context) }
            if ($Binding.handler -notin @('dwapi-get', 'dwapi-signed-in-get')) { throw (New-RecipeFault "Delivery handler $($Binding.handler) is not a row read.") }
            Invoke-RecipeDeliveryGet $Binding $Context $Run.registry
        }
    }
    $rows = Get-RecipeValue $data $(if ($Binding.rows) { $Binding.rows } else { '$' })
    if (-not $rows.found) { throw (New-RecipeFault "Response of '$operation' has no member '$($Binding.rows)'; the projection is not the one the recipe states.") }
    if ($null -eq $rows.value) { return , @() }
    if ($rows.value -is [Collections.IDictionary]) { return , @($rows.value) }
    if ($rows.value -isnot [Collections.IList]) { throw (New-RecipeFault "Member '$($Binding.rows)' of '$operation' is not a list of rows.") }
    return , @($rows.value)
}
function Get-RecipeProduced {
    # The values a step hands to later steps, read from the row the find or the read-back matched.
    param($Row, $Produces, [string]$Operation, $Into)
    $values = if ($Into) { $Into } else { @{} }
    if ($Produces) { foreach ($name in $Produces.Keys) { $values[$name] = Get-RecipeRowField $Row $Produces[$name] $Operation } }
    return $values
}

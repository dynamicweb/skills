<#
.SYNOPSIS
READ-ONLY. Recipe target discovery and the reads a recipe names: MCP, Management API, delivery API and local SQL.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Uses the shared transport (Dw.Api.psm1) and the ledger's local SQL guard (Ledger.Sql.ps1). Every read is on an allowlist in assets/handlers.json, checked before the call; an MCP call's argument names, nested members included, are checked against the tool's own tools/list input schema, because a wrong name answers only an invocation error (an older server refuses a member it does not list). SQL is one guarded SELECT, run with parameters (never a token spliced into the text) inside a transaction that is always rolled back. A delivery read sends no credential except the sign-in a read-back names, or the bearer token of the signIn a dwapi-signed-in-get binding names (signed in for that read, never kept or printed). The TLS bypass follows the runner's gate: a loopback base URL or -AllowSelfSignedCertificate. No response body is printed; an MCP error result's own message is, as one line of at most 300 characters with the values of credential-named arguments and token-shaped text masked.
.EXAMPLE
. ./Recipe.Transport.ps1
#>
#Requires -Version 7.0
# Every HTTP call goes through Invoke-DwHttp (the shared transport's Dw.Http.ps1): the cmdlet as called, or Node in a shell whose PowerShell cannot open TLS connections.
. (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Http.ps1')
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
    $cap = @{surfaces = @($(if ($McpOnly) { 'mcp' } else { $Surfaces })); mcp = $false; tools = @{}; outputs = @{}; admin = $false; sql = $false; dwapi = $false; sqlServer = $SqlServer; database = $Database; errors = @()}
    if ('mcp' -in $cap.surfaces -and $McpToken) {
        try {
            # Assigned first: Get-DwMcpTools returns its list as one object, and @() around the call would wrap it again.
            $listed = Get-DwMcpTools
            foreach ($tool in $listed) { $cap.tools[[string]$tool.name] = ConvertTo-RecipeData $tool.inputSchema; $cap.outputs[[string]$tool.name] = ConvertTo-RecipeData $tool.outputSchema }
            $cap.mcp = $true
        } catch {
            # The reason (a refused socket, a TLS failure, a 401) says what to fix; token-shaped text is masked and the line is bounded.
            $why = (([string]$_.Exception.Message) -replace '\s+', ' ' -replace '(?i)Bearer\s+\S+', 'Bearer ***' -replace '(?i)\b(claude|mcp)\.[0-9a-f]{20,}', '***').Trim().TrimEnd('.')
            if ($why.Length -gt 240) { $why = $why.Substring(0, 240) + '...' }
            $cap.errors += 'MCP tools/list failed; MCP bindings are unavailable.' + $(if ($why) { " Reason: $why." } else { '' })
        }
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
function Test-RecipeSchemaMember {
    # True when a JSON schema carries the dotted member path (a [*] level steps into the array's items).
    param($Schema, [string]$Path)
    $node = $Schema
    foreach ($part in $Path.Split('.')) {
        if ($part -notmatch '^(?<name>[A-Za-z_][A-Za-z0-9_]*)(?<all>\[\*\])?$') { throw (New-RecipeFault "requiresSchema path '$Path' is not a dotted member path.") }
        if ($node -isnot [Collections.IDictionary] -or $node.properties -isnot [Collections.IDictionary] -or -not $node.properties.Contains($Matches['name'])) { return $false }
        $node = $node.properties[$Matches['name']]
        if ($Matches['all']) {
            if ($node -isnot [Collections.IDictionary] -or $node.items -isnot [Collections.IDictionary]) { return $false }
            $node = $node.items
        }
    }
    return $true
}
function Get-RecipeSchemaGap {
    # requiresSchema: $null when the target's tools/list schema of the operation carries every member named,
    # otherwise the reason the binding cannot run here. The schema decides, never a version number: a newer
    # server that adds a member serves the binding, an older one falls to the next binding.
    param($Requires, [string]$Operation, $Capabilities)
    if (-not $Requires) { return $null }
    foreach ($side in @('input', 'output')) {
        if (-not $Requires.Contains($side)) { continue }
        $schema = if ($side -eq 'input') { $Capabilities.tools[$Operation] } elseif ($Capabilities.outputs) { $Capabilities.outputs[$Operation] }
        foreach ($path in @($Requires[$side])) {
            if (-not (Test-RecipeSchemaMember $schema ([string]$path))) { return "MCP $Operation's tools/list $side schema carries no member '$path'" }
        }
    }
    return $null
}
function Get-RecipeUnknownMembers {
    # The members of a value that its schema node does not list, as dotted paths with [*] for array items. Only a
    # node that lists its properties is checked; an open object (a field map) is not. A server that refuses an
    # unlisted member answers a call error, so a member an older server lacks is named here, before the call.
    param($Value, $Schema, [string]$Path)
    if ($Schema -isnot [Collections.IDictionary]) { return }
    if ($Value -is [Collections.IDictionary]) {
        if ($Schema.properties -isnot [Collections.IDictionary]) { return }
        foreach ($k in @($Value.Keys)) {
            $at = if ($Path) { "$Path.$k" } else { [string]$k }
            if (-not $Schema.properties.Contains([string]$k)) { $at; continue }
            Get-RecipeUnknownMembers $Value[$k] $Schema.properties[[string]$k] $at
        }
    } elseif ($Value -is [Collections.IList] -and $Value -isnot [string]) {
        foreach ($v in $Value) { Get-RecipeUnknownMembers $v $Schema.items "$Path[*]" }
    }
}
function Assert-RecipeArguments {
    # The tool's own input schema names its arguments, nested members included; a recipe that names others is refused before the call.
    param([string]$Operation, $Arguments, $Capabilities)
    $schema = $Capabilities.tools[$Operation]
    if ($schema -isnot [Collections.IDictionary] -or $schema.properties -isnot [Collections.IDictionary]) { return }
    $unknown = @(Get-RecipeUnknownMembers $Arguments $schema '' | Select-Object -Unique)
    $missing = @(@($schema.required) | Where-Object { $_ -and -not $Arguments.Contains([string]$_) })
    if ($unknown.Count -or $missing.Count) {
        throw (New-RecipeFault ("MCP $Operation arguments disagree with its tools/list input schema" + $(if ($unknown.Count) { '; not in the schema: ' + ($unknown -join ', ') }) + $(if ($missing.Count) { '; required and absent: ' + ($missing -join ', ') }) + '.'))
    }
}
function Format-RecipeMcpError {
    # The message of an MCP error result, as one bounded line: the tool's own words ("Shop 'X' not found") say what to
    # fix. Values of credential-named arguments and token-shaped text are masked, so a secret the call carried is not printed.
    param($Raw, $Arguments)
    $text = ((@($Raw.content | ForEach-Object { $_.text }) -join ' ') -replace '\s+', ' ').Trim()
    if (-not $text) { return '' }
    $secrets = [Collections.Generic.List[string]]::new()
    $collect = {
        param($node)
        if ($node -is [Collections.IDictionary]) { foreach ($k in @($node.Keys)) { if ([string]$k -match '(?i)password|pwd|secret|token|apikey' -and $node[$k] -is [string] -and $node[$k].Length -ge 4) { $secrets.Add($node[$k]) } else { & $collect $node[$k] } } }
        elseif ($node -is [Collections.IList] -and $node -isnot [string]) { foreach ($x in $node) { & $collect $x } }
    }
    & $collect $Arguments
    foreach ($s in $secrets) { $text = $text.Replace($s, '***') }
    $text = $text -replace '(?i)Bearer\s+\S+', 'Bearer ***' -replace '(?i)\b(claude|mcp)\.[0-9a-f]{20,}', '***'
    if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
    return $text.TrimEnd('.')
}
function Invoke-RecipeMcpCall {
    # One MCP tool call; the structured result as hashtables. An error result never reads as data; its message is printed.
    param([string]$Operation, $Arguments, $Capabilities, [int]$TimeoutSec = 120, [switch]$AllowText)
    Assert-RecipeArguments $Operation $Arguments $Capabilities
    $raw = Invoke-DwMcp -Tool $Operation -Arguments $Arguments -Raw -TimeoutSec $TimeoutSec
    if ($raw.isError) {
        $message = Format-RecipeMcpError $raw $Arguments
        if ($message -match '(?i)not allowed|access denied|unauthorized|forbidden') { throw [UnauthorizedAccessException]::new("MCP $Operation was refused for this key: $message") }
        throw (New-RecipeFailure ("MCP $Operation answered an error result" + $(if ($message) { ": $message" } else { ' with no message' }) + '.'))
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
    $response = Invoke-DwHttp -Uri ($script:RecipeTarget.baseUrl + '/dwapi/' + $Binding.operation) -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept = 'application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
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
    $response = Invoke-DwHttp -Uri ($script:RecipeTarget.baseUrl + '/dwapi/' + $route) -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept = 'application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
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
    $response = Invoke-DwHttp -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
    $status = [int]$response.StatusCode
    if ($status -in @(401, 403)) { throw [UnauthorizedAccessException]::new("Delivery read is not authorised ($($Binding.handler)).") }
    if ($status -ne 200) { throw (New-RecipeFault "Delivery route $($Binding.operation) answered HTTP $status.") }
    return , (ConvertTo-RecipeData ([string]$response.Content))
}
function Invoke-RecipeStorefrontLinks {
    # storefront-links: the anonymous storefront page at arguments.path as rendered, and the links (href, text) inside the
    # first element the operation names (footer or header). No credential is sent; the markup itself is never kept or printed.
    param($Binding, $Context)
    $region = [string]$Binding.operation
    $path = [string](Expand-RecipeValue $Binding.arguments $Context).path
    if ($path -notmatch '^/[A-Za-z0-9/_-]*$') { throw (New-RecipeFault "Runner input: storefront-links reads a site path such as /en-us/about, not '$path'.") }
    $response = Invoke-DwHttp -Uri ($script:RecipeTarget.baseUrl + $path) -Method Get -Headers @{Accept = 'text/html'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:RecipeTarget.insecure
    $status = [int]$response.StatusCode
    if ($status -ne 200) { throw (New-RecipeFailure "Storefront page $path answered HTTP $status.") }
    $part = [regex]::Match([string]$response.Content, "(?is)<$region\b[^>]*>(?<body>.*?)</$region>")
    if (-not $part.Success) { throw (New-RecipeFailure "Storefront page $path renders no $region element.") }
    $links = foreach ($a in [regex]::Matches($part.Groups['body'].Value, '(?is)<a\b(?<attrs>[^>]*)>(?<inner>.*?)</a>')) {
        $href = [regex]::Match($a.Groups['attrs'].Value, '(?i)\bhref\s*=\s*"(?<h>[^"]*)"').Groups['h'].Value
        $text = ([regex]::Replace($a.Groups['inner'].Value, '<[^>]+>', ' ') -replace '\s+', ' ').Trim()
        @{href = [Net.WebUtility]::HtmlDecode($href); text = [Net.WebUtility]::HtmlDecode($text)}
    }
    return @{links = @($links)}
}
function Test-RecipeTimeout($Exception) {
    # A call that ran out of time: an HttpClient timeout surfaces as a cancelled task or a TimeoutException, inner or outer.
    for ($e = $Exception; $e; $e = $e.InnerException) {
        if ($e -is [TimeoutException] -or $e -is [Threading.Tasks.TaskCanceledException] -or $e.Message -match '(?i)timed? ?out|Timeout of \d+') { return $true }
    }
    return $false
}
function Read-RecipeRows {
    # The rows one read binding returns, from the member its `rows` path names ('$' for the response itself).
    param($Binding, $Context, $Run)
    $operation = if ($Binding.surface -eq 'sql') { 'SELECT' } else { [string]$Binding.operation }
    $fault = Get-RecipeSurfaceFault $Binding $operation 'read' $Run.cap $Run.registry
    if ($fault) { throw (New-RecipeFault "Read refused before the call: $fault.") }
    # Every read is bounded by its call's time limit; a read that times out is a FAIL naming what it waited for, never a hang.
    $data = try { switch ($Binding.surface) {
        'mcp' { Invoke-RecipeMcpCall $operation (Expand-RecipeValue $Binding.arguments $Context) $Run.cap 60 }
        'admin-api' {
            $query = Expand-RecipeValue $Binding.arguments $Context
            $pairs = @(foreach ($k in @($query.Keys | Sort-Object)) { [Uri]::EscapeDataString($k) + '=' + [Uri]::EscapeDataString([string]$query[$k]) })
            ConvertTo-RecipeData (Invoke-DwApi ($operation + $(if ($pairs.Count) { '?' + ($pairs -join '&') })))
        }
        'sql' { return , (Invoke-RecipeSqlRows $Binding $Context $Run.cap) }
        'dwapi' {
            if ($Binding.handler -eq 'dwapi-sign-in') { return , (Invoke-RecipeSignIn $Binding $Context) }
            if ($Binding.handler -eq 'storefront-links') { Invoke-RecipeStorefrontLinks $Binding $Context }
            elseif ($Binding.handler -notin @('dwapi-get', 'dwapi-signed-in-get')) { throw (New-RecipeFault "Delivery handler $($Binding.handler) is not a row read.") }
            else { Invoke-RecipeDeliveryGet $Binding $Context $Run.registry }
        }
    } } catch {
        if (Test-RecipeTimeout $_.Exception) { throw (New-RecipeFailure "no answer from $($Binding.surface) $operation within its time limit") }
        throw
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

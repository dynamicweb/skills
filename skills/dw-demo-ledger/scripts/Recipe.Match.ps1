<#
.SYNOPSIS
READ-ONLY. Recipe comparison, natural-key matching, skipWhen conditions and binding selection; definitions only.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Dot-sourced after Recipe.Core.ps1 (Get-RecipeValue, Expand-RecipeValue, the faults). Equality is typed (numbers by value, booleans by value, text by ordinal, a NULL equal to an empty text); a field the recipe names must be in the row, so an unmeasured projection fails loudly. Differences name fields, never values. A binding runs only when its surface is permitted, its operation is on the allowlist in assets/handlers.json and, for MCP, the target's tools/list offers it.
.EXAMPLE
. ./Recipe.Match.ps1
#>
#Requires -Version 7.0
function Test-RecipeNumber($Value) {
    return $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [int16] -or $Value -is [byte]
}
function Test-RecipeEqual {
    # Typed equality: numbers by value (5 equals 5.0 and "5"), booleans by value, text by ordinal.
    param($Left, $Right)
    # A stored NULL and an empty text are the same absent value: a column read back as one may be written as the other.
    if ($null -eq $Left -or $null -eq $Right) { return [string]::IsNullOrEmpty([string]$Left) -and [string]::IsNullOrEmpty([string]$Right) }
    # Lists (a display group's field ids, a rule's fields) are equal element by element, in order.
    if ($Left -is [Collections.IList] -or $Right -is [Collections.IList]) {
        if (-not ($Left -is [Collections.IList] -and $Right -is [Collections.IList]) -or $Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) { if (-not (Test-RecipeEqual $Left[$i] $Right[$i])) { return $false } }
        return $true
    }
    if ((Test-RecipeNumber $Left) -or (Test-RecipeNumber $Right)) {
        $a = 0.0; $b = 0.0; $inv = [Globalization.CultureInfo]::InvariantCulture
        return [double]::TryParse([string]$Left, [Globalization.NumberStyles]::Float, $inv, [ref]$a) -and
            [double]::TryParse([string]$Right, [Globalization.NumberStyles]::Float, $inv, [ref]$b) -and $a -eq $b
    }
    if ($Left -is [bool] -or $Right -is [bool]) { return [string]::Equals([string]$Left, [string]$Right, [StringComparison]::OrdinalIgnoreCase) }
    return [string]::Equals([string]$Left, [string]$Right, [StringComparison]::Ordinal)
}
function Get-RecipeRowField {
    # A field the recipe names must be in the row: an unmeasured projection fails loudly, never as a mismatch.
    param($Row, [string]$Path, [string]$Operation)
    $value = Get-RecipeValue $Row $Path
    if (-not $value.found) { throw (New-RecipeFault "Response of '$Operation' carries no field '$Path'; the projection is not the one the recipe states.") }
    return , $value.value
}
function Test-RecipeEqualUnordered($Left, $Right) {
    # Two lists that hold the same elements as often, in any order (a state's next states, read back sorted by id).
    if (-not ($Left -is [Collections.IList] -and $Right -is [Collections.IList])) { return Test-RecipeEqual $Left $Right }
    $by = { if (Test-RecipeNumber $_) { '{0:R}' -f [double]$_ } else { [string]$_ } }; return Test-RecipeEqual @($Left | Sort-Object -CaseSensitive $by) @($Right | Sort-Object -CaseSensitive $by)
}
function Get-RecipeDifferences {
    # Field names whose row value differs from the expected value. Values are not returned: they may be personal data.
    # -Unordered names the list members compared as sets with their counts, for a list the platform reads back in its own order.
    param($Row, $Expected, [string]$Operation, [string[]]$Unordered)
    $names = @(foreach ($k in @($Expected.Keys)) {
        # An expected null is a statement that the member is empty, and the MCP read models leave out a null
        # member: only there does absence read as null. A value the recipe expects still fails loudly when absent.
        if ($null -eq $Expected[$k] -and -not (Get-RecipeValue $Row $k).found) { continue }
        if (-not (& $(if ($k -cin @($Unordered)) { 'Test-RecipeEqualUnordered' } else { 'Test-RecipeEqual' }) (Get-RecipeRowField $Row $k $Operation) $Expected[$k])) { $k }
    })
    return , $names
}
function Select-RecipeMatches {
    param([object[]]$Rows, $Match, [string]$Operation)
    if (-not $Match -or $Match.Count -eq 0) { return , @($Rows) }
    # A row that leaves out a member the key gives a value is a row whose member is null, so it does not match:
    # price rows of other scopes omit the scope member. A misspelt key member then matches nothing, and the
    # read-back after a write fails on it, so the absence still shows.
    $valued = @($Match.Keys | Where-Object { $null -ne $Match[$_] })
    $Rows = @($Rows | Where-Object { $row = $_; -not @($valued | Where-Object { -not (Get-RecipeValue $row $_).found }).Count })
    $hits = foreach ($row in $Rows) {
        # Assigned, not wrapped in @(): the differences come back as one list object.
        $differs = Get-RecipeDifferences $row $Match $Operation
        if ($differs.Count -eq 0) { , $row }
    }
    return , @($hits)
}
function Get-RecipeMapDifferences {
    # compareMap / expectMap: rows that hold one name and one value each (item fields). Every name of the
    # expected map must be exactly one row whose value equals it. The add-in leaves out a member whose value
    # is null, so an absent value member reads as null here, and only here. Returns the differing names.
    param([object[]]$Rows, $Spec, $Context)
    $map = Expand-RecipeValue $Spec.from $Context
    if ($map -isnot [Collections.IDictionary]) { throw (New-RecipeFault 'A compareMap or expectMap does not resolve to an object of names and values.') }
    $names = foreach ($name in @($map.Keys)) {
        $hits = @($Rows | Where-Object { [string](Get-RecipeValue $_ $Spec.key).value -ceq [string]$name })
        if ($hits.Count -ne 1) { $name; continue }
        $value = Get-RecipeValue $hits[0] $Spec.value
        if (-not (Test-RecipeEqual $(if ($value.found) { $value.value } else { $null }) $map[$name])) { $name }
    }
    return , @($names)
}
function Test-RecipeCondition {
    # skipWhen: exists, equals, notEquals or contains on one input path. Nothing else is evaluated.
    # A list of conditions skips when any of them holds.
    param($Condition, $Context)
    if (-not $Condition) { return $false }
    if ($Condition -is [Collections.IList]) { foreach ($c in $Condition) { if (Test-RecipeCondition $c $Context) { return $true } }; return $false }
    $value = Resolve-RecipeRootPath $Condition.path $Context
    $present = $value.found -and $null -ne $value.value
    if ($Condition.Contains('exists')) { return $present -eq [bool]$Condition.exists }
    # The compared value may be a token of the input ({input.buyer.account}), never code.
    if ($Condition.Contains('equals')) { return $present -and (Test-RecipeEqual $value.value (Expand-RecipeValue $Condition.equals $Context)) }
    if ($Condition.Contains('notEquals')) { return -not ($present -and (Test-RecipeEqual $value.value (Expand-RecipeValue $Condition.notEquals $Context))) }
    if ($Condition.Contains('contains')) { return $present -and ([string]$value.value).Contains([string](Expand-RecipeValue $Condition.contains $Context), [StringComparison]::Ordinal) }
    throw (New-RecipeFault 'A skipWhen condition states no operator.')
}
function Get-RecipeSurfaceFault {
    # $null when the binding's surface and operation can run on this target; otherwise the reason it cannot.
    param($Binding, [string]$Operation, [string]$Kind, $Capabilities, $Registry)
    if ($Binding.status -ne 'implemented') { return "$($Binding.surface) $Operation is planned: $($Binding.reason)" }
    if ($Binding.surface -notin $Capabilities.surfaces) { return "$($Binding.surface) is not a permitted surface for this run" }
    switch ($Binding.surface) {
        'mcp' {
            # A rendered-page read (fetch_frontend_page_html) is a read with its own list; the ledger's read list holds get_ and list_ tools only.
            # A delete is a list of its own, so removing data is reviewed apart from writing it.
            $list = switch ($Kind) { 'write' { $Registry.recipeWriteTools } 'delete' { $Registry.recipeDeleteTools } default { @($Registry.mcpReadTools) + @($Registry.recipeRenderedReadTools) } }
            if ($Operation -cnotin @($list)) { return "MCP $Operation is not on the recipe $Kind allowlist" }
            if (-not $Capabilities.mcp) { return 'MCP is not connected (DW_MCP_TOKEN)' }
            if (-not $Capabilities.tools.Contains($Operation)) { return "MCP $Operation is not offered by this target's tools/list" }
            if ($Binding.requiresSchema) { $gap = Get-RecipeSchemaGap $Binding.requiresSchema $Operation $Capabilities; if ($gap) { return $gap } }
        }
        'admin-api' {
            if ($Kind -eq 'delete') { return 'a recipe deletes through MCP only (recipeDeleteTools)' }
            $list = if ($Kind -eq 'write') { $Registry.recipeAdminCommands } else { $Registry.adminReadQueries }
            if ($Operation -cnotin @($list)) { return "Management API $Operation is not on the recipe $Kind allowlist" }
            if (-not $Capabilities.admin) { return 'the Management API is not connected (DW_API_TOKEN)' }
        }
        'sql' {
            if ($Kind -ne 'read') { return 'SQL never writes in a recipe' }
            if (-not $Capabilities.sql) { return 'SQL is not enabled (local install, -AllowSql with -SqlServer and -Database)' }
        }
        'dwapi' {
            $routes = switch ($Binding.handler) { 'dwapi-get' { $Registry.dwapiReadRoutes } 'dwapi-signed-in-get' { $Registry.recipeSignedInReadRoutes } 'storefront-links' { $Registry.recipeStorefrontRegions } default { $Registry.dwapiSignInRoutes } }
            if ($Operation -cnotin @($routes)) { return "delivery route $Operation is not on the allowlist for $($Binding.handler)" }
            if (-not $Capabilities.dwapi) { return 'the delivery API is not a permitted surface for this run' }
        }
    }
    return $null
}
function Select-RecipeRead {
    # The first read binding that can run here; @{binding; reasons}.
    param([object[]]$Bindings, $Capabilities, $Registry)
    $reasons = @()
    foreach ($b in $Bindings) {
        $fault = Get-RecipeSurfaceFault $b $(if ($b.surface -eq 'sql') { 'SELECT' } else { $b.operation }) 'read' $Capabilities $Registry
        if (-not $fault) { return @{binding = $b; reasons = $reasons} }
        $reasons += $fault
    }
    return @{binding = $null; reasons = $reasons}
}
function Select-RecipeWrite {
    # The first write binding with this action (create, update or delete) whose write and read-back can both run here.
    param([object[]]$Bindings, [string]$Action, $Capabilities, $Registry)
    $reasons = @()
    foreach ($b in $Bindings) {
        if ($b.status -ne 'implemented') { $reasons += "$($b.id): $($b.surface) is planned: $($b.reason)"; continue }
        if (-not $b.Contains($Action)) { continue }
        $fault = Get-RecipeSurfaceFault $b $b[$Action].operation $(if ($Action -eq 'delete') { 'delete' } else { 'write' }) $Capabilities $Registry
        if (-not $fault -and $b.readBack) {
            $rb = $b.readBack
            $fault = Get-RecipeSurfaceFault $rb $(if ($rb.surface -eq 'sql') { 'SELECT' } else { $rb.operation }) 'read' $Capabilities $Registry
            if ($fault) { $fault = "read-back: $fault" }
        }
        if (-not $fault) { return @{binding = $b; reasons = $reasons} }
        $reasons += "$($b.id): $fault"
    }
    if (-not $reasons) { $reasons = @("no binding declares $Action") }
    return @{binding = $null; reasons = $reasons}
}
function Test-RecipeForbidden {
    # Strings a recipe may not carry: a URL or host, an address with a port, a machine path, a token-shaped secret.
    param($Value, [string]$Where = '$')
    $faults = @()
    if ($Value -is [string]) {
        $patterns = @('(?i)\b[a-z][a-z0-9+.-]*://', '(?i)\b(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?\b', '(?i)\b[a-z]:\\', '^\\\\', '^(/home/|/Users/|~/)', '(?i)\b(claude|mcp)\.[0-9a-f]{40,}', '(?i)Bearer\s+\S{20,}')
        foreach ($p in $patterns) { if ($Value -match $p) { $faults += "$Where holds a host, address, machine path or secret" ; break } }
    } elseif ($Value -is [Collections.IDictionary]) {
        foreach ($k in $Value.Keys) {
            if ($k -match '(?i)^(password|pwd|token|apikey|secret)$' -and $Value[$k] -is [string] -and $Value[$k] -notmatch '^\{secret\.') { $faults += "$Where.$k holds a credential literal" }
            $faults += Test-RecipeForbidden $Value[$k] "$Where.$k"
        }
    } elseif ($Value -is [Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $faults += Test-RecipeForbidden $Value[$i] "$Where[$i]" }
    }
    return $faults
}

<#
.SYNOPSIS
WRITES: the objects a recipe ensures, only with -Apply; without it the run only reads and reports.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Runs one recipe (assets/recipes/<area>/<id>.json) against one customer data file. The recipe and the input are validated against their schemas first. Each step finds its objects by natural key through the first binding the target offers (MCP tools/list, then the Management API, then local SQL for reads), so a verify-only run on a host a layer already delivered reports every object UNCHANGED: that is how build path A uses a recipe. With -Apply, absent objects are created and differing ones updated, every write is read back, and the debts run when anything changed. A step with no eligible binding is BLOCKED with the reason. Then the probes run, and the recipe's ledger check ids run through Invoke-DwLedgerChecks.ps1 when -LedgerBuildFile and -Manifest are given.
Output lines: STEP <step> <CREATED|UPDATED|UNCHANGED|BLOCKED|WOULD-CREATE|WOULD-UPDATE> <natural key>; PASS <check>; FAIL <check>: <reason>; OPEN <check>: <reason>; NOTE lines that are not checks; and last "<recipe id>: n of m checks passed". Exit 0 only when every check passed and nothing is BLOCKED.
Connection: parameter, then DW_BASE_URL / DW_API_TOKEN / DW_MCP_TOKEN, then launchSettings.json discovery (Dw.Api.psm1). Secrets the input names by reference come from DW_RECIPE_SECRETS (a JSON object); persona probes read DW_PERSONA_CREDENTIALS. No token, secret or response body is printed or written to the report. The TLS bypass applies to a loopback base URL or after -AllowSelfSignedCertificate.
.PARAMETER Recipe
Recipe id (users.accounts) or path to a recipe file.
.PARAMETER InputPath
Customer data file matching assets/recipe-input.schema.json.
.PARAMETER Apply
Write. Without it, or with -WhatIf, nothing is written.
.PARAMETER BaseUrl
Target URL, otherwise DW_BASE_URL or launchSettings.json discovery.
.PARAMETER ApiToken
Management API credential, otherwise DW_API_TOKEN.
.PARAMETER McpToken
MCP credential, otherwise DW_MCP_TOKEN.
.PARAMETER McpOnly
Use the MCP tools only, as the in-product agent would.
.PARAMETER Surfaces
Permitted surfaces in preference order. Default mcp, admin-api, dwapi, sql.
.PARAMETER AllowSql
Permit local SQL reads; needs -SqlServer and -Database of a local install. SQL never writes.
.PARAMETER SqlServer
Local SQL server (integrated authentication).
.PARAMETER Database
Local database name.
.PARAMETER LedgerBuildFile
Ledger build declaration with its lock; with -Manifest the recipe's ledger checks run, and its build values feed {build.*}.
.PARAMETER Manifest
Ledger release manifest for -LedgerBuildFile.
.PARAMETER SolutionPath
Local solution root; lets a recycle debt run Restart-DwHost.ps1.
.PARAMETER ReportPath
Optional JSON report: steps, checks and summary, no values.
.PARAMETER AllowSelfSignedCertificate
Explicit TLS opt-in for a development endpoint that is not loopback.
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwRecipe.ps1 -Recipe users.accounts -InputPath ./recipe-input.json
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwRecipe.ps1 -Recipe content.pages -InputPath ./recipe-input.json -Apply -ReportPath ./recipe-report.json
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Recipe,
    [Parameter(Mandatory)][string]$InputPath,
    [switch]$Apply,
    [string]$BaseUrl, [string]$ApiToken, [string]$McpToken,
    [switch]$McpOnly,
    [ValidateSet('mcp', 'admin-api', 'dwapi', 'sql')][string[]]$Surfaces = @('mcp', 'admin-api', 'dwapi', 'sql'),
    [switch]$AllowSql, [string]$SqlServer, [string]$Database,
    [string]$LedgerBuildFile, [string]$Manifest,
    [string]$SolutionPath,
    [string]$ReportPath,
    [switch]$AllowSelfSignedCertificate
)
$ErrorActionPreference = 'Stop'
foreach ($file in @('Ledger.Core.ps1', 'Ledger.Sql.ps1', 'Ledger.Transport.ps1', 'Recipe.Core.ps1', 'Recipe.Transport.ps1', 'Recipe.Write.ps1', 'Recipe.Steps.ps1', 'Recipe.Verify.ps1', 'Recipe.Debts.ps1')) { . (Join-Path $PSScriptRoot $file) }
$assets = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
$recipeId = $Recipe
$run = @{lines = [Collections.Generic.List[string]]::new(); checks = [Collections.Generic.List[object]]::new(); steps = [Collections.Generic.List[object]]::new(); planned = [Collections.Generic.List[string]]::new(); blocked = 0; changed = $false; results = @{}}
$applied = $false
try {
    $recipePath = Resolve-RecipeFile $Recipe $assets
    $doc = Read-LedgerJson $recipePath (Join-Path $assets 'recipe.schema.json')
    $recipeId = $doc.id
    $forbidden = @(Test-RecipeForbidden $doc)
    if ($forbidden.Count) { throw (New-RecipeFault ('The recipe carries what no recipe may: ' + ($forbidden -join '; '))) }
    $data = Read-LedgerJson $InputPath (Join-Path $assets 'recipe-input.schema.json')
    if (-not $data.Contains($doc.inputs.section)) { throw (New-RecipeFault "Runner input: the input file has no '$($doc.inputs.section)' section.") }
    $section = $data[$doc.inputs.section]
    foreach ($path in @($doc.inputs.required)) { if (-not (Get-RecipeValue $section $path).found) { throw (New-RecipeFault "Runner input: section '$($doc.inputs.section)' has no '$path'.") } }
    $build = @{}
    if ($LedgerBuildFile) {
        $declared = Read-LedgerJson $LedgerBuildFile (Join-Path $assets 'build.schema.json')
        foreach ($k in @('areaId', 'defaultLanguage', 'pimShop')) { if ($declared.Contains($k)) { $build[$k] = $declared[$k] } }
    } elseif ($data.Contains('build')) { $build = $data.build }
    $secrets = Read-RecipeSecrets $env:DW_RECIPE_SECRETS
    $applied = $Apply -and $PSCmdlet.ShouldProcess("recipe $recipeId", 'apply the recipe writes')
    if (-not @($doc.provenOn).Count) { $run.lines.Add("NOTE ${recipeId}: unproven (provenOn is empty): no release has measured this recipe end to end") }
    $run.lines.Add("NOTE ${recipeId}: $(if ($applied) { 'apply' } else { 'verify-only, nothing is written' })")
    if ($McpOnly -and -not $doc.modes.mcpOnly.usable) { $run.lines.Add("NOTE ${recipeId}: declared not usable MCP-only: $($doc.modes.mcpOnly.reason)") }

    Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
    $state = Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -McpToken $McpToken -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    Assert-DwConnection | Out-Null
    $insecure = [bool]($AllowSelfSignedCertificate -or $state.BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)')
    $script:RecipeTarget = @{baseUrl = $state.BaseUrl; insecure = $insecure}
    $script:LedgerTarget = $script:RecipeTarget
    $registry = Read-LedgerJson (Join-Path $assets 'handlers.json')
    $cap = Get-RecipeCapabilities -Surfaces $Surfaces -McpOnly:$McpOnly -McpToken $state.McpToken -ApiToken $state.ApiToken -AllowSql:$AllowSql -SqlServer $SqlServer -Database $Database
    foreach ($e in $cap.errors) { $run.lines.Add("NOTE ${recipeId}: $e") }
    $run += @{recipeId = $recipeId; section = $section; build = $build; secrets = $secrets; cap = $cap; registry = $registry; apply = $applied
        baseUrl = $state.BaseUrl; apiToken = $state.ApiToken; mcpToken = $state.McpToken; solutionPath = $SolutionPath; ledgerBuild = $LedgerBuildFile; manifest = $Manifest; pollIntervalMs = 1000}

    foreach ($step in $doc.steps) { Invoke-RecipeStep $step $run }
    if (@($doc.debts).Count) {
        if ($applied -and $run.changed) { foreach ($debt in $doc.debts) { Invoke-RecipeDebt $debt $run } }
        else { $run.lines.Add("NOTE ${recipeId}: debts not run ($(if ($applied) { 'nothing changed' } else { 'verify-only' })): " + ($doc.debts -join ', ')) }
    }
    foreach ($probe in @($doc.verify.probes)) { Invoke-RecipeProbe $probe $run }
    Invoke-RecipeLedger $doc $run
} catch {
    Write-Verbose $_.ScriptStackTrace
    # A named contract or input fault is printed; anything else may carry a host, token or body, so it stays generic.
    $exception = $_.Exception
    $cause = if ($exception -is [IO.InvalidDataException] -or $exception -is [InvalidOperationException]) { $exception.Message } else { 'Check the recipe, the input, the connection and the grants; -Verbose shows where it stopped.' }
    $run.checks.Add([ordered]@{name = 'recipe'; result = 'FAIL'; reason = $cause})
    $run.lines.Add("FAIL recipe: $cause")
}
$passed = @($run.checks | Where-Object { $_.result -eq 'PASS' }).Count
$total = $run.checks.Count
$ok = $total -gt 0 -and $passed -eq $total -and $run.blocked -eq 0
foreach ($line in $run.lines) { Write-Output $line }
Write-Output "${recipeId}: $passed of $total checks passed"
if ($ReportPath) {
    $report = [ordered]@{schema = 1; recipe = $recipeId; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); mode = $(if ($applied) { 'apply' } else { 'verify' })
        steps = $run.steps.ToArray(); checks = $run.checks.ToArray(); plannedProbes = $run.planned.ToArray(); blocked = $run.blocked; passed = $passed; total = $total; result = $(if ($ok) { 'PASS' } else { 'FAIL' })}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
}
if ($ok) { exit 0 }
exit 1

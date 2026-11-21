<#
.SYNOPSIS
READ-ONLY. List the recipes for a ledger function or an area: functions, modes and proven state.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Reads assets/recipes/<area>/<id>.json only; no target, no network. Each recipe prints one block: its id and name, the functions it delivers, its modes (MCP-only, hosted, local, what it does on a layer-delivered build), the planned bindings it still carries, and "unproven" while provenOn is empty. When nothing matches, the output says "no recipe" plainly and the exit code is 0. A recipe file that does not match the schema prints INVALID and exits 1.
.PARAMETER Function
Ledger function id, such as users.accounts.
.PARAMETER Area
Recipe area folder, such as users or content.
.EXAMPLE
pwsh -NoProfile -File scripts/Find-DwRecipe.ps1 -Function users.user-groups
.EXAMPLE
pwsh -NoProfile -File scripts/Find-DwRecipe.ps1
#>
#Requires -Version 7.0
[CmdletBinding()]
param([string]$Function, [string]$Area)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ledger.Core.ps1')
$assets = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
$root = Join-Path $assets 'recipes'
$invalid = $false; $shown = 0
$files = if (Test-Path -LiteralPath $root) { @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.json' -File } | Sort-Object FullName) } else { @() }
foreach ($file in $files) {
    if ($Area -and $file.Directory.Name -ne $Area) { continue }
    try { $doc = Read-LedgerJson $file.FullName (Join-Path $assets 'recipe.schema.json') }
    catch { Write-Output "INVALID $($file.Directory.Name)/$($file.Name): $($_.Exception.Message)"; $invalid = $true; continue }
    if ($Function -and $Function -cnotin @($doc.functions)) { continue }
    $shown++
    $modes = $doc.modes
    $planned = @(foreach ($step in $doc.steps) {
        foreach ($b in @(if ($step.find) { $step.find.bindings })) { if ($b.status -eq 'planned') { "$($step.id) find $($b.surface)" } }
        foreach ($b in @($step.bindings)) { if ($b.status -eq 'planned') { "$($step.id) write $($b.surface)" } }
    }) + @(foreach ($probe in $doc.verify.probes) { foreach ($b in $probe.bindings) { if ($b.status -eq 'planned') { "probe $($probe.id) $($b.surface)" } } })
    $proven = if (@($doc.provenOn).Count) { (@($doc.provenOn | ForEach-Object { "dw $($_.dwVersion) mcp $($_.mcpVersion)" }) -join '; ') } else { 'unproven' }
    Write-Output "$($doc.id)  $($doc.name)"
    Write-Output "  functions:      $(@($doc.functions) -join ', ')"
    Write-Output "  skill:          $($doc.skill)"
    Write-Output "  mcpOnly:        $(if ($modes.mcpOnly.usable) { 'yes' } else { 'no - ' + $modes.mcpOnly.reason })"
    Write-Output "  hosted:         $(if ($modes.hosted.usable) { 'yes' } else { 'no - ' + $modes.hosted.reason })"
    Write-Output "  local:          yes"
    Write-Output "  layerDelivered: $($modes.layerDelivered)"
    Write-Output "  planned:        $(if ($planned.Count) { $planned -join ', ' } else { 'none' })"
    Write-Output "  proven:         $proven"
}
if ($shown -eq 0) {
    $scope = if ($Function) { "for function $Function" } elseif ($Area) { "in area $Area" } else { 'in this skill' }
    Write-Output "no recipe $scope"
}
if ($invalid) { exit 1 }
exit 0

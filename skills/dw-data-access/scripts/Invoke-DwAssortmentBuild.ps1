<#
.SYNOPSIS
    WRITES: flags an assortment for rebuild, builds it, waits for the build to
    drain, and gates activation on a non-zero item count. Dry run by default;
    -Apply writes.

.DESCRIPTION
    The rebuild step is the number one footgun on this surface, in three
    separate ways, and this script is the sequence that closes all three.

      1. A MEMBERSHIP WRITE DOES NOT FLAG ANYTHING.
         assign_products_to_assortment / remove_products_from_assortment write
         the relation rows and leave AssortmentRebuildRequired false and
         AssortmentLastBuildDate unchanged — relation writes and the rebuild
         flag are independent operations in the underlying service, and the
         assign call gives no signal either way. Every membership batch owes an
         explicit flag_assortments_for_rebuild plus build_assortments.
      2. FLAG IS NOT BUILD. flag_assortments_for_rebuild only marks the
         assortment dirty. build_assortments does the work and may run
         asynchronously, so an assortment is never ready right after an assign
         call. The only wait primitive is polling get_assortments_for_build
         until this assortment is no longer in it; no assortment-specific
         wait tool is registered.
      3. BOTH TOOLS TAKE AN ARRAY OF REQUEST OBJECTS, each carrying one
         assortmentId — not the flat {"assortmentIds":[...]} that reads
         naturally from the tool name. The flat shape fails with the bare
         "An error occurred invoking '<tool>'.", which names no argument and
         does not distinguish a wrong shape from a wrong id.

    THE PRE-ACTIVATION COUNT GATE. An assortment bound to a PIM data-model
    group (a data-model or data-model-folder group, not a catalogue group)
    carries no EcomGroupProductRelation rows and builds to ZERO items — and
    activating a zero-item assortment does not "add nothing", it takes the
    whole catalogue away from everyone who holds it, because a holder's
    visible set becomes the empty intersection. So -ActivateWhenNonEmpty
    activates only after the built item count is proven non-zero, and refuses
    otherwise.

    The count itself has no tool behind it: check_assortment_product_access
    answers true for every product, every user and anonymous alike, and no
    tool projects the materialised item set. The count is
    SELECT COUNT(*) FROM EcomAssortmentItems, LOCAL INSTALLS ONLY. On a hosted
    install, pass -SkipCountGate and compare the storefront catalogue rendered
    to a holder against the one rendered to a non-holder instead.

    Setting EcomAssortment.AssortmentRebuildRequired in SQL does NOT reach the
    builder — AssortmentService.GetAssortmentsForBuild() reads an in-process
    cache with no public flush — so this script never flags by SQL. SQL stays a
    read path here.

    Owning reference: dw-data-access/references/recipes-commerce.md
    ("Flag, build and gate an assortment"); the surface table, the shop-relation
    trap and the cart-pruning trap are in dw-commerce-b2b.

.PARAMETER AssortmentId
    One or more assortment ids to flag and build.

.PARAMETER SkipFlag
    Build without flagging first. Only when something else already flagged
    them; get_assortments_for_build is the read that proves it.

.PARAMETER ActivateWhenNonEmpty
    After a successful build, set the assortment active — but only once the
    built item count is proven non-zero.

.PARAMETER SkipCountGate
    Do not read the item count. On a hosted install there is no SQL surface,
    so the count is unreachable; -ActivateWhenNonEmpty is then refused,
    because the gate is the whole point.

.PARAMETER TimeoutMinutes
    Poll deadline for the build to drain out of get_assortments_for_build.

.PARAMETER Apply
    Write. Without it the sequence is printed and nothing runs.

.PARAMETER BaseUrl / McpToken / ApiToken / SolutionPath
    Connection; else the DW_* env vars, else launchSettings.json discovery.

.PARAMETER ConnectionString
    Local SQL connection for the count gate; else $env:DW_SQL_CONNECTION.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwAssortmentBuild.ps1 -AssortmentId ASRT1

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-DwAssortmentBuild.ps1 -AssortmentId ASRT1 -ActivateWhenNonEmpty -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string[]]$AssortmentId,
    [switch]$SkipFlag,
    [switch]$ActivateWhenNonEmpty,
    [switch]$SkipCountGate,
    [int]$TimeoutMinutes = 15,
    [switch]$Apply,
    [string]$BaseUrl,
    [string]$McpToken,
    [string]$ApiToken,
    [string]$SolutionPath,
    [string]$ConnectionString
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop
Connect-Dw -BaseUrl $BaseUrl -McpToken $McpToken -ApiToken $ApiToken -SolutionPath $SolutionPath | Out-Null
Assert-DwConnection | Out-Null

if ($ActivateWhenNonEmpty -and $SkipCountGate) {
    Write-Error ('-ActivateWhenNonEmpty with -SkipCountGate is refused: the count IS the gate. ' +
        'Activating a zero-item assortment takes the whole catalogue away from everyone who holds ' +
        'it, because a holder visible set becomes the empty intersection. On a hosted install, ' +
        'build here and activate only after comparing the storefront catalogue rendered to a ' +
        'holder against the one rendered to a non-holder.') -ErrorAction Continue
    exit 1
}

# Both tools take an ARRAY OF REQUEST OBJECTS, one assortmentId each.
$requests = @($AssortmentId | ForEach-Object { @{ assortmentId = $_ } })

Write-Host 'Sequence:'
if (-not $SkipFlag) { Write-Host "  1. flag_assortments_for_rebuild  {requests:[{assortmentId} x $($requests.Count)]}" }
else { Write-Host '  1. flag SKIPPED (-SkipFlag) — prove it with get_assortments_for_build.' }
Write-Host "  2. build_assortments             {requests:[{assortmentId} x $($requests.Count)]}"
Write-Host "  3. poll get_assortments_for_build until these ids drain (deadline $TimeoutMinutes min)"
if (-not $SkipCountGate) { Write-Host '  4. count EcomAssortmentItems per assortment (SQL, local installs only)' }
if ($ActivateWhenNonEmpty) { Write-Host '  5. save_assortments active = true, ONLY for assortments whose count is non-zero' }

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN — nothing written. Re-run with -Apply.'
    exit 0
}
if (-not $PSCmdlet.ShouldProcess(($AssortmentId -join ', '), 'flag, build, wait, count-gate')) { exit 0 }

Write-Host ''
if (-not $SkipFlag) {
    Invoke-DwMcp -Tool 'flag_assortments_for_rebuild' -Arguments @{ requests = $requests } | Out-Null
    Write-Host "Flagged $($requests.Count) assortment(s) for rebuild."
}
Invoke-DwMcp -Tool 'build_assortments' -Arguments @{ requests = $requests } -TimeoutSec 900 | Out-Null
Write-Host 'build_assortments accepted — it may run asynchronously, so this is not yet proof.'

# The only wait primitive: poll until these ids are no longer pending.
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$pending = @($AssortmentId)
do {
    Start-Sleep -Seconds 5
    $forBuild = Invoke-DwMcp -Tool 'get_assortments_for_build'
    $ids = @($forBuild.assortments ?? $forBuild.data ?? $forBuild) |
        ForEach-Object { $_.assortmentId ?? $_.id ?? $_ }
    $pending = @($AssortmentId | Where-Object { $ids -contains $_ })
    Write-Host ("  still pending: {0}" -f $(if ($pending.Count) { $pending -join ', ' } else { '(none)' }))
} while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline)

if ($pending.Count -gt 0) {
    Write-Host ''
    Write-Host "TIMEOUT: $($pending -join ', ') still pending after $TimeoutMinutes minutes."
    Write-Host 'Do NOT report the assortment as ready, and do NOT activate it. Poll again later.'
    exit 1
}
Write-Host 'Build drained out of get_assortments_for_build.'

if ($SkipCountGate) {
    Write-Host ''
    Write-Host 'Count gate SKIPPED. Before activating, compare the storefront catalogue rendered to a'
    Write-Host 'holder against the one rendered to a non-holder — a zero-item assortment does not add'
    Write-Host 'nothing, it takes the whole catalogue away from everyone who holds it.'
    exit 0
}

Write-Host ''
$zero = [System.Collections.Generic.List[string]]::new()
foreach ($id in $AssortmentId) {
    $count = Get-DwSqlScalar -ConnectionString $ConnectionString -Sql (
        "SELECT COUNT(*) FROM EcomAssortmentItems WHERE AssortmentItemAssortmentId = '" + ($id -replace "'", "''") + "'")
    $shops = Get-DwSqlScalar -ConnectionString $ConnectionString -Sql (
        "SELECT COUNT(*) FROM EcomAssortmentShopRelations WHERE AssortmentShopRelationAssortmentId = '" + ($id -replace "'", "''") + "'")
    Write-Host ("{0}: {1} built item(s), {2} shop relation(s)." -f $id, $count, $shops)
    if ([int]$count -eq 0) {
        $zero.Add($id)
        Write-Host '  ZERO items. The usual cause is an assortment bound to a PIM data-model group, which'
        Write-Host '  carries no EcomGroupProductRelation rows. Do not activate it.'
    }
    if ([int]$shops -gt 0) {
        Write-Host '  NOTE: a shop relation is present. The build unions the relation sets, so one shop'
        Write-Host '  relation replaces the intended scope and the item count reads as the whole catalogue.'
    }
}

if (-not $ActivateWhenNonEmpty) {
    if ($zero.Count -gt 0) { exit 1 }
    exit 0
}

$activate = @($AssortmentId | Where-Object { $zero -notcontains $_ })
if ($activate.Count -eq 0) {
    Write-Host ''
    Write-Host 'Nothing activated: every assortment built to zero items.'
    exit 1
}
foreach ($id in $activate) {
    $current = Invoke-DwMcp -Tool 'get_assortment' -Arguments @{ assortmentId = $id }
    $model = $current.assortment ?? $current
    $model = Remove-DwDisplayOnlyMember $model
    $model | Add-Member -NotePropertyName 'active' -NotePropertyValue $true -Force
    Invoke-DwMcp -Tool 'save_assortments' -Arguments @{ assortments = @($model) } | Out-Null
    Write-Host "Activated $id."
}
if ($zero.Count -gt 0) {
    Write-Host "Left inactive (zero items): $($zero -join ', ')."
    exit 1
}
exit 0

<#
.SYNOPSIS
WRITES: cache flushes, index builds, assortment builds and a host recycle that a recipe owes after it changed something.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. A debt is one of a fixed list, each paid by an existing shipped function or script, never by code from the recipe: flush:<service> is Clear-DwServiceCache; index:<repository>/<index> is Build-DwProductIndex.ps1 with the builder resolved from IndexBuildersByRepositoryAndIndexName, or on MCP build_product_index and wait_for_product_index gated on a non-zero documentCount; assortments is Invoke-DwAssortmentBuild.ps1 over the section's assortmentIds, or on MCP build_assortments gated on each last build date moving; recycle is Restart-DwHost.ps1 for a local host given -SolutionPath. A debt this run cannot pay is OPEN with the instruction that pays it, never skipped; an index the target does not have (get_index_repositories) is a NOTE.
.EXAMPLE
. ./Recipe.Debts.ps1
#>
#Requires -Version 7.0
function Get-RecipeIndexBuild {
    # The build name to post: the one builder the index declares, or "Full" when it is among several. $null when undecided.
    param([string]$Repository, [string]$Index)
    $query = 'IndexBuildersByRepositoryAndIndexName?Repository=' + [Uri]::EscapeDataString($Repository) + '&IndexName=' + [Uri]::EscapeDataString($Index)
    $data = ConvertTo-RecipeData (Invoke-DwApi $query)
    $list = foreach ($path in @('model.data', 'model', 'data', '$')) { $v = Get-RecipeValue $data $path; if ($v.found -and $v.value -is [Collections.IList]) { , $v.value; break } }
    $names = @(@($list) | ForEach-Object { if ($_ -is [Collections.IDictionary]) { (Get-RecipeMember $_ 'name').value } } | Where-Object { $_ })
    if ($names.Count -eq 1) { return [string]$names[0] }
    if ('Full' -cin $names) { return 'Full' }
    return $null
}
function Invoke-RecipeMcpIndexBuild {
    # The in-product build: both names always passed (each default addresses nothing), gated on documents, not on "completed".
    param([string]$Repository, [string]$Index, $Run)
    $arguments = @{repositoryName = $Repository; indexName = $Index}
    $null = Invoke-RecipeMcpCall 'build_product_index' $arguments $Run.cap 900
    $null = Invoke-RecipeMcpCall 'wait_for_product_index' $arguments $Run.cap 900
    $status = Invoke-RecipeMcpCall 'get_product_index_status' $arguments $Run.cap 60
    $count = Get-RecipeValue $status 'documentCount'
    return ($count.found -and (Test-RecipeNumber $count.value) -and $count.value -gt 0)
}
function Invoke-RecipeMcpAssortmentBuild {
    # build_assortments over the ids, then get_assortments: every id listed, no rebuild owed, and a last build date that moved.
    param([string[]]$Ids, $Run)
    $before = @{}
    foreach ($row in @((Get-RecipeValue (Invoke-RecipeMcpCall 'get_assortments' @{} $Run.cap 60) 'data').value)) { $before[[string]$row.id] = [string]$row.lastBuildDate }
    $answer = Invoke-RecipeMcpCall 'build_assortments' @{requests = @($Ids | ForEach-Object { @{assortmentId = $_} })} $Run.cap 900
    $failed = Get-RecipeValue $answer 'failed'
    if ($failed.found -and (Test-RecipeNumber $failed.value) -and $failed.value -gt 0) { return $false }
    $after = @{}
    foreach ($row in @((Get-RecipeValue (Invoke-RecipeMcpCall 'get_assortments' @{} $Run.cap 60) 'data').value)) { $after[[string]$row.id] = $row }
    foreach ($id in $Ids) {
        $row = $after[[string]$id]
        if (-not $row -or $row.rebuildRequired -or -not $row.lastBuildDate -or [string]$row.lastBuildDate -eq $before[[string]$id]) { return $false }
    }
    return $true
}
function Test-RecipeMcpDebtTools {
    param([string[]]$Tools, $Run)
    foreach ($tool in $Tools) {
        $kind = if ($tool -like 'get_*') { 'read' } else { 'write' }
        if (Get-RecipeSurfaceFault @{surface = 'mcp'; status = 'implemented'} $tool $kind $Run.cap $Run.registry) { return $false }
    }
    return $true
}
function Invoke-RecipeDebt {
    param([string]$Debt, $Run)
    $name = "debt/$Debt"
    $data = Join-Path $PSScriptRoot '../../dw-data-access/scripts'
    try {
        if ($Debt -match '^flush:(?<service>.+)$') {
            if (-not $Run.cap.admin) { Add-RecipeCheck $Run $name 'OPEN' "owed: no MCP tool refreshes $($Matches['service']); refresh it with Management API CacheInformationRefresh (DW_API_TOKEN) or under Settings > System information > Cache"; return }
            Clear-DwServiceCache -CacheTypeName $Matches['service']
            Add-RecipeCheck $Run $name 'PASS'; return
        }
        if ($Debt -match '^index:(?<repo>[^/]+)/(?<index>.+)$') {
            $repo = $Matches['repo']; $index = $Matches['index']
            if (Test-RecipeMcpDebtTools @('get_index_repositories') $Run) {
                # A recipe names every repository a platform may carry the index under; one this target lacks owes nothing.
                $listed = Invoke-RecipeMcpCall 'get_index_repositories' @{} $Run.cap 60
                $known = @(@((Get-RecipeValue $listed 'data').value) | Where-Object { [string]$_.repository -ceq $repo -and $index -cin @($_.indexes) })
                if ($known.Count -eq 0) { $Run.lines.Add("NOTE ${name}: not owed, the target has no index $repo/$index"); return }
            }
            if ($Run.cap.admin) {
                $build = Get-RecipeIndexBuild $repo $index
                if (-not $build) { Add-RecipeCheck $Run $name 'OPEN' "owed: the builder of $repo/$index is not one name or Full; build it with Build-DwProductIndex.ps1 -BuildName <builder>"; return }
                $arguments = @('-Repository', $repo, '-IndexName', $index, '-BuildName', $build, '-SkipCacheFlush', '-BaseUrl', $Run.baseUrl)
                $code = Invoke-RecipeChildScript (Join-Path $data 'Build-DwProductIndex.ps1') $arguments $Run
                if ($code -eq 0) { Add-RecipeCheck $Run $name 'PASS' } else { Add-RecipeCheck $Run $name 'FAIL' "Build-DwProductIndex.ps1 saw no fresh success for $repo/$index (build $build); poll the status, never re-fire" }
                return
            }
            if (Test-RecipeMcpDebtTools @('build_product_index', 'wait_for_product_index', 'get_product_index_status') $Run) {
                if (Invoke-RecipeMcpIndexBuild $repo $index $Run) { Add-RecipeCheck $Run $name 'PASS' }
                else { Add-RecipeCheck $Run $name 'FAIL' "after the MCP build $repo/$index reports no documents; the tool may not reach this index, build it with Management API BuildIndex" }
                return
            }
            Add-RecipeCheck $Run $name 'OPEN' "owed: no surface here builds $repo/$index; run Build-DwProductIndex.ps1 (Management API) or build_product_index and wait_for_product_index with both names"; return
        }
        if ($Debt -eq 'assortments') {
            $ids = @((Get-RecipeValue $Run.section 'assortmentIds').value | Where-Object { $_ })
            if (-not $ids.Count) { Add-RecipeCheck $Run $name 'OPEN' 'owed: the input section declares no assortmentIds; flag and build them with Invoke-DwAssortmentBuild.ps1'; return }
            if (-not $Run.cap.admin) {
                if (-not (Test-RecipeMcpDebtTools @('build_assortments', 'get_assortments') $Run)) { Add-RecipeCheck $Run $name 'OPEN' 'owed: no surface here builds assortments; run Invoke-DwAssortmentBuild.ps1 (Management API) or build_assortments'; return }
                # The in-product build answers when it is done; its evidence is each assortment's lastBuildDate moving with no rebuild left owed.
                if (Invoke-RecipeMcpAssortmentBuild $ids $Run) { Add-RecipeCheck $Run $name 'PASS' } else { Add-RecipeCheck $Run $name 'FAIL' 'after build_assortments an assortment still owes a rebuild or kept its last build date' }
                return
            }
            $arguments = @('-AssortmentId') + $ids + @('-Apply', '-SkipCountGate', '-BaseUrl', $Run.baseUrl)
            $code = Invoke-RecipeChildScript (Join-Path $data 'Invoke-DwAssortmentBuild.ps1') $arguments $Run
            if ($code -eq 0) { Add-RecipeCheck $Run $name 'PASS' } else { Add-RecipeCheck $Run $name 'FAIL' 'Invoke-DwAssortmentBuild.ps1 did not finish the build' }
            return
        }
        if ($Debt -eq 'recycle') {
            $local = [regex]::Match([string]$Run.baseUrl, '^https?://(localhost|127\.0\.0\.1):(?<port>\d+)')
            if (-not ($Run.solutionPath -and $local.Success)) {
                # No Management API command or MCP tool recycles the application; on Dynamicweb Cloud the control file recycles it.
                Add-RecipeCheck $Run $name 'OPEN' 'owed: recycle the host (a local install: dw-demo-base Restart-DwHost.ps1, or pass -SolutionPath here; a Dynamicweb Cloud install: upload Files/System/CloudHosting/recycle.txt and see it consumed; any other hosted install: the operator recycles the application pool; no Management API command or MCP tool recycles the application), then run this recipe again without -Apply'; return
            }
            $arguments = @('-Action', 'Restart', '-Port', $local.Groups['port'].Value, '-SolutionPath', $Run.solutionPath, '-Reason', "recipe $($Run.recipeId) owes a recycle")
            $code = Invoke-RecipeChildScript (Join-Path $PSScriptRoot '../../dw-demo-base/scripts/Restart-DwHost.ps1') $arguments $Run
            if ($code -eq 0) { Add-RecipeCheck $Run $name 'PASS' } else { Add-RecipeCheck $Run $name 'FAIL' 'Restart-DwHost.ps1 did not bring the host back; read its log' }
            return
        }
        Add-RecipeCheck $Run $name 'OPEN' 'not a debt this runner pays'
    } catch {
        Write-Verbose $_.ScriptStackTrace
        if ($_.Exception -is [InvalidOperationException]) { Add-RecipeCheck $Run $name 'OPEN' $_.Exception.Message }
        else { Add-RecipeCheck $Run $name 'FAIL' 'the debt call failed; no response body is printed (-Verbose shows where)' }
    }
}

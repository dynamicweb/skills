<#
.SYNOPSIS
    WRITES: rebuilds a Lucene index on the target host (flushes product caches
    first). No product data is changed.

.DESCRIPTION
    The enforced form of the flush-then-build-then-poll recipe. Steps:
      1. Flush the three caches the index builder reads through
         (ProductService, ProductCategoryFieldValueService,
         ProductCategoryService) — skipping this after a value write bakes the
         stale value into the index. -SkipCacheFlush only for pure structural
         creates.
      2. POST BuildIndex. `synchronous:true` does NOT block, and on DW 10.28.x
         a long build outlives the HTTP client: a severed response is caught
         and polling continues — the build is NEVER re-fired on a timeout (a
         retry queues a second full rebuild behind a succeeding one).
      3. Poll IndexStatusByRepositoryAndIndexName until State=Success with a
         LastRun newer than this run's POST (a prior build satisfies a
         state-only check). On 10.28.x, where that verb answers 400, the poll
         falls back to IndexStatusesAll. State=Error is terminal only when the
         instance's LifecycleState is Failed — a never-built index reports
         Error while its first build is still writing.

    Owning reference: dw-search-indexing/references/index-management.md
    ("Rebuild after mutations"); the multi-instance two-pass rule is in
    dw-demo-swift/references/integrity-sweep.md — pass -Passes 2 for a
    2-instance index (one instance refreshes per run).

.PARAMETER Repository
    Repository name — solution-specific; read it from
    wwwroot/Files/System/Repositories/ (a stock Swift solution ships
    ProductsFrontend/ProductsBackend, not Products).

.PARAMETER IndexName
    Index name including .index (e.g. Products.index).

.PARAMETER BuildName
    Build name; default Full. When the repository XML declares a different
    <Build Name>, use that value (integrity-sweep rule).

.PARAMETER Passes
    Build passes; default 1. Use 2 for a multi-instance index — one instance
    refreshes per run, and a single pass leaves the sibling stale.

.PARAMETER SkipCacheFlush
    Skip the read-through cache flush (only for pure structural creates).

.PARAMETER TimeoutMinutes
    Poll deadline per pass. On timeout the script exits 1 WITHOUT retrying —
    on 10.28.x a long build may still be completing; poll again later.

.PARAMETER BaseUrl
    Host base URL; else $env:DW_BASE_URL, else launchSettings.json discovery.

.PARAMETER ApiToken
    Management API bearer token; else $env:DW_API_TOKEN.

.PARAMETER SolutionPath
    Solution folder for launchSettings.json discovery.

.EXAMPLE
    pwsh -NoProfile -File scripts/Build-DwProductIndex.ps1 -Repository Products -IndexName Products.index

.EXAMPLE
    pwsh -NoProfile -File scripts/Build-DwProductIndex.ps1 -Repository ProductsFrontend -IndexName Products.index -Passes 2
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$IndexName,
    [string]$BuildName = 'Full',
    [ValidateRange(1, 2)][int]$Passes = 1,
    [switch]$SkipCacheFlush,
    [int]$TimeoutMinutes = 20,
    [string]$BaseUrl,
    [string]$ApiToken,
    [string]$SolutionPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
$state = Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -SolutionPath $SolutionPath
Assert-DwConnection | Out-Null

function Get-IndexStatusModel {
    # 10.26.x verb first; 10.28.x answers 400 there and serves IndexStatusesAll.
    try {
        return (Invoke-DwApi ("IndexStatusByRepositoryAndIndexName?Repository=$Repository&IndexName=$IndexName")).model
    }
    catch {
        $all = (Invoke-DwApi 'IndexStatusesAll').model
        $hit = @($all) | Where-Object { $_.repository -eq $Repository -and $_.indexName -eq $IndexName } | Select-Object -First 1
        if (-not $hit) { throw "No index status for $Repository/$IndexName on either status verb — check the names against wwwroot/Files/System/Repositories/." }
        return $hit
    }
}

if (-not $PSCmdlet.ShouldProcess("$($state.BaseUrl) $Repository/$IndexName", "flush caches and build index ($BuildName, $Passes pass(es))")) {
    exit 0
}

if (-not $SkipCacheFlush) {
    Clear-DwServiceCache -CacheTypeName @(
        'Dynamicweb.Ecommerce.Products.ProductService',
        'Dynamicweb.Ecommerce.Products.Categories.ProductCategoryFieldValueService',
        'Dynamicweb.Ecommerce.Products.Categories.ProductCategoryService'
    )
    Write-Host 'Flushed the 3 read-through product caches.'
}
else {
    Write-Host 'Cache flush SKIPPED — valid only for pure structural creates.'
}

foreach ($pass in 1..$Passes) {
    $posted = Get-Date
    try {
        Invoke-DwApi 'BuildIndex' -Body @{ Repository = $Repository; IndexName = $IndexName; BuildName = $BuildName } -TimeoutSec 900 | Out-Null
    }
    catch {
        # 10.28.x: the build is synchronous and outlives the client — the
        # timeout severs the RESPONSE, not the build. Poll; never re-fire.
        Write-Host "BuildIndex response severed (expected on long builds): $($_.Exception.Message)"
    }

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds 5
        $status = Get-IndexStatusModel
        Write-Host ("Pass {0}  State: {1}  LastRun: {2}" -f $pass, $status.state, $status.lastRun)
        if ($status.state -eq 'Error') {
            $instanceName = $IndexName -replace '\.index$', ''
            try {
                $inst = (Invoke-DwApi ("InstanceStatusByName?Repository=$Repository&IndexName=$IndexName&InstanceName=$instanceName")).model
                if ($inst.lifecycleState -eq 'Failed') {
                    Write-Host 'FAILED: instance LifecycleState=Failed — the build itself failed; inspect the index logs in admin.'
                    exit 1
                }
                # Error while the first build is still writing — keep polling.
            }
            catch { }  # instance verb absent on some versions — keep polling on the index state alone
        }
        $fresh = ($status.state -eq 'Success' -and $status.lastRun -and ([datetime]$status.lastRun) -gt $posted)
    } while (-not $fresh -and (Get-Date) -lt $deadline)

    if (-not $fresh) {
        Write-Host "TIMEOUT: pass $pass saw no fresh Success within $TimeoutMinutes minutes."
        Write-Host 'A timeout is NOT proof of failure (10.28.x builds outlive clients) — poll the status again later; NEVER re-fire the build.'
        exit 1
    }
    Write-Host ("Pass {0} complete in {1:n0}s (fresh Success)." -f $pass, ((Get-Date) - $posted).TotalSeconds)
}
exit 0

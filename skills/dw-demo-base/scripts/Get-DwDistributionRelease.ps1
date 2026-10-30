<#
.SYNOPSIS
WRITES: a public Distribution checkout, verified bacpac and release receipt under DemoRoot.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Refuses unproven or mismatched releases.
.PARAMETER DemoRoot
Destination demo directory. No machine path is assumed.
.PARAMETER Edition
Edition registered in INDEX.json; swift-demo is the supported storefront.
.PARAMETER Apply
Clone, download and write. Without this switch only print the plan.
.EXAMPLE
pwsh -NoProfile -File scripts/Get-DwDistributionRelease.ps1 -DemoRoot $demo -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[string]$Edition='swift-demo',[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Root,'Resolve public release and download verified bacpac')) { Write-Host 'Plan: clone or fast-forward Distribution main, verify gateProven, download and hash bacpac.'; exit 0 }
    New-Item -ItemType Directory -Force -Path $p.Notes | Out-Null
    if (Test-Path (Join-Path $p.Distribution '.git')) {
        $origin=& git -C $p.Distribution remote get-url origin
        if($LASTEXITCODE -ne 0 -or $origin -notmatch '^https://github\.com/justdynamics/Truvio\.Commerce\.Distribution(?:\.git)?$'){throw 'Existing Distribution checkout has an unexpected origin; choose a clean public checkout.'}
        if (git -C $p.Distribution status --porcelain) { throw 'Distribution checkout is dirty; refusing to update it.' }
        Invoke-DwBuildCommand git @('-C',$p.Distribution,'pull','--ff-only','origin','main')
    } else {
        Invoke-DwBuildCommand git @('clone','--depth','1','--filter=blob:none','--sparse','--branch','main','https://github.com/justdynamics/Truvio.Commerce.Distribution.git',$p.Distribution)
        # This build consumes bacpacs, not YAML. Materialize only its public contracts and assets.
        Invoke-DwBuildCommand git @('-C',$p.Distribution,'sparse-checkout','set','--no-cone','/editions/','/layers/INDEX.json','/layers/base/base.contract.json','/layers/*/layer.json','/layers/*/files/','/layers/*/itemtypes/','/layers/*/repositories/','/layers/*/templates/')
    }
    $i=Get-Content -Raw (Join-Path $p.Distribution 'layers/INDEX.json') | ConvertFrom-Json -AsHashtable
    $g=$i.gateProven; $b=$i.bacpacs.editions[$Edition]
    if (-not $g.dwPlatformVersion -or -not $g.editions[$Edition] -or -not $b) { throw 'Edition lacks a gate-proven bacpac. No YAML fallback is performed.' }
    if ($b.dwVersion -ne $g.dwPlatformVersion -or $b.provenRunId -ne $g.editions[$Edition] -or $b.scrubCheck.verdict -ne 'CLEAN') { throw 'Bacpac attestation differs from gateProven or is not CLEAN.' }
    if($b.asset -notmatch '^[A-Za-z0-9._-]+\.bacpac$' -or $b.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Bacpac filename or SHA256 is invalid.'}
    $editionModel=Get-Content -Raw (Join-Path $p.Distribution "editions/$Edition.json") | ConvertFrom-Json -AsHashtable
    $asset=Join-Path $p.Notes $b.asset
    $url="https://github.com/justdynamics/Truvio.Commerce.Distribution/releases/download/$($b.tag)/$($b.asset)"
    if (-not (Test-Path $asset)) { Invoke-WebRequest -Uri $url -OutFile ($asset+'.partial') -TimeoutSec 300; Move-Item -LiteralPath ($asset+'.partial') -Destination $asset -Force }
    if ((Get-FileHash $asset -Algorithm SHA256).Hash -ne $b.sha256) { throw 'Bacpac SHA256 mismatch. Remove the local asset and retry.' }
    $receipt=@{commit=(git -C $p.Distribution rev-parse HEAD); edition=$Edition; editionModel=$editionModel; bacpac=$b; bacpacPath=$asset; dwVersion=$g.dwPlatformVersion; swiftTag=$g.swift.tag; apps=$g.apps}
    Write-DwBuildJson $p.Release $receipt
    Write-Host "Verified $Edition, DW $($receipt.dwVersion), Swift $($receipt.swiftTag), SHA256 $($b.sha256)."
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }

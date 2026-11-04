<#
.SYNOPSIS
WRITES: rebuilt product and content index instances through the Management API.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Resolves actual builders, builds both
balancer instances and requires fresh Lucene files and completion status. A PLP probe follows.
.PARAMETER DemoRoot
Demo root with launch profile and ignored API key.
.PARAMETER Apply
Rebuild indexes; otherwise list the plan.
.EXAMPLE
pwsh -NoProfile -File scripts/Build-DwDemoIndex.ps1 -DemoRoot $demo -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot
    $launch=Get-Content -Raw (Join-Path $p.Host 'Properties/launchSettings.json') | ConvertFrom-Json
    $base=$launch.profiles.'Dynamicweb.Host.Suite'.applicationUrl
    if(-not ([uri]$base).IsLoopback){throw 'Index build accepts localhost or another loopback address only.'}
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($base,'Rebuild local product and content indexes')){Write-Host 'Plan: enumerate index XMLs, resolve builders over API, build and wait, assert PLP.';exit 0}
    $secrets=Get-Content -Raw (Join-Path $p.Notes 'build-secrets.local.json') | ConvertFrom-Json
    $headers=@{Authorization="Bearer $($secrets.apiToken)"}
    $proof=@()
    foreach($file in Get-ChildItem (Join-Path $p.Files 'System/Repositories') -Filter '*.index' -Recurse) {
        $repo=$file.Directory.Name;$name=$file.Name
        [xml]$xml=Get-Content -Raw $file.FullName
        if($xml.Index.Builds.Type -notmatch 'ProductIndexBuilder|ContentIndexBuilder'){continue}
        $builders=Invoke-RestMethod -Uri "$base/admin/api/IndexBuildersByRepositoryAndIndexName?Repository=$repo&IndexName=$name" -Headers $headers -SkipCertificateCheck -TimeoutSec 120
        $builder=@($xml.SelectNodes('//Build'))[0].GetAttribute('Name')
        if(-not $builder -or ($builders | ConvertTo-Json -Depth 30) -notmatch [regex]::Escape($builder)){throw "No verified builder for $repo/$name."}
        $instances=@($xml.SelectNodes('//Instance')).Count;if($instances -lt 1){$instances=1}
        for($i=0;$i -lt $instances;$i++) {
            $start=Get-Date
            $body=@{Repository=$repo;IndexName=$name;BuildName=$builder;BuildType='Full'}|ConvertTo-Json
            $null=Invoke-RestMethod -Uri "$base/admin/api/BuildIndex" -Method Post -Body $body -ContentType 'application/json' -Headers $headers -SkipCertificateCheck -TimeoutSec 300
            $deadline=(Get-Date).AddMinutes(8)
            do {
                Start-Sleep -Seconds 2
                $status=Invoke-RestMethod -Uri "$base/admin/api/IndexStatusesAll" -Headers $headers -SkipCertificateCheck -TimeoutSec 60
                $indexDir=Join-Path $p.Files "System/Indexes/$repo"
                $fresh=@(Get-ChildItem $indexDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -like 'segments*' -and $_.LastWriteTime -ge $start.AddSeconds(-2)})
                $running=@(Get-ChildItem (Join-Path $p.Files 'System/Diagnostics/IndexBuildState') -Filter 'state.json' -Recurse -ErrorAction SilentlyContinue | Where-Object {(Get-Content -Raw $_.FullName) -match '"State"\s*:\s*"Running"'})
                if($fresh.Count -and -not $running.Count){break}
            }while((Get-Date) -lt $deadline)
            if(-not $fresh.Count -or $running.Count){throw "Index $repo/$name did not produce fresh segments and finish."}
        }
        $proof+=@{repository=$repo;index=$name;instances=$instances;status=$status}
        Write-Host "Built $repo/$name ($instances instance passes)."
    }
    if(-not $proof.Count){throw 'Zero indexes found.'}
    $plp=Invoke-WebRequest -Uri "$base/en-us/shop" -SkipCertificateCheck -TimeoutSec 120
    if($plp.StatusCode -ne 200 -or $plp.Content -notmatch 'TCPROD|product-list|productlist'){throw 'PLP does not show indexed products.'}
    Write-DwBuildJson (Join-Path $p.Notes 'index-proof.json') $proof
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}

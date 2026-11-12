<#
.SYNOPSIS
WRITES: a new build file with a re-locked check set, and a re-lock report on standard output. No target is read.
.DESCRIPTION
PowerShell 7 and Git. Owning reference: ../references/release-process.md. Compares a build
declaration with the snapshot beside the given manifest at the current checkout and reports
what a snapshot revision did to it: locked checks that no longer exist, locked checks whose
function the build does not request, requested functions that were removed, rulings whose
ground is gone (with the grounds the function has now) and checks of the requested functions
that the lock does not hold yet. The new lock takes the checkout's commit, the manifest path
and the snapshot digest, keeps the locked ids that still exist and adds new checks only with
-IncludeNewChecks. Functions and rulings are a human decision and are never rewritten: while a
removed function or an invalid ruling remains, no file is written and the exit code is 1. The
input build file is never overwritten, and a lock is refused from a checkout with uncommitted
changes, because no runner could match it.
.PARAMETER BuildFile
The existing build declaration; it may carry a lock on an older commit or snapshot revision.
.PARAMETER Manifest
Manifest of the snapshot to lock against, inside this skills checkout.
.PARAMETER OutFile
New build file to write. Omit it for a report only. An existing file is refused.
.PARAMETER IncludeNewChecks
Also lock the checks of the requested functions that the old lock does not hold.
.EXAMPLE
pwsh -NoProfile -File scripts/Update-DwLedgerLock.ps1 -BuildFile $build -Manifest $manifest -OutFile $newBuild
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildFile,
    [Parameter(Mandatory)][string]$Manifest,
    [string]$OutFile,
    [switch]$IncludeNewChecks
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ledger.Core.ps1')
$assets=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
try {
    $text=Get-Content -LiteralPath $BuildFile -Raw
    $build=Read-LedgerJson $BuildFile (Join-Path $assets 'build.schema.json')
    if($OutFile -and (Test-Path -LiteralPath $OutFile)){throw [IO.InvalidDataException]::new("OutFile '$OutFile' already exists; choose a new path so the earlier build file is kept.")}
    if(-not(Test-Path -LiteralPath $Manifest -PathType Leaf)){throw [IO.InvalidDataException]::new("Manifest '$Manifest' does not exist.")}
    $manifestPath=(Resolve-Path -LiteralPath $Manifest).Path;$root=Split-Path -Parent $manifestPath
    $manifestData=Read-LedgerJson $manifestPath
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $commit=(& git -C $repoRoot rev-parse --verify HEAD 2>$null)
    if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$'){throw [IO.InvalidDataException]::new('Cannot establish the commit to lock: the skills repository is not a git checkout.')}
    if(@(& git -C $repoRoot status --porcelain -- skills/dw-demo-ledger skills/dw-data-access/scripts/Dw.Api.psm1).Count -gt 0){throw [IO.InvalidDataException]::new('The checkout has uncommitted changes under skills/dw-demo-ledger or in skills/dw-data-access/scripts/Dw.Api.psm1; a lock on it could not be run. Re-lock from a clean checkout.')}
    $snapshot=Read-LedgerSnapshot $root $assets;$functions=$snapshot.functions;$checks=$snapshot.checks
    $lock=[ordered]@{commit=$commit;manifest=[IO.Path]::GetRelativePath($repoRoot,$manifestPath).Replace('\','/');digest=Get-LedgerDigest $root;checkIds=@()}
    $removedFunctions=@($build.functions|Where-Object {-not $functions.ContainsKey($_)})
    $removedChecks=@($build.lock.checkIds|Where-Object {-not $checks.ContainsKey($_)})
    $unrequested=@($build.lock.checkIds|Where-Object {$checks.ContainsKey($_) -and $checks[$_].functionId -notin $build.functions})
    $kept=@($build.lock.checkIds|Where-Object {$checks.ContainsKey($_) -and $checks[$_].functionId -in $build.functions})
    $newChecks=@(foreach($id in @($checks.Keys|Sort-Object)){
        if($checks[$id].functionId -in $build.functions -and $id -notin $build.lock.checkIds){
            [ordered]@{id=$id;functionId=$checks[$id].functionId;implemented=@($checks[$id].bindings|Where-Object {$_.status -eq 'implemented'}).Count -gt 0}
        }
    })
    $rulings=@(foreach($id in @(@($build.rulings.Keys)|Sort-Object)){
        $ruling=$build.rulings[$id]
        $fault=if(-not $functions.ContainsKey($id)){'the function is not in this snapshot'}
            elseif($id -notin $build.functions){'the build does not request the function'}
            else{Get-LedgerRulingFault $ruling $functions[$id]}
        if($fault){[ordered]@{functionId=$id;rule=$ruling.rule;fault=$fault;groundsNow=@(if($functions.ContainsKey($id)){$functions[$id].notApplicable|ForEach-Object {$_.id}})}}
    })
    $lock.checkIds=@($kept)+@(if($IncludeNewChecks){$newChecks|ForEach-Object {$_.id}})
    $blocking=$removedFunctions.Count -gt 0 -or $rulings.Count -gt 0
    $written=$false
    if($OutFile -and -not $blocking){
        $new=ConvertFrom-Json -InputObject $text -AsHashtable
        $new.lock=$lock
        $json=$new|ConvertTo-Json -Depth 80
        if(-not(Test-Json -Json $json -SchemaFile (Join-Path $assets 'build.schema.json') -ErrorAction Stop)){throw [IO.InvalidDataException]::new('The re-locked build does not match build.schema.json.')}
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json+"`n",[Text.UTF8Encoding]::new($false))
        $written=$true
    }
    $report=[ordered]@{schema=1;slug=$build.slug;dwVersion=$manifestData.dwVersion;revision=$manifestData.revision
        from=[ordered]@{commit=$build.lock.commit;manifest=$build.lock.manifest;digest=$build.lock.digest;checks=@($build.lock.checkIds).Count}
        to=[ordered]@{commit=$lock.commit;manifest=$lock.manifest;digest=$lock.digest;checks=@($lock.checkIds).Count}
        snapshotChanged=$build.lock.digest -ne $lock.digest
        removedFunctions=$removedFunctions;removedChecks=$removedChecks;unrequestedChecks=$unrequested
        invalidRulings=$rulings;newChecks=$newChecks;newChecksLocked=[bool]$IncludeNewChecks
        written=$written
        next=@(
            if($removedFunctions.Count){'Remove or replace the removed functions in build.functions, then re-lock.'}
            if($rulings.Count){'Correct each invalid ruling: pick a ground the function has now, or drop the ruling and build the function.'}
            if($removedChecks.Count){'Removed checks are dropped from the lock; read the snapshot delta for what replaced them.'}
            if($newChecks.Count -and -not $IncludeNewChecks){'New checks of requested functions are not locked; pass -IncludeNewChecks to lock them.'}
            if(-not $blocking){'Run the checks from this commit; a re-locked build is a new claim and needs a new report.'}
        )}
    Write-Output ($report|ConvertTo-Json -Depth 10)
    if($blocking){exit 1};exit 0
} catch {
    $cause=if($_.Exception -is [IO.InvalidDataException]){$_.Exception.Message}else{'Check the build file, the manifest path and the checkout.'}
    Write-Error ('Re-lock failed. '+$cause) -ErrorAction Continue;exit 1
}

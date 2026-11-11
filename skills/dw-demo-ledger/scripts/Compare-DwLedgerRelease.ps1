<#
.SYNOPSIS
READ-ONLY. Compare snapshots and supplied release evidence; writes a proposed delta only.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/release-process.md. Does not fetch releases, modify snapshots or mark checks measured. Evidence candidates remain proposals requiring review.
.PARAMETER Before
Earlier snapshot manifest path.
.PARAMETER After
Later snapshot manifest path.
.PARAMETER EvidenceFile
JSON with candidates: [{id, change, source, reason}]. Change is added, removed, changed or correction.
.PARAMETER OutFile
Local proposed-delta report path.
.EXAMPLE
pwsh -NoProfile -File scripts/Compare-DwLedgerRelease.ps1 -Before $old -After $new -EvidenceFile $evidence -OutFile $delta
#>
#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Before,[Parameter(Mandatory)][string]$After,[Parameter(Mandatory)][string]$EvidenceFile,[Parameter(Mandatory)][string]$OutFile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ledger.Core.ps1')
function Read-SnapshotFunctions {
    param([string]$Manifest)
    $root=Split-Path -Parent (Resolve-Path -LiteralPath $Manifest).Path
    $entries=@{}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'functions') -Filter '*.json' -File){
        foreach($f in (Read-LedgerJson $file.FullName).functions){
            if($entries.ContainsKey($f.id)){throw 'Duplicate function id.'}
            $probes=@{};foreach($path in $f.checks){$probes[$path]=(Get-FileHash -LiteralPath (Resolve-LedgerPath $root $path) -Algorithm SHA256).Hash}
            $entries[$f.id]=@{function=$f;probes=$probes}
        }
    }
    return $entries
}
try {
    $a=Read-SnapshotFunctions $Before;$b=Read-SnapshotFunctions $After
    $evidence=Read-LedgerJson $EvidenceFile
    if(-not $evidence.ContainsKey('candidates')){throw 'Evidence requires a candidates array.'}
    foreach($candidate in $evidence.candidates){
        if(-not $candidate.id -or -not $candidate.source -or -not $candidate.reason -or $candidate.change -notin @('added','removed','changed','correction')){throw 'Each candidate needs id, change, source and reason.'}
    }
    $delta=@{schema=1;status='proposed';before=(Read-LedgerJson $Before).dwVersion;after=(Read-LedgerJson $After).dwVersion;added=@();removed=@();changed=@();candidates=@($evidence.candidates);unresolved=@()}
    foreach($id in $b.Keys){if(-not $a.ContainsKey($id)){$delta.added+=$id}elseif(($a[$id]|ConvertTo-Json -Depth 40 -Compress) -ne ($b[$id]|ConvertTo-Json -Depth 40 -Compress)){$delta.changed+=$id}}
    foreach($id in $a.Keys){if(-not $b.ContainsKey($id)){$delta.removed+=$id}}
    foreach($id in @($delta.added)+@($delta.removed)+@($delta.changed)){if(@($evidence.candidates|Where-Object {$_.id -eq $id}).Count -eq 0){$delta.unresolved+=$id}}
    $delta.beforeDigest=Get-LedgerDigest (Split-Path -Parent (Resolve-Path -LiteralPath $Before).Path)
    $delta.afterDigest=Get-LedgerDigest (Split-Path -Parent (Resolve-Path -LiteralPath $After).Path)
    $delta.note='Snapshot and probe comparison plus supplied candidate intake only. Release/source extraction requires further review; no autonomous discovery claim is made.'
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),($delta|ConvertTo-Json -Depth 50)+"`n",[Text.UTF8Encoding]::new($false))
    exit 0
} catch {Write-Error 'Release comparison failed: supply valid snapshots and cited candidate evidence.' -ErrorAction Continue;exit 1}

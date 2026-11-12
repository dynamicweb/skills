<#
.SYNOPSIS
READ-ONLY. Evaluate a locked function ledger; writes only the requested report.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. MCP-first equivalent reads, optional local SQL, no missing-probe passes. Connection credentials come from parameters or DW_API_TOKEN/DW_MCP_TOKEN and are never persisted. A diagnostic version mismatch can never produce aggregate PASS.
.PARAMETER Manifest
Selected snapshot manifest path.
.PARAMETER BuildFile
Schema-valid build declaration and explicit check lock.
.PARAMETER OutFile
Local report path; target sites are never written.
.PARAMETER BaseUrl
Target URL, otherwise DW_BASE_URL.
.PARAMETER ApiToken
Management API credential, otherwise DW_API_TOKEN.
.PARAMETER McpToken
MCP credential, otherwise DW_MCP_TOKEN.
.PARAMETER SqlServer
Explicit local SQL server; absence disables SQL even if credentials exist.
.PARAMETER Database
Local database name, required for SQL observations.
.PARAMETER FilesPath
Optional local Files root; no default path.
.PARAMETER Surfaces
Permitted surfaces in selection order. Default MCP, Admin API, delivery, file, SQL.
.PARAMETER DiagnosticVersionMismatch
Allow diagnostic reads on a different or unknown DW release. Aggregate remains UNVERIFIED or worse.
.PARAMETER AllowSelfSignedCertificate
Explicit TLS opt-in for a development endpoint; loopback is handled by the shared transport.
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwLedgerChecks.ps1 -Manifest $manifest -BuildFile $build -OutFile $report
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Manifest,
    [Parameter(Mandatory)][string]$BuildFile,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$BaseUrl=$env:DW_BASE_URL,
    [string]$ApiToken=$env:DW_API_TOKEN,
    [string]$McpToken=$env:DW_MCP_TOKEN,
    [string]$SqlServer,[string]$Database,[string]$FilesPath,
    [ValidateSet('mcp','admin-api','dwapi','file','sql')][string[]]$Surfaces=@('mcp','admin-api','dwapi','file','sql'),
    [switch]$DiagnosticVersionMismatch,[switch]$AllowSelfSignedCertificate
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ledger.Core.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Observations.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Sql.ps1')
. (Join-Path $PSScriptRoot 'Cpq.Json.ps1')
. (Join-Path $PSScriptRoot 'Cpq.Read.ps1')
. (Join-Path $PSScriptRoot 'Cpq.Observations.ps1')
. (Join-Path $PSScriptRoot 'Pim.Fields.ps1')
. (Join-Path $PSScriptRoot 'Pim.Queries.ps1')
. (Join-Path $PSScriptRoot 'Pim.Matrix.ps1')
. (Join-Path $PSScriptRoot 'Pim.Layout.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Transport.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Execute.ps1')
$script:LedgerMcpCache=@{};$script:LedgerStoredFields=$null;$script:LedgerPimLayout=@{}
$assets=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
# A contract failure the runner can name. Its text states ids and paths, never a credential or an exception body.
function New-LedgerFault([string]$Message){return [IO.InvalidDataException]::new($Message)}
try {
    $build=Read-LedgerJson $BuildFile (Join-Path $assets 'build.schema.json')
    if(-not(Test-Path -LiteralPath $Manifest -PathType Leaf)){throw (New-LedgerFault "Manifest '$Manifest' does not exist.")}
    $manifestPath=(Resolve-Path -LiteralPath $Manifest).Path;$root=Split-Path -Parent $manifestPath
    $manifestData=Read-LedgerJson $manifestPath
    if($manifestData.schema -ne 1 -or -not $manifestData.dwVersion){throw (New-LedgerFault "Manifest '$manifestPath' needs schema 1 and a dwVersion.")}
    $digest=Get-LedgerDigest $root
    if($build.lock.digest -ne $digest){throw (New-LedgerFault "Snapshot digest mismatch: lock.digest is $($build.lock.digest), the snapshot beside the manifest is $digest. The snapshot changed after the lock was written, or the lock names another revision.")}
    $relativeManifest=[IO.Path]::GetRelativePath((Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,$manifestPath).Replace('\','/')
    if($build.lock.manifest -ne $relativeManifest){throw (New-LedgerFault "lock.manifest is '$($build.lock.manifest)' but the selected manifest is '$relativeManifest'. The lock takes the path relative to the repository root, with forward slashes.")}
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $runnerCommit=(& git -C $repoRoot rev-parse --verify HEAD 2>$null)
    if($LASTEXITCODE -ne 0 -or $runnerCommit -notmatch '^[a-f0-9]{40}$'){throw (New-LedgerFault 'Cannot establish the runner commit: the skills repository is not a git checkout.')}
    $runnerDirty=@(& git -C $repoRoot status --porcelain -- skills/dw-demo-ledger).Count -gt 0
    $runnerMatches=$runnerCommit -eq $build.lock.commit -and -not $runnerDirty
    if(-not $runnerMatches -and -not $DiagnosticVersionMismatch){throw (New-LedgerFault "Runner does not match the lock: lock.commit is $($build.lock.commit), the checkout is at $runnerCommit$(if($runnerDirty){' with uncommitted changes under skills/dw-demo-ledger'}). Run from a clean checkout of the locked commit.")}
    $functions=@{};$checks=@{}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'functions') -Filter '*.json' -File){
        $area=Read-LedgerJson $file.FullName (Join-Path $assets 'ledger.schema.json')
        foreach($f in $area.functions){
            if($functions.ContainsKey($f.id)){throw (New-LedgerFault "Duplicate function id '$($f.id)' in the snapshot.")};$functions[$f.id]=$f
            foreach($path in $f.checks){
                $check=Read-LedgerJson (Resolve-LedgerPath $root $path) (Join-Path $assets 'check.schema.json')
                if($check.functionId -ne $f.id -or $checks.ContainsKey($check.id)){throw (New-LedgerFault "Check '$($check.id)' at '$path' is owned by another function than '$($f.id)', or its id is used twice.")};$checks[$check.id]=$check
            }
        }
    }
    $seen=@{};foreach($id in $build.lock.checkIds){
        if($seen.ContainsKey($id)){throw (New-LedgerFault "Locked check '$id' is listed twice in lock.checkIds.")}
        if(-not $checks.ContainsKey($id)){throw (New-LedgerFault "Locked check '$id' is not in the checks list of any function in this snapshot. A lock takes its ids from the probes that functions/<area>.json references.")}
        $seen[$id]=$true
    }
    foreach($id in $build.functions){if(-not $functions.ContainsKey($id)){throw (New-LedgerFault "Function '$id' in build.functions is not in this snapshot.")}}
    foreach($id in $build.lock.checkIds){if($checks[$id].functionId -notin $build.functions){throw (New-LedgerFault "Locked check '$id' belongs to '$($checks[$id].functionId)', which build.functions does not request.")}}
    $profile=@{expectations=@{}}
    if($build.profile){$profile=Read-LedgerJson (Resolve-LedgerPath $assets $build.profile)}
    $cap=Get-LedgerCapabilities -BaseUrl $BaseUrl -ApiToken $ApiToken -McpToken $McpToken -SqlServer $SqlServer -FilesPath $FilesPath -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    $observed=if($cap.dwVersion){($cap.dwVersion -split '\+')[0]}else{$null}
    $matches=$observed -eq $manifestData.dwVersion
    $rows=[Collections.Generic.List[object]]::new()
    foreach($id in $build.lock.checkIds){
        $check=$checks[$id];$f=$functions[$check.functionId];$row=New-LedgerRow $check
        if(-not $matches -and -not $DiagnosticVersionMismatch){$row.result='UNSUPPORTED';$row.reason='Exact baseline not established; use diagnostic mode only for investigation.';$rows.Add($row);continue}
        $blocked=$false
        foreach($requirement in $f.requires){
            $state=Get-LedgerRequirementState $requirement $cap.facts
            if($state){$row.result=$state.result;$row.reason=$state.reason;$blocked=$true;break}
        }
        if($blocked){$rows.Add($row);continue}
        $ruling=if($build.rulings -and $build.rulings.ContainsKey($f.id)){$build.rulings[$f.id]}else{$null}
        $fault=if($null -ne $ruling){Get-LedgerRulingFault $ruling $f}else{$null}
        if($fault){$row.result='ERROR';$row.reason='Invalid not-applicable ruling: '+$fault;$rows.Add($row);continue}
        if($null -ne $ruling -and $ruling.applies -eq $false){
            $grounds=@($f.notApplicable|Where-Object {$_.id -eq $ruling.rule})
            if($grounds[0].probe){
                $probe=Read-LedgerJson (Resolve-LedgerPath $root $grounds[0].probe) (Join-Path $assets 'check.schema.json')
                $proof=Invoke-LedgerCheck $probe $build $cap $profile $Surfaces $SqlServer $Database $FilesPath
                $row.result=if($proof.result -eq 'PASS'){'NOT-APPLICABLE'}else{$proof.result};$row.reason='Ruling probe: '+$proof.result
                $row.surface=$proof.surface;$row.binding=$proof.binding
            } else {$row.result='NOT-APPLICABLE';$row.reason='Allowed ruling with evidence: '+$ruling.rule}
            $rows.Add($row);continue
        }
        $rows.Add((Invoke-LedgerCheck $check $build $cap $profile $Surfaces $SqlServer $Database $FilesPath))
    }
    foreach($id in $build.functions){if(@($build.lock.checkIds|Where-Object {$checks[$_].functionId -eq $id}).Count -eq 0){
        $rows.Add(@{id=$id+'.coverage';functionId=$id;result='UNVERIFIED';surface=$null;binding=$null;level='supported';proves='Requested function has executable coverage.';reason='No locked check covers the requested function.'})
    }}
    $endingVersion=Get-LedgerObservedVersion -BaseUrl $BaseUrl -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    $stableVersion=Test-LedgerStableVersion $cap.dwVersion $endingVersion
    if(-not $stableVersion){$matches=$false}
    $verdict=Get-LedgerVerdict $rows.ToArray();if((-not $matches -or -not $runnerMatches) -and $verdict -eq 'PASS'){$verdict='UNVERIFIED'}
    $counts=@{};foreach($state in @('PASS','FAIL','ERROR','UNVERIFIED','UNSUPPORTED','DISABLED','NOT-APPLICABLE')){$counts[$state]=@($rows|Where-Object {$_.result -eq $state}).Count}
    $report=@{schema=1;generatedAt=[DateTimeOffset]::UtcNow.ToString('o');slug=$build.slug;lock=$build.lock;compatibility=@{baseline=$manifestData.dwVersion;observed=$cap.dwVersion;matches=[bool]$matches;diagnostic=[bool]$DiagnosticVersionMismatch};result=$verdict;counts=$counts;capabilities=$cap;checks=$rows.ToArray();errors=@()}
    if(-not $runnerMatches){$report.errors+='Diagnostic runner differs from the locked commit or has uncommitted changes.'}
    if(-not $stableVersion){$report.errors+='Target version changed or became unavailable during observation; the initial baseline cannot certify this report.'}
    $json=$report|ConvertTo-Json -Depth 80
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $assets 'report.schema.json') -ErrorAction Stop)){throw (New-LedgerFault 'The produced report does not match report.schema.json.')}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json+"`n",[Text.UTF8Encoding]::new($false))
    Write-Output ($counts|ConvertTo-Json -Compress)
    if($verdict -eq 'PASS'){exit 0};exit 1
} catch {
    Write-Verbose $_.ScriptStackTrace
    # Only a contract failure names itself. Any other exception may carry a host, token or response body, so it stays generic.
    $cause=if($_.Exception -is [IO.InvalidDataException]){$_.Exception.Message}else{'Check schema, paths, snapshot lock, grants and required handlers; -Verbose shows where it stopped.'}
    Write-Error ('Ledger run failed before a trustworthy report could be produced. '+$cause) -ErrorAction Continue;exit 1
}

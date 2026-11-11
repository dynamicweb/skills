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
. (Join-Path $PSScriptRoot 'Ledger.Sql.ps1')
. (Join-Path $PSScriptRoot 'Pim.Fields.ps1')
. (Join-Path $PSScriptRoot 'Pim.Queries.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Transport.ps1')
. (Join-Path $PSScriptRoot 'Ledger.Execute.ps1')
$script:LedgerMcpCache=@{};$script:LedgerStoredFields=$null
$assets=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
try {
    $build=Read-LedgerJson $BuildFile (Join-Path $assets 'build.schema.json')
    $manifestPath=(Resolve-Path -LiteralPath $Manifest).Path;$root=Split-Path -Parent $manifestPath
    $manifestData=Read-LedgerJson $manifestPath
    if($manifestData.schema -ne 1 -or -not $manifestData.dwVersion){throw 'Invalid manifest.'}
    if($build.lock.digest -ne (Get-LedgerDigest $root)){throw 'Snapshot digest mismatch.'}
    $relativeManifest=[IO.Path]::GetRelativePath((Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,$manifestPath).Replace('\','/')
    if($build.lock.manifest -ne $relativeManifest){throw 'Manifest path differs from lock.'}
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $runnerCommit=(& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if($LASTEXITCODE -ne 0){throw 'Cannot establish runner commit.'}
    $runnerDirty=@(& git -C $repoRoot status --porcelain -- skills/dw-demo-ledger).Count -gt 0
    $runnerMatches=$runnerCommit -eq $build.lock.commit -and -not $runnerDirty
    if(-not $runnerMatches -and -not $DiagnosticVersionMismatch){throw 'Runner commit or working tree does not match the lock.'}
    $functions=@{};$checks=@{}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'functions') -Filter '*.json' -File){
        $area=Read-LedgerJson $file.FullName (Join-Path $assets 'ledger.schema.json')
        foreach($f in $area.functions){
            if($functions.ContainsKey($f.id)){throw 'Duplicate function id.'};$functions[$f.id]=$f
            foreach($path in $f.checks){
                $check=Read-LedgerJson (Resolve-LedgerPath $root $path) (Join-Path $assets 'check.schema.json')
                if($check.functionId -ne $f.id -or $checks.ContainsKey($check.id)){throw 'Invalid check ownership or duplicate id.'};$checks[$check.id]=$check
            }
        }
    }
    $seen=@{};foreach($id in $build.lock.checkIds){if($seen.ContainsKey($id) -or -not $checks.ContainsKey($id)){throw 'Unknown or duplicate locked check.'};$seen[$id]=$true}
    foreach($id in $build.functions){if(-not $functions.ContainsKey($id)){throw 'Unknown function.'}}
    foreach($id in $build.lock.checkIds){if($checks[$id].functionId -notin $build.functions){throw 'Locked check is outside requested functions.'}}
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
            if(-not $cap.facts.ContainsKey($requirement.id)){$row.result='UNVERIFIED';$row.reason='Required capability fact is unknown.';$blocked=$true;break}
            if($cap.facts[$requirement.id] -ne $requirement.expected){$row.result=if($requirement.kind -eq 'flag'){'DISABLED'}else{'UNSUPPORTED'};$row.reason='Required capability not satisfied.';$blocked=$true;break}
        }
        if($blocked){$rows.Add($row);continue}
        $ruling=if($build.rulings){$build.rulings[$f.id]}else{$null}
        if($ruling -and $ruling.applies -eq $false){
            $grounds=@($f.notApplicable|Where-Object {$_.id -eq $ruling.rule})
            if($grounds.Count -ne 1 -or [string]::IsNullOrWhiteSpace($ruling.evidence)){$row.result='ERROR';$row.reason='Invalid not-applicable ruling.'}
            elseif($grounds[0].probe){
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
    $verdict=Get-LedgerVerdict $rows.ToArray();if((-not $matches -or -not $runnerMatches) -and $verdict -eq 'PASS'){$verdict='UNVERIFIED'}
    $counts=@{};foreach($state in @('PASS','FAIL','ERROR','UNVERIFIED','UNSUPPORTED','DISABLED','NOT-APPLICABLE')){$counts[$state]=@($rows|Where-Object {$_.result -eq $state}).Count}
    $report=@{schema=1;generatedAt=[DateTimeOffset]::UtcNow.ToString('o');slug=$build.slug;lock=$build.lock;compatibility=@{baseline=$manifestData.dwVersion;observed=$cap.dwVersion;matches=[bool]$matches;diagnostic=[bool]$DiagnosticVersionMismatch};result=$verdict;counts=$counts;capabilities=$cap;checks=$rows.ToArray();errors=@()}
    if(-not $runnerMatches){$report.errors+='Diagnostic runner differs from the locked commit or has uncommitted changes.'}
    $json=$report|ConvertTo-Json -Depth 80
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $assets 'report.schema.json') -ErrorAction Stop)){throw 'Report contract invalid.'}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json+"`n",[Text.UTF8Encoding]::new($false))
    Write-Output ($counts|ConvertTo-Json -Compress)
    if($verdict -eq 'PASS'){exit 0};exit 1
} catch {Write-Verbose $_.ScriptStackTrace;Write-Error 'Ledger run failed before a trustworthy report could be produced. Check schema, paths, snapshot lock, grants and required handlers.' -ErrorAction Continue;exit 1}

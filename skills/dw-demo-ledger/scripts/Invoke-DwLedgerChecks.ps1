<#
.SYNOPSIS
READ-ONLY. Evaluate a locked function ledger; writes only the requested report.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. MCP-first equivalent reads, optional local SQL, no missing-probe passes. Connection credentials come from parameters or DW_API_TOKEN/DW_MCP_TOKEN and are never persisted. Persona credentials for a sign-in check come only from DW_PERSONA_CREDENTIALS and are never persisted. A diagnostic version mismatch can never produce aggregate PASS. A run that stops early still writes a report whose result is ERROR and whose errors name the cause.
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
foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Repositories.ps1','Ledger.Sql.ps1','Cpq.Json.ps1','Cpq.Read.ps1','Cpq.Observations.ps1','Pim.Fields.ps1','Pim.Queries.ps1','Pim.Matrix.ps1','Pim.Layout.ps1','Ledger.Transport.ps1','Ledger.Facts.ps1','Ledger.Execute.ps1','Ledger.Run.ps1')){. (Join-Path $PSScriptRoot $file)}
$script:LedgerMcpCache=@{};$script:LedgerStoredFields=$null;$script:LedgerPimLayout=@{};$script:LedgerTarget=$null
$assets=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
# Everything the run loads: the skill itself and the shared transport it imports.
$runnerPaths=@('skills/dw-demo-ledger','skills/dw-data-access/scripts/Dw.Api.psm1')
$states=@('PASS','FAIL','ERROR','UNVERIFIED','UNSUPPORTED','DISABLED','NOT-APPLICABLE')
# A contract failure the runner can name. Its text states ids and paths, never a credential or an exception body.
function New-LedgerFault([string]$Message){return [IO.InvalidDataException]::new($Message)}
function Save-LedgerReport($Report){
    $json=$Report|ConvertTo-Json -Depth 80
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $assets 'report.schema.json') -ErrorAction Stop)){throw (New-LedgerFault 'The produced report does not match report.schema.json.')}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json+"`n",[Text.UTF8Encoding]::new($false))
}
$build=$null;$manifestData=$null;$cap=$null
# Nothing ties a caller-supplied Files root or database to the target site, so the report says so.
$local=@{files=$(if($FilesPath){'not-tied-to-target'}else{'not-supplied'});database=$(if($SqlServer){'not-tied-to-target'}else{'not-supplied'})}
try {
    $build=Read-LedgerJson $BuildFile (Join-Path $assets 'build.schema.json')
    if(-not(Test-Path -LiteralPath $Manifest -PathType Leaf)){throw (New-LedgerFault "Manifest '$Manifest' does not exist.")}
    $manifestPath=(Resolve-Path -LiteralPath $Manifest).Path;$root=Split-Path -Parent $manifestPath
    $manifestRead=Read-LedgerJson $manifestPath
    if($manifestRead.schema -ne 1 -or -not $manifestRead.dwVersion){throw (New-LedgerFault "Manifest '$manifestPath' needs schema 1 and a dwVersion.")}
    $manifestData=$manifestRead
    $digest=Get-LedgerDigest $root
    if($build.lock.digest -ne $digest){throw (New-LedgerFault (Get-LedgerDigestFault $root $build.lock.digest $digest))}
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $relativeManifest=[IO.Path]::GetRelativePath($repoRoot,$manifestPath).Replace('\','/')
    if($build.lock.manifest -ne $relativeManifest){throw (New-LedgerFault "lock.manifest is '$($build.lock.manifest)' but the selected manifest is '$relativeManifest'. The lock takes the path relative to the repository root, with forward slashes.")}
    $runnerCommit=(& git -C $repoRoot rev-parse --verify HEAD 2>$null)
    if($LASTEXITCODE -ne 0 -or $runnerCommit -notmatch '^[a-f0-9]{40}$'){throw (New-LedgerFault 'Cannot establish the runner commit: the skills repository is not a git checkout.')}
    $runnerDirty=@(& git -C $repoRoot status --porcelain -- @runnerPaths).Count -gt 0
    $runnerMatches=$runnerCommit -eq $build.lock.commit -and -not $runnerDirty
    if(-not $runnerMatches -and -not $DiagnosticVersionMismatch){throw (New-LedgerFault "Runner does not match the lock: lock.commit is $($build.lock.commit), the checkout is at $runnerCommit$(if($runnerDirty){' with uncommitted changes under '+($runnerPaths -join ' or ')}). Run from a clean checkout of the locked commit.")}
    $snapshot=Read-LedgerSnapshot $root $assets;$functions=$snapshot.functions;$checks=$snapshot.checks
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
    Add-LedgerRequirementFacts -Capabilities $cap -Requirements @($build.functions|ForEach-Object {$functions[$_].requires}) -FilesPath $FilesPath
    $observed=if($cap.dwVersion){($cap.dwVersion -split '\+')[0]}else{$null}
    $matches=$observed -eq $manifestData.dwVersion
    # An unread descriptor is not another release: the row says which of the two stopped it.
    $blocked=if($matches -or $DiagnosticVersionMismatch){$null}
        elseif(-not $BaseUrl){'No target URL was given, so the exact baseline is not established; use diagnostic mode only for investigation.'}
        elseif(-not $observed){'The target version could not be read (admin descriptor unavailable after retries), so the exact baseline is not established. This is not a version mismatch.'}
        else{'Exact baseline not established: the target reports another release; use diagnostic mode only for investigation.'}
    $rows=Get-LedgerRows @{build=$build;functions=$functions;checks=$checks;capabilities=$cap;profile=$profile;surfaces=$Surfaces;sqlServer=$SqlServer;database=$Database;filesPath=$FilesPath;root=$root;assets=$assets;blocked=$blocked}
    $endingVersion=Get-LedgerObservedVersion -BaseUrl $BaseUrl -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    $stableVersion=Test-LedgerStableVersion $cap.dwVersion $endingVersion
    if(-not $stableVersion){$matches=$false}
    $verdict=Get-LedgerVerdict $rows.ToArray();if((-not $matches -or -not $runnerMatches) -and $verdict -eq 'PASS'){$verdict='UNVERIFIED'}
    $counts=@{};foreach($state in $states){$counts[$state]=@($rows|Where-Object {$_.result -eq $state}).Count}
    $report=@{schema=1;generatedAt=[DateTimeOffset]::UtcNow.ToString('o');slug=$build.slug;lock=$build.lock;compatibility=@{baseline=$manifestData.dwVersion;observed=$cap.dwVersion;matches=[bool]$matches;diagnostic=[bool]$DiagnosticVersionMismatch;local=$local};result=$verdict;counts=$counts;capabilities=$cap;checks=$rows.ToArray();errors=@()}
    if(-not $runnerMatches){$report.errors+='Diagnostic runner differs from the locked commit or has uncommitted changes.'}
    if($BaseUrl -and -not $observed){$report.errors+='The target version could not be read: the admin descriptor was unavailable after retries.'}
    if(-not $stableVersion){$report.errors+='Target version changed or became unavailable during observation; the initial baseline cannot certify this report.'}
    Save-LedgerReport $report
    Write-Output ($counts|ConvertTo-Json -Compress)
    if($verdict -eq 'PASS'){exit 0};exit 1
} catch {
    Write-Verbose $_.ScriptStackTrace
    # Only a contract failure names itself. Any other exception may carry a host, token or response body, so it stays generic.
    $cause=if($_.Exception -is [IO.InvalidDataException]){$_.Exception.Message}else{'Check schema, paths, snapshot lock, grants and required handlers; -Verbose shows where it stopped.'}
    # The same cause goes into a report, so a consumer that reads only the file sees why nothing was evaluated.
    try {
        $counts=@{};foreach($state in $states){$counts[$state]=0}
        if(-not $cap){$cap=@{schema=1;dwVersion=$null;discoveredAt=[DateTimeOffset]::UtcNow.ToString('o');mcp=@{available=$false;tools=@()};adminApi=@{available=$false;authenticated=$false;queries=@()};dwapi=@{available=$false};file=@{available=$false;local=$false};sql=@{available=$false;localOnly=$true};facts=@{};errors=@()}}
        Save-LedgerReport @{schema=1;generatedAt=[DateTimeOffset]::UtcNow.ToString('o');slug=$(if($build){$build.slug}else{'unknown'});lock=$(if($build){$build.lock}else{$null})
            compatibility=@{baseline=$(if($manifestData){$manifestData.dwVersion}else{$null});observed=$cap.dwVersion;matches=$false;diagnostic=[bool]$DiagnosticVersionMismatch;local=$local}
            result='ERROR';counts=$counts;capabilities=$cap;checks=@();errors=@('The run stopped before any check was evaluated. '+$cause)}
    } catch {Write-Verbose 'No report could be written for the stopped run.'}
    Write-Error ('Ledger run failed before a trustworthy report could be produced. '+$cause) -ErrorAction Continue;exit 1
}

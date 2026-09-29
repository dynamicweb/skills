<#
.SYNOPSIS
    WRITES: one Data management import project (tenant-wide definition group) and its entity rows, when absent;
    uploads the golden package to the environment's blob store; imports it INTO THE TARGET COMPANY ONLY.

.DESCRIPTION
    Step 2a of the demo-company recipe (references/demo-company.md), entirely over OData (measured on a 10.0.48
    unified sandbox, 2026-09-26):

      1. Verify the zip against its .sha256 (written by Export-GoldenPackage.ps1).
      2. Ensure the import project (-DefinitionGroup, OperationType Import, category Configuration) with one detail
         row per entity of -EntityList, GET before every POST.
      3. GetAzureWriteUrl -> PUT the zip to that blob URL (x-ms-blob-type: BlockBlob).
      4. ImportFromPackage with legalEntityId = -Target, execute = true, overwrite = true.
      5. Poll GetExecutionSummaryStatus; print the per-entity result (GetEntityExecutionSummaryStatusList) and the
         row-level errors grouped by message (GetExecutionErrors).

    Guard: -Target must be listed in -AllowedTarget (the demo's own company) and must not be -Golden. The golden
    company and every other company are never written.

    Import the package only after the target has its ledger and number sequences (shared-table rows the package
    deliberately does not carry): without a ledger most configuration entities fail validation.

.PARAMETER Package
    The golden package zip.

.PARAMETER Target
    The demo company to import into.

.PARAMETER AllowedTarget
    The only company codes this run may write to. Must contain -Target.

.PARAMETER Golden
    The golden company the package came from (refused as a target).

.PARAMETER DefinitionGroup
    Import project name (tenant-wide: carry the demo's prefix).

.PARAMETER EntityList
    The same entity-list JSON the export used.

.PARAMETER ExecutionId
    Skip upload and import; follow an execution that is already running.

.EXAMPLE
    pwsh -NoProfile -File scripts/Import-GoldenPackage.ps1 -Package <zip> -Target ABC -AllowedTarget ABC -Golden NOR -DefinitionGroup ABC-GOLDEN-IMP -EntityList <json> -WhatIf
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Package,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Target,
    [Parameter(Mandatory)][string[]]$AllowedTarget,
    [Parameter(Mandatory)][string]$Golden,
    [Parameter(Mandatory)][string]$DefinitionGroup,
    [Parameter(Mandatory)][string]$EntityList,
    [string]$ExecutionId,
    [string]$SourceFormat = 'XML-Element',
    [string]$ErrorsOut,
    [int]$PollSeconds = 60,
    [int]$MaxMinutes = 300,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [string]$Token = $env:FO_TOKEN
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token $Token
$Target = $Target.ToUpperInvariant()
if ($Target -notin ($AllowedTarget | ForEach-Object { $_.ToUpperInvariant() })) { throw "refused: $Target is not in -AllowedTarget" }
if ($Target -eq $Golden.ToUpperInvariant()) { throw "refused: the golden company $Golden is never an import target" }
$dmf = '/data/DataManagementDefinitionGroups/Microsoft.Dynamics.DataEntities'
$esc = { param($s) [uri]::EscapeDataString($s.Replace("'", "''")) }

# The target must exist (LegalEntities) before anything is written.
[void](Invoke-FoApi -Path "/data/LegalEntities('$Target')")

if (-not $ExecutionId) {
    if (-not $Package) { throw '-Package is required unless -ExecutionId is given' }
    # 1. Integrity
    $shaFile = "$Package.sha256"
    if (Test-Path -LiteralPath $shaFile) {
        $want = ((Get-Content -LiteralPath $shaFile -Raw).Trim() -split '\s+')[0]
        $got = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($want -ne $got) { throw "sha256 mismatch for $Package ($got, expected $want)" }
        Write-Host "sha256 OK $got"
    } else { Write-Warning "no $shaFile; integrity not checked" }

    # 2. Project and entity rows
    $list = (Get-Content -LiteralPath $EntityList -Raw | ConvertFrom-Json).entities
    $group = $null
    try { $group = Invoke-FoApi -Path "/data/DataManagementDefinitionGroups('$(& $esc $DefinitionGroup)')" } catch { Write-Verbose (Get-FoErrorText $_) }
    if (-not $group) {
        if ($PSCmdlet.ShouldProcess($DefinitionGroup, 'create import project')) {
            $desc = "Golden config import from $Golden into $Target"
            [void](Invoke-FoApi -Method Post -Path '/data/DataManagementDefinitionGroups' -Body @{
                Name = $DefinitionGroup; Description = $desc.Substring(0, [Math]::Min(60, $desc.Length))
                OperationType = 'Import'; ProjectCategory = 'Configuration'; GenerateDataPackage = 'No' })
            Write-Host "created import project $DefinitionGroup"
        }
    } elseif ($group.OperationType -ne 'Import') { throw "$DefinitionGroup exists with OperationType $($group.OperationType), not Import" }
    $have = @()   # Select-Object -ExpandProperty, not ForEach-Object <name>: that form honours -WhatIf and returns nothing
    try { $have = @((Invoke-FoApi -Path "/data/DataManagementDefinitionGroupDetails?`$filter=DefinitionGroupId eq '$(& $esc $DefinitionGroup)'&`$select=EntityName").value | Select-Object -ExpandProperty EntityName) } catch { Write-Warning ("could not list the project entities: {0}" -f (Get-FoErrorText $_)) }
    $added = 0; $failed = 0
    foreach ($e in $list) {
        if ($have -contains $e.EntityName) { continue }
        if (-not $PSCmdlet.ShouldProcess("$DefinitionGroup / $($e.EntityName)", 'add entity')) { $added++; continue }
        try {
            [void](Invoke-FoApi -Method Post -Path '/data/DataManagementDefinitionGroupDetails' -Body @{
                DefinitionGroupId = $DefinitionGroup; EntityName = $e.EntityName; SourceFormat = $SourceFormat; AutoGenerateMapping = 'Yes'
                ExecutionUnit = [int]$e.ExecutionUnit; LevelInExecutionUnit = [int]$e.LevelInExecutionUnit; SequenceInLevel = [int]$e.SequenceInLevel })
            $added++
        } catch { $failed++; Write-Warning ("{0}: {1}" -f $e.EntityName, (Get-FoErrorText $_)) }
    }
    Write-Host ("entities: {0} in list, {1} already in the project, {2} added, {3} refused" -f $list.Count, $have.Count, $added, $failed)
    # 2b. Re-point company references. A company-scoped entity still carries the golden company as a VALUE in some
    #     fields (measured in a NOR package: Journal names VOUCHERSERIESCOMPANYID, Subledger journal transfer rule and
    #     Ledger allocation basis source LEGALENTITYID, Ledger allocation rule destination COMPANY/FROMCOMPANY,
    #     Tracking number groups NUMBERSEQUENCESCOPEDATAAREA). Imported as is, those rows point at the golden company
    #     (or, where the field is part of the key, update the golden company's own row). Copy into legal entity
    #     remaps them; a package import does not, so the script rewrites them in a derived copy of the zip.
    $work = Join-Path ([IO.Path]::GetTempPath()) "$DefinitionGroup-$Target-$([guid]::NewGuid().ToString('N'))"
    $derived = "$work.zip"
    # Local scratch copy, also in a dry run (so -WhatIf shows the re-point counts).
    Expand-Archive -LiteralPath $Package -DestinationPath $work -WhatIf:$false
    $rx = [regex]::new("<(?<t>[A-Z0-9_]*(?:COMPANY|DATAAREA|LEGALENTITY)[A-Z0-9_]*)>$([regex]::Escape($Golden))</\k<t>>", 'IgnoreCase')
    $rewritten = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $work -Filter *.xml -File | Where-Object Name -notin 'Manifest.xml', 'PackageHeader.xml')) {
        $sr = [IO.StreamReader]::new($f.FullName, $true); $text = $sr.ReadToEnd(); $enc = $sr.CurrentEncoding; $sr.Dispose()
        $count = $rx.Matches($text).Count
        if (-not $count) { continue }
        $rewritten += $count
        [IO.File]::WriteAllText($f.FullName, $rx.Replace($text, { param($m) "<$($m.Groups['t'].Value)>$Target</$($m.Groups['t'].Value)>" }), $enc)
        Write-Host ("  re-pointed {0,4} {1} -> {2} in {3}" -f $count, $Golden, $Target, $f.Name)
    }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $derived -WhatIf:$false
    Remove-Item -LiteralPath $work -Recurse -Force -WhatIf:$false
    Write-Host "company references re-pointed: $rewritten"
    $Package = $derived
    if (-not $PSCmdlet.ShouldProcess("$Target (from $Package)", 'upload and ImportFromPackage')) { exit 0 }

    # 3. Upload
    $name = "$DefinitionGroup-$([guid]::NewGuid().ToString('N')).zip"
    $w = (Invoke-FoApi -Method Post -Path "$dmf.GetAzureWriteUrl" -Body @{ uniqueFileName = $name }).value | ConvertFrom-Json
    Invoke-WebRequest -Method Put -Uri $w.BlobUrl -InFile $Package -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -ContentType 'application/zip' -TimeoutSec 1800 | Out-Null
    Write-Host "uploaded $(Split-Path -Leaf $Package) as blob $($w.BlobId)"

    # 4. Import into the target only
    # ImportFromPackage answers only after the package is unpacked into staging; a 228-entity package outlived a
    # 180 s client timeout (measured). The server keeps going: never re-send, recover the execution id instead.
    try {
        $ExecutionId = (Invoke-FoApi -Method Post -Path "$dmf.ImportFromPackage" -TimeoutSec 1800 -Body @{
            packageUrl = $w.BlobUrl; definitionGroupId = $DefinitionGroup; executionId = ''; execute = $true; overwrite = $true; legalEntityId = $Target }).value
    } catch {
        Write-Warning ("ImportFromPackage did not answer ({0}); looking up the execution it started" -f (Get-FoErrorText $_))
        Start-Sleep -Seconds 60
        $ExecutionId = @((Invoke-FoApi -Path "/data/DataManagementExecutionJobDetails?`$filter=DefinitionGroupId eq '$(& $esc $DefinitionGroup)'&`$select=JobId").value |
            Select-Object -ExpandProperty JobId | Sort-Object -Unique -Descending)[0]
        if (-not $ExecutionId) { throw 'no execution found for the import project; check Data management > Job history before re-running' }
    }
    Write-Host "execution: $ExecutionId"
}

# 5. Follow
$deadline = (Get-Date).AddMinutes($MaxMinutes)
$prev = ''
do {
    Start-Sleep -Seconds $PollSeconds
    $status = Get-FoExecutionStatus -ExecutionId $ExecutionId
    $line = $status
    try {
        $rows = @((Invoke-FoApi -Path "/data/DataManagementExecutionJobDetails?`$filter=JobId eq '$(& $esc $ExecutionId)'&`$select=EntityName,StagingStatus,TargetStatus").value)
        $line = "$status  entities=$($rows.Count) staging[" + (($rows | Group-Object StagingStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' ') +
                "] target[" + (($rows | Group-Object TargetStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' ') + ']'
    } catch { }
    if ($line -ne $prev) { Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), $line); $prev = $line }
} while ($status -in 'Executing', 'NotRun', 'Unknown' -and (Get-Date) -lt $deadline)

$rows = @((Invoke-FoApi -Path "/data/DataManagementExecutionJobDetails?`$filter=JobId eq '$(& $esc $ExecutionId)'&`$select=EntityName,StagingStatus,TargetStatus,TargetRecordsCreatedCount,TargetRecordsUpdatedCount").value)
$bad = @($rows | Where-Object { $_.StagingStatus -eq 'Error' -or $_.TargetStatus -eq 'Error' })
Write-Host ("final: {0}; entities {1}; in error {2}; target rows created {3}, updated {4}" -f $status, $rows.Count, $bad.Count,
    (($rows | Measure-Object TargetRecordsCreatedCount -Sum).Sum), (($rows | Measure-Object TargetRecordsUpdatedCount -Sum).Sum))
$bad | ForEach-Object { Write-Host ("  ERROR  {0}  (staging {1}, target {2})" -f $_.EntityName, $_.StagingStatus, $_.TargetStatus) }
$errs = @(Get-FoExecutionErrors -ExecutionId $ExecutionId)
Write-Host "row-level errors: $($errs.Count)"
$errs | Group-Object { ($_.ErrorMessage -replace "'[^']*'", "'*'").Trim() } | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("{0,6}  {1}" -f $_.Count, $_.Name) }
if ($ErrorsOut) { $errs | Export-Csv -LiteralPath $ErrorsOut -NoTypeInformation -Encoding utf8NoBOM; Write-Host "written: $ErrorsOut" }
[pscustomobject]@{ ExecutionId = $ExecutionId; Status = $status; Entities = $rows.Count; InError = $bad.Count; RowErrors = $errs.Count }

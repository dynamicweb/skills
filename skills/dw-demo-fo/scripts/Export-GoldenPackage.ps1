<#
.SYNOPSIS
    WRITES: one Data management export project (tenant-wide definition group) and its entity rows, when absent.
    READS the golden company. Downloads the package zip and writes a .sha256 beside it, outside the environment.

.DESCRIPTION
    Step 2e of the demo-company recipe (references/demo-company.md): export the golden company's configuration
    as a Data management package, entirely over OData. Measured on a 10.0.48 unified sandbox (2026-09-26):
    DataManagementDefinitionGroups and DataManagementDefinitionGroupDetails both accept POST, so the export
    project needs no UI.

      1. Ensure the export project (-DefinitionGroup, OperationType Export, category Configuration) and one
         detail row per entity of -EntityList (JSON: { "entities": [ { EntityName, ExecutionUnit,
         LevelInExecutionUnit, SequenceInLevel } ] }), GET before every POST.
      2. ExportToPackage with legalEntityId = -Golden (a read of that company).
      3. Poll GetExecutionSummaryStatus until it leaves Executing/NotRun/Unknown.
      4. GetExportedPackageUrl, download the zip to -OutDir, write <zip>.sha256 and a copy of the entity list.

    The entity list must hold company-scoped entities only (DataManagementEntities.IsShared = No). A shared
    entity exports every company's rows, and importing that package writes into other companies.

    Traps encoded here:
      - A detail row POSTed without AutoGenerateMapping = 'Yes' has no field mapping (ValidationStatus No): the
        export stages 0 rows for it and the execution then sits in Executing indefinitely (measured: 228 entities,
        0 rows, still Executing after 40 minutes). With 'Yes' the row comes back ValidationStatus Yes and exports.
      - The project Description is cut to 60 characters by F&O.
      - Keep the zip OUTSIDE the environment: a sandbox refresh removes the golden company and its projects.
      - A dead or running execution of the same project blocks a new one; the script refuses to start while
        the project's last execution is still Executing.

.PARAMETER Golden
    The golden company (dataAreaId) to export. Read-only.

.PARAMETER DefinitionGroup
    Export project name. Tenant-wide: give it the owning demo's prefix (shared-sandbox.md).

.PARAMETER EntityList
    JSON file with the entity list (see DESCRIPTION).

.PARAMETER OutDir
    Folder outside the environment for the zip, its .sha256 and the entity list copy.

.PARAMETER SourceFormat
    Data management source data format of every entity. Default XML-Element.

.PARAMETER WhatIf
    Plan only: list what would be created and exported.

.EXAMPLE
    pwsh -NoProfile -File scripts/Export-GoldenPackage.ps1 -Golden NOR -DefinitionGroup 'ABC-GOLDEN-NOR-EXP' -EntityList ./golden-entities.json -OutDir <folder outside the repo> -WhatIf
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Golden,
    [Parameter(Mandatory)][string]$DefinitionGroup,
    [Parameter(Mandatory)][string]$EntityList,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Description,
    [string]$SourceFormat = 'XML-Element',
    [int]$PollSeconds = 60,
    [int]$MaxMinutes = 240,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [string]$Token = $env:FO_TOKEN
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token $Token
$Golden = $Golden.ToUpperInvariant()
$dmf = '/data/DataManagementDefinitionGroups/Microsoft.Dynamics.DataEntities'
$list = (Get-Content -LiteralPath $EntityList -Raw | ConvertFrom-Json).entities
if (-not $list) { throw "no entities in $EntityList" }
$esc = { param($s) [uri]::EscapeDataString($s.Replace("'", "''")) }

# 1. Project and entity rows
$group = $null
try { $group = Invoke-FoApi -Path "/data/DataManagementDefinitionGroups('$(& $esc $DefinitionGroup)')" } catch { }
if (-not $group) {
    $desc = if ($Description) { $Description } else { "Golden config export from $Golden" }
    if ($PSCmdlet.ShouldProcess($DefinitionGroup, 'create export project')) {
        [void](Invoke-FoApi -Method Post -Path '/data/DataManagementDefinitionGroups' -Body @{
            Name = $DefinitionGroup; Description = $desc.Substring(0, [Math]::Min(60, $desc.Length))
            OperationType = 'Export'; ProjectCategory = 'Configuration'; GenerateDataPackage = 'Yes' })
        Write-Host "created export project $DefinitionGroup"
    }
} elseif ($group.OperationType -ne 'Export') { throw "$DefinitionGroup exists with OperationType $($group.OperationType), not Export" }
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
if ($WhatIfPreference) { Write-Host "would export $DefinitionGroup from $Golden to $OutDir"; exit 0 }

# 2. Refuse to stack an execution on a running one
$running = @()
try {
    $running = @((Invoke-FoApi -Path "/data/DataManagementExecutionJobDetails?`$filter=DefinitionGroupId eq '$(& $esc $DefinitionGroup)'&`$select=JobId,StagingStatus,TargetStatus").value |
        Where-Object { $_.StagingStatus -eq 'Executing' -or $_.TargetStatus -eq 'Executing' })
} catch { Write-Warning ("could not read earlier executions: {0}" -f (Get-FoErrorText $_)) }
if ($running.Count) { throw "an execution of $DefinitionGroup is still Executing ($($running[0].JobId)); wait for it or clear it from Job history" }

# 3. Export
$packageName = "$DefinitionGroup-$(Get-Date -Format yyyyMMdd-HHmm)"
$exec = (Invoke-FoApi -Method Post -Path "$dmf.ExportToPackage" -Body @{
    definitionGroupId = $DefinitionGroup; packageName = $packageName; executionId = ''; reExecute = $false; legalEntityId = $Golden }).value
Write-Host "execution: $exec"
$deadline = (Get-Date).AddMinutes($MaxMinutes)
do {
    Start-Sleep -Seconds $PollSeconds
    $status = Get-FoExecutionStatus -ExecutionId $exec
    Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), $status)
} while ($status -in 'Executing', 'NotRun', 'Unknown' -and (Get-Date) -lt $deadline)
if ($status -notin 'Succeeded', 'PartiallySucceeded') {
    Get-FoExecutionErrors -ExecutionId $exec | Group-Object { ($_.ErrorMessage -replace "'[^']*'", "'*'") } |
        Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object { Write-Host ("{0,6}  {1}" -f $_.Count, $_.Name) }
    throw "export ended $status"
}

# 4. Download outside the environment
$url = (Invoke-FoApi -Method Post -Path "$dmf.GetExportedPackageUrl" -Body @{ executionId = $exec }).value
if (-not $url) { throw "GetExportedPackageUrl returned nothing for $exec" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir "$packageName.zip"
Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 1800
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$zip.sha256" -Value "$hash  $(Split-Path -Leaf $zip)" -Encoding ascii
Copy-Item -LiteralPath $EntityList -Destination (Join-Path $OutDir "$packageName.entities.json") -Force
Write-Host ("package: {0} ({1:N0} bytes) sha256 {2}; status {3}; execution {4}" -f $zip, (Get-Item $zip).Length, $hash, $status, $exec)
[pscustomobject]@{ Package = $zip; Sha256 = $hash; Status = $status; ExecutionId = $exec }

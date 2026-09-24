<#
.SYNOPSIS
    READ-ONLY. Poll a running "Copy into legal entity" (or any Data management) execution over OData and
    summarise its row-level errors when it ends.

.DESCRIPTION
    Step 2 of the demo-company recipe (references/demo-company.md) is a long-running job of several hundred
    entities (a copy from a stock donor measured 2 h 14 min for 365 entities) whose UI click usually times
    out on the caller side while the server keeps working. This script reads the per-entity job detail rows
    and prints a line whenever the staging/target tallies change, then exits when nothing is left in NotRun
    or Executing.

    With -JobId it follows one execution and, on completion (or at once with -ErrorsOnly), reads the
    row-level errors with the GetExecutionErrors action and prints them grouped by message, quoted values
    masked, most frequent first. Most of a copy's row errors are expected noise from the donor's demo data;
    the reference lists which ones matter.

    Traps encoded here:
      - The access token is renewed during the poll (Fo.Api.psm1); a copy outlives a one-hour token.
      - GetExecutionErrors returns a JSON array inside a string whose messages carry unescaped quotes, so
        ConvertFrom-Json fails part-way; the module parses it with a record-boundary regex split.
      - The entity-level Error status only means "at least one row failed". Read the grouped messages
        before deciding anything.

.PARAMETER JobId
    The execution to follow: DataManagementExecutionJobs.JobId, for example
    'Copy legal entity <SRC> to <DST> - <timestamp>'. Without it, all executions visible to the identity are
    polled together.

.PARAMETER ErrorsOnly
    Skip the poll and print the grouped errors of -JobId now.

.PARAMETER ErrorsOut
    Optional CSV file for every parsed error row (RecordId, Field, ErrorMessage).

.PARAMETER IntervalSeconds
    Seconds between polls. Default 60: the tenant is shared, and a copy moves in minutes, not seconds.

.PARAMETER MaxPolls
    Stop after this many polls even if the job is unfinished. Default 240.

.PARAMETER EnvironmentUrl
    Else $env:FO_ENV_URL. Identity: -TenantId / -ClientId / -CachePath / -Token, else the FO_* environment
    variables (see Fo.Api.psm1). An S2S secret, when used, comes from $env:FO_CLIENT_SECRET only.

.EXAMPLE
    pwsh -NoProfile -File scripts/Watch-CopyProgress.ps1 -JobId 'Copy legal entity USMF to ABC - <timestamp>'

.EXAMPLE
    pwsh -NoProfile -File scripts/Watch-CopyProgress.ps1 -JobId 'Copy legal entity USMF to ABC - <timestamp>' -ErrorsOnly -ErrorsOut ./copy-errors.csv
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$JobId,
    [switch]$ErrorsOnly,
    [string]$ErrorsOut,
    [ValidateRange(10, 3600)][int]$IntervalSeconds = 60,
    [int]$MaxPolls = 240,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [string]$Token = $env:FO_TOKEN
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token $Token
if ($ErrorsOnly -and -not $JobId) { Write-Error '-ErrorsOnly needs -JobId.'; exit 1 }

function Write-ErrorSummary {
    $errs = @(Get-FoExecutionErrors -ExecutionId $JobId)
    Write-Output ("status: {0}; row-level errors: {1}" -f (Get-FoExecutionStatus -ExecutionId $JobId), $errs.Count)
    $errs | Group-Object { ($_.ErrorMessage -replace "'[^']*'", "'*'").Trim() } | Sort-Object Count -Descending |
        ForEach-Object { Write-Output ("{0,6}  {1}" -f $_.Count, $_.Name) }
    if ($ErrorsOut) {
        $out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ErrorsOut)
        $errs | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding utf8NoBOM
        Write-Output "written: $out"
    }
}

if ($ErrorsOnly) { Write-ErrorSummary; exit 0 }

$detailPath = '/data/DataManagementExecutionJobDetails?cross-company=true&$select=JobId,EntityName,StagingStatus,TargetStatus'
if ($JobId) { $detailPath += "&`$filter=JobId eq '" + ($JobId -replace "'", "''") + "'" }
if (-not $JobId) {
    try {
        foreach ($job in (Invoke-FoApi -Path '/data/DataManagementExecutionJobs?$select=JobId,Description').value) { Write-Output "job: $($job.JobId)" }
    } catch { Write-Warning ("could not read the job list: {0}" -f (Get-FoErrorText $_)) }
}

$previous = ''
$done = $false
for ($poll = 0; $poll -lt $MaxPolls; $poll++) {
    try {
        $rows = @((Invoke-FoApi -Path $detailPath).value)
        $staging = ($rows | Group-Object StagingStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
        $target = ($rows | Group-Object TargetStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
        $line = "entities=$($rows.Count) staging[$staging] target[$target]"
        if ($line -ne $previous) { Write-Output ("{0:HH:mm:ss}  {1}" -f (Get-Date), $line); $previous = $line }
        # An entity whose staging failed never reaches target: do not wait for its target step.
        $pending = @($rows | Where-Object { $_.StagingStatus -in 'NotRun', 'Executing' -or
                                            ($_.StagingStatus -ne 'Error' -and $_.TargetStatus -in 'NotRun', 'Executing') })
        if ($rows.Count -gt 0 -and $pending.Count -eq 0) { Write-Output "COPY COMPLETE $line"; $done = $true; break }
    } catch {
        Write-Output ("poll error: {0}" -f (Get-FoErrorText $_))
    }
    Start-Sleep -Seconds $IntervalSeconds
}
if (-not $done) { Write-Output "stopped after $MaxPolls polls; the job may still be running. Re-run to keep watching."; exit 1 }
if ($JobId) { Write-ErrorSummary }
exit 0

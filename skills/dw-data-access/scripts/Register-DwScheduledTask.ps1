<#
.SYNOPSIS
    WRITES: one ScheduledTask row, registered disabled and parked, then flushes
    the task register and proves the registration from the task list. Dry run
    by default; -Apply writes.

.DESCRIPTION
    The multi-column row contract, enforced. Live rows do not reveal the
    constraints, so copying one field-by-field fails on constraints and on
    defaults; every rule below is one such failure:

      - TaskParentId is NULL, never 0. The register is a two-level tree and
        the scheduler enumerates the PARENT list, so 0 means "child of task 0",
        which does not exist: the task never fires and LOGS NOTHING AT ALL.
        A working row shows an empty cell in every viewer, and 0 is the
        natural int default, which is what makes this easy to copy in.
      - Every schedule column (-Minute/-Hour/-Day/-Wday) is -1 by default, so
        the task is outside the scheduler's arithmetic entirely.
      - TaskEnabled = 0 is the kill switch; a far-future next run is NOT. DW
        re-evaluates overdue tasks at APPLICATION START and fires them, so a
        task carrying a realistic minute/hour pair self-fires about a minute
        after anything recycles the pool.
      - TaskRun ignores TaskEnabled entirely, so the right shape for a
        destructive or environment-resetting task is registered disabled with
        a far-future TaskBegin, driven entirely through TaskRun.
      - TaskLastRun is NOT NULL with no default: a sentinel is seeded.
      - TaskParam0..4, TaskTarget, TaskAssembly, TaskNamespace, TaskClass and
        TaskLastException are EMPTY STRINGS on every live row, not NULL.
      - TaskComment is nvarchar(255) and SQL Server REFUSES rather than trims
        ("String or binary data would be truncated"). Rows written through the
        backend can be longer because the backend truncates for you, so
        "match what is already there" is not a safe guide.
      - TaskAddInSettings holds LITERAL XML, and repeats the type name WITHOUT
        the assembly on the root and on every child; TaskAddInTypeName carries
        the assembly-qualified form. XML-escaping the whole document stores a
        string the add-in loader cannot parse: the task exists, opens in
        admin, and does nothing. Only the parameter VALUE is escaped.
      - The running scheduler does not re-read the table. A SQL-written row is
        invisible until the register is flushed, so TaskRun answers
        404 "The task with id: N was not found" for a row that demonstrably
        exists. This script flushes Dynamicweb.Scheduling.TaskService.
      - Prove registration from the task list, not from the INSERT. This
        script reads GET /Admin/Api/Tasks with an explicit page size, because
        the ten-row default is how a freshly added task reads as absent on a
        solution that already has ten.

    What stays in the owning reference: TaskBegin/TaskNextRun semantics (the
    scheduler computes the next run as TaskBegin + n x TaskMinute, so
    TaskNextRun is a derived output column that a hand-set value survives only
    until the first recomputation) and the TaskStartFromLastRun anchor-vs-drift
    choice.

    This script registers a task ROW only. It does NOT register a
    RunSql add-in task: arbitrary SQL through a scheduled task is a banned
    path and this script refuses an add-in type name that names one.

    Owning reference: dw-data-access/references/recipes-extend.md
    ("Register a scheduled task by SQL"); the full row contract and the run
    semantics are dw-extend-scheduled-tasks/references/scheduler-rows-and-runs.md.

.PARAMETER TaskName
    The task name. Also the key the verification read matches on.

.PARAMETER AddInTypeName
    Assembly-qualified: `Namespace.Type, AssemblyName`.

.PARAMETER Parameter
    The add-in's parameters as @{ Name = 'Value' }. Read the names off the
    add-in's own metadata rather than guessing them.

.PARAMETER Comment
    TaskComment. Max 255 characters; longer is refused here rather than by
    SQL Server mid-transaction.

.PARAMETER TaskBegin
    The slot the scheduler anchors on. Defaults to a far-future date, which
    with TaskEnabled = 0 is the parked shape.

.PARAMETER Minute / Hour / Day / Wday
    Schedule columns. All -1 by default (outside the scheduler's arithmetic).
    With TaskType = 0, TaskMinute is an INTERVAL IN MINUTES, not a minute of
    the hour; there is no calendar-month schedule, so "monthly" is 43200.

.PARAMETER Enabled
    Register the task enabled. Off by default, and a deliberate choice: an
    enabled task with any real schedule column can fire the moment the pool
    restarts.

.PARAMETER Apply
    Write. Without it the INSERT, the flush and the verification read are
    printed and nothing runs.

.PARAMETER BaseUrl / ApiToken / SolutionPath
    Connection for the flush and the verification read; else the DW_* env
    vars, else launchSettings.json discovery.

.PARAMETER ConnectionString
    Local SQL connection; else $env:DW_SQL_CONNECTION. Local installs only.

.EXAMPLE
    pwsh -NoProfile -File scripts/Register-DwScheduledTask.ps1 -TaskName 'Nightly orders export' -AddInTypeName 'Dynamicweb.DataIntegration.Integration.JobScheduledTaskAddIn, Dynamicweb.DataIntegration' -Parameter @{ Activity = 'Orders export' }

.EXAMPLE
    pwsh -NoProfile -File scripts/Register-DwScheduledTask.ps1 -TaskName 'Nightly orders export' -AddInTypeName 'Ns.Type, Asm' -Parameter @{ Activity = 'Orders export' } -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$TaskName,
    [Parameter(Mandatory = $true)][string]$AddInTypeName,
    [hashtable]$Parameter = @{},
    [string]$Comment = '',
    [datetime]$TaskBegin = ([datetime]'2099-01-01T03:30:00'),
    [int]$Minute = -1,
    [int]$Hour = -1,
    [int]$Day = -1,
    [int]$Wday = -1,
    [switch]$Enabled,
    [switch]$Apply,
    [string]$BaseUrl,
    [string]$ApiToken,
    [string]$SolutionPath,
    [string]$ConnectionString
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Dw.Sql.Local.psm1') -Force -ErrorAction Stop
Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -SolutionPath $SolutionPath | Out-Null
Assert-DwConnection | Out-Null

# Roadmap rule 10: arbitrary SQL through a scheduled-task add-in is a banned
# path and is not absorbed by any shipped script.
if ($AddInTypeName -match '(?i)RunSql') {
    Write-Error ("Refusing to register '$AddInTypeName': arbitrary SQL executed through a scheduled-task " +
        "add-in is a banned path. Run the statement with Invoke-DwSqlThenFlush.ps1 instead, where it is " +
        "visible, dry-runnable and flushed.") -ErrorAction Continue
    exit 1
}
if ($AddInTypeName -notmatch ',') {
    Write-Error ("-AddInTypeName must be assembly-qualified (`Namespace.Type, AssemblyName`); got " +
        "'$AddInTypeName'. Read the FQN off the assembly rather than guessing the namespace.") -ErrorAction Continue
    exit 1
}
if ($Comment.Length -gt 255) {
    Write-Error ("-Comment is $($Comment.Length) characters. TaskComment is nvarchar(255) and SQL Server " +
        "refuses rather than trims. Rows written through the backend can be longer because the backend " +
        "truncates for you, so an existing row is not a safe guide.") -ErrorAction Continue
    exit 1
}

# TaskAddInSettings is LITERAL XML: only the parameter VALUE is escaped, and
# the type name repeats WITHOUT the assembly on the root and on every child.
$bareType = ($AddInTypeName -split ',')[0].Trim()
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
[void]$sb.AppendLine("<Parameters addin=`"$bareType`">")
foreach ($name in $Parameter.Keys) {
    $value = [System.Security.SecurityElement]::Escape([string]$Parameter[$name])
    $pname = [System.Security.SecurityElement]::Escape([string]$name)
    [void]$sb.AppendLine("  <Parameter addin=`"$bareType`" name=`"$pname`" value=`"$value`" />")
}
[void]$sb.AppendLine('</Parameters>')
$settingsXml = $sb.ToString()

$insert = @'
IF EXISTS (SELECT 1 FROM ScheduledTask WHERE TaskName = @TaskName)
    THROW 50000, 'A ScheduledTask row with that name already exists.', 1;
INSERT INTO ScheduledTask
    (TaskName, TaskParentId, TaskBegin, TaskEnd, TaskLastRun, TaskNextRun, TaskEnabled, TaskType,
     TaskMinute, TaskHour, TaskDay, TaskWday,
     TaskAddInTypeName, TaskAddInSettings, TaskComment,
     TaskCheckPrevious, TaskSort, TaskStartFromLastRun, TaskLastResult,
     TaskParam0, TaskParam1, TaskParam2, TaskParam3, TaskParam4,
     TaskTarget, TaskAssembly, TaskNamespace, TaskClass, TaskLastException)
VALUES
    (@TaskName, NULL, @TaskBegin, '9999-12-31', '1900-01-01', '9999-12-31', @TaskEnabled, 0,
     @Minute, @Hour, @Day, @Wday,
     @AddInTypeName, @Settings, @Comment,
     0, 0, 0, NULL,
     '', '', '', '', '',
     '', '', '', '', '');
SELECT CAST(SCOPE_IDENTITY() AS int);
'@

$parameters = @{
    TaskName      = $TaskName
    TaskBegin     = $TaskBegin
    TaskEnabled   = [int][bool]$Enabled
    Minute        = $Minute
    Hour          = $Hour
    Day           = $Day
    Wday          = $Wday
    AddInTypeName = $AddInTypeName
    Settings      = $settingsXml
    Comment       = $Comment
}

Write-Host 'Plan:'
Write-Host "  1. INSERT one ScheduledTask row — TaskParentId NULL, schedule columns $Minute/$Hour/$Day/$Wday, TaskEnabled $([int][bool]$Enabled)."
Write-Host "  2. Flush Dynamicweb.Scheduling.TaskService (the running scheduler never re-reads the table)."
Write-Host '  3. Read GET /Admin/Api/Tasks with an explicit page size and match the task by name.'
Write-Host ''
Write-Host 'TaskAddInSettings (literal XML, only the parameter value escaped):'
$settingsXml -split "`r?`n" | ForEach-Object { if ($_) { Write-Host "  $_" } }

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN — nothing written. Re-run with -Apply.'
    exit 0
}
if (-not $PSCmdlet.ShouldProcess($TaskName, 'INSERT a ScheduledTask row, flush TaskService, verify from the task list')) {
    exit 0
}

$taskId = Invoke-DwSqlScalarWrite -Sql $insert -Parameters $parameters -ConnectionString $ConnectionString
Write-Host ''
Write-Host "Inserted ScheduledTask row, TaskID $taskId."

Clear-DwServiceCache -CacheTypeName 'Dynamicweb.Scheduling.TaskService'
Write-Host 'Flushed Dynamicweb.Scheduling.TaskService.'

# Prove it from the task list, not from the INSERT. The default page size is
# ten, which is how a freshly added task reads as absent.
$tasks = Invoke-DwApi 'Tasks?PageSize=1000&Page=1'
$rows = @($tasks.data ?? $tasks.model ?? $tasks)
$hit = @($rows | Where-Object { $_.taskName -eq $TaskName -or $_.name -eq $TaskName }) | Select-Object -First 1
if (-not $hit) {
    Write-Host ''
    Write-Host "FAILED: the row exists but GET /Admin/Api/Tasks does not return '$TaskName'."
    Write-Host 'The register did not pick it up. Re-flush, or recycle the app pool, before claiming registration succeeded.'
    exit 1
}
Write-Host "Verified from the task list: '$TaskName' is registered."
Write-Host ''
Write-Host 'Next: drive it with POST /Admin/Api/TaskRun {"TaskId":' "$taskId" '}, which ignores TaskEnabled.'
Write-Host 'Assert the run by comparing TaskLastRun against a value captured BEFORE the trigger —'
Write-Host 'TaskRun is asynchronous, so a fixed wall-clock window is not an assertion.'
exit 0

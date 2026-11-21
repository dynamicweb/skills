<#
.SYNOPSIS
READ-ONLY. Prints the brief that starts an orchestrating demo-build session, with the model split filled in; writes only -OutFile when given.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/orchestrator.md ("Delegating the recipe set"). A session delegates the recipe set run to a cheaper model when the split is in the brief that starts it, and keeps the run on its own model when the split is only in a skill it reads later. This script makes that brief, so a launcher, a dispatcher or a person never retypes it.
The build brief carries the measured split paragraph with the model ids filled in, the delegate's run order (verify, apply once, pay debts, final verify of Invoke-DwRecipeSet.ps1, each with -RunBy), where the set finds the site connection (the demo folder, or -SiteFolder) and which secrets the delegate inherits, the no-write rule while the delegate's apply runs, the orchestrator's ownership and the hand-in. The plan brief keeps the session read-only.
Model ids are the caller's: no default names a provider or a model. A model id or a path that holds a line break is refused. The output holds no date and nothing from the machine: the same input prints the same brief.
.PARAMETER Phase
build (default) or plan.
.PARAMETER OrchestratorModel
The model the session itself runs on. Informational: printed so the session can say it in its hand-in. Without it the brief says "the model you run on".
.PARAMETER SmallModel
The model for the recipe set run (the small tier). Required for -Phase build.
.PARAMETER MidModel
Optional. When given and different from -OrchestratorModel, routine custom pieces may go to a sub-agent on it; the orchestrator still owns and checks them.
.PARAMETER TopModel
Optional. When given and different from -OrchestratorModel, the hardest custom pieces may go up to a sub-agent on it, and the hand-in names which went up.
.PARAMETER EscalateFor
Optional names of the pieces that may go up to -TopModel. Needs -TopModel.
.PARAMETER DataFile
Path of the customer data file the delegate reads. Printed as given; otherwise a placeholder.
.PARAMETER SkillsPath
Path of the skills checkout (the folder that holds dw-demo-ledger). Printed as given; otherwise a placeholder.
.PARAMETER LogFolder
Folder for the delegate's logs and reports. Printed as given; otherwise a placeholder.
.PARAMETER OutFile
Also write the brief here (UTF-8 without BOM).
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBuildBrief.ps1 -OrchestratorModel <mid model> -SmallModel <small model> -TopModel <top model>
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBuildBrief.ps1 -SmallModel <small model> -DataFile <data file> -SkillsPath <skills> -LogFolder <logs> -OutFile <brief.md>
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBuildBrief.ps1 -Phase plan -OrchestratorModel <top model>
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('build', 'plan')][string]$Phase = 'build',
    [string]$OrchestratorModel,
    [string]$SmallModel,
    [string]$MidModel,
    [string]$TopModel,
    [string[]]$EscalateFor,
    [string]$DataFile,
    [string]$SkillsPath,
    [string]$LogFolder,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

function Get-DwBriefLines {
    # The brief as lines. Pure: no clock, no machine state, so a test pins its output.
    param([string]$Phase, [string]$Orchestrator, [string]$Small, [string]$Mid, [string]$Top, [string[]]$Escalate,
        [string]$Data, [string]$Skills, [string]$Logs)
    $self = if ($Orchestrator) { "``$Orchestrator``" } else { 'the model you run on' }
    $onModel = if ($Orchestrator) { ", on ``$Orchestrator``" } else { '' }
    $runOn = if ($Orchestrator) { "You run on ``$Orchestrator``. " } else { '' }
    $up = $Top -and $Top -ne $Orchestrator
    $down = $Mid -and $Mid -ne $Orchestrator
    $pieces = if (@($Escalate).Count) { ' (' + (@($Escalate) -join ', ') + ')' } else { '' }
    $set = if ($Skills) { "$Skills/dw-demo-ledger/scripts/Invoke-DwRecipeSet.ps1" } else { '<skills>/dw-demo-ledger/scripts/Invoke-DwRecipeSet.ps1' }
    $dataText = if ($Data) { $Data } else { '<customer data file>' }
    $logText = if ($Logs) { $Logs } else { '<log folder>' }
    if ($Phase -eq 'plan') {
        $lines = @('# Plan brief', '',
            "You are the orchestrator, planning phase$onModel. Write the impact analysis and the customer data file from the owning skills (dw-demo-base first). Make no write to the site.")
        if ($Small) { $lines += "A verify-only run of the recipe set writes nothing: hand it to a sub-agent on ``$Small``, name that model in the call that starts it, and have it pass ``-RunBy $Small``: ``$set -InputPath $dataText``." }
        if ($up) { $lines += "The judgment calls that decide the plan$pieces may go up to a sub-agent on ``$Top``; name that model in the call and say in the plan which went up." }
        $lines += @('', 'End with the plan and say which model wrote it. The build starts from its own brief: `New-DwBuildBrief.ps1 -Phase build`.')
        return $lines
    }
    $lines = @('# Build brief', '',
        "You are the orchestrator. Keep the brief and the custom work yourself. Hand the recipe set run (verify, apply once, pay debts, final verify) to a sub-agent on ``$Small``, the smallest, fastest model your agent offers, and name that model in the call that starts the sub-agent: a call without a model inherits yours. Do the same for other mechanical work. In your result, say which model ran the recipe set and which model built the rest.",
        '',
        "- ${runOn}You own the brief, the custom work, the final verify and the hand-in; delegating the set never ends your work.",
        "- The delegate runs ``$set`` in this order, each run logged to $logText with ``-ReportPath $logText/<run>.json -RunBy $Small``: verify (``-InputPath $dataText``); apply once (``-Apply``); for each ``DEBT OPEN`` or ``DEBT FAIL`` line, ``-Only <owner> -PayDebts -Apply`` once; final verify.",
        '- The delegate makes no write by hand, edits neither the data file nor a recipe, and retries nothing outside that order: a failure is reported, not repaired. It returns each log and report path, the summary table, every line that is not PASS, the last line and each exit code.',
        "- The set reads the site connection itself from the folder that holds the site's ``.mcp.json`` (and ``demo-host.json`` when there is one): the delegate runs it there or passes ``-SiteFolder <that folder>``. Only ``DW_RECIPE_SECRETS`` and ``DW_PERSONA_CREDENTIALS``, when this session has them, must reach the delegate: start its commands from this shell's environment. They have no file form; never paste a value into a brief.",
        "- Make no write to the site until the delegate's apply has ended. Meanwhile read the brief's custom work, the owning skills and the site's templates.")
    if ($down) { $lines += "- Routine custom pieces may go to a sub-agent on ``$Mid``, named in the call; you still own and check them." }
    if ($up) { $lines += "- The hardest custom pieces$pieces may go up to a sub-agent on ``$Top``, named in the call. Say in the hand-in which pieces went up. A piece you would otherwise leave unbuilt goes up; it is not left out." }
    $lines += "- The recipe set builds the data foundation, not the demo. The hand-in is due when every moment of the brief is built and checked on the site, or when you have tried a moment and can say what stopped it. Handing in with moments not attempted is an unfinished build."
    $handIn = "- The hand-in names the orchestrator ($self), the recipe set's model (``$Small``; its summary prints ``run by: $Small``) and the model that built the rest"
    if ($up) { $handIn += ", and which pieces went up to ``$Top``" }
    $lines += ($handIn + '.')
    return $lines
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
    $named = @{OrchestratorModel = $OrchestratorModel; SmallModel = $SmallModel; MidModel = $MidModel; TopModel = $TopModel; DataFile = $DataFile; SkillsPath = $SkillsPath; LogFolder = $LogFolder}
    foreach ($k in @($named.Keys | Sort-Object)) {
        if ($named[$k] -match '[\r\n]') { throw [ArgumentException]::new("-$k holds a line break; pass one line.") }
        if ($PSBoundParameters.ContainsKey($k) -and -not $named[$k].Trim()) { throw [ArgumentException]::new("-$k is empty; pass a value or leave it out.") }
    }
    foreach ($e in @($EscalateFor)) { if ($e -match '[\r\n]') { throw [ArgumentException]::new('-EscalateFor holds a line break; pass one line per piece.') } }
    # Through pwsh -File a list arrives as one argument: "a,b" is split here, as Invoke-DwRecipeSet.ps1 splits -Only.
    $escalate = @(@($EscalateFor) | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().Trim("'", '"').Trim() } | Where-Object { $_ })
    $EscalateFor = $escalate
    if ($Phase -eq 'build' -and -not $SmallModel) { throw [ArgumentException]::new('-SmallModel is required for -Phase build: the model the recipe set runs on (orchestrator.md "Model tier").') }
    if (@($EscalateFor).Count -and -not $TopModel) { throw [ArgumentException]::new('-EscalateFor needs -TopModel: the model those pieces go up to.') }
    $lines = Get-DwBriefLines -Phase $Phase -Orchestrator $OrchestratorModel.Trim() -Small $SmallModel.Trim() -Mid $MidModel.Trim() -Top $TopModel.Trim() `
        -Escalate $escalate -Data $DataFile -Skills $SkillsPath.TrimEnd('/', '\') -Logs $LogFolder.TrimEnd('/', '\')
    $lines | ForEach-Object { Write-Output $_ }
    if ($OutFile) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false)) }
    exit 0
} catch {
    $message = if ($_.Exception -is [ArgumentException]) { $_.Exception.Message } else { "New-DwBuildBrief: $($_.Exception.Message)" }
    Write-Error $message -ErrorAction Continue
    exit 1
}

<#
.SYNOPSIS
READ-ONLY. Prints the brief that starts an orchestrating demo-build session, with the model split filled in; writes only -OutFile when given.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/orchestrator.md ("Build construction for speed", "Delegating the recipe set"). A session delegates when the split is in the brief that starts it, and keeps the work on its own model when the split is only in a skill it reads later. This script makes that brief, so a launcher, a dispatcher or a person never retypes it.
The build brief sets up the measured construction: the orchestrator on the top tier; phase 1, the recipe set delegate on the small tier while the orchestrator cuts the custom work into work packages with disjoint ownership (no site write before the delegate's apply has ended); phase 2, one builder sub-agent per package in parallel, each on its tier, under the rules that keep parallel writers safe; phase 3, every moment checked on the live site by a sub-agent that did not build it, plus one cross-cutting checker, then a reset; a hand-in from the checkers' evidence only. It carries the measured split paragraph, the delegate's run order (each run with -RunBy) and where the set finds the site connection. The plan brief keeps the session read-only.
Model ids are the caller's: no default names a provider or a model. A model id or a path that holds a line break is refused. The output holds no date and nothing from the machine: the same input prints the same brief.
.PARAMETER Phase
build (default) or plan.
.PARAMETER OrchestratorModel
The model the build session itself runs on: the top tier. Printed so the session can say it in its hand-in. Without it the brief says "the model you run on".
.PARAMETER SmallModel
The model for the recipe set run and the bulk mechanical packages (the small tier). Required for -Phase build.
.PARAMETER MidModel
Optional. Routine content packages (translation batches and the like) go to it. Without it they go to -BuilderModel.
.PARAMETER TopModel
Optional. When given and different from -OrchestratorModel, the caller is starting a lower tier as orchestrator: the brief says that has not completed a build with custom work in measurement, and every custom package goes up to builders on it.
.PARAMETER BuilderModel
Optional. The model for custom template and logic packages. Default: -TopModel when it differs from -OrchestratorModel, otherwise the orchestrator's model.
.PARAMETER CheckerModel
Optional. The model for the phase 3 checkers. Default: the builder model.
.PARAMETER EscalateFor
Optional names of custom pieces that must be their own top-tier builder packages. Needs -TopModel.
.PARAMETER MaxParallel
The most builder sub-agents at once (default 8).
.PARAMETER DataFile
Path of the customer data file the delegate reads. Printed as given; otherwise a placeholder.
.PARAMETER SkillsPath
Path of the skills checkout (the folder that holds dw-demo-ledger). Printed as given; otherwise a placeholder.
.PARAMETER LogFolder
Folder for the delegate's logs and reports. Printed as given; otherwise a placeholder.
.PARAMETER OutFile
Also write the brief here (UTF-8 without BOM).
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBuildBrief.ps1 -OrchestratorModel <top model> -SmallModel <small model> -MidModel <mid model>
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBuildBrief.ps1 -OrchestratorModel <top model> -SmallModel <small model> -DataFile <data file> -SkillsPath <skills> -LogFolder <logs> -OutFile <brief.md>
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
    [string]$BuilderModel,
    [string]$CheckerModel,
    [string[]]$EscalateFor,
    [ValidateRange(1, 16)][int]$MaxParallel = 8,
    [string]$DataFile,
    [string]$SkillsPath,
    [string]$LogFolder,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

function Get-DwBriefLines {
    # The brief as lines. Pure: no clock, no machine state, so a test pins its output.
    param([string]$Phase, [string]$Orchestrator, [string]$Small, [string]$Mid, [string]$Top, [string]$Builder, [string]$Checker,
        [string[]]$Escalate, [int]$MaxParallel = 8, [string]$Data, [string]$Skills, [string]$Logs)
    $self = if ($Orchestrator) { "``$Orchestrator``" } else { 'the model you run on' }
    $onModel = if ($Orchestrator) { ", on ``$Orchestrator``" } else { '' }
    $runOn = if ($Orchestrator) { "You run on ``$Orchestrator``. " } else { '' }
    $up = $Top -and $Top -ne $Orchestrator
    if (-not $Builder) { $Builder = if ($up) { $Top } else { $Orchestrator } }
    if (-not $Checker) { $Checker = $Builder }
    $builderText = if ($Builder) { "``$Builder``" } else { 'your own model' }
    $checkerText = if ($Checker) { " on ``$Checker``" } else { '' }
    $routineText = if ($Mid) { "``$Mid``" } else { $builderText }
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
        "- ${runOn}You are the build session. Keeping the custom work means owning it: you cut it into packages, start the builders, merge and hand in. Delegating never ends your work.")
    if ($up) { $lines += "- An orchestrator below the top tier has not completed a build with custom work in measurement: every custom package goes up to a builder on ``$Top``." }
    $lines += @(
        "- Phase 1, from minute one, in parallel. The recipe set delegate runs ``$set`` in this order, each run logged to $logText with ``-ReportPath $logText/<run>.json -RunBy $Small``: verify (``-InputPath $dataText``); apply once (``-Apply``); for each ``DEBT OPEN`` or ``DEBT FAIL`` line, ``-Only <owner> -PayDebts -Apply`` once; final verify.",
        '- The delegate makes no write by hand, edits neither the data file nor a recipe, and retries nothing outside that order: a failure is reported, not repaired. It returns each log and report path, the summary table, every line that is not PASS, the last line and each exit code.',
        "- The set reads the site connection itself from the folder that holds the site's ``.mcp.json`` (and ``demo-host.json`` when there is one): the delegate runs it there or passes ``-SiteFolder <that folder>``. Only ``DW_RECIPE_SECRETS`` and ``DW_PERSONA_CREDENTIALS``, when this session has them, must reach the delegate: start its commands from this shell's environment. They have no file form; never paste a value into a brief.",
        "- Meanwhile you read the plan and cut the custom work into independent work packages. Each names the files and templates, pages and platform objects it alone may write, its moment or moments, and its acceptance check. Make no write to the site until the delegate's apply has ended.",
        "- Phase 2, as soon as the apply has ended, in one wave. First make, in one pass, every global change the packages need (currency, language layers, order states, custom fields, permissions on shared pages) and restart or recycle once. Then start one builder sub-agent per package at the same time, at most $MaxParallel at once, and name the model in every call. No package waits for another: where one needs another's output, write the contract (names, ids, URLs) into both briefs before the wave starts. Custom templates and logic$pieces on $builderText; bulk mechanical writes (stock rows, page permissions, labels) on ``$Small``; routine content such as translation batches on $routineText.",
        '- Parallel writers stay safe: ownership is disjoint, and a shared file (a shared stylesheet, a shared layout, the data file) has exactly one owner package or is edited only by you at merge. A site restart or recycle, an index rebuild or a global setting (currency, language layers, order states, permissions on shared pages) is yours alone: before the wave where you can, announced to the running builders when it cannot wait. A builder makes no test order or cart it does not remove, and reports every object it created.',
        '- The recipe set builds the data foundation, not the demo. The hand-in is due when every moment of the brief is built and checked on the site, or when a moment was tried and you can say what stopped it. Handing in with moments not attempted is an unfinished build.',
        "- Phase 3, independent check: each moment is checked on the live site by a fresh sub-agent$checkerText that did not build it, started as soon as that moment's packages report done and not after the last builder, in a real browser where the agent has one, signed in as the personas, against the brief's observable outcomes. One more checker covers: another account's data reachable by any persona or by URL, documents reachable without sign-in, leftover sample content, leftover test orders, carts or stock changes, every language's catalogue non-empty, 390 px width.",
        '- Keep a progress file from the first package on: per moment the package, its builder, its checker and the verdict so far. A session that is stopped then still leaves its state.',
        "- A failure goes back to its owning builder once. Then you reset the demo data to the plan's opening state and verify the reset.",
        "- Hand in from the checkers' evidence only: a moment holds only when a checker that did not build it saw it; otherwise it is partly or not checked, with the reason.")
    $handIn = "- The hand-in names the orchestrator ($self), the recipe set's model (``$Small``; its summary prints ``run by: $Small``), the model that built each package and the model that checked each moment"
    if ($up) { $handIn += ", and which packages went up to ``$Top``" }
    $lines += ($handIn + '.')
    return $lines
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
    $named = @{OrchestratorModel = $OrchestratorModel; SmallModel = $SmallModel; MidModel = $MidModel; TopModel = $TopModel; BuilderModel = $BuilderModel; CheckerModel = $CheckerModel; DataFile = $DataFile; SkillsPath = $SkillsPath; LogFolder = $LogFolder}
    foreach ($k in @($named.Keys | Sort-Object)) {
        if ($named[$k] -match '[\r\n]') { throw [ArgumentException]::new("-$k holds a line break; pass one line.") }
        if ($PSBoundParameters.ContainsKey($k) -and -not $named[$k].Trim()) { throw [ArgumentException]::new("-$k is empty; pass a value or leave it out.") }
    }
    foreach ($e in @($EscalateFor)) { if ($e -match '[\r\n]') { throw [ArgumentException]::new('-EscalateFor holds a line break; pass one line per piece.') } }
    # Through pwsh -File a list arrives as one argument: "a,b" is split here, as Invoke-DwRecipeSet.ps1 splits -Only.
    $escalate = @(@($EscalateFor) | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().Trim("'", '"').Trim() } | Where-Object { $_ })
    $EscalateFor = $escalate
    if ($Phase -eq 'build' -and -not $SmallModel) { throw [ArgumentException]::new('-SmallModel is required for -Phase build: the model the recipe set runs on (orchestrator.md "Model tier").') }
    if (@($EscalateFor).Count -and -not $TopModel) { throw [ArgumentException]::new('-EscalateFor needs -TopModel: the model those packages are built on.') }
    $lines = Get-DwBriefLines -Phase $Phase -Orchestrator $OrchestratorModel.Trim() -Small $SmallModel.Trim() -Mid $MidModel.Trim() -Top $TopModel.Trim() `
        -Builder $BuilderModel.Trim() -Checker $CheckerModel.Trim() -Escalate $escalate -MaxParallel $MaxParallel -Data $DataFile -Skills $SkillsPath.TrimEnd('/', '\') -Logs $LogFolder.TrimEnd('/', '\')
    $lines | ForEach-Object { Write-Output $_ }
    if ($OutFile) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false)) }
    exit 0
} catch {
    $message = if ($_.Exception -is [ArgumentException]) { $_.Exception.Message } else { "New-DwBuildBrief: $($_.Exception.Message)" }
    Write-Error $message -ErrorAction Continue
    exit 1
}

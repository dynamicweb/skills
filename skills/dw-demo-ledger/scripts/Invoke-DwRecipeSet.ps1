<#
.SYNOPSIS
WRITES: every recipe the customer data file has a section for, only with -Apply; without it the run only reads and reports.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md ("Running a whole build"). One command for a whole build: it reads one customer data file, selects every recipe whose input section the file holds (assets/recipes, minus -Skip, or only -Only), orders them by their dependsOn and runsLast declarations (the order references/recipe-index.md prints), and runs each through Invoke-DwRecipe.ps1.
Without -Apply each recipe runs verify-only once, in order. With -Apply there are three passes: (1) apply every recipe in order with its debts deferred and no probes; a debt that a later recipe names in dependsOn.debtsPaid is paid before that recipe runs; (2) pay the owed debts once, deduplicated across recipes, in the order assortments, flushes, index builds, recycle, each through the recipe that owes it (Invoke-DwRecipe.ps1 -Debts Only); (3) verify every recipe again without -Apply, so the steps report UNCHANGED and the probes decide. -PayDebts pays the debts of the selected recipes in pass 2 even when nothing changed: the host primitives (index build, assortment build, flush, recycle) on their own.
Before anything runs, a de-brand section's forbidden text found in another section of the input is refused: the next apply would write it back and the build would never settle.
Output: each recipe's own lines under a "== <recipe> <pass>" header, then "SUMMARY", a "run by: <label>" line (-RunBy, else DW_RECIPE_RUN_BY, else "not stated"), one summary table and last "recipe set: n of m recipes passed". Exit 0 only when every selected recipe passed its last pass and every debt was paid. Connection and secrets as Invoke-DwRecipe.ps1: a parameter, then DW_BASE_URL, DW_MCP_TOKEN, DW_API_TOKEN, then the demo folder (-SiteFolder, else the current directory) with the site's .mcp.json and the optional demo-host.json, resolved once for the set with one NOTE line per value naming the file; DW_RECIPE_SECRETS and DW_PERSONA_CREDENTIALS come from the environment only. A {build.*} member a selected recipe reads and the input leaves out is read from the site once, before any recipe runs: one candidate is used and named in a NOTE line, several stop the set with the candidates and the member to add. No token or secret is printed or written to the report.
.PARAMETER InputPath
Customer data file matching assets/recipe-input.schema.json.
.PARAMETER Apply
Write. Without it, or with -WhatIf, nothing is written.
.PARAMETER Only
Run only these recipe ids (their input sections must be present). A list, or one comma-separated text: through pwsh -File a list arrives as one argument, so "a,b" and "'a','b'" are split here.
.PARAMETER Skip
Leave these recipe ids out. A list, or one comma-separated text.
.PARAMETER PayDebts
With -Apply, pay every debt of the selected recipes once, even when nothing changed.
.PARAMETER LayerDelivered
Input sections a layer already delivered: their recipes run verify-only even with -Apply, unless the recipe declares layerDelivered apply.
.PARAMETER BaseUrl
Target URL, otherwise DW_BASE_URL.
.PARAMETER ApiToken
Management API credential, otherwise DW_API_TOKEN.
.PARAMETER McpToken
MCP credential, otherwise DW_MCP_TOKEN, otherwise the site folder.
.PARAMETER SiteFolder
The demo folder that holds the site's .mcp.json and, optionally, demo-host.json. A value given as a parameter or in the environment wins. Default: the current directory.
.PARAMETER McpOnly
Use the MCP tools only, as the in-product agent would.
.PARAMETER AllowSql
Permit local SQL reads; needs -SqlServer and -Database of a local install. SQL never writes.
.PARAMETER SqlServer
Local SQL server (integrated authentication).
.PARAMETER Database
Local database name.
.PARAMETER LedgerBuildFile
Ledger build declaration with its lock; with -Manifest each recipe's ledger checks run in the verify pass.
.PARAMETER Manifest
Ledger release manifest for -LedgerBuildFile.
.PARAMETER SolutionPath
Local solution root; lets a recycle debt run Restart-DwHost.ps1.
.PARAMETER ReportPath
Optional JSON report: per recipe and pass the counts and result, the debts, no values.
.PARAMETER AllowSelfSignedCertificate
Explicit TLS opt-in for a development endpoint that is not loopback.
.PARAMETER RunBy
Who ran the set, as the hand-in names it (the model a delegated run is on); otherwise DW_RECIPE_RUN_BY. Printed in the summary and the report as runBy; absent, the summary says "run by: not stated". One line.
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json -Apply -ReportPath ./recipe-set-report.json -RunBy <model>
.EXAMPLE
pwsh -NoProfile -File scripts/Invoke-DwRecipeSet.ps1 -InputPath ./recipe-input.json -Only pim.identifiers -PayDebts -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [switch]$Apply,
    [string[]]$Only, [string[]]$Skip,
    [switch]$PayDebts,
    [string[]]$LayerDelivered,
    [string]$BaseUrl, [string]$ApiToken, [string]$McpToken,
    [string]$SiteFolder,
    [switch]$McpOnly,
    [switch]$AllowSql, [string]$SqlServer, [string]$Database,
    [string]$LedgerBuildFile, [string]$Manifest,
    [string]$SolutionPath,
    [string]$ReportPath,
    [switch]$AllowSelfSignedCertificate,
    [string]$RunBy
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ledger.Core.ps1')
. (Join-Path $PSScriptRoot 'Recipe.Core.ps1')
. (Join-Path $PSScriptRoot 'Recipe.Site.ps1')
$assets = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets'))
$Only = Split-LedgerList $Only; $Skip = Split-LedgerList $Skip; $LayerDelivered = Split-LedgerList $LayerDelivered
$runner = Join-Path $PSScriptRoot 'Invoke-DwRecipe.ps1'
# Who ran the set: one line, so a label cannot forge a summary row. Absent, the summary says so.
if (-not $RunBy) { $RunBy = $env:DW_RECIPE_RUN_BY }
$RunBy = if ($RunBy) { ($RunBy -replace '\p{Cc}+', ' ').Trim() } else { '' }

function Get-RecipeSetOrder {
    # Dependencies first, ties by id, runsLast at the end: the same order validate_recipes.py prints in recipe-index.md.
    param([hashtable]$Docs)
    $ids = @($Docs.Keys | Sort-Object -CaseSensitive)
    $deps = @{}
    foreach ($id in $ids) {
        $deps[$id] = @(@($Docs[$id].dependsOn) | Where-Object { $_ -and $Docs.ContainsKey($_.recipe) -and $_.recipe -ne $id } | ForEach-Object { $_.recipe })
        if ($Docs[$id].runsLast) { $deps[$id] += @($ids | Where-Object { $_ -ne $id -and -not $Docs[$_].runsLast }) }
    }
    $order = [Collections.Generic.List[string]]::new()
    while ($order.Count -lt $ids.Count) {
        $ready = @($ids | Where-Object { $_ -notin $order -and @($deps[$_] | Where-Object { $_ -notin $order }).Count -eq 0 })
        if (-not $ready.Count) { throw (New-RecipeFault ('dependsOn forms a cycle among ' + (@($ids | Where-Object { $_ -notin $order }) -join ', '))) }
        $order.Add($ready[0])
    }
    return , $order.ToArray()
}
function Get-RecipeDebtRank([string]$Debt) {
    # Assortments before the flushes and the index builds that read them; the recycle last.
    if ($Debt -eq 'assortments') { return 0 }
    if ($Debt -like 'flush:*') { return 1 }
    if ($Debt -like 'index:*') { return 2 }
    return 3
}
function Find-RecipeForbiddenText {
    # A de-brand's forbidden text in another section: the build writes it, the de-brand replaces it, the next apply writes it back.
    param($Data)
    if (-not $Data.Contains('debrand')) { return @() }
    $texts = @(@($Data.debrand.forbidden) | ForEach-Object { if ($_ -is [Collections.IDictionary]) { $_.text } else { $_ } } | Where-Object { $_ })
    $found = foreach ($name in @($Data.Keys | Where-Object { $_ -notin @('schema', 'debrand') })) {
        $json = $Data[$name] | ConvertTo-Json -Depth 50 -Compress
        foreach ($text in $texts) { if ($json.IndexOf([string]$text, [StringComparison]::OrdinalIgnoreCase) -ge 0) { "'$text' is in section $name" } }
    }
    return @($found)
}

function Write-SetLine([string]$Line) { Write-Output $Line }
$rows = [ordered]@{}
$skipped = [ordered]@{}
$debtRows = [Collections.Generic.List[object]]::new()
$fault = $null
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('recipe-set-' + [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Force $scratch
$applied = $false
try {
    $data = Read-LedgerJson $InputPath (Join-Path $assets 'recipe-input.schema.json')
    $docs = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $assets 'recipes') -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.json' -File })) {
        $doc = Read-LedgerJson $file.FullName (Join-Path $assets 'recipe.schema.json')
        $docs[$doc.id] = $doc
    }
    foreach ($id in @($Only) + @($Skip)) { if ($id -and -not $docs.ContainsKey($id)) { throw (New-RecipeFault "Runner input: no recipe '$id'; Find-DwRecipe.ps1 lists them.") } }
    $selected = @{}
    foreach ($id in @($docs.Keys | Sort-Object -CaseSensitive)) {
        $doc = $docs[$id]; $section = $doc.inputs.section
        if ($Only -and $id -cnotin $Only) { continue }
        if ($id -cin @($Skip)) { $skipped[$id] = [ordered]@{recipe = $id; section = $section; result = 'SKIPPED'; reason = '-Skip'; passes = @()}; continue }
        if (-not $data.Contains($section)) {
            if ($Only) { throw (New-RecipeFault "Runner input: -Only names $id, and the input has no '$section' section.") }
            continue
        }
        $missing = @(@($doc.inputs.required) | Where-Object { -not (Get-RecipeValue $data[$section] $_).found })
        if ($missing.Count) { $skipped[$id] = [ordered]@{recipe = $id; section = $section; result = 'SKIPPED'; reason = "section $section has no $($missing -join ', ')"; passes = @()}; continue }
        $selected[$id] = $doc
    }
    $readBy = @($docs.Values | ForEach-Object { $_.inputs.section })
    foreach ($name in @($data.Keys | Where-Object { $_ -notin @('schema', 'build') -and $_ -notin $readBy })) { Write-SetLine "NOTE section ${name}: no recipe reads it (the layer generator's input)" }
    if (-not $selected.Count) { throw (New-RecipeFault 'Runner input: the input holds no section a recipe reads; recipe-input.schema.json names them.') }
    $loop = @(Find-RecipeForbiddenText $data)
    if ($loop.Count) { throw (New-RecipeFault ('Runner input: the de-brand would never settle: ' + ($loop -join '; ') + '. Leave the forbidden text out of every other section.')) }
    $order = Get-RecipeSetOrder $selected
    foreach ($id in $order) {
        foreach ($dep in @($selected[$id].dependsOn)) {
            if ($dep -and -not $selected.ContainsKey($dep.recipe)) { Write-SetLine "NOTE ${id}: depends on $($dep.recipe), which this run does not include; its objects must already be on the site" }
        }
    }
    $applied = $Apply -and $PSCmdlet.ShouldProcess('recipe set', 'apply the recipes and pay their debts')
    Write-SetLine "NOTE recipe set: $(if ($applied) { 'apply' } else { 'verify-only, nothing is written' }); order: $($order -join ', ')"

    # The connection, once for the set: parameter, environment, then the demo folder. Each recipe run gets the values in
    # this process (never on a command line), so it neither reads the files again nor repeats the NOTE lines.
    $conn = Resolve-RecipeConnection -SiteFolder $SiteFolder -BaseUrl $BaseUrl -ApiToken $ApiToken -McpToken $McpToken
    foreach ($note in $conn.notes) { Write-SetLine $note }
    foreach ($gap in @(Get-RecipeConnectionGaps $conn)) { if (-not ($McpOnly -and $gap -like '*Management API*')) { Write-SetLine $gap } }
    $common = @{InputPath = $InputPath}
    foreach ($name in @('SqlServer', 'Database', 'SolutionPath', 'SiteFolder')) { if ($PSBoundParameters.ContainsKey($name)) { $common[$name] = $PSBoundParameters[$name] } }
    if ($conn.baseUrl) { $common.BaseUrl = $conn.baseUrl }
    if ($conn.apiToken) { $common.ApiToken = $conn.apiToken }
    if ($conn.mcpToken) { $common.McpToken = $conn.mcpToken }
    # {build.*} a selected recipe reads and the input leaves out: read from the site once, before any recipe runs.
    $build = @{}
    if ($LedgerBuildFile) {
        $declared = Read-LedgerJson $LedgerBuildFile (Join-Path $assets 'build.schema.json')
        foreach ($k in @('areaId', 'defaultLanguage', 'pimShop')) { if ($declared.Contains($k)) { $build[$k] = $declared[$k] } }
    } elseif ($data.Contains('build')) { foreach ($k in @($data.build.Keys)) { $build[[string]$k] = $data.build[$k] } }
    $needs = @(Get-RecipeBuildNeeds @($order | ForEach-Object { $selected[$_] }) $build)
    if ($needs.Count) {
        $reader = $null
        if ($conn.mcpToken -and $conn.baseUrl) {
            Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
            $null = Connect-Dw -BaseUrl $conn.baseUrl -ApiToken $conn.apiToken -McpToken $conn.mcpToken -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
            $reader = {
                param($tool)
                $raw = Invoke-DwMcp -Tool $tool -Arguments @{} -Raw
                if ($raw.isError) { throw (New-RecipeFault "Runner input: MCP $tool answered an error result, so the build section cannot be read from the site; add it to the data file.") }
                $json = if ($raw.structuredContent) { $raw.structuredContent | ConvertTo-Json -Depth 30 -Compress } else { (@($raw.content | ForEach-Object { $_.text })) -join "`n" }
                return , (ConvertFrom-Json -InputObject $json -AsHashtable -NoEnumerate)
            }
        }
        $resolved = Resolve-RecipeBuildDefaults $needs $reader
        foreach ($note in $resolved.notes) { Write-SetLine $note }
        $common.BuildValues = $resolved.values
    }
    foreach ($name in @('McpOnly', 'AllowSql', 'AllowSelfSignedCertificate')) { if ($PSBoundParameters.ContainsKey($name)) { $common[$name] = [bool]$PSBoundParameters[$name] } }
    $verifyExtra = @{}
    if ($LedgerBuildFile) { $verifyExtra.LedgerBuildFile = $LedgerBuildFile }
    if ($Manifest) { $verifyExtra.Manifest = $Manifest }
    $script:SetRunCount = 0
    function Invoke-SetRecipe {
        # One Invoke-DwRecipe.ps1 run in this process: its lines are the output as they come; the result is $script:SetPass.
        param([string]$Id, [string]$Pass, [hashtable]$Extra)
        $script:SetRunCount++
        $report = Join-Path $scratch ("{0:d3}-{1}.json" -f $script:SetRunCount, $Id)
        $arguments = $common.Clone() + $Extra
        $arguments.Recipe = $Id; $arguments.ReportPath = $report
        Write-SetLine "== $Id $Pass"
        $lines = [Collections.Generic.List[string]]::new()
        & $runner @arguments *>&1 | ForEach-Object { $lines.Add("$_"); Write-SetLine "$_" }
        $exit = $LASTEXITCODE
        $doc = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -AsHashtable } else { @{steps = @(); checks = @(); debtsOwed = @(); passed = 0; total = 0; changed = $false} }
        $states = @{}
        foreach ($s in @($doc.steps)) { $states[$s.state] = 1 + [int]$states[$s.state] }
        $result = [ordered]@{pass = $Pass; exit = $exit; passed = [int]$doc.passed; total = [int]$doc.total; changed = [bool]$doc.changed
            created = [int]$states['CREATED']; updated = [int]$states['UPDATED']; unchanged = [int]$states['UNCHANGED']; blocked = [int]$states['BLOCKED']
            wouldCreate = [int]$states['WOULD-CREATE']; wouldUpdate = [int]$states['WOULD-UPDATE']; delivered = [int]$states['DELIVERED']; debtsOwed = @($doc.debtsOwed | Where-Object { $_ }); checks = @($doc.checks)
            notes = @($lines | Where-Object { $_.StartsWith('NOTE debt/') })}
        $script:SetPass = $result
    }
    foreach ($id in $order) { $rows[$id] = [ordered]@{recipe = $id; section = $selected[$id].inputs.section; result = $null; reason = $null; passes = [Collections.Generic.List[object]]::new()} }

    if (-not $applied) {
        if ($PayDebts) { Write-SetLine ('NOTE recipe set: -PayDebts without -Apply pays nothing; it would pay: ' + ((@($order | ForEach-Object { @($selected[$_].debts) }) | Select-Object -Unique) -join ', ')) }
        foreach ($id in $order) { Invoke-SetRecipe $id 'verify' $verifyExtra; $rows[$id].passes.Add($script:SetPass) }
    } else {
        # Pass 1: apply in order, debts deferred and owed per recipe, unless a later recipe needs one paid first.
        $owed = [Collections.Generic.List[object]]::new()
        function Invoke-SetDebts {
            param([object[]]$Debts, [string]$Why)
            # Deduplicated, ranked, and grouped per owning recipe in that order; each group is one -Debts Only run.
            $unique = [Collections.Generic.List[object]]::new()
            foreach ($d in $Debts) {
                $key = if ($d.debt -eq 'assortments') { "assortments@$($d.owner)" } else { $d.debt }
                if (-not @($unique | Where-Object { $_.key -eq $key }).Count) { $unique.Add([ordered]@{key = $key; debt = $d.debt; owner = $d.owner}) }
            }
            $ranked = @($unique | Sort-Object -Stable { Get-RecipeDebtRank $_.debt })
            $i = 0
            while ($i -lt $ranked.Count) {
                $owner = $ranked[$i].owner; $names = @()
                while ($i -lt $ranked.Count -and $ranked[$i].owner -eq $owner) { $names += $ranked[$i].debt; $i++ }
                Invoke-SetRecipe $owner "debts ($Why)" @{Apply = $true; Debts = 'Only'; DebtNames = $names; SkipVerify = $true}
                $pass = $script:SetPass
                foreach ($name in $names) {
                    $check = @($pass.checks | Where-Object { $_.name -eq "debt/$name" })[0]
                    # A debt the target does not owe (an index it does not carry) is a NOTE line, not a check: it stays a NOTE
                    # when another debt of the same run failed or stayed open.
                    $noted = @($pass.notes | Where-Object { $_.StartsWith("NOTE debt/${name}:") }).Count
                    $state = if ($check) { $check.result } elseif ($noted -or $pass.exit -eq 0) { 'NOTE' } else { 'FAIL' }
                    $debtRows.Add([ordered]@{debt = $name; owner = $owner; when = $Why; result = $state; reason = $(if ($check) { $check.reason })})
                }
            }
        }
        foreach ($id in $order) {
            foreach ($dep in @($selected[$id].dependsOn)) {
                if (-not $dep -or -not $dep.debtsPaid) { continue }
                $now = @($owed | Where-Object { $_.owner -eq $dep.recipe -and $_.debt -cin @($dep.debtsPaid) })
                if ($PayDebts -and $selected.ContainsKey($dep.recipe)) { $now = @($dep.debtsPaid | ForEach-Object { [ordered]@{debt = $_; owner = $dep.recipe} }) }
                if ($now.Count) {
                    Invoke-SetDebts $now "before $id"
                    foreach ($d in $now) { foreach ($o in @($owed | Where-Object { $_.owner -eq $d.owner -and $_.debt -eq $d.debt })) { $null = $owed.Remove($o) } }
                }
            }
            $extra = @{SkipVerify = $true}
            $delivered = $selected[$id].inputs.section -cin @($LayerDelivered) -and $selected[$id].modes.layerDelivered -ne 'apply'
            if ($delivered) { Write-SetLine "NOTE ${id}: section $($selected[$id].inputs.section) was delivered by a layer: verify-only" }
            else { $extra.Apply = $true; $extra.Debts = 'Defer' }
            Invoke-SetRecipe $id $(if ($delivered) { 'verify (layer-delivered)' } else { 'apply' }) $extra
            $pass = $script:SetPass
            $rows[$id].passes.Add($pass)
            foreach ($debt in @($pass.debtsOwed | Where-Object { $_ })) { $owed.Add([ordered]@{debt = $debt; owner = $id}) }
        }
        # Pass 2: the debts, once. -PayDebts owes every debt of every selected recipe.
        if ($PayDebts) { foreach ($id in $order) { foreach ($debt in @($selected[$id].debts)) { $owed.Add([ordered]@{debt = $debt; owner = $id}) } } }
        if ($owed.Count) { Invoke-SetDebts $owed.ToArray() 'end of the set' }
        else { Write-SetLine 'NOTE recipe set: no debt owed' }
        # Pass 3: verify every recipe; the probes decide.
        foreach ($id in $order) { Invoke-SetRecipe $id 'verify' $verifyExtra; $rows[$id].passes.Add($script:SetPass) }
    }
    foreach ($id in $order) {
        $passes = @($rows[$id].passes)
        $failed = @($passes | Where-Object { $_.exit -ne 0 })
        # An apply pass that skipped verification passes on its step checks; the last pass is the verdict on the site.
        $rows[$id].result = if ($failed.Count) { 'FAIL' } else { 'PASS' }
        if ($failed.Count) { $rows[$id].reason = 'failed in: ' + (@($failed | ForEach-Object { $_.pass }) -join ', ') }
    }
} catch {
    Write-Verbose $_.ScriptStackTrace
    $exception = $_.Exception
    $fault = if ($exception -is [IO.InvalidDataException] -or $exception -is [InvalidOperationException]) { $exception.Message } else { 'Check the input, the recipes and the connection; -Verbose shows where it stopped.' }
    Write-SetLine "FAIL recipe set: $fault"
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# The summary: one row per recipe (steps of the apply pass, checks of the last pass), then the debts.
Write-SetLine ''
Write-SetLine 'SUMMARY'
Write-SetLine "run by: $(if ($RunBy) { $RunBy } else { 'not stated' })"
foreach ($row in $rows.Values) { if (-not $row.result) { $row.result = 'NOT RUN' } }
foreach ($id in $skipped.Keys) { $rows[$id] = $skipped[$id] }
$table = foreach ($row in $rows.Values) {
    $passes = @($row.passes)
    $first = if ($passes.Count) { $passes[0] }
    $last = if ($passes.Count) { $passes[-1] }
    [pscustomobject][ordered]@{
        Recipe = $row.recipe; Section = $row.section
        Steps = $(if ($first) { 'C{0} U{1} ={2} B{3} WC{4} WU{5} D{6}' -f $first.created, $first.updated, $first.unchanged, $first.blocked, $first.wouldCreate, $first.wouldUpdate, $first.delivered } else { '-' })
        Checks = $(if ($last) { "$($last.passed)/$($last.total)" } else { '-' })
        Debts = $(if ($first -and @($first.debtsOwed).Count) { @($first.debtsOwed).Count } else { 0 })
        Result = $row.result
        Note = $row.reason
    }
}
if ($table) { ($table | Format-Table -AutoSize | Out-String -Width 220).TrimEnd() -split "`r?`n" | ForEach-Object { Write-SetLine $_ } }
foreach ($d in $debtRows) { Write-SetLine ("DEBT {0} {1} ({2}, {3})" -f $d.result, $d.debt, $d.owner, $d.when) }
$counted = @($rows.Values | Where-Object { $_.result -ne 'SKIPPED' })
$passedCount = @($counted | Where-Object { $_.result -eq 'PASS' }).Count
$debtsOk = -not @($debtRows | Where-Object { $_.result -in @('FAIL', 'OPEN') }).Count
$ok = -not $fault -and $counted.Count -gt 0 -and $passedCount -eq $counted.Count -and $debtsOk
Write-SetLine "recipe set: $passedCount of $($counted.Count) recipes passed$(if (-not $debtsOk) { '; a debt is not paid' })"
if ($ReportPath) {
    $report = [ordered]@{schema = 1; kind = 'recipe-set'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); mode = $(if ($applied) { 'apply' } else { 'verify' }); runBy = $(if ($RunBy) { $RunBy } else { $null })
        recipes = @($rows.Values | ForEach-Object { [ordered]@{recipe = $_.recipe; section = $_.section; result = $_.result; reason = $_.reason
                    passes = @(@($_.passes) | ForEach-Object { $p = [ordered]@{} + $_; $p.Remove('checks'); $p })} })
        debts = $debtRows.ToArray(); fault = $fault; passed = $passedCount; total = $counted.Count; result = $(if ($ok) { 'PASS' } else { 'FAIL' })}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
}
if ($ok) { exit 0 }
exit 1

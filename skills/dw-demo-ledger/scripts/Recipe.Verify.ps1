<#
.SYNOPSIS
READ-ONLY. Recipe probes and the bridge to the ledger checks a recipe names.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. A probe reads through the first eligible binding and asserts count, equals, contains or excludes on the rows; fewer observed subjects than minimumSubjects is FAIL, mirroring the ledger rule; a probe whose forEach finds no input item to verify is a NOTE. A probe whose bindings are all planned cannot execute and is listed as a NOTE, never as a pass. The persona sign-in probe is the ledger's own handler (Ledger.Transport.ps1), with credentials only from DW_PERSONA_CREDENTIALS. The ledger check ids run through Invoke-DwLedgerChecks.ps1 only when a build file and manifest are supplied; otherwise they are listed for a ledger run.
.EXAMPLE
. ./Recipe.Verify.ps1
#>
#Requires -Version 7.0
function Test-RecipeAssert {
    # $null when the rows satisfy the assertion; otherwise the reason. Values are not printed.
    param($Binding, [object[]]$Rows, $Context)
    $assert = $Binding.assert
    $hits = Select-RecipeMatches $Rows (Expand-RecipeValue $Binding.match $Context) $Binding.operation
    $expected = Expand-RecipeValue $assert.value $Context
    if ($assert.kind -eq 'count') {
        $n = $hits.Count
        $ok = switch ($assert.op) { 'ge' { $n -ge $expected } 'le' { $n -le $expected } default { $n -eq $expected } }
        return $(if ($ok) { $null } else { "$n matching row(s), expected $($assert.op) $expected" })
    }
    if ($hits.Count -eq 0) {
        # Name the fields that kept a single row out, never their values (a value may be personal data).
        if (@($Rows).Count -eq 1 -and $Binding.match) { return 'no row matches: ' + ((Get-RecipeDifferences $Rows[0] (Expand-RecipeValue $Binding.match $Context) $Binding.operation) -join ', ') + ' differs' }
        return 'no row matches'
    }
    foreach ($row in $hits) {
        $value = Get-RecipeRowField $row $assert.path $Binding.operation
        if ($assert.kind -eq 'excludes') {
            # No text of the expected value (a text, or a list of texts or of {text} objects) in the value or any element of it, ignoring case.
            $texts = @(foreach ($e in @($expected)) { if ($e -is [Collections.IDictionary]) { $e.text } else { $e } }) | Where-Object { $_ }
            $held = @(foreach ($v in @($value)) { foreach ($t in $texts) { if (([string]$v).Contains([string]$t, [StringComparison]::OrdinalIgnoreCase)) { $t } } })
            if ($held.Count) { return "$($assert.path) holds $($held.Count) excluded text(s)" }
            continue
        }        $ok = if ($assert.kind -eq 'equals') { Test-RecipeEqual $value $expected } else { $null -ne $value -and ([string]$value).Contains([string]$expected, [StringComparison]::Ordinal) }
        if (-not $ok) { return "$($assert.path) does not $($assert.kind -replace 'equals','equal') the expected value" }
    }
    return $null
}
function Invoke-RecipeProbe {
    param($Probe, $Run)
    $name = "probe/$($Probe.id)"
    if (@($Probe.bindings | Where-Object { $_.status -eq 'implemented' }).Count -eq 0) {
        $Run.lines.Add("NOTE ${name}: planned, not executed: " + (@($Probe.bindings | ForEach-Object { $_.reason }) -join '; '))
        $Run.planned.Add($Probe.id); return
    }
    $subjects = 0; $failures = @(); $open = @(); $index = 0; $qualified = 0; $delivered = 0
    # pollSeconds is the probe's whole budget, not each subject's: twelve subjects that never pass must not wait twelve times.
    $pollDeadline = $null; $polled = $false
    foreach ($item in (Get-RecipeItems $Run.section $Probe.forEach)) {
        $index++
        $context = New-RecipeContext $Run $item
        try {
            if (Test-RecipeCondition $Probe.skipWhen $context) { continue }
            $qualified++
            $select = Select-RecipeRead $Probe.bindings $Run.cap $Run.registry
            if (-not $select.binding) { $open += 'no eligible binding: ' + ($select.reasons -join '; '); continue }
            $binding = $select.binding
            if ($binding.handler -eq 'dwapi-persona-sign-in') {
                # The ledger's sign-in observation: one row {value}, one subject per supplied persona.
                $observation = Get-LedgerPersonaSignInObservation $binding
                $subjects += $observation.scanned
                $rows = @(@{value = $observation.value})
                if ($observation.offenders.Count) { $failures += "$($observation.offenders.Count) persona(s) did not sign in and read as themselves" }
                $fault = Test-RecipeAssert $binding $rows $context
            } else {
                $subjects++
                $rows = Read-RecipeRows $binding $context $Run
                $fault = Test-RecipeAssert $binding $rows $context
                # A state the platform publishes late or drops for a moment (a new URL answers 404 for seconds) is read again until it
                # passes or the probe's poll budget is spent; once spent, a failing subject is read once.
                if ($fault -and $Probe.pollSeconds -and -not $pollDeadline) { $pollDeadline = [DateTime]::UtcNow.AddSeconds([int]$Probe.pollSeconds) }
                while ($fault -and $pollDeadline -and [DateTime]::UtcNow -lt $pollDeadline) {
                    $polled = $true
                    Start-Sleep -Milliseconds $Run.pollIntervalMs
                    $rows = Read-RecipeRows $binding $context $Run
                    $fault = Test-RecipeAssert $binding $rows $context
                }
                if ($fault -and $polled) { $fault += " (read again for the probe's $($Probe.pollSeconds) s poll budget: $($binding.operation))" }
            }
            if ($fault -and $Probe.deliveredWith) {
                # A subject a layer delivered in its own shape is not observable in this recipe's shape: said, not failed.
                $owner = $Run.results[$Probe.deliveredWith.step]; $ownerKey = [string](Expand-RecipeValue $Probe.deliveredWith.key $context)
                if ($owner -and $owner.Contains($ownerKey) -and $owner[$ownerKey].state -eq 'DELIVERED') { $delivered++; continue }
            }
            if ($fault) { $failures += "subject ${index}: $fault" }
        } catch {
            Write-Verbose $_.ScriptStackTrace
            $exception = $_.Exception
            if ($exception -is [Collections.Generic.KeyNotFoundException] -and $exception.Data['delivered']) { $delivered++ }
            elseif ($exception -is [Collections.Generic.KeyNotFoundException]) { $failures += "subject ${index}: absent, " + $exception.Message }
            elseif ($exception -is [InvalidOperationException] -or $exception -is [UnauthorizedAccessException]) { $open += "subject ${index}: " + $exception.Message }
            elseif ($exception -is [ApplicationException]) { $failures += "subject ${index}: " + $exception.Message }
            else { $failures += "subject ${index}: the probe read failed; no response body is printed" }
        }
    }
    # The input asks nothing of this probe (no item, or every item skipped): there is nothing to verify, and it is said.
    if ($Probe.forEach -and $qualified -eq 0) { $Run.lines.Add("NOTE ${name}: no input item asks for it ($($Probe.forEach))"); return }
    if ($delivered) {
        $Run.lines.Add("NOTE ${name}: $delivered subject(s) a layer delivered in its own shape, not observable in this recipe's shape")
        $subjects -= $delivered
        if (-not $failures.Count -and -not $open.Count -and $subjects -le 0) { return }
    }
    if ($failures.Count) { Add-RecipeCheck $Run $name 'FAIL' ("$($failures.Count) failing: " + $failures[0]); return }
    if ($open.Count) { Add-RecipeCheck $Run $name 'OPEN' ("$($open.Count) not observable: " + $open[0]); return }
    if ($subjects -lt $Probe.minimumSubjects) { Add-RecipeCheck $Run $name 'FAIL' "$subjects subject(s), below the minimum of $($Probe.minimumSubjects)"; return }
    Add-RecipeCheck $Run $name 'PASS'
}
function Invoke-RecipeChildScript {
    # A shipped script in its own process, so its exit and its module import cannot touch this run. Output goes to -Verbose.
    param([string]$Path, [string[]]$Arguments, $Run)
    $saved = $env:DW_API_TOKEN, $env:DW_MCP_TOKEN
    try {
        # Credentials travel in the child's environment, never on its command line.
        if ($Run.apiToken) { $env:DW_API_TOKEN = $Run.apiToken }
        if ($Run.mcpToken) { $env:DW_MCP_TOKEN = $Run.mcpToken }
        $output = & ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -NoProfile -NonInteractive -File $Path @Arguments 2>&1
        foreach ($line in @($output)) { Write-Verbose "  $line" }
        return $LASTEXITCODE
    } finally { $env:DW_API_TOKEN, $env:DW_MCP_TOKEN = $saved }
}
function Invoke-RecipeLedger {
    param($Recipe, $Run)
    $ids = @($Recipe.verify.checkIds)
    if (-not $ids.Count) { return }
    if (-not ($Run.ledgerBuild -and $Run.manifest)) {
        foreach ($id in $ids) { $Run.lines.Add("NOTE ledger/${id}: run with the ledger (Invoke-DwLedgerChecks.ps1 with a build lock, or -LedgerBuildFile and -Manifest here)") }
        return
    }
    $report = Join-Path ([IO.Path]::GetTempPath()) ("recipe-ledger-" + [guid]::NewGuid().ToString('n') + '.json')
    $arguments = @('-Manifest', $Run.manifest, '-BuildFile', $Run.ledgerBuild, '-OutFile', $report, '-BaseUrl', $Run.baseUrl)
    if ($Run.cap.sql) { $arguments += @('-SqlServer', $Run.cap.sqlServer, '-Database', $Run.cap.database) }
    $null = Invoke-RecipeChildScript (Join-Path $PSScriptRoot 'Invoke-DwLedgerChecks.ps1') $arguments $Run
    $rows = @{}
    try { foreach ($row in @((Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -AsHashtable).checks)) { $rows[$row.id] = $row } }
    catch { foreach ($id in $ids) { Add-RecipeCheck $Run "ledger/$id" 'OPEN' 'the ledger run wrote no readable report' }; return }
    finally { Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue }
    foreach ($id in $ids) {
        if (-not $rows.Contains($id)) { Add-RecipeCheck $Run "ledger/$id" 'OPEN' 'not in the build lock'; continue }
        switch ($rows[$id].result) {
            'PASS' { Add-RecipeCheck $Run "ledger/$id" 'PASS' }
            'NOT-APPLICABLE' { Add-RecipeCheck $Run "ledger/$id" 'PASS' }
            'FAIL' { Add-RecipeCheck $Run "ledger/$id" 'FAIL' ([string]$rows[$id].reason) }
            default { Add-RecipeCheck $Run "ledger/$id" 'OPEN' ("$($rows[$id].result): " + [string]$rows[$id].reason) }
        }
    }
}

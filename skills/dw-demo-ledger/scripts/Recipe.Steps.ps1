<#
.SYNOPSIS
WRITES: through Recipe.Write.ps1, and only with -Apply. Runs one recipe step: find by natural key, create or update, read back.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Per item: find the object by its natural key (more than one match blocks the item); equal fields are UNCHANGED, different fields UPDATE, no match CREATE. Without -Apply the item reports WOULD-CREATE or WOULD-UPDATE and nothing is written. With -Apply the first binding whose write and read-back can both run here writes, and the write is read back and compared with the expected fields: a status is never the evidence. An item with no eligible binding is BLOCKED with the reason, never skipped. Every item is one check named <step>/<natural key>.
.EXAMPLE
. ./Recipe.Steps.ps1
#>
#Requires -Version 7.0
function Add-RecipeCheck {
    param($Run, [string]$Name, [ValidateSet('PASS', 'FAIL', 'OPEN')][string]$Result, [string]$Reason)
    $Name = $Name.Replace(': ', ' - ')
    $Run.checks.Add([ordered]@{name = $Name; result = $Result; reason = $Reason})
    $Run.lines.Add($(if ($Result -eq 'PASS') { "PASS $Name" } else { "$Result ${Name}: $Reason" }))
}
function Add-RecipeStepLine {
    param($Run, [string]$Step, [string]$State, [string]$Key)
    $Run.steps.Add([ordered]@{step = $Step; state = $State; key = $Key})
    if ($State -eq 'BLOCKED') { $Run.blocked++ }
    $Run.lines.Add("STEP $Step $State $Key")
}
function New-RecipeContext {
    param($Run, $Item)
    return @{input = $Run.section; item = $Item.item; parent = $Item.parent; build = $Run.build; results = $Run.results; secrets = $Run.secrets; key = $null; found = $null}
}
function Find-RecipeObject {
    # @{state = UNCHANGED | UPDATE | CREATE; row; fields} from the step's find, or $null when the step has none.
    param($Step, $Context, $Run)
    if (-not $Step.find) { return @{state = 'CREATE'; row = $null; fields = @()} }
    $select = Select-RecipeRead $Step.find.bindings $Run.cap $Run.registry
    if (-not $select.binding) { throw (New-RecipeFault ('no eligible find binding: ' + ($select.reasons -join '; '))) }
    $binding = $select.binding
    $rows = Read-RecipeRows $binding $Context $Run
    if ($binding.compareMap) {
        # The object is the set of rows (an item's fields): no rows is absent, otherwise compare name by name.
        if ($rows.Count -eq 0) { return @{state = 'CREATE'; row = $null; fields = @(); binding = $binding} }
        $differs = Get-RecipeMapDifferences $rows $binding.compareMap $Context
        return @{state = $(if ($differs.Count) { 'UPDATE' } else { 'UNCHANGED' }); row = $null; fields = $differs; binding = $binding}
    }
    $hits = Select-RecipeMatches $rows (Expand-RecipeValue $binding.match $Context) $binding.operation
    if ($hits.Count -gt 1) { throw (New-RecipeFault "$($hits.Count) objects match the natural key; resolve the duplicates before applying") }
    if ($hits.Count -eq 0) { return @{state = 'CREATE'; row = $null; fields = @(); binding = $binding} }
    $differs = if ($binding.compare) { Get-RecipeDifferences $hits[0] (Expand-RecipeValue $binding.compare $Context) $binding.operation } else { @() }
    return @{state = $(if ($differs.Count) { 'UPDATE' } else { 'UNCHANGED' }); row = $hits[0]; fields = $differs; binding = $binding}
}
function Invoke-RecipeStepItem {
    param($Step, $Context, $Run, [string]$Key, [ref]$Printed)
    $name = "$($Step.id)/$Key"
    $found = Find-RecipeObject $Step $Context $Run
    $result = @{state = $found.state; values = @{}}
    $Run.results[$Step.id][$Key] = $result
    if ($found.row) {
        $Context.found = $found.row
        $result.values = Get-RecipeProduced $found.row $found.binding.produces $found.binding.operation
    }
    if ($found.state -eq 'UNCHANGED') {
        Add-RecipeStepLine $Run $Step.id 'UNCHANGED' $Key; $Printed.Value = $true
        Add-RecipeCheck $Run $name 'PASS'; return
    }
    $action = if ($found.state -eq 'CREATE') { 'create' } else { 'update' }
    $what = if ($action -eq 'create') { 'absent' } else { 'differs from the input in ' + ($found.fields -join ', ') }
    $write = Select-RecipeWrite $Step.bindings $action $Run.cap $Run.registry
    if (-not $Run.apply) {
        $result.state = if ($action -eq 'create') { 'WOULD-CREATE' } else { 'WOULD-UPDATE' }
        Add-RecipeStepLine $Run $Step.id $result.state $Key; $Printed.Value = $true
        $tail = if ($write.binding) { "; apply would $action it" } else { "; apply has no eligible $action binding: " + ($write.reasons -join '; ') }
        Add-RecipeCheck $Run $name 'FAIL' ($what + $tail); return
    }
    if (-not $write.binding) {
        $result.state = 'BLOCKED'
        Add-RecipeStepLine $Run $Step.id 'BLOCKED' $Key; $Printed.Value = $true
        Add-RecipeCheck $Run $name 'OPEN' ("$what; no eligible $action binding: " + ($write.reasons -join '; ')); return
    }
    Invoke-RecipeWrite $write.binding $action $Context $Run
    $Run.changed = $true
    $result.state = if ($action -eq 'create') { 'CREATED' } else { 'UPDATED' }
    Add-RecipeStepLine $Run $Step.id $result.state $Key; $Printed.Value = $true
    # Every write is read back. The response of the write is not evidence: a create can answer id 0 and a save can drop a field.
    $readBack = $write.binding.readBack
    $rows = Read-RecipeRows $readBack $Context $Run
    if ($readBack.expectMap) {
        $differs = Get-RecipeMapDifferences $rows $readBack.expectMap $Context
        if ($differs.Count) { Add-RecipeCheck $Run $name 'FAIL' ('the read-back differs from the write in ' + ($differs -join ', ')); return }
        Add-RecipeCheck $Run $name 'PASS'; return
    }
    $hits = Select-RecipeMatches $rows (Expand-RecipeValue $readBack.match $Context) $readBack.operation
    if ($hits.Count -ne 1) { Add-RecipeCheck $Run $name 'FAIL' "the read-back found $($hits.Count) matching object(s), not one"; return }
    $differs = if ($readBack.expect) { Get-RecipeDifferences $hits[0] (Expand-RecipeValue $readBack.expect $Context) $readBack.operation } else { @() }
    $result.values = Get-RecipeProduced $hits[0] $readBack.produces $readBack.operation $result.values
    if ($differs.Count) { Add-RecipeCheck $Run $name 'FAIL' ('the read-back differs from the write in ' + ($differs -join ', ')); return }
    Add-RecipeCheck $Run $name 'PASS'
}
function Invoke-RecipeStep {
    param($Step, $Run)
    $Run.results[$Step.id] = @{}
    $seen = @{}
    foreach ($item in (Get-RecipeItems $Run.section $Step.forEach)) {
        $context = New-RecipeContext $Run $item
        $key = $null; $printed = $false
        try {
            if (Test-RecipeCondition $Step.skipWhen $context) { continue }
            $key = [string](Expand-RecipeValue $Step.key $context)
            $context.key = $key
            if ($Step.after) {
                $prior = $Run.results[$Step.after.step]
                if (-not $prior -or -not $prior.Contains($key) -or $prior[$key].state -notin @($Step.after.states)) { continue }
            }
            if ($seen.Contains($key)) { throw (New-RecipeFault 'the input names this natural key twice') }
            $seen[$key] = $true
            Invoke-RecipeStepItem $Step $context $Run $key ([ref]$printed)
        } catch [Collections.Generic.KeyNotFoundException] {
            # A value this item needs comes from an object that does not exist yet.
            if (-not $key) { $key = '(no key)' }
            $state = if ($Run.apply) { 'BLOCKED' } else { 'WOULD-CREATE' }
            $Run.results[$Step.id][$key] = @{state = $state; values = @{}}
            if (-not $printed) { Add-RecipeStepLine $Run $Step.id $state $key }
            if ($Run.apply) { Add-RecipeCheck $Run "$($Step.id)/$key" 'OPEN' ($_.Exception.Message + '; nothing to write to') }
            else { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' ('absent: ' + $_.Exception.Message + '; apply would create it') }
        } catch {
            if (-not $key) { $key = '(no key)' }
            Write-Verbose $_.ScriptStackTrace
            if (-not $printed) {
                Add-RecipeStepLine $Run $Step.id 'BLOCKED' $key
                $Run.results[$Step.id][$key] = @{state = 'BLOCKED'; values = @{}}
            }
            # A named input or contract fault is printed; anything else may carry a response body, so it stays generic.
            $exception = $_.Exception
            if ($exception -is [InvalidOperationException] -or $exception -is [UnauthorizedAccessException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'OPEN' $exception.Message }
            elseif ($exception -is [ApplicationException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' $exception.Message }
            else { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' 'the binding call failed; check the operation, grants and target (-Verbose shows where); no response body is printed' }
        }
    }
}

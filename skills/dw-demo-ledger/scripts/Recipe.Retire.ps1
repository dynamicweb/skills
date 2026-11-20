<#
.SYNOPSIS
WRITES: through Recipe.Write.ps1, and only with -Apply. Runs one retire step: every active row a read returns that the input does not name is set inactive, never deleted.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. A retire step runs once per natural key (items that share a key are one set). It first resolves retire.named, what the input names for this set: nothing named refuses the item, so a retire can never empty a set. A step named in retire.requires that blocked an item refuses it too, because then what the input names is not known by id. The read (retire.binding) returns the set; a row whose retire.active.field equals retire.active.value is active, and an active row whose member equals one of the values of any retire.keep rule stays. The rest is retired, each named by its identify members. More than retire.max rows refuses the item. Without -Apply each row reports WOULD-RETIRE and fails with where it is. With -Apply each is written through the first eligible update binding, whose arguments read the row as {row.<member>}, and read back: the read-back must no longer return the row as active. Nothing to retire is UNCHANGED.
.EXAMPLE
. ./Recipe.Retire.ps1
#>
#Requires -Version 7.0
function Get-RecipeRetireValues {
    # A token's value as a flat list without empty entries: one value, a list, or nothing.
    param($Token, $Context)
    $raw = Expand-RecipeValue $Token $Context
    return , @(foreach ($v in @($raw)) { if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { $v } })
}
function Test-RecipeRetireKept {
    param($Row, [object[]]$Rules)
    foreach ($rule in $Rules) {
        $field = Get-RecipeValue $Row $rule.field
        if ($field.found -and @($rule.values | Where-Object { Test-RecipeEqual $field.value $_ }).Count) { return $true }
    }
    return $false
}
function Invoke-RecipeRetireStep {
    param($Step, $Run)
    $Run.results[$Step.id] = @{}
    $retire = $Step.retire
    $seen = @{}
    foreach ($item in (Get-RecipeItems $Run.section $Step.forEach)) {
        $context = New-RecipeContext $Run $item
        $key = $null
        try {
            if (Test-RecipeCondition $Step.skipWhen $context) { continue }
            $key = [string](Expand-RecipeValue $Step.key $context)
            # Items that share a key are one set (every payment method of the input is one payment set).
            if ($seen.Contains($key)) { continue }
            $seen[$key] = $true
            $context.key = $key
            $named = Get-RecipeRetireValues $retire.named $context
            if (-not $named.Count) { throw (New-RecipeFault 'refused: the input names nothing in this set, and a retire never empties a set; nothing is retired') }
            foreach ($stepId in @($retire.requires)) {
                $blocked = @($Run.results[$stepId].Values | Where-Object { $_.state -eq 'BLOCKED' }).Count
                if ($blocked) { throw (New-RecipeFault "refused: step '$stepId' blocked $blocked item(s), so what the input names is not known by id; nothing is retired") }
            }
            $rules = @(foreach ($rule in @($retire.keep)) { @{field = $rule.field; values = (Get-RecipeRetireValues $rule.values $context)} })
            $operation = [string]$retire.binding.operation
            $rows = Read-RecipeRows $retire.binding $context $Run
            $active = @($rows | Where-Object { $m = Get-RecipeValue $_ $retire.active.field; $m.found -and (Test-RecipeEqual $m.value $retire.active.value) })
            $go = @($active | Where-Object { -not (Test-RecipeRetireKept $_ $rules) })
            $Run.results[$Step.id][$key] = @{state = 'UNCHANGED'; values = @{}}
            if (-not $go.Count) { Add-RecipeStepLine $Run $Step.id 'UNCHANGED' $key; Add-RecipeCheck $Run "$($Step.id)/$key" 'PASS'; continue }
            if ($go.Count -gt [int]$retire.max) { throw (New-RecipeFailure "refused: $($go.Count) active row(s) of '$operation' the input does not name, more than retire.max $($retire.max); nothing is retired") }
            $write = Select-RecipeWrite $Step.bindings 'update' $Run.cap $Run.registry
            foreach ($row in $go) {
                $place = Get-RecipeScanPlace $row $retire $operation
                $name = "$($Step.id)/$key@$place"
                if (-not $Run.apply) {
                    Add-RecipeStepLine $Run $Step.id 'WOULD-RETIRE' "$key@$place"
                    $tail = if ($write.binding) { 'apply would set it inactive' } else { 'apply cannot: ' + ($write.reasons -join '; ') }
                    Add-RecipeCheck $Run $name 'FAIL' "active and the input does not name it; $tail"; continue
                }
                if (-not $write.binding) {
                    Add-RecipeStepLine $Run $Step.id 'BLOCKED' "$key@$place"
                    Add-RecipeCheck $Run $name 'OPEN' ('active and the input does not name it; no eligible update binding: ' + ($write.reasons -join '; ')); continue
                }
                $context.row = $row
                Invoke-RecipeWrite $write.binding 'update' $context $Run
                $Run.changed = $true
                Add-RecipeStepLine $Run $Step.id 'RETIRED' "$key@$place"
                # The answer of the save is not the evidence: the read-back must no longer return the row as active.
                $readBack = $write.binding.readBack
                # Assigned first: the read returns its rows as one list object, which a pipeline would not enumerate.
                $back = Read-RecipeRows $readBack $context $Run
                $back = @($back | Where-Object { (Get-RecipeScanPlace $_ $retire ([string]$readBack.operation)) -eq $place })
                $still = @($back | Where-Object { $m = Get-RecipeValue $_ $retire.active.field; $m.found -and (Test-RecipeEqual $m.value $retire.active.value) })
                if ($still.Count) { Add-RecipeCheck $Run $name 'FAIL' 'the read-back still returns it active'; continue }
                Add-RecipeCheck $Run $name 'PASS'
            }
            $Run.results[$Step.id][$key].state = if ($Run.apply) { 'RETIRED' } else { 'WOULD-RETIRE' }
            $Run.lines.Add("NOTE $($Step.id)/${key}: $($go.Count) active row(s) the input does not name $(if ($Run.apply) { 'set inactive' } else { 'would be set inactive' }), none deleted; $($active.Count - $go.Count) kept")
        } catch {
            if (-not $key) { $key = '(no key)' }
            Write-Verbose $_.ScriptStackTrace
            $exception = $_.Exception
            # The set's owner does not exist yet (a page a verify run would create): nothing to retire from until apply creates it.
            $absent = $exception -is [Collections.Generic.KeyNotFoundException]
            $state = if ($absent -and -not $Run.apply) { 'WOULD-CREATE' } else { 'BLOCKED' }
            Add-RecipeStepLine $Run $Step.id $state $key
            $Run.results[$Step.id][$key] = @{state = $state; values = @{}}
            if ($state -eq 'WOULD-CREATE') { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' ('absent: ' + $exception.Message + '; apply would create it first') }
            elseif ($absent -or $exception -is [InvalidOperationException] -or $exception -is [UnauthorizedAccessException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'OPEN' $exception.Message }
            elseif ($exception -is [ApplicationException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' $exception.Message }
            else { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' 'the retire failed; check the operation, grants and target (-Verbose shows where); no response body is printed' }
        }
    }
}

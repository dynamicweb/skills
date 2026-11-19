<#
.SYNOPSIS
WRITES: deletes, through Recipe.Write.ps1 and only with -Apply. Runs one prune step: the rows a scoped read returns that the input does not name are removed.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. A prune step resolves its scope first: prune.scope.values names, from the input, the owners whose rows may be removed (the buyer accounts a history names). A scope that resolves to nothing (no value, an empty text, an empty list or the id 0) refuses the step before any read. For each scope value the step reads through prune.binding, whose arguments must carry {scope}, and keeps the rows its match selects. Every row must carry prune.scope.member equal to that scope value; one row outside the scope refuses the whole item and nothing is deleted. A row whose prune.keep.field equals one of prune.keep.values (the input's natural keys) is kept; the remainder is the set to remove, named by its identify members. More than prune.max rows refuses the item. Without -Apply each row reports WOULD-DELETE and fails with where it is. With -Apply each row is removed through the first eligible delete binding (on recipeDeleteTools), whose arguments read the row as {row.<member>}, and the read-back must no longer return it. A set with nothing to remove is UNCHANGED.
.EXAMPLE
. ./Recipe.Prune.ps1
#>
#Requires -Version 7.0
function Get-RecipePruneScope {
    # The scope values, as a list. An empty scope is a refusal: a prune never runs unscoped.
    param($Prune, $Context)
    $raw = Expand-RecipeValue $Prune.scope.values $Context
    $values = @(foreach ($v in @($raw)) { if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v) -and [string]$v -ne '0') { $v } })
    if (-not $values.Count) { throw (New-RecipeFault 'refused: the prune scope is empty; a prune removes only rows of the owners the input names') }
    return , $values
}
function Invoke-RecipePruneStep {
    param($Step, $Run)
    $Run.results[$Step.id] = @{}
    $prune = $Step.prune
    foreach ($item in (Get-RecipeItems $Run.section $Step.forEach)) {
        $context = New-RecipeContext $Run $item
        $key = $null
        try {
            if (Test-RecipeCondition $Step.skipWhen $context) { continue }
            $key = [string](Expand-RecipeValue $Step.key $context)
            $context.key = $key
            if (($prune.binding.arguments | ConvertTo-Json -Depth 30 -Compress) -notmatch '\{scope[}|.]') { throw (New-RecipeFault 'refused: the prune read does not pass {scope} in its arguments, so it is not filtered to the owners the input names') }
            $scopes = Get-RecipePruneScope $prune $context
            # Assigned first: the token returns its list as one object, which @() around the call would wrap again.
            $keep = Expand-RecipeValue $prune.keep.values $context
            $keep = @($keep)
            $operation = [string]$prune.binding.operation
            $remove = [Collections.Generic.List[object]]::new()
            foreach ($scope in $scopes) {
                $context.scope = $scope
                $rows = Read-RecipeRows $prune.binding $context $Run
                $rows = Select-RecipeMatches $rows (Expand-RecipeValue $prune.binding.match $context) $operation
                # The read's own filter is not trusted: a row of another owner refuses the item before anything is deleted.
                $outside = @($rows | Where-Object { $m = Get-RecipeValue $_ $prune.scope.member; -not $m.found -or -not (Test-RecipeEqual $m.value $scope) })
                if ($outside.Count) { throw (New-RecipeFailure "refused: $($outside.Count) row(s) of '$operation' are outside the scope ($($prune.scope.member)); nothing is deleted") }
                foreach ($row in $rows) {
                    # An absent key member is an unnamed row (the read models leave a null member out), so it is not kept.
                    $field = Get-RecipeValue $row $prune.keep.field
                    $kept = $field.found -and @($keep | Where-Object { Test-RecipeEqual $field.value $_ }).Count
                    if (-not $kept) { $remove.Add(@{row = $row; scope = $scope; place = (Get-RecipeScanPlace $row $prune $operation)}) }
                }
            }
            $Run.results[$Step.id][$key] = @{state = 'UNCHANGED'; values = @{}}
            if (-not $remove.Count) { Add-RecipeStepLine $Run $Step.id 'UNCHANGED' $key; Add-RecipeCheck $Run "$($Step.id)/$key" 'PASS'; continue }
            if ($remove.Count -gt [int]$prune.max) { throw (New-RecipeFailure "refused: $($remove.Count) row(s) to remove, more than prune.max $($prune.max); nothing is deleted") }
            $write = Select-RecipeWrite $Step.bindings 'delete' $Run.cap $Run.registry
            foreach ($r in $remove) {
                $name = "$($Step.id)/$key@$($r.place)"
                if (-not $Run.apply) {
                    Add-RecipeStepLine $Run $Step.id 'WOULD-DELETE' "$key@$($r.place)"
                    $tail = if ($write.binding) { 'apply would delete it' } else { 'apply cannot: ' + ($write.reasons -join '; ') }
                    Add-RecipeCheck $Run $name 'FAIL' "the input does not name it; $tail"; continue
                }
                if (-not $write.binding) {
                    Add-RecipeStepLine $Run $Step.id 'BLOCKED' "$key@$($r.place)"
                    Add-RecipeCheck $Run $name 'OPEN' ('the input does not name it; no eligible delete binding: ' + ($write.reasons -join '; ')); continue
                }
                $context.row = $r.row; $context.scope = $r.scope
                Invoke-RecipeWrite $write.binding 'delete' $context $Run
                $Run.changed = $true
                Add-RecipeStepLine $Run $Step.id 'DELETED' "$key@$($r.place)"
                # The delete's answer is not the evidence: the read-back must no longer return the row.
                $readBack = $write.binding.readBack
                $back = Read-RecipeRows $readBack $context $Run
                $back = Select-RecipeMatches $back (Expand-RecipeValue $readBack.match $context) ([string]$readBack.operation)
                $still = @($back | Where-Object { (Get-RecipeScanPlace $_ $prune ([string]$readBack.operation)) -eq $r.place })
                if ($still.Count) { Add-RecipeCheck $Run $name 'FAIL' 'the read-back still returns the row'; continue }
                Add-RecipeCheck $Run $name 'PASS'
            }
            $Run.results[$Step.id][$key].state = if ($Run.apply) { 'DELETED' } else { 'WOULD-DELETE' }
        } catch {
            if (-not $key) { $key = '(no key)' }
            Write-Verbose $_.ScriptStackTrace
            Add-RecipeStepLine $Run $Step.id 'BLOCKED' $key
            $Run.results[$Step.id][$key] = @{state = 'BLOCKED'; values = @{}}
            $exception = $_.Exception
            if ($exception -is [InvalidOperationException] -or $exception -is [UnauthorizedAccessException] -or $exception -is [Collections.Generic.KeyNotFoundException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'OPEN' $exception.Message }
            elseif ($exception -is [ApplicationException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' $exception.Message }
            else { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' 'the prune failed; check the operation, grants and target (-Verbose shows where); no response body is printed' }
        }
    }
}

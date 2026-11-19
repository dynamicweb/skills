<#
.SYNOPSIS
WRITES: through Recipe.Write.ps1, and only with -Apply. Runs one scan step: every row a read returns whose text holds the item's text is one place, replaced or reported.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. A scan step reads through its binding (following the response's paging when the scan names it), and each row whose text member contains the item's text (ordinal, ignoring case) is one place, named by the row's identify members; a row that leaves the text member out holds no text. Without -Apply each place reports WOULD-UPDATE and fails with where it is. With -Apply the first eligible update binding writes the place, its arguments reading the row as {row.<member>} and the replaced text as {replaced:row.<member>}, and the read-back must show the row without the text. A scan with no eligible write binding reports each place OPEN with its reason. An item with no place is UNCHANGED.
.EXAMPLE
. ./Recipe.Scan.ps1
#>
#Requires -Version 7.0
function Read-RecipeScanRows {
    # Every row of the scan's read; with scan.page, the pages the response announces, up to scan.page.max calls.
    param($Scan, $Context, $Run)
    $binding = $Scan.binding
    if (-not $Scan.page) { return , (Read-RecipeRows $binding $Context $Run) }
    $fault = Get-RecipeSurfaceFault $binding ([string]$binding.operation) 'read' $Run.cap $Run.registry
    if ($fault) { throw (New-RecipeFault "Read refused before the call: $fault.") }
    if ($binding.surface -ne 'mcp') { throw (New-RecipeFault 'A paged scan reads through MCP only.') }
    $rows = [Collections.Generic.List[object]]::new(); $skip = 0
    for ($call = 0; $call -lt [int]$Scan.page.max; $call++) {
        $arguments = Expand-RecipeValue $binding.arguments $Context
        $arguments[$Scan.page.argument] = $skip
        $data = Invoke-RecipeMcpCall ([string]$binding.operation) $arguments $Run.cap 120
        $member = Get-RecipeValue $data $binding.rows
        if (-not $member.found) { throw (New-RecipeFault "Response of '$($binding.operation)' has no member '$($binding.rows)'; the projection is not the one the recipe states.") }
        foreach ($r in @($member.value)) { if ($null -ne $r) { $rows.Add($r) } }
        if (-not (Get-RecipeValue $data $Scan.page.more).value) { return , $rows.ToArray() }
        $skip = [int](Get-RecipeValue $data $Scan.page.next).value
    }
    throw (New-RecipeFault "The scan read more than $($Scan.page.max) pages; raise scan.page.max or narrow the read.")
}
function Get-RecipeScanPlace {
    param($Row, $Scan, [string]$Operation)
    return (@(foreach ($m in $Scan.identify) { [string](Get-RecipeRowField $Row $m $Operation) }) -join '/')
}
function Invoke-RecipeScanStep {
    param($Step, $Run)
    $Run.results[$Step.id] = @{}
    $scan = $Step.scan
    foreach ($item in (Get-RecipeItems $Run.section $Step.forEach)) {
        $context = New-RecipeContext $Run $item
        $key = $null
        try {
            if (Test-RecipeCondition $Step.skipWhen $context) { continue }
            $key = [string](Expand-RecipeValue $Step.key $context)
            $context.key = $key
            $text = [string](Expand-RecipeValue $scan.text $context)
            if (-not $text) { throw (New-RecipeFault 'the scan text is empty') }
            $context.replace = @{text = $text; with = [string](Expand-RecipeValue $scan.replacement $context)}
            $operation = [string]$scan.binding.operation
            # Assigned first: the read returns its rows as one list object, which a pipeline would not enumerate.
            $all = Read-RecipeScanRows $scan $context $Run
            $hits = @($all | Where-Object { ([string](Get-RecipeValue $_ $scan.field).value).Contains($text, [StringComparison]::OrdinalIgnoreCase) })
            $Run.results[$Step.id][$key] = @{state = 'UNCHANGED'; values = @{}}
            if (-not $hits.Count) { Add-RecipeStepLine $Run $Step.id 'UNCHANGED' $key; Add-RecipeCheck $Run "$($Step.id)/$key" 'PASS'; continue }
            $write = if (@($Step.bindings).Count) { Select-RecipeWrite $Step.bindings 'update' $Run.cap $Run.registry } else { @{binding = $null; reasons = @("no write binding: $($scan.unwritable)")} }
            $batched = $false
            if ($Run.apply -and $write.binding -and $scan.batch) {
                # One call carries every place: the list member scan.batch of each place's arguments, joined. A tool that
                # saves a page per call can drop a write to one field of a paragraph another write of the same page saves again.
                $elements = [Collections.Generic.List[object]]::new(); $arguments = $null
                foreach ($hit in $hits) {
                    $context.row = $hit
                    $arguments = Expand-RecipeValue $write.binding.update.arguments $context
                    foreach ($e in @($arguments[$scan.batch])) { $elements.Add($e) }
                }
                $arguments[$scan.batch] = $elements.ToArray()
                Invoke-RecipeWrite $write.binding 'update' $context $Run $arguments
                $Run.changed = $true; $batched = $true
            }
            foreach ($hit in $hits) {
                $place = Get-RecipeScanPlace $hit $scan $operation
                $name = "$($Step.id)/$key@$place"
                if (-not $Run.apply) {
                    Add-RecipeStepLine $Run $Step.id 'WOULD-UPDATE' "$key@$place"
                    $tail = if ($write.binding) { 'apply would replace it' } else { 'apply cannot: ' + ($write.reasons -join '; ') }
                    Add-RecipeCheck $Run $name 'FAIL' "$($scan.field) at $place holds the text; $tail"; continue
                }
                if (-not $write.binding) {
                    Add-RecipeStepLine $Run $Step.id 'BLOCKED' "$key@$place"
                    Add-RecipeCheck $Run $name 'OPEN' "$($scan.field) at $place holds the text; " + ($write.reasons -join '; '); continue
                }
                $context.row = $hit
                if (-not $batched) { Invoke-RecipeWrite $write.binding 'update' $context $Run; $Run.changed = $true }
                Add-RecipeStepLine $Run $Step.id 'UPDATED' "$key@$place"
                $rbOp = [string]$write.binding.readBack.operation
                $backRows = Read-RecipeRows $write.binding.readBack $context $Run
                $back = @($backRows | Where-Object { (Get-RecipeScanPlace $_ $scan $rbOp) -eq $place })
                if ($back.Count -ne 1) { Add-RecipeCheck $Run $name 'FAIL' "the read-back found $($back.Count) row(s) at the place, not one"; continue }
                if (([string](Get-RecipeValue $back[0] $scan.field).value).Contains($text, [StringComparison]::OrdinalIgnoreCase)) { Add-RecipeCheck $Run $name 'FAIL' 'the read-back still holds the text'; continue }
                Add-RecipeCheck $Run $name 'PASS'
            }
        } catch {
            if (-not $key) { $key = '(no key)' }
            Write-Verbose $_.ScriptStackTrace
            Add-RecipeStepLine $Run $Step.id 'BLOCKED' $key
            $exception = $_.Exception
            if ($exception -is [InvalidOperationException] -or $exception -is [UnauthorizedAccessException] -or $exception -is [Collections.Generic.KeyNotFoundException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'OPEN' $exception.Message }
            elseif ($exception -is [ApplicationException]) { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' $exception.Message }
            else { Add-RecipeCheck $Run "$($Step.id)/$key" 'FAIL' 'the scan failed; check the operation, grants and target (-Verbose shows where); no response body is printed' }
        }
    }
}

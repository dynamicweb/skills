<#
.SYNOPSIS
WRITES: through Recipe.Write.ps1, and only with -Apply. Runs one recipe step: find by natural key, create or update, read back.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Per item: find the object by its natural key (more than one match blocks the item); equal fields are UNCHANGED, different fields UPDATE, no match CREATE. Without -Apply the item reports WOULD-CREATE or WOULD-UPDATE and nothing is written. With -Apply the first binding whose write and read-back can both run here writes, and the write is read back and compared with the expected fields: a status is never the evidence. An item with no eligible binding is BLOCKED with the reason, never skipped. Every item is one check named <step>/<natural key>. A layer copy that delivered the object under its own keys is found by the step's find.delivered read (only when the find matched nothing) and reported DELIVERED, never written; an item of a delivered object (deliveredWith) that would be created or changed is DELIVERED too, a NOTE and not a check.
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
    return @{input = $Run.section; item = $Item.item; parent = $Item.parent; build = $Run.build; results = $Run.results; secrets = $Run.secrets; inputDir = $Run.inputDir; key = $null; found = $null}
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
    $hits = Select-RecipeBindingMatches $rows $binding $Context
    if ($hits.Count -gt 1) { throw (New-RecipeFault "$($hits.Count) objects match the natural key; resolve the duplicates before applying") }
    if ($hits.Count -eq 0) {
        $layer = Find-RecipeDelivered $Step $Context $Run
        if ($layer) { return $layer }
        return @{state = 'CREATE'; row = $null; fields = @(); binding = $binding}
    }
    $differs = if ($binding.compare) { Get-RecipeDifferences $hits[0] (Expand-RecipeValue $binding.compare $Context) $binding.operation $binding.unordered } else { @() }
    return @{state = $(if ($differs.Count) { 'UPDATE' } else { 'UNCHANGED' }); row = $hits[0]; fields = $differs; binding = $binding}
}
function Select-RecipeBindingMatches {
    # The rows a read binding's match selects: members named in ignoreCase compare as text ignoring case (a folder that
    # exists with other letter case), every other member as Select-RecipeMatches does; then matchSuffix.
    param([object[]]$Rows, $Binding, $Context)
    $match = Expand-RecipeValue $Binding.match $Context
    foreach ($k in @($Binding.ignoreCase)) {
        if (-not $k -or -not $match -or -not $match.Contains($k)) { continue }
        $want = [string]$match[$k]; $match.Remove($k)
        $Rows = @($Rows | Where-Object { $v = Get-RecipeValue $_ $k; $v.found -and [string]::Equals([string]$v.value, $want, [StringComparison]::OrdinalIgnoreCase) })
    }
    $hits = Select-RecipeMatches $Rows $match $Binding.operation
    if ($Binding.matchSuffix) { $hits = Select-RecipeSuffixMatches $hits (Expand-RecipeValue $Binding.matchSuffix $Context) }
    return , @($hits)
}
function Update-RecipeSpelling {
    # respell: once its step has run, every input text that starts with "from" in other letter case starts with "to"
    # instead, so a folder that already exists as /Files/Images/Rhino keeps that spelling in every later write and read.
    param($Recipe, $Run, [string]$StepId)
    $spec = $Recipe.respell
    if (-not $spec -or $spec.step -ne $StepId) { return }
    $context = New-RecipeContext $Run @{item = $null; parent = $null}
    try { $from = [string](Expand-RecipeValue $spec.from $context); $to = [string](Expand-RecipeValue $spec.to $context) } catch { return }
    if (-not $from -or -not $to -or $from -ceq $to -or -not [string]::Equals($from, $to, [StringComparison]::OrdinalIgnoreCase)) { return }
    $walk = {
        param($node)
        if ($node -is [Collections.IDictionary]) { foreach ($k in @($node.Keys)) { if ($node[$k] -is [string]) { if ($node[$k].StartsWith($from, [StringComparison]::OrdinalIgnoreCase)) { $node[$k] = $to + $node[$k].Substring($from.Length) } } else { & $walk $node[$k] } } }
        elseif ($node -is [Collections.IList]) { for ($i = 0; $i -lt $node.Count; $i++) { if ($node[$i] -is [string]) { if ($node[$i].StartsWith($from, [StringComparison]::OrdinalIgnoreCase)) { $node[$i] = $to + $node[$i].Substring($from.Length) } } else { & $walk $node[$i] } } }
    }
    & $walk $Run.section
    $Run.lines.Add("NOTE ${StepId}: the folder exists as $to; every later path of the input takes that spelling")
}
function Select-RecipeSuffixMatches {
    # matchSuffix: a row matches only when each named member's text ends with the given text, ignoring case: a file a
    # layer stored under its own folder is found by its file name. A row without the member does not match.
    param([object[]]$Rows, $Suffix)
    if (-not $Suffix -or $Suffix.Count -eq 0) { return , @($Rows) }
    $hits = foreach ($row in $Rows) {
        $ok = $true
        foreach ($k in @($Suffix.Keys)) {
            $v = Get-RecipeValue $row $k
            if (-not $v.found -or -not ([string]$v.value).EndsWith([string]$Suffix[$k], [StringComparison]::OrdinalIgnoreCase)) { $ok = $false; break }
        }
        if ($ok) { , $row }
    }
    return , @($hits)
}
function Find-RecipeDelivered {
    # find.delivered: the shape a layer copy delivers the object in, under keys this recipe does not write. Read only
    # when the find matched nothing; one matching row or more is the object the layer delivered. $null when absent.
    param($Step, $Context, $Run)
    if (-not $Step.find.delivered) { return $null }
    $select = Select-RecipeRead $Step.find.delivered $Run.cap $Run.registry
    if (-not $select.binding) { return $null }
    $binding = $select.binding
    $rows = Read-RecipeRows $binding $Context $Run
    $hits = Select-RecipeBindingMatches $rows $binding $Context
    if ($hits.Count -eq 0) { return $null }
    # Values are produced only from one row: several rows prove the delivery, not which one a dependant reads.
    return @{state = 'DELIVERED'; row = $(if ($hits.Count -eq 1) { $hits[0] }); fields = @(); binding = $binding}
}
function Get-RecipeDeliveredOwner {
    # deliveredWith: the object this item belongs to, when a layer delivered it ("categories 'tools'"), else $null.
    param($Step, $Context, $Run, [string]$Key)
    if (-not $Step.deliveredWith) { return $null }
    $ownerKey = if ($Step.deliveredWith.key) { [string](Expand-RecipeValue $Step.deliveredWith.key $Context) } else { $Key }
    $owner = $Run.results[$Step.deliveredWith.step]
    if ($owner -and $owner.Contains($ownerKey) -and $owner[$ownerKey].state -eq 'DELIVERED') { return "$($Step.deliveredWith.step) '$ownerKey'" }
    return $null
}
function Set-RecipeDelivered {
    # An object a layer owns: reported, never written. Observed under the layer's keys it is a passing check;
    # one that hangs off a delivered object is a NOTE, because nothing of it was read in this recipe's shape.
    param($Run, $Step, [string]$Key, [string]$Why, [switch]$Observed)
    if (-not $Run.results[$Step.id].Contains($Key)) { $Run.results[$Step.id][$Key] = @{state = 'DELIVERED'; values = @{}} } else { $Run.results[$Step.id][$Key].state = 'DELIVERED' }
    Add-RecipeStepLine $Run $Step.id 'DELIVERED' $Key
    if ($Observed) { Add-RecipeCheck $Run "$($Step.id)/$Key" 'PASS' }
    $Run.lines.Add("NOTE $($Step.id)/${Key}: $Why; not written")
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
    if ($found.state -eq 'DELIVERED') {
        Set-RecipeDelivered $Run $Step $Key "a layer delivered it under its own keys ($($found.binding.operation))" -Observed; $Printed.Value = $true; return
    }
    if ($found.state -eq 'UNCHANGED') {
        Add-RecipeStepLine $Run $Step.id 'UNCHANGED' $Key; $Printed.Value = $true
        Add-RecipeCheck $Run $name 'PASS'; return
    }
    # What a layer delivered stays the layer's: an item that would be created in it or changed is reported, not written.
    $owner = Get-RecipeDeliveredOwner $Step $Context $Run $Key
    if ($owner) { Set-RecipeDelivered $Run $Step $Key "belongs to $owner, which a layer delivered"; $Printed.Value = $true; return }
    $action = if ($found.state -eq 'CREATE') { 'create' } else { 'update' }
    $what = if ($action -eq 'create') { 'absent' } else { 'differs from the input in ' + ($found.fields -join ', ') }
    # A step without write bindings is a lookup: it finds and produces values, and an absent object stops its dependants.
    $write = if (@($Step.bindings).Count) { Select-RecipeWrite $Step.bindings $action $Run.cap $Run.registry } else { @{binding = $null; reasons = @('a lookup step never writes; the object must exist before this recipe runs')} }
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
    $check = Read-RecipeWriteBack $readBack $Context $Run
    # resave: a save the platform is measured to settle only on a second call (it removes one stored row per key, so a
    # key stored twice survives the first save). Said in a NOTE; the second read-back is the evidence, and it may still fail.
    $resave = $write.binding[$action].resave
    if ($check.differs -and $check.differs.Count -and $resave) {
        $Run.lines.Add("NOTE ${name}: the read-back differed in $($check.differs -join ', ') after one save; saved once more, as declared: $resave")
        Invoke-RecipeWrite $write.binding $action $Context $Run
        $check = Read-RecipeWriteBack $readBack $Context $Run
    }
    if ($check.fault) { Add-RecipeCheck $Run $name 'FAIL' $check.fault; return }
    if ($check.row) { $result.values = Get-RecipeProduced $check.row $readBack.produces $readBack.operation $result.values }
    if ($check.differs.Count) { Add-RecipeCheck $Run $name 'FAIL' ('the read-back differs from the write in ' + ($check.differs -join ', ') + $(if ($resave) { ' after a second save' })); return }
    Add-RecipeCheck $Run $name 'PASS'
}
function Read-RecipeWriteBack {
    # The read-back of one write: @{fault; row; differs}. A fault is a read-back that found no single object.
    param($ReadBack, $Context, $Run)
    $rows = Read-RecipeRows $ReadBack $Context $Run
    if ($ReadBack.expectMap) { return @{fault = $null; row = $null; differs = (Get-RecipeMapDifferences $rows $ReadBack.expectMap $Context)} }
    $hits = Select-RecipeBindingMatches $rows $ReadBack $Context
    if ($hits.Count -ne 1) { return @{fault = "the read-back found $($hits.Count) matching object(s), not one"; row = $null; differs = @()} }
    $differs = if ($ReadBack.expect) { Get-RecipeDifferences $hits[0] (Expand-RecipeValue $ReadBack.expect $Context) $ReadBack.operation $ReadBack.unordered } else { @() }
    return @{fault = $null; row = $hits[0]; differs = $differs}
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
            if ($seen.Contains($key)) {
                # A step that resolves a shared object (a product several lines name) handles each key once.
                if ($Step.repeat -eq 'reuse') { continue }
                throw (New-RecipeFault 'the input names this natural key twice')
            }
            $seen[$key] = $true
            Invoke-RecipeStepItem $Step $context $Run $key ([ref]$printed)
        } catch [Collections.Generic.KeyNotFoundException] {
            if (-not $key) { $key = '(no key)' }
            # A value this item needs comes from an object a layer delivered under its own keys: the layer owns this one too.
            if ($_.Exception.Data['delivered']) { if (-not $printed) { Set-RecipeDelivered $Run $Step $key $_.Exception.Message }; continue }
            # A value this item needs comes from an object that does not exist yet.
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

<#
.SYNOPSIS
READ-ONLY. Evaluate the locked checks in order: ruling, then requirements, then the observation.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. A ruling is applied before the
function's requirements. A capability requirement that names a function, and a ground that
cites one (requiresFunction), hold only when every locked check of that function passed in
this run; a circular reference is ERROR. Rows come back in lock order. Definitions only.
.EXAMPLE
. ./Ledger.Run.ps1
Get-LedgerRows -Context $context
#>
#Requires -Version 7.0
function Get-LedgerFunctionState {
    # PASS when every locked check of the function passed in this run; otherwise the state that prevents it.
    param($Context,[string]$FunctionId)
    $ids=@($Context.build.lock.checkIds|Where-Object {$Context.checks[$_].functionId -eq $FunctionId})
    if($FunctionId -notin $Context.build.functions -or $ids.Count -eq 0){return 'ABSENT'}
    $states=@(foreach($id in $ids){(Get-LedgerRow $Context $id).result})
    foreach($state in @('CIRCULAR','ERROR','FAIL','UNSUPPORTED','DISABLED','UNVERIFIED','NOT-APPLICABLE')){if($state -in $states){return $state}}
    return 'PASS'
}
function Get-LedgerFunctionStateText {
    param([string]$FunctionId,[string]$State)
    if($State -eq 'ABSENT'){return "function '$FunctionId' has no locked check in this build"}
    return "function '$FunctionId' is $State in this run"
}
function Get-LedgerRow {
    param($Context,[string]$Id)
    if($Context.rows.ContainsKey($Id)){return $Context.rows[$Id]}
    if($Context.open.ContainsKey($Id)){return @{result='CIRCULAR'}}
    $Context.open[$Id]=$true
    try{$row=New-LedgerEvaluatedRow $Context $Id}finally{$Context.open.Remove($Id)}
    $Context.rows[$Id]=$row
    return $row
}
function New-LedgerEvaluatedRow {
    param($Context,[string]$Id)
    $check=$Context.checks[$Id];$f=$Context.functions[$check.functionId];$build=$Context.build;$row=New-LedgerRow $check
    if($Context.blocked){$row.result='UNSUPPORTED';$row.reason=$Context.blocked;return $row}
    # 1. A ruling comes first: a function the build rules out owes no requirement.
    $ruling=if($build.rulings -and $build.rulings.ContainsKey($f.id)){$build.rulings[$f.id]}else{$null}
    $fault=if($null -ne $ruling){Get-LedgerRulingFault $ruling $f}else{$null}
    if($fault){$row.result='ERROR';$row.reason='Invalid not-applicable ruling: '+$fault;return $row}
    if($null -ne $ruling -and $ruling.applies -eq $false){
        $ground=@($f.notApplicable|Where-Object {$_.id -eq $ruling.rule})[0]
        if($ground.requiresFunction){
            # The ground says another function carries the need, so that function must be built and passing.
            $state=Get-LedgerFunctionState $Context $ground.requiresFunction
            if($state -ne 'PASS'){
                $row.result=if($state -eq 'CIRCULAR'){'ERROR'}else{'UNVERIFIED'}
                $row.reason="Ruling ground '$($ruling.rule)' cites another function, and $(Get-LedgerFunctionStateText $ground.requiresFunction $state)."
                return $row
            }
        }
        if($ground.probe){
            $probe=Read-LedgerJson (Resolve-LedgerPath $Context.root $ground.probe) (Join-Path $Context.assets 'check.schema.json')
            $proof=Invoke-LedgerCheck $probe $build $Context.capabilities $Context.profile $Context.surfaces $Context.sqlServer $Context.database $Context.filesPath
            $row.result=if($proof.result -eq 'PASS'){'NOT-APPLICABLE'}else{$proof.result};$row.reason='Ruling probe: '+$proof.result
            $row.surface=$proof.surface;$row.binding=$proof.binding
        } else {
            $row.result='NOT-APPLICABLE'
            $row.reason=if($ground.requiresFunction){"Allowed ruling with evidence: $($ruling.rule); the cited function '$($ground.requiresFunction)' passed."}else{'Allowed ruling with evidence: '+$ruling.rule}
        }
        return $row
    }
    # 2. Requirements gate every check of the function.
    foreach($requirement in $f.requires){
        if($requirement.kind -eq 'capability' -and $Context.functions.ContainsKey([string]$requirement.id)){
            if($requirement.expected -isnot [bool]){$row.result='ERROR';$row.reason='Requirement expectation must be a boolean.';return $row}
            $state=Get-LedgerFunctionState $Context $requirement.id
            if(($state -eq 'PASS') -eq $requirement.expected){continue}
            $row.result=if($state -eq 'CIRCULAR'){'ERROR'}elseif($state -eq 'PASS'){'UNSUPPORTED'}else{'UNVERIFIED'}
            $row.reason=if($state -eq 'CIRCULAR'){"Circular capability requirement through function '$($requirement.id)'."}else{"Required capability: $(Get-LedgerFunctionStateText $requirement.id $state)."}
            return $row
        }
        $state=Get-LedgerRequirementState $requirement $Context.capabilities.facts
        if($state){$row.result=$state.result;$row.reason=$state.reason;return $row}
    }
    # 3. The observation.
    return Invoke-LedgerCheck $check $build $Context.capabilities $Context.profile $Context.surfaces $Context.sqlServer $Context.database $Context.filesPath
}
function Get-LedgerRows {
    # Context: build, functions, checks, capabilities, profile, surfaces, sqlServer, database, filesPath, root, assets, blocked.
    param($Context)
    $Context.rows=@{};$Context.open=@{}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($id in $Context.build.lock.checkIds){$rows.Add((Get-LedgerRow $Context $id))}
    foreach($id in $Context.build.functions){if(@($Context.build.lock.checkIds|Where-Object {$Context.checks[$_].functionId -eq $id}).Count -eq 0){
        $rows.Add(@{id=$id+'.coverage';functionId=$id;result='UNVERIFIED';surface=$null;binding=$null;level='supported';proves='Requested function has executable coverage.';reason='No locked check covers the requested function.'})
    }}
    return ,$rows
}

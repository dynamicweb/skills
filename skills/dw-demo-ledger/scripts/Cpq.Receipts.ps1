<#
.SYNOPSIS
READ-ONLY. Read CPQ behaviour receipts against the Distribution v1 contract.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/cpq-observations.md. The caller must first
load Cpq.Contracts.ps1 and Cpq.Receipts.ps1 from its reviewed, pinned Distribution checkout:
the row payload contract (contracts/cpq/observation.schema.json), Assert-CpqReceipt and
Get-CpqObservationVerdict live there. No path from a receipt is loaded or executed. Context
and digest come from the trusted run record, not receipt.before. This reader judges the rows;
whether a complete result may count as PASS is the binding status in the locked snapshot,
which every consumer applies with the Distribution's Resolve-CpqReaderVerdict.
.PARAMETER Trust
Independent Context, Behavior, Spec, Packages, ExpectedReceiptDigest, NotBefore, Now and
ContractRoot arguments for Distribution's Assert-CpqReceipt. No network or target writes.
.EXAMPLE
Read-CpqBehaviorObservation -CheckId cpq.bom.results -Receipt $receipt -Trust $trustedRun
#>
#Requires -Version 7.0
function Read-CpqBehaviorObservation {
    param([string]$CheckId,$Receipt,[hashtable]$Trust)
    foreach($name in @('Assert-CpqReceipt','Get-CpqObservationVerdict')){
        if(-not (Get-Command $name -ErrorAction SilentlyContinue)){throw [InvalidOperationException]::new('Load the reviewed Distribution receipt validator first.')}
    }
    if(-not $Trust -or $Trust.ContainsKey('Receipt')){throw 'Invalid independent receipt trust arguments.'}
    Assert-CpqReceipt -Receipt $Receipt @Trust
    $rows=@($Receipt.observations | Where-Object {$_.checkId -ceq $CheckId})
    if(-not $rows.Count){throw [InvalidOperationException]::new('No receipt observations for this check.')}
    $off=[Collections.Generic.List[object]]::new();$complete=$true;$producerError=$false
    foreach($row in $rows){
        if($row.result -ceq 'FAIL'){$off.Add(@{caseId=$row.caseId;reason='Producer recorded failure.'});continue}
        if($row.result -ceq 'ERROR'){$producerError=$true;$complete=$false;continue}
        # The producer never labels a row PASS: every other row is judged from its own step journal
        # against the independent case expectation, never from its label.
        $case=@($Trust.Spec.cases | Where-Object {$_.id -ceq $row.caseId})[0]
        if(-not $case){$complete=$false;continue}
        $verdict=Get-CpqObservationVerdict $row $case $Trust.Spec
        switch -CaseSensitive ($verdict){
            'PASS' {}
            'FAIL' {
                # The facts of the judged step: bom (SKU to quantity), sell, beforeDiscount, valid.
                $seen=$row.observed.steps[$row.observed.operation].observed
                $fields=@(foreach($key in @('valid','bom','sell','beforeDiscount')){
                    if($case.expect.Contains($key) -and $seen.Contains($key) -and
                        (ConvertTo-CpqObservationJson $seen[$key]) -cne (ConvertTo-CpqObservationJson $case.expect[$key])){$key}
                })
                $off.Add(@{caseId=$row.caseId;operation=$row.observed.operation;fields=$fields;reason='Observation differs from the independent case expectation.'})
            }
            'ERROR' {$producerError=$true;$complete=$false}
            default {$complete=$false}
        }
    }
    # Preserve a proven red result even when other portions remain unverified.
    $result=if($producerError){'ERROR'}elseif($off.Count){'FAIL'}elseif(-not $complete){'UNVERIFIED'}else{'PASS'}
    return @{result=$result;complete=$complete;scanned=$rows.Count;offenders=@($off.ToArray());value=@{cases=$rows.Count;invalid=$off.Count}}
}

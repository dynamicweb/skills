<#
.SYNOPSIS
READ-ONLY. Read CPQ behaviour receipts against the Distribution v1 contract.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/cpq-observations.md. The caller must first
load Cpq.Contracts.ps1 and Cpq.Receipts.ps1 from its reviewed, pinned Distribution checkout.
No path from a receipt is loaded or executed. Context and digest come from the trusted run
record, not receipt.before. All behavioural ledger bindings remain planned.
.PARAMETER Trust
Independent Context, Behavior, Spec, Packages, ExpectedReceiptDigest, NotBefore, Now and
ContractRoot arguments for Distribution's Assert-CpqReceipt. No network or target writes.
.EXAMPLE
Read-CpqBehaviorObservation -CheckId cpq.bom.results -Receipt $receipt -Trust $trustedRun
#>
#Requires -Version 7.0
function Read-CpqBehaviorObservation {
    param([string]$CheckId,$Receipt,[hashtable]$Trust)
    if(-not (Get-Command Assert-CpqReceipt -ErrorAction SilentlyContinue)){throw [InvalidOperationException]::new('Load the reviewed Distribution receipt validator first.')}
    if(-not $Trust -or $Trust.ContainsKey('Receipt')){throw 'Invalid independent receipt trust arguments.'}
    Assert-CpqReceipt -Receipt $Receipt @Trust
    $rows=@($Receipt.observations | Where-Object {$_.checkId -ceq $CheckId})
    if(-not $rows.Count){throw [InvalidOperationException]::new('No receipt observations for this check.')}
    $off=[Collections.Generic.List[object]]::new();$complete=$true;$producerError=$false
    foreach($row in $rows){
        if($row.result -eq 'FAIL'){$off.Add(@{caseId=$row.caseId;reason='Producer recorded failure.'});continue}
        if($row.result -eq 'ERROR'){$producerError=$true;$complete=$false;continue}
        if($row.result -ne 'PASS'){$complete=$false;continue}
        $case=@($Trust.Spec.cases | Where-Object {$_.id -ceq $row.caseId})[0]
        $actual=$row.observed
        # Only these two payloads have independent business assertions in spec v1.
        # Other envelopes are readable but cannot certify their domain intent yet.
        switch($CheckId){
            'cpq.bom.results' {
                if($actual.lines -isnot [array] -or -not $case.expect.Contains('bom')){$complete=$false;continue}
                $wanted=@(@(foreach($sku in $case.expect.bom.Keys){ConvertTo-CpqObservationJson @{sku=$sku;quantity=$case.expect.bom[$sku]}}) | Sort-Object -CaseSensitive)
                $got=@($actual.lines | ForEach-Object {ConvertTo-CpqObservationJson $_} | Sort-Object -CaseSensitive)
                if((ConvertTo-CpqObservationJson $wanted) -cne (ConvertTo-CpqObservationJson $got)){$off.Add(@{caseId=$row.caseId;reason='BOM multiset differs.'})}
                # Selection provenance, hidden-answer replay and totals still need a producer.
                $complete=$false
            }
            'cpq.pricing.results' {
                foreach($key in @('sell','beforeDiscount')){
                    if(-not $case.expect.Contains($key) -or -not $actual.Contains($key)){$complete=$false;continue}
                    if($actual[$key] -cne $case.expect[$key]){$off.Add(@{caseId=$row.caseId;field=$key;reason='Independent price expectation differs.'})}
                }
                # No cost/rounding/handoff assertions exist in the initial spec cases.
                $complete=$false
            }
            default {$complete=$false}
        }
    }
    # Preserve a proven red result even when other portions remain unverified.
    $result=if($producerError){'ERROR'}elseif($off.Count){'FAIL'}elseif(-not $complete){'UNVERIFIED'}else{'PASS'}
    return @{result=$result;complete=$complete;scanned=$rows.Count;offenders=@($off.ToArray());value=@{cases=$rows.Count;invalid=$off.Count}}
}

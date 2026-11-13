<#
.SYNOPSIS
READ-ONLY. CPQ behaviour receipt reader controls in the producer's row payload shape.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/cpq-observations.md. No host writes.
The first block replaces the Distribution trust boundary with stand-ins so the reader's own
dispatch runs in this repository's CI: Assert-CpqReceipt accepts, and the stand-in verdict
judges the step the row names against the case, as the Distribution's Get-CpqObservationVerdict
does for a recalculation. The second block runs only with CPQ_DISTRIBUTION_ROOT set to a reviewed
Distribution checkout and uses its real validator, verdict and fixture.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Receipts.Tests.ps1 -CI
#>
#Requires -Version 7.0
param()
Describe 'CPQ receipt reader in the producer payload shape' {
    BeforeAll {
        foreach($f in @('Cpq.Json.ps1','Cpq.Receipts.ps1')){. (Join-Path $PSScriptRoot "../$f")}
        function Assert-CpqReceipt {param($Receipt,$Context,$Behavior,$Spec,$Packages,$ExpectedReceiptDigest,$NotBefore,$Now,$ContractRoot)}
        function Get-CpqObservationVerdict($Row,$Case,$Spec){
            $op=$Row.observed.operation
            if(-not $Row.observed.steps.Contains($op)){return 'UNVERIFIED'}
            $step=$Row.observed.steps[$op]
            if($step.result -cne 'PASS'){return $step.result}
            foreach($key in @('valid','bom','sell','beforeDiscount')){
                if(-not $Case.expect.Contains($key)){continue}
                if(-not $step.observed.Contains($key)){return 'UNVERIFIED'}
                if((ConvertTo-CpqObservationJson $step.observed[$key]) -cne (ConvertTo-CpqObservationJson $Case.expect[$key])){return 'FAIL'}
            }
            return 'PASS'
        }
        $script:cases=@(
            @{id='small-fixed';expect=@{valid=$true;bom=@{'WB-S'=1};sell='100.00'}},
            @{id='large-discount';expect=@{valid=$true;bom=@{'WB-L'=1;'WB-DRAWER'=2};beforeDiscount='190.00';sell='171.00'}}
        )
        # The producer's row: observed={operation,steps,reason}; each step {result,read,observed}.
        # The producer never labels a row PASS, so the label here is UNVERIFIED.
        function New-ProducerRow($Case,[string]$CheckId='cpq.pricing.results'){
            $seen=@{hostId='fixture-host';caseId=$Case.id;modelVersionId=2;erpCalls=0;valid=$Case.expect.valid
                bom=(ConvertFrom-Json (ConvertTo-Json $Case.expect.bom) -AsHashtable);sell=$Case.expect.sell}
            if($Case.expect.Contains('beforeDiscount')){$seen.beforeDiscount=$Case.expect.beforeDiscount}
            $read=@{complete=$true;nextCursor=$null;expectedSubjects=1;observedSubjects=1}
            $render=@{result='PASS';read=$read;observed=@{hostId='fixture-host';caseId=$Case.id;modelVersionId=2;rendered=$true;dwErrors=0;theme='cpq-neutral'}}
            return @{checkId=$CheckId;caseId=$Case.id;result='UNVERIFIED'
                observed=@{operation='recalculate';steps=[ordered]@{render=$render;recalculate=@{result='PASS';read=$read;observed=$seen}};reason='Synthetic fixture journal.'}}
        }
        function New-Receipt([string]$CheckId='cpq.pricing.results'){@{observations=@(foreach($c in $script:cases){New-ProducerRow $c $CheckId})}}
        function Read-Row($Receipt,[string]$CheckId='cpq.pricing.results'){Read-CpqBehaviorObservation $CheckId $Receipt @{Spec=@{cases=$script:cases}}}
    }
    It 'proves a correct producer journal complete, whatever the row label says' {
        $read=Read-Row (New-Receipt)
        $read.result | Should -BeExactly PASS
        $read.complete | Should -BeTrue
        $read.scanned | Should -Be 2
    }
    It 'RED CONTROL: a wrong price in steps.recalculate.observed is a FAIL that names the field' {
        $r=New-Receipt;$r.observations[1].observed.steps.recalculate.observed.sell='99.00'
        $read=Read-Row $r
        $read.result | Should -BeExactly FAIL
        $read.offenders.Count | Should -Be 1
        $read.offenders[0].caseId | Should -BeExactly 'large-discount'
        $read.offenders[0].fields | Should -Be @('sell')
    }
    It 'RED CONTROL: a wrong discount basis and a wrong BOM quantity are FAILs' {
        $r=New-Receipt;$r.observations[1].observed.steps.recalculate.observed.beforeDiscount='200.00'
        (Read-Row $r).offenders[0].fields | Should -Be @('beforeDiscount')
        $r=New-Receipt 'cpq.bom.results';$r.observations[0].observed.steps.recalculate.observed.bom['WB-S']=2
        $read=Read-Row $r 'cpq.bom.results'
        $read.result | Should -BeExactly FAIL
        $read.offenders[0].fields | Should -Be @('bom')
    }
    It 'does not read the facts from the top of observed' {
        $r=New-Receipt;$r.observations[0].observed.sell='99.00';$r.observations[0].observed.lines=@(@{sku='X';quantity=9})
        (Read-Row $r).result | Should -BeExactly PASS
    }
    It 'keeps a producer FAIL and ERROR, and an unfinished journal is not proven' {
        $r=New-Receipt;$r.observations[0].result='FAIL'
        $read=Read-Row $r;$read.result | Should -BeExactly FAIL;$read.offenders[0].reason | Should -BeLike '*Producer recorded*'
        $r=New-Receipt;$r.observations[0].result='ERROR'
        $read=Read-Row $r;$read.result | Should -BeExactly ERROR;$read.complete | Should -BeFalse
        $r=New-Receipt;$r.observations[0].observed.steps.Remove('recalculate')
        $read=Read-Row $r;$read.result | Should -BeExactly UNVERIFIED;$read.complete | Should -BeFalse
        $r=New-Receipt;$r.observations[0].observed.steps.recalculate.result='ERROR'
        (Read-Row $r).result | Should -BeExactly ERROR
        $r=New-Receipt;$r.observations[0].caseId='not-declared'
        (Read-Row $r).complete | Should -BeFalse
    }
    It 'refuses to run without the Distribution verdict loaded' {
        $scripts=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $probe=". '$scripts/Cpq.Json.ps1'; . '$scripts/Cpq.Receipts.ps1'; function Assert-CpqReceipt {}; try { Read-CpqBehaviorObservation x @{observations=@()} @{Spec=@{}} } catch { `$_.Exception.Message }"
        pwsh -NoProfile -NonInteractive -Command $probe | Should -BeLike '*Distribution receipt validator*'
    }
}
$hasDistribution=$env:CPQ_DISTRIBUTION_ROOT -and (Test-Path (Join-Path $env:CPQ_DISTRIBUTION_ROOT 'contracts/cpq/observation.schema.json'))
Describe 'CPQ receipt reader against the Distribution receipt contract' -Skip:(-not $hasDistribution) {
    BeforeAll {
        # Files of the reviewed Distribution checkout the caller names; this repository ships none of them.
        $root=$env:CPQ_DISTRIBUTION_ROOT
        $distribution=@(foreach($name in @('Cpq.Contracts.ps1','Cpq.Receipts.ps1','tests/fixtures/Cpq.Fixture.ps1')){Join-Path (Join-Path $root 'tools/ci') $name})
        $script:contractRoot=(Resolve-Path (Join-Path $root 'contracts/cpq')).Path
        foreach($file in $distribution){. $file}
        foreach($f in @('Cpq.Json.ps1','Cpq.Receipts.ps1')){. (Join-Path $PSScriptRoot "../$f")}
        function Get-Trust($f){@{Context=$f.context;Behavior=$f.behavior;Spec=$f.spec;Packages=$f.packages;ExpectedReceiptDigest=(Get-CpqDigest $f.receipt);NotBefore=[datetimeoffset]'2026-01-01T12:00:00Z';Now=[datetimeoffset]'2026-01-01T12:02:00Z';ContractRoot=$script:contractRoot}}
    }
    It 'proves the producer journal complete, and the binding status decides PASS' {
        $f=New-TestFixture;foreach($row in $f.receipt.observations){$row.result='UNVERIFIED'}
        $read=Read-CpqBehaviorObservation cpq.pricing.results $f.receipt (Get-Trust $f)
        $read.result | Should -BeExactly PASS;$read.complete | Should -BeTrue
        $planned=@{checks=@{'cpq.pricing.results'=@{bindings=@(@{handler='cpq-behavior-receipt';surface='file';status='planned'})}}}
        (Resolve-CpqReaderVerdict cpq.pricing.results $read $planned).result | Should -BeExactly UNVERIFIED
        $planned.checks['cpq.pricing.results'].bindings[0].status='implemented'
        (Resolve-CpqReaderVerdict cpq.pricing.results $read $planned).result | Should -BeExactly PASS
    }
    It 'RED CONTROL: a wrong price the producer recorded as FAIL stays FAIL, and under PASS it is refused' {
        $f=New-TestFixture;$row=$f.receipt.observations[0]
        $row.observed.steps=@{render=$row.observed.steps.render;recalculate=$row.observed.steps.recalculate}
        $row.observed.steps.recalculate.observed.sell='99.00';$row.observed.steps.recalculate.result='FAIL';$row.result='FAIL'
        (Read-CpqBehaviorObservation cpq.pricing.results $f.receipt (Get-Trust $f)).result | Should -BeExactly FAIL
        $f=New-TestFixture;$f.receipt.observations[0].observed.steps.recalculate.observed.sell='99.00'
        {Read-CpqBehaviorObservation cpq.pricing.results $f.receipt (Get-Trust $f)} | Should -Throw '*contradicts its own observation*'
    }
}

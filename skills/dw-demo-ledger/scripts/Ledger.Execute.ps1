<#
.SYNOPSIS
READ-ONLY. Execute a selected check through fixed observation handlers.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. No dynamic code evaluation. Missing implementations are errors; insufficient observations remain unverified. Legacy PIM SQL assertions preserve their original scope.
.EXAMPLE
. ./Ledger.Execute.ps1
#>
#Requires -Version 7.0
function Invoke-LedgerCheck {
    param($Check,$Build,$Capabilities,$Profile,[string[]]$Surfaces,[string]$SqlServer,[string]$Database,[string]$FilesPath,[string[]]$Refused=@())
    $row=New-LedgerRow $Check
    $assertion=@{};foreach($k in $Check.assertion.Keys){$assertion[$k]=$Check.assertion[$k]}
    if($Profile.expectations.ContainsKey($Check.id)){foreach($k in $Profile.expectations[$Check.id].Keys){
        # A profile states expectations. It never changes what a check observes or how the observation is judged.
        if($k -cnotin @('op','value','minimumSubjects')){$row.result='ERROR';$row.reason='Profile may change only op, value and minimumSubjects of a check.';return $row}
        $assertion[$k]=$Profile.expectations[$Check.id][$k]
    }}
    $binding=Select-LedgerBinding -Check $Check -Capabilities $Capabilities -Surfaces $Surfaces -Exclude $Refused
    if(-not $binding){
        if($Refused.Count){$row.reason='Binding is not authorised for the required scope and no other equivalent binding is available: '+($Refused -join ', ')}
        return $row
    }
    $row.surface=$binding.surface;$row.binding=$binding.id
    $row.expected=$assertion
    try {
        $registry=Read-LedgerJson (Join-Path $PSScriptRoot '../assets/handlers.json')
        $entry=$registry.handlers[$binding.handler]
        if(-not $entry -or $binding.surface -notin $entry.surfaces){throw 'Handler/surface is not allowlisted.'}
        # A scalar handler reports no offenders, so judging it as offenders would always pass.
        if($assertion.kind -cnotin $entry.assertions){throw 'Assertion kind does not fit the handler.'}
        if($binding.surface -eq 'mcp') {
            $observation=Get-LedgerMcpObservation -Binding $binding -Check $Check -Build $Build
        } elseif($binding.surface -eq 'file') {
            $observation=Get-LedgerFileObservation -Binding $binding -FilesPath $FilesPath -Build $Build
        } elseif($binding.surface -eq 'admin-api') {
            $observation=Get-LedgerAdminObservation -Binding $binding -Build $Build -Capabilities $Capabilities
        } elseif($binding.surface -eq 'dwapi') {
            $observation=Get-LedgerDwapiObservation -Binding $binding -Build $Build
        } elseif($binding.surface -eq 'sql') {
            if(-not $Database){throw 'Local SQL requires Database.'}
            switch($binding.handler) {
                'cpq-structured-read' {$observation=Get-CpqLedgerObservation -Check $Check -Build $Build -Server $SqlServer -Database $Database}
                'pim-matrix' {$observation=Get-PimMatrixObservation -Aspect $binding.arguments.aspect -Build $Build -Server $SqlServer -Database $Database}
                'pim-edit-layout' {$observation=Get-PimEditLayoutObservation -Arguments $binding.arguments -Build $Build -Server $SqlServer -Database $Database}
                'pim-field-placement' {$observation=Get-PimFieldPlacementObservation -Arguments $binding.arguments -Build $Build -Server $SqlServer -Database $Database}
                'sql-scalar' {$n=Invoke-Sqlcmd-Scalar -Server $SqlServer -Database $Database -Query (Expand-PimSql $binding.query $Build $SqlServer $Database);$observation=@{value=$n;complete=$true;scanned=$null;offenders=@()}}
                'sql-offenders' {
                    $off=@(Invoke-Sqlcmd-Rows -Server $SqlServer -Database $Database -Query (Expand-PimSql $binding.query $Build $SqlServer $Database))
                    # The subjects in scope are counted by a separate single SELECT; without one the subject count is unknown.
                    $subjects=if($binding.subjectsQuery){Invoke-Sqlcmd-Scalar -Server $SqlServer -Database $Database -Query (Expand-PimSql $binding.subjectsQuery $Build $SqlServer $Database)}else{$null}
                    $observation=@{value=$off.Count;complete=$true;scanned=$subjects;offenders=$off}
                }
                {$_ -in @('pim-attributes','pim-families','pim-widget-queries')} {
                    $legacy=@{id=$Check.id;kind=$assertion.kind;proves=$Check.intent.proves;aspect=$assertion.aspect;minScanned=$assertion.minimumSubjects;minFamilies=$assertion.minimumSubjects}
                    $stored=@{};if($binding.handler -eq 'pim-attributes') {
                        if(-not $script:LedgerStoredFields){$script:LedgerStoredFields=Get-PimStoredField -Server $SqlServer -Database $Database}
                        $stored=$script:LedgerStoredFields
                    }
                    $r=Invoke-PimFeatureCheck -Check $legacy -Build $Build -Server $SqlServer -Database $Database -FilesPath $FilesPath -Stored $stored
                    $row.result=$r.result;$row.measured=$r.measured;$row.expected=$r.expected;$row.offenders=@($r.offenders);$row.reason='Local domain assertion evaluated.'
                    return $row
                }
                default {throw 'No registered SQL observation handler.'}
            }
        } else {throw 'No registered observation handler for this binding.'}
        $row.result=Test-LedgerAssertion -Assertion $assertion -Observation $observation
        $row.measured=if($observation -is [Collections.IDictionary] -and $observation.Contains('measured')){$observation.measured}else{$observation.value};$row.scanned=$observation.scanned;$row.offenders=@($observation.offenders|Select-Object -First 25)
        $row.reason=if($observation.complete){'Equivalent observation evaluated.'}else{'Observation omits required fields or completeness evidence.'}
        # Subjects read but outside the build's declared scope are reported, never judged and never dropped.
        if($observation -is [Collections.IDictionary] -and $observation.Contains('outOfScope')){
            $row.outOfScope=@($observation.outOfScope|Select-Object -First 25)
            if($observation.scopeNote){$row.reason+=' '+$observation.scopeNote}
        }
        if($assertion.kind -eq 'offenders' -and $assertion.ContainsKey('minimumSubjects')){
            $row.reason+=if($null -eq $observation.scanned){' The assertion needs a subject count and the binding reports none.'}elseif($observation.scanned -lt $assertion.minimumSubjects){" $($observation.scanned) subject(s) in scope, below the minimum of $($assertion.minimumSubjects)."}else{''}
        }
        if($Refused.Count){$row.reason+=' Refused before observation: '+($Refused -join ', ')+'.'}
    } catch {
        Write-Verbose $_.ScriptStackTrace
        if($_.Exception -is [UnauthorizedAccessException]){
            # A refusal returns no observation: the binding was unavailable, so the next equivalent binding may run.
            # A completed observation, valid or failing, never reaches this branch and is never retried.
            return Invoke-LedgerCheck $Check $Build $Capabilities $Profile $Surfaces $SqlServer $Database $FilesPath (@($Refused)+$binding.id)
        }
        elseif($_.Exception -is [InvalidOperationException]){
            $row.result='UNVERIFIED'
            # A build input the target refutes, or a runner input that is missing, is named; any other message stays
            # generic so no response body is printed. Neither kind of message ever carries an input's value.
            $row.reason=if($_.Exception.Message -like 'Build input: *' -or $_.Exception.Message -like 'Runner input: *'){$_.Exception.Message}else{'Required input, field, path or complete enumeration is unavailable.'}
        }
        else {$row.result='ERROR';$row.reason='Binding execution failed. Check handler, grants, scope and target schema; no exception body is persisted.'}
    }
    return $row
}

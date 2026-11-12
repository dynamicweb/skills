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
    $binding=Select-LedgerBinding -Check $Check -Capabilities $Capabilities -Surfaces $Surfaces -Exclude $Refused
    if(-not $binding){
        if($Refused.Count){$row.reason='Binding is not authorised for the required scope and no other equivalent binding is available: '+($Refused -join ', ')}
        return $row
    }
    $row.surface=$binding.surface;$row.binding=$binding.id
    $assertion=@{};foreach($k in $Check.assertion.Keys){$assertion[$k]=$Check.assertion[$k]}
    if($Profile.expectations.ContainsKey($Check.id)){foreach($k in $Profile.expectations[$Check.id].Keys){$assertion[$k]=$Profile.expectations[$Check.id][$k]}}
    $row.expected=$assertion
    try {
        $registry=Read-LedgerJson (Join-Path $PSScriptRoot '../assets/handlers.json')
        if(-not $registry.ContainsKey($binding.handler) -or $binding.surface -notin $registry[$binding.handler]){throw 'Handler/surface is not allowlisted.'}
        if($binding.surface -eq 'mcp') {
            $observation=Get-LedgerMcpObservation -Binding $binding -Check $Check -Build $Build
        } elseif($binding.surface -eq 'file') {
            $observation=Get-LedgerFileObservation -Binding $binding -FilesPath $FilesPath
        } elseif($binding.surface -eq 'admin-api') {
            $observation=Get-LedgerAdminObservation -Binding $binding -Build $Build -Capabilities $Capabilities
        } elseif($binding.surface -eq 'sql') {
            if(-not $Database){throw 'Local SQL requires Database.'}
            switch($binding.handler) {
                'cpq-structured-read' {$observation=Get-CpqLedgerObservation -Check $Check -Build $Build -Server $SqlServer -Database $Database}
                'pim-matrix' {$observation=Get-PimMatrixObservation -Aspect $binding.arguments.aspect -Build $Build -Server $SqlServer -Database $Database}
                'sql-scalar' {$n=Invoke-Sqlcmd-Scalar -Server $SqlServer -Database $Database -Query (Expand-PimSql $binding.query $Build);$observation=@{value=$n;complete=$true;scanned=$null;offenders=@()}}
                'sql-offenders' {$off=@(Invoke-Sqlcmd-Rows -Server $SqlServer -Database $Database -Query (Expand-PimSql $binding.query $Build));$observation=@{value=$off.Count;complete=$true;scanned=$null;offenders=$off}}
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
        $row.measured=$observation.value;$row.scanned=$observation.scanned;$row.offenders=@($observation.offenders|Select-Object -First 25)
        $row.reason=if($observation.complete){'Equivalent observation evaluated.'}else{'Observation omits required fields or completeness evidence.'}
        if($Refused.Count){$row.reason+=' Refused before observation: '+($Refused -join ', ')+'.'}
    } catch {
        Write-Verbose $_.ScriptStackTrace
        if($_.Exception -is [UnauthorizedAccessException]){
            # A refusal returns no observation: the binding was unavailable, so the next equivalent binding may run.
            # A completed observation, valid or failing, never reaches this branch and is never retried.
            return Invoke-LedgerCheck $Check $Build $Capabilities $Profile $Surfaces $SqlServer $Database $FilesPath (@($Refused)+$binding.id)
        }
        elseif($_.Exception -is [InvalidOperationException]){$row.result='UNVERIFIED';$row.reason='Required input, field, path or complete enumeration is unavailable.'}
        else {$row.result='ERROR';$row.reason='Binding execution failed. Check handler, grants, scope and target schema; no exception body is persisted.'}
    }
    return $row
}

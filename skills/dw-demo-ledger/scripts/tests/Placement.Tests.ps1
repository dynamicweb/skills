<#
.SYNOPSIS
READ-ONLY. Green and red controls for the global field placement rule.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/edit-layout.md. The share rule is a pure
function over an in-memory fill; the SQL reads are exercised through mocks only. Red controls: a
global field filled on fewer than half the products, an unreadable column, an empty scope and a build
with no default language.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Placement.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach ($file in @('Ledger.Core.ps1', 'Ledger.Observations.ps1', 'Ledger.Sql.ps1', 'Pim.Fields.ps1', 'Pim.Layout.ps1', 'Ledger.Transport.ps1', 'Ledger.Execute.ps1')) { . (Join-Path $PSScriptRoot "../$file") }
    function New-Build2 {
        @{ schema = 1; defaultLanguage = 'ENU'; pimShop = 'SHOP1'
           families = @(@{ name = 'Presses'; category = 'Press' }, @{ name = 'Films'; category = 'Film' })
           attributes = @(); rulings = @{}; productScope = @{ exclude = @() } }
    }
    $script:build2 = New-Build2
    function New-Fill { param([int]$Total, $Fields) [pscustomobject]@{ total = $Total; fields = @($Fields) } }
    function Fld { param([string]$Name, [string]$Kind, [int]$Filled = -1) [pscustomobject]@{ name = $Name; kind = $Kind; filled = $Filled } }
}

Describe 'Test-PimFieldPlacement' {
    It 'passes a field at the threshold and refuses one below it, with the measured share' {
        (Test-PimFieldPlacement -Fill (New-Fill 200 @((Fld erpGroup text 100))) -MinSharePct 50).offenders | Should -BeNullOrEmpty
        $r = Test-PimFieldPlacement -Fill (New-Fill 200 @((Fld erpGroup text 100), (Fld platenWidth number 99))) -MinSharePct 50
        $r.offenders.Count | Should -Be 1
        $r.offenders[0] | Should -Match "global field 'platenWidth' is filled on 99 of 200 products \(49%\)"
    }
    It 'does not judge a checkbox or a computed field, and says how many it left out' {
        $r = Test-PimFieldPlacement -Fill (New-Fill 100 @((Fld isHazardous flag), (Fld packedDimensions computed))) -MinSharePct 50
        $r.offenders | Should -BeNullOrEmpty
        $r.measured | Should -Match '0 custom global field\(s\) measured on 100 product\(s\), 0 offender\(s\); 2 checkbox or computed'
    }
    It 'refuses a field whose column could not be read, and a scope with no product' {
        (Test-PimFieldPlacement -Fill (New-Fill 100 @((Fld 'odd name' unreadable))) -MinSharePct 50).offenders -join ';' | Should -Match 'no readable column'
        (Test-PimFieldPlacement -Fill (New-Fill 0 @((Fld a text 0))) -MinSharePct 50).offenders -join ';' | Should -Match 'nothing was measured'
    }
    It 'passes a catalogue with no custom global field' {
        (Test-PimFieldPlacement -Fill (New-Fill 100 @()) -MinSharePct 50).offenders | Should -BeNullOrEmpty
    }
    It 'Get-PimGlobalFieldFill: reads text, number and date columns in scope, and leaves a bit, a computed and an unsafe name uncounted' {
        Mock Invoke-Sqlcmd-Rows { @('erpGroup|0|nvarchar|', 'platenWidth|0|float|', 'firstSold|0|datetime|', 'isHazardous|0|bit|', 'packed|1|nvarchar|', 'bad name]|0|nvarchar|', 'noColumn|0||') }
        Mock Invoke-Sqlcmd-Scalar { if ($Query -match 'AND ISNULL\(p\.\[platenWidth\], 0\) <> 0') { 4 } elseif ($Query -match 'p\.\[') { 60 } else { 100 } }
        $b = New-Build2; $b.productScope = @{ exclude = @(@{ idLike = 'FP-CART%'; reason = 'cart products' }) }
        $fill = Get-PimGlobalFieldFill -Server s -Database d -Build $b
        $fill.total | Should -Be 100
        @($fill.fields | ForEach-Object { "$($_.name)=$($_.kind):$($_.filled)" }) -join ' ' |
            Should -Be 'erpGroup=text:60 platenWidth=number:4 firstSold=date:60 isHazardous=flag:-1 packed=computed:-1 bad name]=unreadable:-1 noColumn=unreadable:-1'
        Should -Invoke Invoke-Sqlcmd-Scalar -ParameterFilter { $Query -match "NOT LIKE N'FP-CART%'" -and $Query -match "ProductLanguageId = N'ENU'" } -Times 4 -Exactly
        Should -Invoke Invoke-Sqlcmd-Scalar -ParameterFilter { $Query -match 'bad name' } -Times 0 -Exactly
    }
    It 'Get-PimGlobalFieldFill: refuses a build with no default language instead of counting every language' {
        $b = New-Build2; $b.Remove('defaultLanguage')
        { Get-PimGlobalFieldFill -Server s -Database d -Build $b } | Should -Throw -ExceptionType ([InvalidOperationException])
    }
    It 'through the runner: a FAIL row listing the fields below the share, a PASS row above it, UNVERIFIED with no default language' {
        $cap = @{ sql = @{ available = $true } }
        $c = @{ schema = 1; id = 'pim.field-placement.global-fields-filled'; functionId = 'pim.field-placement'
                intent = @{ proves = 'p'; level = 'applied'; scope = 's' }; assertion = @{ kind = 'offenders' }
                bindings = @(@{ id = 'local-sql'; surface = 'sql'; status = 'implemented'; handler = 'pim-field-placement'; localOnly = $true; arguments = @{ minSharePct = 50 } }) }
        $script:LedgerPimLayout = @{}
        Mock Get-PimGlobalFieldFill { New-Fill 100 @((Fld platenWidth number 3)) }
        $row = Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'fill-a' ''
        $row.result | Should -Be FAIL
        $row.offenders[0] | Should -Match 'platenWidth'
        Mock Get-PimGlobalFieldFill { New-Fill 100 @((Fld erpGroup text 90)) }
        (Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'fill-b' '').result | Should -Be PASS
        Mock Get-PimGlobalFieldFill { throw [InvalidOperationException]::new('Field placement needs the build defaultLanguage.') }
        (Invoke-LedgerCheck $c $script:build2 $cap @{ expectations = @{} } @('sql') '.' 'fill-c' '').result | Should -Be UNVERIFIED
    }
}

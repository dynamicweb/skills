<#
.SYNOPSIS
READ-ONLY. Test observation handlers against isolated files and mocked API reads.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. No network or target writes.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Observations.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    . (Join-Path $PSScriptRoot '../Ledger.Core.ps1')
    . (Join-Path $PSScriptRoot '../Ledger.Observations.ps1')
    function Invoke-DwApi {param($Command,$Method,$TimeoutSec,$RetryCount);throw 'Unexpected API call.'}
}
Describe 'Collection scope and typed arguments' {
    It 'filters exact booleans without coercing strings and requires every field' {
        $rows=@(@{active=$true},@{active=$false},@{active='true'})
        (Measure-LedgerRows $rows @{filter=@{field='active';op='equals';value=$true}}).value | Should -Be 1
        {Measure-LedgerRows @(@{active=$true},@{}) @{filter=@{field='active';op='equals';value=$true}}} | Should -Throw
    }
    It 'contains is literal text, not wildcard or regex evaluation' {
        (Measure-LedgerRows @(@{provider='a*b'},@{provider='axb'}) @{filter=@{field='provider';op='contains';value='*'}}).value | Should -Be 1
    }
    It 'rejects incomplete pages, absent arrays and unknown fields' {
        {ConvertTo-LedgerRows @{data=@(1);totalCount=2}} | Should -Throw
        {ConvertTo-LedgerRows @{data=@(1);nextCursor='next'}} | Should -Throw
        {ConvertTo-LedgerRows @{data=@{id=1}}} | Should -Throw
        {ConvertTo-LedgerRows @{other=@()}} | Should -Throw
        (ConvertTo-LedgerRows @{data=@();count=0}).Count | Should -Be 0
    }
    It 'substitutes nested arguments while preserving area ID type and escaping as data' {
        $args=Expand-LedgerArguments @{areaId='{areaId}';items=@('{lang}','prefix-{pimShop}')} @{areaId=7;defaultLanguage='ENU';pimShop='SHOP1'}
        $args.areaId | Should -BeOfType int
        $args.items[1] | Should -Be 'prefix-SHOP1'
        {Expand-LedgerArguments @{areaId='{areaId}'} @{}} | Should -Throw
        {Expand-LedgerArguments @{x='{unknown}'} @{}} | Should -Throw
    }
}
Describe 'Local Files scope and XML' {
    BeforeEach {
        $script:files=Join-Path $TestDrive 'Files'
        $null=New-Item -ItemType Directory -Path "$files/System/Repositories/catalog" -Force
        '<index><builder type="Content"/><builder type="Product"/></index>'|Set-Content "$files/System/Repositories/catalog/products.index"
    }
    It 'counts a relative path glob and its virtual Files form identically' {
        (Get-LedgerFileObservation @{handler='files-count';path='System/Repositories/*/*.index'} $files).value | Should -Be 1
        (Get-LedgerFileObservation @{handler='files-count';path='/Files/System/Repositories/*/*.index'} $files).value | Should -Be 1
        {Get-LedgerFileObservation @{handler='files-count';path='../*.config'} $files} | Should -Throw
    }
    It 'uses immediate children for includeSubfolders and does not double-prefix Files' {
        $null=New-Item -ItemType Directory -Path "$files/Files/Integration/jobs/group/deep" -Force
        foreach($path in @('a.xml','group/b.xml','group/deep/c.xml')){'<job/>'|Set-Content "$files/Files/Integration/jobs/$path"}
        $binding=@{handler='files-count';arguments=@{folder='Files/Integration/jobs';filter='*.xml';includeSubfolders=$true}}
        (Get-LedgerFileObservation $binding $files).value | Should -Be 2
    }
    It 'counts XML selectors, returns zero for absent nodes and rejects external entities' {
        $binding=@{handler='xml-count';path='System/Repositories/*/*.index';arguments=@{xpath='/index/builder[@type="Content"]'}}
        (Get-LedgerFileObservation $binding $files).value | Should -Be 1
        $binding.arguments.xpath='/index/builder[@type="Unknown"]'
        (Get-LedgerFileObservation $binding $files).value | Should -Be 0
        '<!DOCTYPE index [<!ENTITY ex SYSTEM "file:///not-read">]><index>&ex;</index>'|Set-Content "$files/System/Repositories/catalog/products.index"
        {Get-LedgerFileObservation $binding $files} | Should -Throw
    }
    It 'never treats missing or duplicate settings as a passing false setting' {
        $binding=@{handler='settings-value';path='GlobalSettings.config';arguments=@{key='/Globalsettings/Settings/Auditing/EnableAuditing';equals=$true}}
        '<Globalsettings><Settings><Auditing><EnableAuditing>True</EnableAuditing></Auditing></Settings></Globalsettings>'|Set-Content "$files/GlobalSettings.config"
        (Get-LedgerFileObservation $binding $files).value | Should -Be 1
        $binding.arguments.equals=$false
        (Get-LedgerFileObservation $binding $files).value | Should -Be 0
        '<Globalsettings/>'|Set-Content "$files/GlobalSettings.config"
        {Get-LedgerFileObservation $binding $files} | Should -Throw
        '<Globalsettings><Settings><Auditing><EnableAuditing>False</EnableAuditing><EnableAuditing>False</EnableAuditing></Auditing></Settings></Globalsettings>'|Set-Content "$files/GlobalSettings.config"
        {Get-LedgerFileObservation $binding $files} | Should -Throw
    }
}
Describe 'Authenticated named Admin queries' {
    It 'requires identity and a discovered query, even when a descriptor exists' {
        $b=@{operation='TestAll';projection=@{rowsPath='$'};arguments=@{}}
        {Get-LedgerAdminObservation $b @{} @{adminApi=@{available=$true;authenticated=$false;queries=@('TestAll')}}} | Should -Throw
        {Get-LedgerAdminObservation $b @{} @{adminApi=@{authenticated=$true;queries=@()}}} | Should -Throw
        Should -Invoke Invoke-DwApi -Times 0 -Exactly
    }
    BeforeEach {Mock Invoke-DwApi { @(@{id=1},@{id=2}) }}
    It 'uses GET and an explicit projection and refuses incomplete responses' {
        $b=@{operation='TestAll';projection=@{rowsPath='$'};arguments=@{}}
        $cap=@{adminApi=@{authenticated=$true;queries=@('TestAll')}}
        (Get-LedgerAdminObservation $b @{} $cap).value | Should -Be 2
        Should -Invoke Invoke-DwApi -Times 1 -ParameterFilter {$Method -eq 'Get'}
        Mock Invoke-DwApi {@{data=@(@{id=1});totalCount=2}}
        $b.projection.rowsPath='data'
        {Get-LedgerAdminObservation $b @{} $cap} | Should -Throw
    }
}

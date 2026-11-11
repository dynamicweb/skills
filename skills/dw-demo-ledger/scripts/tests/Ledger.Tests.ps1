<#
.SYNOPSIS
READ-ONLY. Ledger tests using isolated fixtures and mocked reads.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. No target mutations or credentials.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Ledger.Tests.ps1
#>
#Requires -Version 7.0
BeforeAll {
    $script:root=Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot '../Ledger.Core.ps1')
    . (Join-Path $PSScriptRoot '../Ledger.Observations.ps1')
    . (Join-Path $PSScriptRoot '../Ledger.Sql.ps1')
    . (Join-Path $PSScriptRoot '../Pim.Fields.ps1')
    . (Join-Path $PSScriptRoot '../Pim.Queries.ps1')
    . (Join-Path $PSScriptRoot '../Ledger.Transport.ps1')
    . (Join-Path $PSScriptRoot '../Ledger.Execute.ps1')
}
Describe 'Assertions preserve red controls' {
    It 'evaluates scalar <op> with a passing and failing observation' -TestCases @(
        @{op='ge';good=3;bad=1},@{op='le';good=1;bad=3},@{op='eq';good=2;bad=3}
    ) {
        param($op,$good,$bad)
        $a=@{kind='scalar';op=$op;value=2}
        Test-LedgerAssertion $a @{value=$good;complete=$true} | Should -Be PASS
        Test-LedgerAssertion $a @{value=$bad;complete=$true} | Should -Be FAIL
    }
    It 'does not coerce a missing number or incomplete observation to zero' {
        Test-LedgerAssertion @{kind='scalar';op='eq';value=0} @{complete=$true} | Should -Be ERROR
        Test-LedgerAssertion @{kind='scalar';op='eq';value=0} @{value=0;complete=$false} | Should -Be UNVERIFIED
    }
    It 'evaluates offenders without silently accepting missing data' {
        Test-LedgerAssertion @{kind='offenders'} @{offenders=@();complete=$true} | Should -Be PASS
        Test-LedgerAssertion @{kind='offenders'} @{offenders=@('broken');complete=$true} | Should -Be FAIL
        Test-LedgerAssertion @{kind='offenders'} @{complete=$true} | Should -Be ERROR
    }
    It 'requires subjects and no offenders for <kind>' -TestCases @(@{kind='attributes'},@{kind='families'},@{kind='widget-queries'}) {
        param($kind)
        $a=@{kind=$kind;minimumSubjects=1}
        Test-LedgerAssertion $a @{scanned=1;offenders=@();complete=$true} | Should -Be PASS
        Test-LedgerAssertion $a @{scanned=0;offenders=@();complete=$true} | Should -Be FAIL
        Test-LedgerAssertion $a @{scanned=1;offenders=@('broken');complete=$true} | Should -Be FAIL
    }
    It 'detects wrong attribute typing and missing declared fields' {
        $a=@(@{category='c';field='f';kind='decimal'})
        $s=@{'c|f'=@{type=7}}
        @( (Test-PimAttributeAspect -Aspect typing -Attribute $a -Stored $s).offenders).Count | Should -Be 0
        $s['c|f'].type=1
        @( (Test-PimAttributeAspect -Aspect typing -Attribute $a -Stored $s).offenders).Count | Should -Be 1
        @( (Test-PimAttributeAspect -Aspect typing -Attribute $a -Stored @{}).offenders).Count | Should -Be 1
    }
}
Describe 'Binding selection and failures' {
    BeforeEach {
        $script:cap=@{mcp=@{available=$true;tools=@('get_shops')};adminApi=@{authenticated=$false;queries=@()};dwapi=@{available=$false};file=@{available=$false};sql=@{available=$true}}
        $script:check=@{id='pim.test.count';functionId='pim.test';intent=@{proves='Count';level='configured'};assertion=@{kind='scalar';op='ge';value=1};bindings=@(@{id='m';surface='mcp';status='implemented';handler='missing-handler';operation='get_shops'},@{id='s';surface='sql';status='implemented';localOnly=$true;handler='sql-scalar';query='SELECT 1'})}
    }
    It 'prefers a discovered MCP tool, then local SQL when absent' {
        (Select-LedgerBinding $check $cap).id | Should -Be m
        $cap.mcp.tools=@()
        (Select-LedgerBinding $check $cap).id | Should -Be s
    }
    It 'keeps a planned binding unverified and never runs it' {
        $check.bindings[0].status='planned';$cap.sql.available=$false
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','sql') '' '' ''
        $r.result | Should -Be UNVERIFIED
    }
    It 'does not pass a missing handler or fall through to a passing SQL result' {
        Mock Read-LedgerMcp { @{data=@();count=0} }
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','sql') '' '' ''
        $r.result | Should -Be ERROR
        $r.surface | Should -Be mcp
    }
    It 'retains a valid FAIL rather than trying SQL' {
        $check.bindings[0].handler='mcp-count'
        Mock Read-LedgerMcp { @{data=@();count=0} }
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','sql') '' '' ''
        $r.result | Should -Be FAIL
        $r.surface | Should -Be mcp
    }
    It 'does not pass empty aggregate or a missing proof' {
        Get-LedgerVerdict @() | Should -Be UNVERIFIED
        Get-LedgerVerdict @(@{result='PASS'},@{result='UNVERIFIED'}) | Should -Be UNVERIFIED
    }
}
Describe 'Read safety and lock integrity' {
    It 'rejects a remote SQL server' { {Assert-LedgerLocalServer 'remote-host'} | Should -Throw }
    It 'rejects a write hidden after SELECT or SELECT INTO' {
        {Assert-LedgerSelect 'SELECT 1; DELETE FROM Test'} | Should -Throw
        {Assert-LedgerSelect 'SELECT * INTO other FROM Test'} | Should -Throw
        {Assert-LedgerSelect 'SELECT COUNT(*) FROM Test'} | Should -Not -Throw
        {Assert-LedgerSelect "SELECT N'/*', N'update', N'a'';b'"} | Should -Not -Throw
        {Assert-LedgerSelect "SELECT N'data'; DELETE FROM Test"} | Should -Throw
        {Assert-LedgerSelect "SELECT 1 /* comment */"} | Should -Throw
    }
    It 'rejects token injection and path traversal' {
        {Expand-PimSql "SELECT N'{lang}'" @{defaultLanguage="x';--"}} | Should -Throw
        {Resolve-LedgerPath $TestDrive '../escape.json'} | Should -Throw
    }
    It 'changes snapshot identity for changed files and added probes' {
        Set-Content (Join-Path $TestDrive 'manifest.json') '{}'
        $a=Get-LedgerDigest $TestDrive
        Set-Content (Join-Path $TestDrive 'probe.json') '{}'
        $b=Get-LedgerDigest $TestDrive
        $a | Should -Not -Be $b
        Set-Content (Join-Path $TestDrive 'probe.json') '{"changed":true}'
        (Get-LedgerDigest $TestDrive) | Should -Not -Be $b
    }
}
Describe 'Migrated catalog contracts' {
    It 'retains all original ids and 79 checks' {
        $release=Join-Path $root '../assets/releases/10.29.8'
        $map=Read-LedgerJson (Join-Path $release 'migration/pim-registry.json')
        $map.features.Count | Should -Be 35
        $map.checks.Count | Should -Be 79
        $pim=Read-LedgerJson (Join-Path $release 'functions/pim.json') (Join-Path $root '../assets/ledger.schema.json')
        @($pim.functions|Where-Object {$_.id -match 'matrix'}).Count | Should -Be 0
        foreach($path in $pim.functions.checks){$null=Read-LedgerJson (Join-Path $release $path) (Join-Path $root '../assets/check.schema.json')}
    }
}
Describe 'Release comparison proposals' {
    It 'detects a probe-only change without calling it a measured platform addition' {
        foreach($version in @('before','after')){
            $dir=Join-Path $TestDrive $version
            $null=New-Item -ItemType Directory -Path (Join-Path $dir 'functions') -Force
            $null=New-Item -ItemType Directory -Path (Join-Path $dir 'probes') -Force
            @{schema=1;dwVersion=$version}|ConvertTo-Json|Set-Content (Join-Path $dir 'manifest.json')
            @{schema=1;area='test';functions=@(@{id='test.feature';checks=@('probes/test.json')})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'functions/test.json')
            @{value=$version}|ConvertTo-Json|Set-Content (Join-Path $dir 'probes/test.json')
        }
        @{candidates=@()}|ConvertTo-Json|Set-Content (Join-Path $TestDrive 'evidence.json')
        & (Join-Path $root 'Compare-DwLedgerRelease.ps1') -Before (Join-Path $TestDrive 'before/manifest.json') -After (Join-Path $TestDrive 'after/manifest.json') -EvidenceFile (Join-Path $TestDrive 'evidence.json') -OutFile (Join-Path $TestDrive 'delta.json')
        $LASTEXITCODE | Should -Be 0
        $delta=Read-LedgerJson (Join-Path $TestDrive 'delta.json')
        $delta.status | Should -Be proposed
        $delta.changed | Should -Contain 'test.feature'
        $delta.unresolved | Should -Contain 'test.feature'
        $delta.added.Count | Should -Be 0
    }
}

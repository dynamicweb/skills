<#
.SYNOPSIS
READ-ONLY. CPQ observation green/red controls using isolated synthetic snapshots.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/cpq-observations.md.
No host writes. Tests use independent expected rows and corrupt observed fields.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Cpq.Tests.ps1 -CI
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach($f in @('Ledger.Core.ps1','Cpq.Json.ps1','Cpq.Observations.ps1')){. (Join-Path $PSScriptRoot "../$f")}
    function Copy-Value($v){return ,(ConvertFrom-Json (ConvertTo-Json -InputObject $v -Depth 80 -Compress) -AsHashtable -NoEnumerate)}
    function New-CpqFixture {
        $inputs=@(@{InputId=4;InputName='Size';InputGroupId=3;InputType='select';InputRequired=$true;InputVisible=$true;InputReadOnly=$false;InputEnabled=$true;InputSeq=1;InputDefaultValue='small';InputOptions='[{"value":"small","label":"Small"}]';InputSettings='[]';InputDataSource='';InputDataParameters=''})
        $groups=@(@{GroupId=3;GroupModelVersionId=2;GroupParentId='0';GroupName='Build';GroupMode='input';GroupEnabled=$true;GroupCondition=''},@{GroupId=5;GroupModelVersionId=2;GroupParentId='0';GroupName='Rules';GroupMode='input_rule';GroupEnabled=$true;GroupCondition=''})
        $rule=@{InputRuleId=6;InputRuleGroupId=5;InputRuleEnabled=$true;InputRuleType='CPQOptions';InputRuleSeq=1;InputRuleConditions='[{"group_operator":"AND","and":[["formInput[Size]","eq","small"]]}]'}
        $rows=@{CPQModel=@(@{ModelId=1});CPQModelVersion=@(@{ModelVersionId=2;ModelVersionModelId=1});CPQGroup=$groups;CPQInput=$inputs;CPQInputRule=@($rule);CPQBOMRule=@();CPQPriceRule=@();CPQRouteRule=@();CPQModelVariable=@();CPQOutputRule=@();CPQOutputAction=@();EcomProducts=@(@{ProductNumber='FRAME'})}
        $schema=Get-Content (Join-Path $PSScriptRoot '../../assets/cpq-columns.json') -Raw | ConvertFrom-Json -AsHashtable
        $columns=@(foreach($t in $schema.Keys){foreach($c in $schema[$t].Keys){@{TABLE_NAME=$t;COLUMN_NAME=$c;DATA_TYPE=$schema[$t][$c]}}})
        # Authored expectation, not extracted from the observed input.
        $want=@{InputName='Size';InputGroupId=3;InputType='select';InputRequired=$true;InputVisible=$true;InputReadOnly=$false;InputEnabled=$true;InputSeq=1;InputDefaultValue='small';InputOptions='[{"label":"Small","value":"small"}]';InputSettings='[]'}
        $expected=@{modelId=1;versionId=2;inputs=@($want);children=@{CPQGroup=@(3,5);CPQInput=@(4);CPQInputRule=@(6);CPQBOMRule=@();CPQPriceRule=@();CPQRouteRule=@();CPQModelVariable=@();CPQOutputRule=@();CPQOutputAction=@()}}
        return @{expected=$expected;snapshot=@{complete=$true;modelId=1;versionId=2;rows=$rows;schema=$columns}}
    }
    function Verdict($f,$aspect){Test-LedgerAssertion @{kind='attributes';minimumSubjects=1} (Test-CpqObservation $aspect $f.expected $f.snapshot)}
}
Describe 'CPQ complete stored observations' {
    It 'passes independent complete <aspect> scope' -TestCases @(
        @{aspect='installation.schema'},@{aspect='inputs.declaration'},@{aspect='conditions.dialect'},@{aspect='input-rules.loader'},@{aspect='model-versions.integrity'}
    ) {param($aspect);Verdict (New-CpqFixture) $aspect | Should -BeExactly PASS}
    It 'rejects missing columns and wrong SQL types' {
        $f=New-CpqFixture;$f.snapshot.schema=$f.snapshot.schema[1..($f.snapshot.schema.Count-1)]
        Verdict $f installation.schema | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.schema[0].DATA_TYPE='wrong'
        Verdict $f installation.schema | Should -BeExactly FAIL
    }
    It 'rejects every input declaration mismatch without evaluating literal defaults' {
        foreach($key in @('InputType','InputGroupId','InputRequired','InputVisible','InputReadOnly','InputEnabled','InputSeq','InputOptions','InputSettings')){
            $f=New-CpqFixture;$f.snapshot.rows.CPQInput[0][$key]='broken'
            Verdict $f inputs.declaration | Should -BeExactly FAIL
        }
        $f=New-CpqFixture;$f.expected.inputs[0].InputDefaultValue='formInput[NotEvaluated]';$f.snapshot.rows.CPQInput[0].InputDefaultValue='formInput[NotEvaluated]'
        Verdict $f inputs.declaration | Should -BeExactly PASS
        $f.snapshot.rows.CPQInput=@();Verdict $f inputs.declaration | Should -BeExactly FAIL
    }
    It 'rejects missing loader type, wrong group mode, disabled group and duplicate order' {
        foreach($mode in @('type','group','enabled','order')){
            $f=New-CpqFixture
            switch($mode){type {$f.snapshot.rows.CPQInputRule[0].InputRuleType=''} group {$f.snapshot.rows.CPQGroup[1].GroupMode='input'} enabled {$f.snapshot.rows.CPQGroup[1].GroupEnabled=$false} order {$f.snapshot.rows.CPQInputRule+=Copy-Value $f.snapshot.rows.CPQInputRule[0]}}
            Verdict $f input-rules.loader | Should -BeExactly FAIL
        }
    }
    It 'rejects unsafe object tests, symbolic operators, lowercase groups, missing references and duplicate keys' {
        foreach($text in @(
            '[{"left":"formInput[Size]","operator":"eq","right":"small"}]',
            '[{"group_operator":"AND","and":[["formInput[Size]","==","small"]]}]',
            '[{"group_operator":"and","and":[["formInput[Size]","eq","small"]]}]',
            '[{"group_operator":"AND","and":[["formInput[Other]","eq","small"]]}]',
            '[{"group_operator":"AND","group_operator":"OR","and":[["formInput[Size]","eq","small"]]}]'
        )){$f=New-CpqFixture;$f.snapshot.rows.CPQInputRule[0].InputRuleConditions=$text;Verdict $f conditions.dialect | Should -BeExactly FAIL}
    }
    It 'checks references case-insensitively and checks nested group and price conditions' {
        $f=New-CpqFixture;$f.snapshot.rows.CPQInputRule[0].InputRuleConditions='[{"group_operator":"OR","or":[["forminput[size]","in",["small","large"]],{"group_operator":"AND","and":[["var[bom_total_sell]","gte",0]]}]}]'
        Verdict $f conditions.dialect | Should -BeExactly PASS
        $f.snapshot.rows.CPQPriceRule=@(@{Conditions='[["formInput[Missing]","hasvalue",""]]'});Verdict $f conditions.dialect | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.rows.CPQGroup[0].GroupCondition='[["formInput[Missing]","eq",1]]';Verdict $f conditions.dialect | Should -BeExactly FAIL
    }
    It 'refuses missing scope and wrong model/version rather than passing zero subjects' {
        $f=New-CpqFixture;$f.snapshot.complete=$false;Verdict $f conditions.dialect | Should -BeExactly UNVERIFIED
        $f=New-CpqFixture;$f.snapshot.rows.CPQModelVersion[0].ModelVersionModelId=99;Verdict $f conditions.dialect | Should -BeExactly UNVERIFIED
        $f=New-CpqFixture;$f.expected.Remove('inputs');Verdict $f inputs.declaration | Should -BeExactly UNVERIFIED
        $f=New-CpqFixture;$f.snapshot.rows.CPQInputRule=@();Verdict $f input-rules.loader | Should -BeExactly FAIL
    }
    It 'finds undeclared children, another parent, duplicate names and dangling quantity references' {
        $f=New-CpqFixture;$f.expected.children.CPQInput=@(99);Verdict $f model-versions.integrity | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.rows.CPQGroup[0].GroupParentId='99';Verdict $f model-versions.integrity | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.rows.CPQGroup[0].GroupParentId='5';$f.snapshot.rows.CPQGroup[1].GroupParentId='3';Verdict $f model-versions.integrity | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.rows.CPQGroup[1].GroupName='build';Verdict $f model-versions.integrity | Should -BeExactly FAIL
        $f=New-CpqFixture;$f.snapshot.rows.CPQBOMRule=@(@{BOMRuleId=7;BOMRuleGroupId=3;BOMRuleBomItems='[{"no":"FRAME","qty":"formInput[Missing]"}]'});$f.expected.children.CPQBOMRule=@(7)
        Verdict $f model-versions.integrity | Should -BeExactly FAIL
    }
    It 'does not promote partial BOM, lookup or file-only installation evidence' {
        $f=New-CpqFixture
        foreach($aspect in @('bom.references','lookups.scope','installation.loaded','page.binding','pricing.scope','erp.requirements')){Verdict $f $aspect | Should -BeExactly UNVERIFIED}
        $f.snapshot.installedAssemblies=@(@{name='CPQ_Admin';version='10.24.2.0'})
        Verdict $f installation.loaded | Should -BeExactly UNVERIFIED
    }
    It 'compares complete normalized configured and loaded evidence with red controls' {
        foreach($pair in @(@{aspect='page.binding';key='page';observed='pageScope';value=@{modelVersionId=2;navigation='Configure';theme='neutral';tabs=@('Build')}},@{aspect='pricing.scope';key='pricing';observed='pricing';value=@{shopId='S';languageId='L';currency='EUR';priceBasis='ex-vat';customerContext='anonymous';decimalPlaces=2;rounding='half-up'}},@{aspect='erp.requirements';key='erp';observed='erp';value=@{mode='none'}},@{aspect='installation.loaded';key='assemblies';observed='loadedAssemblies';value=@(@{name='CPQ_Admin';version='10.24.2.0';sha256=('a'*64)})})){
            $f=New-CpqFixture;$f.expected[$pair.key]=$pair.value;$f.snapshot[$pair.observed]=Copy-Value $pair.value
            Verdict $f $pair.aspect | Should -BeExactly PASS
            if($pair.aspect -eq 'installation.loaded'){$f.snapshot.loadedAssemblies+=Copy-Value $pair.value[0]}else{$first=@($pair.value.Keys)[0];$f.snapshot[$pair.observed][$first]='wrong'}
            Verdict $f $pair.aspect | Should -BeExactly FAIL
        }
    }
}

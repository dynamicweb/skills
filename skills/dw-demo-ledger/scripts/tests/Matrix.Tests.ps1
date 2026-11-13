<#
.SYNOPSIS
READ-ONLY. Matrix green and red controls without target writes.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/matrix-fields.md.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Matrix.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Sql.ps1','Ledger.Transport.ps1','Ledger.Execute.ps1','Pim.Matrix.ps1')){. (Join-Path $PSScriptRoot "../$file")}
    function New-MatrixFixture {
        $m=@{categoryId='nutrition';columns=@(@{id='name';type='Text'},@{id='amount';type='Double'});subjects=@(@{productId='P1';variantId='';languageId='L1';ownerCategoryId='food';ownerFieldId='table';rows=@(@{sortOrder=0;cells=@{name='Salt';amount=1.5}},@{sortOrder=1;cells=@{name='Energy';amount=0}})})}
        $o=@{categories=@(@{id='nutrition';type=3});columns=@(@{id='name';type='Text';typeId=1;presentation=''},@{id='amount';type='Double';typeId=7;presentation=''});subjects=@(@{parents=@(@{categoryId='food';fieldId='table';row=0;value=$null;referenceCategoryId='nutrition'});cells=@(
            @{categoryId='nutrition';fieldId='name';row=0;value='Salt';referenceCategoryId=''},
            @{categoryId='nutrition';fieldId='amount';row=0;value='1.500';referenceCategoryId=''},
            @{categoryId='nutrition';fieldId='name';row=1;value='Energy';referenceCategoryId=''},
            @{categoryId='nutrition';fieldId='amount';row=1;value='0';referenceCategoryId=''}
        )})
            owners=@(@{categoryId='food';id='table';type='Matrix';matrixCategoryId='nutrition'})
            markers=@(@{productId='P1';variantId='';languageId='L1';categoryId='food';fieldId='table';markers=1})
            census=@(@{productId='P1';variantId='';languageId='L1';cells=4})}
        return @{matrix=$m;observation=$o}
    }
}
Describe 'Matrix evidence is exact and has red controls' {
    It 'passes the complete <aspect> observation' -TestCases @(@{aspect='columns'},@{aspect='parent-marker'},@{aspect='cells'},@{aspect='negative-control'}) {
        param($aspect)
        $f=New-MatrixFixture
        Test-LedgerAssertion @{kind='scalar';op='eq';value=1} (Test-PimMatrixObservation $f.matrix $f.observation $aspect) | Should -Be PASS
    }
    It 'rejects a wrong category type and wrong column type' {
        $f=New-MatrixFixture;$f.observation.categories[0].type=0
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
        $f=New-MatrixFixture;$f.observation.columns[1].type='Text'
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
    }
    It 'rejects an unsupported matrix column and a non-dropdown list' {
        $f=New-MatrixFixture;$f.observation.columns[0].typeId=2
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
        $f=New-MatrixFixture;$f.matrix.columns[0].type='List';$f.observation.columns[0].type='List';$f.observation.columns[0].typeId=15;$f.observation.columns[0].presentation='3'
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
        $f.observation.columns[0].presentation='2'
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 1
    }
    It 'rejects each broken parent marker property' {
        foreach($key in @('categoryId','fieldId','referenceCategoryId','row','value')){
            $f=New-MatrixFixture;$f.observation.subjects[0].parents[0][$key]='incorrect'
            (Test-PimMatrixObservation $f.matrix $f.observation 'parent-marker').value | Should -Be 0
        }
        $f=New-MatrixFixture;$f.observation.subjects[0].parents=@()
        (Test-PimMatrixObservation $f.matrix $f.observation 'parent-marker').value | Should -Be 0
    }
    It 'fails an altered cell and the negative control refuses already-broken data' {
        $f=New-MatrixFixture;$f.observation.subjects[0].cells[1].value='1.6'
        foreach($aspect in @('cells','negative-control')){
            Test-LedgerAssertion @{kind='scalar';op='eq';value=1} (Test-PimMatrixObservation $f.matrix $f.observation $aspect) | Should -Be FAIL
        }
    }
    It 'rejects missing, duplicate, additional and misplaced cells' {
        foreach($mode in @('missing','duplicate','extra','row','category')){
            $f=New-MatrixFixture;$cells=$f.observation.subjects[0].cells
            switch($mode){
                missing {$f.observation.subjects[0].cells=$cells[0..2]}
                duplicate {$cells[3]=$cells[0].Clone()}
                extra {$f.observation.subjects[0].cells+=,$cells[0].Clone()}
                row {$cells[0].row=4}
                category {$cells[0].categoryId='food'}
            }
            (Test-PimMatrixObservation $f.matrix $f.observation 'cells').value | Should -Be 0
        }
    }
    It 'never mutates the source while applying its red control' {
        $f=New-MatrixFixture;$before=$f.observation|ConvertTo-Json -Depth 30
        $null=Test-PimMatrixObservation $f.matrix $f.observation 'negative-control'
        ($f.observation|ConvertTo-Json -Depth 30) | Should -BeExactly $before
    }
    It 'RED CONTROL: an owner field that is not a Matrix field, or is linked to another matrix, fails' {
        $f=New-MatrixFixture;$f.observation.owners[0].type='Text'
        $r=Test-PimMatrixObservation $f.matrix $f.observation 'columns'
        $r.value | Should -Be 0
        $r.offenders[0] | Should -BeLike "*observed type 'Text'*expected 'Matrix' linked to 'nutrition'*"
        $f=New-MatrixFixture;$f.observation.owners[0].matrixCategoryId='other_matrix'
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
        $f=New-MatrixFixture;$f.observation.owners=@()
        (Test-PimMatrixObservation $f.matrix $f.observation 'columns').value | Should -Be 0
    }
    It 'RED CONTROL: rows and markers outside the declared subjects fail' {
        # Matrix rows on an undeclared product (the 999 rows of the retest).
        $f=New-MatrixFixture;$f.observation.census+=,@{productId='P9';variantId='';languageId='L1';cells=2}
        $r=Test-PimMatrixObservation $f.matrix $f.observation 'cells'
        $r.value | Should -Be 0
        $r.offenders | Should -Contain "Undeclared matrix rows: P9//L1: observed 2 cell(s), expected 0"
        # Orphan cells in another language of the declared product.
        $f=New-MatrixFixture;$f.observation.census+=,@{productId='P1';variantId='';languageId='L2';cells=4}
        (Test-PimMatrixObservation $f.matrix $f.observation 'cells').value | Should -Be 0
        # A second parent marker in another owner category.
        $f=New-MatrixFixture;$f.observation.markers+=,@{productId='P1';variantId='';languageId='L1';categoryId='drink';fieldId='table';markers=1}
        $r=Test-PimMatrixObservation $f.matrix $f.observation 'parent-marker'
        $r.value | Should -Be 0
        $r.offenders | Should -Contain "Markers referencing 'nutrition': observed 2, expected 1"
        $f=New-MatrixFixture;$f.observation.markers=@(@{productId='P9';variantId='';languageId='L1';categoryId='food';fieldId='table';markers=1})
        (Test-PimMatrixObservation $f.matrix $f.observation 'parent-marker').value | Should -Be 0
    }
    It 'names observed and expected values in a cell offender' {
        $f=New-MatrixFixture;$f.observation.subjects[0].cells[1].value='1.6'
        $r=Test-PimMatrixObservation $f.matrix $f.observation 'cells'
        $r.offenders | Should -Contain "P1//L1:0:amount: observed '1.6', expected '1.5'"
        $f=New-MatrixFixture;$f.observation.subjects[0].cells=$f.observation.subjects[0].cells[0..2]
        (Test-PimMatrixObservation $f.matrix $f.observation 'cells').offenders | Should -Contain "P1//L1:1:amount: observed 0 cell(s), expected '0'"
    }
    It 'RED CONTROL: a padded or exponent number is another stored representation' {
        Test-PimMatrixValue ' 4e0 ' 4 'Double' | Should -BeFalse
        Test-PimMatrixValue '4e0' 4 'Double' | Should -BeFalse
        Test-PimMatrixValue '-4.50' -4.5 'Double' | Should -BeTrue
        $f=New-MatrixFixture;$f.observation.subjects[0].cells[1].value=' 1.5 '
        (Test-PimMatrixObservation $f.matrix $f.observation 'cells').value | Should -Be 0
    }
    It 'compares numbers invariantly without treating missing values as zero' {
        Test-PimMatrixValue '0' 0 'Double' | Should -BeTrue
        Test-PimMatrixValue $null 0 'Double' | Should -BeFalse
        Test-PimMatrixValue '1,5' 1.5 'Double' | Should -BeFalse
        Test-PimMatrixValue '1.5' 1.5 'Integer' | Should -BeFalse
        Test-PimMatrixValue 'salt' 'Salt' 'Text' | Should -BeFalse
    }
    It 'requires complete nonempty declarations with zero-based rows' {
        $f=New-MatrixFixture
        (Get-PimMatrixDeclaration @{expected=@{matrix=$f.matrix}}).categoryId | Should -Be nutrition
        foreach($mode in @('subjects','columns','rows','cell','duplicate','order')){
            $m=(New-MatrixFixture).matrix
            switch($mode){subjects {$m.subjects=@()} columns {$m.columns=@()} rows {$m.subjects[0].rows=@()} cell {$m.subjects[0].rows[0].cells.Remove('name')} duplicate {$m.subjects+=,$m.subjects[0]} order {$m.subjects[0].rows[0].sortOrder=1}}
            {Get-PimMatrixDeclaration @{expected=@{matrix=$m}}} | Should -Throw
        }
    }
    It 'uses escaped product, variant and language scopes in SELECT only' {
        Mock Invoke-Sqlcmd-Rows {
            param($Server,$Database,$Query)
            Assert-LedgerSelect $Query
            # The whole-category count reads every subject of the category; it carries no subject scope.
            if($Query -match 'COUNT\(\*\) cells'){$Query | Should -Match "FieldValueFieldCategoryId=N'nutrition'";return '[]'}
            $Query | Should -Match "FieldValueProductId=N'P''1'"
            $Query | Should -Match "FieldValueProductVariantId=N'V1'"
            $Query | Should -Match "FieldValueProductLanguageId=N'L1'"
            return '[]'
        }
        $m=(New-MatrixFixture).matrix;$m.subjects[0].productId="P'1";$m.subjects[0].variantId='V1'
        (Get-PimMatrixObservation -Aspect cells -Build @{expected=@{matrix=$m}} -Server '.' -Database 'fixture').value | Should -Be 0
        # The declared subject's cells, then the whole matrix category.
        Should -Invoke Invoke-Sqlcmd-Rows -Times 2 -Exactly
    }
    It 'projects complete SQL JSON into the <aspect> observation' -TestCases @(@{aspect='columns'},@{aspect='parent-marker'},@{aspect='cells'},@{aspect='negative-control'}) {
        param($aspect)
        $script:sqlFixture=New-MatrixFixture
        Mock Invoke-Sqlcmd-Rows {
            param($Server,$Database,$Query)
            Assert-LedgerSelect $Query
            $data=if($Query -match 'FROM EcomProductCategory WHERE'){$script:sqlFixture.observation.categories}
                elseif($Query -match 'FieldMatrixAttributeGroupId'){$script:sqlFixture.observation.owners}
                elseif($Query -match 'EcomProductCategoryField f'){$script:sqlFixture.observation.columns}
                elseif($Query -match 'COUNT\(\*\) markers'){$script:sqlFixture.observation.markers}
                elseif($Query -match 'COUNT\(\*\) cells'){$script:sqlFixture.observation.census}
                elseif($Query -match "FieldValueFieldCategoryId=N'food'"){$script:sqlFixture.observation.subjects[0].parents}
                else{$script:sqlFixture.observation.subjects[0].cells}
            return ConvertTo-Json -InputObject @($data) -Depth 30 -Compress
        }
        $o=Get-PimMatrixObservation -Aspect $aspect -Build @{expected=@{matrix=$script:sqlFixture.matrix}} -Server '.' -Database 'fixture'
        Test-LedgerAssertion @{kind='scalar';op='eq';value=1} $o | Should -Be PASS
    }
}
Describe 'New capability reads never manufacture a pass' {
    It 'rejects a concurrent upgrade or an unavailable final version' {
        Test-LedgerStableVersion '10.28.15+build' '10.28.15+build' | Should -BeTrue
        Test-LedgerStableVersion '10.28.15+build' '10.29.8+build' | Should -BeFalse
        Test-LedgerStableVersion '10.28.15+build' '' | Should -BeFalse
        Test-LedgerStableVersion '' '' | Should -BeFalse
        Test-LedgerStableVersion '10.28.15+one' '10.28.15+two' | Should -BeFalse
    }
    It 'keeps every other new behaviour unverified and its threshold has a red control' {
        $release=Join-Path $PSScriptRoot '../../assets/releases/10.29.8'
        $delta=Read-LedgerJson (Join-Path $release 'delta.json')
        $ids=@($delta.added.id|Where-Object {$_ -ne 'users.login-activity' -and $_ -ne 'pim.matrix-fields'})
        $count=0
        foreach($path in Get-ChildItem (Join-Path $release 'probes') -Recurse -Filter '*.json'){
            $check=Read-LedgerJson $path.FullName
            if($check.functionId -notin $ids){continue}
            $count++
            (Invoke-LedgerCheck $check @{} @{} @{expectations=@{}} @('mcp','admin-api','sql') '' '' '').result | Should -Be UNVERIFIED
            Test-LedgerAssertion $check.assertion @{value=1;complete=$true} | Should -Be PASS
            Test-LedgerAssertion $check.assertion @{value=0;complete=$true} | Should -Be FAIL
        }
        $count | Should -Be $ids.Count
        $count | Should -BeGreaterThan 0
    }
    It 'counts Matrix by alias through MCP and fails its absence' {
        $projection=@{filter=@{field='dynamicwebAlias';op='equals';value='Matrix'}}
        $assertion=@{kind='scalar';op='eq';value=1}
        Test-LedgerAssertion $assertion (Measure-LedgerRows @(@{dynamicwebAlias='Matrix';id=77}) $projection) | Should -Be PASS
        Test-LedgerAssertion $assertion (Measure-LedgerRows @(@{dynamicwebAlias='Text';id=77}) $projection) | Should -Be FAIL
    }
    It 'requires complete typed feature observations and distinguishes false from unknown' {
        $good=@{model=@{totalCount=1;totalPages=1;data=@(@{featureTypeName='Example.Flag';active=$false})}}
        $facts=Get-LedgerFeatureFacts $good
        $facts.ContainsKey('Example.Flag') | Should -BeTrue
        $facts['Example.Flag'] | Should -BeFalse
        $good.model.totalCount=2;{Get-LedgerFeatureFacts $good} | Should -Throw
        $good.model.totalCount=1;$good.model.data[0].active='false';{Get-LedgerFeatureFacts $good} | Should -Throw
    }
    It 'passes flag-on, fails flag-off and rejects an unknown flag observation' {
        $binding=@{handler='admin-feature-flag';operation='FeaturesAll';arguments=@{featureTypeName='Example.Flag'}}
        $cap=@{adminApi=@{authenticated=$true;queries=@('FeaturesAll')};facts=@{'Example.Flag'=$true}}
        $a=@{kind='scalar';op='eq';value=1}
        Test-LedgerAssertion $a (Get-LedgerAdminObservation $binding @{} $cap) | Should -Be PASS
        $cap.facts['Example.Flag']=$false
        Test-LedgerAssertion $a (Get-LedgerAdminObservation $binding @{} $cap) | Should -Be FAIL
        $cap.facts=@{};{Get-LedgerAdminObservation $binding @{} $cap} | Should -Throw
    }
}

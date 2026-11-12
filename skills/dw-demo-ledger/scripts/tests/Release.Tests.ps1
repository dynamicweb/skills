<#
.SYNOPSIS
READ-ONLY. Test generic release discovery with synthetic A/B evidence.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/release-process.md.
No live target or package code execution. Local fixtures test the candidate protocol.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Release.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    . (Join-Path $PSScriptRoot '../Release.Compare.ps1')
    . (Join-Path $PSScriptRoot '../Release.Evidence.ps1')
    function New-ReleasePair {
        $a=@{version='1.0.0';packages=@(@{package='Example';source='https://example.invalid/old';metadata=@{types=@(@{name='Example.FeatureBase';base='System.Object';public=$true;constants=@()},@{name='Example.Old';base='System.Object';public=$true;constants=@()})}});database=@{source='fixture';columns=@(@{schema='dbo';table='Item';name='Id';type='int'});primaryKeys=@(@{schema='dbo';table='Item';name='Id';ordinal=1})}}
        $b=($a | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable)
        $b.version='1.1.0';$b.packages[0].source='https://example.invalid/new';$b.packages[0].assemblyDigest='sha256:fixture'
        $b.packages[0].metadata.types+=@{name='Example.NewCapability';base='Example.FeatureBase';public=$true;constants=@()}
        $b.packages[0].metadata.types+=@{name='Example.Mode';base='System.Enum';public=$true;constants=@(@{name='NewMode';value=3})}
        $b.packages[0].metadata.types+=@{name='Example.Internal';base='System.Object';public=$false;constants=@()}
        $b.database.columns+=@{schema='dbo';table='Item';name='Revision';type='int'}
        $b.database.primaryKeys+=@{schema='dbo';table='Item';name='Revision';ordinal=2}
        @{a=$a;b=$b;notes=@{source='https://example.invalid/releases';releases=@(@{version='1.1.0';isReleased=$true;workItems=@(@{id=100;title='Add a new capability';type='Feature';area='Platform'})})}}
    }
}
Describe 'General release candidate scan' {
    It 'discovers public types, enum values, feature subclasses, columns, keys and notes without a keyword' {
        $pair=New-ReleasePair; $r=@(Compare-ReleaseEvidence $pair.a $pair.b $pair.notes)
        $r.kind | Should -Contain 'feature-class';$r.kind | Should -Contain 'enum-value'
        $r.kind | Should -Contain 'database-column';$r.kind | Should -Contain 'primary-key'
        $r.kind | Should -Contain 'release-work-item';$r.name | Should -Contain 'Example.NewCapability'
        $r.name | Should -Not -Contain 'Example.Internal'
    }
    It 'RED CONTROL: identical inventories emit no additions' {
        $pair=New-ReleasePair
        @(Compare-ReleaseEvidence $pair.a $pair.a @{releases=@()}).Count | Should -Be 0
    }
    It 'preserves removed public types and columns for review' {
        $pair=New-ReleasePair
        $r=@(Compare-ReleaseEvidence $pair.b $pair.a @{releases=@()})
        @($r | Where-Object change -eq removed).Count | Should -Be 3
    }
    It 'RED CONTROL: a feature-named class with no FeatureBase ancestry is not a flag' {
        $pair=New-ReleasePair;$pair.b.packages[0].metadata.types[2].base='System.Object'
        @(Compare-ReleaseEvidence $pair.a $pair.b @{releases=@()} | Where-Object kind -eq 'feature-class').Count | Should -Be 0
    }
    It 'resolves indirect feature inheritance and stops cycles' {
        $pair=New-ReleasePair
        $pair.b.packages[0].metadata.types+=@{name='Example.Child';base='Example.NewCapability';public=$true;constants=@()}
        $pair.b.packages[0].metadata.types+=@{name='Example.Cycle';base='Example.Cycle';public=$true;constants=@()}
        @(Get-ReleaseFeatureTypes $pair.b.packages | Sort-Object) | Should -Be @('Example.Child','Example.NewCapability') -Because 'both inherit the feature base'
    }
    It 'RED CONTROL: missing predecessor package fails rather than claiming every type is new' {
        $pair=New-ReleasePair;$pair.a.packages=@()
        { Compare-ReleaseEvidence $pair.a $pair.b $pair.notes } | Should -Throw '*each requested package*'
    }
    It 'reads framework assembly bytes as metadata without loading target code' {
        $r=Read-ReleaseAssemblyMetadata -Path ([object].Assembly.Location)
        $r.types.name | Should -Contain 'System.Object'
        $r.types.Count | Should -BeGreaterThan 100
    }
    It 'RED CONTROL: a non-assembly is rejected' {
        $p=Join-Path $TestDrive 'not-a-dll';Set-Content -LiteralPath $p -Value 'not executable metadata'
        { Read-ReleaseAssemblyMetadata $p } | Should -Throw
    }
    It 'RED CONTROL: the CLI refuses to overwrite a raw scan' {
        $p=Join-Path $TestDrive 'raw.json';Set-Content -LiteralPath $p -Value '{"retained":true}'
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot '../Find-DwReleaseFunctions.ps1') -BeforeVersion 1.0.0 -AfterVersion 1.1.0 -OutFile $p -EvidenceDirectory $TestDrive 2>$null
        $LASTEXITCODE | Should -Be 1
        (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json).retained | Should -BeTrue
    }
    It 'resolves a moving ring and excludes later patches and other milestones' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*basicinfo') { return ,@(@{latestReleaseName='milestones/10.30'},@{latestReleaseName='milestones/10.29'}) }
            ,@(@{version='10.29.8';isReleased=$true;workItems=@()},@{version='10.29.12';workItems=@()},@{version='10.30.0';workItems=@()},@{version='next release';workItems=@()})
        }
        $r=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $TestDrive
        $r.releases.version | Should -Be @('10.29.8')
        $r.source | Should -Match '/2$'
    }
}
Describe 'The scan can be rerun from retained evidence' {
    BeforeEach {
        $script:dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('n'));$null=New-Item -ItemType Directory $dir
        $script:capture=Join-Path $dir 'changelog-response.json'
        $script:upstream=@(@{version='10.29.8';isReleased=$true;workItems=@(@{id=1;title='One'})},@{version='10.29.12';workItems=@()})
        $script:rings=@(@{latestReleaseName='milestones/10.30'},@{latestReleaseName='milestones/10.29'})
        function Get-Digest([string]$Path){return 'sha256:'+(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    It 'reads a retained changelog capture without any request and leaves it as it is' {
        Mock Invoke-RestMethod {throw 'Unexpected request.'}
        Set-Content -LiteralPath $capture -Value '[{"workItems":[{"title":"One","id":1}],"version":"10.29.8","isReleased":true},{"version":"10.29.12","workItems":[]}]'
        $recorded=Get-Digest $capture
        $r=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir -ChangelogFile $capture -ExpectedDigest $recorded
        $r.releases.version | Should -Be @('10.29.8')
        $r.source | Should -Be 'retained capture'
        $r.responseDigest | Should -Be $recorded
        Get-Digest $capture | Should -Be $recorded
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
    It 'RED CONTROL: refuses a retained capture whose digest is not the recorded one' {
        Set-Content -LiteralPath $capture -Value '[{"version":"10.29.8","workItems":[]}]'
        {Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir -ChangelogFile $capture -ExpectedDigest ('sha256:'+'0'*64)} | Should -Throw '*not the recorded*'
    }
    It 'keeps the ring listing and leaves an unchanged capture alone' {
        Mock Invoke-RestMethod {if($Uri -like '*basicinfo'){return ,$rings};,$upstream}
        $first=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir
        Test-Path (Join-Path $dir 'changelog-rings.json') | Should -BeTrue
        $second=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir
        $second.responseDigest | Should -Be $first.responseDigest
    }
    It 'RED CONTROL: an upstream change does not replace the retained capture' {
        Mock Invoke-RestMethod {if($Uri -like '*basicinfo'){return ,$rings};,$upstream}
        $first=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir
        $script:upstream=@(@{version='10.29.8';isReleased=$true;workItems=@(@{id=1;title='One'},@{id=2;title='Added later'})})
        {Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir} | Should -Throw '*changelog-response.json*differs from the new capture and is not overwritten*'
        Get-Digest $capture | Should -Be $first.responseDigest
    }
    It 'RED CONTROL: a ring listing that moved on does not replace the retained one' {
        Mock Invoke-RestMethod {if($Uri -like '*basicinfo'){return ,$rings};,$upstream}
        $null=Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir
        $before=Get-Digest (Join-Path $dir 'changelog-rings.json')
        $script:rings=@(@{latestReleaseName='milestones/10.31'},@{latestReleaseName='milestones/10.30'},@{latestReleaseName='milestones/10.29'})
        {Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir} | Should -Throw '*changelog-rings.json*is not overwritten*'
        Get-Digest (Join-Path $dir 'changelog-rings.json') | Should -Be $before
        Get-Digest $capture | Should -Not -BeNullOrEmpty
    }
    It 'RED CONTROL: a retained capture brought from elsewhere does not replace a different one in the directory' {
        Set-Content -LiteralPath $capture -Value '[{"version":"10.29.8","workItems":[]}]'
        $other=Join-Path $TestDrive 'other-capture.json';Set-Content -LiteralPath $other -Value '[{"version":"10.29.8","workItems":[{"id":9,"title":"Nine"}]}]'
        {Get-ReleaseChangelogEvidence -Version 10.29.8 -Directory $dir -ChangelogFile $other} | Should -Throw '*is not overwritten*'
        (Get-Content -LiteralPath $capture -Raw).Trim() | Should -Be '[{"version":"10.29.8","workItems":[]}]'
    }
    It 'writes the same bytes for the same content, whatever the member order' {
        $a=@{b=1;a=@{z=$true;y=@(@{k='v';j=2})};list=@()}
        $b=[ordered]@{list=@();a=[ordered]@{y=@([ordered]@{j=2;k='v'});z=$true};b=1}
        $c='{"b":1,"list":[],"a":{"z":true,"y":[{"k":"v","j":2}]}}'|ConvertFrom-Json
        ConvertTo-ReleaseJson $a | Should -BeExactly (ConvertTo-ReleaseJson $b)
        ConvertTo-ReleaseJson $c | Should -BeExactly (ConvertTo-ReleaseJson $b)
        (ConvertTo-ReleaseJson $a) -replace '\s','' | Should -BeExactly '{"a":{"y":[{"j":2,"k":"v"}],"z":true},"b":1,"list":[]}'
    }
    It 'lists a work item once and names every release that carries it' {
        $pair=New-ReleasePair
        $pair.notes.releases+=@{version='1.1.1';isReleased=$true;workItems=@(@{id=100;title='Add a new capability';type='Feature';area='Platform'},@{id=101;title='Another';type='Bug';area='Platform'})}
        $items=@(Compare-ReleaseEvidence $pair.a $pair.b $pair.notes | Where-Object kind -eq 'release-work-item')
        $items.id | Should -Be @('work-item:100','work-item:101')
        $items[0].evidence.version | Should -Be '1.1.0'
        $items[0].evidence.versions | Should -Be @('1.1.0','1.1.1')
    }
    It 'gives the candidates in the same ordinal order on every run' {
        $pair=New-ReleasePair
        $first=@(Compare-ReleaseEvidence $pair.a $pair.b $pair.notes)
        $second=@(Compare-ReleaseEvidence $pair.a $pair.b $pair.notes)
        ConvertTo-ReleaseJson $first | Should -BeExactly (ConvertTo-ReleaseJson $second)
        $keys=[string[]]@($first|ForEach-Object {$_.kind+[char]0+$_.id});$sorted=[string[]]$keys.Clone();[Array]::Sort($sorted,[StringComparer]::Ordinal)
        $keys | Should -Be $sorted
    }
    It 'records which database a schema capture came from, without a machine name' {
        Mock Invoke-Sqlcmd-Rows {'[{"schema":"dbo","table":"Item","name":"Id","type":"int"}]'}
        $a=Get-ReleaseSchemaEvidence -Server 'FixtureServer' -Database 'Before' -Version '1.0.0'
        $same=Get-ReleaseSchemaEvidence -Server 'fixtureserver' -Database 'BEFORE' -Version '1.1.0'
        $other=Get-ReleaseSchemaEvidence -Server 'FixtureServer' -Database 'Elsewhere' -Version '1.1.0'
        $a.provenance.database | Should -Be 'Before'
        $a.provenance.sourceId | Should -Match '^sha256:[a-f0-9]{64}$'
        $same.provenance.sourceId | Should -Be $a.provenance.sourceId
        $other.provenance.sourceId | Should -Not -Be $a.provenance.sourceId
        $a.provenance.hostVersionVerified | Should -BeFalse
        ($a|ConvertTo-Json -Depth 10) | Should -Not -Match 'FixtureServer'
        $a.capturedAt | Should -Not -BeNullOrEmpty
    }
}


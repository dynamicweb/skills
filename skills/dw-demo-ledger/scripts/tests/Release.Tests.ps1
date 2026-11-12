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

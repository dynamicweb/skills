<#
.SYNOPSIS
READ-ONLY. End-to-end controls: the runner and the re-lock script from a clean fixture checkout against a loopback stub.
.DESCRIPTION
PowerShell 7, Pester and Git. Owning reference: ../../references/contract.md. A copy of the
runner is committed to a temporary git repository with a small snapshot (LedgerFixture.ps1), so
the lock commit, the dirty-checkout refusal and an aggregate PASS are exercised for real. The
target is an in-process stub on a free loopback port: no host, no database and no credential.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Runner.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    . (Join-Path $PSScriptRoot 'LedgerFixture.ps1')
    function New-FileBinding([string]$Path){return @{id='file';surface='file';status='implemented';handler='files-count';path=$Path}}
    $present=@{name='present';bindings=@(New-FileBinding 'Marker/*.txt')}
    $script:fixture=New-LedgerFixtureRepo -Path (Join-Path $TestDrive 'repo') -Functions @(
        @{id='fx.files';requires=@();notApplicable=@();checks=@($present,@{name='second';bindings=@(New-FileBinding 'Marker/*.txt')})}
        @{id='fx.flagged';requires=@(@{kind='flag';id='Example.Features.GateFeature';expected=$true});notApplicable=@();checks=@($present)}
        @{id='fx.short';requires=@(@{kind='flag';id='GateFeature';expected=$true});notApplicable=@();checks=@($present)}
        @{id='fx.app';requires=@(@{kind='app';id='Example.App';expected=@{min='1.2.0'}});notApplicable=@();checks=@($present)}
        @{id='fx.setting';requires=@(@{kind='flag';id='/Globalsettings/Settings/Auditing/EnableAuditing';expected=$true});notApplicable=@();checks=@($present)}
        @{id='fx.dependent';requires=@(@{kind='capability';id='fx.files';expected=$true});notApplicable=@();checks=@(@{name='missing';bindings=@(New-FileBinding 'Absent/*.txt')})}
        @{id='fx.ruled';requires=@(@{kind='app';id='Absent.App';expected=$true});notApplicable=@(@{id='catalogue-does-not-use';when='Not used'},@{id='replaced-by-files';when='fx.files carries it';requiresFunction='fx.files'});checks=@($present)}
        @{id='fx.delivery';requires=@();notApplicable=@();checks=@(@{name='served';bindings=@(@{id='dwapi';surface='dwapi';status='implemented';handler='dwapi-count';operation='content/areas';projection=@{rowsPath='$'}})})}
    )
    $script:files=Join-Path $TestDrive 'files'
    $null=New-Item -ItemType Directory -Force (Join-Path $files 'Marker'),(Join-Path $files 'System/AddIns/Installed/Example.App.1.3.0')
    Set-Content (Join-Path $files 'Marker/a.txt') 'marker'
    Set-Content (Join-Path $files 'GlobalSettings.config') '<Globalsettings><Settings><Auditing><EnableAuditing>True</EnableAuditing></Auditing></Settings></Globalsettings>'
    $script:all=@('fx.files.present','fx.files.second','fx.flagged.present','fx.short.present','fx.app.present','fx.setting.present','fx.delivery.served')
    $script:allFunctions=@('fx.files','fx.flagged','fx.short','fx.app','fx.setting','fx.delivery')
    function Start-Site([hashtable]$Change=@{}){
        $settings=@{Versions=@('1.0.0');Features=@{'Example.Features.GateFeature'=$true};Dwapi=@{'content/areas'='[{"id":1},{"id":2}]'}}
        foreach($key in $Change.Keys){$settings[$key]=$Change[$key]}
        $script:state=New-LedgerStubState @settings
        $script:site=Start-LedgerStubSite $state
    }
    function Invoke-Run([string[]]$CheckIds=$all,[string[]]$FunctionIds=$allFunctions,[hashtable]$Lock=@{},[hashtable]$Build=@{},[hashtable]$Arguments=@{}){
        $parameters=@{BaseUrl=$site.url;ApiToken='fixture';FilesPath=$files};foreach($key in $Arguments.Keys){$parameters[$key]=$Arguments[$key]}
        return Invoke-LedgerFixtureRun -Fixture $fixture -CheckIds $CheckIds -FunctionIds $FunctionIds -Lock $Lock -Build $Build -Arguments $parameters -WorkDirectory $TestDrive
    }
    function Get-Row($Run,[string]$Id){return @($Run.report.checks|Where-Object {$_.id -eq $Id})[0]}
    function Restore-Fixture {$null=& git -C $fixture.repo checkout -q -- . 2>&1;$null=& git -C $fixture.repo clean -fdq 2>&1}
}
AfterAll {
    # Git object files are read-only, and the TestDrive cleanup does not remove those.
    if($fixture){Remove-Item -LiteralPath $fixture.repo -Recurse -Force -ErrorAction SilentlyContinue}
}
Describe 'A clean locked run against the stub' {
    AfterEach {if($site){Stop-LedgerStubSite $site;$script:site=$null}}
    It 'passes when the flag, the app, the setting and the delivery read are all established' {
        Start-Site
        $run=Invoke-Run
        $run.exit | Should -Be 0 -Because $run.text
        $run.report.result | Should -Be PASS
        $run.report.counts.PASS | Should -Be 7
        $run.report.errors | Should -BeNullOrEmpty
        $run.report.capabilities.facts.'app:Example.App' | Should -Be '1.3.0'
        (Get-Row $run 'fx.delivery.served').surface | Should -Be dwapi
        # The delivery read is anonymous although the run holds a Management API credential.
        @($state.log|Where-Object {$_ -like 'GET /dwapi/content/areas*'}) | Should -Be @('GET /dwapi/content/areas')
        @($state.log|Where-Object {$_ -notlike 'GET *'}) | Should -BeNullOrEmpty
    }
    It 'states that the local Files root and database are not tied to the target' {
        Start-Site
        $run=Invoke-Run
        $run.report.compatibility.local.files | Should -Be 'not-tied-to-target'
        $run.report.compatibility.local.database | Should -Be 'not-supplied'
    }
    It 'RED CONTROL: reports DISABLED for the functions behind a flag that is off' {
        Start-Site @{Features=@{'Example.Features.GateFeature'=$false}}
        $run=Invoke-Run
        $run.exit | Should -Be 1
        $run.report.result | Should -Be DISABLED
        (Get-Row $run 'fx.flagged.present').result | Should -Be DISABLED
        (Get-Row $run 'fx.short.present').result | Should -Be DISABLED
        $run.report.counts.PASS | Should -Be 5
    }
    It 'RED CONTROL: leaves the flag-gated checks UNVERIFIED without a Management API credential' {
        Start-Site
        $run=Invoke-Run -Arguments @{ApiToken=''}
        (Get-Row $run 'fx.flagged.present').result | Should -Be UNVERIFIED
        (Get-Row $run 'fx.app.present').result | Should -Be PASS
    }
    It 'reports the FAIL of a check whose required function passed' {
        Start-Site
        $run=Invoke-Run @('fx.files.present','fx.files.second','fx.dependent.missing') @('fx.files','fx.dependent')
        $run.exit | Should -Be 1
        $run.report.result | Should -Be FAIL
        (Get-Row $run 'fx.dependent.missing').result | Should -Be FAIL
    }
    It 'applies a ruling before the requirement, and a cited function must be locked and passing' {
        Start-Site
        $build=@{rulings=@{'fx.ruled'=@{applies=$false;rule='catalogue-does-not-use';evidence='Census reviewed.'}}}
        $run=Invoke-Run @('fx.files.present','fx.ruled.present') @('fx.files','fx.ruled') @{} $build
        $run.exit | Should -Be 0 -Because $run.text
        (Get-Row $run 'fx.ruled.present').result | Should -Be 'NOT-APPLICABLE'
        $build.rulings.'fx.ruled'.rule='replaced-by-files'
        (Get-Row (Invoke-Run @('fx.files.present','fx.ruled.present') @('fx.files','fx.ruled') @{} $build) 'fx.ruled.present').result | Should -Be 'NOT-APPLICABLE'
        $run=Invoke-Run @('fx.ruled.present','fx.delivery.served') @('fx.ruled','fx.delivery') @{} $build
        $run.exit | Should -Be 1
        (Get-Row $run 'fx.ruled.present').result | Should -Be UNVERIFIED
        (Get-Row $run 'fx.ruled.present').reason | Should -Match "function 'fx\.files' has no locked check in this build"
    }
}
Describe 'The certified release is the one observed from start to end' {
    AfterEach {if($site){Stop-LedgerStubSite $site;$script:site=$null}}
    It 'RED CONTROL: a version that changes during the run cannot pass' {
        Start-Site @{Versions=@('1.0.0','9.9.9')}
        $run=Invoke-Run
        $run.exit | Should -Be 1
        $run.report.result | Should -Be UNVERIFIED
        $run.report.counts.PASS | Should -Be 7
        $run.report.compatibility.matches | Should -BeFalse
        $run.report.errors | Should -Contain 'Target version changed or became unavailable during observation; the initial baseline cannot certify this report.'
    }
    It 'RED CONTROL: another release blocks every check' {
        Start-Site @{Versions=@('9.9.9')}
        $run=Invoke-Run
        $run.exit | Should -Be 1
        $run.report.counts.UNSUPPORTED | Should -Be 7
        (Get-Row $run 'fx.files.present').reason | Should -Match 'the target reports another release'
    }
    It 'passes after one failed descriptor read' {
        Start-Site @{FailDescriptor=1}
        $run=Invoke-Run
        $run.exit | Should -Be 0 -Because $run.text
        $state.descriptorReads | Should -Be 3
    }
    It 'RED CONTROL: an unreadable descriptor is reported as unread, not as another release' {
        Start-Site @{FailDescriptor=99}
        $run=Invoke-Run
        $run.exit | Should -Be 1
        (Get-Row $run 'fx.files.present').result | Should -Be UNSUPPORTED
        (Get-Row $run 'fx.files.present').reason | Should -Match 'could not be read .* This is not a version mismatch'
        $run.report.errors | Should -Contain 'The target version could not be read: the admin descriptor was unavailable after retries.'
        $state.descriptorReads | Should -Be 6
    }
}
Describe 'A run that stops early says why, in the report too' {
    BeforeAll {Start-Site}
    AfterAll {Stop-LedgerStubSite $site;Restore-Fixture}
    AfterEach {Restore-Fixture}
    It 'RED CONTROL: refuses a changed <path> although the commit matches' -TestCases @(
        @{path='skills/dw-data-access/scripts/Dw.Api.psm1'},@{path='skills/dw-demo-ledger/scripts/Ledger.Transport.ps1'},@{path='skills/dw-demo-ledger/assets/handlers.json'}
    ) {
        param($path)
        Add-Content -LiteralPath (Join-Path $fixture.repo $path) -Value ' '
        $run=Invoke-Run
        $run.exit | Should -Be 1
        $run.text | Should -Match 'Runner does not match the lock: .* with uncommitted changes under skills/dw-demo-ledger or skills/dw-data-access/scripts/Dw\.Api\.psm1'
        $run.report.result | Should -Be ERROR
        $run.report.checks | Should -BeNullOrEmpty
        $run.report.errors[0] | Should -Match '^The run stopped before any check was evaluated\. Runner does not match the lock'
        $run.report.lock.commit | Should -Be $fixture.commit
    }
    It 'runs a changed runner in diagnostic mode only, and never to a PASS' {
        Add-Content -LiteralPath (Join-Path $fixture.repo 'skills/dw-data-access/scripts/Dw.Api.psm1') -Value ' '
        $run=Invoke-Run -Arguments @{DiagnosticVersionMismatch=$true}
        $run.exit | Should -Be 1
        $run.report.result | Should -Be UNVERIFIED
        $run.report.counts.PASS | Should -Be 7
        $run.report.errors | Should -Contain 'Diagnostic runner differs from the locked commit or has uncommitted changes.'
    }
    It 'RED CONTROL: refuses a lock on another commit' {
        $run=Invoke-Run -Lock @{commit='0'*40}
        $run.exit | Should -Be 1
        $run.report.errors[0] | Should -Match "lock\.commit is 0{40}, the checkout is at $($fixture.commit)\."
    }
    It 'names a check that is not in the snapshot, in the report' {
        $run=Invoke-Run ($all+'fx.files.gone')
        $run.exit | Should -Be 1
        $run.report.result | Should -Be ERROR
        $run.report.errors[0] | Should -Match "Locked check 'fx\.files\.gone' is not in the checks list of any function"
        $run.report.compatibility.baseline | Should -Be '1.0.0'
    }
    It 'writes a report without a lock for a build file that is not a build' {
        $run=Invoke-Run -Build @{rulings=@{'fx.files'=@{applies=$false;rule='x';evidence=@{}}}}
        $run.exit | Should -Be 1
        $run.report.lock | Should -BeNullOrEmpty
        $run.report.slug | Should -Be 'unknown'
        $run.report.errors[0] | Should -Match "build\.json' does not match build\.schema\.json"
    }
    It 'names converted line endings as the cause of a digest mismatch' {
        foreach($file in Get-ChildItem $fixture.root -Recurse -File){[IO.File]::WriteAllText($file.FullName,[IO.File]::ReadAllText($file.FullName).Replace("`n","`r`n"))}
        $run=Invoke-Run
        $run.exit | Should -Be 1
        $run.report.errors[0] | Should -Match "lock\.digest is $($fixture.digest), the snapshot beside the manifest is sha256:[a-f0-9]{64}\. \d+ of \d+ snapshot files have CRLF line endings, and with LF endings this snapshot has the locked digest"
    }
}
Describe 'Re-locking an existing build' {
    BeforeAll {
        function Invoke-Relock([hashtable]$Build,[string]$OutFile,[switch]$IncludeNewChecks){
            $file=Join-Path $TestDrive 'old-build.json';Write-LedgerFixtureJson $file $Build
            $parameters=@('-BuildFile',$file,'-Manifest',$fixture.manifest);if($OutFile){$parameters+='-OutFile',$OutFile};if($IncludeNewChecks){$parameters+='-IncludeNewChecks'}
            $output=& pwsh -NoProfile -NonInteractive -File $fixture.relock @parameters 2>&1
            $exit=$LASTEXITCODE;$text=($output|Out-String)
            $report=try{$text|ConvertFrom-Json -AsHashtable}catch{$null}
            return @{exit=$exit;text=$text -replace '\s+',' ';report=$report}
        }
        $script:oldLock=@{commit='1'*40;manifest=$fixture.lockManifest;digest='sha256:'+'1'*64;checkIds=@('fx.files.present','fx.files.layout','fx.app.present')}
        $script:newBuild=Join-Path $TestDrive 'relocked.json'
    }
    AfterEach {Restore-Fixture}
    It 'reports removed checks, removed functions, grounds that are gone and new checks, and writes nothing while a decision is open' {
        $old=@{schema=1;slug='old';lock=$oldLock;functions=@('fx.files','fx.app','fx.removed','fx.ruled')
            rulings=@{'fx.ruled'=@{applies=$false;rule='under-25-fields-per-family';evidence='Counted.'}}}
        $run=Invoke-Relock $old $newBuild
        $run.exit | Should -Be 1
        $run.report.removedFunctions | Should -Be @('fx.removed')
        $run.report.removedChecks | Should -Be @('fx.files.layout')
        $run.report.invalidRulings[0].functionId | Should -Be 'fx.ruled'
        $run.report.invalidRulings[0].groundsNow | Should -Be @('catalogue-does-not-use','replaced-by-files')
        @($run.report.newChecks|ForEach-Object {$_.id}) | Should -Be @('fx.files.second','fx.ruled.present')
        $run.report.snapshotChanged | Should -BeTrue
        $run.report.written | Should -BeFalse
        Test-Path $newBuild | Should -BeFalse
    }
    It 'writes a lock that the runner accepts and that passes' {
        $old=@{schema=1;slug='old';lock=$oldLock;functions=@('fx.files','fx.app');defaultLanguage='LANG1'}
        $run=Invoke-Relock $old $newBuild
        $run.exit | Should -Be 0 -Because $run.text
        $run.report.to.commit | Should -Be $fixture.commit
        $run.report.to.digest | Should -Be $fixture.digest
        $relocked=Get-Content $newBuild -Raw|ConvertFrom-Json -AsHashtable
        $relocked.lock.checkIds | Should -Be @('fx.files.present','fx.app.present')
        $relocked.defaultLanguage | Should -Be 'LANG1'
        Start-Site
        try{
            $run=Invoke-LedgerFixtureRun -Fixture $fixture -BuildFile $newBuild -Arguments @{BaseUrl=$site.url;FilesPath=$files} -WorkDirectory $TestDrive
            $run.exit | Should -Be 0 -Because $run.text
            $run.report.result | Should -Be PASS
        }finally{Stop-LedgerStubSite $site}
    }
    It 'locks new checks only when asked, and never overwrites a build file' {
        $old=@{schema=1;slug='old';lock=$oldLock;functions=@('fx.files','fx.app')}
        $run=Invoke-Relock $old $newBuild
        $run.exit | Should -Be 1
        $run.text | Should -Match 'already exists'
        $second=Join-Path $TestDrive 'relocked-all.json'
        $run=Invoke-Relock $old $second -IncludeNewChecks
        $run.exit | Should -Be 0 -Because $run.text
        (Get-Content $second -Raw|ConvertFrom-Json).lock.checkIds | Should -Be @('fx.files.present','fx.app.present','fx.files.second')
    }
    It 'reports without writing when no OutFile is given' {
        $run=Invoke-Relock @{schema=1;slug='old';lock=$oldLock;functions=@('fx.files','fx.app')}
        $run.exit | Should -Be 0
        $run.report.written | Should -BeFalse
        $run.report.to.checks | Should -Be 2
    }
    It 'RED CONTROL: refuses to lock a checkout with uncommitted changes' {
        Add-Content -LiteralPath (Join-Path $fixture.repo 'skills/dw-demo-ledger/scripts/Ledger.Core.ps1') -Value ' '
        $run=Invoke-Relock @{schema=1;slug='old';lock=$oldLock;functions=@('fx.files','fx.app')} (Join-Path $TestDrive 'dirty.json')
        $run.exit | Should -Be 1
        $run.text | Should -Match 'uncommitted changes'
        Test-Path (Join-Path $TestDrive 'dirty.json') | Should -BeFalse
    }
}

<#
.SYNOPSIS
READ-ONLY. Red controls for the read-only guards, rulings, profiles and runner errors.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. Isolated fixtures, a fake
SQL connection and mocked MCP calls only: no host, no database and no credential.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Integrity.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Sql.ps1','Pim.Fields.ps1','Pim.Queries.ps1','Ledger.Transport.ps1','Ledger.Execute.ps1')){. (Join-Path $PSScriptRoot "../$file")}
    $script:assets=Join-Path $PSScriptRoot '../../assets'
    function Invoke-DwMcp {param($Tool,$Arguments,[switch]$Raw,$TimeoutSec);throw 'Unexpected MCP call.'}
    function New-TestCheck([hashtable]$Binding,[hashtable]$Assertion=@{kind='scalar';op='ge';value=1}){
        return @{id='fx.count';functionId='fx';intent=@{proves='Count';level='configured'};assertion=$Assertion;bindings=@($Binding)}
    }
    $script:cap=@{mcp=@{available=$true;tools=@('get_currencies','delete_product')};adminApi=@{authenticated=$false;queries=@()};dwapi=@{available=$false};file=@{available=$false};sql=@{available=$true}}
    $script:noProfile=@{expectations=@{}}
}
Describe 'SQL text is one read-only SELECT' {
    It 'refuses <query>' -TestCases @(
        @{query='SELECT 1 CREATE TABLE dbo.LedgerProbe(a int)'}
        @{query='SELECT 1 GRANT CONTROL ON DATABASE::Demo TO public'}
        @{query="SELECT 1 BACKUP DATABASE Demo TO DISK='C:\x.bak'"}
        @{query='SELECT 1 DBCC FREEPROCCACHE'}
        @{query='SELECT 1 KILL 55'}
        @{query='SELECT 1 SHUTDOWN WITH NOWAIT'}
        @{query='SELECT 1 CREATE LOGIN probe WITH PASS'+"WORD='...'"}  # split so the credential lint does not read a literal
        @{query='SELECT 1 DISABLE TRIGGER ALL ON DATABASE'}
        @{query="SELECT 1 WAITFOR DELAY '00:05:00'"}
        @{query='SELECT NEXT VALUE FOR dbo.Seq'}
        @{query='SELECT 1 RECEIVE TOP(1) * FROM q'}
        @{query='SELECT 1 USE master'}
        @{query='SELECT 1 BEGIN TRAN'}
        @{query='DELETE FROM EcomProducts'}
        @{query='SELECT 1 DELETE FROM EcomProducts'}
        @{query='SELECT 1 SELECT 2'}
        @{query='SELECT 1 FROM t WHERE x IN (SELECT 1) SELECT 2'}
        @{query="SELECT [a'b] DROP TABLE x SELECT [c'd]"}
        @{query='SELECT "a''b" DROP TABLE x SELECT "c''d"'}
        @{query="SELECT 'unterminated"}
        @{query='SELECT (1'}
        @{query='SELECT 1) FROM (t'}
    ) {
        param($query)
        {Assert-LedgerSelect $query} | Should -Throw
    }
    It 'allows <query>' -TestCases @(
        @{query='SELECT 1 UNION ALL SELECT 2'}
        @{query="SELECT [Update], [a'b] FROM t WHERE x IN (SELECT y FROM z)"}
        @{query='SELECT COUNT(*) FROM (SELECT 1 a UNION SELECT 2 EXCEPT SELECT 3) q'}
        @{query="SELECT N'/*', N'drop table x', N'a'';b'"}
    ) {
        param($query)
        {Assert-LedgerSelect $query} | Should -Not -Throw
    }
    It 'allows every query shipped in <version>, raw and with its tokens expanded' -TestCases @(@{version='10.29.8'},@{version='10.28.15'}) {
        param($version)
        $build=@{defaultLanguage='LANG1';pimShop='SHOP1';productScope=@{exclude=@(@{idLike='X%'})}}
        $queries=@(Get-ChildItem (Join-Path $assets "releases/$version/probes") -Recurse -Filter '*.json' | ForEach-Object {(Read-LedgerJson $_.FullName).bindings} | Where-Object {$_.query} | ForEach-Object {$_.query})
        $queries.Count | Should -BeGreaterThan 300
        foreach($query in $queries){
            {Assert-LedgerSelect $query} | Should -Not -Throw -Because $query
            {Assert-LedgerSelect (Expand-PimSql $query $build)} | Should -Not -Throw -Because $query
        }
    }
}
Describe 'SQL reads are never committed' {
    BeforeEach {
        $script:log=[Collections.Generic.List[string]]::new()
        function New-FakeConnection([scriptblock]$Read){
            $log=$script:log
            $reader=[pscustomobject]@{left=1}
            $reader|Add-Member ScriptMethod Read $Read
            $reader|Add-Member ScriptMethod IsDBNull {param($i) $false}
            $reader|Add-Member ScriptMethod GetValue {param($i) 7}
            $reader|Add-Member ScriptMethod Dispose {}
            $transaction=[pscustomobject]@{}
            $transaction|Add-Member ScriptMethod Rollback {$log.Add('rollback')}.GetNewClosure()
            $transaction|Add-Member ScriptMethod Commit {$log.Add('commit')}.GetNewClosure()
            $transaction|Add-Member ScriptMethod Dispose {}
            $command=[pscustomobject]@{Transaction=$null;CommandText='';CommandTimeout=0}
            $command|Add-Member ScriptMethod ExecuteReader {if($null -eq $this.Transaction){throw 'No transaction.'};$log.Add('execute');$reader}.GetNewClosure()
            $command|Add-Member ScriptMethod Dispose {}
            $connection=[pscustomobject]@{}
            $connection|Add-Member ScriptMethod Open {}
            $connection|Add-Member ScriptMethod BeginTransaction {$log.Add('begin');$transaction}.GetNewClosure()
            $connection|Add-Member ScriptMethod CreateCommand {$command}.GetNewClosure()
            $connection|Add-Member ScriptMethod Dispose {$log.Add('dispose')}.GetNewClosure()
            return $connection
        }
    }
    It 'runs the read inside a transaction and rolls it back' {
        $connection=New-FakeConnection {if($this.left -gt 0){$this.left--;return $true};return $false}
        Mock New-LedgerSqlConnection {$connection}
        Invoke-Sqlcmd-Scalar -Server '.' -Database 'fixture' -Query 'SELECT COUNT(*) FROM T' | Should -Be 7
        $log -join ',' | Should -Be 'begin,execute,rollback,dispose'
    }
    It 'rolls back when the read fails' {
        $connection=New-FakeConnection {throw 'Read failed.'}
        Mock New-LedgerSqlConnection {$connection}
        {Invoke-Sqlcmd-Rows -Server '.' -Database 'fixture' -Query 'SELECT COUNT(*) FROM T'} | Should -Throw '*Read failed*'
        $log -join ',' | Should -Be 'begin,execute,rollback,dispose'
    }
    It 'opens no connection for a refused statement' {
        Mock New-LedgerSqlConnection {throw 'Unexpected connection.'}
        {Invoke-Sqlcmd-Rows -Server '.' -Database 'fixture' -Query 'SELECT 1 DBCC FREEPROCCACHE'} | Should -Throw '*single local SELECT*'
        Should -Invoke New-LedgerSqlConnection -Times 0 -Exactly
    }
    It 'ships no script that commits a transaction' {
        Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter '*.ps1' -File | Select-String -Pattern '\.Commit\(' | Should -BeNullOrEmpty
    }
}
Describe 'MCP bindings call allowlisted read tools only' {
    BeforeEach {$script:LedgerMcpCache=@{}}
    It 'refuses a write tool before the call, although the target lists it' {
        Mock Invoke-DwMcp {@{isError=$false;structuredContent=@{data=@(@{id=1})}}}
        $binding=@{id='m';surface='mcp';status='implemented';handler='mcp-count';operation='delete_product';arguments=@{productId='{pimShop}'}}
        $row=Invoke-LedgerCheck (New-TestCheck $binding) @{pimShop='SHOP1'} $cap $noProfile @('mcp') '' '' ''
        $row.result | Should -Be ERROR
        Should -Invoke Invoke-DwMcp -Times 0 -Exactly
    }
    It 'calls an allowlisted read tool' {
        Mock Invoke-DwMcp {@{isError=$false;structuredContent=@{data=@(@{id=1})}}}
        $binding=@{id='m';surface='mcp';status='implemented';handler='mcp-count';operation='get_currencies'}
        (Invoke-LedgerCheck (New-TestCheck $binding) @{} $cap $noProfile @('mcp') '' '' '').result | Should -Be PASS
        Should -Invoke Invoke-DwMcp -Times 1 -Exactly -ParameterFilter {$Tool -eq 'get_currencies'}
    }
    It 'lists read tools only' {
        $registry=Read-LedgerJson (Join-Path $assets 'handlers.json')
        $registry.mcpReadTools.Count | Should -BeGreaterThan 0
        @($registry.mcpReadTools | Where-Object {$_ -cnotmatch '^(get|list)_[a-z_]+$'}) | Should -BeNullOrEmpty
    }
}
Describe 'A profile changes expectations, never the judgement' {
    BeforeEach {
        Mock Read-LedgerMcp {@{data=@(@{id=1})}}
        $script:check=New-TestCheck @{id='m';surface='mcp';status='implemented';handler='mcp-count';operation='get_currencies'} @{kind='scalar';op='ge';value=100}
    }
    It 'keeps the failing observation a FAIL without a profile' {
        (Invoke-LedgerCheck $check @{} $cap $noProfile @('mcp') '' '' '').result | Should -Be FAIL
    }
    It 'refuses a profile that states <key>' -TestCases @(@{key='kind';value='offenders'},@{key='aspect';value='typing'},@{key='handler';value='sql-scalar'}) {
        param($key,$value)
        $row=Invoke-LedgerCheck $check @{} $cap @{expectations=@{'fx.count'=@{$key=$value}}} @('mcp') '' '' ''
        $row.result | Should -Be ERROR
        Should -Invoke Read-LedgerMcp -Times 0 -Exactly
    }
    It 'applies op, value and minimumSubjects' {
        (Invoke-LedgerCheck $check @{} $cap @{expectations=@{'fx.count'=@{op='ge';value=1;minimumSubjects=1}}} @('mcp') '' '' '').result | Should -Be PASS
    }
    It 'refuses an offenders assertion on a scalar handler' {
        Mock Read-LedgerMcp {@{data=@(1..5|ForEach-Object {@{id=$_}})}}
        $check.assertion=@{kind='offenders'}
        (Invoke-LedgerCheck $check @{} $cap $noProfile @('mcp') '' '' '').result | Should -Be ERROR
    }
    It 'ships profiles that state expectations only' {
        foreach($file in Get-ChildItem (Join-Path $assets 'profiles') -Filter '*.json'){
            foreach($entry in (Read-LedgerJson $file.FullName).expectations.Values){@($entry.Keys | Where-Object {$_ -cnotin @('op','value','minimumSubjects')}) | Should -BeNullOrEmpty}
        }
    }
}
Describe 'Requirements compare typed facts' {
    It 'refuses a text expectation whatever the fact is' {
        foreach($fact in @($true,$false)){
            (Get-LedgerRequirementState @{kind='flag';id='F';expected='false'} @{F=$fact}).result | Should -Be ERROR
        }
        (Get-LedgerRequirementState @{kind='capability';id='F';expected=1} @{F=$true}).result | Should -Be ERROR
    }
    It 'establishes, disables, rejects and leaves unknown' {
        Get-LedgerRequirementState @{kind='flag';id='F';expected=$true} @{F=$true} | Should -BeNullOrEmpty
        (Get-LedgerRequirementState @{kind='flag';id='F';expected=$true} @{F=$false}).result | Should -Be DISABLED
        (Get-LedgerRequirementState @{kind='capability';id='F';expected=$true} @{F=$false}).result | Should -Be UNSUPPORTED
        (Get-LedgerRequirementState @{kind='flag';id='F';expected=$true} @{}).result | Should -Be UNVERIFIED
        (Get-LedgerRequirementState @{kind='app';id='F';expected='false'} @{F=$true}).result | Should -Be UNSUPPORTED
    }
    It 'rejects a text expectation in a function file' {
        $function=@{id='fx.one';area='fx';name='One';skill='dw-demo-ledger';status='candidate';requires=@(@{kind='flag';id='F';expected='false'});inputs=@();checks=@();notApplicable=@();sources=@()}
        $file=Join-Path $TestDrive 'fx.json'
        @{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content $file
        {Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Throw '*ledger.schema.json*'
        $function.requires[0].expected=$false
        @{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content $file
        {Read-LedgerJson $file (Join-Path $assets 'ledger.schema.json')} | Should -Not -Throw
    }
}
Describe 'Rulings certify nothing by themselves' {
    BeforeAll {$script:function=@{id='fx.one';notApplicable=@(@{id='catalogue-does-not-use';when='Not used'})}}
    It 'does not pass a run in which nothing was evaluated' {
        Get-LedgerVerdict @(@{result='NOT-APPLICABLE'}) | Should -Be UNVERIFIED
        Get-LedgerVerdict @(@{result='NOT-APPLICABLE'},@{result='NOT-APPLICABLE'}) | Should -Be UNVERIFIED
        Get-LedgerVerdict @(@{result='PASS'},@{result='NOT-APPLICABLE'}) | Should -Be PASS
        Get-LedgerVerdict @(@{result='FAIL'},@{result='NOT-APPLICABLE'}) | Should -Be FAIL
    }
    It 'refuses a ruling with <name>' -TestCases @(
        @{name='an object as evidence';ruling=@{applies=$false;rule='catalogue-does-not-use';evidence=@{}}}
        @{name='blank evidence';ruling=@{applies=$false;rule='catalogue-does-not-use';evidence=' '}}
        @{name='no evidence';ruling=@{applies=$false;rule='catalogue-does-not-use'}}
        @{name='a number as evidence';ruling=@{applies=$false;rule='catalogue-does-not-use';evidence=1}}
        @{name='text for applies';ruling=@{applies='false';rule='catalogue-does-not-use';evidence='x'}}
        @{name='a ground the function does not allow';ruling=@{applies=$false;rule='no-erp';evidence='x'}}
    ) {
        param($name,$ruling)
        Get-LedgerRulingFault $ruling $function | Should -Not -BeNullOrEmpty
        $build=@{schema=1;slug='fx';lock=@{commit='0'*40;manifest='m';digest='sha256:'+'0'*64;checkIds=@()};functions=@('fx.one');rulings=@{'fx.one'=$ruling}}
        $file=Join-Path $TestDrive 'build.json';$build|ConvertTo-Json -Depth 10|Set-Content $file
        if($name -ne 'a ground the function does not allow'){{Read-LedgerJson $file (Join-Path $assets 'build.schema.json')} | Should -Throw '*build.schema.json*'}
    }
    It 'accepts a typed ruling with text evidence' {
        Get-LedgerRulingFault @{applies=$false;rule='catalogue-does-not-use';evidence='Census reviewed.'} $function | Should -BeNullOrEmpty
        Get-LedgerRulingFault @{applies=$true} $function | Should -BeNullOrEmpty
    }
}
Describe 'Check defects found on retest' {
    It 'counts an Admin page under a nested row path as incomplete' {
        {ConvertTo-LedgerRows @{model=@{data=@(1,2);totalCount=500;totalPages=250}} 'model.data'} | Should -Throw '*incomplete*'
        {ConvertTo-LedgerRows @{model=@{data=@(1,2);totalPages=3}} 'model.data'} | Should -Throw '*not complete*'
        (ConvertTo-LedgerRows @{model=@{data=@(1,2);totalCount=2;totalPages=1}} 'model.data').Count | Should -Be 2
        # A row that has a member named count is data, not completeness evidence.
        (ConvertTo-LedgerRows @(@{count=9},@{count=9}) '$').Count | Should -Be 2
    }
    It 'reports no declared family instead of a family without a name' {
        Mock Invoke-Sqlcmd-Rows {@()}
        $row=Invoke-PimFeatureCheck -Check @{id='pim.data-models.families-have-models';kind='families';proves='p'} -Build @{} -Server '.' -Database 'fixture' -FilesPath $null -Stored @{}
        $row.result | Should -Be FAIL
        $row.measured | Should -Be '0 declared, 1 offender(s)'
        @($row.offenders) | Should -Be @('the build file declares 0 family(ies); this check needs 1')
        $row=Invoke-PimFeatureCheck -Check @{id='x';kind='families';proves='p'} -Build @{families=@(@{name='Bikes';category='bikes'})} -Server '.' -Database 'fixture' -FilesPath $null -Stored @{}
        @($row.offenders) | Should -Be @("family 'Bikes' has no data model on category 'bikes'")
    }
    It 'leaves a check UNVERIFIED when its <token> input is not declared' -TestCases @(@{token='{lang}'},@{token='{pimShop}'}) {
        param($token)
        Mock Invoke-Sqlcmd-Scalar {throw 'Unexpected SQL read.'}
        $binding=@{id='s';surface='sql';status='implemented';handler='sql-scalar';localOnly=$true;query="SELECT COUNT(*) FROM T WHERE a = N'$token'"}
        $row=Invoke-LedgerCheck (New-TestCheck $binding) @{} $cap $noProfile @('sql') '.' 'fixture' ''
        $row.result | Should -Be UNVERIFIED
        Should -Invoke Invoke-Sqlcmd-Scalar -Times 0 -Exactly
        (Invoke-LedgerCheck (New-TestCheck $binding) @{defaultLanguage="x';--";pimShop="x';--"} $cap $noProfile @('sql') '.' 'fixture' '').result | Should -Be ERROR
    }
}
Describe 'The runner names why it stopped' {
    BeforeAll {
        $script:runner=Join-Path $PSScriptRoot '../Invoke-DwLedgerChecks.ps1'
        $script:snapshot=Join-Path $TestDrive 'release'
        $null=New-Item -ItemType Directory -Path (Join-Path $snapshot 'functions'),(Join-Path $snapshot 'probes/fx') -Force
        @{schema=1;dwVersion='1.0.0';functionsGlob='functions/*.json';coverageGlob='coverage/*.json'}|ConvertTo-Json|Set-Content (Join-Path $snapshot 'manifest.json')
        $function=@{id='fx.one';area='fx';name='One';skill='dw-demo-ledger';status='candidate';requires=@();inputs=@();checks=@('probes/fx/count.json');notApplicable=@(@{id='catalogue-does-not-use';when='Not used'});sources=@()}
        @{schema=1;area='fx';functions=@($function)}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $snapshot 'functions/fx.json')
        @{schema=1;id='fx.one.count';functionId='fx.one';intent=@{proves='Rows exist';level='configured';scope='all'};assertion=@{kind='scalar';op='ge';value=1};bindings=@(@{id='sql';surface='sql';status='implemented';handler='sql-scalar';localOnly=$true;query='SELECT 1'})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $snapshot 'probes/fx/count.json')
        $repo=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
        $script:lock=@{commit='0'*40;manifest=[IO.Path]::GetRelativePath($repo,(Join-Path $snapshot 'manifest.json')).Replace('\','/');digest=Get-LedgerDigest $snapshot;checkIds=@('fx.one.count')}
        function Invoke-Runner([hashtable]$Lock,[hashtable]$Extra=@{},[string]$Manifest=(Join-Path $snapshot 'manifest.json')){
            $build=@{schema=1;slug='fx';lock=$Lock;functions=@('fx.one')};foreach($key in $Extra.Keys){$build[$key]=$Extra[$key]}
            $file=Join-Path $TestDrive 'build.json';$build|ConvertTo-Json -Depth 10|Set-Content $file
            $script:report=Join-Path $TestDrive 'report.json';Remove-Item $report -ErrorAction SilentlyContinue
            $output=& pwsh -NoProfile -NonInteractive -File $runner -Manifest $Manifest -BuildFile $file -OutFile $report -DiagnosticVersionMismatch 2>&1 | Out-String
            return @{text=$output -replace '\s+',' ';exit=$LASTEXITCODE}
        }
        function Edit-Lock([hashtable]$Change){$copy=$lock.Clone();foreach($key in $Change.Keys){$copy[$key]=$Change[$key]};return $copy}
    }
    It 'names the lock path it expected and the one it was given' {
        $run=Invoke-Runner (Edit-Lock @{manifest='assets/releases/1.0.0/manifest.json'})
        $run.exit | Should -Be 1
        $run.text | Should -Match "lock\.manifest is 'assets/releases/1\.0\.0/manifest\.json' but the selected manifest is '"
        $run.text | Should -Match 'relative to the repository root'
        Test-Path $report | Should -BeFalse
    }
    It 'names a locked check that no function references' {
        $run=Invoke-Runner (Edit-Lock @{checkIds=@('fx.one.count','fx.one.orphan')})
        $run.exit | Should -Be 1
        $run.text | Should -Match "Locked check 'fx\.one\.orphan' is not in the checks list of any function"
    }
    It 'names a digest mismatch, a missing manifest and an unknown function' {
        (Invoke-Runner (Edit-Lock @{digest='sha256:'+'0'*64})).text | Should -Match 'Snapshot digest mismatch: lock\.digest is sha256:0+, the snapshot beside the manifest is sha256:[a-f0-9]{64}'
        (Invoke-Runner $lock @{} (Join-Path $TestDrive 'absent/manifest.json')).text | Should -Match "Manifest '.*absent.manifest\.json' does not exist"
        (Invoke-Runner $lock @{functions=@('fx.one','fx.absent')}).text | Should -Match "Function 'fx\.absent' in build\.functions is not in this snapshot"
    }
    It 'names the build file and schema for evidence that is not text' {
        $run=Invoke-Runner $lock @{rulings=@{'fx.one'=@{applies=$false;rule='catalogue-does-not-use';evidence=@{}}}}
        $run.exit | Should -Be 1
        $run.text | Should -Match "build\.json' does not match build\.schema\.json"
    }
    It 'writes a report that is not a PASS when a ruling is all the run holds' {
        $run=Invoke-Runner $lock @{rulings=@{'fx.one'=@{applies=$false;rule='catalogue-does-not-use';evidence='x'}}}
        $run.exit | Should -Be 1
        $result=Read-LedgerJson $report (Join-Path $assets 'report.schema.json')
        $result.counts.'NOT-APPLICABLE' | Should -Be 1
        $result.counts.PASS | Should -Be 0
        $result.result | Should -Be UNVERIFIED
    }
}

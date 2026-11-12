<#
.SYNOPSIS
WRITES: a temporary fixture checkout of the runner and a loopback stub site; no target, no database.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. New-LedgerFixtureRepo
copies the runner, the schemas and the shared transport into a new git repository under the
given directory, with a small snapshot, and commits it, so the runner can be executed from a
clean checkout of a known commit. Start-LedgerStubSite serves the public descriptor, the
feature enumeration and delivery routes on a free loopback port from state the test changes.
.EXAMPLE
. ./LedgerFixture.ps1
$fx=New-LedgerFixtureRepo -Path $TestDrive/repo -Functions $functions
#>
#Requires -Version 7.0
param()
function New-LedgerFixtureRepo {
    # Functions: @{id; requires; notApplicable; checks=@(@{name; assertion; bindings})}. The area is the id's first segment.
    param([string]$Path,[hashtable[]]$Functions,[string]$Version='1.0.0')
    $source=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $skill=Join-Path $Path 'skills/dw-demo-ledger'
    $null=New-Item -ItemType Directory -Force -Path (Join-Path $skill 'scripts'),(Join-Path $skill 'assets/profiles'),(Join-Path $Path 'skills/dw-data-access/scripts')
    Copy-Item (Join-Path $source 'skills/dw-demo-ledger/scripts/*.ps1') (Join-Path $skill 'scripts')
    Copy-Item (Join-Path $source 'skills/dw-demo-ledger/assets/*.json') (Join-Path $skill 'assets')
    Copy-Item (Join-Path $source 'skills/dw-demo-ledger/assets/profiles/*.json') (Join-Path $skill 'assets/profiles')
    Copy-Item (Join-Path $source 'skills/dw-data-access/scripts/Dw.Api.psm1') (Join-Path $Path 'skills/dw-data-access/scripts')
    $root=Join-Path $skill "assets/releases/$Version"
    $null=New-Item -ItemType Directory -Force -Path (Join-Path $root 'functions')
    Write-LedgerFixtureJson (Join-Path $root 'manifest.json') @{schema=1;dwVersion=$Version;functionsGlob='functions/*.json';coverageGlob='coverage/*.json'}
    $areas=@{}
    foreach($function in $Functions){
        $area=$function.id.Split('.')[0];$paths=@()
        foreach($check in @($function.checks)){
            $relative="probes/$area/$($function.id.Substring($area.Length+1)).$($check.name).json"
            $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $root $relative))
            Write-LedgerFixtureJson (Join-Path $root $relative) @{schema=1;id="$($function.id).$($check.name)";functionId=$function.id
                intent=@{proves='Fixture claim';level='configured';scope='fixture'}
                assertion=$(if($check.assertion){$check.assertion}else{@{kind='scalar';op='ge';value=1}});bindings=@($check.bindings)}
            $paths+=$relative
        }
        if(-not $areas.ContainsKey($area)){$areas[$area]=@()}
        $areas[$area]+=@{id=$function.id;area=$area;name=$function.id;skill='dw-demo-ledger';status='candidate';requires=@($function.requires)
            inputs=@();checks=$paths;notApplicable=@($function.notApplicable);sources=@()}
    }
    foreach($area in $areas.Keys){Write-LedgerFixtureJson (Join-Path $root "functions/$area.json") @{schema=1;area=$area;functions=@($areas[$area])}}
    Save-LedgerFixtureCommit $Path
    . (Join-Path $PSScriptRoot '../Ledger.Core.ps1')
    return @{repo=$Path;runner=Join-Path $skill 'scripts/Invoke-DwLedgerChecks.ps1';relock=Join-Path $skill 'scripts/Update-DwLedgerLock.ps1';root=$root
        manifest=Join-Path $root 'manifest.json';lockManifest="skills/dw-demo-ledger/assets/releases/$Version/manifest.json"
        commit=(& git -C $Path rev-parse HEAD);digest=Get-LedgerDigest $root}
}
function Write-LedgerFixtureJson {
    param([string]$File,$Value)
    [IO.File]::WriteAllText($File,($Value|ConvertTo-Json -Depth 20)+"`n",[Text.UTF8Encoding]::new($false))
}
function Save-LedgerFixtureCommit {
    # Commits everything in the fixture checkout; line endings are kept as written.
    param([string]$Path)
    if(-not(Test-Path (Join-Path $Path '.git'))){$null=& git -C $Path init -q 2>&1;$null=& git -C $Path config core.autocrlf false}
    $null=& git -C $Path add -A 2>&1
    $null=& git -C $Path -c user.name=fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m fixture 2>&1
    if($LASTEXITCODE -ne 0){throw 'Fixture commit failed.'}
}
function Invoke-LedgerFixtureRun {
    # Runs the fixture checkout's runner in its own process, without the caller's DW_* environment.
    # Returns exit code, console text and the parsed report. -BuildFile runs an existing build file as it is.
    param($Fixture,[string[]]$CheckIds,[string[]]$FunctionIds,[hashtable]$Lock=@{},[hashtable]$Build=@{},[hashtable]$Arguments=@{},[string]$WorkDirectory,[string]$BuildFile)
    $report=Join-Path $WorkDirectory 'report.json';Remove-Item $report -ErrorAction SilentlyContinue
    if(-not $BuildFile){
        $locked=@{commit=$Fixture.commit;manifest=$Fixture.lockManifest;digest=$Fixture.digest;checkIds=@($CheckIds)}
        foreach($key in $Lock.Keys){$locked[$key]=$Lock[$key]}
        $declared=@{schema=1;slug='fixture';lock=$locked;functions=@($FunctionIds)};foreach($key in $Build.Keys){$declared[$key]=$Build[$key]}
        $BuildFile=Join-Path $WorkDirectory 'build.json';Write-LedgerFixtureJson $BuildFile $declared
    }
    $parameters=@('-Manifest',$Fixture.manifest,'-BuildFile',$BuildFile,'-OutFile',$report)
    foreach($key in $Arguments.Keys){if($Arguments[$key] -is [bool]){if($Arguments[$key]){$parameters+="-$key"}}elseif($Arguments[$key]){$parameters+="-$key";$parameters+=$Arguments[$key]}}
    $names=@('DW_BASE_URL','DW_API_TOKEN','DW_MCP_TOKEN');$saved=@{}
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,$null)}
    try{
        $text=& pwsh -NoProfile -NonInteractive -File $Fixture.runner @parameters 2>&1 | Out-String
        $exit=$LASTEXITCODE
    }finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}
    $data=if(Test-Path $report){Get-Content -LiteralPath $report -Raw|ConvertFrom-Json -AsHashtable}else{$null}
    return @{exit=$exit;text=$text -replace '\s+',' ';report=$data;buildFile=$BuildFile}
}
function Start-LedgerStubSite {
    # State keys: versions (one per descriptor read, the last repeats), failDescriptor (reads to fail first),
    # features (type name -> active), dwapi (route -> JSON text), status (route -> HTTP status), log (requests seen).
    param([hashtable]$State)
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    $prefix="http://localhost:$port/"
    $listener=[Net.HttpListener]::new();$listener.Prefixes.Add($prefix);$listener.Start()
    $job=Start-ThreadJob -ArgumentList $listener,$State -ScriptBlock {
        param($listener,$state)
        while($listener.IsListening){
            try{$context=$listener.GetContext()}catch{break}
            $path=$context.Request.Url.AbsolutePath;$status=200;$body='{}'
            $null=$state.log.Add($context.Request.HttpMethod+' '+$path+$(if($context.Request.Headers['Authorization']){' +authorization'}))
            if($path -ieq '/admin/api/api.json'){
                $state.descriptorReads++
                if($state.descriptorReads -le $state.failDescriptor){$status=500}
                else{
                    $index=[Math]::Min($state.descriptorReads-$state.failDescriptor,@($state.versions).Count)-1
                    $body=@{info=@{version=@($state.versions)[$index]};paths=@{'/FeaturesAll'=@{get=@{}};'/McpConfigurationAll'=@{get=@{}}}}|ConvertTo-Json -Depth 6
                }
            } elseif($path -ieq '/admin/api/FeaturesAll'){
                $rows=@(foreach($name in $state.features.Keys){@{featureTypeName=$name;active=[bool]$state.features[$name]}})
                $body=@{model=@{data=$rows;totalCount=$rows.Count;totalPages=1}}|ConvertTo-Json -Depth 6
            } elseif($path -like '/dwapi/*'){
                $route=$path.Substring(7)
                if($state.status.ContainsKey($route)){$status=$state.status[$route]}
                elseif($state.dwapi.ContainsKey($route)){$body=$state.dwapi[$route]}
                else{$status=404}
            } elseif($path -ine '/admin/api/McpConfigurationAll'){$status=404}
            $bytes=[Text.Encoding]::UTF8.GetBytes($body)
            $context.Response.StatusCode=$status;$context.Response.ContentType='application/json'
            $context.Response.OutputStream.Write($bytes,0,$bytes.Length);$context.Response.Close()
        }
    }
    return @{url=$prefix.TrimEnd('/');listener=$listener;job=$job}
}
function New-LedgerStubState {
    param([string[]]$Versions=@('1.0.0'),[hashtable]$Features=@{},[hashtable]$Dwapi=@{},[hashtable]$Status=@{},[int]$FailDescriptor=0)
    return [hashtable]::Synchronized(@{versions=$Versions;features=$Features;dwapi=$Dwapi;status=$Status;failDescriptor=$FailDescriptor;descriptorReads=0;log=[Collections.ArrayList]::Synchronized([Collections.ArrayList]::new())})
}
function Stop-LedgerStubSite {
    param($Site)
    try{$Site.listener.Stop();$Site.listener.Close()}catch{}
    $Site.job|Remove-Job -Force -ErrorAction SilentlyContinue
}

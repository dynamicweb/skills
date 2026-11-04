BeforeAll {
    $repo=Split-Path $PSScriptRoot
    $script:module=Join-Path $repo 'skills/dw-demo-base/scripts/Dw.DemoBuild.psm1'
    $script:orchestrator=Join-Path $repo 'skills/dw-demo-base/scripts/Invoke-DwDemoBaseBuild.ps1'
    Import-Module $script:module -Force
    function New-TestConfig {
        param([hashtable]$Value)
        $file=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.json')
        $Value|ConvertTo-Json -Depth 20|Set-Content $file -Encoding utf8NoBOM
        $file
    }
}

Describe 'Scripted base build config and helpers' {
    It 'bounds a stalled native command and stops only its child tree' {
        {Invoke-DwBuildCommand pwsh @('-NoProfile','-Command','Start-Sleep -Seconds 15') -TimeoutSeconds 1}|Should -Throw '*exceeded*'
    }
    It 'passes native arguments without a shell, preserving spaces and metacharacters' {
        $probe=Join-Path $TestDrive 'argument probe.ps1'
        'param([string]$Value) if($Value -ne ''literal $() & with spaces''){exit 1}'|Set-Content $probe
        {Invoke-DwBuildCommand pwsh @('-NoProfile','-File',$probe,'-Value','literal $() & with spaces')}|Should -Not -Throw
    }
    It 'captures stdout while streaming diagnostics separately' {
        $captured=Invoke-DwBuildCommand pwsh @('-NoProfile','-Command','[Console]::Out.WriteLine("one"); [Console]::Error.WriteLine("diagnostic"); [Console]::Out.WriteLine("two")') -CaptureOutput
        $captured|Should -Be "one`ntwo"
    }
    It 'hashes only the key secret with the platform salt and preserves the prefix' {
        $value='x'*32
        $hash=Get-DwBuildTokenHash ('DEMO.'+$value)
        $digest=[Convert]::ToHexString([Security.Cryptography.SHA512]::HashData([Text.Encoding]::UTF8.GetBytes($value+'DwSecret'))).ToLowerInvariant()
        $hash|Should -Be ('DEMO.'+$digest)
        (Get-DwBuildTokenHash ('OTHER.'+$value))|Should -Be ('OTHER.'+$digest)
        {Get-DwBuildTokenHash 'no-prefix'}|Should -Throw '*format*'
    }
    It 'accepts the minimal customer config' {
        $file=New-TestConfig @{slug='marine';customer=@{name='Marine Supply'}}
        (Read-DwBuildConfig $file).edition|Should -Be 'swift-demo'
        (Read-DwBuildConfig $file).installMcpBeforeStart|Should -BeTrue
    }
    It 'rejects unknown keys' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};typo=$true})}|Should -Throw '*Unknown*'
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply';tagline='x'}})}|Should -Throw '*Unknown*customer.tagline*'
    }
    It 'refuses branding blocks and points at dw-demo-swift' {
        foreach($block in @(@{brand=@{primary='#000000'}},@{storefront=@{}},@{personas=@()},@{catalogue=@{}})){
            $value=@{slug='marine';customer=@{name='Supply'}}+$block
            {Read-DwBuildConfig (New-TestConfig $value)}|Should -Throw '*dw-demo-swift*'
        }
    }
    It 'rejects unsupported localization instead of pretending to apply it' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply';currency='EUR'}})}|Should -Throw '*localization*'
    }
    It 'ships a minimal example config that resolves' {
        $example=Read-DwBuildConfig (Join-Path (Split-Path $PSScriptRoot) 'skills/dw-demo-base/assets/demo-build.example.json')
        $example.customer.name|Should -Be 'Truvio Commerce'
        @($example.Keys|Sort-Object)|Should -Be @('customer','edition','installMcpBeforeStart','slug')
    }
    It 'ships no branding helpers' {
        foreach($name in 'Get-DwBuildInk','Get-DwBuildRenamePlan','New-DwBuildTile','Test-DwBuildVendorKept','Test-DwBuildTypographyCss','Resolve-DwBuildAsset'){
            Get-Command $name -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
        }
    }
    It 'plans the scaffold steps with key minting before first start and no brand step' {
        $config=New-TestConfig @{slug='marine';customer=@{name='Marine Supply'}}
        $plan=& pwsh -NoProfile -File $script:orchestrator -ConfigPath $config -DemoRoot (Join-Path $TestDrive 'plan') -SqlServer localhost -Port 44471 6>&1
        $LASTEXITCODE|Should -Be 0
        $steps=@($plan|ForEach-Object {"$_"}|Where-Object {$_ -like 'Plan: *'}|ForEach-Object {$_.Substring(6)})
        $steps|Should -Be @('preflight','release','scaffold','restore','files','access-keys','start-license','access','index','test','stamps')
        ($plan -join "`n")|Should -Match 'dw-demo-swift'
        Test-Path (Join-Path $TestDrive 'plan')|Should -BeFalse
    }
}

Describe 'Offline edition file composition on Windows' -Skip:(-not $IsWindows) {
    It 'verifies the public app archive, stages only AddIns and preserves overlay order' {
        $demo=Join-Path $TestDrive 'files-fixture';$hostDir=Join-Path $demo 'Dynamicweb.Host.Suite'
        $dist=Join-Path $demo 'distribution';$notes=Join-Path $demo 'notes';$cache=Join-Path $demo 'cache'
        foreach($dir in $notes,(Join-Path $hostDir 'obj'),(Join-Path $dist 'layers/base')){New-Item -ItemType Directory -Force $dir|Out-Null}
        $archiveRoot=Join-Path $TestDrive 'archive-source';New-Item -ItemType Directory -Force (Join-Path $archiveRoot 'Files')|Out-Null
        '<Globalsettings><System><Security><EncryptPassword>0</EncryptPassword></Security></System></Globalsettings>'|Set-Content (Join-Path $archiveRoot 'Files/GlobalSettings.config')
        $zip=Join-Path $notes 'fixture.zip';[IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot,$zip)
        $contract=@{deliveryTarget=@{hostFiles=@{swiftRelease=@{tag='fixture';asset='fixture.zip';url='https://github.com/dynamicweb/Swift/releases/download/fixture/fixture.zip';sha256=(Get-FileHash $zip).Hash};globalSettings=@{required=@(@{path='/Globalsettings/Ecom/Assortments/UseAssortments';value='True'})}}}}
        Write-DwBuildJson (Join-Path $dist 'layers/base/base.contract.json') $contract
        foreach($layer in 'base','surface-fixture','theme-default'){
            $folder=Join-Path $dist "layers/$layer/files";New-Item -ItemType Directory -Force $folder|Out-Null
            $layer|Set-Content (Join-Path $folder 'overlay.txt')
        }
        New-Item -ItemType Directory -Force (Join-Path $dist 'layers/surface-fixture/itemtypes'),(Join-Path $dist 'layers/surface-fixture/repositories/Fixture')|Out-Null
        '<ItemType/>'|Set-Content (Join-Path $dist 'layers/surface-fixture/itemtypes/ItemType_Fixture.xml')
        '<Query/>'|Set-Content (Join-Path $dist 'layers/surface-fixture/repositories/Fixture/Fixture.query')
        $packageSource=Join-Path $TestDrive 'package-source'
        $payload=Join-Path $packageSource 'Files/System/AddIns/Installed/Truvio.Commerce.MCP.Host/lib/net10.0'
        New-Item -ItemType Directory -Force $payload,(Join-Path $packageSource 'lib/net10.0')|Out-Null
        'host assembly fixture'|Set-Content (Join-Path $payload 'Truvio.Commerce.MCP.Host.dll')
        'tool assembly fixture'|Set-Content (Join-Path $packageSource 'lib/net10.0/Truvio.Commerce.MCP.dll')
        $cache=Join-Path $notes 'tools/truvio.commerce.mcp.0.0.0-fixture'
        New-Item -ItemType Directory -Force $cache|Out-Null
        $package=Join-Path $cache 'truvio.commerce.mcp.0.0.0-fixture.nupkg'
        [IO.Compression.ZipFile]::CreateFromDirectory($packageSource,$package)
        $stream=[IO.File]::OpenRead($package)
        try{$hash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::HashData($stream))}finally{$stream.Dispose()}
        Write-DwBuildJson (Join-Path $cache 'catalog.json') @{id='Truvio.Commerce.MCP';version='0.0.0-fixture';packageHash=$hash;packageHashAlgorithm='SHA512'}
        Write-DwBuildJson (Join-Path $notes 'distribution-release.json') @{swiftTag='fixture';apps=@(@{id='Truvio.Commerce.MCP';version='0.0.0-fixture'});editionModel=@{from='base@fixture';add=@();surfaces=@('surface-fixture@fixture');sampleData=$false;themes=@('default')}}
        $installer=Join-Path $repo 'skills/dw-demo-base/scripts/Install-DwDemoFiles.ps1'
        & pwsh -NoProfile -File $installer -DemoRoot $demo -SqlServer localhost -Database fixture-db -Apply
        $LASTEXITCODE|Should -Be 0
        $files=Join-Path $hostDir 'wwwroot/Files'
        (Get-Content (Join-Path $files 'overlay.txt'))|Should -Be 'theme-default'
        Test-Path (Join-Path $files 'System/AddIns/Installed/Truvio.Commerce.MCP.Host/lib/net10.0/Truvio.Commerce.MCP.Host.dll')|Should -BeTrue
        Test-Path (Join-Path $files 'System/AddIns/Installed/Truvio.Commerce.MCP.0.0.0-fixture/lib/net10.0/Truvio.Commerce.MCP.dll')|Should -BeTrue
        Test-Path (Join-Path $files 'System/Items/ItemType_Fixture.xml')|Should -BeTrue
        Test-Path (Join-Path $files 'System/Repositories/Fixture/Fixture.query')|Should -BeTrue
        [xml]$settings=Get-Content -Raw (Join-Path $files 'GlobalSettings.config')
        $settings.Globalsettings.Ecom.Assortments.UseAssortments|Should -Be 'True'
        $settings.Globalsettings.System.Security.EncryptPassword|Should -Be '1'
        $priorUser=$env:DW_SQL_USER;$priorPassword=$env:DW_SQL_PASSWORD
        try {
            $env:DW_SQL_USER='fixture-user';$env:DW_SQL_PASSWORD='fixture<&value'
            & pwsh -NoProfile -File $installer -DemoRoot $demo -SqlServer localhost -Database fixture-db -Apply
            $LASTEXITCODE|Should -Be 0
            [xml]$databaseSettings=Get-Content -Raw (Join-Path $files 'GlobalSettings.Database.config')
            $databaseSettings.Globalsettings.System.Database.IntegratedSecurity|Should -Be 'False'
            $databaseSettings.Globalsettings.System.Database.UserName|Should -Be $env:DW_SQL_USER
            $databaseSettings.Globalsettings.System.Database.Password|Should -Be $env:DW_SQL_PASSWORD
        } finally { $env:DW_SQL_USER=$priorUser;$env:DW_SQL_PASSWORD=$priorPassword }
        $bin=Join-Path $hostDir 'bin/Debug/net10.0'
        New-Item -ItemType Directory -Force $bin|Out-Null
        'duplicate fixture'|Set-Content (Join-Path $bin 'Truvio.Commerce.MCP.dll')
        & pwsh -NoProfile -File $installer -DemoRoot $demo -SqlServer localhost -Database fixture-db -Apply 2>$null
        $LASTEXITCODE|Should -Be 1
        Move-Item -LiteralPath (Join-Path $bin 'Truvio.Commerce.MCP.dll') -Destination (Join-Path $TestDrive 'duplicate.dll')
        'tampered'|Add-Content $package
        & pwsh -NoProfile -File $installer -DemoRoot $demo -SqlServer localhost -Database fixture-db -Apply 2>$null
        $LASTEXITCODE|Should -Be 1
    }
}

Describe 'Owned scaffold patches without an SDK or network' {
    It 'pins Suite only, excludes runtime files and adds guardrails' {
        $demo=Join-Path $TestDrive 'scaffold'
        $suite=Join-Path $demo 'Dynamicweb.Host.Suite'
        New-Item -ItemType Directory -Force (Join-Path $suite 'Properties'),(Join-Path $demo 'notes')|Out-Null
        '<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFrameworks>net8.0;net10.0</TargetFrameworks></PropertyGroup><ItemGroup><PackageReference Include="Dynamicweb.Suite" Version="10.*" /></ItemGroup></Project>'|Set-Content (Join-Path $suite 'Dynamicweb.Host.Suite.csproj')
        'var builder = WebApplication.CreateBuilder(args);'|Set-Content (Join-Path $suite 'Program.cs')
        @{}|ConvertTo-Json|Set-Content (Join-Path $demo 'notes/scaffold-owned.json')
        @{dwVersion='10.0.0-fixture';apps=@(@{id='Truvio.Commerce.MCP';version='0.0.0-fixture'},@{id='Truvio.Commerce.MCP.Host';version='0.0.0-fixture'})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $demo 'notes/distribution-release.json')
        $config=New-TestConfig @{slug='marine';customer=@{name='Marine Supply'};installMcpBeforeStart=$true}
        $script=Join-Path $repo 'skills/dw-demo-base/scripts/New-DwDemoHost.ps1'
        & pwsh -NoProfile -File $script -ConfigPath $config -DemoRoot $demo -Port 44471 -Apply -SkipPackageRestore
        $LASTEXITCODE|Should -Be 0
        [xml]$project=Get-Content -Raw (Join-Path $suite 'Dynamicweb.Host.Suite.csproj')
        $project.Project.PropertyGroup.TargetFramework|Should -Be 'net10.0'
        $project.SelectNodes('//TargetFrameworks').Count|Should -Be 0
        $project.SelectSingleNode('//PackageReference[@Include="Dynamicweb.Suite"]').Version|Should -Be '10.0.0-fixture'
        $project.SelectNodes('//PackageReference[@Include="Truvio.Commerce.MCP"]').Count|Should -Be 0
        $project.SelectNodes('//PackageReference[@Include="Truvio.Commerce.MCP.Host"]').Count|Should -Be 0
        $project.SelectNodes('//TruvioMcpSdkReferences').Count|Should -Be 0
        $project.SelectNodes('//Content[@Remove="wwwroot/Files/System/**"]').Count|Should -Be 1
        Get-Content -Raw (Join-Path $suite 'Program.cs')|Should -Match 'ImplicitDistributedTransactions = true'
        Get-Content -Raw (Join-Path $demo 'CLAUDE.md')|Should -Match 'read-only'
        Get-Content (Join-Path $demo '.gitignore')|Should -Contain '.mcp.json'
    }
}

BeforeAll {
    $repo=Split-Path $PSScriptRoot
    $script:module=Join-Path $repo 'skills/dw-demo-base/scripts/Dw.DemoBuild.psm1'
    $script:generator=Join-Path $repo 'skills/dw-demo-base/scripts/New-DwBrandFiles.ps1'
    Import-Module $script:module -Force
    function New-TestConfig {
        param([hashtable]$Value)
        $file=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.json')
        $Value|ConvertTo-Json -Depth 20|Set-Content $file -Encoding utf8NoBOM
        $file
    }
}

Describe 'Scripted build config and rename planning' {
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
    It 'rejects unknown keys and unsafe CSS' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};typo=$true})}|Should -Throw '*Unknown*'
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};brand=@{primary='red;display:none'}})}|Should -Throw '*hex*'
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};brand=@{schemes=@{typo=@{BackgroundColor='#FFFFFF'}}}})}|Should -Throw '*scheme id*'
    }
    It 'rejects unsupported localization instead of pretending to apply it' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply';currency='EUR'}})}|Should -Throw '*localization*'
    }
    It 'refuses assets escaping the demo root' {
        {Resolve-DwBuildAsset $TestDrive '../secret.svg'}|Should -Throw '*escapes*'
    }
    It 'binds hostile product text as a value and preserves the stable id' {
        $value="O'Brien'); DROP TABLE Area;--"
        $c=Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};catalogue=@{products=@(@{id='TCPROD0001';name=$value})}})
        $plan=Get-DwBuildRenamePlan $c
        $plan.Count|Should -Be 1
        $plan[0].sql|Should -Not -Match 'DROP TABLE'
        $plan[0].parameters.value|Should -Be $value
        $plan[0].parameters.id|Should -Be 'TCPROD0001'
        $plan[0].sql|Should -Match "ProductVariantId=''"
    }
    It 'rejects keys outside the stable catalogue families' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};catalogue=@{groups=@(@{id='SHOP1';name='Wrong'})}})}|Should -Throw '*stable key*'
    }
    It 'targets category label translations, never nonexistent schema columns' {
        $c=Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};catalogue=@{categoryFields=@(@{id='tcMaterialClass';label='Marine material'})}})
        $plan=Get-DwBuildRenamePlan $c
        $plan[0].table|Should -Be 'EcomProductCategoryFieldTranslation'
        $plan[0].column|Should -Be 'FieldTranslationFieldLabel'
        $plan[0].sql|Should -Match "FieldTranslationLanguageId='ENU'"
    }
    It 'rejects negative prices before a build can mutate anything' {
        {Read-DwBuildConfig (New-TestConfig @{slug='marine';customer=@{name='Supply'};catalogue=@{products=@(@{id='TCPROD0001';price=-1})}})}|Should -Throw '*non-negative*'
    }
    It 'keeps the vendor brand only for a customer name that carries the vendor word' {
        Test-DwBuildVendorKept 'Truvio Commerce'|Should -BeTrue
        Test-DwBuildVendorKept 'truvio'|Should -BeTrue
        Test-DwBuildVendorKept 'Northwind Marine Supply'|Should -BeFalse
        Test-DwBuildVendorKept 'Truvioline Parts'|Should -BeFalse
    }
    It 'ships an example config that keeps the edition brand and resolves' {
        $example=Read-DwBuildConfig (Join-Path (Split-Path $PSScriptRoot) 'skills/dw-demo-base/assets/demo-build.example.json')
        $example.customer.name|Should -Be 'Truvio Commerce'
        Test-DwBuildVendorKept $example.customer.name|Should -BeTrue
        $example.brand.logo|Should -Match '^distribution/layers/sample-data/files/Images/TruvioCommerce/brand/.+\.svg$'
        [int]$example.personas.Count|Should -Be 0
        [int]$example.catalogue.products.Count|Should -Be 0
    }
    It 'chooses readable ink on amber and dark blue' {
        Get-DwBuildInk '#B8860B'|Should -Be '#000000'
        Get-DwBuildInk '#15324F'|Should -Be '#FFFFFF'
    }
}

Describe 'Brand generation without network or database' -Skip:(-not $IsWindows) {
    BeforeAll {
        $script:demo=Join-Path $TestDrive 'demo'
        $theme=Join-Path $script:demo 'distribution/layers/theme-default/files'
        $custom=Join-Path $theme 'Templates/Designs/Swift-v2/Custom'
        New-Item -ItemType Directory -Force $custom|Out-Null
        $seed=@{brand=@{name='Default';logo=@{alt='Default'}};css=@{'--td-accent'='#000000';'--td-ink'='#000000'};schemes=@('light','lightgrey1','lightgrey2','dark','darksubtle','primary','secondary'|ForEach-Object {@{Id=$_;Name=$_;BackgroundColor='#FFFFFF';ForegroundColor='#000000';PrimaryButtonColor='#000000';SecondaryButtonColor='#000000';AccentColor=$null}});typography=@{ParagraphFont='Inter';HeadingFont='Inter';ButtonFont='Inter';fontImport=$null};buttons=@{Shape=2;BorderSize=1;PaddingY=0.55;PaddingX=1.4;borderRadius='999px'}}
        $seed|ConvertTo-Json -Depth 20|Set-Content (Join-Path $custom 'brand.tokens.json')
        New-Item -ItemType Directory -Force (Join-Path $theme 'System/Styles/Typography')|Out-Null
        "/* default */`n/* Imports */`n@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');`n/* Basic types */`nbody, .preview {`n--dw-font-family: Inter;`n}`n/* Headings */`nh1, h2 {`n--dw-font-family: Inter;`n}"|Set-Content (Join-Path $theme 'System/Styles/Typography/default.css')
        $files=Join-Path $script:demo 'Dynamicweb.Host.Suite/wwwroot/Files'
        foreach($dir in 'ColorSchemes','Typography','Buttons'){New-Item -ItemType Directory -Force (Join-Path $files "System/Styles/$dir")|Out-Null}
        New-Item -ItemType Directory -Force (Join-Path $files 'Templates/Designs/Swift-v2/Custom')|Out-Null
        $script:config=New-TestConfig @{slug='marine';customer=@{name='Marine & Supply'};brand=@{primary='#B8860B';radius='12px'}}
    }
    It 'writes both halves of all pairs, fixed scheme ids, tokens and escaped logo' {
        & pwsh -NoProfile -File $script:generator -ConfigPath $script:config -DemoRoot $script:demo -Apply
        $LASTEXITCODE|Should -Be 0
        $files=Join-Path $script:demo 'Dynamicweb.Host.Suite/wwwroot/Files'
        foreach($dir in 'ColorSchemes','Typography','Buttons'){
            Test-Path (Join-Path $files "System/Styles/$dir/default.json")|Should -BeTrue
            Test-Path (Join-Path $files "System/Styles/$dir/default.css")|Should -BeTrue
        }
        $model=Get-Content -Raw (Join-Path $files 'System/Styles/ColorSchemes/default.json')|ConvertFrom-Json
        $model.Schemes.Count|Should -Be 7
        $model.Schemes.Id|Should -Contain 'darksubtle'
        $css=Get-Content -Raw (Join-Path $files 'System/Styles/ColorSchemes/default.css')
        $css|Should -Match '--dw-color-button-primary-contrast: #000000;'
        Get-Content -Raw (Join-Path $files 'Templates/Designs/Swift-v2/Custom/brand.css')|Should -Match ':root:root'
        $typography=Get-Content -Raw (Join-Path $files 'System/Styles/Typography/default.css')
        $typography|Should -Not -Match '@import|display=swap'
        $typography|Should -Match '(?s)body, \.preview \{[^}]*--dw-font-family: Arial;'
        Get-Content -Raw (Join-Path $files 'Images/Brand/logo.svg')|Should -Match 'Marine &amp; Supply'
        $tokens=Get-Content -Raw (Join-Path $files 'Templates/Designs/Swift-v2/Custom/brand.tokens.json')|ConvertFrom-Json
        $tokens.brand.favicon|Should -Be '/Files/Images/marine/favicon.png'
        [IO.File]::ReadAllBytes((Join-Path $files 'Images/marine/favicon.png'))[0]|Should -Be 137
        $first=Get-FileHash (Join-Path $files 'System/Styles/ColorSchemes/default.css')
        & pwsh -NoProfile -File $script:generator -ConfigPath $script:config -DemoRoot $script:demo -Apply
        (Get-FileHash $first.Path).Hash|Should -Be $first.Hash
    }
    It 'keeps a configured font import as the first line and still parses' {
        $root=Join-Path $TestDrive 'imported'
        Copy-Item (Join-Path $script:demo 'distribution') (Join-Path $root 'distribution') -Recurse
        foreach($dir in 'System/Styles/ColorSchemes','System/Styles/Typography','System/Styles/Buttons','Templates/Designs/Swift-v2/Custom'){New-Item -ItemType Directory -Force (Join-Path $root "Dynamicweb.Host.Suite/wwwroot/Files/$dir")|Out-Null}
        $config=New-TestConfig @{slug='marine';customer=@{name='Marine'};brand=@{fontFamily='Source Sans 3';fontImportUrl='https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600&display=swap'}}
        & pwsh -NoProfile -File $script:generator -ConfigPath $config -DemoRoot $root -Apply
        $LASTEXITCODE|Should -Be 0
        $lines=Get-Content (Join-Path $root 'Dynamicweb.Host.Suite/wwwroot/Files/System/Styles/Typography/default.css')
        $lines[0]|Should -Be "@import url('https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600&display=swap');"
        ($lines -join "`n")|Should -Match '(?s)body, \.preview \{[^}]*--dw-font-family: Source Sans 3;'
        { Test-DwBuildTypographyCss -Css ($lines -join "`n") -Font 'Source Sans 3' }|Should -Not -Throw
    }
    It 'rejects a typography sheet with a leftover import fragment or no body font' {
        { Test-DwBuildTypographyCss -Css "500;600;700&display=swap');`nbody, .preview {`n--dw-font-family: Arial;`n}" -Font 'Arial' }|Should -Throw '*outside a rule*'
        { Test-DwBuildTypographyCss -Css "h1 {`n--dw-font-family: Arial;`n}" -Font 'Arial' }|Should -Throw '*body font*'
    }
    It 'does not write when previewed' {
        $newRoot=Join-Path $TestDrive 'preview'
        New-Item -ItemType Directory -Force (Join-Path $newRoot 'distribution/layers/theme-default/files/Templates/Designs/Swift-v2/Custom')|Out-Null
        Copy-Item (Join-Path $script:demo 'distribution/layers/theme-default/files/Templates/Designs/Swift-v2/Custom/brand.tokens.json') (Join-Path $newRoot 'distribution/layers/theme-default/files/Templates/Designs/Swift-v2/Custom/brand.tokens.json')
        & pwsh -NoProfile -File $script:generator -ConfigPath $script:config -DemoRoot $newRoot -WhatIf
        $LASTEXITCODE|Should -Be 0
        Test-Path (Join-Path $newRoot 'Dynamicweb.Host.Suite')|Should -BeFalse
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

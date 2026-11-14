<#
.SYNOPSIS
READ-ONLY. Green and red controls for files-facet-analyzed, files-query-constant-macros and dwapi-persona-sign-in.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. Fixture Files trees under
TestDrive and mocked delivery responses; no network, no target, no database.
.EXAMPLE
Invoke-Pester -Path scripts/tests/Handlers.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeAll {
    foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Repositories.ps1','Ledger.Sql.ps1','Ledger.Transport.ps1','Ledger.Facts.ps1','Ledger.Execute.ps1')){. (Join-Path $PSScriptRoot "../$file")}
    $script:assets=Join-Path $PSScriptRoot '../../assets'
    $script:release=Join-Path $assets 'releases/10.30.6'
    function Get-Probe([string]$Relative){Read-LedgerJson (Join-Path $release "probes/$Relative") (Join-Path $assets 'check.schema.json')}
    function Get-Implemented($Probe){@($Probe.bindings|Where-Object {$_.status -eq 'implemented'})[0]}
    function New-FileCapabilities{@{dwVersion='10.30.6';mcp=@{available=$false;tools=@()};adminApi=@{available=$false;authenticated=$false;queries=@()};dwapi=@{available=$true};file=@{available=$true;local=$true};sql=@{available=$false};facts=@{};errors=@()}}
    function Invoke-Probe($Probe,[string]$Files,[string[]]$Surfaces=@('file')){Invoke-LedgerCheck $Probe @{} (New-FileCapabilities) @{expectations=@{}} $Surfaces '' '' $Files}
    function Write-Xml([string]$Path,[string]$Text){$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path);[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
    function New-Repository([string]$Files,[string]$Name,[string]$Facets,[string]$IndexFields,[string]$Extender='Dynamicweb.Ecommerce.Indexing.ProductIndexSchemaExtender, Dynamicweb.Ecommerce'){
        $dir="$Files/System/Repositories/$Name"
        Write-Xml "$dir/Products.facets" "<Facets Name=`"Products.facets`"><Source Repository=`"$Name`" Item=`"Products.query`" />$Facets</Facets>"
        Write-Xml "$dir/Products.query" "<Query Name=`"Products.query`"><Source Repository=`"$Name`" Item=`"Products.index`" Type=`"Dynamicweb.Indexing.Queries.IndexQueryProvider, Dynamicweb.Core`" /><Expressions /></Query>"
        Write-Xml "$dir/Products.index" "<Index Name=`"Products.index`"><Schema><Fields><Extension Type=`"$Extender`" Analyzed=`"false`" />$IndexFields</Fields></Schema></Index>"
    }
    function Set-DefaultFields([string]$Files,[string]$Value){
        Write-Xml "$Files/GlobalSettings.Ecom.config" "<Globalsettings><Ecom><Indexing><DoNotAnalyzeDefaultFields>$Value</DoNotAnalyzeDefaultFields></Indexing></Ecom></Globalsettings>"
    }
}
Describe 'files-facet-analyzed reads the Analyzed flag of every facet field' {
    BeforeAll {$script:probe=Get-Probe 'search/facets.not-analyzed.json'}
    BeforeEach {
        $script:files=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Set-DefaultFields $files 'False'
    }
    It 'is implemented on the file surface, scoped to the repository facets, and allowlisted' {
        $binding=Get-Implemented $probe
        $binding.handler | Should -Be 'files-facet-analyzed'
        $binding.path | Should -Be 'System/Repositories/*/*.facets'
        (Read-LedgerJson (Join-Path $assets 'handlers.json')).handlers['files-facet-analyzed'].assertions | Should -Be @('offenders')
    }
    It 'PASSes declared non-analysed fields, a grouping and a generated field the extender writes unanalysed' {
        New-Repository $files 'Headless' '<Facet Name="M" Field="Manufacturer_Facet" /><Facet Name="G" Field="ParentGroupIDs" /><Facet Name="P" Field="PriceRange" /><Facet Name="V" Field="VariantGroup_VARGRP1" />' '<Field SystemName="Manufacturer_Facet" Analyzed="false" /><Grouping SystemName="PriceRange" Analyzed="false" />'
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be PASS
        $row.scanned | Should -Be 4
        $row.binding | Should -Be 'files-repositories-facet-analyzed'
    }
    It 'RED CONTROL: a facet on a declared analysed field FAILs and names it' {
        New-Repository $files 'Headless' '<Facet Name="Name" Field="ProductName_Search" />' '<Field SystemName="ProductName_Search" Analyzed="true" />'
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.offenders[0].field | Should -Be 'ProductName_Search'
        $row.offenders[0].facets | Should -Be 'System/Repositories/Headless/Products.facets'
        $row.offenders[0].reason | Should -Match 'Analyzed="true"'
    }
    It 'RED CONTROL: a field neither declared nor generated is an offender, not skipped (a typo never passes)' {
        New-Repository $files 'Headless' '<Facet Name="G" Field="ParentGroupIds" />' ''
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.offenders[0].reason | Should -Match 'Analyzed flag is unknown'
    }
    It 'RED CONTROL: a declaration without an explicit Analyzed flag is an offender' {
        New-Repository $files 'Headless' '<Facet Name="M" Field="Manufacturer_Facet" />' '<Field SystemName="Manufacturer_Facet" />'
        (Invoke-Probe $probe $files).result | Should -Be FAIL
    }
    It 'RED CONTROL: a generated default field is analysed while DoNotAnalyzeDefaultFields is false, and not when it is true' {
        New-Repository $files 'Headless' '<Facet Name="Brand" Field="ManufacturerName" />' ''
        (Invoke-Probe $probe $files).result | Should -Be FAIL
        Set-DefaultFields $files 'True'
        (Invoke-Probe $probe $files).result | Should -Be PASS
    }
    It 'RED CONTROL: an unstated DoNotAnalyzeDefaultFields is not assumed' {
        Remove-Item "$files/GlobalSettings.Ecom.config"
        New-Repository $files 'Headless' '<Facet Name="Brand" Field="ManufacturerName" />' ''
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.offenders[0].reason | Should -Match 'no GlobalSettings layer states'
    }
    It 'RED CONTROL: a category field is an offender unless DoNotAnalyzeDefaultFields is true' {
        New-Repository $files 'Swift' '<Facet Name="Bike" Field="ProductCategory|Reference_Bike|Bike_type" />' ''
        (Invoke-Probe $probe $files).result | Should -Be FAIL
        Set-DefaultFields $files 'True'
        (Invoke-Probe $probe $files).result | Should -Be PASS
    }
    It 'RED CONTROL: a generated field resolves only through the extender the index declares' {
        New-Repository $files 'Content' '<Facet Name="G" Field="ParentGroupIDs" />' '' 'Dynamicweb.Content.ContentIndexSchemaExtender, Dynamicweb'
        (Invoke-Probe $probe $files).result | Should -Be FAIL
    }
    It 'RED CONTROL: a facet whose source query does not resolve is an offender' {
        New-Repository $files 'Headless' '<Facet Name="M" Field="Manufacturer_Facet" />' '<Field SystemName="Manufacturer_Facet" Analyzed="false" />'
        Remove-Item "$files/System/Repositories/Headless/Products.query"
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.offenders[0].reason | Should -Match 'source query'
    }
    It 'RED CONTROL: a facets source that climbs out of the repository folder never resolves' {
        New-Repository $files 'Headless' '<Facet Name="M" Field="Manufacturer_Facet" />' '<Field SystemName="Manufacturer_Facet" Analyzed="false" />'
        $path="$files/System/Repositories/Headless/Products.facets"
        (Get-Content -LiteralPath $path -Raw).Replace('Item="Products.query"','Item="../Headless/Products.query"')|Set-Content -LiteralPath $path
        (Invoke-Probe $probe $files).result | Should -Be FAIL
    }
    It 'RED CONTROL: no facets file is FAIL, below minimumSubjects, never PASS' {
        $null=New-Item -ItemType Directory -Force -Path "$files/System/Repositories/Empty"
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.reason | Should -Match 'below the minimum'
    }
    It 'RED CONTROL: without a Files root the check is UNVERIFIED' {
        $row=Invoke-LedgerCheck $probe @{} ((New-FileCapabilities)+@{}) @{expectations=@{}} @('file') '' '' (Join-Path $TestDrive 'absent')
        $row.result | Should -Be UNVERIFIED
    }
    It 'RED CONTROL: an XML DTD is refused' {
        New-Repository $files 'Headless' '<Facet Name="M" Field="Manufacturer_Facet" />' '<Field SystemName="Manufacturer_Facet" Analyzed="false" />'
        Write-Xml "$files/System/Repositories/Headless/Products.facets" '<!DOCTYPE Facets [<!ENTITY ex SYSTEM "file:///not-read">]><Facets>&ex;</Facets>'
        (Invoke-Probe $probe $files).result | Should -Be ERROR
    }
}
Describe 'files-query-constant-macros reports macro-shaped constants' {
    BeforeAll {$script:probe=Get-Probe 'search/index-queries.no-constant-macros.json'}
    BeforeEach {$script:files=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))}
    It 'PASSes constants that are literals and macros stored as macros' {
        Write-Xml "$files/System/Repositories/A/Products.query" '<Query><Expressions><GroupExpression><BinaryExpression><Right><ConstantExpression Value="True" Type="System.Boolean" /></Right></BinaryExpression><BinaryExpression><Right><MacroExpression Lookup="Dynamicweb.Ecommerce.Context:ShopID" /></Right></BinaryExpression><BinaryExpression><Right><ConstantExpression Value="http://x:80" /></Right></BinaryExpression></GroupExpression></Expressions></Query>'
        Write-Xml "$files/System/Repositories/B/Other.query" '<Query><Expressions /></Query>'
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be PASS
        $row.scanned | Should -Be 2
        $row.binding | Should -Be 'files-repositories-query-constant-macros'
    }
    It 'RED CONTROL: a macro stored as a constant FAILs and names the query and value' {
        Write-Xml "$files/System/Repositories/A/Products.query" '<Query><Expressions><ConstantExpression Value="Dynamicweb.UserManagement.Context:AssortmentIDs" Type="System.String" /></Expressions></Query>'
        $row=Invoke-Probe $probe $files
        $row.result | Should -Be FAIL
        $row.offenders[0].query | Should -Be 'System/Repositories/A/Products.query'
        $row.offenders[0].value | Should -Be 'Dynamicweb.UserManagement.Context:AssortmentIDs'
    }
    It 'RED CONTROL: no query file is FAIL, never PASS' {
        $null=New-Item -ItemType Directory -Force -Path "$files/System/Repositories/A"
        (Invoke-Probe $probe $files).result | Should -Be FAIL
    }
}
Describe 'dwapi-persona-sign-in signs each persona in and reads as that user' {
    BeforeAll {
        $script:probe=Get-Probe 'users/frontend-sign-in.persona-signs-in.json'
        function New-Response([int]$Status,$Body){return @{StatusCode=$Status;Content=$(if($null -eq $Body){''}else{$Body|ConvertTo-Json -Depth 10 -Compress})}}
        function Invoke-SignIn{Invoke-LedgerCheck $probe @{} (New-FileCapabilities) @{expectations=@{}} @('dwapi') '' '' ''}
        $script:secret='Pa55-not-in-any-report'
    }
    BeforeEach {
        $script:LedgerTarget=@{baseUrl='http://stub.invalid';insecure=$false}
        $env:DW_PERSONA_CREDENTIALS=(@(@{userName='Buyer';password=$secret;userId=7},@{userName='Csr';password=$secret}) | ConvertTo-Json -Compress)
    }
    AfterEach {Remove-Item Env:DW_PERSONA_CREDENTIALS -ErrorAction SilentlyContinue}
    It 'is implemented with the sign-in route and one signed-in read, neither on the anonymous read list' {
        $binding=Get-Implemented $probe
        $binding.handler | Should -Be 'dwapi-persona-sign-in'
        $registry=Read-LedgerJson (Join-Path $assets 'handlers.json')
        $binding.operation | Should -BeIn $registry.dwapiSignInRoutes
        $binding.arguments.readAs | Should -BeIn $registry.dwapiSignedInReadRoutes
        $binding.operation | Should -Not -BeIn $registry.dwapiReadRoutes
        $binding.arguments.readAs | Should -Not -BeIn $registry.dwapiReadRoutes
    }
    It 'PASSes when every persona gets a token and is served itself, and no report field carries the password or token' {
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Post'} {New-Response 200 @{token="tok-$((ConvertFrom-Json $Body).username)"}}
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Get'} {$name=$Headers.Authorization.Substring(11);New-Response 200 @{id=$(if($name -eq 'Buyer'){7}else{8});userName=$name}}
        $row=Invoke-SignIn
        $row.result | Should -Be PASS
        $row.measured | Should -Be 1
        $row.scanned | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter {$Method -eq 'Post' -and $Uri -eq 'http://stub.invalid/dwapi/users/authenticate'}
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter {$Method -eq 'Get' -and $Uri -eq 'http://stub.invalid/dwapi/users/info' -and $Headers.Authorization -like 'Bearer tok-*'}
        $json=$row|ConvertTo-Json -Depth 20
        $json | Should -Not -Match ([regex]::Escape($secret))
        $json | Should -Not -Match 'tok-'
    }
    It 'RED CONTROL: a refused sign-in FAILs, names the user and status, and quotes no body' {
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Post'} {@{StatusCode=404;Content="echo $Body"}}
        $row=Invoke-SignIn
        $row.result | Should -Be FAIL
        $row.offenders[0].userName | Should -Be 'Buyer'
        $row.offenders[0].status | Should -Be 404
        ($row|ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($secret))
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter {$Method -eq 'Get'}
    }
    It 'RED CONTROL: a token that is served another user FAILs' {
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Post'} {New-Response 200 @{token='tok-x'}}
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Get'} {New-Response 200 @{id=99;userName='Anonymous'}}
        (Invoke-SignIn).result | Should -Be FAIL
    }
    It 'RED CONTROL: the right name with another user id FAILs' {
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Post'} {New-Response 200 @{token="tok-$((ConvertFrom-Json $Body).username)"}}
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Get'} {New-Response 200 @{id=99;userName=$Headers.Authorization.Substring(11)}}
        $row=Invoke-SignIn
        $row.result | Should -Be FAIL
        @($row.offenders).Count | Should -Be 1
        $row.offenders[0].userName | Should -Be 'Buyer'
    }
    It 'RED CONTROL: a signed-in read that is refused FAILs' {
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Post'} {New-Response 200 @{token='tok-x'}}
        Mock Invoke-WebRequest -ParameterFilter {$Method -eq 'Get'} {New-Response 401 $null}
        (Invoke-SignIn).result | Should -Be FAIL
    }
    It 'RED CONTROL: no persona credential is UNVERIFIED, with no request made' {
        Remove-Item Env:DW_PERSONA_CREDENTIALS
        Mock Invoke-WebRequest {throw 'no request expected'}
        $row=Invoke-SignIn
        $row.result | Should -Be UNVERIFIED
        $row.reason | Should -Match 'DW_PERSONA_CREDENTIALS'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
    It 'RED CONTROL: a malformed credential is UNVERIFIED and its value is never quoted' {
        $env:DW_PERSONA_CREDENTIALS="{`"userName`":`"Buyer`",`"password`":`"$secret`"}"
        Mock Invoke-WebRequest {throw 'no request expected'}
        $row=Invoke-SignIn
        $row.result | Should -Be UNVERIFIED
        ($row|ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($secret))
    }
    It 'RED CONTROL: a server error is ERROR and quotes nothing' {
        Mock Invoke-WebRequest {@{StatusCode=500;Content="boom $Body"}}
        $row=Invoke-SignIn
        $row.result | Should -Be ERROR
        ($row|ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($secret))
    }
    It 'RED CONTROL: refuses a sign-in route or read route off the lists before any request' -TestCases @(
        @{change=@{operation='users/authenticate/refresh'}},@{change=@{arguments=@{readAs='users/info/profiles/switch'}}},@{change=@{arguments=@{}}}
    ) {
        param($change)
        Mock Invoke-WebRequest {throw 'no request expected'}
        $copy=Read-LedgerJson (Join-Path $release 'probes/users/frontend-sign-in.persona-signs-in.json')
        foreach($key in $change.Keys){$copy.bindings[0][$key]=$change[$key]}
        (Invoke-LedgerCheck $copy @{} (New-FileCapabilities) @{expectations=@{}} @('dwapi') '' '' '').result | Should -Be ERROR
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
    It 'RED CONTROL: dwapi-count never reaches the sign-in route' {
        Mock Invoke-WebRequest {throw 'no request expected'}
        $check=@{id='fx.delivery';functionId='fx';intent=@{proves='Served';level='behavioural'};assertion=@{kind='scalar';op='ge';value=1}
            bindings=@(@{id='d';surface='dwapi';status='implemented';handler='dwapi-count';operation='users/authenticate';projection=@{rowsPath='$'}})}
        (Invoke-LedgerCheck $check @{} (New-FileCapabilities) @{expectations=@{}} @('dwapi') '' '' '').result | Should -Be ERROR
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
}

<#
.SYNOPSIS
WRITES: Swift release Files, ordered edition overlays, settings and local database config.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Only disk content is composed; no YAML
is deserialized. The release Files archive is verified against the public base contract.
.PARAMETER DemoRoot
Demo root containing the resolved Distribution checkout.
.PARAMETER SqlServer
Local integrated-auth SQL server.
.PARAMETER Database
Restored edition database name.
.PARAMETER Apply
Install files; otherwise preview.
.EXAMPLE
pwsh -NoProfile -File scripts/Install-DwDemoFiles.ps1 -DemoRoot $demo -SqlServer $server -Database $db -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$SqlServer,[Parameter(Mandatory)][string]$Database,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot; $connection=[System.Data.SqlClient.SqlConnectionStringBuilder]::new((Get-DwBuildConnection $SqlServer $Database))
    $r=Get-Content -Raw $p.Release | ConvertFrom-Json
    $contract=Get-Content -Raw (Join-Path $p.Distribution 'layers/base/base.contract.json') | ConvertFrom-Json
    $swift=$contract.deliveryTarget.hostFiles.swiftRelease
    if ($swift.tag -ne $r.swiftTag -or $swift.url -notlike 'https://github.com/dynamicweb/Swift/releases/download/*') { throw 'Swift release contract does not match the receipt.' }
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Files,'Install release and edition overlays')) { Write-Host 'Plan: verified Swift Files, base/add/surfaces/sample-data, themes last, database config.'; exit 0 }
    $zip=Join-Path $p.Notes $swift.asset
    if (-not(Test-Path $zip)) { Invoke-WebRequest -Uri $swift.url -OutFile ($zip+'.partial') -TimeoutSec 600; Move-Item -LiteralPath ($zip+'.partial') -Destination $zip -Force }
    if((Get-FileHash $zip -Algorithm SHA256).Hash -ne $swift.sha256){throw 'Swift Files SHA256 mismatch.'}
    [IO.Compression.ZipFile]::ExtractToDirectory($zip,(Join-Path $p.Host 'wwwroot'),$true)
    $mcp=@($r.apps | Where-Object {$_.id -match '\.MCP$'})[0]
    if(-not $mcp -or $mcp.id -notmatch '^Truvio\.Commerce\.MCP$' -or $mcp.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid pinned MCP app in the release receipt.'}
    $id=$mcp.id.ToLowerInvariant();$version=$mcp.version.ToLowerInvariant()
    $cache=Join-Path $p.Notes "tools/$id.$version"
    New-Item -ItemType Directory -Force $cache | Out-Null
    $metadataPath=Join-Path $cache 'catalog.json'
    if(-not(Test-Path $metadataPath)){
        $registration=Invoke-RestMethod "https://api.nuget.org/v3/registration5-gz-semver2/$id/$version.json" -TimeoutSec 120
        if($registration.catalogEntry -notlike 'https://api.nuget.org/*'){throw 'Unexpected NuGet catalog URL.'}
        $metadata=Invoke-RestMethod $registration.catalogEntry -TimeoutSec 120
        Write-DwBuildJson $metadataPath $metadata
    }
    $metadata=Get-Content -Raw $metadataPath | ConvertFrom-Json
    if($metadata.id -ine $mcp.id -or $metadata.version -ine $mcp.version -or $metadata.packageHashAlgorithm -ne 'SHA512' -or -not $metadata.packageHash){throw 'NuGet identity or published hash is missing.'}
    $package=Join-Path $cache "$id.$version.nupkg"
    if(-not(Test-Path $package)){
        Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg" -OutFile ($package+'.partial') -TimeoutSec 600
        Move-Item -LiteralPath ($package+'.partial') -Destination $package -Force
    }
    $stream=[IO.File]::OpenRead($package)
    try{$packageHash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::HashData($stream))}finally{$stream.Dispose()}
    if($packageHash -cne $metadata.packageHash){throw 'MCP nupkg does not match its published SHA512.'}
    $unpacked=Join-Path $cache 'unpacked'
    [IO.Compression.ZipFile]::ExtractToDirectory($package,$unpacked,$true)
    $lib=Join-Path $unpacked 'lib/net10.0'
    if(-not(Test-Path (Join-Path $lib 'Truvio.Commerce.MCP.dll'))){throw 'Pinned MCP package has no net10 runtime assembly.'}
    $installed=Join-Path $p.Files "System/AddIns/Installed/$($mcp.id).$($mcp.version)/lib/net10.0"
    New-Item -ItemType Directory -Force $installed | Out-Null
    Get-ChildItem $lib -File | Copy-Item -Destination $installed -Force
    if(Test-Path (Join-Path $unpacked 'Files')){Get-ChildItem (Join-Path $unpacked 'Files') -Force | Copy-Item -Destination $p.Files -Recurse -Force}
    # The AddIn loader and the default host load context must never load the same assembly.
    $bin=Join-Path $p.Host 'bin'
    $binNames=if(Test-Path $bin){@(Get-ChildItem $bin -Filter '*.dll' -Recurse -File | ForEach-Object Name)}else{@()}
    $duplicates=@(Get-ChildItem (Join-Path $p.Files 'System/AddIns/Installed') -Filter '*.dll' -Recurse -File | Where-Object {$_.FullName -match '[\\/]lib[\\/]' -and $_.Name -in $binNames} | ForEach-Object Name | Select-Object -Unique)
    if($duplicates.Count){throw "An app exists in both bin and AddIns: $($duplicates -join ', '). Remove its PackageReference and clean/rebuild this owned host before starting."}
    $e=$r.editionModel; $before=@();$after=@()
    foreach($ref in $e.add) {
        $name=($ref -split '@')[0]
        $layer=Get-Content -Raw (Join-Path $p.Distribution "layers/$name/layer.json") | ConvertFrom-Json
        if($layer.kind -eq 'sample-data'){$after+=$name}else{$before+=$name}
    }
    $layers=@(($e.from -split '@')[0])+$before+@($e.surfaces | ForEach-Object {($_ -split '@')[0]})+$after
    if($e.sampleData){$layers+='sample-data'}
    $layers+=@($e.themes | ForEach-Object {if($_ -like 'theme-*'){$_}else{"theme-$_"}})
    foreach($name in $layers) {
        $src=Join-Path $p.Distribution "layers/$name/files"
        if(Test-Path $src){ Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $p.Files -Recurse -Force }
        foreach($pair in @(@('itemtypes','System/Items'),@('repositories','System/Repositories'),@('templates','Templates'))) {
            $source=Join-Path $p.Distribution "layers/$name/$($pair[0])"
            if(Test-Path $source){
                $destination=Join-Path $p.Files $pair[1]
                New-Item -ItemType Directory -Force $destination | Out-Null
                Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $destination -Recurse -Force
            }
        }
    }
    $settings=Join-Path $p.Files 'GlobalSettings.config'
    [xml]$xml=Get-Content -Raw $settings
    function Merge-SettingsNode($Source,$Target) {
        foreach($child in @($Source.ChildNodes | Where-Object NodeType -eq Element)) {
            $node=$Target.SelectSingleNode($child.Name)
            if(-not $node){$node=$xml.CreateElement($child.Name);$null=$Target.AppendChild($node)}
            if(@($child.ChildNodes | Where-Object NodeType -eq Element).Count){Merge-SettingsNode $child $node}else{$node.InnerText=$child.InnerText}
        }
    }
    foreach($name in $layers) {
        $source=Join-Path $p.Distribution "layers/$name/files"
        if(Test-Path $source){
            foreach($fragment in Get-ChildItem $source -Filter 'globalsettings.*.fragment.config' -Recurse){
                [xml]$part=Get-Content -Raw $fragment.FullName
                if($part.DocumentElement.Name -ne 'Globalsettings'){throw 'Invalid GlobalSettings fragment root.'}
                # Public layers may switch features, but never replace a local connection or license.
                foreach($node in @($part.DocumentElement.ChildNodes | Where-Object NodeType -eq Element)){
                    if($node.Name -ne 'Features'){throw "Unsupported settings fragment branch: $($node.Name)"}
                }
                Merge-SettingsNode $part.DocumentElement $xml.DocumentElement
            }
        }
    }
    foreach($required in $contract.deliveryTarget.hostFiles.globalSettings.required) {
        $parent=$xml.DocumentElement
        foreach($segment in @($required.path.Trim('/') -split '/' | Select-Object -Skip 1)) {
            $node=$parent.SelectSingleNode($segment)
            if(-not $node){$node=$xml.CreateElement($segment);$null=$parent.AppendChild($node)}
            $parent=$node
        }
        $parent.InnerText=$required.value
    }
    # Keep the published password hash convention explicit.
    $encrypt=$xml.SelectSingleNode('//EncryptPassword'); if($encrypt){$encrypt.InnerText='1'}
    $xml.Save($settings)
    $db=[xml]'<Globalsettings><System><Database><Type>ms_sqlserver</Type><SQLServer/><Database/><IntegratedSecurity>True</IntegratedSecurity></Database></System></Globalsettings>'
    $db.SelectSingleNode('//SQLServer').InnerText=$SqlServer; $db.SelectSingleNode('/Globalsettings/System/Database/Database').InnerText=$Database
    if (-not $connection.IntegratedSecurity) {
        $db.SelectSingleNode('//IntegratedSecurity').InnerText='False'
        foreach ($entry in @{UserName=$connection.UserID;Password=$connection.Password}.GetEnumerator()) {
            $node=$db.CreateElement($entry.Key);$node.InnerText=$entry.Value
            $null=$db.SelectSingleNode('/Globalsettings/System/Database').AppendChild($node)
        }
    }
    $db.Save((Join-Path $p.Files 'GlobalSettings.Database.config'))
    Write-DwBuildJson (Join-Path $p.Notes 'files-installed.json') @{layers=$layers;swiftSha256=$swift.sha256;mcpPackage=@{id=$mcp.id;version=$mcp.version;hostPayload=$true;mechanism='AddIns';sha512=$packageHash}}
    Write-Host "Installed verified Files and $($layers.Count) layer overlays."
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }

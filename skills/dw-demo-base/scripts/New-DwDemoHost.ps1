<#
.SYNOPSIS
WRITES: the pinned Suite scaffold, launch profile, gitignore and read-only source contract.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Existing unowned hosts are refused.
The Suite host has no MCP PackageReference. The files step installs the pinned public app
into the same AddIns layout used by the AppStore before the first start.
.PARAMETER DemoRoot
Demo directory with release receipt.
.PARAMETER ConfigPath
Customer JSON.
.PARAMETER Port
Free HTTPS port, explicitly supplied.
.PARAMETER Apply
Write the scaffold; otherwise preview.
.PARAMETER SkipPackageRestore
Generate only the scaffold files for offline inspection or hermetic tests. The normal build
restores the Suite packages before file installation.
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwDemoHost.ps1 -DemoRoot $demo -ConfigPath $config -Port $port -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][ValidateRange(1024,65535)][int]$Port,[switch]$Apply,[switch]$SkipPackageRestore)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot; $c=Read-DwBuildConfig $ConfigPath
    $r=Get-Content -Raw $p.Release | ConvertFrom-Json
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Host,'Scaffold pinned net10 host')) { Write-Host "Plan: scaffold Suite at $($r.dwVersion), net10, explicit HTTPS port."; exit 0 }
    $marker=Join-Path $p.Notes 'scaffold-owned.json'
    if ((Test-Path $p.Host) -and -not (Test-Path $marker)) { throw 'Existing host is not owned by this build; choose an empty DemoRoot.' }
    if (-not (Test-Path $p.Host)) {
        Write-DwBuildJson $marker @{port=$Port;created=(Get-Date -Format o)}
        Invoke-DwBuildCommand dotnet @('new','dw10-suite','--name','Dynamicweb.Host.Suite','--output',$p.Host,'--no-update-check') -TimeoutSeconds 600
    }
    $csproj=Join-Path $p.Host 'Dynamicweb.Host.Suite.csproj'
    [xml]$xml=Get-Content -Raw $csproj
    foreach ($pg in $xml.Project.PropertyGroup) {
        foreach ($node in @($pg.SelectNodes('TargetFramework|TargetFrameworks'))) { $null=$pg.RemoveChild($node) }
    }
    $tf=$xml.CreateElement('TargetFramework'); $tf.InnerText='net10.0'; $null=$xml.SelectSingleNode('/Project/PropertyGroup').AppendChild($tf)
    $suite=$xml.SelectSingleNode('//PackageReference[@Include="Dynamicweb.Suite"]')
    if (-not $suite) { throw 'Template does not reference Dynamicweb.Suite.' }
    $suite.SetAttribute('Version',$r.dwVersion)
    foreach($node in @($xml.SelectNodes('//PackageReference[starts-with(@Include,"Truvio.Commerce.MCP")]|//TruvioMcpSdkReferences'))) {
        $null=$node.ParentNode.RemoveChild($node)
    }
    if (-not $xml.SelectSingleNode('//Content[@Remove="wwwroot/Files/System/**"]')) {
        $group=$xml.CreateElement('ItemGroup')
        foreach($tag in 'Content','None') { $node=$xml.CreateElement($tag);$node.SetAttribute('Remove','wwwroot/Files/System/**');$null=$group.AppendChild($node) }
        $null=$xml.Project.AppendChild($group)
    }
    $xml.Save($csproj)
    $nugetConfig=Join-Path $p.Host 'NuGet.Config'
    '<configuration><packageSources><clear/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources><packageSourceMapping><clear/></packageSourceMapping></configuration>' | Set-Content -LiteralPath $nugetConfig -Encoding utf8NoBOM
    $program=Join-Path $p.Host 'Program.cs'; $source=Get-Content -Raw $program
    if ($source -notmatch 'ImplicitDistributedTransactions') { $source=$source -replace '(var builder\s*=\s*WebApplication.CreateBuilder)',"System.Transactions.TransactionManager.ImplicitDistributedTransactions = true;`n`$1" }
    Set-Content -LiteralPath $program -Value $source -Encoding utf8NoBOM
    Write-DwBuildJson (Join-Path $p.Host 'Properties/launchSettings.json') @{profiles=@{'Dynamicweb.Host.Suite'=@{commandName='Project';launchBrowser=$false;applicationUrl="https://localhost:$Port";environmentVariables=@{ASPNETCORE_ENVIRONMENT='Development'}}}}
    $ignorePath=Join-Path $p.Root '.gitignore'
    $ignore=if(Test-Path $ignorePath){@(Get-Content $ignorePath)}else{@()}
    @($ignore+@('bin/','obj/','wwwroot/Files/System/','notes/','.demo/','.mcp.json','.claude/settings.local.json','distribution/','dw-swift/') | Select-Object -Unique) | Set-Content $ignorePath -Encoding utf8NoBOM
    $contract='## Customer-context read-only contract'
    $claude=Join-Path $p.Root 'CLAUDE.md'
    if (-not (Test-Path $claude) -or (Get-Content -Raw $claude) -notmatch [regex]::Escape($contract)) {
        "$contract`n`nThe customer-context/ directory is read-only. Copy source assets into the host; never write into customer-context/. Build evidence belongs under notes/." | Add-Content $claude -Encoding utf8NoBOM
    }
    if (-not (Test-Path (Join-Path $p.Root 'CUSTOMISATIONS.md'))) { (Get-Content -Raw (Join-Path $PSScriptRoot '../assets/CUSTOMISATIONS.md.template')).Replace('<demo-name>',$c.slug) | Set-Content (Join-Path $p.Root 'CUSTOMISATIONS.md') -Encoding utf8NoBOM }
    if(-not $SkipPackageRestore){Invoke-DwBuildCommand dotnet @('restore',$csproj,'--configfile',$nugetConfig)}
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; Write-Host "Scaffold failure line $($_.InvocationInfo.ScriptLineNumber)."; exit 1 }

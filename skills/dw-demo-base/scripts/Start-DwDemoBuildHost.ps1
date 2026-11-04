<#
.SYNOPSIS
WRITES: starts the owned local host and activates a trial license over HTTP.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Uses the existing ownership-checked
host lifecycle script and the sibling skill's HTTP license helper. Missing bundle files fail.
.PARAMETER DemoRoot
Root of this scripted demo.
.PARAMETER Port
HTTPS port matching launchSettings.json.
.PARAMETER Apply
Start and license; otherwise preview.
.EXAMPLE
pwsh -NoProfile -File scripts/Start-DwDemoBuildHost.ps1 -DemoRoot $demo -Port $port -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][int]$Port,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot
    $launch=Get-Content -Raw (Join-Path $p.Host 'Properties/launchSettings.json') | ConvertFrom-Json
    if(([uri]$launch.profiles.'Dynamicweb.Host.Suite'.applicationUrl).Port -ne $Port){throw 'Port does not match this host launch profile.'}
    $license=Join-Path $PSScriptRoot '../../dw-setup-install/scripts/activate-free-trial.ps1'
    if(-not(Test-Path $license)){throw 'Bundle lacks dw-setup-install/scripts/activate-free-trial.ps1. Install the complete presales bundle.'}
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Host,'Start owned host and activate trial')){Write-Host 'Plan: ownership-checked durable start, /Admin readiness, HTTP trial activation.';exit 0}
    Invoke-DwBuildCommand pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Restart-DwHost.ps1'),'-Action','Start','-Port',"$Port",'-SolutionPath',$p.Root,'-Reason','Scripted base build','-ReadyTimeoutMinutes','20')
    $base="https://localhost:$Port"
    $response=Invoke-WebRequest -Uri "$base/Admin" -SkipCertificateCheck -TimeoutSec 120
    if([string]$response.BaseResponse.RequestMessage.RequestUri -match '/admin/license'){
        Invoke-DwBuildCommand pwsh @('-NoProfile','-File',$license,'-DynamicwebUrl',$base,'-FilesPath',$p.Files)
    }
    $licenses=@(Get-ChildItem $p.Files -Filter '*.license' -File)
    if(-not $licenses.Count){throw 'No license file was created. Check /Admin/License.'}
    $licenseProof=Join-Path $p.Notes 'license-proof.json'
    if(-not(Test-Path $licenseProof)){Write-DwBuildJson $licenseProof @{files=@($licenses.Name);expiry='Pending authenticated License query in the access step.'}}
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}

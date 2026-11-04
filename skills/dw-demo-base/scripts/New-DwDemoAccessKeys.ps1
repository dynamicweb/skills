<#
.SYNOPSIS
WRITES: a local Management API key and a full-access MCP key on a fresh restore, before first start.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. SQL is local installs only: no host or
Management API exists yet, and the MCP binding must exist at startup. One transaction writes the
two administrator token rows, the full-access McpConfiguration and its credential binding. A
repeated run reuses the stored secrets, so the hashes and binding stay the same.
.PARAMETER DemoRoot
Demo root containing the restored database receipt.
.PARAMETER SqlServer
Local SQL Server.
.PARAMETER Database
Database owned by this build.
.PARAMETER Apply
Write the keys. Dry run by default.
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwDemoAccessKeys.ps1 -DemoRoot $demo -SqlServer $server -Database $db -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$SqlServer,[Parameter(Mandatory)][string]$Database,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot;$conn=Get-DwBuildConnection $SqlServer $Database
    $receipt=Get-Content -Raw (Join-Path $p.Notes 'database-owned.json') | ConvertFrom-Json
    if($receipt.database -ne $Database -or $receipt.server -ne $SqlServer){throw 'Database does not match the owned restore.'}
    $launch=Join-Path $p.Host 'Properties/launchSettings.json'
    $port=([uri](Get-Content -Raw $launch | ConvertFrom-Json).profiles.'Dynamicweb.Host.Suite'.applicationUrl).Port
    if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue){throw 'Key minting is pre-start only. Stop the owned host before applying this step.'}
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($Database,'Mint the local API and MCP keys in one transaction')){Write-Host 'Plan: administrator API key, full-access MCP configuration, key and binding.';exit 0}
    $secretPath=Join-Path $p.Notes 'build-secrets.local.json'
    $secrets=Get-Content -Raw $secretPath | ConvertFrom-Json -AsHashtable
    foreach($kind in 'api','mcp'){
        $key=$kind+'Token'
        if(-not $secrets[$key]){
            $value=[Environment]::GetEnvironmentVariable(('DW_'+$kind.ToUpperInvariant()+'_KEY_SECRET'))
            if(-not $value){$value=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()}
            if($value.Length -lt 32){throw 'API and MCP key secrets must be at least 32 characters.'}
            $secrets[$key]=@{api='DEMO';mcp='DEMOMCP'}[$kind]+'.'+$value
        }
    }
    Write-DwBuildJson $secretPath $secrets
    $cn=[System.Data.SqlClient.SqlConnection]::new($conn);$cn.Open();$tx=$cn.BeginTransaction()
    try {
        $secrets.mcpConfigurationId=Initialize-DwBuildAccess -Connection $cn -Transaction $tx -ApiBearer $secrets.apiToken -McpBearer $secrets.mcpToken
        $tx.Commit()
    } catch { $tx.Rollback();throw } finally { $cn.Dispose() }
    Write-DwBuildJson $secretPath $secrets
    Write-Host "Keys minted: API key, MCP key and configuration $($secrets.mcpConfigurationId). Secrets stored locally, never printed."
    exit 0
} catch { Write-Error $_ -ErrorAction Continue;exit 1 }

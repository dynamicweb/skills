<#
.SYNOPSIS
WRITES: ignored local client settings after proving the pre-boot API and MCP credentials.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Authenticate with the restored admin
over loopback HTTP, prove the stored API key and require tools/list >200 before attaching
the MCP key to client settings. Credentials were provisioned in the stopped-host SQL step.
.PARAMETER DemoRoot
Demo root with ignored build secrets and launch settings.
.PARAMETER Apply
Prove access and write settings. Without this switch preview only.
.EXAMPLE
pwsh -NoProfile -File scripts/Grant-DwDemoAccess.ps1 -DemoRoot $demo -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$DemoRoot,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot
    $launch=Get-Content -Raw (Join-Path $p.Host 'Properties/launchSettings.json') | ConvertFrom-Json
    $base=$launch.profiles.'Dynamicweb.Host.Suite'.applicationUrl
    if(-not ([uri]$base).IsLoopback){throw 'Access provisioning accepts localhost or another loopback address only.'}
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($base,'Verify pre-boot API and MCP access and attach client settings')){Write-Host 'Plan: token authentication, API key, MCP config/key, tools/list proof, ignored local client files.';exit 0}
    $secretFile=Join-Path $p.Notes 'build-secrets.local.json';$secrets=Get-Content -Raw $secretFile | ConvertFrom-Json -AsHashtable
    $auth=Invoke-RestMethod -Uri "$base/Admin/TokenAuthentication/authenticate" -Method Post -ContentType 'application/json' -Body (@{Username='Admin';Password=$secrets['2']} | ConvertTo-Json) -SkipCertificateCheck -TimeoutSec 60
    if(-not $auth.token){throw 'Admin token authentication failed; inspect the license and restored admin state.'}
    if(-not $secrets.apiToken -or -not $secrets.mcpToken){throw 'Run brand-content while the host is stopped to provision the local credentials.'}
    $headers=@{Authorization="Bearer $($secrets.apiToken)"}
    function Invoke-AccessApi([string]$Path) {
        Invoke-RestMethod -Uri "$base/admin/api/$Path" -Headers $headers -SkipCertificateCheck -TimeoutSec 120
    }
    $license=Invoke-AccessApi 'License'
    if(-not $license.model.expirationDate){throw 'License query returned no expiry date.'}
    Write-DwBuildJson (Join-Path $p.Notes 'license-proof.json') @{expiry=$license.model.expirationDate;status=$license.model.licenseStatus;type=$license.model.licenseType;source='Management API License'}
    $key=$secrets.mcpToken;$id=$secrets.mcpConfigurationId
    $mcpHeaders=@{Authorization="Bearer $key";Accept='application/json, text/event-stream'}
    function Invoke-KeyRpc([hashtable]$Message) {
        $response=Invoke-WebRequest -Uri "$base/admin/mcp" -Method Post -Headers $mcpHeaders -ContentType 'application/json' -Body ($Message | ConvertTo-Json -Depth 12) -SkipCertificateCheck -TimeoutSec 90
        if($response.Headers['mcp-session-id']){$mcpHeaders['mcp-session-id']=[string]@($response.Headers['mcp-session-id'])[0]}
        if(-not $response.Content){return $null}
        $lines=@([string]$response.Content -split "`n" | Where-Object {$_ -match '^data:'})
        $json=if($lines.Count){$lines[-1] -replace '^data:\s*',''}else{[string]$response.Content}
        $json | ConvertFrom-Json
    }
    $init=Invoke-KeyRpc @{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-03-26';capabilities=@{};clientInfo=@{name='DwDemoBuild';version='1.0'}}}
    if(-not $init.result){throw 'MCP initialize failed.'}
    $null=Invoke-KeyRpc @{jsonrpc='2.0';method='notifications/initialized'}
    $tools=@();$cursor=$null;$rpcId=1
    do {
        $rpcParams=if($cursor){@{cursor=$cursor}}else{@{}}
        $page=Invoke-KeyRpc @{jsonrpc='2.0';id=(++$rpcId);method='tools/list';params=$rpcParams}
        if($page.error){throw 'MCP tools/list returned an RPC error.'}
        $tools+=@($page.result.tools);$cursor=$page.result.nextCursor
    }while($cursor)
    if($tools.Count -le 200){throw "MCP key exposes $($tools.Count) tools; full access was not established."}
    $secrets.mcpToken=$key;$secrets.mcpConfigurationId=$id;Write-DwBuildJson $secretFile $secrets
    Write-DwBuildJson (Join-Path $p.Root '.mcp.json') @{mcpServers=@{'dynamicweb-commerce-mcp'=@{type='http';url="$base/admin/mcp";headers=@{Authorization="Bearer $key"}}}}
    $settingsPath=Join-Path $p.Root '.claude/settings.local.json'
    $settings=if(Test-Path $settingsPath){Get-Content -Raw $settingsPath | ConvertFrom-Json -AsHashtable}else{@{}}
    if(-not $settings.env){$settings.env=@{}};$settings.env.NODE_TLS_REJECT_UNAUTHORIZED='0'
    $settings.enabledMcpjsonServers=@(@($settings.enabledMcpjsonServers)+'dynamicweb-commerce-mcp' | Select-Object -Unique)
    Write-DwBuildJson $settingsPath $settings
    [Environment]::SetEnvironmentVariable('NODE_TLS_REJECT_UNAUTHORIZED','0','User');$env:NODE_TLS_REJECT_UNAUTHORIZED='0'
    Add-Content (Join-Path $p.Notes 'credentials.local.md') @("`nHost: $base","Management API: $($secrets.apiToken)","MCP: $key") -Encoding utf8NoBOM
    Write-DwBuildJson (Join-Path $p.Notes 'access-proof.json') @{toolCount=$tools.Count;server=$init.result.serverInfo;configurationId=$id}
    Write-Host "MCP verified: $($tools.Count) tools. Keys stored in ignored local files. Start the agent from a fresh shell to inherit TLS settings."
    exit 0
} catch {
    $message=$_.Exception.Message
    foreach($secret in @($secrets.Values)+@($key,$auth.token)){
        if($secret -is [string] -and $secret.Length -gt 4){$message=$message.Replace($secret,'<masked>')}
    }
    Write-Error "Access provisioning failed: $message" -ErrorAction Continue
    Write-Host "Failure location: $($_.InvocationInfo.ScriptLineNumber). Check the license, admin credentials and MCP app."
    exit 1
}

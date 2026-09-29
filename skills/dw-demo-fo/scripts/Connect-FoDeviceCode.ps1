<#
.SYNOPSIS
    WRITES: a DPAPI-protected refresh-token cache file at -CachePath. Nothing in F&O.

.DESCRIPTION
    Delegated sign-in to a Dynamics 365 Finance and Operations environment with the OAuth 2.0 device-code
    flow, for a machine or a session that has no S2S app secret. Signs in once, then the other dw-demo-fo
    scripts renew their own access tokens from the cached refresh token (Fo.Api.psm1 rotates it on every
    renewal), so a copy or repair run of several hours never stops on an expired token.

    Owning reference: dw-demo-fo/references/connection-modes.md ("Access for the scripts").

    The client id must be a public client app that is allowed the F&O delegated permission, for example an
    app registration with "Allow public client flows" on. The signed-in user needs an F&O user with the
    roles the scripts need (read for the checks, write inside the demo company for the repair).

    Traps encoded here:
      - The device code and URL are written to the host (information stream), never to the output, so
        the script can run unattended while a person completes the sign-in elsewhere.
      - The refresh token is stored with Windows DPAPI for the current user only. The file is useless on
        another machine or to another account; delete it to sign out. Windows only.
      - No token or secret is ever printed; the script reports the environment, the cache path and a probe.
      - authorization_pending and slow_down are the normal replies while the person signs in; anything
        else stops the poll with the error text.

.PARAMETER TenantId
    Directory (tenant) id or domain of the tenant that owns the environment. Else $env:FO_TENANT_ID.

.PARAMETER ClientId
    Application (client) id of the public client app. Else $env:FO_CLIENT_ID.

.PARAMETER EnvironmentUrl
    Environment root, https://<env>.operations.dynamics.com. Else $env:FO_ENV_URL.

.PARAMETER CachePath
    File that receives the protected refresh token. Else $env:FO_TOKEN_CACHE. Keep it outside any repo
    and any synced folder.

.PARAMETER Force
    Sign in again even when the cache already holds a working refresh token.

.EXAMPLE
    pwsh -NoProfile -File scripts/Connect-FoDeviceCode.ps1 -TenantId <tenant-id> -ClientId <client-id> -EnvironmentUrl https://<env>.operations.dynamics.com -CachePath $env:LOCALAPPDATA/fo/<env>.dpapi
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop

foreach ($pair in @(@('TenantId', $TenantId, 'FO_TENANT_ID'), @('ClientId', $ClientId, 'FO_CLIENT_ID'),
                    @('EnvironmentUrl', $EnvironmentUrl, 'FO_ENV_URL'), @('CachePath', $CachePath, 'FO_TOKEN_CACHE'))) {
    if (-not $pair[1]) { Write-Error "Missing -$($pair[0]) (or `$env:$($pair[2]))."; exit 1 }
}
$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
$CachePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CachePath)

function Test-FoSignIn {
    Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token ''
    $probe = Invoke-FoApi -Path '/data/LegalEntities?$top=1&$select=LegalEntityId'
    [pscustomobject]@{ Environment = $EnvironmentUrl; SignedIn = $true; CachePath = $CachePath; Probe = "LegalEntities readable ($(@($probe.value).Count) row)" }
}

if ((Test-Path -LiteralPath $CachePath) -and -not $Force -and -not $env:FO_CLIENT_SECRET) {
    try {
        Write-Host ((Test-FoSignIn | Format-List | Out-String).Trim())
        Write-Host 'cached refresh token still works; nothing to do (use -Force to sign in again)'
        exit 0
    } catch {
        Write-Host "cached refresh token did not work ($($_.Exception.Message)); signing in again"
    }
}

$scope = "$EnvironmentUrl/.default offline_access"
$authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
$dc = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" -Body @{ client_id = $ClientId; scope = $scope }
Write-Host ("sign in at {0} with code {1} (valid {2} min)" -f $dc.verification_uri, $dc.user_code, [int]($dc.expires_in / 60))

$deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
$interval = [int]$dc.interval
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    try {
        $t = Invoke-RestMethod -Method Post -Uri "$authority/token" -Body @{
            grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $ClientId; device_code = $dc.device_code }
    } catch {
        $e = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        $code = if ($e) { $e.error } else { 'unknown' }
        if ($code -eq 'authorization_pending') { continue }
        if ($code -eq 'slow_down') { $interval += 5; continue }
        Write-Error ("device-code sign-in failed: {0} {1}" -f $code, $(if ($e) { $e.error_description }))
        exit 1
    }
    if (-not $t.refresh_token) { Write-Error 'sign-in returned no refresh token: the scope must include offline_access.'; exit 1 }
    Save-FoRefreshToken -Path $CachePath -RefreshToken $t.refresh_token
    Write-Host "signed in; refresh token cached (DPAPI, current user) at $CachePath"
    Write-Host ((Test-FoSignIn | Format-List | Out-String).Trim())
    exit 0
}
Write-Error 'device code expired before the sign-in completed; run the script again.'
exit 1

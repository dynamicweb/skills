<#
.SYNOPSIS
  Acquire an Entra ID access token for a D365 Finance & Operations environment (client-credentials, S2S).

.DESCRIPTION
  Uses the v2.0 token endpoint with scope "<EnvironmentUrl>/.default". The app registration must be listed under
  System administration > Setup > Microsoft Entra ID applications in F&O, tied to a user with the roles needed
  for reading the entities you query. The secret is read from the FO_CLIENT_SECRET environment variable or the
  -ClientSecret SecureString — never from a file in the discovery output folder.

.OUTPUTS
  The bearer token string. Also sets $env:FO_TOKEN for the current process so sibling scripts can reuse it.

.EXAMPLE
  $env:FO_CLIENT_SECRET = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText   # paste once per session
  .\Get-FoToken.ps1 -TenantId <guid> -ClientId <guid> -EnvironmentUrl https://<env>.operations.dynamics.com
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$TenantId,
  [Parameter(Mandatory)][string]$ClientId,
  [Parameter(Mandatory)][string]$EnvironmentUrl,
  [securestring]$ClientSecret
)
$ErrorActionPreference = 'Stop'
$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
$secret = if ($ClientSecret) { ConvertFrom-SecureString $ClientSecret -AsPlainText } else { $env:FO_CLIENT_SECRET }
if (-not $secret) { throw 'No client secret: pass -ClientSecret (SecureString) or set $env:FO_CLIENT_SECRET.' }

$body = @{
  grant_type    = 'client_credentials'
  client_id     = $ClientId
  client_secret = $secret
  scope         = "$EnvironmentUrl/.default"
}
$resp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
$env:FO_TOKEN = $resp.access_token
$env:FO_ENV_URL = $EnvironmentUrl
Write-Host ("token acquired for {0} (expires in {1}s); `$env:FO_TOKEN set" -f $EnvironmentUrl, $resp.expires_in)
$resp.access_token

<#
.SYNOPSIS
    WRITES: one LegalEntities record (the demo company) in D365 Finance and Operations, only when it is absent.

.DESCRIPTION
    Step 1 of the demo-company recipe (references/demo-company.md). GETs /data/LegalEntities('<Code>') first
    and creates the record only when it is absent, so the script is safe to re-run as part of a seed chain.

    It creates the legal ENTITY only. A new company has no ledger, no number sequences, no bank accounts and
    no dimension groups: step 2 (import the golden company's configuration package, or Copy into legal
    entity when building the golden company itself) and step 3 (apply the company profile) do that.

    Some tenants expose LegalEntities read-only or gate the create path. That is expected, not fatal: the
    script reports the refusal and names the documented fallback (the Create button on the
    Copy-into-legal-entity project's Legal entities FastTab, or Organization administration > Organizations >
    Legal entities > New).

    The dry run is -WhatIf; without it the script writes the one record.

.PARAMETER Code
    Legal entity id, 1-4 characters. Read-only in F&O once created.

.PARAMETER Name
    Legal name of the company.

.PARAMETER SearchName
    NameAlias. Defaults to the code.

.PARAMETER CountryRegionId
    ISO country/region id, for example USA. Must match the region of the golden or donor company, or the
    localisation-specific fields fail validation on import.

.PARAMETER LanguageId
    Company language, for example en-us.

.PARAMETER ProfilePath
    Optional JSON file with any additional LegalEntities fields to set on create (for example AddressStreet,
    AddressState, AddressZipCode). Values there win over the equivalent parameters; LegalEntityId never.

.PARAMETER EnvironmentUrl
    Else $env:FO_ENV_URL. Identity: -TenantId / -ClientId / -CachePath / -Token, else the FO_* environment
    variables (see Fo.Api.psm1).

.EXAMPLE
    pwsh -NoProfile -File scripts/New-DemoCompany.ps1 -Code ABC -Name 'Example Industries, Inc.' -CountryRegionId USA -LanguageId en-us -City Springfield -State IL -WhatIf

.EXAMPLE
    pwsh -NoProfile -File scripts/New-DemoCompany.ps1 -Code ABC -Name 'Example Industries, Inc.' -CountryRegionId USA -LanguageId en-us -ProfilePath ./abc-legal-entity.json
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Code,
    [Parameter(Mandatory)][string]$Name,
    [string]$SearchName,
    [Parameter(Mandatory)][string]$CountryRegionId,
    [Parameter(Mandatory)][string]$LanguageId,
    [string]$Street,
    [string]$City,
    [string]$State,
    [string]$ZipCode,
    [string]$ProfilePath,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [string]$Token = $env:FO_TOKEN
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token $Token
$Code = $Code.ToUpperInvariant()
$envUrl = Get-FoEnvironmentUrl

# 1. Does it already exist?
$existing = $null
try {
    $existing = Invoke-FoApi -Path "/data/LegalEntities('$Code')"
} catch {
    $response = $_.Exception.PSObject.Properties['Response'] ? $_.Exception.Response : $null
    $status = if ($response) { [int]$response.StatusCode } else { 0 }
    if ($status -in 401, 403) {
        Write-Error ("Read of LegalEntities('{0}') was refused (HTTP {1}). The app must be listed in F&O under System administration > Setup > Microsoft Entra ID applications, bound to a user with rights on this entity." -f $Code, $status)
        exit 1
    }
    if ($status -ne 404) { Write-Error (Get-FoErrorText $_); exit 1 }
}
if ($existing) {
    Write-Host ("legal entity '{0}' already exists: {1}. Nothing created. Next: recipe step 2." -f $Code, $existing.Name)
    [pscustomobject]@{ Code = $Code; Created = $false; Name = $existing.Name }
    exit 0
}

# 2. Build the payload
$payload = [ordered]@{
    LegalEntityId          = $Code
    Name                   = $Name
    NameAlias              = if ($SearchName) { $SearchName } else { $Code }
    CompanyCountry         = $CountryRegionId
    AddressCountryRegionId = $CountryRegionId
    LanguageId             = $LanguageId
}
if ($Street) { $payload['AddressStreet'] = $Street }
if ($City) { $payload['AddressCity'] = $City }
if ($State) { $payload['AddressState'] = $State }
if ($ZipCode) { $payload['AddressZipCode'] = $ZipCode }
if ($City -or $Street) { $payload['AddressDescription'] = "$Name - primary" }

# Optional overrides from a profile JSON. A distinct variable for the parsed object: reusing the [string]
# path parameter would silently turn the parsed value back into a string.
if ($ProfilePath) {
    $profileFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath)
    if (-not (Test-Path -LiteralPath $profileFile)) { Write-Error "Profile file not found: $profileFile"; exit 1 }
    $profileJson = Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json
    foreach ($prop in $profileJson.PSObject.Properties) { $payload[$prop.Name] = $prop.Value }
    $payload['LegalEntityId'] = $Code
}
$body = $payload | ConvertTo-Json -Depth 4

if (-not $PSCmdlet.ShouldProcess("$envUrl (legal entity $Code)", 'POST /data/LegalEntities')) {
    Write-Host "would create legal entity '$Code':"
    Write-Host $body
    [pscustomobject]@{ Code = $Code; Created = $false; Name = $Name }
    exit 0
}

# 3. Create
try {
    $created = Invoke-FoApi -Path '/data/LegalEntities' -Method Post -Body $body
    Write-Host ("created legal entity '{0}' ({1}): the ENTITY only, no ledger, number sequences or bank accounts yet." -f $Code, $created.Name)
    Write-Host 'Next: recipe step 2 (import the golden configuration package), then step 3 (apply the company profile).'
    [pscustomobject]@{ Code = $Code; Created = $true; Name = $created.Name }
    exit 0
} catch {
    Write-Warning ("POST /data/LegalEntities was refused: {0}" -f (Get-FoErrorText $_))
    Write-Host 'A known tenant-dependent gate, not a dead end. Create the company through either:' -ForegroundColor Yellow
    Write-Host '  a) Data management > Copy into legal entity > New > Legal entities FastTab > Create, or' -ForegroundColor Yellow
    Write-Host '  b) Organization administration > Organizations > Legal entities > New.' -ForegroundColor Yellow
    Write-Host 'Then re-run this script: it finds the company and exits without changing anything.' -ForegroundColor Yellow
    Write-Host 'Payload that was attempted:'
    Write-Host $body
    exit 1
}

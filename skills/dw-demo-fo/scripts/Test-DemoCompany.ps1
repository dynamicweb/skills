<#
.SYNOPSIS
    READ-ONLY. Verify that a demo legal entity exists in D365 Finance and Operations and carries its own data.

.DESCRIPTION
    Step 5 of the demo-company recipe (references/demo-company.md). Every call is a GET; nothing is written.

    The load-bearing detail is the query shape: counts are taken with
        ?cross-company=true&$filter=dataAreaId eq '<Code>'
    Without cross-company=true, F&O answers for the DEFAULT company of the identity the token belongs to; in a
    shared sandbox that is usually the donor, and the numbers look plausible while describing another company.

    Checks:
      1. LegalEntities('<Code>')                      the company exists, and its name/country
      2. ReleasedProductsV2  $count in the company    released products
      3. CustomersV3         $count in the company    customers
      4. SalesOrderHeadersV2 $count in the company    sales orders
      5. BankAccounts and CustomerPaymentMethods      the payment chain a copy without Cash and bank
                                                      management leaves empty (see Repair-CopyGaps.ps1)
      6. NumberSequencesV2References (ScopeValue)     number sequences are assigned in the company
      7. -Entity <name> ...                           any extra entity sets to count in the company

    Entity set names vary by build. Anything that cannot be read is reported as "not readable on this build"
    rather than failing the run; take the authoritative set names from the environment's /data/$metadata.

    Exit code 1 when the company is missing or has no number sequences; 0 otherwise.

.PARAMETER Code
    Legal entity id (dataAreaId), 1-4 characters.

.PARAMETER Entity
    Extra entity sets to count inside the company.

.PARAMETER OutFile
    Optional JSON file for the results.

.PARAMETER EnvironmentUrl
    Else $env:FO_ENV_URL. Identity: -TenantId / -ClientId / -CachePath / -Token, else the FO_* environment
    variables (see Fo.Api.psm1).

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DemoCompany.ps1 -Code ABC

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DemoCompany.ps1 -Code ABC -Entity ItemSerialNumbers,SalesQuotationHeadersV2 -OutFile ./verify-ABC.json
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Code,
    [string[]]$Entity = @(),
    [string]$OutFile,
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

$results = [ordered]@{ environment = (Get-FoEnvironmentUrl); company = $Code; checks = [ordered]@{} }
$failures = 0

function Write-Count([string]$Label, [string]$EntitySet, [switch]$Required, [string]$CompanyField = 'dataAreaId') {
    $count = Get-FoCount -EntitySet $EntitySet -Company $Code -CompanyField $CompanyField
    $results.checks[$Label] = [ordered]@{ entitySet = $EntitySet; count = $count }
    if ($null -eq $count) { return $null }
    $verdict = if ($count -gt 0) { 'PASS' } elseif ($Required) { 'FAIL' } else { 'WARN' }
    $colour = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red' }[$verdict]
    Write-Host ("{0}  {1,-24} {2,8} rows in {3}" -f $verdict, $EntitySet, $count, $Code) -ForegroundColor $colour
    $count
}

# 1. The company exists
try {
    $le = Invoke-FoApi -Path "/data/LegalEntities('$Code')"
    $results.checks['legalEntity'] = [ordered]@{ exists = $true; name = $le.Name; country = $le.CompanyCountry; language = $le.LanguageId }
    Write-Host ("PASS  legal entity {0} exists: {1} ({2})" -f $Code, $le.Name, $le.CompanyCountry) -ForegroundColor Green
} catch {
    $results.checks['legalEntity'] = [ordered]@{ exists = $false; error = (Get-FoErrorText $_) }
    Write-Host ("FAIL  legal entity {0} not found: a sandbox refresh removes demo companies; re-run the seed" -f $Code) -ForegroundColor Red
    $failures++
}

# 2-4. Core volumes, scoped to the company
Write-Count releasedProducts ReleasedProductsV2 | Out-Null
Write-Count customers CustomersV3 | Out-Null
Write-Count salesOrders SalesOrderHeadersV2 | Out-Null

# 5. The payment chain a copy without Cash and bank management leaves empty
$banks = Write-Count bankAccounts BankAccounts
$pay = Write-Count customerPaymentMethods CustomerPaymentMethods
if ($banks -eq 0 -or $pay -eq 0) {
    Write-Host '      no bank accounts or payment methods: customers will fail to import; run Repair-CopyGaps.ps1' -ForegroundColor Yellow
}

# 6. Number sequence references scoped to the company. The entity is global: the company sits in ScopeValue,
#    not in dataAreaId (set name varies by build; unreadable is informational)
$seq = Write-Count numberSequences NumberSequencesV2References -Required -CompanyField ScopeValue
if ($seq -eq 0) {
    $failures++
    Write-Host '      no company number sequences: run the copy with "copy number sequences = Yes" (recipe step 2)' -ForegroundColor Red
}

# 7. Extra entity sets
foreach ($set in ($Entity | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) { Write-Count $set.Trim() $set.Trim() | Out-Null }

if ($OutFile) {
    $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    [System.IO.File]::WriteAllText($target, ($results | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    Write-Host "written: $target"
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host ("{0} check(s) failed for company {1}" -f $failures, $Code) -ForegroundColor Red
    exit 1
}
Write-Host ("company {0} verified. Counts are scoped with cross-company=true + dataAreaId; compare them with the DW side after an import run." -f $Code) -ForegroundColor Green
exit 0

<#
.SYNOPSIS
READ-ONLY. Probes standard BC collections in selected companies without printing tokens or rows.
.DESCRIPTION
Requires PowerShell 7.x. Owner: references/verification.md. Connectivity is not live
integration acceptance. Exits 1 if any selected company or collection cannot be read.
.PARAMETER CompanyIds
Required GUIDs, explicitly selected from the companies API.
.PARAMETER TenantId
Owning tenant GUID; defaults to BC_TENANT_ID.
.PARAMETER Environment
Exact environment name; defaults to BC_ENVIRONMENT.
.EXAMPLE
pwsh -NoProfile -File scripts/Test-BcConnection.ps1 -CompanyIds $selectedCompanyIds
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$CompanyIds,
    [string]$TenantId = $env:BC_TENANT_ID,
    [string]$Environment = $env:BC_ENVIRONMENT
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bc.Api.psm1') -Force -ErrorAction Stop
try {
    Initialize-BcConnection -TenantId $TenantId -Environment $Environment -CompanyIds $CompanyIds
    Assert-BcConnection
    $companies = @(Get-BcCompanies)
    foreach ($company in $CompanyIds) {
        if ($company -notin @($companies | ForEach-Object { $_.id })) { throw 'A selected company is not in the accessible companies list.' }
        foreach ($resource in @('items', 'customers', 'salesOrders', 'salesInvoices')) {
            $rows = @(Get-BcCollection -CompanyId $company -Resource $resource -SampleSize 1)
            [pscustomobject]@{ companyId = $company; resource = $resource; sampledRows = $rows.Count; completeCensus = $false }
        }
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}

<#
.SYNOPSIS
WRITES: Local BC inventory evidence only with -Apply; all ERP operations are read-only.
.DESCRIPTION
Requires PowerShell 7.x. Owner: references/access-surfaces.md. Captures accessible
companies and item/customer sample counts. Optional metadata is standard API v2 only.
No raw customer/item rows or tokens are saved. Default is a dry run with console output.
.PARAMETER CompanyIds
Optional selected company GUIDs. Without them only the company inventory is read.
.PARAMETER TenantId
Owning tenant GUID; defaults to BC_TENANT_ID.
.PARAMETER Environment
Exact environment name; defaults to BC_ENVIRONMENT.
.PARAMETER IncludeMetadata
Also retrieve the standard API metadata.
.PARAMETER OutDirectory
New directory for inventory.json and optional metadata.xml; required with -Apply.
.PARAMETER Apply
Explicit opt-in for local evidence writes.
.EXAMPLE
pwsh -NoProfile -File scripts/Get-BcInventory.ps1 -CompanyIds $selectedCompanyIds
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$CompanyIds = @(),
    [string]$TenantId = $env:BC_TENANT_ID,
    [string]$Environment = $env:BC_ENVIRONMENT,
    [switch]$IncludeMetadata,
    [string]$OutDirectory,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../dw-integration-bc/scripts/Bc.Api.psm1') -Force -ErrorAction Stop
try {
    if ($Apply -and ([string]::IsNullOrWhiteSpace($OutDirectory) -or (Test-Path -LiteralPath $OutDirectory))) {
        throw 'With -Apply, select a new -OutDirectory to preserve previous evidence.'
    }
    Initialize-BcConnection -TenantId $TenantId -Environment $Environment -CompanyIds $CompanyIds
    Assert-BcConnection
    $companies = @(Get-BcCompanies)
    $samples = @()
    $failed = $false
    foreach ($company in $CompanyIds) {
        if ($company -notin @($companies | ForEach-Object { $_.id })) { throw 'A selected company is absent from the accessible companies inventory.' }
        foreach ($resource in @('items', 'customers')) {
            try {
                $rows = @(Get-BcCollection -CompanyId $company -Resource $resource -SampleSize 1)
                $samples += @{ companyId = $company; resource = $resource; sampledRows = $rows.Count; state = 'observed'; completeCensus = $false }
            } catch {
                $failed = $true
                $samples += @{ companyId = $company; resource = $resource; state = 'unavailable'; error = $_.Exception.Message; completeCensus = $false }
            }
        }
    }
    $metadata = if ($IncludeMetadata) { Get-BcMetadata } else { $null }
    $report = @{
        schema = 1; tenantId = $TenantId; environment = $Environment
        observedAt = [datetime]::UtcNow.ToString('o')
        companies = @($companies | ForEach-Object { @{ id = $_.id; name = $_.name; displayName = $_.displayName } })
        samples = $samples; liveIntegrationAccepted = $false
    }
    $json = $report | ConvertTo-Json -Depth 8
    if ($Apply -and $PSCmdlet.ShouldProcess($OutDirectory, 'Write read-only BC inventory evidence')) {
        New-Item -ItemType Directory -Path $OutDirectory -ErrorAction Stop | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $OutDirectory 'inventory.json'), $json, [System.Text.UTF8Encoding]::new($false))
        if ($IncludeMetadata) {
            [System.IO.File]::WriteAllText((Join-Path $OutDirectory 'metadata.xml'), $metadata, [System.Text.UTF8Encoding]::new($false))
        }
    }
    Write-Output $json
    if ($failed) { exit 1 }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}

<#
.SYNOPSIS
READ-ONLY. Company-pinned BC API reads with bounded paging and retry.
.DESCRIPTION
Requires PowerShell 7.x. Owns references/endpoints-and-auth.md. Secrets come only
from BC_ACCESS_TOKEN or BC_CLIENT_SECRET in the environment and are never returned.
No redirect is followed; each next link must keep the original collection path.
.PARAMETER TenantId
Tenant GUID; falls back to BC_TENANT_ID in Initialize-BcConnection.
.PARAMETER Environment
Environment name; falls back to BC_ENVIRONMENT.
.PARAMETER CompanyIds
Company GUID allowlist; required for company-scoped reads.
.PARAMETER ClientId
Application GUID; falls back to BC_CLIENT_ID when an access token is absent.
.PARAMETER MaxPages
Maximum pages per collection, default 1000. Hitting the limit fails, never truncates silently.
.PARAMETER MaxRetries
Retries after 429 or 503, default 3, maximum 5.
.EXAMPLE
Import-Module ./Bc.Api.psm1
Initialize-BcConnection -CompanyIds $selectedCompanyIds
Get-BcCompanies
#>
#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Bc = $null

function Initialize-BcConnection {
    [CmdletBinding()]
    param(
        [string]$TenantId = $env:BC_TENANT_ID,
        [string]$Environment = $env:BC_ENVIRONMENT,
        [string[]]$CompanyIds = @(),
        [string]$ClientId = $env:BC_CLIENT_ID,
        [ValidateRange(1, 10000)][int]$MaxPages = 1000,
        [ValidateRange(0, 5)][int]$MaxRetries = 3
    )
    $script:Bc = $null
    $tenantGuid = [guid]::Empty
    if (-not [guid]::TryParse($TenantId, [ref]$tenantGuid) -or $tenantGuid -eq [guid]::Empty) {
        throw 'Set BC_TENANT_ID or -TenantId to the owning tenant GUID.'
    }
    if ([string]::IsNullOrWhiteSpace($Environment) -or $Environment -notmatch '^[A-Za-z0-9_-]+$') {
        throw 'Set BC_ENVIRONMENT or -Environment to the exact BC environment name.'
    }
    $allowed = @()
    foreach ($company in $CompanyIds) {
        $companyGuid = [guid]::Empty
        if (-not [guid]::TryParse($company, [ref]$companyGuid) -or $companyGuid -eq [guid]::Empty) {
            throw 'CompanyIds must contain non-empty company GUIDs from the companies API.'
        }
        $allowed += $companyGuid.ToString()
    }
    $bearer = $env:BC_ACCESS_TOKEN
    if ([string]::IsNullOrWhiteSpace($bearer)) {
        $clientGuid = [guid]::Empty
        if (-not [guid]::TryParse($ClientId, [ref]$clientGuid) -or [string]::IsNullOrWhiteSpace($env:BC_CLIENT_SECRET)) {
            throw 'Set BC_ACCESS_TOKEN, or BC_CLIENT_ID and BC_CLIENT_SECRET, in the process environment.'
        }
        try {
            $token = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantGuid/oauth2/v2.0/token" `
                -ContentType 'application/x-www-form-urlencoded' -Body @{
                    grant_type = 'client_credentials'; client_id = $clientGuid.ToString()
                    client_secret = $env:BC_CLIENT_SECRET
                    scope = 'https://api.businesscentral.dynamics.com/.default'
                } -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
            $bearer = $token.access_token
        } catch { throw 'BC token acquisition failed. Check tenant, client, secret and application consent; no token was logged.' }
    }
    if ([string]::IsNullOrWhiteSpace($bearer)) { throw 'BC authentication returned no access token.' }
    $script:Bc = @{
        Root = "https://api.businesscentral.dynamics.com/v2.0/$tenantGuid/$Environment/api/v2.0"
        Bearer = $bearer; Companies = @($allowed | Select-Object -Unique)
        MaxPages = $MaxPages; MaxRetries = $MaxRetries
    }
}

function Assert-BcConnection {
    [CmdletBinding()]
    param()
    if ($null -eq $script:Bc) { throw 'Run Initialize-BcConnection with the selected tenant, environment and company GUIDs first.' }
}

function Invoke-BcRead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri, [Parameter(Mandatory)][string]$ExpectedPath)
    Assert-BcConnection
    $root = [uri]$script:Bc.Root
    if ($Uri.Scheme -ne 'https' -or $Uri.Authority -ne $root.Authority -or $Uri.UserInfo -or
        $Uri.Fragment -or $Uri.AbsolutePath -cne $ExpectedPath) {
        throw 'BC URL escaped the pinned tenant, environment or collection. Check the server next link.'
    }
    for ($attempt = 0; $attempt -le $script:Bc.MaxRetries; $attempt++) {
        try {
            $response = Invoke-WebRequest -Method Get -Uri $Uri.AbsoluteUri -Headers @{
                Authorization = "Bearer $($script:Bc.Bearer)"; Accept = 'application/json, application/xml'
            } -MaximumRedirection 0 -SkipHttpErrorCheck -TimeoutSec 30 -ErrorAction Stop
        } catch { throw 'BC read failed before a response. Check connectivity and authentication; request details were suppressed.' }
        $status = [int]$response.StatusCode
        if ($status -ge 200 -and $status -lt 300) { return $response.Content }
        if ($status -in @(429, 503) -and $attempt -lt $script:Bc.MaxRetries) {
            $delay = 0
            if (-not [int]::TryParse([string]$response.Headers['Retry-After'], [ref]$delay)) {
                $delay = [int][math]::Pow(2, $attempt)
            }
            Start-Sleep -Seconds ([math]::Clamp($delay, 0, 60))
            continue
        }
        throw "BC read returned HTTP $status. Check company scope, permissions, published source or retry budget."
    }
}

function Get-BcPagedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri, [ValidateRange(0, 10000)][int]$SampleSize = 0)
    $expectedPath = $Uri.AbsolutePath
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($page = 0; $page -lt $script:Bc.MaxPages; $page++) {
        if (-not $seen.Add($Uri.AbsoluteUri)) { throw 'BC repeated a next link; fix paging before trusting the census.' }
        $body = Invoke-BcRead -Uri $Uri -ExpectedPath $expectedPath
        try { $data = ConvertFrom-Json -InputObject $body -AsHashtable -ErrorAction Stop }
        catch { throw 'BC did not return valid JSON for the collection.' }
        if ($data -isnot [System.Collections.IDictionary] -or -not $data.Contains('value') -or
            $data['value'] -isnot [array]) { throw 'BC collection is missing its value array.' }
        foreach ($row in $data['value']) {
            $rows.Add($row)
            if ($SampleSize -gt 0 -and $rows.Count -ge $SampleSize) { return $rows.ToArray() }
        }
        if (-not $data.Contains('@odata.nextLink') -or -not $data['@odata.nextLink']) { return $rows.ToArray() }
        $Uri = [uri]::new($Uri, [string]$data['@odata.nextLink'])
    }
    throw 'BC paging exceeded MaxPages; raise the explicit limit or narrow the source. Results are incomplete.'
}

function Get-BcCompanies {
    [CmdletBinding()]
    param()
    Assert-BcConnection
    Get-BcPagedRows -Uri ($script:Bc.Root + '/companies')
}

function Get-BcCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$CompanyId,
        [Parameter(Mandatory)][ValidateSet('items', 'customers', 'salesOrders', 'salesInvoices')][string]$Resource,
        [ValidateRange(0, 10000)][int]$SampleSize = 0
    )
    Assert-BcConnection
    if ($CompanyId.ToString() -notin $script:Bc.Companies) { throw 'Company is outside the selected BC company allowlist.' }
    $uri = $script:Bc.Root + '/companies(' + $CompanyId.ToString() + ')/' + $Resource
    if ($SampleSize -gt 0) { $uri += '?$top=' + $SampleSize }
    Get-BcPagedRows -Uri $uri -SampleSize $SampleSize
}

function Get-BcMetadata {
    [CmdletBinding()]
    param()
    Assert-BcConnection
    $uri = [uri]($script:Bc.Root + '/$metadata')
    Invoke-BcRead -Uri $uri -ExpectedPath $uri.AbsolutePath
}

Export-ModuleMember -Function Initialize-BcConnection, Assert-BcConnection, Get-BcCompanies, Get-BcCollection, Get-BcMetadata

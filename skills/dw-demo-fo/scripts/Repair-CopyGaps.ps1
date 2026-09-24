<#
.SYNOPSIS
    WRITES: missing bank and payment configuration rows into ONE target company (dry run unless -Apply).

.DESCRIPTION
    Closes the configuration gaps that "Copy into legal entity" leaves when the chosen templates do not
    include Cash and bank management. Without bank groups and bank accounts in the target, customer and
    vendor payment methods fail to import, and most customers fail after them because they reference a
    payment method. The copy also skips company-scoped values of custom-list financial dimensions (for
    example ItemGroup). This script copies exactly those rows from the donor company, over OData:

      1. bank groups used by the donor's bank accounts          BankGroups
      2. bank accounts, with the donor's id prefix removed      BankAccounts
      3. bank transaction types                                 BankTransactionTypes
      4. company-scoped financial dimension values              FinancialDimensionValues (per -Dimension)
      5. customer payment methods, bank account remapped        CustomerPaymentMethods
      6. vendor payment methods, bank account remapped          VendorPaymentMethods

    Idempotent: every entity is read in the target first and a row is created only when its key is absent;
    nothing is updated or deleted. Re-run the customer (and vendor) import of the copy afterwards.

    Owning reference: dw-demo-fo/references/demo-company.md ("Measured gaps after a copy").

    Traps encoded here:
      - Empty-string fields and LastFileDate are stripped from every payload: an empty string trips field
        validators (a QR-IBAN check on bank accounts, for one) that an absent field does not.
      - Read-only and address-derived fields of bank groups and bank accounts are dropped; F&O rebuilds them.
      - Bank transaction types must exist before payment methods that reference them.
      - Company-scoped dimension values are keyed by LegalEntityId (lower case in the filter), not by
        dataAreaId, and are not part of any copy template.
      - Writes only inside -Target. The donor is read, never written.

.PARAMETER Target
    Company (dataAreaId) that receives the rows. 1-4 characters.

.PARAMETER Donor
    Company the rows are copied from: the donor of the copy, or the golden company.

.PARAMETER BankIdPrefix
    Prefix to strip from the donor's bank account ids and statement names, for example 'USMF ' when the
    donor names its accounts 'USMF OPER'. Accounts without the prefix keep their id.

.PARAMETER BankIdMap
    Explicit id mapping, 'DONORID=TARGETID' pairs (comma-separated or repeated). Wins over -BankIdPrefix.
    When given, only the mapped accounts are copied.

.PARAMETER Dimension
    Custom-list financial dimensions whose company-scoped values are copied. Default ItemGroup.

.PARAMETER Apply
    Write. Without it the script is a dry run that prints what it would create.

.PARAMETER LogPath
    Optional file for the run log (one line per row: exists, WHATIF, CREATED or FAILED).

.PARAMETER EnvironmentUrl
    Else $env:FO_ENV_URL. Identity: -TenantId / -ClientId / -CachePath / -Token, else the FO_* environment
    variables (see Fo.Api.psm1).

.EXAMPLE
    pwsh -NoProfile -File scripts/Repair-CopyGaps.ps1 -Target ABC -Donor USMF -BankIdPrefix 'USMF '

.EXAMPLE
    pwsh -NoProfile -File scripts/Repair-CopyGaps.ps1 -Target ABC -Donor USMF -BankIdPrefix 'USMF ' -Apply -LogPath ./repair-ABC.log
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Target,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,4}$')][string]$Donor,
    [string]$BankIdPrefix,
    [string[]]$BankIdMap = @(),
    [string[]]$Dimension = @('ItemGroup'),
    [switch]$Apply,
    [string]$LogPath,
    [string]$EnvironmentUrl = $env:FO_ENV_URL,
    [string]$TenantId = $env:FO_TENANT_ID,
    [string]$ClientId = $env:FO_CLIENT_ID,
    [string]$CachePath = $env:FO_TOKEN_CACHE,
    [string]$Token = $env:FO_TOKEN
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fo.Api.psm1') -Force -ErrorAction Stop
Initialize-FoConnection -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -CachePath $CachePath -Token $Token

$Target = $Target.ToUpperInvariant(); $Donor = $Donor.ToUpperInvariant()
if ($Target -eq $Donor) { Write-Error 'Target and Donor are the same company.'; exit 1 }
$dryRun = -not $Apply

$map = @{}
foreach ($pair in ($BankIdMap | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    $kv = $pair -split '=', 2
    if ($kv.Count -ne 2) { Write-Error "BankIdMap entry '$pair' is not DONORID=TARGETID."; exit 1 }
    $map[$kv[0].Trim()] = $kv[1].Trim()
}
function Get-TargetBankId([string]$DonorId) {
    if ($map.Count) { return $map[$DonorId] }
    if ($BankIdPrefix -and $DonorId.StartsWith($BankIdPrefix)) { return $DonorId.Substring($BankIdPrefix.Length).Trim() }
    $DonorId
}

$log = [System.Collections.Generic.List[string]]::new()
$failed = 0
function Say([string]$Message) { $log.Add($Message); Write-Output $Message }

function Get-Payload($Row, [string[]]$Drop = @()) {
    $h = [ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        if ($p.Name -like '@odata*' -or $p.Name -in $Drop -or $p.Name -eq 'LastFileDate') { continue }
        if ($p.Value -is [string] -and $p.Value -eq '') { continue }
        $h[$p.Name] = $p.Value
    }
    $h
}

function New-Row([string]$EntitySet, $Payload, [string]$Label) {
    if ($dryRun -or -not $PSCmdlet.ShouldProcess("$EntitySet $Label in $Target", 'POST')) {
        Say "WHATIF  create $EntitySet $Label"; return
    }
    try {
        Invoke-FoApi -Path "/data/$EntitySet" -Method Post -Body $Payload | Out-Null
        Say "CREATED $EntitySet $Label"
    } catch {
        $script:failed++
        Say "FAILED  $EntitySet $Label :: $(Get-FoErrorText $_)"
    }
}

$addressFields = @('AddressLocationId', 'FullPrimaryAddress', 'AddressValidFrom', 'AddressValidTo')

# 1. Bank groups used by the donor's bank accounts
$donorBanks = Get-FoCompanyRows -EntitySet BankAccounts -Company $Donor
$have = @((Get-FoCompanyRows -EntitySet BankGroups -Company $Target) | ForEach-Object BankGroupId)
$usedGroups = @($donorBanks | ForEach-Object BankGroupId)
foreach ($g in (Get-FoCompanyRows -EntitySet BankGroups -Company $Donor) | Where-Object { $_.BankGroupId -in $usedGroups }) {
    if ($g.BankGroupId -in $have) { Say "exists  BankGroups $($g.BankGroupId)"; continue }
    $b = Get-Payload $g $addressFields; $b.dataAreaId = $Target
    New-Row BankGroups $b $g.BankGroupId
}

# 2. Bank accounts, renamed without the donor prefix
$have = @((Get-FoCompanyRows -EntitySet BankAccounts -Company $Target) | ForEach-Object BankAccountId)
$prefixPattern = if ($BankIdPrefix) { '^' + [regex]::Escape($BankIdPrefix.Trim()) + '\s*' } else { $null }
foreach ($a in $donorBanks) {
    $id = Get-TargetBankId $a.BankAccountId
    if (-not $id) { continue }
    if ($id -in $have) { Say "exists  BankAccounts $id"; continue }
    $b = Get-Payload $a ($addressFields + @('PositivePayStartDate', 'NonSufficientFundsChargesGroupId'))
    $b.dataAreaId = $Target; $b.BankAccountId = $id; $b.BanksIdentificationOfCompany = $id
    if ($prefixPattern -and $a.CompanyStatementName) { $b.CompanyStatementName = ($a.CompanyStatementName -replace $prefixPattern, '').Trim() }
    New-Row BankAccounts $b $id
}

# 3. Bank transaction types (payment methods reference them)
$have = @((Get-FoCompanyRows -EntitySet BankTransactionTypes -Company $Target) | ForEach-Object TransactionTypeId)
foreach ($t in (Get-FoCompanyRows -EntitySet BankTransactionTypes -Company $Donor)) {
    if ($t.TransactionTypeId -in $have) { Say "exists  BankTransactionTypes $($t.TransactionTypeId)"; continue }
    $b = Get-Payload $t; $b.dataAreaId = $Target
    New-Row BankTransactionTypes $b $t.TransactionTypeId
}

# 4. Company-scoped financial dimension values (custom list per legal entity)
foreach ($dim in $Dimension) {
    $q = "/data/FinancialDimensionValues?`$filter=FinancialDimension eq '$dim' and LegalEntityId eq '{0}'"
    $haveDim = @((Invoke-FoApi -Path ($q -f $Target.ToLowerInvariant())).value | ForEach-Object DimensionValue)
    foreach ($v in (Invoke-FoApi -Path ($q -f $Donor.ToLowerInvariant())).value) {
        if ($v.DimensionValue -in $haveDim) { Say "exists  FinancialDimensionValues $dim/$($v.DimensionValue)"; continue }
        $b = Get-Payload $v; $b.LegalEntityId = $Target
        New-Row FinancialDimensionValues $b "$dim/$($v.DimensionValue)"
    }
}

# 5-6. Customer and vendor payment methods, bank account remapped
foreach ($set in 'CustomerPaymentMethods', 'VendorPaymentMethods') {
    try {
        $have = @((Get-FoCompanyRows -EntitySet $set -Company $Target) | ForEach-Object Name)
        $donorRows = Get-FoCompanyRows -EntitySet $set -Company $Donor
    } catch {
        Say "skip    ${set}: $(Get-FoErrorText $_)"; continue
    }
    foreach ($p in $donorRows) {
        if ($p.Name -in $have) { Say "exists  $set $($p.Name)"; continue }
        $b = Get-Payload $p; $b.dataAreaId = $Target
        if ($p.AccountType -eq 'Bank' -and $p.PaymentAccountDisplayValue) {
            $mapped = Get-TargetBankId $p.PaymentAccountDisplayValue
            if ($mapped) { $b.PaymentAccountDisplayValue = $mapped }
        }
        New-Row $set $b $p.Name
    }
}

if ($LogPath) {
    $out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    [System.IO.File]::WriteAllLines($out, $log, [System.Text.UTF8Encoding]::new($false))
}
if ($dryRun) { Write-Host 'dry run: nothing written. Re-run with -Apply to create the rows marked WHATIF.' }
if ($failed -gt 0) { Write-Host "$failed row(s) failed; the log line carries the F&O message."; exit 1 }
exit 0

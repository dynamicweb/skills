<#
.SYNOPSIS
    READ-ONLY. Asserts an impersonation grant in the right direction, and
    reports whether the Users index still owes a rebuild before the grant is
    observable on any rendered surface.

.DESCRIPTION
    One grant is one AccessUserSecondaryRelation row, and the two ids are NOT
    interchangeable:

      AccessUserSecondaryRelationUserId          = the IMPERSONATOR (the CSR)
      AccessUserSecondaryRelationSecondaryUserId = the CUSTOMER being impersonated

    The symptom of the wrong direction is quiet: the impersonation bar is
    empty, and the customer's admin profile shows the CSR under "Users that can
    impersonate this user". Nothing errors. This script therefore checks BOTH
    directions and names which one it found.

    THE GRANT IS NOT OBSERVABLE UNTIL THE USERS INDEX IS REBUILT. The shipped
    user-index extender writes the relation onto the user documents as
    CanImpersonate and CanBeImpersonatedBy, already expanded through group
    inheritance, and the rendered surface reads the index, not the table. So
    after any write to the relation the debt is: flush UserService, then run a
    FULL build of the Users index, then re-read the index document — and assert
    on the document of the identity whose grant was REMOVED, not only on the
    surface of the identity whose grant was kept. This script reports the index
    state; it does not build (that is Build-DwProductIndex.ps1's job) and it
    does not write.

    Mind the two repository names: this relation is indexed under both `Users`
    and `Secondary users`, each with `Users.index`, and the status verbs split
    their parameter names — IndexByRepositoryAndName and
    IndexBuildersByRepositoryAndIndexName take Repository + IndexName, while
    IndexInstancesByRepositoryAndIndex takes RepositoryName + IndexName; the
    wrong one answers 400 "Unable to load query parameters".

    SQL is LOCAL INSTALLS ONLY. On a hosted install, read the grant with
    get_impersonatable_users / GroupsICanImpersonateByGroupId instead and pass
    -SkipRowRead.

    Owning reference: dw-data-access/references/recipes-users.md
    ("Rebuild the Users index after an impersonation write"); the verbs, the
    Ids-are-strings trap on UserImpersonateDelete and the row-count assert are
    in dw-users-permissions (`user-group-operations.md` §17c).

.PARAMETER ImpersonatorUserId
    The CSR's AccessUser id — the identity doing the impersonating.

.PARAMETER CustomerUserId
    The customer's AccessUser id — the identity being impersonated.

.PARAMETER SkipRowRead
    Skip the SQL row read (hosted installs, which have no SQL surface).

.PARAMETER SkipIndexRead
    Skip the index freshness read.

.PARAMETER ConnectionString
    Local SQL connection; else $env:DW_SQL_CONNECTION.

.PARAMETER BaseUrl / ApiToken / SolutionPath
    Connection for the index read; else the DW_* env vars, else
    launchSettings.json discovery.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwImpersonationGrant.ps1 -ImpersonatorUserId 1270 -CustomerUserId 1292

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwImpersonationGrant.ps1 -ImpersonatorUserId 1270 -CustomerUserId 1292 -SkipRowRead
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$ImpersonatorUserId,
    [Parameter(Mandatory = $true)][int]$CustomerUserId,
    [switch]$SkipRowRead,
    [switch]$SkipIndexRead,
    [string]$ConnectionString,
    [string]$BaseUrl,
    [string]$ApiToken,
    [string]$SolutionPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop
Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -SolutionPath $SolutionPath | Out-Null
Assert-DwConnection | Out-Null

$failed = $false

if (-not $SkipRowRead) {
    Write-Host 'AccessUserSecondaryRelation (local installs only):'
    $forward = Get-DwSqlScalar -ConnectionString $ConnectionString -Sql (
        'SELECT COUNT(*) FROM AccessUserSecondaryRelation ' +
        "WHERE AccessUserSecondaryRelationUserId = $ImpersonatorUserId " +
        "AND AccessUserSecondaryRelationSecondaryUserId = $CustomerUserId")
    $reverse = Get-DwSqlScalar -ConnectionString $ConnectionString -Sql (
        'SELECT COUNT(*) FROM AccessUserSecondaryRelation ' +
        "WHERE AccessUserSecondaryRelationUserId = $CustomerUserId " +
        "AND AccessUserSecondaryRelationSecondaryUserId = $ImpersonatorUserId")

    if ([int]$forward -gt 0) {
        Write-Host "  GRANTED: user $ImpersonatorUserId (impersonator) may impersonate $CustomerUserId (customer)."
    }
    elseif ([int]$reverse -gt 0) {
        Write-Host "  WRONG DIRECTION: the row reads $CustomerUserId -> $ImpersonatorUserId."
        Write-Host '  UserId is the impersonator and SecondaryUserId is the customer. The visible symptom is an'
        Write-Host '  empty impersonation bar plus the CSR appearing under "Users that can impersonate this user"'
        Write-Host "  on the customer's profile. Swap the two ids."
        $failed = $true
    }
    else {
        Write-Host "  NO GRANT: no row in either direction between $ImpersonatorUserId and $CustomerUserId."
        $failed = $true
    }
}
else {
    Write-Host 'Row read SKIPPED. On a hosted install, read the grant with get_impersonatable_users or'
    Write-Host 'GroupsICanImpersonateByGroupId, whose modelIdentifier strings are also what'
    Write-Host 'UserImpersonateDelete Ids takes (STRINGS, inherited from ListItemsCommandBase).'
}

if (-not $SkipIndexRead) {
    Write-Host ''
    Write-Host 'Users index (the surface actually reads the index, not the table):'
    $found = $false
    foreach ($repository in 'Users', 'Secondary users') {
        try {
            # Repository + IndexName on this verb. IndexInstancesByRepositoryAndIndex
            # takes RepositoryName instead and answers 400 for these names.
            $status = (Invoke-DwApi (
                    'IndexStatusByRepositoryAndIndexName?Repository=' +
                    [uri]::EscapeDataString($repository) + '&IndexName=Users.index')).model
        }
        catch {
            try {
                $all = (Invoke-DwApi 'IndexStatusesAll').model
                $status = @($all) | Where-Object {
                    $_.repository -eq $repository -and $_.indexName -eq 'Users.index'
                } | Select-Object -First 1
            }
            catch { $status = $null }
        }
        if (-not $status) { continue }
        $found = $true
        Write-Host ("  {0,-16} state {1,-8} lastRun {2}" -f $repository, $status.state, $status.lastRun)
    }
    if (-not $found) {
        Write-Host '  No Users.index status under either `Users` or `Secondary users`.'
    }
    Write-Host ''
    Write-Host '  After ANY write to the impersonation relation the debt is: flush'
    Write-Host '  Dynamicweb.Security.UserManagement.UserService, run a FULL build of the Users index'
    Write-Host '  (BuildIndex needs BuildName; without it, 400 {"BuildName":["The value is required."]}),'
    Write-Host '  then re-read the index document. A lastRun older than the write means the rendered'
    Write-Host '  surface is still answering from the pre-write documents.'
    Write-Host '  Assert on the index document of the identity whose grant was REMOVED, not only on the'
    Write-Host '  surface of the identity whose grant was kept.'
}

if ($failed) { exit 1 }
exit 0

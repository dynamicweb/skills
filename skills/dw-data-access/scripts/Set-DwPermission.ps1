<#
.SYNOPSIS
    WRITES: one entity grant through PermissionSave, and reads it back through
    PermissionsByIdentifier. Dry run by default; -Apply writes.

.DESCRIPTION
    `PermissionSave` at /Admin/Api/PermissionSave is the write verb for every
    entity grant — Section, Page, GridRow, Paragraph, UserGroup and the rest of
    the PermissionEntity registry. It is an upsert, safe to re-run, and it
    self-invalidates the permission cache, which a raw SQL INSERT does not.

    Four shapes this script carries so a retyped call cannot get them wrong:

      - THE BODY IS NESTED UNDER Model. PermissionSaveCommand is a
        CommandBase<PermissionDataModel>, so a flat body of the inner
        properties is rejected before it executes —
        400 {"Command.Model":["Command.Model cannot be null"]} — leaving the
        table untouched and saying nothing about what the model is.
      - KEY IS A STRING ON EVERY ENTITY TYPE, so a numeric page id is quoted.
      - THE COMPOSITE IDENTIFIER is <Key>|$|<Name>|$|<SubName>|$|<OwnerId>,
        four parts joined with the literal separator |$|. An empty SubName
        yields the doubled separator ("97|$|Page|$||$|9"). It is what the
        response modelIdentifier carries and what PermissionDelete's
        PermissionIdentifier takes.
      - THE READ RETURNS AN EMPTY data ARRAY WHEN SubName IS PASSED AS "".
        Omit SubName entirely when reading; the write side still takes
        SubName:"" normally. The read also returns the three implicit user
        ROLES (Anonymous, AuthenticatedFrontend, Administrator) with
        isUserRolePermission true.

    The sparse PermissionLevel table stays in the owning reference on purpose,
    so an in-product reader can still recognise a denial at level 1. This
    script accepts the level by NAME and prints the number beside it, because
    level 1 is None, not the bottom of a ladder — the trap that inverts a gate.

    Owning reference: dw-data-access/references/recipes-users.md
    ("PermissionSave — the write verb for every entity grant"); the layer model
    and the UnifiedPermission row shape are in dw-users-permissions.

.PARAMETER Key
    The entity key, as a string. A page id, a paragraph id, a user-group id,
    or for a backend area the AreaBase subclass name without the Area suffix
    (Content, Ecommerce, Products, Users, Settings, ...).

.PARAMETER Name
    The entity type: Page, GridRow, Paragraph, Section, UserGroup, ...

.PARAMETER OwnerId
    The user-group id (or role string) the grant belongs to.

.PARAMETER Level
    None, Read, Edit, Create, Delete or All. Bit-flag values, higher includes
    lower. None is a DENIAL, not the bottom of a ladder.

.PARAMETER SubName
    Entity sub-name; empty on most entities, 'User' on a UserGroup grant.

.PARAMETER IsUserRolePermission
    Set only for a grant on one of the implicit roles.

.PARAMETER NoVerify
    Skip the read-back. The read-back is the point; skip it only when the
    identity you are writing for is a role the read does not project.

.PARAMETER Apply
    Write. Without it the exact body is printed and nothing is sent.

.PARAMETER BaseUrl / ApiToken / SolutionPath
    Connection; else the DW_* env vars, else launchSettings.json discovery.

.EXAMPLE
    pwsh -NoProfile -File scripts/Set-DwPermission.ps1 -Key 97 -Name Page -OwnerId 9 -Level Read

.EXAMPLE
    pwsh -NoProfile -File scripts/Set-DwPermission.ps1 -Key Content -Name Section -OwnerId 42 -Level Edit -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$OwnerId,
    [Parameter(Mandatory = $true)][ValidateSet('None', 'Read', 'Edit', 'Create', 'Delete', 'All')][string]$Level,
    [string]$SubName = '',
    [switch]$IsUserRolePermission,
    [switch]$NoVerify,
    [switch]$Apply,
    [string]$BaseUrl,
    [string]$ApiToken,
    [string]$SolutionPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -Force -ErrorAction Stop
Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -SolutionPath $SolutionPath | Out-Null
Assert-DwConnection | Out-Null

# PermissionLevel is a sparse bit-flag enum; higher includes lower
# (Edit = Read | 1<<4 = 4 | 16 = 20). The values live in the owning reference
# too, so an in-product reader can recognise a level read out of a solution.
$levels = [ordered]@{ None = 1; Read = 4; Edit = 20; Create = 84; Delete = 340; All = 1364 }
$levelValue = $levels[$Level]

# The composite identifier: four parts, literal |$| separator, empty SubName
# yielding the doubled separator.
$identifier = @($Key, $Name, $SubName, $OwnerId) -join '|$|'

$body = @{
    Model = @{
        Key                  = [string]$Key
        Name                 = $Name
        SubName              = $SubName
        OwnerId              = [string]$OwnerId
        Level                = $levelValue
        IsUserRolePermission = [bool]$IsUserRolePermission
        IsExplicitPermission = $true
    }
}

Write-Host "POST /Admin/Api/PermissionSave"
Write-Host ($body | ConvertTo-Json -Depth 5 -Compress)
Write-Host ''
Write-Host "Level:      $Level = $levelValue$(if ($Level -eq 'None') { '  (a DENIAL, not the bottom of a ladder)' })"
Write-Host "Identifier: $identifier"

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN — nothing written. Re-run with -Apply.'
    exit 0
}
if (-not $PSCmdlet.ShouldProcess($identifier, "grant $Level ($levelValue)")) { exit 0 }

$result = Invoke-DwApi 'PermissionSave' -Body $body
Write-Host ''
Write-Host "PermissionSave: status $($result.status), modelIdentifier $($result.model.modelIdentifier ?? $result.modelIdentifier)"

if ($NoVerify) { exit 0 }

# Read back with SubName OMITTED: passing SubName="" returns an empty data
# array and would read as "the write did not land".
$rows = Invoke-DwApi ("PermissionsByIdentifier?Key=$([uri]::EscapeDataString($Key))&Name=$([uri]::EscapeDataString($Name))")
$hit = @($rows.data) | Where-Object { [string]$_.ownerId -eq [string]$OwnerId } | Select-Object -First 1
if (-not $hit) {
    Write-Host ''
    Write-Host "FAILED: PermissionsByIdentifier does not return a row for owner $OwnerId on $Name/$Key."
    Write-Host 'PermissionSave answered, so read the response above before assuming the read is at fault.'
    exit 1
}
Write-Host "Verified: owner $OwnerId holds level $($hit.level) on $Name/$Key."
Write-Host ''
Write-Host 'This write self-invalidates the permission cache and owes no flush. A raw SQL INSERT on'
Write-Host 'UnifiedPermission does not, and owes DefaultCapabilityService, DefaultCapabilitySetService'
Write-Host 'and PermissionService — see recipes-users.md.'
exit 0

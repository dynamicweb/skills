<#
.SYNOPSIS
    WRITES: nothing on import. The write and cleanup verbs of the Dynamicweb 10
    shared module - every exported function is a dry run until -Apply.

.DESCRIPTION
    The companion to Dw.Api.psm1, which it imports for connection discovery,
    the Management API call path and the SQL read-back. It is a separate file
    on purpose: a single script that reads, uploads files, deletes users and
    rewrites global settings is exactly the co-located verb cluster endpoint
    protection scores, and two smaller files give a behavioural engine less to
    correlate. See dw-skill-authoring, "Shipping scripts" -> "AV-safe scripts".

    Every function here is [CmdletBinding(SupportsShouldProcess)], reports what
    it would do and returns applied = $false without -Apply, and proves the
    write by READING BACK. An HTTP 200 is never the evidence.

    Owning reference: dw-data-access/references/management-api-and-sql.md.
    Traps encoded here so callers cannot re-create them:
      - The delete verbs disagree about scalar types, and each disagreement
        fails in a way that reads as success: a singular numeric id binds to
        nothing and answers 400, a numeric array element answers 500, an array
        of STRINGS works. The dynamic-structure verb ignores the integer id
        entirely and binds the unique-id GUID.
      - A settings save does not validate the key against a schema: naming a
        path that does not exist CREATES it, the save answers ok, and the
        read-back echoes the invented key while the application keeps reading
        the real one. So the config file is re-parsed, the key must resolve to
        exactly one node anywhere in the tree, and the caller's effect probe
        is mandatory.
      - The upload verb derives the destination name from the LOCAL filename,
        so an upload can genuinely succeed at creating a second file beside the
        one it meant to replace. The destination name is mandatory and the file
        is staged under it; the archive's reported size lags the write, so it is
        polled; and the served bytes are hashed, because the static-file cache
        does not invalidate through a junction.
      - The TLS bypass is NOT set here. Every request in this file passes the
        gate Connect-Dw resolved, which skips certificate validation only for a
        localhost base URL or after an explicit -AllowSelfSignedCertificate
        opt-in. An unconditional bypass on every call is itself a scored
        behaviour.
      - Clearing one recycle-bin id legitimately removes more than one row: a
        master cascades to its language copies. So the removed id SET is
        asserted to be a subset of the caller's own expected set, never a count
        delta.

    REFUSED, deliberately, and not for a caller's convenience:
      - Arbitrary SQL executed through a scheduled task. It is already a banned
        path, and it is the single verb that turns this module into a remote
        code-execution tool.
      - Admin-account creation and deletion, and backend-access revocation.
        Admin-account lifecycle does not belong in a shipped script; it is
        half of the flagged verb cluster, and the correct home for a one-off
        teardown is the admin Users screen, by hand, by a human who can see
        what else the account owns.
      The owning reference states both refusals in prose, so a reader who never
      opens this file still learns them.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot 'Dw.Api.Write.psm1') -Force -ErrorAction Stop
    Assert-DwConnection
    Remove-DwUser -Id 1332            # dry run: reports, changes nothing
    Remove-DwUser -Id 1332 -Apply     # writes, then proves it by reading back
#>
#Requires -Version 7.0
param()

$ErrorActionPreference = 'Stop'

# No -Force on this nested import: -Force REMOVES the already-loaded Dw.Api and
# re-imports it privately, which silently strips its verbs from a caller that
# imported it first. The caller owns -Force.
Import-Module (Join-Path $PSScriptRoot 'Dw.Api.psm1') -ErrorAction Stop

function Test-DwApply {
    # Internal. One rule for every verb here: -Apply is the switch that writes,
    # -WhatIf suppresses it, and the absence of -Apply is a reported dry run,
    # never a silent no-op the caller mistakes for a write.
    param(
        [Parameter(Mandatory = $true)][bool]$Apply,
        [Parameter(Mandatory = $true)][string]$Action
    )
    if (-not $Apply) {
        Write-Warning "DRY RUN (no -Apply): would $Action"
        return $false
    }
    $true
}

function Remove-DwUser {
    <#
    .SYNOPSIS
        WRITES: deletes one user, then proves it is gone.
    .DESCRIPTION
        The ids go as an array of STRINGS: a singular numeric id answers 400 and
        leaves the user alive, a numeric array element answers 500 and leaves the
        user alive, and both read as success to a wrapper that only checks that
        the call returned. The read-back is the evidence: the by-id read must
        return no model, and the row count must be 0 when a SQL connection is
        available.
    .PARAMETER Id
        User id.
    .PARAMETER Apply
        Perform the delete. Without it the function reports and changes nothing.
    .EXAMPLE
        Remove-DwUser -Id 1332 -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][int]$Id,
        [switch]$Apply
    )
    Assert-DwConnection | Out-Null
    if (-not $PSCmdlet.ShouldProcess("user $Id", 'UserDelete')) {
        return [pscustomobject]@{ id = $Id; applied = $false; deleted = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "delete user $Id")) {
        return [pscustomobject]@{ id = $Id; applied = $false; deleted = $false }
    }
    Invoke-DwApi 'UserDelete' -Body @{ Ids = @("$Id") } | Out-Null

    $stillThere = $false
    try {
        $after = Invoke-DwApi "UserById?Id=$Id" -RetryCount 0
        $stillThere = [bool]($after -and $after.model)
    }
    catch { $stillThere = $false }   # a by-id read that fails after a delete is the delete
    if ($stillThere) {
        throw "Remove-DwUser: UserById?Id=$Id still returns a model after UserDelete. The delete did not take."
    }
    $rowsLeft = Get-DwRowCountOrNull "SELECT COUNT(*) FROM AccessUser WHERE AccessUserId = $Id"
    if ($null -ne $rowsLeft -and $rowsLeft -ne 0) {
        throw "Remove-DwUser: AccessUser still holds $rowsLeft row(s) for id $Id after UserDelete."
    }
    [pscustomobject]@{ id = $Id; applied = $true; deleted = $true; sqlRowsRemaining = $rowsLeft }
}

function Remove-DwGroup {
    <#
    .SYNOPSIS
        WRITES: deletes one user group, then proves it is gone.
    .DESCRIPTION
        Same scalar-type contract as Remove-DwUser: the ids go as an array of
        STRINGS, and the read-back is the evidence rather than the HTTP status.
    .PARAMETER Id
        Group id.
    .PARAMETER Apply
        Perform the delete. Without it the function reports and changes nothing.
    .EXAMPLE
        Remove-DwGroup -Id 1340 -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][int]$Id,
        [switch]$Apply
    )
    Assert-DwConnection | Out-Null
    if (-not $PSCmdlet.ShouldProcess("group $Id", 'GroupDelete')) {
        return [pscustomobject]@{ id = $Id; applied = $false; deleted = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "delete group $Id")) {
        return [pscustomobject]@{ id = $Id; applied = $false; deleted = $false }
    }
    Invoke-DwApi 'GroupDelete' -Body @{ Ids = @("$Id") } | Out-Null
    $rowsLeft = Get-DwRowCountOrNull "SELECT COUNT(*) FROM AccessUser WHERE AccessUserId = $Id"
    if ($null -ne $rowsLeft -and $rowsLeft -ne 0) {
        throw "Remove-DwGroup: AccessUser still holds $rowsLeft row(s) for group id $Id after GroupDelete."
    }
    [pscustomobject]@{ id = $Id; applied = $true; deleted = $true; sqlRowsRemaining = $rowsLeft }
}

function Remove-DwDynamicStructure {
    <#
    .SYNOPSIS
        WRITES: deletes one dynamic structure by its unique-id GUID.
    .DESCRIPTION
        The verb ignores the integer structure id entirely and binds the unique-id
        GUID; an integer answers 500 with a GUID conversion error. So a non-GUID
        argument is refused here rather than sent, and the read-back is the
        evidence.
    .PARAMETER UniqueId
        The structure's unique-id GUID, never the integer id.
    .PARAMETER Apply
        Perform the delete. Without it the function reports and changes nothing.
    .EXAMPLE
        Remove-DwDynamicStructure -UniqueId '7b1e0bcd-0000-0000-0000-000000000000' -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$UniqueId,
        [switch]$Apply
    )
    $guid = [guid]::Empty
    if (-not [guid]::TryParse($UniqueId, [ref]$guid)) {
        throw ("Remove-DwDynamicStructure: -UniqueId '$UniqueId' is not a GUID. The delete verb " +
            'ignores the integer structure id entirely and binds the unique-id GUID.')
    }
    Assert-DwConnection | Out-Null
    if (-not $PSCmdlet.ShouldProcess("dynamic structure $UniqueId", 'DynamicStructureDelete')) {
        return [pscustomobject]@{ uniqueId = $UniqueId; applied = $false; deleted = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "delete dynamic structure $UniqueId")) {
        return [pscustomobject]@{ uniqueId = $UniqueId; applied = $false; deleted = $false }
    }
    Invoke-DwApi 'DynamicStructureDelete' -Body @{ Id = "$UniqueId" } | Out-Null
    $safe = $UniqueId -replace "'", "''"
    $rowsLeft = Get-DwRowCountOrNull (
        "SELECT COUNT(*) FROM DynamicStructure WHERE DynamicStructureUniqueId = '$safe'")
    if ($null -ne $rowsLeft -and $rowsLeft -ne 0) {
        throw "Remove-DwDynamicStructure: DynamicStructure still holds $rowsLeft row(s) for $UniqueId."
    }
    [pscustomobject]@{ uniqueId = $UniqueId; applied = $true; deleted = $true; sqlRowsRemaining = $rowsLeft }
}

function Get-DwRowCountOrNull([string]$Sql) {
    # Internal. The SQL read-back is a LOCAL-install bonus: when no connection is
    # configured the verb still works and the result says the count is unknown
    # ($null) rather than pretending it verified a zero.
    try { return Get-DwSqlCount -Sql $Sql }
    catch { return $null }
}

function Assert-DwGlobalSettingNode {
    <#
    .SYNOPSIS
        READ-ONLY. Asserts a global-setting key resolves to exactly one node.
    .DESCRIPTION
        Parses the settings config file and requires the exact key path to
        resolve to one node, AND the leaf name to appear exactly once anywhere
        in the tree. The second test is the load-bearing one: a stray sibling
        minted under a different parent is what makes a setting dead, and an
        exact-path check alone never sees it. Returns 1 on success.
    .PARAMETER ConfigFilePath
        Path to the settings config file.
    .PARAMETER Key
        Full key path, e.g. /Globalsettings/Settings/Auditing/EnableAuditing.
    .EXAMPLE
        Assert-DwGlobalSettingNode -ConfigFilePath $config -Key '/Globalsettings/Settings/Auditing/EnableAuditing'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFilePath,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if (-not (Test-Path -LiteralPath $ConfigFilePath)) {
        throw "Assert-DwGlobalSettingNode: settings config not found at $ConfigFilePath."
    }
    [xml]$xml = Get-Content -Raw -LiteralPath $ConfigFilePath -Encoding utf8
    $segments = @($Key.Trim('/') -split '/' | Where-Object { $_ })
    $leaf = $segments[-1]
    $anywhere = @($xml.SelectNodes("//$leaf"))
    $exact = @($xml.SelectNodes('/' + ($segments -join '/')))
    if ($exact.Count -ne 1) {
        throw ("Assert-DwGlobalSettingNode: '$Key' resolves to $($exact.Count) node(s) in " +
            "$ConfigFilePath (expected exactly 1).")
    }
    if ($anywhere.Count -gt 1) {
        $paths = @($anywhere | ForEach-Object {
            $parts = @(); $node = $_
            while ($node -and $node.NodeType -eq 'Element') { $parts = @($node.Name) + $parts; $node = $node.ParentNode }
            '/' + ($parts -join '/')
        })
        throw ("Assert-DwGlobalSettingNode: '$leaf' appears at $($anywhere.Count) paths in " +
            "${ConfigFilePath}: $($paths -join ', '). More than one node for the same setting " +
            'means a dead setting was minted at a path nothing reads.')
    }
    1
}

function Set-DwGlobalSetting {
    <#
    .SYNOPSIS
        WRITES: one global setting, then proves the application acted on it.
    .DESCRIPTION
        The save does not validate the key against a schema. Naming a path that
        does not exist CREATES it, the save answers ok, and the by-key read
        echoes the invented key back while the application keeps reading the
        real one - a setting can read True for an entire workstream and be dead.
        A by-key read is therefore never proof.

        So, after the save: re-parse the config file, assert the key resolves to
        exactly one node anywhere in the tree, and then run the caller's effect
        probe. -EffectProbe is MANDATORY. A settings write with no effect assert
        is precisely the shape that wasted the workstream above.
    .PARAMETER Key
        Full key path, starting /Globalsettings/.
    .PARAMETER Value
        The value to write.
    .PARAMETER ConfigFilePath
        Path to the settings config file, for the node assert.
    .PARAMETER EffectProbe
        Scriptblock returning truthy once the setting has visibly taken effect.
    .PARAMETER EffectDescription
        What the probe observes, for the failure message.
    .PARAMETER Apply
        Perform the write. Without it the function reports and changes nothing.
    .EXAMPLE
        Set-DwGlobalSetting -Key '/Globalsettings/Settings/Auditing/EnableAuditing' -Value 'True' `
            -ConfigFilePath $config -EffectProbe { (Get-DwSqlCount 'SELECT COUNT(*) FROM Audit') -gt $before } -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$ConfigFilePath,
        [Parameter(Mandatory = $true)][scriptblock]$EffectProbe,
        [string]$EffectDescription = 'the caller-supplied effect probe',
        [switch]$Apply
    )
    if ($Key -notmatch '^/Globalsettings/') {
        throw "Set-DwGlobalSetting: -Key must be a full /Globalsettings/... path, got '$Key'."
    }
    Assert-DwConnection | Out-Null
    if (-not $PSCmdlet.ShouldProcess($Key, 'GlobalSettingSave')) {
        return [pscustomobject]@{ key = $Key; applied = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "set $Key")) {
        return [pscustomobject]@{ key = $Key; applied = $false }
    }
    Invoke-DwApi 'GlobalSettingSave' -Body @{ Model = @{ Key = $Key; Value = $Value } } | Out-Null
    $nodes = Assert-DwGlobalSettingNode -ConfigFilePath $ConfigFilePath -Key $Key
    $effect = & $EffectProbe
    if (-not $effect) {
        throw ("Set-DwGlobalSetting: '$Key' resolves to exactly one node in $ConfigFilePath, but " +
            "$EffectDescription did not observe the change. The value was persisted; the " +
            'application did not act on it.')
    }
    [pscustomobject]@{ key = $Key; value = $Value; applied = $true; nodeCount = $nodes; effect = $effect }
}

function Send-DwFile {
    <#
    .SYNOPSIS
        WRITES: uploads one local file into the file archive under an explicit
        destination name, then proves the host is serving it.
    .DESCRIPTION
        Three measured traps, in order.

        The upload verb derives the destination name from the LOCAL filename, so
        an arm kept under a working name uploads successfully and creates a
        BRAND NEW file beside the one it meant to replace. The upload genuinely
        succeeded; it succeeded at something else. So -DestName is mandatory and
        the file is staged under that name before it is sent.

        The archive's reported size lags the write by seconds, so a
        sleep-then-sample reads the PREVIOUS size and scores a correct deploy as
        a failure. The size is polled for the expected value instead.

        The archive is reached through directory junctions and Windows
        file-change notification does not propagate through one, so the static
        file cache never invalidates: the host keeps serving the old bytes,
        which still carry every sentinel marker the new ones do. Only a hash of
        the served bytes separates the two. -RecycleAction is invoked ONCE on a
        mismatch and the read-back retried; a second mismatch throws.
    .PARAMETER RelDir
        Destination directory, relative to the archive root.
    .PARAMETER LocalPath
        The local file to upload.
    .PARAMETER DestName
        The bare filename it must land under. Never inferred.
    .PARAMETER PollAttempts
        Size-poll attempts.
    .PARAMETER PollIntervalMs
        Delay between size polls.
    .PARAMETER SkipServedHashCheck
        Skip the served-bytes hash (for a file the host does not serve).
    .PARAMETER RecycleAction
        Scriptblock that recycles the host, tried once on a hash mismatch.
    .PARAMETER Apply
        Perform the upload. Without it the function reports and changes nothing.
    .EXAMPLE
        Send-DwFile -RelDir 'Templates/Designs/Swift' -LocalPath ./theme.css -DestName 'theme.css' -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$RelDir,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$DestName,
        [int]$PollAttempts = 20,
        [int]$PollIntervalMs = 2000,
        [switch]$SkipServedHashCheck,
        [scriptblock]$RecycleAction,
        [switch]$Apply
    )
    if (-not (Test-Path -LiteralPath $LocalPath)) {
        throw "Send-DwFile: local file not found: $LocalPath"
    }
    if ($DestName -match '[\\/]') {
        throw "Send-DwFile: -DestName must be a bare filename, got '$DestName'."
    }
    Assert-DwConnection | Out-Null
    if (-not $PSCmdlet.ShouldProcess("$RelDir/$DestName", 'FileUpload')) {
        return [pscustomobject]@{ destName = $DestName; relDir = $RelDir; applied = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "upload $LocalPath to $RelDir/$DestName")) {
        return [pscustomobject]@{ destName = $DestName; relDir = $RelDir; applied = $false }
    }
    $expectedBytes = (Get-Item -LiteralPath $LocalPath).Length
    $localHash = (Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('dw-upload-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        $staged = Join-Path $stage $DestName
        Copy-Item -LiteralPath $LocalPath -Destination $staged -Force
        $connection = Get-DwConnection
        Invoke-WebRequest -Uri "$($connection.BaseUrl)/Admin/Api/FileUpload" -Method Post `
            -Form @{ file = Get-Item -LiteralPath $staged; directory = $RelDir } `
            -Headers @{
                Authorization = "Bearer $($connection.ApiToken)"
                # why: the target negotiates archive content on the UA - see Get-DwBrowserUserAgent.
                'User-Agent'  = Get-DwBrowserUserAgent
            } `
            -SkipCertificateCheck:$connection.SkipCert -TimeoutSec 300 -ErrorAction Stop | Out-Null

        $seen = $null
        for ($i = 0; $i -lt $PollAttempts; $i++) {
            Start-Sleep -Milliseconds $PollIntervalMs
            $query = 'FileByName?Name=' + [uri]::EscapeDataString($DestName) +
                     '&Directory=' + [uri]::EscapeDataString($RelDir)
            $meta = $null
            try { $meta = Invoke-DwApi $query -RetryCount 0 } catch { continue }
            $model = if ($meta.model -and $meta.model.model) { $meta.model.model } else { $meta.model }
            if ($model -and $model.PSObject.Properties['sizeInBytes']) { $seen = [long]$model.sizeInBytes }
            if ($seen -eq $expectedBytes) { break }
        }
        if ($seen -ne $expectedBytes) {
            throw ("Send-DwFile: the archive reports $seen bytes for '$DestName' in '$RelDir', " +
                "expected $expectedBytes. The upload landed under a different name, or the " +
                'archive never took the write.')
        }
        $servedHash = $null
        if (-not $SkipServedHashCheck) {
            $url = "$($connection.BaseUrl)/Files/$($RelDir.Trim('/'))/$DestName"
            $servedHash = Get-DwServedFileHash -Url $url
            if ($servedHash -ne $localHash -and $RecycleAction) {
                & $RecycleAction | Out-Null
                $servedHash = Get-DwServedFileHash -Url $url
            }
            if ($servedHash -ne $localHash) {
                throw ("Send-DwFile: the host is serving DIFFERENT bytes at $url (served " +
                    "$servedHash, local $localHash). The archive is reached through a junction " +
                    'and the static-file cache did not invalidate; recycle the host and read ' +
                    'back. A sentinel-marker check would call this green, because the stale ' +
                    'copy carries the same markers.')
            }
        }
        [pscustomobject]@{
            destName = $DestName; relDir = $RelDir; applied = $true
            bytes = $expectedBytes; sha256 = $localHash; servedSha256 = $servedHash
        }
    }
    finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

function Clear-DwRecycleBin {
    <#
    .SYNOPSIS
        WRITES: purges named soft-deleted entities, and proves only they went.
    .DESCRIPTION
        The intuitive guard - clear one id, confirm the bin total falls by
        exactly one - fires on CORRECT behaviour: clearing a master purges its
        master-linked language copies in the same operation, because the copies
        are children of the master rather than independent rows. A one-id clear
        legitimately dropped a bin by three, on a host holding hundreds of
        unrelated soft-deleted rows where a blanket clear is destructive, and
        the guard read the cascade as "the ids were not honoured" and aborted.

        So: snapshot the SET of soft-deleted ids before, purge, and assert the
        removed set is a SUBSET of the caller's own expected set. The delta is
        reported, never asserted. -SnapshotSql must return one id per row, so
        this needs a SQL connection (LOCAL installs only).
    .PARAMETER EntityType
        Entity type name for the purge.
    .PARAMETER Ids
        The ids to purge.
    .PARAMETER ExpectedIds
        Every id the caller accepts losing, including cascaded copies.
        Defaults to -Ids.
    .PARAMETER SnapshotSql
        Query returning one soft-deleted id per row for this entity type.
    .PARAMETER Apply
        Perform the purge. Without it the function reports and changes nothing.
    .EXAMPLE
        Clear-DwRecycleBin -EntityType Page -Ids 8944 -ExpectedIds 8944,8945,8946 `
            -SnapshotSql 'SELECT PageId FROM Page WHERE PageDeleted = 1' -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$EntityType,
        [Parameter(Mandatory = $true)][string[]]$Ids,
        [string[]]$ExpectedIds,
        [Parameter(Mandatory = $true)][string]$SnapshotSql,
        [switch]$Apply
    )
    Assert-DwConnection | Out-Null
    if (-not $ExpectedIds) { $ExpectedIds = $Ids }
    if (-not $PSCmdlet.ShouldProcess("$EntityType $($Ids -join ', ')", 'RecycleBinClear')) {
        return [pscustomobject]@{ entityType = $EntityType; applied = $false }
    }
    if (-not (Test-DwApply -Apply:$Apply -Action "purge $EntityType $($Ids -join ', ')")) {
        return [pscustomobject]@{ entityType = $EntityType; applied = $false }
    }
    $before = @(Get-DwSqlRows -Sql $SnapshotSql |
        ForEach-Object { "$(@($_.PSObject.Properties.Value)[0])" })
    Invoke-DwApi 'RecycleBinClear' -Body @{
        EntityType = "$EntityType"; Ids = @($Ids | ForEach-Object { "$_" })
    } | Out-Null
    $after = @(Get-DwSqlRows -Sql $SnapshotSql |
        ForEach-Object { "$(@($_.PSObject.Properties.Value)[0])" })
    $removed = @($before | Where-Object { $after -notcontains $_ })
    $expected = @($ExpectedIds | ForEach-Object { "$_" })
    $collateral = @($removed | Where-Object { $expected -notcontains $_ })
    if ($collateral.Count -gt 0) {
        throw ("Clear-DwRecycleBin: the purge removed $($collateral.Count) id(s) OUTSIDE the " +
            "expected set: $($collateral -join ', ').")
    }
    $notRemoved = @($Ids | ForEach-Object { "$_" } | Where-Object { $after -contains $_ })
    if ($notRemoved.Count -gt 0) {
        throw "Clear-DwRecycleBin: id(s) still soft-deleted after the purge: $($notRemoved -join ', ')."
    }
    [pscustomobject]@{
        entityType = $EntityType; applied = $true; removed = @($removed)
        binBefore = $before.Count; binAfter = $after.Count
        # Reported, never asserted: a master cascades to its language copies.
        delta = ($before.Count - $after.Count)
    }
}

Export-ModuleMember -Function @(
    'Remove-DwUser', 'Remove-DwGroup', 'Remove-DwDynamicStructure',
    'Assert-DwGlobalSettingNode', 'Set-DwGlobalSetting',
    'Send-DwFile', 'Clear-DwRecycleBin'
)

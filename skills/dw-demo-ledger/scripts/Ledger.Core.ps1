<#
.SYNOPSIS
READ-ONLY. Schema, lock, selection and assertion helpers; definitions only.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Rejects path escapes, digest drift, missing handlers and empty proof. No target mutation.
.EXAMPLE
. ./Ledger.Core.ps1
#>
#Requires -Version 7.0
function Read-LedgerJson {
    param([string]$Path, [string]$Schema)
    # Contract failures are IO.InvalidDataException: their text names the cause and holds no credential, so the runner may print it.
    try { $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop } catch { throw [IO.InvalidDataException]::new("Cannot read '$Path'.") }
    if ($Schema) {
        $valid = $false; $detail = ''
        try { $valid = Test-Json -Json $text -SchemaFile $Schema -ErrorAction Stop } catch { $detail = ' ' + $_.Exception.Message }
        if (-not $valid) { throw [IO.InvalidDataException]::new("'$Path' does not match $(Split-Path -Leaf $Schema).$detail") }
    }
    try { return ConvertFrom-Json -InputObject $text -AsHashtable } catch { throw [IO.InvalidDataException]::new("'$Path' is not valid JSON.") }
}
function Resolve-LedgerPath {
    param([string]$Root, [string]$Relative)
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Expected a relative ledger path.' }
    $parent = [IO.Path]::GetFullPath($Root).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath((Join-Path $parent $Relative))
    if (-not $path.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)) { throw 'Ledger path escapes its root.' }
    return $path
}
function Get-LedgerDigest {
    # -Force: the runner reads a hidden file like any other, so it is hashed. -NormaliseLineEndings is diagnostic only.
    param([string]$Root, [switch]$NormaliseLineEndings)
    $lines = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
        $rel = [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')
        $bytes = [IO.File]::ReadAllBytes($_.FullName)
        if ($NormaliseLineEndings) { $bytes = [Text.Encoding]::Latin1.GetBytes([Text.Encoding]::Latin1.GetString($bytes).Replace("`r`n","`n")) }
        $rel + ':' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    })
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    return 'sha256:' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
function Get-LedgerDigestFault {
    # The text for a digest mismatch: both digests, and whether converted line endings explain it.
    param([string]$Root, [string]$LockDigest, [string]$Digest)
    $text = "Snapshot digest mismatch: lock.digest is $LockDigest, the snapshot beside the manifest is $Digest."
    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)
    $crlf = @($files | Where-Object { [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains("`r`n") }).Count
    if ($crlf -gt 0 -and (Get-LedgerDigest $Root -NormaliseLineEndings) -eq $LockDigest) {
        return "$text $crlf of $($files.Count) snapshot files have CRLF line endings, and with LF endings this snapshot has the locked digest: the checkout or copy converted line endings (core.autocrlf on a commit without .gitattributes, or a copy made outside git). Check the locked commit out again with core.autocrlf=false."
    }
    if ($crlf -gt 0) { $text += " $crlf of $($files.Count) snapshot files have CRLF line endings, which changes the digest, but line endings alone do not explain this difference." }
    return "$text The snapshot changed after the lock was written, or the lock names another revision; Update-DwLedgerLock.ps1 reports what changed and writes a new lock."
}
function Read-LedgerSnapshot {
    # Every function and every check a function lists, keyed by id. A contract failure names the id and the path.
    param([string]$Root, [string]$Assets)
    $functions = @{}; $checks = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'functions') -Filter '*.json' -File) {
        $area = Read-LedgerJson $file.FullName (Join-Path $Assets 'ledger.schema.json')
        foreach ($f in $area.functions) {
            if ($functions.ContainsKey($f.id)) { throw [IO.InvalidDataException]::new("Duplicate function id '$($f.id)' in the snapshot.") }
            $functions[$f.id] = $f
            foreach ($path in $f.checks) {
                $check = Read-LedgerJson (Resolve-LedgerPath $Root $path) (Join-Path $Assets 'check.schema.json')
                if ($check.functionId -ne $f.id -or $checks.ContainsKey($check.id)) { throw [IO.InvalidDataException]::new("Check '$($check.id)' at '$path' is owned by another function than '$($f.id)', or its id is used twice.") }
                $checks[$check.id] = $check
            }
        }
    }
    return @{functions=$functions; checks=$checks}
}
function Test-LedgerAssertion {
    param($Assertion, $Observation)
    if (-not $Observation.complete) { return 'UNVERIFIED' }
    if ($Assertion.kind -eq 'offenders') {
        if ($null -eq $Observation.offenders) { return 'ERROR' }
        # A claim that needs subjects is not proven by zero offenders over zero subjects.
        if ($Assertion.ContainsKey('minimumSubjects')) {
            if ($null -eq $Observation.scanned -or $Observation.scanned -is [string]) { return 'ERROR' }
            if ($Observation.scanned -lt $Assertion.minimumSubjects) { return 'FAIL' }
        }
        return $(if (@($Observation.offenders).Count -eq 0) {'PASS'} else {'FAIL'})
    }
    if ($Assertion.kind -eq 'scalar') {
        if ($null -eq $Observation.value -or $Observation.value -is [string]) { return 'ERROR' }
        $ok = switch ($Assertion.op) {
            'eq' {$Observation.value -eq $Assertion.value}
            'ge' {$Observation.value -ge $Assertion.value}
            'le' {$Observation.value -le $Assertion.value}
            default {throw 'Unknown scalar comparator.'}
        }
        return $(if ($ok) {'PASS'} else {'FAIL'})
    }
    if ($Assertion.kind -in @('attributes','families','widget-queries')) {
        if ($null -eq $Observation.scanned -or $null -eq $Observation.offenders) { return 'ERROR' }
        $minimum = if ($Assertion.ContainsKey('minimumSubjects')) {$Assertion.minimumSubjects} else {1}
        return $(if ($Observation.scanned -ge $minimum -and @($Observation.offenders).Count -eq 0) {'PASS'} else {'FAIL'})
    }
    return 'ERROR'
}
function Select-LedgerBinding {
    param($Check, $Capabilities, [string[]]$Surfaces = @('mcp','admin-api','dwapi','file','sql'), [string[]]$Exclude = @())
    foreach ($surface in $Surfaces) {
        foreach ($binding in @($Check.bindings | Where-Object {$_.surface -eq $surface -and $_.status -eq 'implemented' -and $_.id -notin $Exclude})) {
            $available = switch ($surface) {
                'mcp' { $Capabilities.mcp.available -and $binding.operation -in $Capabilities.mcp.tools -and @($binding.requiredTools | Where-Object {$_ -and $_ -notin $Capabilities.mcp.tools}).Count -eq 0 }
                'admin-api' { $Capabilities.adminApi.authenticated -and $binding.operation -in $Capabilities.adminApi.queries }
                'dwapi' { $Capabilities.dwapi.available }
                'file' { $Capabilities.file.available -and (-not $binding.localOnly -or $Capabilities.file.local) }
                'sql' { $Capabilities.sql.available -and $binding.localOnly }
            }
            if ($available) { return $binding }
        }
    }
    return $null
}
function Get-LedgerVerdict {
    param([object[]]$Checks)
    if (@($Checks).Count -eq 0) { return 'UNVERIFIED' }
    foreach ($state in @('ERROR','FAIL','UNSUPPORTED','DISABLED','UNVERIFIED')) {
        if (@($Checks | Where-Object {$_.result -eq $state}).Count -gt 0) { return $state }
    }
    if (@($Checks | Where-Object {$_.result -notin @('PASS','NOT-APPLICABLE')}).Count) {return 'ERROR'}
    # A ruling observes nothing: a run of NOT-APPLICABLE rows alone has evaluated no requirement.
    if (@($Checks | Where-Object {$_.result -eq 'PASS'}).Count -eq 0) { return 'UNVERIFIED' }
    return 'PASS'
}
function Get-LedgerRulingFault {
    # A ruling is evidence, so its types are checked. Returns the fault, or $null for a usable ruling.
    param($Ruling, $Function)
    if ($Ruling -isnot [Collections.IDictionary] -or $Ruling.applies -isnot [bool]) { return 'applies must be a boolean.' }
    if ($Ruling.applies) { return $null }
    if ($Ruling.rule -isnot [string] -or @($Function.notApplicable | Where-Object {$_.id -eq $Ruling.rule}).Count -ne 1) { return 'rule must name one allowed ground of the function.' }
    if ($Ruling.evidence -isnot [string] -or [string]::IsNullOrWhiteSpace($Ruling.evidence)) { return 'evidence must be text.' }
    return $null
}
function Compare-LedgerVersion {
    # -1, 0 or 1 for two package versions (three or four numbers, optional prerelease label); $null when either is not one.
    param([string]$Left, [string]$Right)
    $parsed = @(foreach ($text in @($Left,$Right)) {
        if ($text -match '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?$') {
            $label = if ($Matches[5]) { '-' + $Matches[5] } else { '' }
            @{core=[semver]"$($Matches[1]).$($Matches[2]).$($Matches[3])$label"; fourth=[int]$(if ($Matches[4]) { $Matches[4] } else { 0 })}
        }
    })
    if ($parsed.Count -ne 2) { return $null }
    $order = $parsed[0].core.CompareTo($parsed[1].core)
    if ($order -eq 0) { $order = $parsed[0].fourth.CompareTo($parsed[1].fourth) }
    return [Math]::Sign($order)
}
function Resolve-LedgerFact {
    # The discovered fact a requirement names. A lookup only: nothing is inferred from the requirement's wording.
    param($Requirement, $Facts)
    $id = [string]$Requirement.id
    $keys = switch ($Requirement.kind) {
        'app' { @(('app:' + $id), $id) }
        'flag' { if ($id.StartsWith('/Globalsettings/')) { @(('setting:' + $id), $id) } else { @($id) } }
        default { @($id) }
    }
    foreach ($key in $keys) { if ($Facts.ContainsKey($key)) { return @{known=$true; value=$Facts[$key]} } }
    if ($Requirement.kind -eq 'flag' -and $id -cmatch '^[A-Za-z][A-Za-z0-9]*$') {
        # A flag may be named by its class alone, while the fact key is the full type name.
        $hits = @($Facts.Keys | Where-Object { "$_" -notmatch ':' -and "$_".EndsWith('.' + $id, [StringComparison]::Ordinal) })
        if ($hits.Count -eq 1) { return @{known=$true; value=$Facts[$hits[0]]} }
        if ($hits.Count -gt 1) { return @{known=$false; reason="Required flag '$id' matches $($hits.Count) feature types on this target; the requirement must name the full type."} }
    }
    return @{known=$false; reason="Required $($Requirement.kind) '$id' is not established on this target."}
}
function Get-LedgerRequirementState {
    # $null when the requirement is established; otherwise the row state and its reason. No type is coerced.
    param($Requirement, $Facts)
    $expected = $Requirement.expected; $kind = $Requirement.kind; $id = $Requirement.id
    if ($kind -in @('flag','capability') -and $expected -isnot [bool]) { return @{result='ERROR'; reason='Requirement expectation must be a boolean.'} }
    $fact = Resolve-LedgerFact $Requirement $Facts
    if (-not $fact.known) { return @{result='UNVERIFIED'; reason=$fact.reason} }
    $value = $fact.value
    if ($kind -eq 'app' -and $expected -is [Collections.IDictionary]) {
        # {min}: the installed version is this one or a later one.
        if ($expected.Count -ne 1 -or $expected['min'] -isnot [string]) { return @{result='ERROR'; reason="App requirement '$id' must expect true, a version or {min}."} }
        if ($value -isnot [string]) { return @{result='UNVERIFIED'; reason="Required app '$id' is present, but its version is not established."} }
        $order = Compare-LedgerVersion $value $expected['min']
        if ($null -eq $order) { return @{result='UNVERIFIED'; reason="Required app '$id' has a version that cannot be compared with the minimum."} }
        if ($order -ge 0) { return $null }
        return @{result='UNSUPPORTED'; reason="Required app '$id' is installed below the minimum version."}
    }
    $met = ($value -is [bool] -and $expected -is [bool] -and $value -eq $expected) -or
        ($value -is [string] -and $expected -is [string] -and $value -ceq $expected) -or
        ($kind -eq 'app' -and $expected -is [bool] -and $expected -and $value -is [string] -and $value)
    if ($met) { return $null }
    if ($kind -eq 'flag') { return @{result='DISABLED'; reason="Required flag '$id' does not have the required state."} }
    return @{result='UNSUPPORTED'; reason="Required $kind '$id' is not satisfied on this target."}
}
function New-LedgerRow {
    param($Check)
    return [ordered]@{id=$Check.id; functionId=$Check.functionId; result='UNVERIFIED'; surface=$null; binding=$null; level=$Check.intent.level; proves=$Check.intent.proves; reason='No equivalent implemented binding is available.'}
}

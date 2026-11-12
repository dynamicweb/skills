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
    param([string]$Root)
    $lines = @(Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
        $rel = [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rel + ':' + $hash
    })
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    return 'sha256:' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
function Test-LedgerAssertion {
    param($Assertion, $Observation)
    if (-not $Observation.complete) { return 'UNVERIFIED' }
    if ($Assertion.kind -eq 'offenders') {
        if ($null -eq $Observation.offenders) { return 'ERROR' }
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
function Get-LedgerRequirementState {
    # $null when the requirement is established; otherwise the row state and its reason. No type is coerced.
    param($Requirement, $Facts)
    $expected = $Requirement.expected
    if ($Requirement.kind -in @('flag','capability') -and $expected -isnot [bool]) { return @{result='ERROR'; reason='Requirement expectation must be a boolean.'} }
    if (-not $Facts.ContainsKey($Requirement.id)) { return @{result='UNVERIFIED'; reason='Required capability fact is unknown.'} }
    $fact = $Facts[$Requirement.id]
    $met = ($fact -is [bool] -and $expected -is [bool] -and $fact -eq $expected) -or ($fact -is [string] -and $expected -is [string] -and $fact -ceq $expected)
    if ($met) { return $null }
    return @{result=$(if ($Requirement.kind -eq 'flag') {'DISABLED'} else {'UNSUPPORTED'}); reason='Required capability not satisfied.'}
}
function New-LedgerRow {
    param($Check)
    return [ordered]@{id=$Check.id; functionId=$Check.functionId; result='UNVERIFIED'; surface=$null; binding=$null; level=$Check.intent.level; proves=$Check.intent.proves; reason='No equivalent implemented binding is available.'}
}

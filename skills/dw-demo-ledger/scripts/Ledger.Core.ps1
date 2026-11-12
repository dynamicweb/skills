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
    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ($Schema -and -not (Test-Json -Json $text -SchemaFile $Schema -ErrorAction Stop)) { throw 'JSON contract invalid.' }
    return ConvertFrom-Json -InputObject $text -AsHashtable
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
    return 'PASS'
}
function New-LedgerRow {
    param($Check)
    return [ordered]@{id=$Check.id; functionId=$Check.functionId; result='UNVERIFIED'; surface=$null; binding=$null; level=$Check.intent.level; proves=$Check.intent.proves; reason='No equivalent implemented binding is available.'}
}
